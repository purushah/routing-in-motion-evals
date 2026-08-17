#!/bin/bash
# Reviewer-driven cheap experiments (Aug 2026):
#   A. mini-in-candidate-set: routed-rules with nano <-> gpt-5-mini (answers "why not just pin mini?")
#   B. repeats r2/r3 of rules/big/mini arms (CIs for the headline comparison + tier-inversion cost)
#   C. temperature-equalized nano + rules at T=1.0 (kills the confound under the headline)
# Sequential, detached; marker file EXP_REVIEWS_DONE on completion.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
JAR=harness/pinned-exp.jar
OA="--small openai:gpt-4.1-nano --big openai:gpt-5.1"
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
# --- A: the dominant model inside the candidate set ---
run rq1w-rules-mini routed-rules --small openai:gpt-4.1-nano --big openai:gpt-5-mini
# --- B: repeats for CIs on the headline arms ---
run rq1w-rules-r2 routed-rules $OA
run rq1w-big-r2   always-big   $OA
run rq1w-rules-r3 routed-rules $OA
run rq1w-big-r3   always-big   $OA
run rq1w-mini-r2  always-small --small openai:gpt-5-mini
run rq1w-mini-r3  always-small --small openai:gpt-5-mini
# --- C: temperature-equalized (non-gpt-5 arms at T=1.0) ---
run rq1w-nano-t1  always-small --small openai:gpt-4.1-nano --temperature 1.0
run rq1w-rules-t1 routed-rules $OA --temperature 1.0
touch EXP_REVIEWS_DONE
echo "===== REVIEWER EXPERIMENTS COMPLETE ====="
