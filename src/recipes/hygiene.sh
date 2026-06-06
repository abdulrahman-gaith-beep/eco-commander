#!/usr/bin/env bash
# Purpose: ~/.eco/ runtime hygiene watcher — RAM/swap/MCP/gemini-stuck monitor; state in ~/.eco/state.json; replaces session-scoped Claude Monitor loops.
# DESC: Mac hygiene watcher — RAM/swap/MCP/gemini-stuck monitor with state in ~/.eco/state.json
# INPUTS: subcommand: watch|watch-fg|snapshot|stop|status|tail|tail-high|install|uninstall
# OUTPUT: ~/.eco/state.json plus private hygiene logs under ~/.eco/hygiene/
# USES: macOS vm_stat, sysctl, pgrep, launchctl, and optional osascript notifications
# HUMAN: review status/log output and decide whether to stop or reduce workloads
#
# Designed 2026-05-12 to replace session-scoped Claude Monitor loops that died every
# 25 min from SIGURG signals. This version runs as a proper LaunchAgent-managed daemon.
#
# State output:
#   ~/.eco/state.json → adds "hygiene" namespace (atomic write via mv)
#   ~/.eco/hygiene/events.log → append-only line stream
#   ~/.eco/hygiene/HIGH.log → high-severity events only (SwiftBar/tail-friendly)
#   ~/.eco/hygiene/daemon.pid → daemon pidfile
#
# Subcommands:
#   eco hygiene watch       → start as LaunchAgent (recommended)
#   eco hygiene watch-fg    → run in foreground (for debugging)
#   eco hygiene snapshot    → one-shot state line, print + write
#   eco hygiene stop        → stop the LaunchAgent
#   eco hygiene status      → is daemon running? last event time?
#   eco hygiene tail        → tail -f the events log
#   eco hygiene install     → install + load the LaunchAgent (one-time)
#   eco hygiene uninstall   → unload + remove the LaunchAgent

set -euo pipefail

ECO="${ECO:-${ECO_HOME:-$HOME/.eco}}"
STATE_JSON="$ECO/state.json"
HYGIENE_DIR="${ECO_HYGIENE_DIR:-$ECO/hygiene}"
EVT_LOG="${ECO_HYGIENE_EVT_LOG:-$HYGIENE_DIR/events.log}"
HIGH_LOG="${ECO_HYGIENE_HIGH_LOG:-$HYGIENE_DIR/HIGH.log}"
PID_FILE="${ECO_HYGIENE_PID_FILE:-$HYGIENE_DIR/daemon.pid}"
LA_LABEL="com.eco-commander.hygiene"
LA_PLIST="$HOME/Library/LaunchAgents/${LA_LABEL}.plist"
DAEMON_INTERVAL="${ECO_HYGIENE_INTERVAL:-30}"

# Thresholds (override via env)
RED_MEM_GB="${ECO_HYGIENE_RED_MEM_GB:-3}"
YEL_MEM_GB="${ECO_HYGIENE_YEL_MEM_GB:-6}"
RED_SWAP_MB="${ECO_HYGIENE_RED_SWAP_MB:-6000}"
YEL_SWAP_MB="${ECO_HYGIENE_YEL_SWAP_MB:-5500}"
RED_MCP="${ECO_HYGIENE_RED_MCP:-80}"
YEL_MCP="${ECO_HYGIENE_YEL_MCP:-50}"
STUCK_GEMINI_MIN="${ECO_HYGIENE_STUCK_MIN:-20}"

ensure_hygiene_dir() {
  mkdir -p "$HYGIENE_DIR"
  chmod 700 "$HYGIENE_DIR" 2>/dev/null || true
}

append_private_log() {
  local file="$1" line="$2"
  ensure_hygiene_dir
  : >> "$file"
  chmod 600 "$file" 2>/dev/null || true
  printf '%s\n' "$line" >> "$file"
}

write_pid_file() {
  ensure_hygiene_dir
  printf '%s\n' "$$" > "$PID_FILE"
  chmod 600 "$PID_FILE" 2>/dev/null || true
}

