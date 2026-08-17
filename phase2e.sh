#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
until [ -f PHASE2D_DONE ]; do sleep 30; done
echo "[$(date +%H:%M:%S)] START rq2-judge-v4"
t0=$SECONDS
java -jar harness/target/routing-eval-harness-0.1-shaded.jar \
  --run-id rq2-judge-v4 --arm routed-judge --requests-file workloads/requests.jsonl \
  --small qwen2.5:0.5b --big qwen2.5:0.5b --judge-model qwen3:1.7b --runs-dir runs \
  > runs_rq2-judge-v4.stdout.log 2>&1
echo "[$(date +%H:%M:%S)] DONE rq2-judge-v4 wall=$((SECONDS-t0))s"
python3 analysis/parse_eventlog.py --run-dir runs/rq2-judge-v4 --arm routed-judge --requests workloads/requests.jsonl || true
touch PHASE2E_DONE
