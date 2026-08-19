#!/bin/bash
# Store-write cost isolation (reviewer ask): identical routed-nondet runs against a
# fixed-latency stub backend (200 ms), with and without the Kafka action-state store.
# The end-to-end delta isolates the durable machinery's per-request cost (2 durable
# calls/request: route + chat). Parallelism 1, unthrottled source, 400 items, 3 repeats.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
JAR=harness/pinned-rq4.jar
REQS=workloads/rq3-400.jsonl
MODELS="--small stub:200 --big stub:200"

run() {
  local id=$1; shift
  java -jar $JAR --run-id "$id" --arm routed-nondet --requests-file $REQS --runs-dir runs \
    $MODELS --parallelism 1 "$@" > "runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] $id rc=$?"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm routed-nondet --requests $REQS >/dev/null
}
for r in 1 2 3; do
  run sw-off-$r
  run sw-on-$r --state-backend kafka --state-topic action-state-sw-$r --checkpoint-interval 5000
done
echo "STOREWRITE RUNS DONE"
