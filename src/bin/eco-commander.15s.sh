#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq filters legitimately use single quotes with --arg \$vars
# <xbar.title>Eco Commander</xbar.title>
# <xbar.version>v2.0</xbar.version>
# <xbar.author>Abdulrahman Al-Sayyari</xbar.author>
# <xbar.author.github>abdulrahman-gaith-beep</xbar.author.github>
# <xbar.author.email>245627891+abdulrahman-gaith-beep@users.noreply.github.com</xbar.author.email>
# <xbar.desc>Unified AI ecosystem panel: quotas, system health, actions — one icon</xbar.desc>
# <xbar.dependencies>jq,python3</xbar.dependencies>
#
# Single compact icon in the menu bar. Click to reveal everything.
# Merges the old eco-commander.30s.sh + usage-monitor.15s.sh into one plugin.
#
# CLI fallback:
#   eco-commander.15s.sh --cli

set -u

# Resolve symlinks so an installed (symlinked) widget still finds its repo root.
_eco_src="${BASH_SOURCE[0]}"
while [ -L "$_eco_src" ]; do
  _eco_dir="$(cd "$(dirname "$_eco_src")" && pwd)"
  _eco_src="$(readlink "$_eco_src")"
  case "$_eco_src" in /*) ;; *) _eco_src="$_eco_dir/$_eco_src" ;; esac
done
SCRIPT_DIR="$(cd "$(dirname "$_eco_src")" && pwd)"
for path_dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" /opt/homebrew/sbin; do
  case ":$PATH:" in
    *":$path_dir:"*) ;;
    *) PATH="$path_dir:$PATH" ;;
  esac
done
export PATH

ECO="${ECO_HOME:-$HOME/.eco}"
WIDGET_CONFIG="${ECO_WIDGET_CONFIG:-$ECO/config/widget.env}"

config_value() {
  local key="$1"
  local file="${2:-}"
  [ -n "$file" ] && [ -f "$file" ] || return 0
  awk -v key="$key" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*($|#)/ { next }
    {
      line = $0
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)
      eq = index(line, "=")
      if (!eq) next
      name = trim(substr(line, 1, eq - 1))
      if (name != key) next
      value = trim(substr(line, eq + 1))
      if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
          (substr(value, 1, 1) == "'"'"'" && substr(value, length(value), 1) == "'"'"'")) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$file"
}

env_or_config() {
  local key="$1"
  local value="${!key:-}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    config_value "$key" "$WIDGET_CONFIG"
  fi
}

STATE="$ECO/current/state.json"
DASHBOARD="$ECO/current/dashboard.html"
MAP="$ECO/current/map.md"
PROFILES_DIR="$HOME/.ai-ecosystem/profiles"
CURRENT_PROFILE_FILE="$HOME/.ai-ecosystem/.current-profile"
SWITCH_PROFILE="$HOME/.ai-ecosystem/switch-profile.sh"
ALERT_ACTION="$ECO/bin/eco-alerts.sh"
[ -x "$ALERT_ACTION" ] || ALERT_ACTION="$SCRIPT_DIR/eco-alerts.sh"
RECIPES_DIR="$ECO/recipes"
AUDIT_ROOT="$(env_or_config ECO_AUDIT_ROOT)"
EROR_SPEC="$(env_or_config ECO_EROR_SPEC)"
DOMAIN_CHARTERS="$(env_or_config ECO_DOMAIN_CHARTERS)"
if [ -n "$AUDIT_ROOT" ]; then
  [ -n "$EROR_SPEC" ] || EROR_SPEC="$AUDIT_ROOT/specs/EROR-v1-DRAFT.md"
  [ -n "$DOMAIN_CHARTERS" ] || DOMAIN_CHARTERS="$AUDIT_ROOT/specs/DOMAIN-CHARTERS.md"
fi
REPO_ROOT="${ECO_COMMANDER_REPO:-}"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  for repo_candidate in \
    "$HOME/projects/eco-commander" \
    "$HOME/Projects/eco-commander" \
    "$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"; do
    if [ -d "$repo_candidate/docs" ] && [ -f "$repo_candidate/README.md" ]; then
      REPO_ROOT="$repo_candidate"
      break
    fi
  done
fi
[ -n "$REPO_ROOT" ] || REPO_ROOT="$HOME/projects/eco-commander"
DOCS_DIR="$REPO_ROOT/docs"
README_DOC="$REPO_ROOT/README.md"
DOCS_INDEX="$DOCS_DIR/INDEX.md"
DOCS_READING_ORDER="$DOCS_DIR/READING_ORDER.md"
CLI_REFERENCE_DOC="$DOCS_DIR/api/cli-reference.md"
CONFIGURATION_DOC="$DOCS_DIR/reference/configuration.md"
RECIPES_DOC="$DOCS_DIR/subsystems/recipes.md"
WIDGET_HEALTH_DOC="$DOCS_DIR/subsystems/widget-health.md"
CHANGELOG_DOC="$REPO_ROOT/CHANGELOG.md"
SNAPSHOT_SCRIPT="$REPO_ROOT/scripts/usage-snapshot.sh"

CLI_MODE=0
[ "${1:-}" = "--cli" ] && CLI_MODE=1

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: Gather all data (token quotas + system probes)
# ═══════════════════════════════════════════════════════════════════

# ── Token quota data (from usage.json) ──
USAGE_JSON="$ECO/current/usage.json"
LOCAL_CONFIG_JSON="$ECO/config.json"
LOCAL_ACCOUNTS_JSON="$ECO/accounts.json"
ACTIVE_ACCOUNTS_JSON="$ECO/state/active-accounts.json"
STALE_AFTER_SECS=180
WARN_PCT=80
CRIT_PCT=95

have_jq() { command -v jq >/dev/null 2>&1; }

json_config_value() {
  local service="$1"
  local filter="$2"
  local file
  for file in "$LOCAL_CONFIG_JSON" "$LOCAL_ACCOUNTS_JSON"; do
    [ -f "$file" ] || continue
    jq -er --arg service "$service" "$filter" "$file" 2>/dev/null && return 0
  done
  return 1
}

service_plan_label() {
  local service="$1"
  local value
  value=$(json_config_value "$service" '(.[$service].plan? // .plans?[$service] // .[($service + "_plan")]?) | select(type == "string" and length > 0)') ||
    value="Unknown"
  printf '%s' "$value"
}

service_account_count() {
  local service="$1"
  local value
  local account_filter='
    def account_count:
      if type == "number" then .
      elif type == "string" then tonumber? // empty
      elif type == "array" then length
      elif type == "object" then length
      else empty end;
    (.[$service].accounts? // .account_counts?[$service] // .accounts?[$service] // .[($service + "_accounts")]?)
    | account_count
    | floor
    | select(. >= 0)
  '
  value=$(json_config_value "$service" "$account_filter") ||
    value="1"
  printf '%s' "$value"
}

# Humanize tokens: 0..999 → "N", 1k → "1.2K", 1M → "3.4M"
humanize() {
  awk -v n="$1" 'BEGIN{
    if (n+0 == 0) { print "0"; exit }
    abs = (n < 0) ? -n : n;
    units[0]=""; units[1]="K"; units[2]="M"; units[3]="B"; units[4]="T"; units[5]="P";
    i = 0;
    while (abs >= 1000 && i < 5) { abs /= 1000.0; i++ }
    if (i == 0) { printf "%d", abs }
    else if (abs >= 100) { printf "%.0f%s", abs, units[i] }
    else if (abs >= 10)  { printf "%.1f%s", abs, units[i] }
    else                 { printf "%.2f%s", abs, units[i] }
  }'
}

color_for() {
  awk -v p="$1" -v w="$WARN_PCT" -v c="$CRIT_PCT" 'BEGIN{
    if (p+0 >= c) print "red";
    else if (p+0 >= w) print "orange";
    else print "green";
  }'
}

glyph_for_pct() {
  awk -v p="$1" -v w="$WARN_PCT" -v c="$CRIT_PCT" 'BEGIN{
    if (p+0 >= c) printf "🚨 ";
    else if (p+0 >= w) printf "⚠ ";
    else printf "";
  }'
}

bar() {
  awk -v p="$1" 'BEGIN{
    w=12; pp=p+0; if(pp>100)pp=100; if(pp<0)pp=0;
    f=int((pp/100)*w + 0.5); if(f>w)f=w;
    s=""; for(i=0;i<f;i++)s=s"█"; for(i=f;i<w;i++)s=s"░";
    print s;
  }'
}

fmt_pct() { awk -v p="$1" 'BEGIN{ printf (p>=10 ? "%d" : "%.0f"), p+0 }'; }

format_time_for_ts() {
  local ts_value="$1"
  if [ "$(date -u -r 0 '+%s' 2>/dev/null || true)" = "0" ]; then
    date -r "$ts_value" '+%H:%M:%S' 2>/dev/null && return 0
  fi
  date -d "@$ts_value" '+%H:%M:%S' 2>/dev/null ||
    printf '%s' "$ts_value"
}

# Format MB → "N.N GB"
fmt_gb() {
  local mb="${1:-0}"
  local int="$(( mb / 1024 ))"
  local dec="$(( (mb % 1024) * 10 / 1024 ))"
  printf '%d.%d' "$int" "$dec"
}

# ── Usage data ──
usage_ok=0
usage_stale=0
usage_age=0

c_ok="false"; c_sess=0; c_week=0
x_ok="false"; x_sess=0; x_week=0
g_ok="false"; g_max=0
worst_quota=0

if have_jq && [ -f "$USAGE_JSON" ]; then
  if jq -e 'type=="object" and (.ts|type=="number")' "$USAGE_JSON" >/dev/null 2>&1; then
    ts=$(jq -r '.ts | floor' "$USAGE_JSON")
    if [[ "$ts" =~ ^[0-9]{1,10}$ ]]; then
      usage_ok=1
      now_ts=$(date +%s)
      usage_age=$(( now_ts - ts ))
      [ "$usage_age" -gt "$STALE_AFTER_SECS" ] && usage_stale=1

      c_ok=$(jq -r '.claude.ok // false' "$USAGE_JSON")
      c_sess=$(jq -r '.claude.session.pct // 0' "$USAGE_JSON")
      c_week=$(jq -r '.claude.weekly.pct // 0' "$USAGE_JSON")

      x_ok=$(jq -r '.codex.ok // false' "$USAGE_JSON")
      x_sess=$(jq -r '.codex.session.pct // 0' "$USAGE_JSON")
      x_week=$(jq -r '.codex.weekly.pct // 0' "$USAGE_JSON")

      g_ok=$(jq -r '.gemini.ok // false' "$USAGE_JSON")
      g_max=$(jq -r '[.gemini.tiers.flash.pct, .gemini.tiers.flash_lite.pct, .gemini.tiers.pro.pct] | max // 0' "$USAGE_JSON" 2>/dev/null || echo 0)

      worst_quota=$(awk -v a="$c_sess" -v b="$c_week" -v c="$x_sess" -v d="$x_week" -v e="$g_max" 'BEGIN{
        m=a; if(b>m)m=b; if(c>m)m=c; if(d>m)m=d; if(e>m)m=e; print m+0;
      }')
    fi
  fi
fi

# ── System probes ──
current_profile="—"
[ -f "$CURRENT_PROFILE_FILE" ] && current_profile="$(tr -d '\n' < "$CURRENT_PROFILE_FILE" 2>/dev/null)"
[ -z "$current_profile" ] && current_profile="—"

ollama_loaded_csv=""
ollama_list_output=""
ollama_loaded_count=0
ollama_installed_count=0
ollama_running=0
OLLAMA_BIN="$(command -v ollama 2>/dev/null || true)"
CURL_BIN="$(command -v curl 2>/dev/null || true)"
if [ -n "$OLLAMA_BIN" ] && [ -n "$CURL_BIN" ] && "$CURL_BIN" -s -m 1 http://127.0.0.1:11434/ >/dev/null 2>&1; then
  ollama_running=1
  ollama_loaded_csv="$("$OLLAMA_BIN" ps 2>/dev/null | tail -n +2 | awk 'NF>0{print $1}' | tr '\n' ',' | sed 's/,$//')"
  if [ -n "$ollama_loaded_csv" ]; then
    ollama_loaded_count=$(echo "$ollama_loaded_csv" | tr ',' '\n' | grep -c .)
  fi
  ollama_list_output="$("$OLLAMA_BIN" list 2>/dev/null | tail -n +2 || true)"
  if [ -n "$ollama_list_output" ]; then
    ollama_installed_count="$(printf '%s\n' "$ollama_list_output" | awk 'NF>0{count++} END{print count+0}')"
  fi
fi

openclaw_status="offline"; openclaw_color="red"
if [ -n "$CURL_BIN" ] && "$CURL_BIN" -s -m 1 http://127.0.0.1:18789/status >/dev/null 2>&1; then
  openclaw_status="online"; openclaw_color="green"
fi

cortex_status="offline"; cortex_color="red"
if [ -n "$CURL_BIN" ] && "$CURL_BIN" -s -m 1 http://127.0.0.1:3000/ >/dev/null 2>&1; then
  cortex_status="online"; cortex_color="green"
fi

n8n_status="offline"; n8n_color="red"
if [ -n "$CURL_BIN" ] && "$CURL_BIN" -s -m 1 http://127.0.0.1:5678/ >/dev/null 2>&1; then
  n8n_status="online"; n8n_color="green"
fi

# RAM
avail_mb=0; free_mb=0
if command -v vm_stat >/dev/null 2>&1; then
  vm=$(vm_stat 2>/dev/null)
  page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
  pages_free=$(echo "$vm" | awk '/Pages free:/ {gsub(/\./, "", $3); print $3; exit}')
  pages_inactive=$(echo "$vm" | awk '/Pages inactive:/ {gsub(/\./, "", $3); print $3; exit}')
  pages_purgeable=$(echo "$vm" | awk '/Pages purgeable:/ {gsub(/\./, "", $3); print $3; exit}')
  pages_speculative=$(echo "$vm" | awk '/Pages speculative:/ {gsub(/\./, "", $3); print $3; exit}')
  [ -n "${pages_free:-}" ] && free_mb=$(( pages_free * page_size / 1048576 ))
  avail_pages=$(( ${pages_free:-0} + ${pages_inactive:-0} + ${pages_purgeable:-0} + ${pages_speculative:-0} ))
  avail_mb=$(( avail_pages * page_size / 1048576 ))
fi
ram_color="green"
[ "$avail_mb" -lt 4096 ] && ram_color="orange"
[ "$avail_mb" -lt 1024 ] && ram_color="red"
avail_gb="$(fmt_gb "$avail_mb")"
free_gb="$(fmt_gb "$free_mb")"

# Snapshot freshness
snapshot_age_sec=-1
snapshot_age_label="unknown"
snapshot_state="missing"
snapshot_color="gray"
if [ -f "$STATE" ]; then
  snapshot_state="fresh"
  state_mtime="$(stat -f %m "$STATE" 2>/dev/null || stat -c %Y "$STATE" 2>/dev/null || echo 0)"
  now_ts="$(date +%s 2>/dev/null || echo 0)"
  if [ "${state_mtime:-0}" -gt 0 ] && [ "${now_ts:-0}" -gt 0 ]; then
    snapshot_age_sec=$(( now_ts - state_mtime ))
    if [ "$snapshot_age_sec" -lt 3600 ]; then
      snapshot_age_label="$(( snapshot_age_sec / 60 ))m"
    elif [ "$snapshot_age_sec" -lt 172800 ]; then
      snapshot_age_label="$(( snapshot_age_sec / 3600 ))h"
    else
      snapshot_age_label="$(( snapshot_age_sec / 86400 ))d"
    fi
    [ "$snapshot_age_sec" -ge 86400 ] && snapshot_state="stale" && snapshot_color="orange"
    [ "$snapshot_age_sec" -ge 259200 ] && snapshot_state="very stale" && snapshot_color="red"
  fi
else
  snapshot_color="red"
fi

# ── Alerts (normalized by eco-alerts.sh) ──
alert_count=0
actionable_alert_count=0
gen_at="unknown"
snap_id="unknown"
issue_severities=()
issue_ids=()
issue_descs=()
issue_statuses=()
issue_details=()
issue_action_keys=()
issue_action_labels=()
issue_colors=()
issue_icons=()
issue_categories=()
issue_priorities=()
issue_action_ids=()
parsed_issue_count=0
verified_active_count=0
evidence_count=0
triage_count=0
resolved_count=0
if [ -f "$STATE" ] && have_jq; then
  alerts_out=""
  if [ -x "$ALERT_ACTION" ]; then
    alerts_out="$(ECO_N8N_STATUS="$n8n_status" "$ALERT_ACTION" widget-issues 2>/dev/null || true)"
  fi
  if [[ "$alerts_out" != META$'\t'* ]]; then
    alerts_out="$(jq -r --arg n8n_status "$n8n_status" '
      def eco_issues:
        ((.layers // {}) | [to_entries[] | select(.key != "Linf_wiring") | .value.issues[]?]) as $layer_issues |
        if ($layer_issues | length) > 0 then $layer_issues else (.layers.Linf_wiring.issues // []) end;
      (eco_issues) as $issues |
      "META\t\($issues | length)\t0\t0\t\($issues | length)\t0\t\(.generated_at // "unknown")\t\(.snapshot_id // "unknown")",
      ($issues[]? |
        (.severity // "unknown" | tostring | ascii_upcase | gsub("[\t\r\n]+"; " ")) as $severity |
        (.id // "unknown" | tostring | split("|")[0] | gsub("[^A-Za-z0-9_.:-]+"; "_") | gsub("_+"; "_") | gsub("^_|_$"; "") | if . == "" then "unknown" else . end) as $id |
        (.desc // .description // "no description" | tostring | gsub("[\t\r\n]+"; " ")) as $desc |
        ($desc | ascii_downcase) as $lower |
        (if ($lower | contains("n8n")) then
          if $n8n_status == "offline" then
            ["active", "verified live: n8n is unreachable", "fix-n8n", "Start n8n", "orange", "⚠", "service", "P1"]
          else
            ["resolved", "live check now passes: n8n responds", "", "", "gray", "✓", "service", "P3"]
          end
        elif (($lower | contains("rc=124")) or ($lower | contains("timed out")) or ($lower | contains("timeout")) or ($lower | contains("quota"))) then
          ["evidence", "evidence-backed snapshot failure; rerun to clear", "fix-snapshot-timeout", "Rerun snapshot", "orange", "◆", "data-freshness", "P2"]
        else
          ["triage", "snapshot finding has no live verifier yet", "delegate-fix", "Plan with Gemini Pro", "gray", "◇", "repo-ops", "P3"]
        end) as $a |
        "ISSUE\t\($severity)\t\($id)\t\($desc)\t\($a[0])\t\($a[1])\t\($a[2])\t\($a[3])\t\($a[4])\t\($a[5])\t\($a[6])\t\($a[7])\t\($id)")
    ' "$STATE" 2>/dev/null || printf 'META\t0\t0\t0\t0\t0\tunknown\tunknown\n')"
  fi

  while IFS=$'\t' read -r kind f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12; do
    if [ "$kind" = "ISSUE" ]; then
      issue_severities+=("$f1")
      issue_ids+=("$f2")
      issue_descs+=("$f3")
      issue_statuses+=("$f4")
      issue_details+=("$f5")
      issue_action_keys+=("$f6")
      issue_action_labels+=("$f7")
      issue_colors+=("$f8")
      issue_icons+=("$f9")
      issue_categories+=("$f10")
      issue_priorities+=("$f11")
      issue_action_ids+=("$f12")
      parsed_issue_count=$(( parsed_issue_count + 1 ))
    elif [ "$kind" = "META" ]; then
      alert_count="$f1"
      verified_active_count="$f2"
      evidence_count="$f3"
      triage_count="$f4"
      resolved_count="$f5"
      gen_at="$f6"
      snap_id="$f7"
    fi
  done <<< "$alerts_out"
fi
alert_count="$parsed_issue_count"
verified_active_count=0
evidence_count=0
triage_count=0
resolved_count=0
for ((i = 0; i < parsed_issue_count; i++)); do
  status="${issue_statuses[$i]:-triage}"
  case "$status" in
    active) verified_active_count=$(( verified_active_count + 1 )) ;;
    evidence) evidence_count=$(( evidence_count + 1 )) ;;
    resolved) resolved_count=$(( resolved_count + 1 )) ;;
    *) triage_count=$(( triage_count + 1 )) ;;
  esac
done
actionable_alert_count=$(( verified_active_count + evidence_count + triage_count ))


# ═══════════════════════════════════════════════════════════════════
# SECTION 2: Determine single icon for menu bar
# ═══════════════════════════════════════════════════════════════════

# Icon reflects the WORST status across all systems:
#   🔴 = any quota ≥ 95%, RAM < 1GB, snapshot very stale, or poller stale
#   🟡 = any quota 80-94%, RAM < 4GB, or snapshot stale
#   🟢 = everything healthy
status_icon="🟢"
status_level=0  # 0=green, 1=yellow, 2=red

bump_level() {
  local new="$1"
  [ "$new" -gt "$status_level" ] && status_level="$new"
}

# Quota-based
[ "$(awk -v w="$worst_quota" 'BEGIN{print (w>=95)}')" = "1" ] && bump_level 2
[ "$(awk -v w="$worst_quota" 'BEGIN{print (w>=80 && w<95)}')" = "1" ] && bump_level 1

# RAM-based
[ "$ram_color" = "red" ] && bump_level 2
[ "$ram_color" = "orange" ] && bump_level 1

# Snapshot freshness
[ "$snapshot_color" = "red" ] && bump_level 2
[ "$snapshot_color" = "orange" ] && bump_level 1

# Poller staleness
[ "$usage_stale" = "1" ] && bump_level 2

# Alerts
[ "$verified_active_count" -gt 0 ] && bump_level 1

case "$status_level" in
  2) status_icon="🔴" ;;
  1) status_icon="🟡" ;;
  *) status_icon="🟢" ;;
esac


# ═══════════════════════════════════════════════════════════════════
# SECTION 3: Render output
# ═══════════════════════════════════════════════════════════════════

swiftbar_escape_label() {
  printf '%s' "${1:-}" | tr '\r\n\t' '   ' | sed 's/|/\\|/g; s/[[:cntrl:]]//g'
}

is_safe_action_arg() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]] && [[ "$value" != *..* ]]
}

is_safe_ollama_model() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z0-9._:/-]+$ ]] && [[ "$value" != *..* ]]
}

section() {
  if [ "$CLI_MODE" -eq 1 ]; then
    echo
    echo "── $1 ──"
  else
    echo "$(swiftbar_escape_label "$1") | size=12 color=white"
  fi
}

menu() {
  local label="$1"; shift
  if [ "$CLI_MODE" -eq 1 ]; then
    local prefix=""
    while [[ "$label" == -* ]]; do
      prefix="$prefix  "
      label="${label#-}"
    done
    label="${label# }"
    echo "  $prefix$label"
  else
    label="$(swiftbar_escape_label "$label")"
    if [ "$#" -gt 0 ]; then
      echo "$label | $*"
    else
      echo "$label"
    fi
  fi
}

divider() { [ "$CLI_MODE" -eq 0 ] && echo "---"; }

open_file_menu() {
  local label="$1"
  local target="$2"
  [ -f "$target" ] || return 0
  menu "$label" "bash=/usr/bin/open param1=${target} terminal=false"
}

open_dir_menu() {
  local label="$1"
  local target="$2"
  [ -d "$target" ] || return 0
  menu "$label" "bash=/usr/bin/open param1=${target} terminal=false"
}


# ── Title ──
if [ "$CLI_MODE" -eq 0 ]; then
  # COMPACT: single icon only in the menu bar
  echo "$status_icon"
  echo "---"
else
  echo "=== Eco Commander (CLI) ==="
  echo "Status: $status_icon  |  Profile: $current_profile"
  echo "Quota worst: $(fmt_pct "$worst_quota")%  |  RAM: ${avail_gb}GB avail  |  Snapshot: ${snapshot_age_label} (${snapshot_state})"
  echo "Runtime: OpenClaw=${openclaw_status} | Cortex=${cortex_status} | n8n=${n8n_status}"
  echo
fi


# ── Token Quotas ──
section "📊 Token Quotas"
if [ "$usage_ok" -eq 1 ]; then
  stale_marker=""
  [ "$usage_stale" = "1" ] && stale_marker="  ⚠ STALE"
  menu "-- Updated $(format_time_for_ts "$ts") (${usage_age}s ago)$stale_marker" "size=11 color=gray"
  [ "$usage_stale" = "1" ] && menu "-- ⚠ Poller stale (>${STALE_AFTER_SECS}s). Check launchctl." "color=orange size=11"

  # Plan labels
  c_plan=$(service_plan_label claude)
  c_acc=$(service_account_count claude)
  g_plan=$(service_plan_label gemini)
  g_acc=$(service_account_count gemini)
  x_plan=$(service_plan_label codex)
  x_acc=$(service_account_count codex)
  x_active_slug="unknown"
  if [ -f "$ACTIVE_ACCOUNTS_JSON" ]; then
    x_active_slug=$(jq -r '.codex // "unknown"' "$ACTIVE_ACCOUNTS_JSON" 2>/dev/null || echo "unknown")
  fi

  # ── Claude ──
  c_acct_label="$c_plan"; [ "$c_acc" -gt 1 ] && c_acct_label="$c_plan ×$c_acc"
  c_stale_widget=$(jq -r '.claude.stale // false' "$USAGE_JSON")
  c_stale_suffix=""; [ "$c_stale_widget" = "true" ] && c_stale_suffix="  ⚠ cached"
  divider
  menu "Claude · $c_acct_label$c_stale_suffix" "size=13"
  if [ "$c_ok" = "true" ]; then
    c_src=$(jq -r '.claude.source // "jsonl"' "$USAGE_JSON")
    c_has_token_detail=$(jq -r 'if (.claude.weekly.input_tokens? // null) == null then "false" else "true" end' "$USAGE_JSON")
    c_sess_in=$(jq -r '.claude.session.resets_in // "—"' "$USAGE_JSON")
    c_week_in=$(jq -r '.claude.weekly.resets_in // "—"' "$USAGE_JSON")
    c_w_all=$(jq -r '.claude.weekly.pct_all // 0' "$USAGE_JSON")
    c_w_sonnet=$(jq -r '.claude.weekly.pct_sonnet // 0' "$USAGE_JSON")

    menu "-- Session  $(bar "$c_sess")  $(glyph_for_pct "$c_sess")$(fmt_pct "$c_sess")%  resets $c_sess_in" "font=Menlo size=12 color=$(color_for "$c_sess")"
    if [ "$c_src" != "api" ] || [ "$c_has_token_detail" = "true" ]; then
      c_s_total=$(jq -r '.claude.session.tokens // 0' "$USAGE_JSON")
      c_s_in=$(jq -r '.claude.session.input_tokens // 0' "$USAGE_JSON")
      c_s_out=$(jq -r '.claude.session.output_tokens // 0' "$USAGE_JSON")
      c_s_cc=$(jq -r '.claude.session.cache_creation_tokens // 0' "$USAGE_JSON")
      c_s_cr=$(jq -r '.claude.session.cache_read_tokens // 0' "$USAGE_JSON")
      menu "---- in $(humanize "$c_s_in") · out $(humanize "$c_s_out") · cache+ $(humanize "$c_s_cc") · cache↻ $(humanize "$c_s_cr") · billable: $(humanize "$c_s_total")" "size=10 font=Menlo color=gray"
    fi
    menu "-- Weekly   $(bar "$c_week")  $(glyph_for_pct "$c_week")$(fmt_pct "$c_week")%  resets $c_week_in" "font=Menlo size=12 color=$(color_for "$c_week")"
    menu "---- all $(fmt_pct "$c_w_all")% · sonnet $(fmt_pct "$c_w_sonnet")%" "size=10 font=Menlo color=gray"
    if [ "$c_src" != "api" ] || [ "$c_has_token_detail" = "true" ]; then
      c_w_total=$(jq -r '.claude.weekly.tokens // 0' "$USAGE_JSON")
      c_w_in=$(jq -r '.claude.weekly.input_tokens // 0' "$USAGE_JSON")
      c_w_out=$(jq -r '.claude.weekly.output_tokens // 0' "$USAGE_JSON")
      c_w_cc=$(jq -r '.claude.weekly.cache_creation_tokens // 0' "$USAGE_JSON")
      c_w_cr=$(jq -r '.claude.weekly.cache_read_tokens // 0' "$USAGE_JSON")
      c_w_sess=$(jq -r '.claude.weekly.sessions // 0' "$USAGE_JSON")
      menu "---- in $(humanize "$c_w_in") · out $(humanize "$c_w_out") · cache+ $(humanize "$c_w_cc") · cache↻ $(humanize "$c_w_cr") · billable: $(humanize "$c_w_total") · sessions: $c_w_sess" "size=10 font=Menlo color=gray"
    fi
  else
    err=$(jq -r '.claude.error // "unknown"' "$USAGE_JSON")
    menu "-- ⚠ $err" "color=orange size=11"
  fi

  # ── Gemini ──
  divider
  g_acct_label="$g_plan"; [ "$g_acc" -gt 1 ] && g_acct_label="$g_plan ×$g_acc"
  menu "Gemini · $g_acct_label" "size=13"
  if [ "$g_ok" = "true" ]; then
    for tier in flash flash_lite pro; do
      pct=$(jq -r ".gemini.tiers.$tier.pct // 0" "$USAGE_JSON")
      rin=$(jq -r ".gemini.tiers.$tier.resets_in // \"—\"" "$USAGE_JSON")
      label=$(echo "$tier" | tr '_' ' ')
      menu "-- $(printf '%-10s' "$label")  $(bar "$pct")  $(glyph_for_pct "$pct")$(fmt_pct "$pct")%  $rin" "font=Menlo size=12 color=$(color_for "$pct")"
    done
  else
    err=$(jq -r '.gemini.error // "stub"' "$USAGE_JSON")
    menu "-- ⚙ $err" "color=gray size=11"
  fi

  # ── Codex ──
  divider
  x_acct_label="$x_plan"; [ "$x_acc" -gt 1 ] && x_acct_label="$x_plan ×$x_acc"
  x_stale_widget=$(jq -r '.codex.stale // false' "$USAGE_JSON")
  x_stale_suffix=""; [ "$x_stale_widget" = "true" ] && x_stale_suffix="  ⚠ cached"
  x_org_label="${ECO_ORG_LABEL:-}"
  x_org_segment=""; [ -n "$x_org_label" ] && x_org_segment=" · $x_org_label"
  menu "Codex CLI · $x_acct_label$x_org_segment · active: $x_active_slug$x_stale_suffix" "size=13"
  if [ "$x_ok" = "true" ]; then
    x_src=$(jq -r '.codex.source // "jsonl"' "$USAGE_JSON")
    x_has_token_detail=$(jq -r 'if (.codex.weekly.input_tokens? // null) == null then "false" else "true" end' "$USAGE_JSON")
    x_sess_in=$(jq -r '.codex.session.resets_in // "—"' "$USAGE_JSON")
    x_week_in=$(jq -r '.codex.weekly.resets_in // "—"' "$USAGE_JSON")

    menu "-- Session  $(bar "$x_sess")  $(glyph_for_pct "$x_sess")$(fmt_pct "$x_sess")%  resets $x_sess_in" "font=Menlo size=12 color=$(color_for "$x_sess")"
    if [ "$x_src" != "api" ] || [ "$x_has_token_detail" = "true" ]; then
      x_s_total=$(jq -r '.codex.session.tokens // 0' "$USAGE_JSON")
      x_s_in=$(jq -r '.codex.session.input_tokens // 0' "$USAGE_JSON")
      x_s_out=$(jq -r '.codex.session.output_tokens // 0' "$USAGE_JSON")
      x_s_ci=$(jq -r '.codex.session.cached_input_tokens // 0' "$USAGE_JSON")
      menu "---- in $(humanize "$x_s_in") · out $(humanize "$x_s_out") · cached-in $(humanize "$x_s_ci") · total: $(humanize "$x_s_total")" "size=10 font=Menlo color=gray"
    fi
    menu "-- Weekly   $(bar "$x_week")  $(glyph_for_pct "$x_week")$(fmt_pct "$x_week")%  resets $x_week_in" "font=Menlo size=12 color=$(color_for "$x_week")"
    if [ "$x_src" != "api" ] || [ "$x_has_token_detail" = "true" ]; then
      x_w_total=$(jq -r '.codex.weekly.tokens // 0' "$USAGE_JSON")
      x_w_in=$(jq -r '.codex.weekly.input_tokens // 0' "$USAGE_JSON")
      x_w_out=$(jq -r '.codex.weekly.output_tokens // 0' "$USAGE_JSON")
      x_w_ci=$(jq -r '.codex.weekly.cached_input_tokens // 0' "$USAGE_JSON")
      menu "---- in $(humanize "$x_w_in") · out $(humanize "$x_w_out") · cached-in $(humanize "$x_w_ci") · total: $(humanize "$x_w_total")" "size=10 font=Menlo color=gray"
    fi
  else
    err=$(jq -r '.codex.error // "unknown"' "$USAGE_JSON")
    menu "-- ⚠ $err" "color=orange size=11"
  fi

  # ── Suggestion / pace ──
  suggestion=$(jq -r '
    def reset_min:
      if . == null or . == "—" or . == "" then 99999
      else
        (try (capture("(?<d>[0-9]+)d\\s*(?<h>[0-9]+)h") | {d:.d|tonumber, h:.h|tonumber, m:0})
         catch null) //
        (try (capture("(?<h>[0-9]+)h\\s*(?<m>[0-9]+)m") | {d:0, h:.h|tonumber, m:.m|tonumber})
         catch null) //
        (try (capture("(?<m>[0-9]+)m") | {d:0, h:0, m:.m|tonumber})
         catch null) //
        {d:0, h:0, m:0}
        | .d * 1440 + .h * 60 + .m
      end;
    def fmt_left:
      if . < 60 then "\(.|tostring)m"
      else "\((. / 60 | floor)|tostring)h \(. % 60 | tostring)m"
      end;
    def pick(n; tool; meter):
      (n.resets_in // "" | reset_min) as $rmin
      | (n.pct // 0) as $pct
      | (n.target_pct // 0) as $target
      | ((100 - $pct) | floor) as $left_pct
      | if $pct >= 95 then
          {p: 1, msg: "🚧 \(tool) \(meter) at \($pct|floor)% — switch tools NOW"}
        elif $rmin <= 20 and $left_pct >= 5 then
          {p: 2, msg: "🚨 \(tool) \(meter) — LAST CALL: \($rmin|fmt_left) until reset (\($left_pct)% left)"}
        elif (n.pace_label // "") == "ahead" and $pct >= 80 then
          {p: 3, msg: "🐎 \(tool) \(meter) hot (\($pct|floor)%/\($target|floor)%) — spare it"}
        elif $rmin <= 60 and $left_pct >= 10 then
          {p: 4, msg: "🔥 \(tool) \(meter) SPRINT: \($rmin|fmt_left) left · \($left_pct)% will vanish"}
        elif $rmin <= 180 and $left_pct >= 20 then
          {p: 5, msg: "🐢 \(tool) \(meter) burn fast: \($rmin|fmt_left) to reset · \($left_pct)% unburned"}
        elif $target >= 50 and (n.pace_delta_pp // 0) <= -15 then
          {p: 6, msg: "🐢 \(tool) \(meter) underutilized (\($pct|floor)%/\($target|floor)%) — push tasks here"}
        else null end;
    [
      pick(.claude.session;"Claude";"Session"),
      pick(.claude.weekly;"Claude";"Weekly"),
      pick(.codex.session;"Codex";"Session"),
      pick(.codex.weekly;"Codex";"Weekly"),
      pick(.gemini.tiers.flash;"Gemini";"Flash"),
      pick(.gemini.tiers.flash_lite;"Gemini";"Flash Lite"),
      pick(.gemini.tiers.pro;"Gemini";"Pro")
    ]
    | map(select(. != null))
    | sort_by(.p)
    | (.[0].msg // "")
  ' "$USAGE_JSON" 2>/dev/null)
  if [ -n "$suggestion" ]; then
    divider
    menu "💡 $suggestion" "color=orange size=11"
  fi

  # Burn-rate comment
  comment=$(jq -r '.comment // ""' "$USAGE_JSON" 2>/dev/null)
  [ -n "$comment" ] && menu "🗣  $comment" "color=gray size=11"

  # Alternatives
  if jq -e '.alternatives' "$USAGE_JSON" >/dev/null 2>&1; then
    divider
    menu "Alternatives" "size=13"
    ag_status=$(jq -r '.alternatives.antigravity.status // ""' "$USAGE_JSON")
    cu_status=$(jq -r '.alternatives.cursor.status // ""' "$USAGE_JSON")
    vsc_status=$(jq -r '.alternatives.vs_code.status // ""' "$USAGE_JSON")
    ol_n=$(jq -r '.alternatives.ollama.models // [] | length' "$USAGE_JSON")
    menu "-- Antigravity  ⚙ $ag_status" "size=11 color=gray font=Menlo"
    menu "-- Cursor       ⚙ $cu_status" "size=11 color=gray font=Menlo"
    menu "-- VS Code      ✓ $vsc_status" "size=11 color=gray font=Menlo"
    [ "$ol_n" -gt 0 ] && menu "-- Ollama       ✓ $ol_n local models" "size=11 color=gray font=Menlo"
  fi
else
  if ! have_jq; then
    menu "-- jq required. Install: brew install jq" "color=red size=11"
  elif [ ! -f "$USAGE_JSON" ]; then
    menu "-- Poller has not produced data yet" "color=gray size=11"
    menu "-- Run: make install from the eco-commander repo" "color=gray size=10"
  else
    menu "-- usage.json is corrupt" "color=red size=11"
  fi
fi


# ── System Status ──
divider
section "📡 System"
menu "-- Profile: ${current_profile}" "color=gray size=11"
menu "-- RAM: ${avail_gb} GB avail (free: ${free_gb} GB)" "color=${ram_color} size=11"
menu "-- Ollama: ${ollama_loaded_count}/${ollama_installed_count} loaded${ollama_loaded_csv:+ · $ollama_loaded_csv}" "color=gray size=11"
menu "-- OpenClaw: ${openclaw_status}" "color=${openclaw_color} size=11"
menu "-- Cortex: ${cortex_status}" "color=${cortex_color} size=11"
menu "-- n8n: ${n8n_status}" "color=${n8n_color} size=11"
menu "-- Snapshot: ${snapshot_age_label} (${snapshot_state})" "color=${snapshot_color} size=11"
menu "-- Snap ID: ${snap_id}" "color=gray size=10"


# ── Ollama Models ──
if [ "$ollama_running" -eq 1 ] && [ -n "$ollama_list_output" ]; then
  divider
  section "🦙 Local LLMs"
  : "${PREWARM_GB_LIMIT:=10}"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    read -r model _ size_num size_unit _ <<< "$line"
    size="$size_num $size_unit"
    case ",$ollama_loaded_csv," in
      *",${model},"*)
        menu "-- 🟢 $model ($size) — loaded" "color=green size=11"
        if is_safe_ollama_model "$model"; then
          menu "---- Unload $model" "bash=${OLLAMA_BIN} param1=stop param2=${model} terminal=false refresh=true"
        else
          menu "---- Unload action unavailable: unsafe model name" "color=gray size=10"
        fi
        ;;
    esac
  done <<< "$ollama_list_output"

  menu "-- ⭕ Unloaded Models" "size=11"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    read -r model _ size_num size_unit _ <<< "$line"
    size="$size_num $size_unit"
    case ",$ollama_loaded_csv," in
      *",${model},"*) continue ;;
    esac
    size_int="${size_num%%.*}"
    is_heavy=0
    if [ "$size_unit" = "GB" ] && [ "${size_int:-0}" -ge "$PREWARM_GB_LIMIT" ]; then
      is_heavy=1
    fi
    case "$model" in
      bge-m3*|nomic-embed*)
        menu "---- ⚪ $model ($size) — auto-loads" "color=gray size=10" ;;
      *)
        if [ "$is_heavy" -eq 1 ]; then
          menu "---- 🛑 $model ($size) — heavy" "color=gray size=10"
        else
          menu "---- ⭕ $model ($size)" "color=gray size=10"
          if is_safe_ollama_model "$model"; then
            menu "------ Pre-warm $model" "bash=${ALERT_ACTION} param1=prewarm-ollama param2=${model} terminal=false refresh=true"
          else
            menu "------ Pre-warm unavailable: unsafe model name" "color=gray size=10"
          fi
        fi ;;
    esac
  done <<< "$ollama_list_output"
elif [ -n "$OLLAMA_BIN" ]; then
  divider
  section "🦙 Local LLMs"
  menu "-- (ollama daemon unreachable)" "color=red size=11"
else
  divider
  section "🦙 Local LLMs"
  menu "-- (ollama not installed)" "color=gray size=11"
fi


# ── MCP Profile Switcher ──
divider
section "🔌 MCP Profile"
if [ -d "$PROFILES_DIR" ]; then
  for profile_file in "$PROFILES_DIR"/*.mcpServers.json; do
    [ -f "$profile_file" ] || continue
    name=$(basename "$profile_file" .mcpServers.json)
    if [ "$name" = "$current_profile" ]; then
      menu "-- ✓ $name (current)" "color=green"
    elif is_safe_action_arg "$name"; then
      menu "-- → $name" "bash=${SWITCH_PROFILE} param1=${name} terminal=true refresh=true"
    else
      menu "-- → $name (manual switch only)" "color=gray"
    fi
  done
fi
menu "-- ⓘ Restart clients after switching" "color=gray size=10"


# ── Recipes / Do Task ──
divider
section "🧰 Recipes"
if [ -d "$RECIPES_DIR" ]; then
  for recipe in "$RECIPES_DIR"/*.sh; do
    [ -f "$recipe" ] || continue
    recipe_name="$(basename "$recipe" .sh)"
    [ "$recipe_name" = "_lib" ] && continue
    recipe_desc="$(grep -m1 '^# DESC:' "$recipe" 2>/dev/null | sed 's/^# DESC: *//')"
    [ -z "${recipe_desc:-}" ] && recipe_desc="run recipe"
    case "$recipe_name" in
      dashboard)
        if is_safe_action_arg "$recipe_name"; then
          menu "-- ${recipe_name} — ${recipe_desc}" "bash=${ALERT_ACTION} param1=run-recipe param2=${recipe_name} terminal=false refresh=true"
        else
          menu "-- ${recipe_name} — ${recipe_desc} (manual run only)" "color=gray"
        fi ;;
      snapshot)
        menu "-- ${recipe_name} — run snapshot" "bash=${ALERT_ACTION} param1=run-logged param2=fix-snapshot-timeout terminal=false refresh=true" ;;
      *)
        if is_safe_action_arg "$recipe_name"; then
          menu "-- ${recipe_name} — ${recipe_desc}" "bash=${ALERT_ACTION} param1=run-recipe param2=${recipe_name} terminal=true refresh=true"
        else
          menu "-- ${recipe_name} — ${recipe_desc} (manual run only)" "color=gray"
        fi ;;
    esac
  done
