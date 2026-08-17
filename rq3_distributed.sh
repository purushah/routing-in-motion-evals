#!/bin/bash
# RQ3-D: operator scaling on a real standalone Flink 2.3.0 cluster (1 JM + 4 TMs, separate
# JVMs, 2 slots each, checkpoints on). Same design as the MiniCluster sweep: 400 stub:200
# requests, routed-rules, p in 1/2/4/8, 3 reps. Throughput from the CLI's Job Runtime.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
FLINK=/Users/purushah/views/flink-agents/claude/flink-cluster/flink-2.3.0
EVAL=$(pwd)
for p in 1 2 4 8; do
  for rep in 1 2 3; do
    id="rq3d-p${p}-r${rep}"
    rm -rf "runs/$id"
    echo "[$(date +%H:%M:%S)] START $id"
    OUT=$($FLINK/bin/flink run -c org.apache.flink.agents.eval.EvalJob \
      "$EVAL/harness/pinned-cluster.jar" --run-id "$id" --arm routed-rules \
      --requests-file "$EVAL/workloads/rq3-400.jsonl" --small stub:200 --big stub:200 \
      --parallelism $p --checkpoint-interval 5000 --runs-dir "$EVAL/runs" 2>&1 | grep "Job Runtime")
    echo "$id $OUT"
  done
done
touch RQ3D_DONE
echo "===== DISTRIBUTED SWEEP COMPLETE ====="
