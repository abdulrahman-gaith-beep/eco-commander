# helpers/common.bash — shared setup for every eco bats test
#
# Usage in a .bats file:
#   load '../helpers/common.bash'
#   setup()    { eco_setup; }
#   teardown() { eco_teardown; }
#
# Guarantees:
#   - $HOME is a fresh tmpdir per test
#   - $HOME/.eco/ has a minimal skeleton copied from the real source
#   - PATH is prepended with our stub dir (no real external calls)
#   - $HOME/.stub-*.log files accumulate call records
#   - nothing writes outside $HOME

# Capture the real HOME before any mutation. This is the key to portability.
# ORIG_HOME is set once here and never changed — sandbox tests mutate $HOME.
: "${ORIG_HOME:=$HOME}"
: "${ORIG_PATH:=$PATH}"

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HELPER_DIR/../.." && pwd)"

# Real source lives in the working tree by default, so tests cover uncommitted
# changes instead of whatever happens to be installed under ~/.eco.
: "${ECO_TEST_ROOT:=$REPO_ROOT/tests}"
: "${ECO_REAL_ROOT:=$REPO_ROOT/src}"
: "${ECO_REAL_SRC:=$ECO_REAL_ROOT}"

eco_setup() {
  # Snapshot the real tests root BEFORE mutating HOME
  export ECO_TESTS_REAL="${ECO_TESTS_REAL:-$ECO_TEST_ROOT}"
  export ECO_REAL_SRC="${ECO_REAL_SRC:-$ECO_REAL_ROOT}"

  # Fresh sandbox
  export SANDBOX="$(mktemp -d "${ECO_BATS_TMPDIR:-/tmp}/eco-bats.XXXXXX")"
  export ORIG_HOME="${ORIG_HOME:-$HOME}"
  export HOME="$SANDBOX"

  # Build skeleton
  mkdir -p "$HOME/.eco/bin" \
           "$HOME/.eco/recipes" \
           "$HOME/.eco/current" \
           "$HOME/.eco/snapshots" \
           "$HOME/.eco/reasons" \
           "$HOME/.eco/reports" \
           "$HOME/.ai-ecosystem/profiles" \
           "$HOME/.ai-memory/spaces" \
           "$HOME/.claude/hooks" \
           "$HOME/.eco/ecosystem-audit/prompts" \
           "$HOME/Documents/research"

  # Copy real source under test
  cp "$ECO_REAL_SRC/bin/eco" "$HOME/.eco/bin/eco"
  cp "$ECO_REAL_SRC/bin/eco-commander.15s.sh" "$HOME/.eco/bin/eco-commander.15s.sh"
  [ -f "$ECO_REAL_SRC/bin/ai-clear.sh" ] && cp "$ECO_REAL_SRC/bin/ai-clear.sh" "$HOME/.eco/bin/ai-clear.sh"
  [ -f "$ECO_REAL_SRC/bin/eco-alerts.sh" ] && cp "$ECO_REAL_SRC/bin/eco-alerts.sh" "$HOME/.eco/bin/eco-alerts.sh"
  chmod +x "$HOME/.eco/bin/eco" "$HOME/.eco/bin/eco-commander.15s.sh" "$HOME/.eco/bin/ai-clear.sh" "$HOME/.eco/bin/eco-alerts.sh" 2>/dev/null || true

  # Copy all recipes
  for r in "$ECO_REAL_SRC/recipes/"*.sh; do
    [ -f "$r" ] && cp "$r" "$HOME/.eco/recipes/"
  done
  chmod +x "$HOME/.eco/recipes/"*.sh 2>/dev/null || true

  # Fixture state.json (good)
  cp "$ECO_TESTS_REAL/fixtures/state.json.good" "$HOME/.eco/current/state.json" 2>/dev/null || \
    echo '{"snapshot_id":"test","generated_at":"2026-04-18","layers":{"Linf_wiring":{"issues":[]}}}' \
      > "$HOME/.eco/current/state.json"

  # Placeholder view files
  echo "<html>dashboard</html>" > "$HOME/.eco/current/dashboard.html"
  echo "# map" > "$HOME/.eco/current/map.md"

  # Current profile (for commander)
  echo "core" > "$HOME/.ai-ecosystem/.current-profile"
  cat > "$HOME/.ai-ecosystem/switch-profile.sh" <<'SH'
#!/usr/bin/env bash
set -u

profile="${1:-}"
profile_file="$HOME/.ai-ecosystem/profiles/${profile}.mcpServers.json"
current_file="$HOME/.ai-ecosystem/.current-profile"

if [ -z "$profile" ]; then
  echo "usage: switch-profile.sh PROFILE" >&2
  exit 1
fi

if [ ! -f "$profile_file" ]; then
  echo "profile not found: $profile" >&2
  exit 1
fi

if ! python3 - "$profile_file" <<'PY' >/dev/null 2>&1; then
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    json.load(f)
PY
  echo "invalid profile JSON: $profile_file"
  exit 1
fi

echo "Switching to profile: $profile"
updated=0

if [ -d "$HOME/.cursor" ]; then
  cp "$profile_file" "$HOME/.cursor/mcp.json"
  echo "Cursor: updated"
  updated=$((updated + 1))
fi

if [ -f "$HOME/.gemini/settings.json" ]; then
  if ! python3 - "$HOME/.gemini/settings.json" <<'PY' >/dev/null 2>&1; then
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    json.load(f)
PY
    echo "Gemini CLI: invalid settings JSON"
    echo "Active profile was NOT changed"
    exit 2
  fi
  echo "Gemini CLI: checked"
fi

printf '%s\n' "$profile" > "$current_file"
echo "Summary: $updated updated"
SH
  chmod +x "$HOME/.ai-ecosystem/switch-profile.sh"

  # Point the widget/recipes at the real repo so shipped doc links resolve
  export ECO_COMMANDER_REPO="$(cd "$ECO_TESTS_REAL/.." 2>/dev/null && pwd)"

  # Prepend stub dir to PATH
  export PATH="$ECO_TESTS_REAL/helpers/stubs:$PATH"

  # Default stub behavior knobs (tests override)
  export STUB_OLLAMA_RUNNING=1
  export STUB_OLLAMA_LOADED="qwen2.5:3b"
  export STUB_OLLAMA_LIST=$'qwen2.5:3b\t-\t2.0 GB\t-\nqwen3.6:latest\t-\t24 GB\t-\nbge-m3:latest\t-\t1.2 GB\t-'
  export STUB_GEMINI_OUTPUT="stub gemini response"
  export STUB_CURL_EXIT=0

  # Deterministic vm_stat/sysctl output for RAM math
  export STUB_PAGE_SIZE=16384
  export STUB_PAGES_FREE=100000      # ~1.5 GB free
  export STUB_PAGES_INACTIVE=200000  # ~3 GB inactive
  export STUB_PAGES_PURGEABLE=50000  # ~800 MB purgeable
  export STUB_PAGES_SPECULATIVE=10000

  export ECO_BIN="$HOME/.eco/bin/eco"
  export ECO_CMD="$HOME/.eco/bin/eco-commander.15s.sh"
  export SWITCH_PROFILE_BIN="$HOME/.ai-ecosystem/switch-profile.sh"
}

