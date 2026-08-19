#!/bin/bash
# Determinism 2x2 completion: a content-keyed hash split (sticky A/B) across kill/restore
# WITHOUT the action-state store. Expectation: 0% divergence purely by determinism —
# the cell that shows which routing class actually needs the durable record.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
TRIAL=$1
JAR=harness/target/routing-eval-harness-0.1-shaded.jar
REQS=workloads/rq3-400.jsonl
MODELS="--small proxy:count-small --big proxy:count-big --proxy-url http://localhost:4001/v1"
LEDGER="$(pwd)/runs_$TRIAL-ledger.jsonl"; rm -f "$LEDGER"
python3 infra/counting_backend.py --port 4001 --ledger "$LEDGER" --latency 1 > "runs_$TRIAL-backend.log" 2>&1 &
BPID=$!; sleep 2; trap 'kill $BPID 2>/dev/null' EXIT

java -jar $JAR --run-id "$TRIAL" --arm routed-hashsplit --requests-file $REQS --runs-dir runs \
  $MODELS --escalate-percent 50 --checkpoint-interval 20000 --parallelism 2 --emit-rate 2 \
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
echo "restoring from $CHK (NO action-state store)"
java -jar $JAR --run-id "$TRIAL-resume" --arm routed-hashsplit --requests-file $REQS --runs-dir runs \
  $MODELS --escalate-percent 50 --checkpoint-interval 20000 --parallelism 2 --emit-rate 2 \
  --restore-from "$(pwd)/$CHK" > "runs_$TRIAL-resume.stdout.log" 2>&1
echo "resume rc=$?"
python3 analysis/recovery_join.py --pre "runs/$TRIAL" --post "runs/$TRIAL-resume" --requests workloads/requests.jsonl
