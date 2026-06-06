#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# Eco Commander Widget — End-to-End Test Suite
# ═══════════════════════════════════════════════════════════════════════
#
# Tests the widget from EVERY angle: normal operation, edge cases,
# corrupt data, missing deps, stress, concurrency, output format.
#
# Usage:
#   tests/e2e/run_e2e.sh              # run all tests
#   tests/e2e/run_e2e.sh --verbose    # show stdout on pass too
#   tests/e2e/run_e2e.sh T042         # run single test by ID
#
# Results written to a temp dir by default; set E2E_RESULTS_DIR to override.
# ═══════════════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WIDGET="$REPO_ROOT/src/bin/eco-commander.15s.sh"
FIXTURES="$SCRIPT_DIR/fixtures"
RESULTS_DIR="${E2E_RESULTS_DIR:-}"
if [ -z "$RESULTS_DIR" ]; then
  if ! RESULTS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/eco-e2e-results.XXXXXX")"; then
    echo "ERROR: failed to create temporary E2E results directory" >&2
    exit 1
  fi
fi
VERBOSE="${VERBOSE:-0}"
FILTER="${1:-}"
[ "$FILTER" = "--verbose" ] && { VERBOSE=1; FILTER="${2:-}"; }
E2E_HOST_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
E2E_DEFAULT_PATH="$E2E_HOST_PATH"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
if [ -z "$TIMEOUT_BIN" ]; then
  echo "ERROR: tests/e2e/run_e2e.sh requires timeout or gtimeout. On macOS: brew install coreutils" >&2
  exit 1
fi

# Colors (disable when not a TTY for CI)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# Counters
PASS=0; FAIL=0; SKIP=0; TOTAL=0
FAILURES=()
PASSES=()

# Prepare
mkdir -p "$RESULTS_DIR"
rm -rf "$RESULTS_DIR/failures"  # Clean old failure artifacts
REPORT="$RESULTS_DIR/report-$(date +%Y%m%dT%H%M%S).md"
LOG="$RESULTS_DIR/run.log"
> "$LOG"

# Track sandboxes for cleanup on abort
ALL_SANDBOXES=()
cleanup_on_exit() {
  for d in "${ALL_SANDBOXES[@]+${ALL_SANDBOXES[@]}}"; do
    [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup_on_exit EXIT

# ─────────────────────────────────────────────────────────────────────
# Test harness
# ─────────────────────────────────────────────────────────────────────

write_probe_stubs() {
  local stub_bin="$1"
  mkdir -p "$stub_bin"

  cat > "$stub_bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$HOME/.stub-curl.log"
exit "${STUB_CURL_EXIT:-7}"
SH

  cat > "$stub_bin/ollama" <<'SH'
#!/usr/bin/env bash
printf 'ollama %s\n' "$*" >> "$HOME/.stub-ollama.log"
sub="${1:-}"
if [ "${STUB_OLLAMA_RUNNING:-0}" -ne 1 ]; then
  case "$sub" in
    ps|list) exit 1 ;;
    run) echo "Error: could not connect to ollama daemon" >&2; exit 1 ;;
    *) exit 1 ;;
  esac
fi
case "$sub" in
  ps)
    printf 'NAME\tID\tSIZE\tPROCESSOR\tUNTIL\n'
    if [ -n "${STUB_OLLAMA_LOADED:-}" ]; then
      old_ifs="$IFS"; IFS=,
      for model in $STUB_OLLAMA_LOADED; do
        [ -n "$model" ] && printf '%s\tstub\t2.0 GB\tGPU\t10m\n' "$model"
      done
      IFS="$old_ifs"
    fi
    ;;
  list)
    printf 'NAME\tID\tSIZE\tMODIFIED\n'
    [ -n "${STUB_OLLAMA_LIST:-}" ] && printf '%s\n' "$STUB_OLLAMA_LIST"
    ;;
  *) ;;
esac
exit 0
SH

  cat > "$stub_bin/vm_stat" <<'SH'
#!/usr/bin/env bash
cat <<EOF
Mach Virtual Memory Statistics: (page size of ${STUB_PAGE_SIZE:-16384} bytes)
Pages free:                               ${STUB_PAGES_FREE:-100000}.
Pages active:                             500000.
Pages inactive:                           ${STUB_PAGES_INACTIVE:-200000}.
Pages speculative:                        ${STUB_PAGES_SPECULATIVE:-10000}.
Pages throttled:                          0.
Pages wired down:                         400000.
Pages purgeable:                          ${STUB_PAGES_PURGEABLE:-50000}.
EOF
exit 0
SH

  cat > "$stub_bin/sysctl" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "hw.pagesize" ]; then
  echo "${STUB_PAGE_SIZE:-16384}"
  exit 0
fi
if [ "${1:-}" = "-n" ] && [ "${2:-}" = "vm.swapusage" ]; then
  echo "vm.swapusage: total = 2048.00M used = ${STUB_SWAP_USED_MB:-0}.00M free = 2048.00M"
  exit 0
fi
exit 1
SH

  cat > "$stub_bin/pgrep" <<'SH'
#!/usr/bin/env bash
printf '0\n'
exit 0
SH

  cat > "$stub_bin/ps" <<'SH'
#!/usr/bin/env bash
printf 'ELAPSED COMMAND\n'
exit 0
SH

  chmod +x "$stub_bin/curl" "$stub_bin/ollama" "$stub_bin/vm_stat" "$stub_bin/sysctl" "$stub_bin/pgrep" "$stub_bin/ps"
}

e2e_probe_path() {
  local sandbox="$1"
  printf '%s:%s' "$sandbox/stub-bin" "$E2E_DEFAULT_PATH"
}

hide_command_env() {
  local sandbox="$1"; shift
  local env_file="$sandbox/hide-command.bash"
  local pattern="" name
  for name in "$@"; do
    pattern="${pattern:+$pattern|}$name"
  done
  {
    printf 'command() {\n'
    printf '  if [ "${1:-}" = "-v" ]; then\n'
    printf '    case "${2:-}" in\n'
    printf '      %s) return 1 ;;\n' "$pattern"
    printf '    esac\n'
    printf '  fi\n'
    printf '  builtin command "$@"\n'
    printf '}\n'
  } > "$env_file"
  echo "$env_file"
}

