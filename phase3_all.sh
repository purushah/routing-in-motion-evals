#!/bin/bash
# All RQ4 trials sequentially: 5 judge trials (kafka store) + 1 no-store control.
set -uo pipefail
cd "$(dirname "$0")"
for t in 2 3 4 5 6; do
  ./phase3_trial.sh "rq4b-t$t" routed-judge >> phase3_all.log 2>&1
done
./phase3_trial.sh rq4b-ctrl routed-nondet --no-store >> phase3_all.log 2>&1 || true
touch PHASE3_DONE
echo "===== PHASE 3 COMPLETE ====="
