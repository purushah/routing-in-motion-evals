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

/**
 * Agent for the windowed-routing arm: input is "<model><prompt>" — the model was already
 * selected upstream by the windowed batch judge, so the agent sends the chat DIRECTLY to that
 * model name (the select-not-delegate contract lets pre-routing compose with the normal path).
 */
public class BatchedEvalAgent extends Agent {

    @Action(EventType.InputEvent)
    public static void processInput(InputEvent event, RunnerContext ctx) {
        String s = (String) event.getInput();
        int sep = s.indexOf('');
        String model = s.substring(0, sep);
        String prompt = s.substring(sep + 1);
        ctx.sendEvent(
                new ChatRequestEvent(
                        model, Collections.singletonList(ChatMessage.user(prompt))));
    }

    @Action(EventType.ChatResponseEvent)
    public static void processChatResponse(ChatResponseEvent event, RunnerContext ctx) {
        String content = event.getResponse().getContent();
        ctx.sendEvent(
                new OutputEvent(
                        "{request_id=" + event.getRequestId() + ", answer_head="
                                + (content == null
                                        ? ""
                                        : content.substring(0, Math.min(60, content.length())))
                                + "}"));
    }
}
