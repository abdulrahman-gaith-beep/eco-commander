#!/usr/bin/env bash
# run-all.sh — run the full eco commander test suite
#
# Usage:
#   ./run-all.sh              # all engines: BATS + Python + E2E
#   ./run-all.sh --pretty     # pretty formatter for BATS
#   ./run-all.sh --parallel   # parallel BATS execution
#   ./run-all.sh smoke        # BATS smoke tests only
#   ./run-all.sh router       # BATS router only
#   ./run-all.sh commander    # BATS commander/state tests only
#   ./run-all.sh recipes      # BATS recipes only
#   ./run-all.sh bats         # BATS only (skip Python + E2E)
#   ./run-all.sh python       # Python only
#   ./run-all.sh e2e          # E2E only
#
# Exit code: 0 if all green, non-zero otherwise.

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
cd "$HERE"

if [ -z "${PYTHON:-}" ] && [ -x "$REPO_ROOT/.venv/bin/python" ]; then
  PYTHON="$REPO_ROOT/.venv/bin/python"
else
  PYTHON="${PYTHON:-$(command -v python3 || true)}"
fi

BATS_AVAILABLE=0
command -v bats >/dev/null 2>&1 && BATS_AVAILABLE=1

MODE="full"
FORMATTER=""
JOBS=""

for arg in "$@"; do
  case "$arg" in
    --pretty)   FORMATTER="--formatter pretty" ;;
    --parallel)
      JOBS="--jobs ${ECO_BATS_JOBS:-4}"
      ;;
    smoke)      MODE="smoke" ;;
    router)     MODE="router" ;;
    commander)  MODE="commander" ;;
    recipes)    MODE="recipes" ;;
    bats)       MODE="bats-only" ;;
    python)     MODE="python-only" ;;
    e2e)        MODE="e2e-only" ;;
    -h|--help)
      sed -n '2,15p' "$HERE/run-all.sh"
      exit 0
      ;;
    *)
      echo "ERROR: unknown test runner argument: $arg" >&2
      echo "Run: $0 --help" >&2
      exit 2
      ;;
  esac
done

TOTAL_RC=0
SKIPPED_ENGINES=()
ALLOW_TEST_ENGINE_SKIP="${ECO_ALLOW_TEST_ENGINE_SKIP:-0}"

python_available() {
  [ -n "$PYTHON" ] && command -v "$PYTHON" >/dev/null 2>&1
}

needs_bats() {
  case "$MODE" in
    smoke|router|commander|recipes|bats-only|full) return 0 ;;
    *) return 1 ;;
  esac
}

needs_python() {
  case "$MODE" in
    python-only|full) return 0 ;;
    *) return 1 ;;
  esac
}

record_engine_skip() {
  local engine="$1"
  local message="$2"
  if [ "$ALLOW_TEST_ENGINE_SKIP" = "1" ]; then
    echo "⏭ Skipping $engine: $message" >&2
    echo "   ECO_ALLOW_TEST_ENGINE_SKIP=1 is set; continuing, but final result will be non-success." >&2
    SKIPPED_ENGINES+=("$engine")
    TOTAL_RC=1
    return 0
  fi

  echo "ERROR: required test engine missing: $engine" >&2
  echo "       $message" >&2
  echo "       Set ECO_ALLOW_TEST_ENGINE_SKIP=1 to continue other suites while still returning non-success." >&2
  exit 1
}

if needs_bats && [ "$BATS_AVAILABLE" -eq 0 ]; then
  record_engine_skip "BATS" "bats not found. Install: brew install bats-core"
fi

if needs_python && ! python_available; then
  record_engine_skip "Python" "python3 not found. Set PYTHON=/path/to/python3 if needed."
fi

# ── BATS ──────────────────────────────────────────────────────────
run_bats() {
  if [ "$BATS_AVAILABLE" -eq 0 ]; then
    echo "⏭ Skipping BATS (not installed)"
    return 0
  fi

  local targets=()
  case "${1:-full}" in
    smoke)     targets=("bats/00_smoke.bats") ;;
    router)    targets=("bats/01_router.bats") ;;
    commander) targets=("bats/02_commander_cli.bats" "bats/03_state_parsing.bats") ;;
    recipes)   targets=("bats/recipes/") ;;
    *)         targets=("bats/" "bats/recipes/") ;;
  esac

  echo "=== BATS (${#targets[@]} target(s)) ==="
  echo "bats: $(bats --version)"
  echo "targets: ${targets[*]}"
  [ -n "$FORMATTER" ] && echo "formatter: $FORMATTER"
  [ -n "$JOBS" ] && echo "parallel: $JOBS"
  echo

  local start end
  start=$(date +%s)
  # shellcheck disable=SC2086
  bats $FORMATTER $JOBS "${targets[@]}" || TOTAL_RC=1
  end=$(date +%s)
  echo
  echo "=== BATS duration: $((end - start))s ==="
}

# ── Python ────────────────────────────────────────────────────────
run_python() {
  if ! python_available; then
    echo "⏭ Skipping Python (python3 not found)"
    return 0
  fi

  echo
  echo "=== Python ==="
  local start end
  start=$(date +%s)
  PYTHONPATH="$REPO_ROOT/src" "$PYTHON" -m unittest discover -s python -p "test_*.py" || TOTAL_RC=1
  end=$(date +%s)
  echo "=== Python duration: $((end - start))s ==="
}

# ── E2E ───────────────────────────────────────────────────────────
run_e2e() {
  echo
  echo "=== E2E ==="
  local start end
  start=$(date +%s)
  bash e2e/run_e2e.sh || TOTAL_RC=1
  end=$(date +%s)
  echo "=== E2E duration: $((end - start))s ==="
}

# ── Dispatch ──────────────────────────────────────────────────────

SUITE_START=$(date +%s)

case "$MODE" in
  smoke|router|commander|recipes)
    run_bats "$MODE"
    ;;
  bats-only)
    run_bats "full"
    ;;
  python-only)
    run_python
    ;;
  e2e-only)
    run_e2e
    ;;
  full)
    run_bats "full"
    run_python
    run_e2e
    ;;
esac

SUITE_END=$(date +%s)

echo
echo "═══════════════════════════════════════════"
echo "  Total duration: $((SUITE_END - SUITE_START))s"
if [ "${#SKIPPED_ENGINES[@]}" -gt 0 ]; then
  echo "  Skipped engines: ${SKIPPED_ENGINES[*]}"
fi
if [ "$TOTAL_RC" -eq 0 ]; then
  echo "  Result: ✅ ALL PASSED"
else
  echo "  Result: ❌ SOME FAILURES (exit $TOTAL_RC)"
fi
echo "═══════════════════════════════════════════"

exit $TOTAL_RC
