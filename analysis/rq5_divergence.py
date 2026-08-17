#!/usr/bin/env python3
"""Divergence for the proxy arm: which real backend answered each prompt before vs after the
engine restart, per LiteLLM's own success-callback logs (the engine cannot see this — that IS
the finding; the logs exist only because we instrumented the proxy)."""
import json

def load(path):
    out = {}
    for line in open(path):
        if line.strip():
            r = json.loads(line)
            out[r["prompt_head"]] = r["model"]
    return out

pre, post = load("backend_pre.jsonl"), load("backend_post.jsonl")
common = sorted(set(pre) & set(post))
div = [p for p in common if pre[p] != post[p]]
print(json.dumps({"replayed": len(common), "diverged": len(div),
                  "rate": round(len(div) / len(common), 4) if common else None}))