# ──────────────────────────────────────────────────────────────────────
# Probe — collect one state sample
# Outputs: free_gb swap_mb mcp gem heavy stuck (space-separated)
probe() {
  local free_pg inac_pg free_gb swap_used_int mcp gem heavy stuck
  free_pg=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub(/\./,""); print $3; exit}')
  inac_pg=$(vm_stat 2>/dev/null | awk '/Pages inactive/{gsub(/\./,""); print $3; exit}')
  free_gb=$(( (${free_pg:-0} + ${inac_pg:-0}) * 16384 / 1024 / 1024 / 1024 ))

  swap_used_int=$(sysctl -n vm.swapusage 2>/dev/null \
    | sed -nE 's/.*used = ([0-9]+)\.[0-9]+M.*/\1/p')
  swap_used_int=${swap_used_int:-0}

  mcp=$(pgrep -fc '@modelcontextprotocol|@wonderwhy|mcp-server-(memory|filesystem|sequential)|node /opt/homebrew/bin/desktop-commander' 2>/dev/null || true)
  heavy=$(pgrep -fc 'max-old-space-size=18432' 2>/dev/null || true)
  gem=$(pgrep -fc 'opt/homebrew/bin/gemini -m gemini-3' 2>/dev/null || true)
  mcp=${mcp:-0}
  heavy=${heavy:-0}
  gem=${gem:-0}

  stuck=$(ps -eo etime,command 2>/dev/null \
    | awk -v t="$STUCK_GEMINI_MIN" '$0 !~ /grep/ && /max-old-space-size=18432/ {
        et=$1
        if (et ~ /-/) {n++; next}
        if (et ~ /:[0-9]{2}:/) { split(et,a,":"); if (a[1]+0 >= t) n++ }
      } END { print n+0 }')

  printf '%s %s %s %s %s %s\n' \
    "$free_gb" "$swap_used_int" "$mcp" "$gem" "$heavy" "$stuck"
}

# ──────────────────────────────────────────────────────────────────────
# Classify — given a probe sample, return: severity|alert_string
classify() {
  local free_gb=$1 swap_mb=$2 mcp=$3 stuck=$6
  local alert="" sev="OK"
  if [ "$free_gb" -lt "$RED_MEM_GB" ]   2>/dev/null; then sev=RED; alert="$alert RED-MEM(${free_gb}G)"; fi
  if [ "$swap_mb" -gt "$RED_SWAP_MB" ]  2>/dev/null; then sev=RED; alert="$alert RED-SWAP(${swap_mb}M)"; fi
  if [ "$mcp" -gt "$RED_MCP" ]          2>/dev/null; then sev=RED; alert="$alert RED-MCP($mcp)"; fi
  if [ "$stuck" -gt 0 ]                 2>/dev/null; then sev=RED; alert="$alert STUCK-GEMINI($stuck)"; fi
  if [ "$sev" = OK ]; then
    if [ "$free_gb" -lt "$YEL_MEM_GB" ] 2>/dev/null; then sev=YEL; alert="$alert YEL-MEM(${free_gb}G)"; fi
    if [ "$mcp" -gt "$YEL_MCP" ] && [ "$mcp" -lt "$RED_MCP" ] 2>/dev/null; then sev=YEL; alert="$alert YEL-MCP($mcp)"; fi
    if [ "$swap_mb" -gt "$YEL_SWAP_MB" ] && [ "$swap_mb" -lt "$RED_SWAP_MB" ] 2>/dev/null; then sev=YEL; alert="$alert YEL-SWAP(${swap_mb}M)"; fi
  fi
  printf '%s|%s\n' "$sev" "${alert# }"
}

