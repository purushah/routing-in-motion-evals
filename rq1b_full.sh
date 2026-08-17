#!/bin/bash
# RQ1b full runs, single seed: streaming-native workloads (ToxicChat moderation,
# Banking77 intent triage). Anchors nano/mini/big + judge-routed arm.
# Parallelism 8: gpt-5.1 takes ~55s/item on the 77-intent prompts (91min/100 seq).
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
JAR=harness/pinned-anthropic.jar
run() {
  local id=$1 arm=$2 reqs=$3; shift 3
  echo "[$(date +%H:%M:%S)] START $id"
  java -jar "$JAR" --run-id "$id" --arm "$arm" \
    --requests-file "$reqs" --runs-dir runs --parallelism 8 "$@" >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$?"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests "$reqs" || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/rq1b-answers.jsonl || true
}
TC=workloads/rq1b-toxicchat.jsonl
B77=workloads/rq1b-banking77.jsonl
run rq1b-tc-nano   always-small "$TC"  --small openai:gpt-4.1-nano
run rq1b-tc-mini   always-small "$TC"  --small openai:gpt-5-mini
run rq1b-tc-big    always-big   "$TC"  --big openai:gpt-5.1
run rq1b-tc-judge  routed-judge "$TC"  --small openai:gpt-4.1-nano --big openai:gpt-5.1 --judge-model openai:gpt-4o-mini
run rq1b-b77-nano  always-small "$B77" --small openai:gpt-4.1-nano
run rq1b-b77-mini  always-small "$B77" --small openai:gpt-5-mini
run rq1b-b77-big   always-big   "$B77" --big openai:gpt-5.1
run rq1b-b77-judge routed-judge "$B77" --small openai:gpt-4.1-nano --big openai:gpt-5.1 --judge-model openai:gpt-4o-mini
touch RQ1B_FULL_DONE
echo "===== RQ1B FULL (single seed) COMPLETE ====="
