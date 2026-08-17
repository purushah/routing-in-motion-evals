package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.EventType;
import org.apache.flink.agents.api.InputEvent;
import org.apache.flink.agents.api.OutputEvent;
import org.apache.flink.agents.api.agents.Agent;
import org.apache.flink.agents.api.annotation.Action;
import org.apache.flink.agents.api.chat.messages.ChatMessage;
import org.apache.flink.agents.api.context.RunnerContext;
import org.apache.flink.agents.api.event.ChatRequestEvent;
import org.apache.flink.agents.api.event.ChatResponseEvent;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Minimal eval agent: every input goes to the resource named {@code target}. The eval job
 * registers "target" as either a MODEL_ROUTER (routed arms) or a plain CHAT_MODEL (fixed arms),
 * so the agent code is byte-identical across all arms.
 */
public class EvalAgent extends Agent {

    public static final String TARGET = "target";

    @Action(EventType.InputEvent)
    public static void processInput(InputEvent event, RunnerContext ctx) {
        ctx.sendEvent(
                new ChatRequestEvent(
                        TARGET,
                        Collections.singletonList(ChatMessage.user((String) event.getInput()))));
    }

    @Action(EventType.ChatResponseEvent)
    public static void processChatResponse(ChatResponseEvent event, RunnerContext ctx) {
        // Emit a compact result record; full per-request analysis reads the EventLog.
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("request_id", event.getRequestId().toString());
        Object routing = event.getResponse().getExtraArgs().get("model_routing");
        if (routing != null) {
            result.put("model_routing", routing);
        }
        String content = event.getResponse().getContent();
        result.put(
                "answer_head",
                content == null ? "" : content.substring(0, Math.min(80, content.length())));
        ctx.sendEvent(new OutputEvent(result.toString()));
    }
}
