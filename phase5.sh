#!/bin/bash
# RQ5: LiteLLM proxy vs in-engine routing. Waits for phase4b, then:
#  1) arm B (ours): routed-rules on nano/5.1 direct, 500 reqs
#  2) arm A (proxy): engine pinned to LiteLLM w/ SAME regex policy, 500 reqs
#  3) divergence: LiteLLM random mode; kill engine at ~250, fresh restart, compare pre/post
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
JAR=harness/pinned-phase5.jar
until [ -f PHASE4B_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] phase4b done — starting RQ5"
head -500 workloads/requests.jsonl > workloads/rq5-500.jsonl

run() {
  local id=$1 arm=$2; shift 2
  echo "[$(date +%H:%M:%S)] START $id"
  java -jar $JAR --run-id "$id" --arm "$arm" --requests-file workloads/rq5-500.jsonl \
    --runs-dir runs "$@" > "runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$?"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests workloads/requests.jsonl || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/answers.jsonl || true
}

start_litellm() {
  (cd infra && ../infra/.venv/bin/litellm --config "$1" --port 4000 > ../litellm.log 2>&1 &)
  for i in $(seq 1 60); do curl -s -m 2 http://localhost:4000/health/liveliness >/dev/null 2>&1 && return 0; sleep 2; done
  echo "LITELLM FAILED TO START"; tail -5 litellm.log; return 1
}
stop_litellm() { pkill -f "litellm --config" 2>/dev/null || true; sleep 3; }

# 1) ours
run rq5-ours routed-rules --small openai:gpt-4.1-nano --big openai:gpt-5.1

# 2) proxy, same policy
start_litellm litellm-policy.yaml
run rq5-proxy always-small --small proxy:auto
stop_litellm

# 3) divergence: random proxy, kill engine at ~250, fresh restart
start_litellm litellm-random.yaml
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
echo "[$(date +%H:%M:%S)] div-pre killed at ${N:-?}"
java -jar $JAR --run-id rq5-div-post --arm always-small --requests-file workloads/rq5-500.jsonl \
  --runs-dir runs --small proxy:auto > runs_rq5-div-post.stdout.log 2>&1
stop_litellm
python3 analysis/rq5_divergence.py > rq5_divergence.json 2>&1 || true
touch PHASE5_DONE
echo "===== PHASE 5 COMPLETE ====="
