#!/bin/bash
# One command per Phase 1 exit criteria: run an arm, parse its eventlog, grade it.
# Usage: ./run_arm.sh <run-id> <arm> <requests-file> [extra jar args...]
set -euo pipefail
cd "$(dirname "$0")"
RUN_ID=$1; ARM=$2; REQS=$3; shift 3
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
java -jar harness/target/routing-eval-harness-0.1-shaded.jar \
  --run-id "$RUN_ID" --arm "$ARM" --requests-file "$REQS" \
  --small qwen2.5:0.5b --big qwen3:1.7b --runs-dir runs "$@"
python3 analysis/parse_eventlog.py --run-dir "runs/$RUN_ID" --arm "$ARM" --requests workloads/requests.jsonl
python3 analysis/grade.py --run-dir "runs/$RUN_ID" --answers workloads/answers.jsonl
