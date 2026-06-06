#!/usr/bin/env bash
# Read-only readiness checks for the contributor devcontainer.
set -euo pipefail

MODE="${1:---quick}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

ECO_HOME="${ECO_HOME:-$HOME/.eco}"
VENV_DIR="${VENV_DIR:-$HOME/.venvs/eco-commander}"
STRICT=0
[ "$MODE" = "--strict" ] && STRICT=1

FAIL=0
WARN=0

ok() { printf "  ok   %s\n" "$*"; }
warn() { WARN=$((WARN + 1)); printf "  warn %s\n" "$*" >&2; }
fail() { FAIL=$((FAIL + 1)); printf "  fail %s\n" "$*" >&2; }

need_bin() {
  local bin="$1"
  local required="${2:-1}"
  if command -v "$bin" >/dev/null 2>&1; then
    ok "$bin: $(command -v "$bin")"
  elif [ "$required" -eq 1 ] || [ "$STRICT" -eq 1 ]; then
    fail "$bin missing"
  else
    warn "$bin missing"
  fi
}

printf "devcontainer readiness (%s)\n" "$MODE"
printf "  repo: %s\n" "$REPO_ROOT"
printf "  ECO_HOME: %s\n" "$ECO_HOME"
printf "  VENV_DIR: %s\n" "$VENV_DIR"

need_bin bash
need_bin make
need_bin git
need_bin jq
need_bin shellcheck
need_bin shfmt
need_bin bats
need_bin timeout
need_bin node 0
need_bin npm 0
need_bin go 0
need_bin actionlint 0
need_bin gitleaks 0

if [ -x "$VENV_DIR/bin/python" ]; then
  ok "venv python: $("$VENV_DIR/bin/python" --version)"
else
  fail "venv python missing at $VENV_DIR/bin/python"
fi

if [ -x "$ECO_HOME/bin/eco" ]; then
  ok "eco linked at $ECO_HOME/bin/eco"
else
  fail "eco missing at $ECO_HOME/bin/eco"
fi

if [ "$FAIL" -eq 0 ]; then
  bash scripts/verify-manifest.sh
  PYTHONPATH=src "$VENV_DIR/bin/python" -m unittest discover -s tests/python -p "test_value.py"
  bash tests/run-all.sh smoke
fi

if [ "$STRICT" -eq 1 ] && [ "$WARN" -gt 0 ]; then
  fail "$WARN warning(s) in strict mode"
fi

if [ "$FAIL" -gt 0 ]; then
  printf "devcontainer readiness failed: %s failure(s), %s warning(s)\n" "$FAIL" "$WARN" >&2
  exit 1
fi

printf "devcontainer readiness passed: %s warning(s)\n" "$WARN"
