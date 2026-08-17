#!/bin/bash
# Phase 2 driver: RQ2 (decision overhead) then RQ3 (parallelism sweep). All local Ollama.
# RQ2: both candidate names bind to the SAME model, so backend calls are identical across
# arms and e2e deltas isolate the decision step. n=1000 (full workload) per arm.
# RQ3: routed-rules with real small/big models, 400-request subset, parallelism {1,2,4,8} x2.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
JAR=harness/target/routing-eval-harness-0.1-shaded.jar
REQS=workloads/requests.jsonl
SAME="--small qwen2.5:0.5b --big qwen2.5:0.5b"

run() { # run-id arm extra...
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id ($arm) $*"
  local t0=$SECONDS
  java -jar $JAR --run-id "$id" --arm "$arm" --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  local rc=$?
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$rc wall=$((SECONDS-t0))s"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
}

echo "===== RQ2: decision overhead (identical backend) ====="
run rq2-direct always-small  --requests-file $REQS $SAME
run rq2-rules  routed-rules  --requests-file $REQS $SAME
run rq2-mf     routed-mf     --requests-file $REQS $SAME
run rq2-judge  routed-judge  --requests-file $REQS $SAME --judge-model qwen3:1.7b

echo "===== RQ3: parallelism sweep (routed-rules, real models, 400 reqs) ====="
head -400 workloads/requests.jsonl > workloads/rq3-400.jsonl
for p in 1 2 4 8; do
  for rep in 1 2; do
    run "rq3-p${p}-r${rep}" routed-rules --requests-file workloads/rq3-400.jsonl \
        --small qwen2.5:0.5b --big qwen3:1.7b --parallelism $p
  done
done
echo "===== PHASE 2 RUNS COMPLETE ====="
