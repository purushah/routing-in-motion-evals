package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.AgentsExecutionEnvironment;
import org.apache.flink.agents.api.agents.AgentExecutionOptions;
import org.apache.flink.agents.api.chat.model.routing.ModelRouter;
import org.apache.flink.agents.api.chat.model.routing.Strategies;
import org.apache.flink.agents.api.configuration.AgentConfigOptions;
import org.apache.flink.agents.api.logger.LoggerType;
import org.apache.flink.agents.api.resource.ResourceDescriptor;
import org.apache.flink.agents.api.resource.ResourceName;
import org.apache.flink.agents.api.resource.ResourceType;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Routing-eval job (Phase 0: smoke). Runs one arm over a small generated workload against a local
 * Ollama server and writes the EventLog to {@code <runsDir>/<runId>/eventlog}.
 *
 * <p>Usage: {@code java -jar routing-eval-harness-0.1-shaded.jar --run-id smoke-001
 * [--arm routed-rules|always-small|always-big] [--requests 20] [--parallelism 1]
 * [--small qwen2.5:0.5b] [--big llama3.1:8b] [--runs-dir <path>]}
 */
public final class EvalJob {

    public static void main(String[] args) throws Exception {
        Map<String, String> opt = parseArgs(args);
        if (opt.containsKey("temperature")) {
            openaiTemperatureOverride = Double.parseDouble(opt.get("temperature"));
        }
        String runId = require(opt, "run-id");
        String arm = opt.getOrDefault("arm", "routed-rules");
        smallDesc = opt.getOrDefault("small-desc", smallDesc);
        bigDesc = opt.getOrDefault("big-desc", bigDesc);
        int requests = Integer.parseInt(opt.getOrDefault("requests", "20"));
        int parallelism = Integer.parseInt(opt.getOrDefault("parallelism", "1"));
        String small = opt.getOrDefault("small", "qwen2.5:0.5b");
        String big = opt.getOrDefault("big", "llama3.1:8b");
        Path runDir =
                Path.of(opt.getOrDefault("runs-dir", "runs")).resolve(runId).toAbsolutePath();
        Files.createDirectories(runDir.resolve("eventlog"));

        // Recovery (RQ4) support: checkpointing to the run dir, retained on cancellation, with
        // optional restore; the durable action-state store lives in Kafka under --state-topic.
        org.apache.flink.configuration.Configuration flinkConf =
                new org.apache.flink.configuration.Configuration();
        long checkpointMs = Long.parseLong(opt.getOrDefault("checkpoint-interval", "0"));
        if (checkpointMs > 0) {
            flinkConf.setString("execution.checkpointing.interval", checkpointMs + "ms");
            flinkConf.setString(
                    "execution.checkpointing.dir",
                    "file://" + runDir.resolve("checkpoints"));
            flinkConf.setString(
                    "execution.checkpointing.externalized-checkpoint-retention",
                    "RETAIN_ON_CANCELLATION");
        }
        String restoreFrom = opt.get("restore-from");
        if (restoreFrom != null) {
            flinkConf.setString("execution.savepoint.path", restoreFrom);
        }
        StreamExecutionEnvironment env =
                StreamExecutionEnvironment.getExecutionEnvironment(flinkConf);
        env.setParallelism(parallelism);
        AgentsExecutionEnvironment agentsEnv =
                AgentsExecutionEnvironment.getExecutionEnvironment(env);

        agentsEnv.getConfig().set(AgentExecutionOptions.NUM_ASYNC_THREADS, 2);
        if ("kafka".equals(opt.get("state-backend"))) {
            agentsEnv.getConfig().set(AgentConfigOptions.ACTION_STATE_STORE_BACKEND, "kafka");
            agentsEnv
                    .getConfig()
                    .set(
                            AgentConfigOptions.KAFKA_BOOTSTRAP_SERVERS,
                            opt.getOrDefault("kafka-servers", "localhost:9092"));
            agentsEnv
                    .getConfig()
                    .set(
                            AgentConfigOptions.KAFKA_ACTION_STATE_TOPIC,
                            opt.getOrDefault("state-topic", "action-state-" + runId));
        }
        // Local Ollama occasionally stalls a request under sustained load (model swapping);
        // retries keep a 1000-request run from dying on one slow call.
        agentsEnv
                .getConfig()
                .set(
                        AgentExecutionOptions.ERROR_HANDLING_STRATEGY,
                        org.apache.flink.agents.api.agents.Agent.ErrorHandlingStrategy.RETRY);
        agentsEnv.getConfig().set(AgentExecutionOptions.MAX_RETRIES, 2);
        agentsEnv.getConfig().set(AgentExecutionOptions.RETRY_WAIT_INTERVAL, 2);
        agentsEnv.getConfig().set(AgentConfigOptions.EVENT_LOGGER_TYPE, LoggerType.FILE);
        agentsEnv
                .getConfig()
                .set(AgentConfigOptions.BASE_LOG_DIR, runDir.resolve("eventlog").toString());

        // Ollama connection + the two candidate chat models.
        agentsEnv.addResource(
                "ollamaConnection",
                ResourceType.CHAT_MODEL_CONNECTION,
                ResourceDescriptor.Builder.newBuilder(ResourceName.ChatModel.OLLAMA_CONNECTION)
                        .addInitialArgument("requestTimeout", 240)
                        .addInitialArgument("endpoint", "http://localhost:11434")
                        .build());
        String openaiKey = System.getenv("OPENAI_API_KEY");
        if (openaiKey != null && !openaiKey.isEmpty()) {
            agentsEnv.addResource(
                    "openaiConnection",
                    ResourceType.CHAT_MODEL_CONNECTION,
                    ResourceDescriptor.Builder.newBuilder(
                                    ResourceName.ChatModel.OPENAI_COMPLETIONS_CONNECTION)
                            .addInitialArgument("api_key", openaiKey)
                            .build());
        }
        String anthropicKey = System.getenv("ANTHROPIC_API_KEY");
        if (anthropicKey != null && !anthropicKey.isEmpty()) {
            agentsEnv.addResource(
                    "anthropicConnection",
                    ResourceType.CHAT_MODEL_CONNECTION,
                    ResourceDescriptor.Builder.newBuilder(
                                    ResourceName.ChatModel.OPENAI_COMPLETIONS_CONNECTION)
                            .addInitialArgument("api_key", anthropicKey)
                            // Anthropic's OpenAI-compatible endpoint
                            .addInitialArgument("api_base_url", "https://api.anthropic.com/v1/")
                            .build());
        }
        agentsEnv.addResource(
                "proxyConnection",
                ResourceType.CHAT_MODEL_CONNECTION,
                ResourceDescriptor.Builder.newBuilder(
                                ResourceName.ChatModel.OPENAI_COMPLETIONS_CONNECTION)
                        .addInitialArgument("api_key", "sk-eval")
                        .addInitialArgument(
                                "api_base_url",
                                opt.getOrDefault("proxy-url", "http://localhost:4000/v1"))
                        .build());
        agentsEnv
                .addResource("small", ResourceType.CHAT_MODEL, ollamaModel(small))
                .addResource("big", ResourceType.CHAT_MODEL, ollamaModel(big));

        // The agent always talks to "target"; the arm decides what "target" is.
        switch (arm) {
            case "always-small":
                agentsEnv.addResource(EvalAgent.TARGET, ResourceType.CHAT_MODEL, ollamaModel(small));
                break;
            case "always-big":
                agentsEnv.addResource(EvalAgent.TARGET, ResourceType.CHAT_MODEL, ollamaModel(big));
                break;
            case "routed-rules":
                agentsEnv.addResource(
                        EvalAgent.TARGET,
                        ResourceType.MODEL_ROUTER,
                        routerBuilder()
                                .strategy(
                                        Strategies.rules(
                                                Map.of(
                                                        "big",
                                                        "\\b(code|sql|python|function|prove|derive|theorem|algorithm|probability|per (hour|day|week)|how (much|many))\\b")))
                                .build());
                break;
            case "routed-custom":
                agentsEnv.addResource(
                        EvalAgent.TARGET,
                        ResourceType.MODEL_ROUTER,
                        routerBuilder()
                                .strategy(Strategies.of(LengthPlusKeywordStrategy.class))
                                .build());
                break;
            case "routed-judge":
                agentsEnv.addResource(
                        EvalAgent.TARGET,
                        ResourceType.MODEL_ROUTER,
                        routerBuilder()
                                .strategy(
                                        Strategies.of(
                                                JudgeStrategy.class.getName(),
                                                Map.of(
                                                        "judge_model",
                                                        opt.getOrDefault(
                                                                "judge-model", "qwen2.5:0.5b"),
                                                        "temperature",
                                                        Double.parseDouble(
                                                                opt.getOrDefault(
                                                                        "judge-temperature",
                                                                        "0")))))
                                .build());
                break;
            case "routed-nondet":
                agentsEnv.addResource(
                        EvalAgent.TARGET,
                        ResourceType.MODEL_ROUTER,
                        routerBuilder()
                                .strategy(
                                        Strategies.of(
                                                NondetStrategy.class.getName(),
                                                Map.of(
                                                        "escalate_p",
                                                        opt.getOrDefault("escalate-p", "-1"))))
                                .build());
                break;
            case "routed-mf":
                agentsEnv.addResource(
                        EvalAgent.TARGET,
                        ResourceType.MODEL_ROUTER,
                        routerBuilder()
                                .strategy(
                                        Strategies.of(
                                                MlRouterStrategy.class.getName(),
                                                Map.of(
                                                        "sidecar_url",
                                                        opt.getOrDefault(
                                                                "sidecar-url",
                                                                "http://localhost:8765"))))
                                .build());
                break;
            default:
                throw new IllegalArgumentException("Unknown arm: " + arm);
        }

        String requestsFile = opt.get("requests-file");
        List<String> prompts =
                requestsFile != null ? loadPrompts(requestsFile) : smokePrompts(requests);
        // Two things pin agent parallelism to 1 without these steps: the framework sets the
        // action operator's parallelism from the (keyed) input's parallelism, and collection
        // sources are always parallelism 1 — so fan out through a parallel no-op map first,
        // then key by prompt so requests spread across subtasks.
        //
        // --emit-rate <records/s> switches to a rate-limited, checkpointable generator source.
        // Recovery trials need it: an instantly-finished bounded source makes checkpoints
        // capture "source complete" while requests are still in flight, so a restore has
        // nothing to re-emit and in-flight work is lost — the kill must land mid-stream.
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
                            org.apache.flink.api.common.eventtime.WatermarkStrategy
                                    .noWatermarks(),
                            "throttled-workload");
        } else {
            raw = env.fromData(prompts);
        }
        DataStream<String> input =
                raw.rebalance().map(s -> s).setParallelism(parallelism).name("fanout");
        // Key must be underscore-free: the Kafka action-state store serializes state keys as
        // "<key>_<seq>_<uuid>_<uuid>" and splits on '_' when parsing (upstream limitation), so
        // any '_' in the key breaks recovery. Hex hash keeps distribution and stays clean.
        agentsEnv
                .fromDataStream(
                        input,
                        (org.apache.flink.api.java.functions.KeySelector<String, String>)
                                s -> Integer.toHexString(s.hashCode()))
                .apply(new EvalAgent())
                .toDataStream()
                .print();

        System.out.printf(
                "=== eval run %s | arm=%s | requests=%d | parallelism=%d | logdir=%s ===%n",
                runId, arm, requests, parallelism, runDir.resolve("eventlog"));
        agentsEnv.execute("routing-eval-" + runId + "-" + arm);
        System.out.println("=== run complete: " + runId + " ===");
    }

    // Workload-appropriate candidate descriptions matter: the judge routes by reading
    // these. Overridable per run (--small-desc/--big-desc) so a non-math workload does
    // not inherit the math-oriented defaults.
    private static String smallDesc = "fast and cheap; chit-chat, simple factual questions";
    private static String bigDesc = "strong but expensive; code, SQL, math, multi-step analysis";

    private static ModelRouter.Builder routerBuilder() {
        return ModelRouter.of("small", "big")
                .describe("small", smallDesc)
                .describe("big", bigDesc)
                .defaultModel("small")
                .fallback(true);
    }

    /** Reads {"prompt": ...} per line from a requests.jsonl file. */
    private static List<String> loadPrompts(String path) throws Exception {
        com.fasterxml.jackson.databind.ObjectMapper mapper =
                new com.fasterxml.jackson.databind.ObjectMapper();
        List<String> prompts = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of(path))) {
            if (!line.isBlank()) {
                prompts.add(mapper.readTree(line).path("prompt").asText());
            }
        }
        return prompts;
    }

    /** --temperature override for non-gpt-5 OpenAI arms (temperature-equalized reruns). */
    private static Double openaiTemperatureOverride = null;

    /**
     * Model-name prefixes select the backend: "stub:<delayMs>" = fixed-latency stub (RQ3),
     * "openai:<model>" = OpenAI (RQ1/RQ5; key from OPENAI_API_KEY), anything else = local Ollama.
     */
    private static ResourceDescriptor ollamaModel(String model) {
        if (model.startsWith("stub:")) {
            Map<String, Object> args = new HashMap<>();
            args.put("delayMs", Long.parseLong(model.substring("stub:".length())));
            return new ResourceDescriptor(StubChatModel.class.getName(), args);
        }
        if (model.startsWith("proxy:")) {
            // RQ5 arm A: the "model" is a LiteLLM proxy endpoint; the engine sees ONE model.
            return ResourceDescriptor.Builder.newBuilder(
                            ResourceName.ChatModel.OPENAI_COMPLETIONS_SETUP)
                    .addInitialArgument("connection", "proxyConnection")
                    .addInitialArgument("model", model.substring("proxy:".length()))
                    // backends behind the proxy are gpt-5 family: default temperature only
                    .addInitialArgument("temperature", 1.0d)
                    .build();
        }
        if (model.startsWith("anthropic:")) {
            // AnthropicChatModelSetup omits `temperature`: Claude Sonnet 5 rejects the
            // parameter entirely (the integration's 0.1 default 400s every call).
            return ResourceDescriptor.Builder.newBuilder(AnthropicChatModelSetup.class.getName())
                    .addInitialArgument("connection", "anthropicConnection")
                    .addInitialArgument("model", model.substring("anthropic:".length()))
                    .build();
        }
        if (model.startsWith("openai:")) {
            String name = model.substring("openai:".length());
            ResourceDescriptor.Builder b =
                    ResourceDescriptor.Builder.newBuilder(
                                    ResourceName.ChatModel.OPENAI_COMPLETIONS_SETUP)
                            .addInitialArgument("connection", "openaiConnection")
                            .addInitialArgument("model", name);
            if (name.startsWith("gpt-5")) {
                // gpt-5-family models reject non-default temperature; the integration's
                // default (0.1) turns every call into a 400.
                b.addInitialArgument("temperature", 1.0d);
            } else if (openaiTemperatureOverride != null) {
                b.addInitialArgument("temperature", openaiTemperatureOverride);
            }
            return b.build();
        }
        return ResourceDescriptor.Builder.newBuilder(ResourceName.ChatModel.OLLAMA_SETUP)
                .addInitialArgument("connection", "ollamaConnection")
                .addInitialArgument("model", model)
                // qwen2.5 (unlike qwen3) rejects requests with thinking enabled; the eval
                // measures routing, not reasoning, so disable it everywhere for comparability.
                .addInitialArgument("think", false)
                .build();
    }

    /** Alternating easy / hard prompts so the router exercises both candidates. */
    private static List<String> smokePrompts(int n) {
        List<String> prompts = new ArrayList<>(n);
        for (int i = 0; i < n; i++) {
            prompts.add(
                    i % 2 == 0
                            ? "Say hello in five words or fewer. (request " + i + ")"
                            : "Write SQL to count rows in table t" + i + ".");
        }
        return prompts;
    }

    private static Map<String, String> parseArgs(String[] args) {
        Map<String, String> map = new HashMap<>();
        for (int i = 0; i < args.length - 1; i += 2) {
            map.put(args[i].replaceFirst("^--", ""), args[i + 1]);
        }
        return map;
    }

    private static String require(Map<String, String> opt, String key) {
        String v = opt.get(key);
        if (v == null) {
            throw new IllegalArgumentException("--" + key + " is required");
        }
        return v;
    }
}
