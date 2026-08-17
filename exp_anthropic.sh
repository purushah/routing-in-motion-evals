#!/bin/bash
# Anthropic arms (third provider + cross-provider routing), queued behind exp_reviews.sh.
#   rq1a-haiku   : always Claude Haiku 4.5      (cheap-tier Claude baseline)
#   rq1a-sonnet  : always Claude Sonnet 5       (strong-tier Claude baseline)
#   rq1a-rules-xp: rules routing OpenAI nano <-> Claude Sonnet 5 (CROSS-PROVIDER arm)
# Waits for EXP_REVIEWS_DONE so the sequential API pacing is preserved.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
: "${ANTHROPIC_API_KEY:-}"
JAR=harness/pinned-anthropic.jar
while [ ! -f EXP_REVIEWS_DONE ]; do sleep 60; done
run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id"
  local t0=$SECONDS
  java -jar "$JAR" --run-id "$id" --arm "$arm" \
    --requests-file workloads/requests.jsonl --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  local rc=$?
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$rc wall=$((SECONDS-t0))s"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/answers.jsonl || true
}
run rq1a-haiku    always-small --small anthropic:claude-haiku-4-5 --big anthropic:claude-haiku-4-5
run rq1a-sonnet   always-small --small anthropic:claude-sonnet-5 --big anthropic:claude-sonnet-5
run rq1a-rules-xp routed-rules --small openai:gpt-4.1-nano --big anthropic:claude-sonnet-5
touch EXP_ANTHROPIC_DONE
echo "===== ANTHROPIC ARMS COMPLETE ====="
