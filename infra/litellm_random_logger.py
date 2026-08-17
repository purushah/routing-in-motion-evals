"""Logs which real backend answered each request — ground truth for the divergence leg
that the alias deliberately hides from the engine."""
import json, os
from litellm.integrations.custom_logger import CustomLogger

class BackendLogger(CustomLogger):
    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        msgs = kwargs.get("messages") or []
        user = [m for m in msgs if m.get("role") == "user"]
        head = user[-1].get("content", "")[:60] if user else ""
        path = os.environ.get("BACKEND_LOG", "backend_log.jsonl")
        with open(path, "a") as f:
            f.write(json.dumps({"prompt_head": head, "model": kwargs.get("model", "")}) + "\n")

backend_logger = BackendLogger()
