#!/usr/bin/env python3
"""EventLog JSONL -> per-request results.csv for one run.

Usage: parse_eventlog.py --run-dir runs/<run-id> --arm <arm> [--requests workloads/requests.jsonl]

Joins ChatRequestEvent / ModelRoutingEvent(s) / ChatResponseEvent by request_id; maps each
request back to its workload item by exact prompt match (workload prompts are unique).
Columns: request_id, workload_id, slice, arm, selected_model, final_model, decision_source,
decision_ms, fallback_attempted, judge_prompt_tokens, judge_completion_tokens, win_rate,
prompt_tokens, completion_tokens, model_name, e2e_ms, answer
"""
import argparse
import csv
import glob
import json
import os
import sys
from datetime import datetime


def ts_ms(ts):
    if ts is None:
        return None
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp() * 1000.0
    except ValueError:
        return None


def load_events(run_dir):
    events = []
    for f in sorted(glob.glob(os.path.join(run_dir, "eventlog", "*.log"))):
        with open(f) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return events


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--arm", required=True)
    ap.add_argument("--requests", default=None, help="requests.jsonl for workload-id mapping")
    ap.add_argument("--after", default=None, help="ISO ts: ignore events before this (decontamination)")
    args = ap.parse_args()
    cutoff = ts_ms(args.after) if args.after else None

    prompt_to_item = {}
    if args.requests:
        with open(args.requests) as fh:
            for line in fh:
                if line.strip():
                    row = json.loads(line)
                    prompt_to_item[row["prompt"]] = (row["id"], row["slice"])

    rows = {}  # request_id -> row dict
    for rec in load_events(args.run_dir):
        ev = rec.get("event", rec)
        etype = rec.get("eventType") or ev.get("type") or ""
        attrs = ev.get("attributes", {})
        ts = rec.get("timestamp") or rec.get("timeMillis")
        if cutoff and ts and (ts_ms(ts) or 0) < cutoff:
            continue

        if etype == "_chat_request_event":
            rid = str(ev.get("id"))
            row = rows.setdefault(rid, {"request_id": rid, "arm": args.arm})
            row["t_request"] = ts_ms(ts)
            msgs = attrs.get("messages") or []
            user = [m for m in msgs if str((m or {}).get("role", "")).lower() == "user"]
            if user:
                prompt = user[-1].get("content", "")
                if isinstance(prompt, dict):
                    # event-log truncation wraps long strings:
                    # {"truncatedString": "<prefix>...", "omittedChars": M}
                    prompt = (prompt.get("truncatedString") or "").removesuffix("...")
                    hits = [v for k, v in prompt_to_item.items() if k.startswith(prompt)]
                    wid, sl = hits[0] if len(hits) == 1 else ("", "")
                else:
                    wid, sl = prompt_to_item.get(prompt, ("", ""))
                row["workload_id"], row["slice"] = wid, sl

        elif etype == "_model_routing_event":
            rid = str(attrs.get("request_id"))
            row = rows.setdefault(rid, {"request_id": rid, "arm": args.arm})
            source = attrs.get("decision_source")
            if source == "fallback":
                row["fallback_attempted"] = True
                row["final_model"] = attrs.get("selected_model")
            else:
                row["selected_model"] = attrs.get("selected_model")
                row["decision_source"] = source
                row["decision_ms"] = attrs.get("decision_ms")
                md = attrs.get("metadata") or {}
                row["judge_prompt_tokens"] = md.get("judge_prompt_tokens")
                row["judge_completion_tokens"] = md.get("judge_completion_tokens")
                row["win_rate"] = attrs.get("score")

        elif etype == "_chat_response_event":
            rid = str(attrs.get("request_id"))
            row = rows.setdefault(rid, {"request_id": rid, "arm": args.arm})
            row["t_response"] = ts_ms(ts)
            resp = attrs.get("response") or {}
            extra = resp.get("extra_args") or {}
            row["prompt_tokens"] = extra.get("promptTokens")
            row["completion_tokens"] = extra.get("completionTokens")
            row["model_name"] = extra.get("model_name")
            routing = extra.get("model_routing") or {}
            if routing.get("final_model"):
                row["final_model"] = routing.get("final_model")
            content = resp.get("content")
            if not isinstance(content, str):
                content = json.dumps(content) if content is not None else ""
            row["answer"] = content[:4000]

    out = os.path.join(args.run_dir, "results.csv")
    cols = [
        "request_id", "workload_id", "slice", "arm", "selected_model", "final_model",
        "decision_source", "decision_ms", "fallback_attempted", "judge_prompt_tokens",
        "judge_completion_tokens", "win_rate", "prompt_tokens", "completion_tokens",
        "model_name", "e2e_ms", "answer",
    ]
    n = 0
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for row in rows.values():
            if "t_request" in row and "t_response" in row and row.get("t_request") and row.get("t_response"):
                row["e2e_ms"] = row["t_response"] - row["t_request"]
            row.setdefault("final_model", row.get("selected_model") or row.get("model_name"))
            w.writerow(row)
            n += 1
    print(f"wrote {out}: {n} requests")
    if n == 0:
        sys.exit("ERROR: no requests parsed — check eventlog dir")


if __name__ == "__main__":
    main()
