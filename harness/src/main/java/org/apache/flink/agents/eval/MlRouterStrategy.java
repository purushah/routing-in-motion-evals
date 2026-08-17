package org.apache.flink.agents.eval;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.apache.flink.agents.api.chat.model.routing.RoutingContext;
import org.apache.flink.agents.api.chat.model.routing.RoutingDecision;
import org.apache.flink.agents.api.chat.model.routing.RoutingStrategy;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

/**
 * The "routed-mf" arm: RouteLLM's learned router (Apache-2.0, lmsys) running in a local Python
 * sidecar ({@code infra/routellm_sidecar.py}). The sidecar returns the BERT classifier's
 * predicted strong-model win rate; win_rate >= threshold routes to "big".
 *
 * <p>EVAL-HARNESS CODE: demonstrates that the canonical open-source learned routing policy plugs
 * into the RoutingStrategy SPI unchanged. The win rate is recorded as the decision score, so it
 * lands on the ModelRoutingEvent.
 */
public class MlRouterStrategy implements RoutingStrategy {

    private static final long serialVersionUID = 1L;

    private final String sidecarUrl;

    private transient HttpClient httpClient;
    private transient ObjectMapper mapper;

    public MlRouterStrategy(Map<String, Object> args) {
        this.sidecarUrl =
                (args == null ? Map.of() : args)
                        .getOrDefault("sidecar_url", "http://localhost:8765")
                        .toString();
    }

    @Override
    public RoutingDecision route(RoutingContext context) throws Exception {
        String request = context.lastUserMessage();
        if (request == null || request.isEmpty()) {
            return RoutingDecision.abstain();
        }
        if (httpClient == null) {
            httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
            mapper = new ObjectMapper();
        }
        ObjectNode body = mapper.createObjectNode();
        body.put("prompt", request);
        HttpRequest httpRequest =
                HttpRequest.newBuilder()
                        .uri(URI.create(sidecarUrl + "/route"))
                        .timeout(Duration.ofSeconds(30))
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body)))
                        .build();
        HttpResponse<String> response =
                httpClient.send(httpRequest, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) {
            throw new IllegalStateException(
                    "RouteLLM sidecar failed: HTTP "
                            + response.statusCode()
                            + ": "
                            + response.body());
        }
        JsonNode reply = mapper.readTree(response.body());
        double winRate = reply.path("win_rate").asDouble();
        double threshold = reply.path("threshold").asDouble();
        String selected = winRate >= threshold ? "big" : "small";
        return RoutingDecision.builder(selected)
                .reason("routellm bert win_rate=" + winRate + " vs threshold=" + threshold)
                .score(winRate)
                .metadata("router", "routellm-bert")
                .metadata("threshold", threshold)
                .build();
    }
}
