#!/usr/bin/env python3
"""RouteLLM BERT router behind a tiny local HTTP endpoint.

The harness's MlRouterStrategy POSTs {"prompt": ...} to /route and gets back
{"win_rate": float, "threshold": float, "model": "strong"|"weak"}.

Run:  infra/.venv/bin/python infra/routellm_sidecar.py [--threshold 0.5] [--port 8765]
First run downloads the routellm/bert_gpt4_augmented checkpoint from HuggingFace.
"""
import argparse
import time

from flask import Flask, jsonify, request

parser = argparse.ArgumentParser()
parser.add_argument("--threshold", type=float, default=0.5)
parser.add_argument("--port", type=int, default=8765)
parser.add_argument("--router", default="bert", help="routellm router name (bert = fully local)")
parser.add_argument(
    "--checkpoint", default="routellm/bert_gpt4_augmented", help="HF checkpoint for the router"
)
args = parser.parse_args()

print(f"loading RouteLLM '{args.router}' router from {args.checkpoint} (first run downloads)...")
t0 = time.time()
from routellm.routers.routers import ROUTER_CLS  # noqa: E402

router = ROUTER_CLS[args.router](checkpoint_path=args.checkpoint)
print(f"router ready in {time.time() - t0:.1f}s; threshold={args.threshold}")

app = Flask(__name__)


@app.route("/route", methods=["POST"])
def route():
    prompt = request.get_json(force=True).get("prompt", "")
    t = time.time()
    win_rate = float(router.calculate_strong_win_rate(prompt))
    return jsonify(
        {
            "win_rate": win_rate,
            "threshold": args.threshold,
            "model": "strong" if win_rate >= args.threshold else "weak",
            "router": args.router,
            "latency_ms": round((time.time() - t) * 1000, 2),
        }
    )


@app.route("/health")
def health():
    return jsonify({"ok": True, "router": args.router, "threshold": args.threshold})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=args.port, threaded=True)
