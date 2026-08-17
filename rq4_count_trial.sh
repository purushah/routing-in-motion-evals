#!/bin/bash
# One RQ4 recovery trial: start a routed run with the Kafka durable store + 5s checkpoints,
# kill -9 at ~half the requests, restore from the latest retained checkpoint, then compare
# routing decisions per workload item across the kill boundary.
# Usage: ./phase3_trial.sh <trial-id> <arm> [--no-store]   (arm: routed-judge | routed-nondet)
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
TRIAL=$1; ARM=$2; STORE_FLAG=${3:-}
JAR=harness/pinned-rq4.jar
REQS=workloads/rq3-400.jsonl
MODELS="--small proxy:count-small --big proxy:count-big --proxy-url http://localhost:4001/v1"
JUDGE=""
TOPIC="action-state-$TRIAL"
BACKEND="--state-backend kafka --state-topic $TOPIC"
[ "$STORE_FLAG" = "--no-store" ] && BACKEND=""

echo "[$(date +%H:%M:%S)] trial $TRIAL arm=$ARM store=${BACKEND:+kafka}${BACKEND:-DISABLED}"
java -jar $JAR --run-id "$TRIAL" --arm "$ARM" --requests-file $REQS --runs-dir runs \
  $MODELS $JUDGE $BACKEND --checkpoint-interval 5000 --parallelism 2 --emit-rate 2 \
  > "runs_$TRIAL.stdout.log" 2>&1 &
JPID=$!

# wait for ~half the responses, then kill -9
TARGET=200
for i in $(seq 1 600); do
  N=$(cat runs/$TRIAL/eventlog/*.log 2>/dev/null | grep -c "_chat_response_event")
  [ "${N:-0}" -ge $TARGET ] && break
  kill -0 $JPID 2>/dev/null || { echo "job died early"; exit 1; }
  sleep 2
done
kill -9 $JPID 2>/dev/null
echo "[$(date +%H:%M:%S)] KILLED at ${N} responses"
sleep 3

CHK=$(for d in runs/$TRIAL/checkpoints/*/chk-*; do [ -f "$d/_metadata" ] && echo "$d"; done 2>/dev/null | sort -t- -k2 -n | tail -1)
[ -z "$CHK" ] && { echo "NO CHECKPOINT FOUND"; exit 1; }
echo "[$(date +%H:%M:%S)] restoring from $CHK"
java -jar $JAR --run-id "$TRIAL-resume" --arm "$ARM" --requests-file $REQS --runs-dir runs \
  $MODELS $JUDGE $BACKEND --checkpoint-interval 5000 --parallelism 2 --emit-rate 2 \
  --restore-from "$(pwd)/$CHK" > "runs_$TRIAL-resume.stdout.log" 2>&1
echo "[$(date +%H:%M:%S)] resume finished rc=$?"

python3 analysis/recovery_join.py --pre "runs/$TRIAL" --post "runs/$TRIAL-resume" --requests workloads/requests.jsonl
