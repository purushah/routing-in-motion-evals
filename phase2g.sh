#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
for p in 1 2 4 8; do
  for rep in 1 2 3; do
    id="rq3f-p${p}-r${rep}"
    echo "[$(date +%H:%M:%S)] START $id"
    java -jar harness/target/routing-eval-harness-0.1-shaded.jar --run-id "$id" --arm routed-rules \
      --requests-file workloads/rq3-400.jsonl --small stub:200 --big stub:200 \
      --parallelism $p --runs-dir runs >"runs_$id.stdout.log" 2>&1
    echo "[$(date +%H:%M:%S)] DONE  $id rc=$?"
  done
done
touch PHASE2G_DONE
echo "===== FINAL STUB SWEEP COMPLETE ====="
