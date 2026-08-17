#!/bin/bash
# RQ5 legs 2+3, working litellm venv + backend-truth logging.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
JAR=harness/pinned-phase5.jar
start_litellm() {
  (cd infra && .venv-litellm/bin/litellm --config "$1" --port 4000 > ../litellm.log 2>&1 &)
  for i in $(seq 1 60); do curl -s -m 2 http://localhost:4000/health/liveliness >/dev/null 2>&1 && return 0; sleep 2; done
  echo "LITELLM FAILED"; return 1
}
stop_litellm() { pkill -f "litellm --config" 2>/dev/null || true; sleep 3; }
run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id"
  java -jar $JAR --run-id "$id" --arm "$arm" --requests-file workloads/rq5-500.jsonl \
    --runs-dir runs "$@" > "runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE $id rc=$?"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/answers.jsonl || true
}
rm -rf runs/rq5-proxy runs/rq5-div-pre runs/rq5-div-post backend_pre.jsonl backend_post.jsonl
start_litellm litellm-policy.yaml || exit 1
run rq5-proxy always-small --small proxy:auto
stop_litellm
export BACKEND_LOG="$(pwd)/backend_pre.jsonl"
start_litellm litellm-random.yaml || exit 1
java -jar $JAR --run-id rq5-div-pre --arm always-small --requests-file workloads/rq5-500.jsonl \
  --runs-dir runs --small proxy:auto > runs_rq5-div-pre.stdout.log 2>&1 &
JPID=$!
for i in $(seq 1 600); do
  N=$(cat runs/rq5-div-pre/eventlog/*.log 2>/dev/null | grep -c "_chat_response_event")
  [ "${N:-0}" -ge 250 ] && break
  kill -0 $JPID 2>/dev/null || break
  sleep 2
done
kill -9 $JPID 2>/dev/null; sleep 3
stop_litellm
echo "div-pre killed at ${N:-?}"
export BACKEND_LOG="$(pwd)/backend_post.jsonl"
start_litellm litellm-random.yaml || exit 1
java -jar $JAR --run-id rq5-div-post --arm always-small --requests-file workloads/rq5-500.jsonl \
  --runs-dir runs --small proxy:auto > runs_rq5-div-post.stdout.log 2>&1
stop_litellm
python3 analysis/rq5_divergence.py > rq5_divergence.json
cat rq5_divergence.json
touch PHASE5C_DONE
echo "PHASE 5C COMPLETE"
