#!/bin/bash
# RQ1 wide-gap regime: gpt-5-nano vs gpt-5.1 (high-end), 6 arms x 1000. Detached.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
OA="--small openai:gpt-4.1-nano --big openai:gpt-5.1"
run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id"
  local t0=$SECONDS
  java -jar harness/pinned-phase4b.jar --run-id "$id" --arm "$arm" \
    --requests-file workloads/requests.jsonl --runs-dir runs $OA "$@" >"runs_$id.stdout.log" 2>&1
  local rc=$?
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$rc wall=$((SECONDS-t0))s"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/answers.jsonl || true
}
run rq1w-nano   always-small
run rq1w-mini   always-small --small openai:gpt-5-mini
run rq1w-rules  routed-rules
run rq1w-mf     routed-mf
run rq1w-judge  routed-judge --judge-model openai:gpt-4o-mini
run rq1w-big    always-big
touch PHASE4B_DONE
echo "===== PHASE 4B (RQ1 wide regime) COMPLETE ====="
