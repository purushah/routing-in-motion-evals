#!/bin/bash
# RQ1: 6 arms x 1000 requests on OpenAI. Detached; sequential to respect rate limits.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
OA="--small openai:gpt-4o-mini --big openai:gpt-4o"
run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id"
  local t0=$SECONDS
  java -jar harness/target/routing-eval-harness-0.1-shaded.jar --run-id "$id" --arm "$arm" \
    --requests-file workloads/requests.jsonl --runs-dir runs $OA "$@" >"runs_$id.stdout.log" 2>&1
  local rc=$?
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$rc wall=$((SECONDS-t0))s"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/answers.jsonl || true
}
run rq1-small  always-small
run rq1-rules  routed-rules
run rq1-custom routed-custom
run rq1-mf     routed-mf
run rq1-judge  routed-judge --judge-model openai:gpt-4o-mini
run rq1-big    always-big
touch PHASE4_DONE
echo "===== PHASE 4 (RQ1) COMPLETE ====="
