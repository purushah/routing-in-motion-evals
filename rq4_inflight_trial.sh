#!/bin/bash
# RQ4 IN-FLIGHT-kill trial: force backend calls to be genuinely in flight at the
# kill (slow counting backend + backpressure), then measure the at-least-once
# boundary the certified trials couldn't exercise: how many calls were in flight
# (backend-side resp_err), whether exactly those re-issue after restore, whether
# completed calls stay exactly-once, and whether re-issued calls keep their
# durably persisted decision (nondet coin-flip arm).
# Usage: ./rq4_inflight_trial.sh <trial-id>
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
TRIAL=$1
JAR=harness/pinned-rq4.jar
REQS=workloads/rq3-400.jsonl
LEDGER="$(pwd)/runs_$TRIAL-ledger.jsonl"
LATENCY=4
P=4
MODELS="--small proxy:count-small --big proxy:count-big --proxy-url http://localhost:4001/v1"
TOPIC="action-state-$TRIAL"
BACKEND="--state-backend kafka --state-topic $TOPIC"

rm -f "$LEDGER"
python3 infra/counting_backend.py --port 4001 --ledger "$LEDGER" --latency $LATENCY \
  > "runs_$TRIAL-backend.log" 2>&1 &
BPID=$!
sleep 2

echo "[$(date +%H:%M:%S)] trial $TRIAL latency=${LATENCY}s p=$P (expect ~$P calls in flight at kill)"
java -jar $JAR --run-id "$TRIAL" --arm routed-nondet --requests-file $REQS --runs-dir runs \
  $MODELS $BACKEND --checkpoint-interval 5000 --parallelism $P --emit-rate 2 \
  > "runs_$TRIAL.stdout.log" 2>&1 &
JPID=$!

TARGET=40
for i in $(seq 1 600); do
  N=$(cat runs/$TRIAL/eventlog/*.log 2>/dev/null | grep -c "_chat_response_event")
  [ "${N:-0}" -ge $TARGET ] && break
  kill -0 $JPID 2>/dev/null || { echo "job died early"; kill $BPID; exit 1; }
  sleep 2
done
KILL_TS=$(python3 -c "import time; print(time.time())")
kill -9 $JPID 2>/dev/null
echo "[$(date +%H:%M:%S)] KILLED at ${N} responses (kill_ts=$KILL_TS)"
sleep $((LATENCY + 2))   # let pending backend calls hit their broken pipes

CHK=$(for d in runs/$TRIAL/checkpoints/*/chk-*; do [ -f "$d/_metadata" ] && echo "$d"; done 2>/dev/null | sort -t- -k2 -n | tail -1)
[ -z "$CHK" ] && { echo "NO CHECKPOINT FOUND"; kill $BPID; exit 1; }
echo "[$(date +%H:%M:%S)] restoring from $CHK"
java -jar $JAR --run-id "$TRIAL-resume" --arm routed-nondet --requests-file $REQS --runs-dir runs \
  $MODELS $BACKEND --checkpoint-interval 5000 --parallelism $P --emit-rate 2 \
  --restore-from "$(pwd)/$CHK" > "runs_$TRIAL-resume.stdout.log" 2>&1
echo "[$(date +%H:%M:%S)] resume finished rc=$?"
kill $BPID 2>/dev/null

python3 analysis/inflight_join.py --ledger "$LEDGER" --kill-ts "$KILL_TS" \
  --pre "runs/$TRIAL" --post "runs/$TRIAL-resume" --requests workloads/requests.jsonl
