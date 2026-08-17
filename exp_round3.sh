#!/bin/bash
# Round-3 repeats: give every single-run Table II arm r2/r3 seeds (~$15).
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
: "${ANTHROPIC_API_KEY:-}"
JAR=harness/pinned-anthropic.jar
run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id"
  java -jar "$JAR" --run-id "$id" --arm "$arm" \
    --requests-file workloads/requests.jsonl --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$?"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/answers.jsonl || true
}
for seed in r2 r3; do
  run rq1w-nano-$seed       always-small --small openai:gpt-4.1-nano
  run rq1w-rules-mini-$seed routed-rules --small openai:gpt-4.1-nano --big openai:gpt-5-mini
  run rq1w-mf-$seed         routed-mf    --small openai:gpt-4.1-nano --big openai:gpt-5.1
  run rq1w-judge-$seed      routed-judge --small openai:gpt-4.1-nano --big openai:gpt-5.1 --judge-model openai:gpt-4o-mini
  run rq1a-haiku-$seed      always-small --small anthropic:claude-haiku-4-5 --big anthropic:claude-haiku-4-5
  run rq1a-sonnet-$seed     always-small --small anthropic:claude-sonnet-5 --big anthropic:claude-sonnet-5
  run rq1a-rules-xp-$seed   routed-rules --small openai:gpt-4.1-nano --big anthropic:claude-sonnet-5
done
touch EXP_ROUND3_DONE
echo "===== ROUND 3 REPEATS COMPLETE ====="
