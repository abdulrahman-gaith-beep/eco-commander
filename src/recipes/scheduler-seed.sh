#!/usr/bin/env bash
# DESC: Import mission YAML files into the scheduler queue
# INPUTS: <path> — a directory of mission .yaml/.yml files, or a single
#         mission file (its parent directory is seeded).
#         Default: examples/missions/ (ships seed-jobs.example.yaml)
# OUTPUT: Jobs added to ~/.eco/queue/jobs.yaml
# USES: scheduler CLI (Python)
# HUMAN: Review seed output, then run `eco scheduler status` to verify

set -euo pipefail

resolve_script_path() {
  local source="${BASH_SOURCE[0]}"
  local dir

  while [[ -L "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ "$source" = /* ]] || source="$dir/$source"
  done

  dir="$(cd -P "$(dirname "$source")" && pwd)"
  printf '%s/%s\n' "$dir" "$(basename "$source")"
}

is_repo_root() {
  local candidate="$1"
  [[ -d "$candidate/src/scheduler" && -f "$candidate/src/scheduler/cli.py" ]]
}

python_is_supported() {
  "$1" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if (3, 10) <= sys.version_info[:2] < (3, 14) else 1)
PY
}

select_python_runner() {
  local candidate
  for candidate in "$REPO_ROOT/.venv/bin/python" "${PYTHON:-}" "${PYTHON_BIN:-}" python3.13 python3.12 python3.11 python3.10 python3; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" >/dev/null 2>&1 && python_is_supported "$candidate"; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

REPO_ROOT=""
if [[ -n "${ECO_COMMANDER_REPO:-}" ]]; then
  if candidate_repo="$(cd "$ECO_COMMANDER_REPO" 2>/dev/null && pwd -P)" && is_repo_root "$candidate_repo"; then
    REPO_ROOT="$candidate_repo"
  fi
fi

if [[ -z "$REPO_ROOT" ]]; then
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
  candidate_repo="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
  if is_repo_root "$candidate_repo"; then
    REPO_ROOT="$candidate_repo"
  else
    echo "Error: could not locate eco-commander repo root. Set ECO_COMMANDER_REPO to the repository path." >&2
    exit 1
  fi
fi

SRC_DIR="$(cd "$REPO_ROOT/src" && pwd -P)"
PYTHON_RUNNER="$(select_python_runner)" || {
  echo "Error: no supported Python found (requires 3.10-3.13)." >&2
  echo "Create a venv and install dependencies: python3 -m venv \"$REPO_ROOT/.venv\" && \"$REPO_ROOT/.venv/bin/pip\" install -e \"$REPO_ROOT\"" >&2
  exit 1
}
SEED_PATH="${1:-$REPO_ROOT/examples/missions}"

if [[ ! -e "$SEED_PATH" ]]; then
  echo "Error: path not found: $SEED_PATH" >&2
  echo "Usage: eco do scheduler-seed [path]" >&2
  exit 1
fi

# The scheduler CLI seeds a directory of mission files; if given a single
# file, seed its containing directory.
if [[ -d "$SEED_PATH" ]]; then
  SEED_DIR="$SEED_PATH"
else
  SEED_DIR="$(cd "$(dirname "$SEED_PATH")" && pwd)"
fi

echo "🌱 Seeding scheduler queue from: $SEED_DIR"
echo ""

# Run seed via the scheduler CLI module
PYTHONPATH="$SRC_DIR${PYTHONPATH:+:$PYTHONPATH}" "$PYTHON_RUNNER" -m scheduler.cli seed --dir "$SEED_DIR"

echo ""
echo "📋 Current queue status:"
PYTHONPATH="$SRC_DIR${PYTHONPATH:+:$PYTHONPATH}" "$PYTHON_RUNNER" -m scheduler.cli status
