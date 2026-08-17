package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.AgentsExecutionEnvironment;
import org.apache.flink.agents.api.agents.AgentExecutionOptions;
import org.apache.flink.agents.api.configuration.AgentConfigOptions;
import org.apache.flink.agents.api.logger.LoggerType;
import org.apache.flink.agents.api.resource.ResourceDescriptor;
import org.apache.flink.agents.api.resource.ResourceName;
import org.apache.flink.agents.api.resource.ResourceType;
import org.apache.flink.api.common.state.ListState;
import org.apache.flink.api.common.state.ListStateDescriptor;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.runtime.state.VoidNamespace;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.streaming.api.operators.BoundedOneInput;
import org.apache.flink.streaming.api.operators.KeyedProcessOperator;
import org.apache.flink.streaming.api.operators.TimestampedCollector;
import org.apache.flink.util.Collector;

import java.io.FileWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The windowed-routing experiment: a batcher stage groups requests (count OR time trigger), ONE
 * judge call routes the whole batch, and each request then flows down the NORMAL chat path against
 * its selected model — select-not-delegate composed with a Flink window. This shape is impossible
 * to express in a per-request proxy/library router.
 *
 * <p>Usage: {@code java -cp <jar> org.apache.flink.agents.eval.BatchedEvalJob --run-id x
 * --requests-file workloads/requests.jsonl [--batch-size 16] [--batch-timeout-ms 2000]
 * [--small qwen2.5:0.5b] [--big qwen3:1.7b] [--judge-model qwen3:1.7b] [--runs-dir runs]}
 */
public final class BatchedEvalJob {

