#!/usr/bin/env bash
# DESC: Refresh dashboard metric placeholders from live ecosystem state
# INPUTS: [dashboard_html]
# OUTPUT: rewrites <span class=metric data-id=...>NUMBER</span> placeholders in place
# USES: sed (BSD/macOS), python3, optional agent/MCP/plugin metadata, ~/.eco/current/state.json
# HUMAN: points it at a dashboard that already contains metric placeholders
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: dashboard-refresh.sh [dashboard.html]

Rewrites metric placeholders in-place using live ecosystem state.

Defaults:
  dashboard.html   ~/.eco/current/dashboard.html

Environment overrides:
  DASHBOARD_HTML   target dashboard file
  AGENTS_DIR       optional agent markdown directory (missing counts as 0)
  MCP_MASTER       optional MCP registry JSON (missing counts as 0)
  CLAUDE_SETTINGS  optional Claude settings JSON (missing counts as 0)
  STATE_JSON       defaults to <dashboard dir>/state.json

Supported metric ids:
  agents, agent-count, agent_count
  mcps, mcp, mcp-count, mcp_count, mcp-servers, mcp_servers
  plugins, plugin-count, plugin_count
  snapshot-age, snapshot_age, snapshot-days, snapshot_days
  snapshot-age-days, snapshot_age_days
  snapshot-hours, snapshot_hours
  snapshot-age-hours, snapshot_age_hours
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

DASHBOARD_HTML="${1:-${DASHBOARD_HTML:-$HOME/.eco/current/dashboard.html}}"
if dashboard_dir="$(cd "$(dirname "$DASHBOARD_HTML")" 2>/dev/null && pwd)"; then
  :
else
  dashboard_dir="$(dirname "$DASHBOARD_HTML")"
fi
AGENTS_DIR="${AGENTS_DIR:-$HOME/.claude/agents}"
MCP_MASTER="${MCP_MASTER:-$HOME/.ai-ecosystem/mcp-master.json}"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
STATE_JSON="${STATE_JSON:-$dashboard_dir/state.json}"

require_file() {
  if [ ! -f "$1" ]; then
    echo "Missing file: $1" >&2
    exit 1
  fi
}

require_dir() {
  if [ ! -d "$1" ]; then
    echo "Missing directory: $1" >&2
    exit 1
  fi
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi

require_file "$DASHBOARD_HTML"

count_agents() {
  if [ ! -d "$AGENTS_DIR" ]; then
    echo 0
    return 0
  fi

  find "$AGENTS_DIR" -type f -name "*.md" ! -path "*/_archived/*" 2>/dev/null \
    | wc -l \
    | awk '{print $1}'
}

count_mcps() {
  if [ ! -f "$MCP_MASTER" ]; then
    echo 0
    return 0
  fi

  python3 - "$MCP_MASTER" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

print(len(data.get("mcpServers", {})))
PY
}

count_plugins() {
  if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo 0
    return 0
  fi

  python3 - "$CLAUDE_SETTINGS" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

enabled = data.get("enabledPlugins", {})
print(sum(1 for value in enabled.values() if value is True))
PY
}

snapshot_age_hours() {
  python3 - "$STATE_JSON" "$DASHBOARD_HTML" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

state_path = Path(sys.argv[1])
dashboard_path = Path(sys.argv[2])

def parse_ts(raw: str):
    raw = raw.strip()
    if not raw:
        return None
    if raw.endswith("Z") and raw[-2:] != "MZ":
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(raw)
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except ValueError:
        pass
    for fmt in ("%Y-%m-%dT%H-%MZ", "%Y-%m-%dT%H:%MZ"):
        try:
            return datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return None

ts = None
if state_path.is_file():
    try:
        data = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        data = {}
    for key in ("generated_at", "snapshot_id"):
        value = data.get(key)
        if value is None:
            continue
        ts = parse_ts(str(value))
        if ts is not None:
            break
    if ts is None:
        ts = datetime.fromtimestamp(state_path.stat().st_mtime, tz=timezone.utc)
else:
    ts = datetime.fromtimestamp(dashboard_path.stat().st_mtime, tz=timezone.utc)

age_seconds = max((datetime.now(timezone.utc) - ts.astimezone(timezone.utc)).total_seconds(), 0)
print(int(age_seconds // 3600))
PY
}

placeholder_present() {
  local metric_id="$1"
  grep -q "data-id=${metric_id}" "$DASHBOARD_HTML" \
    || grep -q "data-id=\"${metric_id}\"" "$DASHBOARD_HTML" \
    || grep -q "data-id='${metric_id}'" "$DASHBOARD_HTML"
}

replace_metric() {
  local metric_id="$1"
  local value="$2"
  local class_form
  local id_form
  local class_forms=(
    "class=metric"
    "class=\"metric\""
    "class='metric'"
  )
  local id_forms=(
    "data-id=${metric_id}"
    "data-id=\"${metric_id}\""
    "data-id='${metric_id}'"
  )

  for class_form in "${class_forms[@]}"; do
    for id_form in "${id_forms[@]}"; do
      sed -i '' -E \
        "s#(<span[[:space:]]+${class_form}[[:space:]]+${id_form}>)[[:space:]]*[0-9]+([[:space:]]*</span>)#\\1${value}\\2#g" \
        "$DASHBOARD_HTML"
    done
  done
}

apply_metric() {
  local value="$1"
  shift
  local metric_id
  for metric_id in "$@"; do
    if placeholder_present "$metric_id"; then
      MATCHED=1
    fi
    replace_metric "$metric_id" "$value"
  done
}

if ! grep -q "class=metric" "$DASHBOARD_HTML" \
  && ! grep -q "class=\"metric\"" "$DASHBOARD_HTML" \
  && ! grep -q "class='metric'" "$DASHBOARD_HTML"; then
  echo "No metric placeholders found in $DASHBOARD_HTML" >&2
  exit 1
fi

AGENT_COUNT="$(count_agents)"
MCP_COUNT="$(count_mcps)"
PLUGIN_COUNT="$(count_plugins)"
SNAPSHOT_AGE_HOURS="$(snapshot_age_hours)"
SNAPSHOT_AGE_DAYS="$((SNAPSHOT_AGE_HOURS / 24))"
MATCHED=0

apply_metric "$AGENT_COUNT" \
  agents agent-count agent_count

apply_metric "$MCP_COUNT" \
  mcps mcp mcp-count mcp_count mcp-servers mcp_servers

apply_metric "$PLUGIN_COUNT" \
  plugins plugin-count plugin_count

apply_metric "$SNAPSHOT_AGE_DAYS" \
  snapshot-age snapshot_age snapshot-days snapshot_days \
  snapshot-age-days snapshot_age_days

apply_metric "$SNAPSHOT_AGE_HOURS" \
  snapshot-hours snapshot_hours snapshot-age-hours snapshot_age_hours

if [ "$MATCHED" -ne 1 ]; then
  echo "No supported metric ids matched in $DASHBOARD_HTML" >&2
  exit 1
fi

echo "Refreshed $DASHBOARD_HTML"
echo "  agents: $AGENT_COUNT"
echo "  mcps: $MCP_COUNT"
echo "  plugins: $PLUGIN_COUNT"
echo "  snapshot_age_days: $SNAPSHOT_AGE_DAYS"
echo "  snapshot_age_hours: $SNAPSHOT_AGE_HOURS"
