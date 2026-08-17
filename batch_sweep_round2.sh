#!/bin/bash
# Round 2: re-run N>=50 with 900s judge timeout (pinned-sweep2.jar), after the main sweep.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
until [ -f BATCH_SWEEP_DONE ] && [ -f harness/pinned-sweep2.jar ]; do sleep 60; done
run() {
  local id=$1 n=$2 tmo=$3
  rm -rf "runs/$id"
  echo "[$(date +%H:%M:%S)] START $id (N=$n)"
  java -cp harness/pinned-sweep2.jar org.apache.flink.agents.eval.BatchedEvalJob \
    --run-id "$id" --requests-file workloads/requests.jsonl \
    --small qwen2.5:0.5b --big qwen2.5:0.5b --judge-model qwen3:1.7b \
    --batch-size "$n" --batch-timeout-ms "$tmo" \
    --emit-rate 8 --batch-lanes 1 --parallelism 1 \
    --runs-dir runs >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$? routed=$(wc -l < runs/$id/batches.jsonl 2>/dev/null)"
}
run bs-n50-r8  50  300000
run bs-n100-r8 100 600000
run bs-n200-r8 200 600000
run bs-n400-r8 400 900000
touch BATCH_SWEEP_ROUND2_DONE
echo "===== ROUND 2 COMPLETE ====="
