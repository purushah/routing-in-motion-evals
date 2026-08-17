#!/usr/bin/env python3
"""Assemble the paper's supplementary-material bundle.

Produces supplement/ (and supplement.tar.gz) containing everything needed to reproduce or
audit the evaluation:
  code/       harness source + pom, analysis scripts, sidecar, run drivers
  workloads/  requests.jsonl, answers.jsonl, generator (exact evaluated inputs, seed 42)
  configs/    prices.yaml, calibrated RouteLLM threshold, infra configs
  data/       per-run results.csv + compressed raw eventlogs + run-index.csv
  README.md   inventory + how-to-reproduce

Safety: refuses to include any file containing the OpenAI key; strips env-dependent paths.
Re-run any time — deterministic layout, overwrites in place. Backfills a manifest.json for
every run from its results.csv (arm, n, models seen, first/last timestamps).
"""
import csv
import glob
import gzip
import json
import os
import shutil
import subprocess
import sys

EVAL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUP = os.path.join(EVAL, "supplement")

# Used only to scrub the key from any archived file, should it ever appear.
KEY = os.environ.get("OPENAI_API_KEY", "")


def guard(path):
    """Never ship a file containing the API key."""
    if not KEY:
        return True
    try:
        return KEY not in open(path, errors="ignore").read()
    except (OSError, UnicodeDecodeError):
        return True


def copy(src, dst_rel):
    dst = os.path.join(SUP, dst_rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not guard(src):
        print(f"REFUSING (contains key): {src}", file=sys.stderr)
        return
    shutil.copy2(src, dst)


def main():
    shutil.rmtree(SUP, ignore_errors=True)

    # code
    for f in glob.glob(f"{EVAL}/harness/src/main/java/**/*.java", recursive=True):
        copy(f, "code/harness/" + os.path.relpath(f, f"{EVAL}/harness"))
    copy(f"{EVAL}/harness/pom.xml", "code/harness/pom.xml")
    for f in glob.glob(f"{EVAL}/analysis/*.py") + glob.glob(f"{EVAL}/*.sh"):
        copy(f, "code/" + os.path.basename(f))
    copy(f"{EVAL}/infra/routellm_sidecar.py", "code/routellm_sidecar.py")
    copy(f"{EVAL}/infra/requirements.txt", "configs/requirements.txt")

    # workloads + configs
    for name in ["requests.jsonl", "answers.jsonl", "smoke.jsonl", "make_workload.py"]:
        p = f"{EVAL}/workloads/{name}"
        if os.path.exists(p):
            copy(p, f"workloads/{name}")
    copy(f"{EVAL}/analysis/prices.yaml", "configs/prices.yaml")
    if os.path.exists(f"{EVAL}/infra/calibrated_threshold.txt"):
        copy(f"{EVAL}/infra/calibrated_threshold.txt", "configs/calibrated_threshold.txt")
    copy(f"{EVAL}/PLAN.md", "PLAN.md")

    # data: per-run results + manifests + gzipped eventlogs; index of all runs
    index = []
    for run_dir in sorted(glob.glob(f"{EVAL}/runs/*")):
        run = os.path.basename(run_dir)
        rcsv = os.path.join(run_dir, "results.csv")
        if not os.path.exists(rcsv):
            continue
        rows = list(csv.DictReader(open(rcsv)))
        if not rows:
            continue
        models = sorted({r.get("model_name", "") for r in rows if r.get("model_name")})
        arm = rows[0].get("arm", "")
        manifest = {
            "run_id": run,
            "arm": arm,
            "requests": len(rows),
            "models_seen": models,
            "graded": sum(1 for r in rows if r.get("graded_correct") not in ("", None)),
        }
        json.dump(manifest, open(os.path.join(run_dir, "manifest.json"), "w"), indent=1)
        copy(rcsv, f"data/runs/{run}/results.csv")
        copy(os.path.join(run_dir, "manifest.json"), f"data/runs/{run}/manifest.json")
        for log in glob.glob(os.path.join(run_dir, "eventlog", "*.log")):
            if not guard(log):
                continue
            dst = os.path.join(SUP, f"data/runs/{run}/eventlog/{os.path.basename(log)}.gz")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(log, "rb") as fi, gzip.open(dst, "wb") as fo:
                shutil.copyfileobj(fi, fo)
        index.append(manifest)

    with open(os.path.join(SUP, "data/run-index.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["run_id", "arm", "requests", "graded", "models_seen"])
        w.writeheader()
        for m in index:
            w.writerow({**m, "models_seen": ";".join(m["models_seen"])})

    commit = subprocess.run(
        ["git", "-C", os.path.join(EVAL, "../../flink-agents"), "rev-parse", "HEAD"],
        capture_output=True, text=True).stdout.strip()
    open(os.path.join(SUP, "README.md"), "w").write(f"""# Supplementary material: Routing in Motion

Evaluation of model routing as a durable, observable streaming operator in Apache Flink Agents
(branch model-routing-v1, commit {commit or 'see PLAN.md'}).

- code/       eval harness (Java, shaded-jar runner), analysis scripts, RouteLLM sidecar
- workloads/  the exact evaluated inputs: 1,000 requests (500 GSM8K / 350 MMLU / 150 HumanEval,
              seed 42) + grading answers + generator script
- configs/    token prices used for cost accounting (pinned), calibrated RouteLLM threshold
- data/       one directory per run: results.csv (per-request join of the engine's EventLog),
              manifest.json, and the raw EventLog JSONL (gzipped). run-index.csv inventories all runs.

Reproduce: build the harness (mvn package), start Ollama / the RouteLLM sidecar, then
`./run_arm.sh <run-id> <arm> workloads/requests.jsonl` (see code/*.sh and PLAN.md).
No API keys or credentials are included; OpenAI runs require OPENAI_API_KEY.
""")

    subprocess.run(["tar", "czf", os.path.join(EVAL, "supplement.tar.gz"), "-C", EVAL, "supplement"])
    size = os.path.getsize(os.path.join(EVAL, "supplement.tar.gz")) / 1e6
    print(f"supplement/: {len(index)} runs indexed; supplement.tar.gz = {size:.1f} MB")


if __name__ == "__main__":
    main()
