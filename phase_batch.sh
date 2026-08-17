#!/bin/bash
# Windowed batch-routing arm: 1000 requests, ONE judge call per 20. Comparable to
# rq2-judge-v4 (same candidate models, same judge, per-request). Waits for the recovery
# trials to release ollama.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
until [ -f RESUMES_DONE ]; do sleep 60; done
echo "[$(date +%H:%M:%S)] START rq2-judge-batched"
java -cp harness/target/routing-eval-harness-0.1-shaded.jar \
  org.apache.flink.agents.eval.BatchedEvalJob \
  --run-id rq2-judge-batched --requests-file workloads/requests.jsonl \
  --small qwen2.5:0.5b --big qwen2.5:0.5b --judge-model qwen3:1.7b \
  --batch-size 20 --batch-timeout-ms 5000 --runs-dir runs \
  > runs_rq2-judge-batched.stdout.log 2>&1
echo "[$(date +%H:%M:%S)] DONE rc=$?"
touch PHASE_BATCH_DONE