# Create isolated sandbox
setup_sandbox() {
  local tmpdir
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/eco-e2e.XXXXXX")
  mkdir -p "$tmpdir/eco/current" "$tmpdir/eco/logs" "$tmpdir/eco/bin" \
           "$tmpdir/eco/recipes" "$tmpdir/eco/alert-runs" \
           "$tmpdir/eco/state" \
           "$tmpdir/.ai-ecosystem/profiles" \
           "$tmpdir/Projects/ai-ecosystem-audit/specs"
  write_probe_stubs "$tmpdir/stub-bin"
  # Stub files so widget doesn't crash on missing paths
  echo "no-mcp" > "$tmpdir/.ai-ecosystem/.current-profile"
  echo '#!/bin/bash' > "$tmpdir/.ai-ecosystem/switch-profile.sh"
  chmod +x "$tmpdir/.ai-ecosystem/switch-profile.sh"
  # Stub profiles
  echo '{}' > "$tmpdir/.ai-ecosystem/profiles/no-mcp.mcpServers.json"
  echo '{}' > "$tmpdir/.ai-ecosystem/profiles/full.mcpServers.json"
  # Stub scripts
  echo '#!/bin/bash' > "$tmpdir/eco/bin/ai-clear.sh"; chmod +x "$tmpdir/eco/bin/ai-clear.sh"
  echo '#!/bin/bash' > "$tmpdir/eco/bin/eco-alerts.sh"; chmod +x "$tmpdir/eco/bin/eco-alerts.sh"
  # Stub recipes
  for r in ask note research snapshot dashboard; do
    printf '#!/bin/bash\n# DESC: test %s recipe\nexit 0\n' "$r" > "$tmpdir/eco/recipes/${r}.sh"
    chmod +x "$tmpdir/eco/recipes/${r}.sh"
  done
  # Stub EROR spec
  echo "# EROR v1" > "$tmpdir/Projects/ai-ecosystem-audit/specs/EROR-v1-DRAFT.md"
  ALL_SANDBOXES+=("$tmpdir")
  echo "$tmpdir"
}

teardown_sandbox() {
  [ -n "${1:-}" ] && rm -rf "$1"
}