# ──────────────────────────────────────────────────────────────────────
# Update state.json atomically (merges into hygiene namespace)
update_state_json() {
  local sev="$1" alert="$2"
  local sample="$3"
  local ts; ts=$(date -u +%FT%TZ)
  mkdir -p "$ECO"
  local tmp; tmp=$(mktemp)
  read -r free_gb swap_mb mcp gem heavy stuck <<<"$sample"
  # Read existing state if present, else start fresh
  if [ -f "$STATE_JSON" ]; then
    python3 - "$STATE_JSON" "$tmp" "$ts" "$sev" "$alert" "$free_gb" "$swap_mb" "$mcp" "$gem" "$heavy" "$stuck" <<'PY' 2>/dev/null
import json, sys
src, dst, ts, sev, alert, *vals = sys.argv[1:]
free_gb, swap_mb, mcp, gem, heavy, stuck = [int(v) for v in vals]
try:
    with open(src) as f: state = json.load(f)
except Exception:
    state = {}
state["hygiene"] = {
    "ts": ts, "severity": sev, "alert": alert,
    "free_gb": free_gb, "swap_mb": swap_mb,
    "mcp": mcp, "gem": gem, "heavy": heavy, "stuck": stuck,
}
with open(dst, "w") as f: json.dump(state, f, indent=2)
PY
  else
    cat > "$tmp" <<EOF
{
  "hygiene": {
    "ts": "$ts", "severity": "$sev", "alert": "$alert",
    "free_gb": $free_gb, "swap_mb": $swap_mb,
    "mcp": $mcp, "gem": $gem, "heavy": $heavy, "stuck": $stuck
  }
}
EOF
  fi
  mv -f "$tmp" "$STATE_JSON" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────
# One probe + log + state update + optional notify on RED
snapshot() {
  local quiet="${1:-}"
  local sample sev_alert sev alert
  local -a sample_fields
  sample=$(probe)
  read -r -a sample_fields <<< "$sample"
  sev_alert=$(classify "${sample_fields[@]}")
  sev=${sev_alert%%|*}
  alert=${sev_alert#*|}
  local ts; ts=$(date +%H:%M:%S)
  read -r free_gb swap_mb mcp gem heavy stuck <<<"$sample"
  local line="[$ts] $sev mem=${free_gb}G swap=${swap_mb}M mcp=$mcp gem=$gem heavy=$heavy stuck=$stuck"
  [ -n "$alert" ] && line="$line — $alert"

  update_state_json "$sev" "$alert" "$sample"
  append_private_log "$EVT_LOG" "$line"
  if [ "$sev" = RED ]; then
    append_private_log "$HIGH_LOG" "$line"
    # macOS notification (best-effort)
    osascript -e "display notification \"$alert\" with title \"eco hygiene RED\"" 2>/dev/null &
  fi
  [ -z "$quiet" ] && echo "$line"
}

# ──────────────────────────────────────────────────────────────────────
# Daemon loop — for LaunchAgent or watch-fg
daemon_loop() {
  trap '' SIGURG SIGHUP SIGPIPE
  write_pid_file
  append_private_log "$EVT_LOG" "[$(date +%H:%M:%S)] eco hygiene daemon start pid=$$ interval=${DAEMON_INTERVAL}s"
  local heartbeat=0
  local prev_sev=""
  while true; do
    local sample sev_alert sev alert
    local -a sample_fields
    sample=$(probe)
    read -r -a sample_fields <<< "$sample"
    sev_alert=$(classify "${sample_fields[@]}")
    sev=${sev_alert%%|*}
    alert=${sev_alert#*|}
    update_state_json "$sev" "$alert" "$sample"

    # Only emit when severity changes OR every 10 cycles (5 min heartbeat)
    local should_emit=0
    [ "$sev" != "$prev_sev" ] && should_emit=1
    [ "$heartbeat" -ge 10 ] && should_emit=1 && heartbeat=0

    if [ "$should_emit" = 1 ]; then
      local ts; ts=$(date +%H:%M:%S)
      read -r free_gb swap_mb mcp gem heavy stuck <<<"$sample"
      local line="[$ts] $sev mem=${free_gb}G swap=${swap_mb}M mcp=$mcp gem=$gem heavy=$heavy stuck=$stuck"
      [ -n "$alert" ] && line="$line — $alert"
      append_private_log "$EVT_LOG" "$line"
      if [ "$sev" = RED ]; then
        append_private_log "$HIGH_LOG" "$line"
        osascript -e "display notification \"$alert\" with title \"eco hygiene RED\"" 2>/dev/null &
      fi
      prev_sev="$sev"
    fi
    heartbeat=$((heartbeat + 1))
    sleep "$DAEMON_INTERVAL" 2>/dev/null || sleep "$DAEMON_INTERVAL"
  done
}

# ──────────────────────────────────────────────────────────────────────
# LaunchAgent install/uninstall
validate_plist() {
  python3 - "$1" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as f:
    plistlib.load(f)
PY
}

install_la() {
  local la_dir tmp_plist
  ensure_hygiene_dir
  la_dir="$(dirname "$LA_PLIST")"
  mkdir -p "$la_dir"
  tmp_plist="$(mktemp "$la_dir/${LA_LABEL}.plist.XXXXXX")"

  if ! cat > "$tmp_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LA_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$HOME/.eco/recipes/hygiene.sh</string>
    <string>watch-fg</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict>
    <key>Crashed</key><true/>
    <key>SuccessfulExit</key><false/>
  </dict>
  <key>StandardOutPath</key><string>$HYGIENE_DIR/stdout.log</string>
  <key>StandardErrorPath</key><string>$HYGIENE_DIR/stderr.log</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ThrottleInterval</key><integer>30</integer>
</dict>
</plist>
EOF
  then
    echo "Error: failed to write plist: $tmp_plist" >&2
    rm -f "$tmp_plist"
    exit 1
  fi

  if [[ ! -s "$tmp_plist" ]]; then
    echo "Error: plist write produced an empty file: $tmp_plist" >&2
    rm -f "$tmp_plist"
    exit 1
  fi

  if ! validate_plist "$tmp_plist"; then
    echo "Error: generated plist failed validation: $tmp_plist" >&2
    rm -f "$tmp_plist"
    exit 1
  fi

  mv -f "$tmp_plist" "$LA_PLIST"
  if ! validate_plist "$LA_PLIST"; then
    echo "Error: installed plist failed validation: $LA_PLIST" >&2
    rm -f "$LA_PLIST"
    exit 1
  fi

  echo "Installed plist: $LA_PLIST"
}

# ──────────────────────────────────────────────────────────────────────
case "${1:-status}" in
  watch)
    [ ! -f "$LA_PLIST" ] && { install_la; }
    launchctl unload "$LA_PLIST" 2>/dev/null || true
    launchctl load   "$LA_PLIST" || { echo "launchctl load failed"; exit 1; }
    sleep 1
    echo "eco hygiene daemon loaded. tail with: eco hygiene tail"
    ;;
  watch-fg|daemon)
    daemon_loop
    ;;
  snapshot|now)
    snapshot
    ;;
  stop)
    if [ -f "$LA_PLIST" ]; then
      launchctl unload "$LA_PLIST" 2>/dev/null && echo "eco hygiene daemon stopped"
    fi
    if [ -f "$PID_FILE" ]; then
      rm -f "$PID_FILE"
    fi
    ;;
  status)
    if launchctl list | grep -q "$LA_LABEL"; then
      echo "daemon: LOADED ($(launchctl list | awk -v l="$LA_LABEL" '$3==l{print "pid="$1}'))"
    else
      echo "daemon: STOPPED"
    fi
    if [ -f "$STATE_JSON" ] && command -v python3 >/dev/null; then
      python3 -c "
