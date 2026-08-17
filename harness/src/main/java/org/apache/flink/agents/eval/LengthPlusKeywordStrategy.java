package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.chat.model.routing.RoutingContext;
import org.apache.flink.agents.api.chat.model.routing.RoutingDecision;
import org.apache.flink.agents.api.chat.model.routing.RoutingStrategy;

import java.util.Map;
import java.util.regex.Pattern;

/**
 * The "routed-custom" arm: a hand-written heuristic combining hard-topic keywords with prompt
 * length. Long prompts on this workload are word problems / code specs that need the strong
 * model even without keyword hits.
 */
public class LengthPlusKeywordStrategy implements RoutingStrategy {

    private static final long serialVersionUID = 1L;

    private static final Pattern HARD =
            Pattern.compile(
                    "\\b(code|sql|python|function|prove|derive|theorem|algorithm|complexit|"
                            + "integral|probability|per (hour|day|week)|how (much|many))\\b",
                    Pattern.CASE_INSENSITIVE);

    private final int lengthThreshold;

    public LengthPlusKeywordStrategy(Map<String, Object> args) {
        Object t = args == null ? null : args.get("length_threshold");
        this.lengthThreshold = t instanceof Number ? ((Number) t).intValue() : 400;
    }

    @Override
    public RoutingDecision route(RoutingContext context) {
        String text = context.lastUserMessage();
        if (text == null || text.isEmpty()) {
            return RoutingDecision.abstain();
        }
        boolean keyword = HARD.matcher(text).find();
        boolean lengthy = text.length() > lengthThreshold;
        if (keyword || lengthy) {
            return RoutingDecision.builder("big")
                    .reason(keyword ? "hard-topic keyword" : "long prompt (" + text.length() + " chars)")
                    .metadata("keyword_hit", keyword)
                    .metadata("prompt_chars", text.length())
                    .build();
        }
        return RoutingDecision.abstain();
    }
}
