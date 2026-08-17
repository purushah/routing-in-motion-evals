#!/bin/bash
# RQ1b pilot: 100 items per workload on the anchor models, to check the
# difficulty ladder exists before committing full runs (decision rule: proceed
# if big beats nano by >=3-4pts on either workload).
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${OPENAI_API_KEY:?set OPENAI_API_KEY in the environment}"
JAR=harness/pinned-anthropic.jar
run() {
  local id=$1 arm=$2 reqs=$3; shift 3
  echo "[$(date +%H:%M:%S)] START $id"
  java -jar "$JAR" --run-id "$id" --arm "$arm" \
    --requests-file "$reqs" --runs-dir runs "$@" >"runs_$id.stdout.log" 2>&1
  echo "[$(date +%H:%M:%S)] DONE  $id rc=$?"
  python3 analysis/parse_eventlog.py --run-dir "runs/$id" --arm "$arm" --requests "$reqs" || true
  python3 analysis/grade.py --run-dir "runs/$id" --answers workloads/rq1b-answers.jsonl || true
}
for wl in toxicchat banking77; do
  REQS=workloads/rq1b-$wl-pilot.jsonl
  run rq1b-$wl-pilot-nano always-small "$REQS" --small openai:gpt-4.1-nano
  run rq1b-$wl-pilot-big  always-big   "$REQS" --big openai:gpt-5.1
done
touch RQ1B_PILOT_DONE
echo "===== RQ1B PILOT COMPLETE ====="