else
  menu "-- recipes directory missing" "color=red size=11"
fi


# ── Quick Actions ──
divider
section "⚡ Quick Actions"
menu "-- 📸 Run snapshot now" "bash=${ALERT_ACTION} param1=run-logged param2=fix-snapshot-timeout terminal=false refresh=true"
menu "-- 📊 Refresh dashboard metrics" "bash=${ALERT_ACTION} param1=run-logged param2=fix-dashboard-refresh terminal=false refresh=true"
menu "-- 🔁 Refresh usage now" "bash=${REPO_ROOT}/scripts/run-poller.sh terminal=false refresh=true"
menu "-- 🔁 Rebuild memory indexes" "bash=${ALERT_ACTION} param1=run-logged param2=rebuild-memory-indexes terminal=false refresh=true"
menu "-- 🩺 Alert doctor" "bash=${ALERT_ACTION} param1=run-logged param2=doctor terminal=false refresh=true"
menu "-- 🩺 Repo health check" "bash=${ALERT_ACTION} param1=run-logged param2=repo-health terminal=false refresh=true"
[ -d "$ECO/alert-runs" ] && menu "-- 🧾 Open alert run logs" "bash=${ALERT_ACTION} param1=open-run-logs terminal=false"
open_file_menu "-- 📸 Open EROR spec" "$EROR_SPEC"
open_dir_menu "-- 📁 Open audit root" "$AUDIT_ROOT"
menu "-- 💻 Open ~/.eco/" "bash=/usr/bin/open param1=${ECO} terminal=false"


