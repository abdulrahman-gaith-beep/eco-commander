#!/usr/bin/env bash
# Single-command end-to-end health check for the eco-commander widget +
# usage poller. Exits 0 if everything is green, non-zero with the first
# failed check.
#
# Usage:
#   bash scripts/healthcheck.sh
#   bash scripts/healthcheck.sh --json
#
# Designed to run from any environment, including the restricted PATH
# SwiftBar provides — so it doubles as a regression test for future
# PATH-related breakage.

set -uo pipefail

# Apply the same PATH preamble all installed scripts use.
for _p in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" /opt/homebrew/sbin; do
  case ":$PATH:" in *":$_p:"*) ;; *) PATH="$_p:$PATH" ;; esac
done
export PATH
unset _p

ECO_HOME="${ECO_HOME:-$HOME/.eco}"
SWIFTBAR_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LA_DIR="$HOME/Library/LaunchAgents"
CHECK_MACOS_SURFACES="${ECO_HEALTHCHECK_MACOS_SURFACES:-0}"
CHECK_LIVE_RUNTIME="${ECO_HEALTHCHECK_LIVE_RUNTIME:-0}"

OK=0
FAIL=0
RESULTS=()

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    OK=$((OK+1))
    RESULTS+=("✓ $name")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("✗ $name")
  fi
}

# 1. Required binaries on PATH
check "binary: jq"        command -v jq
check "binary: python3"   command -v python3
check "binary: qlmanage"  command -v qlmanage
check "binary: osascript" command -v osascript
check "binary: pbcopy"    command -v pbcopy
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  OK=$((OK+1)); RESULTS+=("✓ binary: timeout/gtimeout")
else
  RESULTS+=("○ binary: timeout/gtimeout missing (snapshot falls back to uncapped optional probes)")
fi

# 2. macOS integration checks are opt-in so agent runs never touch user Library paths.
if [ "$CHECK_MACOS_SURFACES" = "1" ]; then
  check "plist: usage-poller exists"  test -f "$LA_DIR/com.eco-commander.usage-poller.plist"
  check "plist: swiftbar exists"      test -f "$LA_DIR/com.eco-commander.swiftbar.plist"
  check "plist: usage-poller valid"   plutil -lint "$LA_DIR/com.eco-commander.usage-poller.plist"
  check "plist: swiftbar valid"       plutil -lint "$LA_DIR/com.eco-commander.swiftbar.plist"
  check "launchctl: usage-poller loaded" bash -c "launchctl list | grep -q com.eco-commander.usage-poller"
  check "launchctl: swiftbar loaded"     bash -c "launchctl list | grep -q com.eco-commander.swiftbar"
  check "swiftbar: eco-commander.15s.sh symlink" test -L "$SWIFTBAR_DIR/eco-commander.15s.sh"
  check "app: SwiftBar.app present" test -d "/Applications/SwiftBar.app"
  check "process: SwiftBar running"  pgrep -fq "SwiftBar.app/Contents/MacOS/SwiftBar"
else
  RESULTS+=("○ macOS integration checks skipped (set ECO_HEALTHCHECK_MACOS_SURFACES=1)")
fi

# 6. Live runtime data checks are opt-in; default agent-safe runs use fixtures.
if [ "$CHECK_LIVE_RUNTIME" = "1" ]; then
  USAGE_JSON="$ECO_HOME/current/usage.json"
  check "data: usage.json exists" test -f "$USAGE_JSON"
  if [ -f "$USAGE_JSON" ]; then
    AGE=$(( $(date +%s) - $(stat -f %m "$USAGE_JSON") ))
    if [ "$AGE" -le 180 ]; then
      OK=$((OK+1)); RESULTS+=("✓ data: usage.json fresh ($AGE s old)")
    else
      FAIL=$((FAIL+1)); RESULTS+=("✗ data: usage.json STALE ($AGE s old; >180s)")
    fi
  fi
else
  RESULTS+=("○ live runtime data checks skipped (set ECO_HEALTHCHECK_LIVE_RUNTIME=1)")
fi