# Run the widget in a sandbox and capture output
run_widget() {
  local sandbox="$1"; shift
  local mode="${1:-swiftbar}"; shift || true
  local extra_env=()
  [ $# -gt 0 ] && extra_env=("$@")

  local args=()
  [ "$mode" = "cli" ] && args=("--cli")

  env \
    HOME="$sandbox" \
    ECO_HOME="$sandbox/eco" \
    ECO_COMMANDER_REPO="$REPO_ROOT" \
    PATH="$(e2e_probe_path "$sandbox")" \
    ${extra_env[@]+"${extra_env[@]}"} \
    "$TIMEOUT_BIN" 30 bash "$WIDGET" ${args[@]+"${args[@]}"} 2>"$sandbox/stderr.txt"
  local rc=$?
  echo "$rc">"$sandbox/exit_code.txt"
  return $rc
}

offline_probe_path() {
  local sandbox="$1"
  local stub_bin="$sandbox/stub-bin"
  write_probe_stubs "$stub_bin"
  printf '%s:%s' "$stub_bin" "$E2E_DEFAULT_PATH"
}

# Install usage.json from template (replaces __NOW__ with current epoch)
install_usage() {
  local sandbox="$1"
  local fixture="$2"
  local ts_override="${3:-$(date +%s)}"
  sed "s/__NOW__/$ts_override/" "$fixture" > "$sandbox/eco/current/usage.json"
}

# Install state.json with given alert count
install_state() {
  local sandbox="$1"
  local alert_count="${2:-0}"
  local issues=""
  for ((i = 1; i <= alert_count; i++)); do
    [ -n "$issues" ] && issues="$issues,"
    issues="$issues{\"severity\":\"HIGH\",\"id\":\"ISSUE-$i\",\"desc\":\"Test issue number $i for stress testing\"}"
  done
  cat > "$sandbox/eco/current/state.json" <<JSON
{
  "generated_at": "2026-05-20T12:00:00Z",
  "snapshot_id": "2026-05-20T12-00Z",
  "layers": {
    "L1_core": {
      "issues": [$issues]
    }
  }
}
JSON
}

# Test assertion helpers
assert_exit() {
  local sandbox="$1" expected="$2"
  local actual
  actual=$(cat "$sandbox/exit_code.txt" 2>/dev/null || echo "?")
  [ "$actual" = "$expected" ]
}

assert_stdout_contains() {
  local output="$1" pattern="$2"
  printf '%s\n' "$output" | grep -qF "$pattern"
}

assert_stdout_regex() {
  local output="$1" pattern="$2"
  printf '%s\n' "$output" | grep -qE "$pattern"
}

assert_stdout_not_contains() {
  local output="$1" pattern="$2"
  ! printf '%s\n' "$output" | grep -qF "$pattern"
}

assert_no_stderr() {
  local sandbox="$1"
  [ ! -s "$sandbox/stderr.txt" ]
}

assert_line_count_ge() {
  local output="$1" min="$2"
  local count
  count=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
  [ "$count" -ge "$min" ]
}

assert_first_line() {
  local output="$1" expected="$2"
  local first
  first=$(printf '%s\n' "$output" | head -1)
  [ "$first" = "$expected" ]
}

assert_swiftbar_format() {
  # Validates SwiftBar output: first line = title, second line = ---
  local output="$1"
  local line2
  line2=$(printf '%s\n' "$output" | sed -n '2p')
  [ "$line2" = "---" ]
}

# ─────────────────────────────────────────────────────────────────────
# Test runner
# ─────────────────────────────────────────────────────────────────────
run_test() {
  local id="$1" name="$2" fn="$3"
  TOTAL=$((TOTAL + 1))
  
  # Filter
  if [ -n "$FILTER" ] && [ "$FILTER" != "$id" ]; then
    SKIP=$((SKIP + 1))
    return
  fi

  local sandbox
  sandbox=$(setup_sandbox)

  printf "  %-7s %-65s " "$id" "$name"
  
  local test_stdout test_stderr test_exit
  test_stdout=$( ($fn "$sandbox") 2>"$sandbox/test_stderr.txt" )
  test_exit=$?

  if [ "$test_exit" -eq 0 ]; then
    printf "${GREEN}PASS${NC}\n"
    PASS=$((PASS + 1))
    PASSES+=("$id: $name")
    [ "$VERBOSE" -eq 1 ] && echo "$test_stdout" | head -5 | sed 's/^/         /'
  else
    printf "${RED}FAIL${NC}\n"
    FAIL=$((FAIL + 1))
    local reason
    reason=$(cat "$sandbox/test_stderr.txt" 2>/dev/null | head -3)
    [ -z "$reason" ] && reason="(no details)"
    FAILURES+=("$id|$name|$reason")
    # Save failure artifacts
    mkdir -p "$RESULTS_DIR/failures/$id"
    cp -r "$sandbox"/* "$RESULTS_DIR/failures/$id/" 2>/dev/null || true
  fi

  echo "[$id] $name: exit=$test_exit" >> "$LOG"
  teardown_sandbox "$sandbox"
}


# ═══════════════════════════════════════════════════════════════════════
# TEST CASES
# ═══════════════════════════════════════════════════════════════════════

# ─── TIER 1: Core Output Format ───

test_T001() {
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_swiftbar_format "$out" || { echo "Line 2 is not '---'" >&2; return 1; }
  assert_first_line "$out" "🟢" || assert_first_line "$out" "🟡" || assert_first_line "$out" "🔴" || { echo "Title not a status icon" >&2; return 1; }
}

test_T002() {
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" cli)
  assert_stdout_contains "$out" "=== Eco Commander (CLI) ===" || { echo "Missing CLI header" >&2; return 1; }
  assert_stdout_contains "$out" "Status:" || { echo "Missing Status line" >&2; return 1; }
  assert_stdout_not_contains "$out" "| size=" || { echo "SwiftBar params leaked into CLI" >&2; return 1; }
}

test_T003() {
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # Every SwiftBar menu item (after ---) must have | or be --- itself
  local bad_lines
  bad_lines=$(echo "$out" | tail -n +3 | grep -v '^---$' | grep -v '|' | grep -cv '^$' || true)
  [ "$bad_lines" -eq 0 ] || { echo "$bad_lines lines missing SwiftBar pipe separator" >&2; return 1; }
}

test_T004() {
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # Title must be EXACTLY one short line — no long verbose text
  local title_len
  title_len=$(echo "$out" | head -1 | wc -c | tr -d ' ')
  [ "$title_len" -le 10 ] || { echo "Title too long: ${title_len} chars (max 10 for compact icon)" >&2; return 1; }
}

# ─── TIER 2: Status Icon Logic ───

test_T010() {
  # Green when everything healthy
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  # Touch state.json to make it fresh
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_first_line "$out" "🟢" || { echo "Expected green, got: $(echo "$out" | head -1)" >&2; return 1; }
}

test_T011() {
  # Red when quota >= 95%
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  # Override session pct to 96
  sed -i '' 's/"pct": 12/"pct": 96/' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_first_line "$out" "🔴" || { echo "Expected red at 96% quota, got: $(echo "$out" | head -1)" >&2; return 1; }
}

test_T012() {
  # Yellow when quota 80-94%
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": 12/"pct": 85/' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_first_line "$out" "🟡" || { echo "Expected yellow at 85% quota, got: $(echo "$out" | head -1)" >&2; return 1; }
}

test_T013() {
  # Red when snapshot very stale (>3 days)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  # Make state.json 4 days old
  touch -t $(date -v-4d +%Y%m%d%H%M) "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_first_line "$out" "🔴" || { echo "Expected red for stale snapshot, got: $(echo "$out" | head -1)" >&2; return 1; }
}

test_T014() {
  # Red when poller data is stale (>180s)
  local sandbox="$1"
  local stale_ts=$(( $(date +%s) - 300 ))
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json" "$stale_ts"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_first_line "$out" "🔴" || { echo "Expected red for stale poller, got: $(echo "$out" | head -1)" >&2; return 1; }
}

# ─── TIER 3: Missing Dependencies ───

test_T020() {
  # No jq → graceful degradation
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  local out
  out=$(run_widget "$sandbox" swiftbar "BASH_ENV=$(hide_command_env "$sandbox" jq)")
  # Should not crash
  assert_exit "$sandbox" "0" || { echo "Crashed without jq" >&2; return 1; }
  # Should show jq required message
  assert_stdout_contains "$out" "jq" || { echo "No jq-required message" >&2; return 1; }
}

test_T021() {
  # No usage.json → graceful message
  local sandbox="$1"
  # Don't install usage.json
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "not produced data" || assert_stdout_contains "$out" "usage" || { echo "No missing-data message" >&2; return 1; }
}

test_T022() {
  # No state.json → no crash, shows default alert state
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  # Don't install state.json
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed without state.json" >&2; return 1; }
}

test_T023() {
  # No profiles directory → no crash in MCP section
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  rm -rf "$sandbox/.ai-ecosystem/profiles"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed without profiles dir" >&2; return 1; }
  assert_stdout_contains "$out" "MCP Profile" || { echo "MCP section missing" >&2; return 1; }
}

test_T024() {
  # No recipes directory → shows error message
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  rm -rf "$sandbox/eco/recipes"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "recipes directory missing" || { echo "No missing-recipes message" >&2; return 1; }
}

# ─── TIER 4: Corrupt / Malformed Data ───

test_T030() {
  # Corrupt usage.json (invalid JSON)
  local sandbox="$1"
  echo "NOT VALID JSON {{{" > "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on corrupt JSON" >&2; return 1; }
  assert_stdout_contains "$out" "corrupt" || { echo "No corrupt-data message" >&2; return 1; }
}

test_T031() {
  # Empty usage.json (0 bytes)
  local sandbox="$1"
  > "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on empty usage.json" >&2; return 1; }
  # Should show corrupt/missing data message, not quota data
  assert_stdout_contains "$out" "corrupt" || assert_stdout_contains "$out" "not produced" || { echo "No error indicator for empty file" >&2; return 1; }
}

test_T032() {
  # usage.json is a JSON array instead of object
  local sandbox="$1"
  echo '[1,2,3]' > "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on array JSON" >&2; return 1; }
  # Should NOT show token quota data
  assert_stdout_not_contains "$out" "Session" || { echo "Session shown for array JSON" >&2; return 1; }
}

test_T033() {
  # usage.json with missing fields (partial data)
  local sandbox="$1"
  echo '{"ts": '"$(date +%s)"', "claude": {"ok": true}}' > "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on partial JSON" >&2; return 1; }
}

test_T034() {
  # Corrupt state.json
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  echo "CORRUPTED" > "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on corrupt state.json" >&2; return 1; }
}

test_T035() {
  # usage.json with null values for critical fields
  local sandbox="$1"
  cat > "$sandbox/eco/current/usage.json" <<'JSON'
{"ts": 0, "claude": {"ok": null, "session": {"pct": null}, "weekly": {"pct": null}}, "gemini": {"ok": null}, "codex": {"ok": null}}
JSON
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on null values" >&2; return 1; }
}

test_T036() {
  # usage.json with negative percentages
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": 12/"pct": -5/' "$sandbox/eco/current/usage.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on negative pct" >&2; return 1; }
}

test_T037() {
  # usage.json with >100% values
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": 12/"pct": 150/' "$sandbox/eco/current/usage.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on >100% pct" >&2; return 1; }
  # Progress bar should clamp to 100% — check all 12 blocks filled
  local full_bar
  full_bar=$(printf '█%.0s' {1..12})
  assert_stdout_contains "$out" "$full_bar" || { echo "Progress bar not clamped at >100%" >&2; return 1; }
}

test_T038() {
  # usage.json with string instead of number for pct
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": 12/"pct": "twelve"/' "$sandbox/eco/current/usage.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on string pct" >&2; return 1; }
}

# ─── TIER 5: Boundary / Edge Cases ───

test_T040() {
  # Exactly 0% on all meters
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": [0-9]*/"pct": 0/g' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed at 0%" >&2; return 1; }
}

test_T041() {
  # Exactly 100% on all meters
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": [0-9]*/"pct": 100/g' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed at 100%" >&2; return 1; }
}

test_T042() {
  # Exactly at WARN threshold (80%)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": 12/"pct": 80/' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_regex "$out" "color=orange" || { echo "80% should be orange" >&2; return 1; }
}

test_T043() {
  # Exactly at CRIT threshold (95%)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"pct": 12/"pct": 95/' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_regex "$out" "color=red" || { echo "95% should be red" >&2; return 1; }
}

