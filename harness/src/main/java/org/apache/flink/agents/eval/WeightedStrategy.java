package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.chat.model.routing.RoutingCandidate;
import org.apache.flink.agents.api.chat.model.routing.RoutingContext;
import org.apache.flink.agents.api.chat.model.routing.RoutingDecision;
import org.apache.flink.agents.api.chat.model.routing.RoutingStrategy;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Weighted traffic split across candidates (the canary / A-B pattern): each request routes to
 * candidate c with probability weight(c)/sum(weights). Non-deterministic by construction — the
 * policy class whose assignments a restart silently reshuffles unless the decision is durable
 * (measured in RQ4). Args: {"weights": {"small": 0.8, "big": 0.2}}.
 */
public class WeightedStrategy implements RoutingStrategy {

    private static final long serialVersionUID = 1L;
    private final Map<String, Double> weights = new LinkedHashMap<>();

    @SuppressWarnings("unchecked")
    public WeightedStrategy(Map<String, Object> args) {
        Object raw = args == null ? null : args.get("weights");
        if (raw instanceof Map) {
            for (Map.Entry<String, ?> e : ((Map<String, ?>) raw).entrySet()) {
                weights.put(e.getKey(), Double.parseDouble(String.valueOf(e.getValue())));
            }
        }
        if (weights.isEmpty()) {
            throw new IllegalArgumentException("WeightedStrategy requires a 'weights' map.");
        }
    }

    @Override
    public RoutingDecision route(RoutingContext context) {
        double total = 0;
        for (RoutingCandidate c : context.getCandidates()) {
            total += weights.getOrDefault(c.getName(), 0.0);
        }
        double r = ThreadLocalRandom.current().nextDouble() * total;
        for (RoutingCandidate c : context.getCandidates()) {
            r -= weights.getOrDefault(c.getName(), 0.0);
            if (r <= 0) {
                return RoutingDecision.builder(c.getName())
                        .reason("weighted split (w=" + weights.get(c.getName()) + ")")
                        .build();
            }
        }
        return RoutingDecision.abstain();
    }
}