# 7. Snapshot script runs cleanly under SwiftBar's restricted PATH
safe_rm_tmp_dir() {
  local d
  for d in "$@"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    case "$d" in
      /tmp/*|/var/folders/*|/private/var/folders/*) rm -R "$d" ;;
    esac
  done
}

TMP_OUT=$(mktemp -d)
TMP_ECO=$(mktemp -d)
TMP_HOME=$(mktemp -d)
TMP_LOG=$(mktemp)
mkdir -p "$TMP_ECO/current"
sed "s/__NOW__/$(date +%s)/" "$REPO_ROOT/tests/e2e/fixtures/usage_healthy.json" > "$TMP_ECO/current/usage.json"
env -i HOME="$TMP_HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  ECO_HOME="$TMP_ECO" ECO_SNAPSHOT_DIR="$TMP_OUT" \
  ECO_SNAPSHOT_CLIPBOARD=0 ECO_SNAPSHOT_REVEAL=0 ECO_SNAPSHOT_NOTIFY=0 \
  bash "$REPO_ROOT/scripts/usage-snapshot.sh" >"$TMP_LOG" 2>&1
SNAP_EXIT=$?
SNAP_PNG=$(find "$TMP_OUT" -maxdepth 1 -type f -name 'eco-usage-*.png' -print -quit 2>/dev/null)
SNAP_TXT=$(find "$TMP_OUT" -maxdepth 1 -type f -name 'eco-usage-*.txt' -print -quit 2>/dev/null)
if [ "$SNAP_EXIT" -eq 0 ] && [ -n "$SNAP_PNG" ] && [ -n "$SNAP_TXT" ]; then
  OK=$((OK+1)); RESULTS+=("✓ snapshot: runs under restricted PATH")
else
  FAIL=$((FAIL+1)); RESULTS+=("✗ snapshot: FAILED under restricted PATH (exit=$SNAP_EXIT)")
  RESULTS+=("    log: $TMP_LOG")
fi
safe_rm_tmp_dir "$TMP_OUT" "$TMP_ECO" "$TMP_HOME"
[ "$SNAP_EXIT" -eq 0 ] && rm -f "$TMP_LOG"

# 8. Widget renders under restricted PATH (sanity check)
TMP_WIDGET_HOME=$(mktemp -d)
TMP_WIDGET_ECO=$(mktemp -d)
mkdir -p "$TMP_WIDGET_ECO/current" "$TMP_WIDGET_ECO/recipes" "$TMP_WIDGET_ECO/bin" "$TMP_WIDGET_HOME/.ai-ecosystem"
printf 'core\n' > "$TMP_WIDGET_HOME/.ai-ecosystem/.current-profile"
printf '{"snapshot_id":"healthcheck","generated_at":"synthetic","layers":{"Linf_wiring":{"issues":[]}}}\n' > "$TMP_WIDGET_ECO/current/state.json"
sed "s/__NOW__/$(date +%s)/" "$REPO_ROOT/tests/e2e/fixtures/usage_healthy.json" > "$TMP_WIDGET_ECO/current/usage.json"
WIDGET_OUT=$(env -i HOME="$TMP_WIDGET_HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
              ECO_HOME="$TMP_WIDGET_ECO" ECO_COMMANDER_REPO="$REPO_ROOT" \
              bash "$REPO_ROOT/src/bin/eco-commander.15s.sh" 2>&1 | head -1 || true)
if echo "$WIDGET_OUT" | grep -qE '^(🟢|🟡|🔴)$'; then
  OK=$((OK+1)); RESULTS+=("✓ widget: renders status icon under restricted PATH")
else
  FAIL=$((FAIL+1)); RESULTS+=("✗ widget: failed to render — got: ${WIDGET_OUT:0:80}")
fi
safe_rm_tmp_dir "$TMP_WIDGET_HOME" "$TMP_WIDGET_ECO"

# 9. Disk for log dir
if [ "$CHECK_LIVE_RUNTIME" = "1" ]; then
  LOGS_DIR="$ECO_HOME/logs"
  if [ -d "$LOGS_DIR" ]; then
    TOTAL_KB=$(du -sk "$LOGS_DIR" 2>/dev/null | awk '{print $1}')
    if [ "${TOTAL_KB:-0}" -lt 50000 ]; then
      OK=$((OK+1)); RESULTS+=("✓ logs: $LOGS_DIR is ${TOTAL_KB:-0} KB (<50 MB)")
    else
      FAIL=$((FAIL+1)); RESULTS+=("⚠ logs: $LOGS_DIR is ${TOTAL_KB} KB — install log rotation")
    fi
  fi
else
  RESULTS+=("○ live log size check skipped (set ECO_HEALTHCHECK_LIVE_RUNTIME=1)")
fi

# Output
if [ "${1:-}" = "--json" ]; then
  printf '{"ok":%d,"fail":%d,"results":[' "$OK" "$FAIL"
  for i in "${!RESULTS[@]}"; do
    [ "$i" -gt 0 ] && printf ','
    printf '%s' "$(printf '%s' "${RESULTS[$i]}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  done
  printf ']}\n'
else
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  echo
  echo "── Summary ── ✓ $OK passed · ✗ $FAIL failed"
fi

[ "$FAIL" -eq 0 ]
