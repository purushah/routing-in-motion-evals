package org.apache.flink.agents.eval;

import org.apache.flink.agents.api.resource.ResourceContext;
import org.apache.flink.agents.api.resource.ResourceDescriptor;
import org.apache.flink.agents.integrations.chatmodels.openai.OpenAICompletionsSetup;

import java.util.HashMap;
import java.util.Map;

/**
 * Anthropic models via the OpenAI-compatible endpoint (api.anthropic.com/v1).
 *
 * <p>Claude Sonnet 5 rejects the {@code temperature} parameter outright ("temperature is
 * deprecated for this model") — the third distinct provider sampling constraint the eval hit,
 * after gpt-5's mandatory default temperature. The upstream {@code OpenAICompletionsSetup}
 * always sends its 0.1 default, so this subclass strips the parameter; all Anthropic arms run
 * at the provider default (disclosed in the paper's threats section).
 */
public class AnthropicChatModelSetup extends OpenAICompletionsSetup {

    public AnthropicChatModelSetup(ResourceDescriptor descriptor, ResourceContext context) {
        super(descriptor, context);
    }

    @Override
    public Map<String, Object> getParameters() {
        Map<String, Object> parameters = new HashMap<>(super.getParameters());
        parameters.remove("temperature");
        return parameters;
    }
}
