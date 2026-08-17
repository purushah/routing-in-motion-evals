package org.apache.flink.agents.eval;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/**
 * One judge call that routes a whole WINDOW of requests: the prompt lists K numbered requests and
 * the reply is schema-constrained to a JSON array of K candidate names. Amortizes the judge's
 * latency and tokens across the batch — the windowed-routing experiment's core.
 */
public final class BatchJudge {

    private final String judgeUrl;
    private final String judgeModel;
    private final HttpClient http =
            HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final ObjectMapper mapper = new ObjectMapper();

    /** OpenAI mode: judgeModel "openai:<model>" routes to api.openai.com with OPENAI_API_KEY. */
    private final boolean openai;

    public BatchJudge(String judgeUrl, String judgeModel) {
        this.openai = judgeModel.startsWith("openai:");
        this.judgeUrl = openai ? "https://api.openai.com" : judgeUrl;
        this.judgeModel = openai ? judgeModel.substring("openai:".length()) : judgeModel;
    }

    /** Returns one candidate name per request (same order); falls back to defaultModel. */
    public Verdicts route(List<String> requests, List<String> candidates, String defaultModel)
            throws Exception {
        StringBuilder prompt =
                new StringBuilder(
                        "Classify EACH numbered request below to the candidate model that should"
                            + " answer it. Do not answer the requests. Candidates: small = fast and"
                            + " cheap (chit-chat, simple facts); big = strong but expensive (code,"
                            + " SQL, math, multi-step analysis).\nReply with a JSON array of exactly "
                                + requests.size()
                                + " candidate names, one per request, in order.\n\n");
        for (int i = 0; i < requests.size(); i++) {
            String r = requests.get(i);
            prompt.append("--- request ").append(i + 1).append(" ---\n")
                    .append(r, 0, Math.min(r.length(), 500))
                    .append('\n');
        }

        if (openai) {
            return routeOpenai(prompt.toString(), requests, candidates, defaultModel);
        }
        ObjectNode body = mapper.createObjectNode();
        body.put("model", judgeModel);
        body.put("stream", false);
        body.put("think", false);
        ObjectNode format = body.putObject("format");
        format.put("type", "object");
        ObjectNode choices = format.putObject("properties").putObject("choices");
        choices.put("type", "array");
        ObjectNode items = choices.putObject("items");
        items.put("type", "string");
        ArrayNode allowed = items.putArray("enum");
        candidates.forEach(allowed::add);
        format.putArray("required").add("choices");
        ObjectNode opts = body.putObject("options");
        opts.put("temperature", 0);
        // large-N prompts overflow Ollama's default context; request explicit room for
        // prompt + the N-element verdict array (qwen3 supports 32k).
        opts.put("num_ctx", 32768);
        opts.put("num_predict", 8192);
        ObjectNode msg = body.putArray("messages").addObject();
        msg.put("role", "user");
        msg.put("content", prompt.toString());

        long t0 = System.nanoTime();
        HttpResponse<String> resp =
                http.send(
                        HttpRequest.newBuilder()
                                .uri(URI.create(judgeUrl + "/api/chat"))
                                .timeout(Duration.ofSeconds(900))
                                .header("Content-Type", "application/json")
                                .POST(
                                        HttpRequest.BodyPublishers.ofString(
                                                mapper.writeValueAsString(body)))
                                .build(),
                        HttpResponse.BodyHandlers.ofString());
        double ms = (System.nanoTime() - t0) / 1e6;
        if (resp.statusCode() != 200) {
            throw new IllegalStateException("batch judge HTTP " + resp.statusCode());
        }
        JsonNode root = mapper.readTree(resp.body());
        // A truncated reply (context/num_predict ceiling) is a per-batch health datum, not a
        // job-killer: fall back to the default model for the whole window and record it.
        JsonNode arr;
        boolean parseFailed = false;
        try {
            arr = mapper.readTree(root.path("message").path("content").asText("[]")).path("choices");
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
            arr = mapper.createArrayNode();
            parseFailed = true;
        }
        List<String> out = new ArrayList<>(requests.size());
        for (int i = 0; i < requests.size(); i++) {
            String v = arr.path(i).asText("");
            out.add(candidates.contains(v) ? v : defaultModel);
        }
        return new Verdicts(
                out,
                ms,
                root.path("prompt_eval_count").asLong(0),
                root.path("eval_count").asLong(0),
                parseFailed);
    }

    private Verdicts routeOpenai(
            String prompt, List<String> requests, List<String> candidates, String defaultModel)
            throws Exception {
        ObjectNode body = mapper.createObjectNode();
        body.put("model", judgeModel);
        ObjectNode msg = body.putArray("messages").addObject();
        msg.put("role", "user");
        msg.put("content", prompt);
        // schema-constrained verdict array, same anti-hijack shape as the Ollama path
        ObjectNode rf = body.putObject("response_format");
        rf.put("type", "json_schema");
        ObjectNode js = rf.putObject("json_schema");
        js.put("name", "verdicts");
        js.put("strict", true);
        ObjectNode sch = js.putObject("schema");
        sch.put("type", "object");
        sch.put("additionalProperties", false);
        ObjectNode choices = sch.putObject("properties").putObject("choices");
        choices.put("type", "array");
        ObjectNode items = choices.putObject("items");
        items.put("type", "string");
        com.fasterxml.jackson.databind.node.ArrayNode allowed = items.putArray("enum");
        candidates.forEach(allowed::add);
        sch.putArray("required").add("choices");

        long t0 = System.nanoTime();
        HttpResponse<String> resp =
                http.send(
                        HttpRequest.newBuilder()
                                .uri(URI.create(judgeUrl + "/v1/chat/completions"))
                                .timeout(Duration.ofSeconds(900))
                                .header("Content-Type", "application/json")
                                .header(
                                        "Authorization",
                                        "Bearer " + System.getenv("OPENAI_API_KEY"))
                                .POST(
                                        HttpRequest.BodyPublishers.ofString(
                                                mapper.writeValueAsString(body)))
                                .build(),
                        HttpResponse.BodyHandlers.ofString());
        double ms = (System.nanoTime() - t0) / 1e6;
        if (resp.statusCode() != 200) {
            throw new IllegalStateException("openai batch judge HTTP " + resp.statusCode());
        }
        JsonNode root = mapper.readTree(resp.body());
        JsonNode arr;
        boolean parseFailed = false;
        try {
            arr =
                    mapper.readTree(
                                    root.path("choices").path(0).path("message").path("content")
                                            .asText("{}"))
                            .path("choices");
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
            arr = mapper.createArrayNode();
            parseFailed = true;
        }
        List<String> out = new ArrayList<>(requests.size());
        for (int i = 0; i < requests.size(); i++) {
            String v = arr.path(i).asText("");
            out.add(candidates.contains(v) ? v : defaultModel);
        }
        return new Verdicts(
                out,
                ms,
                root.path("usage").path("prompt_tokens").asLong(0),
                root.path("usage").path("completion_tokens").asLong(0),
                parseFailed);
    }

    /** Batch verdicts plus the judge call's cost, for per-request amortization math. */
    public record Verdicts(
            List<String> models, double judgeMs, long promptTokens, long completionTokens, boolean parseFailed) {}
}