test_T044() {
  # Empty profile name
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  > "$sandbox/.ai-ecosystem/.current-profile"
  local out
  out=$(run_widget "$sandbox" cli)
  # Should show "—" fallback for empty profile, not crash
  assert_exit "$sandbox" "0" || { echo "Crashed on empty profile" >&2; return 1; }
  assert_stdout_contains "$out" "—" || { echo "Empty profile should show — fallback" >&2; return 1; }
}

test_T045() {
  # Future timestamp in usage.json (clock skew)
  local sandbox="$1"
  local future_ts=$(( $(date +%s) + 3600 ))
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json" "$future_ts"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on future timestamp" >&2; return 1; }
}

test_T046() {
  # ts = 0 (epoch) in usage.json
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json" "0"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on ts=0" >&2; return 1; }
}

# ─── TIER 6: Sections Exist ───

test_T050() {
  # All major sections present in SwiftBar output
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  local missing=()
  assert_stdout_contains "$out" "📊 Token Quotas" || missing+=("Token Quotas")
  assert_stdout_contains "$out" "📡 System"       || missing+=("System")
  assert_stdout_contains "$out" "🔌 MCP Profile"  || missing+=("MCP Profile")
  assert_stdout_contains "$out" "🧰 Recipes"      || missing+=("Recipes")
  assert_stdout_contains "$out" "⚡ Quick Actions" || missing+=("Quick Actions")
  assert_stdout_contains "$out" "📚 Docs"          || missing+=("Docs")
  assert_stdout_contains "$out" "Alerts"           || missing+=("Alerts")
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing sections: ${missing[*]}" >&2; return 1
  fi
}

test_T051() {
  # All sections present in CLI output
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" cli)
  local missing=()
  assert_stdout_contains "$out" "Token Quotas" || missing+=("Token Quotas")
  assert_stdout_contains "$out" "System"       || missing+=("System")
  assert_stdout_contains "$out" "MCP Profile"  || missing+=("MCP Profile")
  assert_stdout_contains "$out" "Recipes"      || missing+=("Recipes")
  assert_stdout_contains "$out" "Quick Actions" || missing+=("Quick Actions")
  assert_stdout_contains "$out" "Docs"          || missing+=("Docs")
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing CLI sections: ${missing[*]}" >&2; return 1
  fi
}

test_T052() {
  # Claude section shows session + weekly with progress bars
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "Claude" || { echo "Missing Claude header" >&2; return 1; }
  assert_stdout_contains "$out" "Session" || { echo "Missing Session bar" >&2; return 1; }
  assert_stdout_contains "$out" "Weekly" || { echo "Missing Weekly bar" >&2; return 1; }
  assert_stdout_regex "$out" "[█░]" || { echo "No progress bar chars" >&2; return 1; }
}

test_T053() {
  # Gemini shows 3 tiers
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "Gemini" || { echo "Missing Gemini header" >&2; return 1; }
  assert_stdout_contains "$out" "flash" || { echo "Missing flash tier" >&2; return 1; }
  assert_stdout_contains "$out" "pro" || { echo "Missing pro tier" >&2; return 1; }
}

test_T054() {
  # Codex shows explicit org label
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar ECO_ORG_LABEL=ExampleOrg)
  assert_stdout_contains "$out" "ExampleOrg" || { echo "Missing org label" >&2; return 1; }
}

# ─── TIER 7: Stress / Performance ───

test_T060() {
  # Many alerts (50)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox" 50
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed with 50 alerts" >&2; return 1; }
  assert_stdout_contains "$out" "50 Alerts" || { echo "Alert count wrong" >&2; return 1; }
}

test_T061() {
  # Large number of recipes (20)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  for i in $(seq 1 20); do
    printf '#!/bin/bash\n# DESC: stress recipe %d\nexit 0\n' "$i" > "$sandbox/eco/recipes/stress-${i}.sh"
    chmod +x "$sandbox/eco/recipes/stress-${i}.sh"
  done
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed with 20 recipes" >&2; return 1; }
}

test_T062() {
  # Many MCP profiles (10)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  for i in $(seq 1 10); do
    echo '{}' > "$sandbox/.ai-ecosystem/profiles/profile-${i}.mcpServers.json"
  done
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed with 10 profiles" >&2; return 1; }
  # At least some of the 10 new profiles should appear in output
  assert_stdout_contains "$out" "profile-1" || { echo "profile-1 not visible in output" >&2; return 1; }
}

test_T063() {
  # Widget runs under 5 seconds (performance)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox" 20
  touch "$sandbox/eco/current/state.json"
  local start end elapsed
  start=$(date +%s)
  run_widget "$sandbox" swiftbar >/dev/null
  end=$(date +%s)
  elapsed=$(( end - start ))
  [ "$elapsed" -le 5 ] || { echo "Widget took ${elapsed}s (max 5s)" >&2; return 1; }
}

test_T064() {
  # Concurrent execution (3 instances) — separate sandboxes to avoid data races
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local pids=() sboxes=()
  for i in 1 2 3; do
    local csb
    csb=$(setup_sandbox)
    install_usage "$csb" "$FIXTURES/usage_healthy.json"
    install_state "$csb"
    touch "$csb/eco/current/state.json"
    sboxes+=("$csb")
    run_widget "$csb" swiftbar >/dev/null &
    pids+=($!)
  done
  local failures=0
  for pid in "${pids[@]}"; do
    wait "$pid" || failures=$((failures + 1))
  done
  for csb in "${sboxes[@]}"; do teardown_sandbox "$csb"; done
  [ "$failures" -eq 0 ] || { echo "$failures/3 concurrent runs failed" >&2; return 1; }
}

# ─── TIER 8: Provider Error States ───

test_T070() {
  # Claude error state
  local sandbox="$1"
  cat > "$sandbox/eco/current/usage.json" <<JSON
{"ts": $(date +%s), "claude": {"ok": false, "error": "rate limited, try again later"}, "gemini": {"ok": true, "plan": "Unknown", "accounts": 1, "tiers": {"flash": {"pct": 0, "resets_in": "24h"}, "flash_lite": {"pct": 0, "resets_in": "24h"}, "pro": {"pct": 0, "resets_in": "24h"}}}, "codex": {"ok": false, "error": "auth expired"}}
JSON
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on error state" >&2; return 1; }
  assert_stdout_contains "$out" "rate limited" || { echo "Claude error not shown" >&2; return 1; }
  assert_stdout_contains "$out" "auth expired" || { echo "Codex error not shown" >&2; return 1; }
}

test_T071() {
  # All providers in error state
  local sandbox="$1"
  cat > "$sandbox/eco/current/usage.json" <<JSON
{"ts": $(date +%s), "claude": {"ok": false, "error": "down"}, "gemini": {"ok": false, "error": "quota"}, "codex": {"ok": false, "error": "timeout"}}
JSON
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed with all errors" >&2; return 1; }
}

test_T072() {
  # Claude stale + Codex stale
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"stale": false/"stale": true/g' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "cached" || { echo "No stale indicator" >&2; return 1; }
}

# ─── TIER 9: Suggestion Engine ───

