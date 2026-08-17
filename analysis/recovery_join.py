#!/usr/bin/env python3
"""RQ4 divergence analysis: join routing decisions across a kill/restore boundary.

Joins by workload item (prompt -> ChatRequestEvent -> its routing decision via request_id),
so it is robust even if event ids are regenerated on replay. Items decided BOTH before the
kill and after the restore are the replayed set; a divergence is a different selected_model.
"""
import argparse
import glob
import json


def decisions(run_dir, prompt_to_id):
    req_prompt, decided = {}, {}
    for f in glob.glob(f"{run_dir}/eventlog/*.log"):
        for line in open(f):
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            ev = rec.get("event", {})
            attrs = ev.get("attributes", {})
            t = rec.get("eventType")
            if t == "_chat_request_event":
                msgs = attrs.get("messages") or []
                user = [m for m in msgs if str(m.get("role", "")).lower() == "user"]
                if user:
                    wid = prompt_to_id.get(user[-1].get("content", ""))
                    if wid:
                        req_prompt[str(ev.get("id"))] = wid
            elif t == "_model_routing_event" and attrs.get("decision_source") != "fallback":
                decided[str(attrs.get("request_id"))] = attrs.get("selected_model")
    return {req_prompt[r]: m for r, m in decided.items() if r in req_prompt}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pre", required=True)
    ap.add_argument("--post", required=True)
    ap.add_argument("--requests", required=True)
    args = ap.parse_args()

    prompt_to_id = {}
    for line in open(args.requests):
        if line.strip():
            r = json.loads(line)
            prompt_to_id[r["prompt"]] = r["id"]

    pre = decisions(args.pre, prompt_to_id)
    post = decisions(args.post, prompt_to_id)
    replayed = sorted(set(pre) & set(post))
    diverged = [w for w in replayed if pre[w] != post[w]]
    print(
        json.dumps(
            {
                "decided_pre_kill": len(pre),
                "decided_post_restore": len(post),
                "replayed_decisions": len(replayed),
                "diverged": len(diverged),
                "divergence_rate": round(len(diverged) / len(replayed), 4) if replayed else None,
                "diverged_items": diverged[:20],
            },
            indent=1,
        )
    )


if __name__ == "__main__":
    main()
