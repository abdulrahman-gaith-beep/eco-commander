#!/usr/bin/env bash
# Thin wrapper to run the eco-alerts engine from anywhere.
# Consistent with run-poller.sh and run-scheduler.sh.
#
# Usage: scripts/run-alerts.sh [args...]
#
# @category  runtime
# @depends   bash, src/bin/eco-alerts.sh
# @calls     src/bin/eco-alerts.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="$REPO_ROOT/src${PYTHONPATH:+:$PYTHONPATH}"
exec bash "$REPO_ROOT/src/bin/eco-alerts.sh" "$@"