test_T080() {
  # Suggestion fires at 96% (priority 1 — switch tools NOW)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' '0,/"pct": 12/{s/"pct": 12/"pct": 96/}' "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "💡" || { echo "No suggestion at 96%" >&2; return 1; }
}

test_T081() {
  # No suggestion when all quotas are low
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # At 12% with >1h to reset, no P1/P2/P3 suggestion should fire
  assert_exit "$sandbox" "0" || { echo "Crashed in suggestion logic" >&2; return 1; }
  assert_stdout_not_contains "$out" "switch tools NOW" || { echo "P1 suggestion fired at 12%" >&2; return 1; }
  assert_stdout_not_contains "$out" "LAST CALL" || { echo "P2 suggestion fired at 12%" >&2; return 1; }
}

# ─── TIER 10: humanize() function ───

test_T090() {
  # humanize: 0 tokens
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"tokens": 120/"tokens": 0/' "$sandbox/eco/current/usage.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on 0 tokens" >&2; return 1; }
}

test_T091() {
  # humanize: very large tokens (trillions)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  sed -i '' 's/"tokens": 120/"tokens": 5000000000000/' "$sandbox/eco/current/usage.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on trillion tokens" >&2; return 1; }
}

# ─── TIER 11: SwiftBar Action Params ───

test_T100() {
  # Quick actions have terminal= and refresh= params
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # Deprecated ai-clear should not appear in quick actions.
  assert_stdout_not_contains "$out" "ai-clear" || { echo "ai-clear should not appear" >&2; return 1; }
  # Refresh usage should have terminal=false
  assert_stdout_regex "$out" "Refresh usage.*terminal=false" || { echo "Refresh usage missing terminal=false" >&2; return 1; }
}

test_T101() {
  # All bash= actions have valid format (absolute paths or known binaries)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Action param validation crashed" >&2; return 1; }
  # Every bash= value must start with / (absolute path)
  local relative_paths
  relative_paths=$(printf '%s\n' "$out" | grep -oE 'bash=[^ |]+' | sed 's/bash=//' | grep -cv '^/' || true)
  [ "$relative_paths" -eq 0 ] || { echo "$relative_paths bash= actions use relative paths" >&2; return 1; }
  # Must have at least 5 bash= actions (sanity check)
  local action_count
  action_count=$(printf '%s\n' "$out" | grep -c 'bash=' || true)
  [ "$action_count" -ge 5 ] || { echo "Only $action_count bash= actions (expected ≥5)" >&2; return 1; }
}

# ─── TIER 12: Alert System ───

test_T110() {
  # 0 alerts → green checkmark
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox" 0
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "✓ 0 Alerts" || { echo "Missing green 0-alert message" >&2; return 1; }
}

test_T111() {
  # Multiple alerts → orange warning
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox" 5
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "5 Alerts" || { echo "Alert count not shown" >&2; return 1; }
}

test_T112() {
  # Alert with very long description (>200 chars) — should truncate
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  local long_desc
  long_desc=$(printf 'X%.0s' {1..200})
  cat > "$sandbox/eco/current/state.json" <<JSON
{"generated_at":"2026-05-20","snapshot_id":"test","layers":{"L1":{"issues":[{"severity":"HIGH","id":"LONG","desc":"$long_desc"}]}}}
JSON
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on long alert desc" >&2; return 1; }
  # Should be truncated to ~110 chars
  local longest_line
  longest_line=$(echo "$out" | grep "LONG" | head -1 | wc -c | tr -d ' ')
  [ "$longest_line" -lt 250 ] || { echo "Alert not truncated: ${longest_line} chars" >&2; return 1; }
}

# ─── TIER 13: Output Stability ───

test_T120() {
  # Two consecutive runs produce identical output (deterministic)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out1 out2
  out1=$(run_widget "$sandbox" swiftbar)
  out2=$(run_widget "$sandbox" swiftbar)
  # Filter out the timestamp line (age changes by 1-2s) and RAM (live vm_stat data)
  local filtered1 filtered2
  filtered1=$(echo "$out1" | grep -v 'Updated\|ago)\|RAM:')
  filtered2=$(echo "$out2" | grep -v 'Updated\|ago)\|RAM:')
  [ "$filtered1" = "$filtered2" ] || { echo "Output not deterministic between runs" >&2; return 1; }
}

test_T121() {
  # No unescaped newlines in SwiftBar items
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox" 3
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # Each line after --- should either be --- itself or contain text
  local blank_in_menu
  blank_in_menu=$(echo "$out" | tail -n +3 | grep -c '^$' || true)
  [ "$blank_in_menu" -eq 0 ] || { echo "$blank_in_menu blank lines in menu output" >&2; return 1; }
}


# ─── TIER 14: Suggestion Engine (all 7 priorities) ───

test_T130() {
  # P2: LAST CALL — reset in <20m but >5% left
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  # Set resets_in to 15m and pct to 50 (50% left)
  jq '.claude.session.resets_in = "15m" | .claude.session.pct = 50' \
    "$sandbox/eco/current/usage.json" > "$sandbox/eco/current/usage.tmp" \
    && mv "$sandbox/eco/current/usage.tmp" "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "LAST CALL" || { echo "P2 LAST CALL not triggered at 15m/50%" >&2; return 1; }
}

test_T131() {
  # P4: SPRINT — reset in <60m, >10% left
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  jq '.claude.session.resets_in = "45m" | .claude.session.pct = 60' \
    "$sandbox/eco/current/usage.json" > "$sandbox/eco/current/usage.tmp" \
    && mv "$sandbox/eco/current/usage.tmp" "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "SPRINT" || { echo "P4 SPRINT not triggered at 45m/60%" >&2; return 1; }
}

test_T132() {
  # P5: burn fast — reset in <180m, >20% left
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  jq '.claude.session.resets_in = "2h 30m" | .claude.session.pct = 40' \
    "$sandbox/eco/current/usage.json" > "$sandbox/eco/current/usage.tmp" \
    && mv "$sandbox/eco/current/usage.tmp" "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "burn fast" || { echo "P5 burn-fast not triggered at 2h30m/40%" >&2; return 1; }
}

# ─── TIER 15: Alternatives Section ───

test_T140() {
  # Alternatives section shows all 4 tools
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "Alternatives" || { echo "Missing Alternatives section" >&2; return 1; }
  assert_stdout_contains "$out" "Antigravity" || { echo "Missing Antigravity" >&2; return 1; }
  assert_stdout_contains "$out" "Cursor" || { echo "Missing Cursor" >&2; return 1; }
  assert_stdout_contains "$out" "VS Code" || { echo "Missing VS Code" >&2; return 1; }
}

test_T141() {
  # No alternatives key → section hidden, no crash
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  jq 'del(.alternatives)' "$sandbox/eco/current/usage.json" > "$sandbox/eco/current/usage.tmp" \
    && mv "$sandbox/eco/current/usage.tmp" "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed without alternatives" >&2; return 1; }
  assert_stdout_not_contains "$out" "Alternatives" || { echo "Alternatives showed without data" >&2; return 1; }
}

