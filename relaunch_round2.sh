#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"
until grep -q BUILD_OK /tmp/sweep3_build.log 2>/dev/null; do sleep 10; done
exec ./batch_sweep_round2.sh