# ── Docs & Views ──
divider
section "📚 Docs"
open_file_menu "-- 📘 README" "$README_DOC"
open_file_menu "-- 📚 Docs index" "$DOCS_INDEX"
open_file_menu "-- 🧭 Reading order" "$DOCS_READING_ORDER"
open_file_menu "-- ⌨️ CLI reference" "$CLI_REFERENCE_DOC"
open_file_menu "-- ⚙ Configuration" "$CONFIGURATION_DOC"
open_file_menu "-- 🧰 Recipes docs" "$RECIPES_DOC"
open_file_menu "-- 🧭 Widget health" "$WIDGET_HEALTH_DOC"
open_file_menu "-- 🧾 Changelog" "$CHANGELOG_DOC"
open_file_menu "-- 🌐 Dashboard" "$DASHBOARD"
open_file_menu "-- 📝 Map" "$MAP"
open_file_menu "-- 🔍 state.json" "$STATE"
open_file_menu "-- 🔍 usage.json" "$USAGE_JSON"
[ -x "$SNAPSHOT_SCRIPT" ] && menu "-- 📸 Save snapshot (PNG + clipboard)" "bash=${SNAPSHOT_SCRIPT} terminal=false refresh=true"
[ -f "$ECO/logs/usage-poller.err.log" ] && menu "-- 📋 Tail poller log" "bash=/usr/bin/open param1=-a param2=Console param3=${ECO}/logs/usage-poller.err.log terminal=false"
menu "-- Restart poller" "bash=/bin/launchctl param1=kickstart param2=-k param3=gui/$(id -u)/com.eco-commander.usage-poller terminal=false refresh=true"