# ─── TIER 16: Domains Section ───

test_T150() {
  # 11 domains listed
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "11 Domains" || { echo "Missing Domains header" >&2; return 1; }
  assert_stdout_contains "$out" "D1 Memory/RAG" || { echo "Missing D1" >&2; return 1; }
  assert_stdout_contains "$out" "D11 EROR" || { echo "Missing D11" >&2; return 1; }
}

# ─── TIER 17: Footer Section ───

test_T160() {
  # Footer shows snapshot ID and refresh button
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "Snapshot" || { echo "Missing Snapshot in footer" >&2; return 1; }
  assert_stdout_contains "$out" "Refresh" || { echo "Missing Refresh button" >&2; return 1; }
  assert_stdout_regex "$out" "refresh=true" || { echo "Refresh missing refresh=true param" >&2; return 1; }
}

test_T161() {
  # Footer absent when no state.json
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  # No state.json installed
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_not_contains "$out" "Generated" || { echo "Footer showed without state.json" >&2; return 1; }
}

# ─── TIER 18: Live Alert Verification ───

test_T170() {
  # n8n alert verified live with deterministic offline probe
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  cat > "$sandbox/eco/current/state.json" <<JSON
{"generated_at":"2026-05-20","snapshot_id":"test","layers":{"L1":{"issues":[{"severity":"HIGH","id":"N8N-001","desc":"n8n workflow engine is not running"}]}}}
JSON
  touch "$sandbox/eco/current/state.json"
  local out probe_path
  probe_path=$(offline_probe_path "$sandbox")
  out=$(run_widget "$sandbox" swiftbar "PATH=$probe_path")
  assert_stdout_contains "$out" "verified live" || { echo "n8n alert not verified live" >&2; return 1; }
}

test_T171() {
  # Timeout alert shows "evidence" status
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  cat > "$sandbox/eco/current/state.json" <<JSON
{"generated_at":"2026-05-20","snapshot_id":"test","layers":{"L1":{"issues":[{"severity":"HIGH","id":"TO-001","desc":"Snapshot timed out rc=124"}]}}}
JSON
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "evidence" || { echo "Timeout alert not marked as evidence" >&2; return 1; }
}

test_T172() {
  # Unknown alert type shows "triage" status
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  cat > "$sandbox/eco/current/state.json" <<JSON
{"generated_at":"2026-05-20","snapshot_id":"test","layers":{"L1":{"issues":[{"severity":"LOW","id":"UNK-001","desc":"Some completely unknown issue type"}]}}}
JSON
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "triage" || { echo "Unknown alert not marked as triage" >&2; return 1; }
}

# ─── TIER 19: Permission and Environment Edge Cases ───

test_T180() {
  # Unreadable usage.json → graceful
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  chmod 000 "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on unreadable usage.json" >&2; return 1; }
  # Restore for cleanup
  chmod 644 "$sandbox/eco/current/usage.json"
}

test_T181() {
  # Unreadable state.json → graceful
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  chmod 000 "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_exit "$sandbox" "0" || { echo "Crashed on unreadable state.json" >&2; return 1; }
  chmod 644 "$sandbox/eco/current/state.json"
}

test_T182() {
  # ECO_COMMANDER_REPO points to nonexistent dir → falls back
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar ECO_COMMANDER_REPO="/nonexistent/path")
  assert_exit "$sandbox" "0" || { echo "Crashed on bad REPO_ROOT" >&2; return 1; }
}

test_T183() {
  # Burn-rate comment shown when present
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  jq '.comment = "Light usage day — save quota for tonight"' \
    "$sandbox/eco/current/usage.json" > "$sandbox/eco/current/usage.tmp" \
    && mv "$sandbox/eco/current/usage.tmp" "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "Light usage day" || { echo "Burn-rate comment not shown" >&2; return 1; }
}

test_T184() {
  # No comment key → no crash, no empty speech bubble
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  jq 'del(.comment)' "$sandbox/eco/current/usage.json" > "$sandbox/eco/current/usage.tmp" \
    && mv "$sandbox/eco/current/usage.tmp" "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_not_contains "$out" "🗣" || { echo "Empty speech bubble shown without comment" >&2; return 1; }
}

test_T185() {
  # System section shows all runtime probes without depending on localhost
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out probe_path
  probe_path=$(offline_probe_path "$sandbox")
  out=$(run_widget "$sandbox" swiftbar "PATH=$probe_path")
  assert_stdout_contains "$out" "OpenClaw:" || { echo "Missing OpenClaw probe" >&2; return 1; }
  assert_stdout_contains "$out" "Cortex:" || { echo "Missing Cortex probe" >&2; return 1; }
  assert_stdout_contains "$out" "n8n:" || { echo "Missing n8n probe" >&2; return 1; }
  assert_stdout_contains "$out" "Snapshot:" || { echo "Missing Snapshot line" >&2; return 1; }
}

test_T186() {
  # MCP profile current indicator (✓)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "✓ no-mcp (current)" || { echo "Current profile not marked with ✓" >&2; return 1; }
}

test_T187() {
  # MCP non-current profile shows → arrow
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "→ full" || { echo "Non-current profile missing → arrow" >&2; return 1; }
}

test_T188() {
  # Recipe DESC extraction
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  # The setup_sandbox creates recipes with "# DESC: test <name> recipe"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "test ask recipe" || { echo "Recipe DESC not extracted" >&2; return 1; }
}

test_T189() {
  # Recipe without DESC → fallback "run recipe"
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  printf '#!/bin/bash\nexit 0\n' > "$sandbox/eco/recipes/nodesc.sh"
  chmod +x "$sandbox/eco/recipes/nodesc.sh"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "nodesc — run recipe" || { echo "No fallback DESC for recipe without DESC" >&2; return 1; }
}

# ─── TIER 20: Output Line Count / Size Regression ───

test_T190() {
  # Healthy widget produces at least 50 lines of output
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox" 3
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  local count
  count=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  [ "$count" -ge 50 ] || { echo "Only $count lines output (expected ≥50 for full widget)" >&2; return 1; }
}

test_T191() {
  # CLI mode produces no SwiftBar params anywhere
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox" 2
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" cli)
  local sb_params
  sb_params=$(printf '%s\n' "$out" | grep -c 'terminal=\|refresh=\|font=Menlo' || true)
  [ "$sb_params" -eq 0 ] || { echo "$sb_params SwiftBar params leaked into CLI mode" >&2; return 1; }
}

# ─── TIER 21: Recipe Edge Cases ───

test_T200() {
  # _lib recipe should be skipped (not shown in menu)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  printf '#!/bin/bash\n# DESC: library helpers\nexit 0\n' > "$sandbox/eco/recipes/_lib.sh"
  chmod +x "$sandbox/eco/recipes/_lib.sh"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_not_contains "$out" "_lib" || { echo "_lib recipe should be hidden" >&2; return 1; }
}

