#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
for t in 2 3 4 5 6; do
  ./phase3_trial.sh "rq4c-t$t" routed-judge >> phase3c.log 2>&1
done
touch PHASE3C_DONE
echo "===== PHASE 3C COMPLETE ====="