    public static void main(String[] args) throws Exception {
        Map<String, String> opt = new HashMap<>();
        for (int i = 0; i < args.length - 1; i += 2) {
            opt.put(args[i].replaceFirst("^--", ""), args[i + 1]);
        }
        String runId = opt.get("run-id");
        int batchSize = Integer.parseInt(opt.getOrDefault("batch-size", "16"));
        long batchTimeoutMs = Long.parseLong(opt.getOrDefault("batch-timeout-ms", "2000"));
        String small = opt.getOrDefault("small", "qwen2.5:0.5b");
        String big = opt.getOrDefault("big", "qwen3:1.7b");
        String judgeModel = opt.getOrDefault("judge-model", "qwen3:1.7b");
        String judgeUrl = opt.getOrDefault("judge-url", "http://localhost:11434");
        Path runDir = Path.of(opt.getOrDefault("runs-dir", "runs")).resolve(runId).toAbsolutePath();
        Files.createDirectories(runDir.resolve("eventlog"));
        String batchLog = runDir.resolve("batches.jsonl").toString();

        StreamExecutionEnvironment env =
                StreamExecutionEnvironment.getExecutionEnvironment(new Configuration());
        env.setParallelism(Integer.parseInt(opt.getOrDefault("parallelism", "1")));
        AgentsExecutionEnvironment agentsEnv =
                AgentsExecutionEnvironment.getExecutionEnvironment(env);
        agentsEnv.getConfig().set(AgentExecutionOptions.NUM_ASYNC_THREADS, 2);
        // Local Ollama occasionally stalls a request under bursty load (batch flushes release
        // 20+ chats at once); retries keep one stall from killing the run — same guard as EvalJob.
        agentsEnv
                .getConfig()
                .set(
                        AgentExecutionOptions.ERROR_HANDLING_STRATEGY,
                        org.apache.flink.agents.api.agents.Agent.ErrorHandlingStrategy.RETRY);
        agentsEnv.getConfig().set(AgentExecutionOptions.MAX_RETRIES, 2);
        agentsEnv.getConfig().set(AgentExecutionOptions.RETRY_WAIT_INTERVAL, 2);
        agentsEnv.getConfig().set(AgentConfigOptions.EVENT_LOGGER_TYPE, LoggerType.FILE);
        agentsEnv.getConfig().set(AgentConfigOptions.BASE_LOG_DIR, runDir.resolve("eventlog").toString());

        agentsEnv.addResource(
                "ollamaConnection",
                ResourceType.CHAT_MODEL_CONNECTION,
                ResourceDescriptor.Builder.newBuilder(ResourceName.ChatModel.OLLAMA_CONNECTION)
                        .addInitialArgument("requestTimeout", 240)
                        .addInitialArgument("endpoint", judgeUrl)
                        .build());
        agentsEnv
                .addResource("small", ResourceType.CHAT_MODEL, ollama(small))
                .addResource("big", ResourceType.CHAT_MODEL, ollama(big));

        List<String> prompts = new ArrayList<>();
        com.fasterxml.jackson.databind.ObjectMapper m = new com.fasterxml.jackson.databind.ObjectMapper();
        for (String line : Files.readAllLines(Path.of(opt.get("requests-file")))) {
            if (!line.isBlank()) {
                prompts.add(m.readTree(line).path("prompt").asText());
            }
        }

        // --emit-rate <records/s>: rate-limited generator source for arrival-rate sweeps.
        double emitRate = Double.parseDouble(opt.getOrDefault("emit-rate", "0"));
        final List<String> promptsRef = prompts;
        DataStream<String> raw;
        if (emitRate > 0) {
            org.apache.flink.connector.datagen.source.DataGeneratorSource<String> gen =
                    new org.apache.flink.connector.datagen.source.DataGeneratorSource<>(
                            (org.apache.flink.connector.datagen.source.GeneratorFunction<
                                            Long, String>)
                                    i -> promptsRef.get(i.intValue()),
                            prompts.size(),
                            org.apache.flink.api.connector.source.util.ratelimit
                                    .RateLimiterStrategy.perSecond(emitRate),
                            org.apache.flink.api.common.typeinfo.Types.STRING);
            raw =
                    env.fromSource(
                            gen,
                            org.apache.flink.api.common.eventtime.WatermarkStrategy.noWatermarks(),
                            "throttled-prompts");
        } else {
            raw = env.fromData(prompts);
        }

        // --batch-lanes k: shard the batcher into k independent keyed lanes so judge calls
        // parallelize (single-lane judge calls serialize: stable only while
        // judge_latency(N) < N/lambda). endInput flush covers each lane's tail.
        final int lanes = Integer.parseInt(opt.getOrDefault("batch-lanes", "1"));
        DataStream<String> routed =
                raw
                        .keyBy(s -> "lane-" + (Math.abs(s.hashCode()) % lanes))
                        .transform(
                                "batch-router",
                                Types.STRING,
                                new FlushingBatcherOperator(
                                        new Batcher(batchSize, batchTimeoutMs, judgeUrl, judgeModel, batchLog)))
                        .name("windowed-judge");

        agentsEnv
                .fromDataStream(
                        routed,
                        (org.apache.flink.api.java.functions.KeySelector<String, String>)
                                s -> Integer.toHexString(s.hashCode()))
                .apply(new BatchedEvalAgent())
                .toDataStream()
                .print();

        System.out.printf("=== batched eval %s | batch=%d timeout=%dms ===%n", runId, batchSize, batchTimeoutMs);
        agentsEnv.execute("batched-routing-" + runId);
        System.out.println("=== run complete: " + runId + " ===");
    }

    private static ResourceDescriptor ollama(String model) {
        if (model.startsWith("stub:")) {
            Map<String, Object> args = new HashMap<>();
            args.put("delayMs", Long.parseLong(model.substring("stub:".length())));
            return new ResourceDescriptor(StubChatModel.class.getName(), args);
        }
        return ResourceDescriptor.Builder.newBuilder(ResourceName.ChatModel.OLLAMA_SETUP)
                .addInitialArgument("connection", "ollamaConnection")
                .addInitialArgument("model", model)
                .addInitialArgument("think", false)
                .build();
    }

