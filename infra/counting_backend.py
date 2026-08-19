#!/usr/bin/env python3
"""OpenAI-compatible counting backend for the RQ4 invocation-ledger experiment.

Every /chat/completions call appends one JSONL record {ts, model, prompt_sha1} to the
ledger file BEFORE responding. The server is a separate process from the Flink job, so the
ledger survives engine kill/restore — giving backend-side ground truth on whether recovery
re-issued calls. Fixed 200 ms latency; deterministic reply.

Run: python3 infra/counting_backend.py [--port 4001] [--ledger /tmp/invocations.jsonl]
"""
import argparse
import hashlib
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=4001)
ap.add_argument("--ledger", default="/tmp/invocations.jsonl")
ap.add_argument("--latency", type=float, default=0.2, help="seconds per call")
args = ap.parse_args()


def ledger(rec):
    with open(args.ledger, "a") as fh:
        fh.write(json.dumps(rec) + "\n")
        fh.flush()


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        user = [m for m in body.get("messages", []) if m.get("role") == "user"]
        prompt = user[-1]["content"] if user else ""
        rec = {
            "ts": time.time(),
            "phase": "recv",
            "model": body.get("model", "?"),
            "prompt_sha1": hashlib.sha1(prompt.encode()).hexdigest(),
        }
        ledger(rec)
        time.sleep(args.latency)
        resp = {
            "id": "cnt-" + rec["prompt_sha1"][:12],
            "object": "chat.completion",
            "created": int(time.time()),
            "model": body.get("model", "counting"),
            "choices": [{
                "index": 0,
                "finish_reason": "stop",
                "message": {"role": "assistant",
                            "content": "counting backend reply. ANSWER: A"},
            }],
            "usage": {"prompt_tokens": 10, "completion_tokens": 8, "total_tokens": 18},
        }
        out = json.dumps(resp).encode()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
            ledger({**rec, "ts": time.time(), "phase": "resp"})
        except (BrokenPipeError, ConnectionResetError):
            # the client (the engine) died while this call was in flight
            ledger({**rec, "ts": time.time(), "phase": "resp_err"})

    def log_message(self, *a):
        pass


print(f"counting backend on :{args.port}, ledger={args.ledger}")
ThreadingHTTPServer(("127.0.0.1", args.port), H).serve_forever()
