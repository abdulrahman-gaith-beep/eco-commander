#!/usr/bin/env bash
# Thin wrapper to run the scheduler dispatcher from anywhere.
# Used by:
#   • Manual debugging / one-shot tick
#   • Testing scheduler dispatch without LaunchAgent
#   • Anywhere PYTHONPATH/cwd needs to be set explicitly
#
# @category  runtime
# @depends   Python 3.10-3.13, src/scheduler/
# @calls     scheduler.dispatcher (via python -m)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="$REPO_ROOT/src${PYTHONPATH:+:$PYTHONPATH}"

select_python_runner() {
  local candidate
  for candidate in "${PYTHON:-}" "${PYTHON_BIN:-}" "$REPO_ROOT/.venv/bin/python" python3.13 python3.12 python3.11 python3.10 python3; do
    [ -n "$candidate" ] || continue
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" - <<'PY' >/dev/null 2>&1; then
import sys
raise SystemExit(0 if (3, 10) <= sys.version_info[:2] < (3, 14) else 1)
PY
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

PYTHON_RUNNER="$(select_python_runner)" || {
  echo "run-scheduler.sh: no supported Python found (requires 3.10-3.13)" >&2
  exit 1
}

exec "$PYTHON_RUNNER" -m scheduler.dispatcher "$@"
