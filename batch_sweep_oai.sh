#!/bin/bash
# API-judge N sweep: gpt-4o-mini judge, local chat backends, N in {20,50,100,200,400} at 8 rec/s.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
run() {
  local n=$1 tmo=$2
  local id="bs-oai-n${n}-r8"
  rm -rf "runs/$id"
  echo "[$(date +%H:%M:%S)] START $id"
  java -cp harness/pinned-sweep3.jar org.apache.flink.agents.eval.BatchedEvalJob \
    --run-id "$id" --requests-file workloads/requests.jsonl \
    --small qwen2.5:0.5b --big qwen2.5:0.5b --judge-model openai:gpt-4o-mini \
    --batch-size "$n" --batch-timeout-ms "$tmo" \
    --emit-rate 8 --batch-lanes 1 --parallelism 1 \
    --runs-dir runs >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$? routed=$(wc -l < runs/$id/batches.jsonl 2>/dev/null)"
}
run 20 300000
run 50 300000
run 100 300000
run 200 600000
run 400 900000
touch BATCH_SWEEP_OAI_DONE
echo "===== OAI N SWEEP COMPLETE ====="