test_T201() {
  # Snapshot recipe gets special routing (run-logged fix-snapshot-timeout)
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # The snapshot recipe uses eco-alerts.sh run-logged, not direct execution
  assert_stdout_regex "$out" "snapshot.*run-logged\|snapshot.*eco-alerts" || \
    assert_stdout_contains "$out" "run snapshot" || \
    { echo "Snapshot recipe missing or no special routing" >&2; return 1; }
}

# ─── TIER 22: Provider Source Branch ───

test_T210() {
  # source: "api" still renders JSONL-grafted token breakdown details
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  jq '.claude.source = "api"' "$sandbox/eco/current/usage.json" > "$sandbox/eco/current/usage.tmp" \
    && mv "$sandbox/eco/current/usage.tmp" "$sandbox/eco/current/usage.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # OAuth/API can be authoritative for pct while JSONL adds local token detail.
  assert_stdout_contains "$out" "cache+" || { echo "Token breakdown missing for api payload with token fields" >&2; return 1; }
  # But session/weekly bars should still appear
  assert_stdout_contains "$out" "Session" || { echo "Session bar missing for api source" >&2; return 1; }
}

# ─── TIER 23: Ollama Edge Cases ───

test_T220() {
  # Ollama hidden from command discovery → no crash
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  local out
  out=$(run_widget "$sandbox" swiftbar "BASH_ENV=$(hide_command_env "$sandbox" ollama)")
  assert_exit "$sandbox" "0" || { echo "Crashed without ollama in PATH" >&2; return 1; }
}

# ─── TIER 24: Alert Layer Parsing ───

test_T230() {
  # Linf_wiring is fallback layer — only used when other layers are empty
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  cat > "$sandbox/eco/current/state.json" <<JSON
{"generated_at":"2026-05-20","snapshot_id":"test","layers":{"Linf_wiring":{"issues":[{"severity":"LOW","id":"WIRE-001","desc":"Wiring fallback issue"}]}}}
JSON
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # Linf_wiring issues should show when no other layers have issues
  assert_stdout_contains "$out" "1 Alert" || { echo "Linf_wiring fallback alert not counted" >&2; return 1; }
}

test_T231() {
  # Linf_wiring suppressed when other layers have issues
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  cat > "$sandbox/eco/current/state.json" <<JSON
{"generated_at":"2026-05-20","snapshot_id":"test","layers":{"L1_core":{"issues":[{"severity":"HIGH","id":"CORE-1","desc":"Real core issue"}]},"Linf_wiring":{"issues":[{"severity":"LOW","id":"WIRE-001","desc":"Wiring noise"}]}}}
JSON
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # Only the L1_core issue should show (1 alert), not the Linf_wiring one
  assert_stdout_contains "$out" "1 Alert" || { echo "Expected 1 alert (Linf_wiring should be suppressed)" >&2; return 1; }
  assert_stdout_not_contains "$out" "Wiring noise" || { echo "Linf_wiring noise leaked through" >&2; return 1; }
}

# ─── TIER 25: Snapshot Age Formatting ───

test_T240() {
  # Snapshot 2h old → age shows in hours with orange
  local sandbox="$1"
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json"
  install_state "$sandbox"
  touch -t $(date -v-2d +%Y%m%d%H%M) "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  # 2 days old → "stale" + orange
  assert_stdout_regex "$out" "Snapshot:.*stale" || { echo "2d old snapshot not marked stale" >&2; return 1; }
}

test_T241() {
  # Poller stale warning message includes threshold
  local sandbox="$1"
  local stale_ts=$(( $(date +%s) - 300 ))
  install_usage "$sandbox" "$FIXTURES/usage_healthy.json" "$stale_ts"
  install_state "$sandbox"
  touch "$sandbox/eco/current/state.json"
  local out
  out=$(run_widget "$sandbox" swiftbar)
  assert_stdout_contains "$out" "STALE" || { echo "Missing STALE marker for old poller data" >&2; return 1; }
  assert_stdout_contains "$out" "launchctl" || { echo "Missing launchctl hint for stale poller" >&2; return 1; }
}

# ═══════════════════════════════════════════════════════════════════════
# RUN ALL TESTS
# ═══════════════════════════════════════════════════════════════════════

echo
echo "═══════════════════════════════════════════════════════════════"
echo "  Eco Commander Widget — E2E Test Suite"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════════"
echo

echo -e "${CYAN}── TIER 1: Core Output Format ──${NC}"
run_test T001 "SwiftBar format: icon + --- separator"              test_T001
run_test T002 "CLI mode: header + no SwiftBar params"              test_T002
run_test T003 "Every menu item has | pipe separator"               test_T003
run_test T004 "Title is compact (≤10 chars)"                       test_T004
echo

echo -e "${CYAN}── TIER 2: Status Icon Logic ──${NC}"
run_test T010 "Green icon when all healthy"                        test_T010
run_test T011 "Red icon when quota ≥ 95%"                          test_T011
run_test T012 "Yellow icon when quota 80-94%"                      test_T012
run_test T013 "Red icon when snapshot very stale (>3d)"            test_T013
run_test T014 "Red icon when poller data stale (>180s)"            test_T014
echo

echo -e "${CYAN}── TIER 3: Missing Dependencies ──${NC}"
run_test T020 "No jq → graceful degradation"                       test_T020
run_test T021 "No usage.json → informative message"                test_T021
run_test T022 "No state.json → no crash"                           test_T022
run_test T023 "No profiles dir → no crash"                         test_T023
run_test T024 "No recipes dir → error message"                     test_T024
echo

echo -e "${CYAN}── TIER 4: Corrupt / Malformed Data ──${NC}"
run_test T030 "Corrupt usage.json (invalid JSON)"                  test_T030
run_test T031 "Empty usage.json (0 bytes)"                         test_T031
run_test T032 "usage.json is array instead of object"              test_T032
run_test T033 "Partial usage.json (missing fields)"                test_T033
run_test T034 "Corrupt state.json"                                 test_T034
run_test T035 "Null values in usage.json"                          test_T035
run_test T036 "Negative percentage values"                         test_T036
run_test T037 "Over-100% percentage values"                        test_T037
run_test T038 "String instead of number for pct"                   test_T038
echo

echo -e "${CYAN}── TIER 5: Boundary / Edge Cases ──${NC}"
run_test T040 "All meters at exactly 0%"                           test_T040
run_test T041 "All meters at exactly 100%"                         test_T041
run_test T042 "Exactly at WARN threshold (80%)"                    test_T042
run_test T043 "Exactly at CRIT threshold (95%)"                    test_T043
run_test T044 "Empty profile name"                                 test_T044
run_test T045 "Future timestamp (clock skew)"                      test_T045
run_test T046 "ts=0 (epoch) in usage.json"                         test_T046
echo

echo -e "${CYAN}── TIER 6: Sections Exist ──${NC}"
run_test T050 "All 7 sections present (SwiftBar)"                  test_T050
run_test T051 "All sections present (CLI)"                         test_T051
run_test T052 "Claude session + weekly with progress bars"         test_T052
run_test T053 "Gemini shows 3 tiers"                               test_T053
run_test T054 "Codex shows explicit org label"                     test_T054
echo