    /**
     * Flushes the Batcher's pending window when a bounded input ends. Processing-time timers do
     * not fire at end-of-input, which silently dropped 160/1,000 buffered requests in the first
     * run of this experiment; {@link BoundedOneInput#endInput()} is the canonical fix.
     */
    public static class FlushingBatcherOperator extends KeyedProcessOperator<String, String, String>
            implements BoundedOneInput {
        FlushingBatcherOperator(Batcher batcher) {
            super(batcher);
        }

        @Override
        public void endInput() throws Exception {
            Batcher batcher = (Batcher) getUserFunction();
            TimestampedCollector<String> out = new TimestampedCollector<>(output);
            List<Object> keys = new ArrayList<>();
            try (java.util.stream.Stream<Object> ks =
                    ((org.apache.flink.runtime.state.KeyedStateBackend<Object>) getKeyedStateBackend())
                            .getKeys("buf", VoidNamespace.INSTANCE)) {
                ks.forEach(keys::add);
            }
            for (Object k : keys) {
                setCurrentKey(k);
                batcher.endFlush(out);
            }
        }
    }

    /** Buffers up to N requests (or T ms), routes the whole batch with one judge call. */
    public static class Batcher extends KeyedProcessFunction<String, String, String> {
        private final int batchSize;
        private final long timeoutMs;
        private final String judgeUrl;
        private final String judgeModel;
        private final String batchLog;
        private transient ListState<String> buffer;
        private transient ListState<Long> arrivals;
        private transient ValueState<Long> timer;
        private transient BatchJudge judge;

        Batcher(int batchSize, long timeoutMs, String judgeUrl, String judgeModel, String batchLog) {
            this.batchSize = batchSize;
            this.timeoutMs = timeoutMs;
            this.judgeUrl = judgeUrl;
            this.judgeModel = judgeModel;
            this.batchLog = batchLog;
        }

        @Override
        public void open(org.apache.flink.api.common.functions.OpenContext ctx) {
            buffer = getRuntimeContext().getListState(new ListStateDescriptor<>("buf", String.class));
            arrivals = getRuntimeContext().getListState(new ListStateDescriptor<>("arr", Long.class));
            timer = getRuntimeContext().getState(new ValueStateDescriptor<>("timer", Long.class));
            judge = new BatchJudge(judgeUrl, judgeModel);
        }

        @Override
        public void processElement(String prompt, Context ctx, Collector<String> out) throws Exception {
            buffer.add(prompt);
            arrivals.add(System.currentTimeMillis());
            List<String> buf = new ArrayList<>();
            buffer.get().forEach(buf::add);
            if (buf.size() >= batchSize) {
                flush(out);
                if (timer.value() != null) {
                    ctx.timerService().deleteProcessingTimeTimer(timer.value());
                    timer.update(null);
                }
            } else if (timer.value() == null) {
                long t = ctx.timerService().currentProcessingTime() + timeoutMs;
                ctx.timerService().registerProcessingTimeTimer(t);
                timer.update(t);
            }
        }

        @Override
        public void onTimer(long ts, OnTimerContext ctx, Collector<String> out) throws Exception {
            timer.update(null);
            flush(out);
        }

        void endFlush(Collector<String> out) throws Exception {
            flush(out);
        }

        private void flush(Collector<String> out) throws Exception {
            List<String> buf = new ArrayList<>();
            buffer.get().forEach(buf::add);
            if (buf.isEmpty()) {
                return;
            }
            List<Long> arr = new ArrayList<>();
            arrivals.get().forEach(arr::add);
            buffer.clear();
            arrivals.clear();
            BatchJudge.Verdicts v = judge.route(buf, List.of("small", "big"), "small");
            long now = System.currentTimeMillis();
            synchronized (Batcher.class) {
                try (FileWriter w = new FileWriter(batchLog, true)) {
                    for (int i = 0; i < buf.size(); i++) {
                        w.write(String.format(
                                "{\"prompt_head\":%s,\"model\":\"%s\",\"batch\":%d,\"judge_ms\":%.1f,"
                                        + "\"wait_ms\":%d,\"judge_prompt_tokens\":%d,\"judge_completion_tokens\":%d,\"parse_failed\":%b}%n",
                                com.fasterxml.jackson.databind.node.TextNode.valueOf(
                                                buf.get(i).substring(0, Math.min(60, buf.get(i).length())))
                                        .toString(),
                                v.models().get(i), buf.size(), v.judgeMs(),
                                now - arr.get(i), v.promptTokens(), v.completionTokens(), v.parseFailed()));
                    }
                }
            }
            for (int i = 0; i < buf.size(); i++) {
                out.collect(v.models().get(i) + "" + buf.get(i));
            }
        }
    }
}