# ── Alerts ──
divider
if [ -f "$STATE" ] && have_jq; then
  if [ "${actionable_alert_count:-0}" -eq 0 ]; then
    menu "✓ 0 Alerts" "color=green size=12"
    [ "${alert_count:-0}" -gt 0 ] && menu "-- ${alert_count} total candidates · ${resolved_count} cleared" "color=gray size=10"
  else
    menu "⚠ ${actionable_alert_count} Alerts" "color=orange size=12"
    menu "-- ${verified_active_count} live · ${evidence_count} evidence · ${triage_count} triage · ${resolved_count} cleared · ${alert_count} total" "color=gray size=10"
    for ((i = 0; i < parsed_issue_count; i++)); do
      if [ "${issue_statuses[$i]}" = "resolved" ] && [ "${ECO_ALERT_SHOW_CLEARED:-0}" != "1" ]; then
        continue
      fi
      issue="[${issue_severities[$i]}] ${issue_ids[$i]}: ${issue_descs[$i]}"
      short="${issue:0:110}"
      [ "${#issue}" -gt 110 ] && short="${short}…"
      menu "-- ${issue_icons[$i]} ${issue_priorities[$i]} · ${issue_categories[$i]} · $short — ${issue_statuses[$i]}" "color=${issue_colors[$i]} size=11"
      menu "---- ${issue_details[$i]}" "color=gray size=10"
      if [ -x "$ALERT_ACTION" ]; then
        if [ -n "${issue_action_ids[$i]}" ] && is_safe_action_arg "${issue_action_ids[$i]}"; then
          menu "---- Open evidence" "bash=${ALERT_ACTION} param1=open-source param2=${issue_action_ids[$i]} terminal=false"
          if [ -n "${issue_action_keys[$i]}" ] && is_safe_action_arg "${issue_action_keys[$i]}"; then
            if [ "${issue_action_keys[$i]}" = "fix-guide-stale" ]; then
              menu "---- Fix: ${issue_action_labels[$i]}" "bash=${ALERT_ACTION} param1=${issue_action_keys[$i]} terminal=false refresh=true"
            else
              menu "---- Fix: ${issue_action_labels[$i]}" "bash=${ALERT_ACTION} param1=run-logged param2=${issue_action_keys[$i]} param3=${issue_action_ids[$i]} terminal=false refresh=true"
            fi
          fi
        else
          menu "---- Evidence action unavailable: unsafe issue id" "color=gray size=10"
        fi
      fi
    done
  fi
