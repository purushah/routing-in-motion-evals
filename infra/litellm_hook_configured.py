"""Best-practice-configured LiteLLM hooks (RQ5 configured-proxy arm).

Same regex routing policy as litellm_hook.py, plus the documented remediation the
paper's Table row invites: a post-call hook that surfaces the actually-dispatched
deployment in the response's `model` field, so a client (here: the engine's
per-model token metrics, which read the response's model_name) can attribute
tokens to the real backend instead of the requested alias.
"""
import re
from litellm.integrations.custom_logger import CustomLogger

HARD = re.compile(r"\b(code|sql|python|function|prove|derive|theorem|algorithm|probability|per (hour|day|week)|how (much|many))\b", re.I)

# alias -> deployment shown to accounting
DEPLOYMENT = {"small": "count-small", "big": "count-big"}

class ConfiguredRegexRouter(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        msgs = data.get("messages") or []
        user = [m for m in msgs if m.get("role") == "user"]
        text = user[-1].get("content", "") if user else ""
        data["model"] = "big" if HARD.search(text) else "small"
        return data

    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        try:
            alias = data.get("model")
            if alias in DEPLOYMENT:
                response.model = DEPLOYMENT[alias]
            if getattr(response, "choices", None):
                response.choices[0].message.content += " [hook-fired]"
        except Exception:
            pass
        return response

proxy_handler_instance = ConfiguredRegexRouter()
