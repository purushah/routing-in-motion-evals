"""LiteLLM pre-call hook implementing the SAME regex policy as the engine's routed-rules arm.
The request is data; the hook rewrites data["model"] before dispatch."""
import re
from litellm.integrations.custom_logger import CustomLogger

HARD = re.compile(r"\b(code|sql|python|function|prove|derive|theorem|algorithm|probability|per (hour|day|week)|how (much|many))\b", re.I)

class RegexRouter(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        msgs = data.get("messages") or []
        user = [m for m in msgs if m.get("role") == "user"]
        text = user[-1].get("content", "") if user else ""
        data["model"] = "big" if HARD.search(text) else "small"
        return data

proxy_handler_instance = RegexRouter()
