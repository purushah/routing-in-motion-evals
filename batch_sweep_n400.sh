#!/bin/bash
# Addendum: N=400 probe (CAIS upper bound; likely near judge context ceiling — either
# outcome is a reportable datapoint). Chains after the main sweep.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
until [ -f BATCH_SWEEP_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] START bs-n400-r8"
java -cp harness/pinned-sweep.jar org.apache.flink.agents.eval.BatchedEvalJob \
  --run-id bs-n400-r8 --requests-file workloads/requests.jsonl \
  --small qwen2.5:0.5b --big qwen2.5:0.5b --judge-model qwen3:1.7b \
  --batch-size 400 --batch-timeout-ms 600000 \
  --emit-rate 8 --batch-lanes 1 --parallelism 1 \
  --runs-dir runs > runs_bs-n400-r8.stdout.log 2>&1
echo "[$(date +%H:%M:%S)] DONE rc=$? routed=$(wc -l < runs/bs-n400-r8/batches.jsonl 2>/dev/null)"
touch BATCH_SWEEP_N400_DONE
