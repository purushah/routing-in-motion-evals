#!/bin/bash
# Phase 2 final chunk. Run DETACHED (setsid nohup) — survives session task kills.
# 1) rq2-judge-v3: full judge arm, judge now self-retries and abstains on failure.
# 2) RQ3 stub sweep: operator scaling with a 200ms fixed-latency backend, p {1,2,4,8} x3.
# 3) RQ3 ollama saturation points: p4, p8 single rep (p1, p2 already measured).
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
JAR=harness/target/routing-eval-harness-0.1-shaded.jar

run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id"
  local t0=$SECONDS
  java -jar $JAR --run-id "$id" --arm "$arm" --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  local rc=$?
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$rc wall=$((SECONDS-t0))s"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
}

run rq2-judge-v3 routed-judge --requests-file workloads/requests.jsonl \
    --small qwen2.5:0.5b --big qwen2.5:0.5b --judge-model qwen3:1.7b

for p in 1 2 4 8; do
  for rep in 1 2 3; do
    run "rq3s-p${p}-r${rep}" routed-rules --requests-file workloads/rq3-400.jsonl \
        --small stub:200 --big stub:200 --parallelism $p
  done
done

for p in 4 8; do
  run "rq3-p${p}-r1" routed-rules --requests-file workloads/rq3-400.jsonl \
      --small qwen2.5:0.5b --big qwen3:1.7b --parallelism $p
done

touch PHASE2C_DONE
echo "===== PHASE 2C COMPLETE ====="
