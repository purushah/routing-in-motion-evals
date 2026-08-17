#!/bin/bash
# Waits for the anthropic jar build, verifies a live Sonnet smoke, then starts exp_anthropic.sh.
# Writes ANTHROPIC_SMOKE_FAILED and stops if the smoke does not pass.
set -uo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
: "${ANTHROPIC_API_KEY:-}"
# 1. wait for build (max 30 min)
for i in $(seq 1 180); do
  grep -q BUILD_OK build_anthropic.log 2>/dev/null && break
  sleep 10
done
grep -q BUILD_OK build_anthropic.log || { touch ANTHROPIC_BUILD_TIMEOUT; exit 1; }
# 2. live smoke: sonnet only, must answer as claude-sonnet-5 with no fallback
rm -rf runs/anth-smoke5
java -jar harness/pinned-anthropic.jar --run-id anth-smoke5 --arm always-small --smoke 2 \
  --small anthropic:claude-sonnet-5 --big anthropic:claude-sonnet-5 --runs-dir runs \
  > smoke_anthropic.log 2>&1
if grep -q '"model_name":"claude-sonnet-5"' runs/anth-smoke5/eventlog/*.log 2>/dev/null \
   && ! grep -q '"decision_source":"fallback"' runs/anth-smoke5/eventlog/*.log 2>/dev/null; then
  echo "smoke OK $(date +%H:%M:%S)" >> smoke_anthropic.log
  nohup ./exp_anthropic.sh > exp_anthropic.log 2>&1 & disown
else
  touch ANTHROPIC_SMOKE_FAILED
  exit 1
fi