import json
try:
    d = json.load(open('$STATE_JSON')).get('hygiene', {})
    if d:
        print(f\"last: {d.get('ts','?')} sev={d.get('severity','?')} mem={d.get('free_gb','?')}G swap={d.get('swap_mb','?')}M mcp={d.get('mcp','?')} gem={d.get('gem','?')} stuck={d.get('stuck','?')}\")
        a = d.get('alert')
        if a: print(f\"alert: {a}\")
except Exception as e: pass
"
    fi
    last_evt=$(tail -1 "$EVT_LOG" 2>/dev/null || true)
    if [ -n "$last_evt" ]; then
      echo "log:  $last_evt"
    fi
    ;;
  tail)
    [ ! -f "$EVT_LOG" ] && { echo "no event log yet at $EVT_LOG"; exit 0; }
    exec tail -F "$EVT_LOG"
    ;;
  tail-high)
    [ ! -f "$HIGH_LOG" ] && { echo "no high-severity events yet"; exit 0; }
    exec tail -F "$HIGH_LOG"
    ;;
  install)
    install_la
    ;;
  uninstall)
    launchctl unload "$LA_PLIST" 2>/dev/null || true
    rm -f "$LA_PLIST" && echo "removed $LA_PLIST"
    ;;
  help|-h|--help)
    sed -n '2,25p' "$0"
    ;;
  *)
    echo "Usage: eco hygiene {watch|watch-fg|snapshot|stop|status|tail|tail-high|install|uninstall}"
    exit 1
    ;;
esac
