#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
until [ -f PHASE3_DONE ]; do sleep 30; done
JAR=harness/pinned-phase3.jar
for T in rq4b-t2 rq4b-t3 rq4b-t4 rq4b-t5 rq4b-t6 rq4b-ctrl; do
  CHK=$(for d in runs/$T/checkpoints/*/chk-*; do [ -f "$d/_metadata" ] && echo "$d"; done 2>/dev/null | sort -t- -k2 -n | tail -1)
  [ -z "$CHK" ] && { echo "$T: no completed checkpoint"; continue; }
  ARM=routed-judge; BACKEND="--state-backend kafka --state-topic action-state-$T"
  [ "$T" = "rq4b-ctrl" ] && { ARM=routed-nondet; BACKEND=""; }
  echo "[$(date +%H:%M:%S)] resume $T from $CHK"
  java -jar $JAR --run-id "$T-res2" --arm $ARM --requests-file workloads/rq3-400.jsonl \
    --runs-dir runs --small qwen2.5:0.5b --big qwen3:1.7b \
    --judge-model qwen3:1.7b --judge-temperature 1.0 $BACKEND \
    --checkpoint-interval 5000 --parallelism 2 --emit-rate 2 \
    --restore-from "$(pwd)/$CHK" > "runs_$T-res2.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] done rc=$?"
  python3 analysis/recovery_join.py --pre "runs/$T" --post "runs/$T-res2" --requests workloads/requests.jsonl || true
done
touch RESUMES_DONE
