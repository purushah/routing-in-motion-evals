package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.chat.model.routing.RoutingCandidate;
import org.apache.flink.agents.api.chat.model.routing.RoutingContext;
import org.apache.flink.agents.api.chat.model.routing.RoutingDecision;
import org.apache.flink.agents.api.chat.model.routing.RoutingStrategy;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/**
 * RQ4 control strategy: a coin flip between candidates. Re-executing it diverges ~50% of the
 * time, so with the durable store DISABLED the recovery experiment shows the divergence a
 * stateless system would suffer; with the store enabled, replay must pin it to 0%.
 */
public class NondetStrategy implements RoutingStrategy {

    private static final long serialVersionUID = 1L;

    /** Probability of escalating to "big"; default 0.5 (uniform over two candidates). */
    private final double escalateP;

    public NondetStrategy(Map<String, Object> args) {
        Object p = args == null ? null : args.get("escalate_p");
        this.escalateP = p == null ? -1.0 : Double.parseDouble(String.valueOf(p));
    }

    @Override
    public RoutingDecision route(RoutingContext context) {
        List<RoutingCandidate> candidates = context.getCandidates();
        RoutingCandidate pick;
        if (escalateP >= 0 && candidates.size() == 2) {
            // budget-matched random-escalation control: escalate to the 2nd candidate w.p. p
            pick =
                    candidates.get(
                            ThreadLocalRandom.current().nextDouble() < escalateP ? 1 : 0);
        } else {
            pick = candidates.get(ThreadLocalRandom.current().nextInt(candidates.size()));
        }
        return RoutingDecision.builder(pick.getName())
                .reason("random escalation (control strategy)")
                .build();
    }
}
