#!/bin/bash
# Batch sizing-at-rate sweep: N x lambda (+ lanes at the top rate), all local.
# Measures: window wait (batches.jsonl wait_ms), judge tokens/req, judge_ms,
# parse health (batches routed vs 1000), lane stability.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
JAR=harness/pinned-sweep.jar
run() {
  local id=$1 n=$2 rate=$3 lanes=$4 par=$5
  echo "[$(date +%H:%M:%S)] START $id (N=$n rate=$rate lanes=$lanes)"
  java -cp "$JAR" org.apache.flink.agents.eval.BatchedEvalJob \
    --run-id "$id" --requests-file workloads/requests.jsonl \
    --small qwen2.5:0.5b --big qwen2.5:0.5b --judge-model qwen3:1.7b \
    --batch-size "$n" --batch-timeout-ms 300000 \
    --emit-rate "$rate" --batch-lanes "$lanes" --parallelism "$par" \
    --runs-dir runs >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$? routed=$(wc -l < runs/$id/batches.jsonl 2>/dev/null)"
}
# N sweep at moderate rate (amortization + context ceiling)
for n in 20 50 100 200; do
  run "bs-n${n}-r8" "$n" 8 1 1
done
# rate sweep at N=20 (wait + stability)
for r in 2 32; do
  run "bs-n20-r${r}" 20 "$r" 1 1
done
# lanes at the top rate: single lane (expected to back up) vs 4 lanes
run "bs-n20-r32-l4" 20 32 4 4
touch BATCH_SWEEP_DONE
echo "===== BATCH SWEEP COMPLETE ====="