echo -e "${CYAN}── TIER 7: Stress / Performance ──${NC}"
run_test T060 "50 alerts → no crash, count correct"                test_T060
run_test T061 "20 recipes → no crash"                              test_T061
run_test T062 "10 MCP profiles → no crash"                         test_T062
run_test T063 "Runs under 5 seconds"                               test_T063
run_test T064 "3 concurrent instances → no crash"                  test_T064
echo

echo -e "${CYAN}── TIER 8: Provider Error States ──${NC}"
run_test T070 "Claude+Codex errors shown in dropdown"              test_T070
run_test T071 "All providers in error state → no crash"            test_T071
run_test T072 "Stale cache indicators shown"                       test_T072
echo

echo -e "${CYAN}── TIER 9: Suggestion Engine ──${NC}"
run_test T080 "Suggestion fires at 96%"                            test_T080
run_test T081 "No crash in suggestion logic at low quota"          test_T081
echo

echo -e "${CYAN}── TIER 10: humanize() ──${NC}"
run_test T090 "0 tokens → no crash"                                test_T090
run_test T091 "Trillion tokens → no crash"                         test_T091
echo

echo -e "${CYAN}── TIER 11: SwiftBar Action Params ──${NC}"
run_test T100 "Actions have terminal/refresh params"               test_T100
run_test T101 "bash= actions format valid"                         test_T101
echo

echo -e "${CYAN}── TIER 12: Alert System ──${NC}"
run_test T110 "0 alerts → green checkmark"                         test_T110
run_test T111 "Multiple alerts → count shown"                      test_T111
run_test T112 "Long alert desc → truncated"                        test_T112
echo

echo -e "${CYAN}── TIER 13: Output Stability ──${NC}"
run_test T120 "Deterministic output between runs"                  test_T120
run_test T121 "No blank lines in menu output"                      test_T121
echo

echo -e "${CYAN}── TIER 14: Suggestion Engine (priorities) ──${NC}"
run_test T130 "P2: LAST CALL at <20m reset"                        test_T130
run_test T131 "P4: SPRINT at <60m reset"                           test_T131
run_test T132 "P5: burn fast at <180m reset"                       test_T132
echo

echo -e "${CYAN}── TIER 15: Alternatives Section ──${NC}"
run_test T140 "Alternatives shows all 4 tools"                     test_T140
run_test T141 "No alternatives key → section hidden"               test_T141
echo

echo -e "${CYAN}── TIER 16: Domains Section ──${NC}"
run_test T150 "11 domains listed with D1-D11"                      test_T150
echo

echo -e "${CYAN}── TIER 17: Footer Section ──${NC}"
run_test T160 "Footer shows snapshot ID + refresh"                 test_T160
run_test T161 "Footer absent without state.json"                   test_T161
echo

echo -e "${CYAN}── TIER 18: Live Alert Verification ──${NC}"
run_test T170 "n8n alert verified live"                             test_T170
run_test T171 "Timeout alert → evidence status"                    test_T171
run_test T172 "Unknown alert → triage status"                      test_T172
echo

echo -e "${CYAN}── TIER 19: Permission & Environment ──${NC}"
run_test T180 "Unreadable usage.json → graceful"                   test_T180
run_test T181 "Unreadable state.json → graceful"                   test_T181
run_test T182 "Bad ECO_COMMANDER_REPO → fallback"                  test_T182
run_test T183 "Burn-rate comment shown"                             test_T183
run_test T184 "No comment → no empty bubble"                       test_T184
run_test T185 "System section all runtime probes"                   test_T185
run_test T186 "MCP current profile ✓ indicator"                    test_T186
run_test T187 "MCP non-current profile → arrow"                    test_T187
run_test T188 "Recipe DESC extraction"                              test_T188
run_test T189 "Recipe without DESC → fallback"                     test_T189
echo

echo -e "${CYAN}── TIER 20: Output Size Regression ──${NC}"
run_test T190 "Healthy widget ≥50 lines output"                    test_T190
run_test T191 "CLI mode: zero SwiftBar params"                      test_T191
echo

echo -e "${CYAN}── TIER 21: Recipe Edge Cases ──${NC}"
run_test T200 "_lib recipe hidden from menu"                        test_T200
run_test T201 "Snapshot recipe special routing"                      test_T201
echo

echo -e "${CYAN}── TIER 22: Provider Source Branch ──${NC}"
run_test T210 "source=api renders grafted token breakdown"           test_T210
echo

echo -e "${CYAN}── TIER 23: Ollama Edge Cases ──${NC}"
run_test T220 "Ollama not in PATH → no crash"                       test_T220
echo

echo -e "${CYAN}── TIER 24: Alert Layer Parsing ──${NC}"
run_test T230 "Linf_wiring fallback when no other issues"            test_T230
run_test T231 "Linf_wiring suppressed with real issues"              test_T231
echo

echo -e "${CYAN}── TIER 25: Snapshot Age & Stale Warnings ──${NC}"
run_test T240 "2d old snapshot marked stale"                         test_T240
run_test T241 "Poller stale warning + launchctl hint"                test_T241
echo

if [ -n "$FILTER" ] && [ $((PASS + FAIL)) -eq 0 ]; then
  echo "ERROR: no E2E test matched filter '$FILTER'" >&2
  FAIL=$((FAIL + 1))
  FAILURES+=("FILTER|No matching test|Unknown filter: $FILTER")
fi

# ═══════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
  printf "  ${GREEN}ALL %d TESTS PASSED${NC}" "$PASS"
else
  printf "  ${RED}%d FAILED${NC} · ${GREEN}%d passed${NC}" "$FAIL" "$PASS"
fi
[ "$SKIP" -gt 0 ] && printf " · ${YELLOW}%d skipped${NC}" "$SKIP"
printf "  (total: %d)\n" "$TOTAL"
echo "═══════════════════════════════════════════════════════════════"

# Write markdown report
{
  echo "# E2E Test Report — $(date '+%Y-%m-%d %H:%M:%S')"
  echo
  echo "| Metric | Count |"
  echo "|--------|-------|"
  echo "| ✅ Pass | $PASS |"
  echo "| ❌ Fail | $FAIL |"
  echo "| ⏭ Skip | $SKIP |"
  echo "| Total | $TOTAL |"
  echo
  if [ "${#FAILURES[@]}" -gt 0 ]; then
    echo "## ❌ Failures"
    echo
    echo "| ID | Test | Details |"
    echo "|----|------|---------|"
    for f in "${FAILURES[@]}"; do
      IFS='|' read -r fid fname fdetail <<< "$f"
      echo "| $fid | $fname | ${fdetail:0:100} |"
    done
    echo
    echo "Failure artifacts saved to: \`$RESULTS_DIR/failures/\`"
    echo
  fi
  echo "## ✅ Passes"
  echo
  for p in "${PASSES[@]+${PASSES[@]}}"; do
    echo "- $p"
  done
} > "$REPORT"

echo
echo "Results: $RESULTS_DIR"
echo "Report: $REPORT"
echo "Log:    $LOG"
echo

[ "$FAIL" -eq 0 ]