else
  menu "⚠ Alerts (jq or state missing)" "color=gray size=12"
fi


# ── Domains ──
divider
menu "🏛 11 Domains" "color=white size=12"
domain_doc_target=""
if [ -f "$DOMAIN_CHARTERS" ]; then
  domain_doc_target="$DOMAIN_CHARTERS"
  menu "-- Audit charter (${snapshot_age_label} old)" "color=${snapshot_color} size=10"
elif [ -f "$DOCS_INDEX" ]; then
  domain_doc_target="$DOCS_INDEX"
  menu "-- Public docs index" "color=gray size=10"
elif [ -f "$README_DOC" ]; then
  domain_doc_target="$README_DOC"
  menu "-- Public README" "color=gray size=10"
else
  menu "-- No shipped docs target found" "color=gray size=10"
fi
declare -a domains=(
  "D1|Memory/RAG" "D2|MCP Wiring" "D3|Agents" "D4|Toolkit" "D5|Plugins"
  "D6|Hooks" "D7|Clients" "D8|Local LLMs" "D9|Projects" "D10|External" "D11|EROR"
)
for d in "${domains[@]}"; do
  id="${d%%|*}"
  name="${d##*|}"
  if [ -n "$domain_doc_target" ]; then
    menu "-- ${id} ${name}" "bash=/usr/bin/open param1=${domain_doc_target} terminal=false"
  else
    menu "-- ${id} ${name}" "color=gray"
  fi
done


# ── Footer ──
divider
if [ -f "$STATE" ] && have_jq; then
  menu "Snapshot ${snap_id}" "color=gray size=10"
  menu "Generated ${gen_at}" "color=gray size=10"
fi
menu "↻ Refresh" "refresh=true color=gray"

exit 0
