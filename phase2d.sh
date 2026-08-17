#!/bin/bash
# Stub-sweep re-run (waits for phase2c to finish first). Detach with nohup.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
JAR=harness/target/routing-eval-harness-0.1-shaded.jar

until [ -f PHASE2C_DONE ]; do sleep 30; done
echo "[$(date +%H:%M:%S)] phase2c done — starting stub sweep"

run() {
  local id=$1; shift
  echo "[$(date +%H:%M:%S)] START $id"
  local t0=$SECONDS
  java -jar $JAR --run-id "$id" --arm routed-rules --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  local rc=$?
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$rc wall=$((SECONDS-t0))s"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm routed-rules --requests workloads/requests.jsonl || true
}

for p in 1 2 4 8; do
  for rep in 1 2 3; do
    run "rq3sv2-p${p}-r${rep}" --requests-file workloads/rq3-400.jsonl \
        --small stub:200 --big stub:200 --parallelism $p
  done
done
touch PHASE2D_DONE
echo "===== PHASE 2D COMPLETE ====="
