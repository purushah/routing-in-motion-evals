#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
until [ -f PHASE2E_DONE ]; do sleep 30; done
echo "[$(date +%H:%M:%S)] judge-v4 done — stub sweep v3"
run() {
  local id=$1; shift
  echo "[$(date +%H:%M:%S)] START $id"
  java -jar harness/target/routing-eval-harness-0.1-shaded.jar --run-id "$id" --arm routed-rules \
    --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$?"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm routed-rules --requests workloads/requests.jsonl || true
}
for p in 1 2 4 8; do
  for rep in 1 2 3; do
    run "rq3sv3-p${p}-r${rep}" --requests-file workloads/rq3-400.jsonl \
        --small stub:200 --big stub:200 --parallelism $p
  done
done
touch PHASE2F_DONE
echo "===== PHASE 2F COMPLETE ====="
