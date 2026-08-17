#!/bin/bash
# Phase 2 remainder: rerun the two RQ2 arms that died on Ollama timeouts (now with framework
# retries enabled), then the rest of the RQ3 sweep (p1-r1 already complete).
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
JAR=harness/target/routing-eval-harness-0.1-shaded.jar
REQS=workloads/requests.jsonl
SAME="--small qwen2.5:0.5b --big qwen2.5:0.5b"

run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id ($arm)"
  local t0=$SECONDS
  java -jar $JAR --run-id "$id" --arm "$arm" --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$? wall=$((SECONDS-t0))s"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
}

echo "===== RQ2 reruns (with retries) ====="
run rq2-direct-v2 always-small --requests-file $REQS $SAME
run rq2-judge-v2  routed-judge --requests-file $REQS $SAME --judge-model qwen3:1.7b

echo "===== RQ3 sweep remainder ====="
run rq3-p1-r2 routed-rules --requests-file workloads/rq3-400.jsonl --small qwen2.5:0.5b --big qwen3:1.7b --parallelism 1
for p in 2 4 8; do
  for rep in 1 2; do
    run "rq3-p${p}-r${rep}" routed-rules --requests-file workloads/rq3-400.jsonl \
        --small qwen2.5:0.5b --big qwen3:1.7b --parallelism $p
  done
done
echo "===== PHASE 2B COMPLETE ====="