eco_usage_monitor_setup() {
  export ECO_TESTS_REAL="${ECO_TESTS_REAL:-$ECO_TEST_ROOT}"
  export ORIG_HOME="${ORIG_HOME:-$HOME}"
  export ORIG_PATH="${ORIG_PATH:-$PATH}"

  local real_python="${PYTHON:-}"
  if [ -z "$real_python" ]; then
    real_python="$(command -v python3 || true)"
  else
    real_python="$(command -v "$real_python" || true)"
  fi

  export SANDBOX="$(mktemp -d "${ECO_BATS_TMPDIR:-/tmp}/eco-bats-usage.XXXXXX")"
  export HOME="$SANDBOX/home"
  export ECO_HOME="$HOME/.eco"
  export ECO_COMMANDER_REPO="$REPO_ROOT"

  mkdir -p "$ECO_HOME/current" \
           "$ECO_HOME/logs" \
           "$HOME/.ai-ecosystem/profiles" \
           "$HOME/.claude/projects/fixture" \
           "$HOME/.codex/sessions/fixture" \
           "$HOME/.gemini/accounts"

  echo "core" > "$HOME/.ai-ecosystem/.current-profile"
  cat > "$ECO_HOME/config.json" <<'JSON'
{"server_truth":{"claude":false,"gemini":false,"codex":false}}
JSON

  local now_iso
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cat > "$HOME/.claude/projects/fixture/session.jsonl" <<JSON
{"type":"assistant","timestamp":"$now_iso","message":{"id":"msg-fixture","model":"claude-sonnet-4","usage":{"input_tokens":100,"output_tokens":25,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSON
  cat > "$HOME/.codex/sessions/fixture/session.jsonl" <<JSON
{"timestamp":"$now_iso","usage":{"input_tokens":40,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":5,"total_tokens":55}}
JSON
  cat > "$HOME/.gemini/oauth_creds.json" <<'JSON'
{"access_token":"fake-access-token","refresh_token":"fake-refresh-token","expiry_date":0}
JSON

  export PATH="$ECO_TESTS_REAL/helpers/stubs:$ORIG_PATH"
  [ -n "$real_python" ] && export PYTHON="$real_python"
  export STUB_CURL_EXIT=1
  export STUB_OLLAMA_RUNNING=0
}

eco_teardown() {
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && [[ "$SANDBOX" == /*eco-bats* ]]; then
    rm -rf "$SANDBOX"
  fi
  export HOME="${ORIG_HOME:-$HOME}"
  export PATH="${ORIG_PATH:-$PATH}"
}

# --- assertions ----------------------------------------------------

assert_success() {
  if [ "$status" -ne 0 ]; then
    echo "Expected status 0, got $status"
    echo "--- stdout ---"
    echo "$output"
    return 1
  fi
}

assert_failure() {
  local expected_code="${1:-}"
  if [ "$status" -eq 0 ]; then
    echo "Expected nonzero status, got 0"
    echo "--- stdout ---"
    echo "$output"
    return 1
  fi
  if [ -n "$expected_code" ] && [ "$status" -ne "$expected_code" ]; then
    echo "Expected status $expected_code, got $status"
    return 1
  fi
}

assert_output_contains() {
  local needle="$1"
  if [[ "$output" != *"$needle"* ]]; then
    echo "Expected output to contain: $needle"
    echo "--- actual output ---"
    echo "$output"
    return 1
  fi
}

assert_output_not_contains() {
  local needle="$1"
  if [[ "$output" == *"$needle"* ]]; then
    echo "Expected output NOT to contain: $needle"
    echo "--- actual output ---"
    echo "$output"
    return 1
  fi
}

assert_stub_called() {
  local stub="$1"
  local log="$HOME/.stub-${stub}.log"
  if [ ! -s "$log" ]; then
    echo "Expected stub '$stub' to be called (log: $log)"
    [ -f "$log" ] && echo "log exists but is empty"
    return 1
  fi
}

assert_stub_args_contain() {
  local stub="$1"; shift
  local needle="$*"
  local log="$HOME/.stub-${stub}.log"
  if ! grep -qF -- "$needle" "$log" 2>/dev/null; then
    echo "Expected stub '$stub' to be called with args containing: $needle"
    echo "--- $log ---"
    [ -f "$log" ] && cat "$log"
    return 1
  fi
}
