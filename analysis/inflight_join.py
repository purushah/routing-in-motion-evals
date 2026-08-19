#!/usr/bin/env python3
"""Join the in-flight-kill trial's three vantage points.

Backend ledger (phase records) gives ground truth: `resp_err` = the engine died while
the call was in flight. Cross-checks:
  1. in-flight calls re-issue after restore (at-least-once, by design);
  2. calls that completed AND were durably recorded stay exactly-once;
  3. re-issued calls keep the durably persisted routing decision (same model).
"""
import argparse
import glob
import json
from collections import Counter, defaultdict


def decisions(run_dir, prompt_to_id):
    req_wid, decided = {}, {}
    for f in glob.glob(f"{run_dir}/eventlog/*.log"):
        for line in open(f):
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            ev = rec.get("event", rec)
            t = rec.get("eventType") or ev.get("type") or ""
            attrs = ev.get("attributes", {})
            if t == "_chat_request_event":
                for m in attrs.get("messages") or []:
                    c = m.get("content")
                    if isinstance(c, dict):
                        c = (c.get("truncatedString") or "").removesuffix("...")
                    if isinstance(c, str) and c in prompt_to_id:
                        req_wid[str(ev.get("id"))] = prompt_to_id[c]
            elif t == "_model_routing_event" and attrs.get("decision_source") != "fallback":
                decided[str(attrs.get("request_id"))] = attrs.get("selected_model")
    return {req_wid[r]: m for r, m in decided.items() if r in req_wid}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--kill-ts", type=float, required=True)
    ap.add_argument("--pre", required=True)
    ap.add_argument("--post", required=True)
    ap.add_argument("--requests", required=True)
    args = ap.parse_args()

    prompt_to_id = {}
    for line in open(args.requests):
        if line.strip():
            r = json.loads(line)
            prompt_to_id[r["prompt"]] = r["id"]

    recs = [json.loads(l) for l in open(args.ledger) if l.strip()]
    pre_kill = [r for r in recs if r["ts"] <= args.kill_ts]
    in_flight = [r for r in recs if r["phase"] == "resp_err"]
    recv_by_key = Counter((r["prompt_sha1"]) for r in recs if r["phase"] == "recv")

    completed_pre = {
        r["prompt_sha1"] for r in pre_kill if r["phase"] == "resp"
    }
    inflight_keys = {r["prompt_sha1"] for r in in_flight}

    reissued = {k for k, n in recv_by_key.items() if n > 1}
    completed_reissued = completed_pre & reissued
    inflight_reissued = inflight_keys & reissued

    # decision stability on re-issued items
    pre_d = decisions(args.pre, prompt_to_id)
    post_d = decisions(args.post, prompt_to_id)
    # ledger keys are sha1 of prompt; map workload id -> sha1
    import hashlib

    wid_sha = {
        wid: hashlib.sha1(p.encode()).hexdigest() for p, wid in prompt_to_id.items()
    }
    diverged, kept = [], 0
    for wid in set(pre_d) & set(post_d):
        if wid_sha.get(wid) in reissued:
            if pre_d[wid] != post_d[wid]:
                diverged.append(wid)
            else:
                kept += 1

    print(
        json.dumps(
            {
                "ledger_recv_total": sum(recv_by_key.values()),
                "unique_prompts_invoked": len(recv_by_key),
                "in_flight_at_kill (resp_err)": len(in_flight),
                "reissued_prompts (recv>1)": len(reissued),
                "inflight_and_reissued": len(inflight_reissued),
                "completed_prekill_reissued (should be 0)": len(completed_reissued),
                "max_recv_per_prompt": max(recv_by_key.values()) if recv_by_key else 0,
                "reissued_decision_kept": kept,
                "reissued_decision_diverged": len(diverged),
                "diverged_items": diverged[:10],
                "double_billed_tokens_upper_bound": 18 * sum(
                    n - 1 for n in recv_by_key.values() if n > 1
                ),
            },
            indent=1,
        )
    )


if __name__ == "__main__":
    main()
