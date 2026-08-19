package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.chat.model.routing.RoutingContext;
import org.apache.flink.agents.api.chat.model.routing.RoutingDecision;
import org.apache.flink.agents.api.chat.model.routing.RoutingStrategy;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

/**
 * Deterministic ("sticky") A-B split: hash the request CONTENT into [0,100) and escalate to the
 * second candidate below the percent threshold. Keying on content, not the engine-generated
 * request id, is deliberate: event ids regenerate when the source replays after a restore (the
 * RQ4 bug-one lesson), so an id-keyed split is only restart-stable WITH the durable store, while
 * a content-keyed split re-derives identically even without one. Args: {"escalate_percent": 50}.
 */
public class HashSplitStrategy implements RoutingStrategy {

    private static final long serialVersionUID = 1L;
    private final int escalatePercent;

    public HashSplitStrategy(Map<String, Object> args) {
        Object p = args == null ? null : args.get("escalate_percent");
        this.escalatePercent = p == null ? 50 : (int) Double.parseDouble(String.valueOf(p));
    }

    @Override
    public RoutingDecision route(RoutingContext context) throws Exception {
        String text = context.lastUserMessage();
        byte[] d = MessageDigest.getInstance("SHA-1").digest(text.getBytes(StandardCharsets.UTF_8));
        int bucket = Math.floorMod((d[0] << 8) | (d[1] & 0xFF), 100);
        String pick =
                bucket < escalatePercent
                        ? context.getCandidates().get(1).getName()
                        : context.getCandidates().get(0).getName();
        return RoutingDecision.builder(pick)
                .reason("hash split (bucket=" + bucket + "/" + escalatePercent + ")")
                .build();
    }
}
