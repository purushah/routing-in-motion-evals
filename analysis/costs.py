#!/usr/bin/env python3
"""Aggregate cost + accuracy per arm from one or more graded results.csv files.

Usage: costs.py --runs runs/rq1-* [--prices analysis/prices.yaml]
Judge tokens (judge_prompt_tokens/judge_completion_tokens) are priced at the judge model's
rate (assumed = small model unless --judge-model given) and included in the arm's total.
"""
import argparse
import csv
import glob
import json


def load_prices(path):
    # minimal YAML reader for our flat file (avoids a yaml dependency)
    prices, current = {}, None
    for line in open(path):
        line = line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            current = line.rstrip(":").strip()
            prices[current] = {}
        else:
            k, v = line.strip().split(":")
            prices[current][k.strip()] = float(v)
    return prices


def price_for(prices, model):
    best, best_len = None, -1
    for name, p in prices.items():
        # longest matching prefix wins: "gpt-4o-mini" must not be billed as "gpt-4o"
        if name != "default" and model and model.startswith(name) and len(name) > best_len:
            best, best_len = p, len(name)
    return best if best else prices["default"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", nargs="+", required=True)
    ap.add_argument("--prices", default="analysis/prices.yaml")
    ap.add_argument("--judge-model", default="gpt-4o-mini")
    args = ap.parse_args()

    prices = load_prices(args.prices)
    arms = {}
    for pattern in args.runs:
        for run_dir in glob.glob(pattern):
            for row in csv.DictReader(open(f"{run_dir}/results.csv")):
                arm = row["arm"]
                a = arms.setdefault(
                    arm, {"n": 0, "correct": 0, "graded": 0, "usd": 0.0, "by_model": {}}
                )
                a["n"] += 1
                if row.get("graded_correct") not in ("", None):
                    a["graded"] += 1
                    a["correct"] += int(row["graded_correct"])
                model = row.get("model_name") or row.get("final_model") or ""
                p = price_for(prices, model)
                pt = float(row.get("prompt_tokens") or 0)
                ct = float(row.get("completion_tokens") or 0)
                a["usd"] += pt / 1e6 * p["input"] + ct / 1e6 * p["output"]
                a["by_model"][model] = a["by_model"].get(model, 0) + 1
                jp = float(row.get("judge_prompt_tokens") or 0)
                jc = float(row.get("judge_completion_tokens") or 0)
                if jp or jc:
                    jprice = price_for(prices, args.judge_model)
                    a["usd"] += jp / 1e6 * jprice["input"] + jc / 1e6 * jprice["output"]

    print(json.dumps(
        {
            arm: {
                "requests": a["n"],
                "accuracy": round(a["correct"] / a["graded"], 4) if a["graded"] else None,
                "usd_total": round(a["usd"], 4),
                "usd_per_1k": round(a["usd"] / a["n"] * 1000, 4) if a["n"] else None,
                "by_model": a["by_model"],
            }
            for arm, a in sorted(arms.items())
        },
        indent=2,
    ))


if __name__ == "__main__":
    main()
