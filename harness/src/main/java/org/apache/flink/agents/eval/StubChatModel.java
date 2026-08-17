package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.chat.messages.ChatMessage;
import org.apache.flink.agents.api.chat.messages.MessageRole;
import org.apache.flink.agents.api.chat.model.BaseChatModelSetup;
import org.apache.flink.agents.api.resource.ResourceContext;
import org.apache.flink.agents.api.resource.ResourceDescriptor;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * RQ3 fallback backend: returns a canned answer after a fixed delay. Measures the
 * <em>operator's</em> scaling with parallelism, isolated from local model-server saturation
 * (which the real-Ollama sweep documents separately). Reported in the paper clearly labeled as
 * the stub-backend curve.
 */
public class StubChatModel extends BaseChatModelSetup {

    private final long delayMs;

    public StubChatModel(ResourceDescriptor descriptor, ResourceContext resourceContext) {
        super(descriptor, resourceContext);
        Object d = descriptor.getArgument("delayMs");
        this.delayMs = d instanceof Number ? ((Number) d).longValue() : 200L;
    }

    /** No connection/prompt/tools to resolve — the base open() would fail on the null connection. */
    @Override
    public void open() {}

    @Override
    public Map<String, Object> getParameters() {
        return Map.of();
    }

    @Override
    public ChatMessage chat(
            List<ChatMessage> messages,
            Map<String, Object> promptArgs,
            Map<String, Object> modelParams) {
        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        Map<String, Object> extraArgs = new HashMap<>();
        extraArgs.put("model_name", "stub-" + delayMs + "ms");
        extraArgs.put("promptTokens", 10);
        extraArgs.put("completionTokens", 5);
        return new ChatMessage(MessageRole.ASSISTANT, "stub reply. ANSWER: A", extraArgs);
    }
}
