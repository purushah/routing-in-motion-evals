#!/bin/bash
# RQ4 RESCALED-restore trial: identical to rq4_trial.sh (kill -9 at ~half the
# requests, restore from the latest retained checkpoint) EXCEPT the restore runs
# at a different parallelism (2 -> 4), redistributing key groups across subtasks.
# Reviewer-requested: either the durable-call key scoping survives key-group
# redistribution (envelope extends) or this finds bug three.
# Usage: ./rq4_rescale_trial.sh <trial-id>
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
TRIAL=$1
JAR=harness/pinned-rq4.jar
REQS=workloads/rq3-400.jsonl
MODELS="--small qwen2.5:0.5b --big qwen3:1.7b"
JUDGE="--judge-model qwen3:1.7b --judge-temperature 1.0"
TOPIC="action-state-$TRIAL"
BACKEND="--state-backend kafka --state-topic $TOPIC"
P_PRE=2
P_POST=4

echo "[$(date +%H:%M:%S)] trial $TRIAL arm=routed-nondet p_pre=$P_PRE p_post=$P_POST"
java -jar $JAR --run-id "$TRIAL" --arm routed-nondet --requests-file $REQS --runs-dir runs \
  $MODELS $JUDGE $BACKEND --checkpoint-interval 5000 --parallelism $P_PRE --emit-rate 2 \
  > "runs_$TRIAL.stdout.log" 2>&1 &
JPID=$!

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
echo "[$(date +%H:%M:%S)] restoring from $CHK at parallelism $P_POST"
java -jar $JAR --run-id "$TRIAL-resume" --arm routed-nondet --requests-file $REQS --runs-dir runs \
  $MODELS $JUDGE $BACKEND --checkpoint-interval 5000 --parallelism $P_POST --emit-rate 2 \
  --restore-from "$(pwd)/$CHK" > "runs_$TRIAL-resume.stdout.log" 2>&1
echo "[$(date +%H:%M:%S)] resume finished rc=$?"

python3 analysis/recovery_join.py --pre "runs/$TRIAL" --post "runs/$TRIAL-resume" --requests workloads/requests.jsonl
