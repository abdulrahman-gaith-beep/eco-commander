#!/usr/bin/env bash
# Generate a shareable snapshot of the current usage data.
#
# Outputs:
#   ~/.eco/usage-snapshots/eco-usage-YYYYMMDD-HHMM.png   (rendered card image)
#   ~/.eco/usage-snapshots/eco-usage-YYYYMMDD-HHMM.txt   (plain text, also clipboard)
# Override with ECO_SNAPSHOT_DIR when a one-off destination is intentional.
# Image goes to clipboard. Reveals PNG in Finder. Sends notification.
#
# Triggered from the SwiftBar widget's "Save snapshot" action — which runs
# under a restricted PATH (/usr/bin:/bin:/usr/sbin:/sbin) where Homebrew
# binaries (timeout, ollama) and user-local binaries (claude) aren't found.
# Prepend the right paths first, BEFORE `set -e`, so a missing optional
# binary later doesn't silently kill the whole snapshot.

# 1. PATH first — covers SwiftBar's restricted env + makes the script
# behave the same in Terminal and from the menu-bar dropdown.
for _p in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/.cargo/bin" /opt/homebrew/sbin; do
  case ":$PATH:" in *":$_p:"*) ;; *) PATH="$_p:$PATH" ;; esac
done
export PATH
unset _p
umask 077

# 2. Logging — when SwiftBar runs us with terminal=false, stderr is
# discarded by default. Mirror it to a log so failures are debuggable.
LOG_DIR="${ECO_HOME:-$HOME/.eco}/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
chmod 0700 "$LOG_DIR" 2>/dev/null || true
exec 2> >(tee -a "$LOG_DIR/usage-snapshot.err.log" >&2)

set -uo pipefail   # NOTE: dropped -e so optional probes don't kill the run.
                   # Each "must succeed" call uses explicit `|| { ... ; exit 1; }`.

command -v jq >/dev/null 2>&1 || {
  echo "usage-snapshot.sh: jq not found on PATH" >&2
  exit 127
}

ECO_ROOT="${ECO_HOME:-$HOME/.eco}"
USAGE_JSON="$ECO_ROOT/current/usage.json"
DEFAULT_OUT_DIR="$ECO_ROOT/usage-snapshots"
OUT_DIR="${ECO_SNAPSHOT_DIR:-$DEFAULT_OUT_DIR}"
TS="$(date +%Y%m%d-%H%M)"
PNG_PATH="$OUT_DIR/eco-usage-$TS.png"
TXT_PATH="$OUT_DIR/eco-usage-$TS.txt"
ECO_SNAPSHOT_CLIPBOARD="${ECO_SNAPSHOT_CLIPBOARD:-1}"
ECO_SNAPSHOT_REVEAL="${ECO_SNAPSHOT_REVEAL:-1}"
ECO_SNAPSHOT_NOTIFY="${ECO_SNAPSHOT_NOTIFY:-1}"

mkdir -p "$OUT_DIR"
chmod 0700 "$OUT_DIR" 2>/dev/null || true

# Use whichever timeout-equivalent is available. macOS doesn't ship `timeout`;
# Homebrew coreutils provides /opt/homebrew/bin/timeout (gtimeout works too).
# If neither is found, run the command bare — sub-second probe latency on a
# local machine is fine without an enforced cap.
_run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout  >/dev/null 2>&1; then timeout  "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  else "$@"
  fi
}

if [ ! -f "$USAGE_JSON" ]; then
  if [ "$ECO_SNAPSHOT_NOTIFY" = "1" ]; then
    osascript -e 'display notification "Run the poller first." with title "eco-commander" subtitle "No usage data found"' || true
  fi
  exit 1
fi

if ! jq empty "$USAGE_JSON" >/dev/null 2>&1; then
  echo "usage-snapshot.sh: usage.json is invalid JSON: $USAGE_JSON" >&2
  exit 1
fi

# ------- humanize helper (shared via lib/snapshot-helpers.sh) -------
_SNAPSHOT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/snapshot-helpers.sh
source "$_SNAPSHOT_REPO_ROOT/scripts/lib/snapshot-helpers.sh"
unset _SNAPSHOT_REPO_ROOT

# ------- pull data -------
ts=$(jq -r '.ts // 0' "$USAGE_JSON")
when="$(date -r "$ts" '+%Y-%m-%d %H:%M:%S %Z')"

account_count() {
  case "${1:-}" in
    ""|*[!0-9]*) printf '0' ;;
    *) printf '%d' "$((10#$1))" ;;
  esac
}

c_plan=$(jq -r '.claude.plan // "Unknown"' "$USAGE_JSON")
c_acc=$(account_count "$(jq -r '.claude.accounts // 0' "$USAGE_JSON")")
g_plan=$(jq -r '.gemini.plan // "Unknown"' "$USAGE_JSON")
g_acc=$(account_count "$(jq -r '.gemini.accounts // 0' "$USAGE_JSON")")
x_plan=$(jq -r '.codex.plan // "Unknown"' "$USAGE_JSON")
x_acc=$(account_count "$(jq -r '.codex.accounts // 0' "$USAGE_JSON")")

c_models=$(jq -r '.claude.weekly.models_seen // [] | join(" · ")' "$USAGE_JSON")
g_models=$(jq -r '[.gemini.tiers.flash.model_id, .gemini.tiers.flash_lite.model_id, .gemini.tiers.pro.model_id] | map(select(. != null)) | unique | join(" · ")' "$USAGE_JSON")

# ------- detect local stack (CLIs, Ollama models, apps) -------
clis=()
for spec in \
  "claude:Claude Code:--version" \
  "gemini:Gemini CLI:--version" \
  "codex:Codex CLI:--version" \
  "ollama:Ollama:--version" \
  "uv:uv:--version" \
  "python3:Python:--version" \
  "node:Node:--version"; do
  cmd="${spec%%:*}"; rest="${spec#*:}"
  label="${rest%%:*}"; flag="${rest#*:}"
  if command -v "$cmd" >/dev/null 2>&1; then
    v="$(_run_with_timeout 2 "$cmd" "$flag" 2>/dev/null | head -1 \
         | sed -E 's/^[^0-9]*//;s/[[:space:]]+\(.*$//' | head -c 25)"
    [ -n "$v" ] && clis+=("$label $v") || clis+=("$label")
  fi
done

ollama_models=""
ollama_count=0
if command -v ollama >/dev/null 2>&1; then
  ol_raw="$(_run_with_timeout 3 ollama list 2>/dev/null | tail -n +2)"
  if [ -n "$ol_raw" ]; then
    ollama_count=$(printf '%s\n' "$ol_raw" | awk 'NF>0' | wc -l | tr -d ' ')
    ollama_models="$(printf '%s\n' "$ol_raw" \
      | awk '{name=$1; size=$3 $4; if(name && name!="NAME") print name " (" size ")"}' \
      | head -8 | awk 'NR>1{printf " · "} {printf "%s", $0}')"
  fi
fi

apps=()
for app in "Claude" "Cursor" "SwiftBar" "Antigravity" "LM Studio" "Ollama" "Visual Studio Code"; do
  if [ -d "/Applications/$app.app" ]; then
    apps+=("$app")
  fi
done

c_ok=$(jq -r '.claude.ok // false' "$USAGE_JSON")
c_src=$(jq -r '.claude.source // "jsonl"' "$USAGE_JSON")
c_stale=$(jq -r '.claude.stale // false' "$USAGE_JSON")
x_src=$(jq -r '.codex.source // "jsonl"' "$USAGE_JSON")
x_stale=$(jq -r '.codex.stale // false' "$USAGE_JSON")
g_src=$(jq -r '.gemini.source // "stub"' "$USAGE_JSON")
c_s_pct=$(jq -r '.claude.session.pct // 0' "$USAGE_JSON")
c_w_pct=$(jq -r '.claude.weekly.pct // 0' "$USAGE_JSON")
c_w_all=$(jq -r '.claude.weekly.pct_all // 0' "$USAGE_JSON")
c_w_son=$(jq -r '.claude.weekly.pct_sonnet // 0' "$USAGE_JSON")
c_s_in=$(jq -r '.claude.session.resets_in // "—"' "$USAGE_JSON")
c_w_in=$(jq -r '.claude.weekly.resets_in // "—"' "$USAGE_JSON")
c_s_bill=$(jq -r '.claude.session.tokens // 0' "$USAGE_JSON")
c_w_bill=$(jq -r '.claude.weekly.tokens // 0' "$USAGE_JSON")
c_op_b=$(jq -r '.claude.weekly.by_model.opus // 0' "$USAGE_JSON")
c_so_b=$(jq -r '.claude.weekly.by_model.sonnet // 0' "$USAGE_JSON")
c_ha_b=$(jq -r '.claude.weekly.by_model.haiku // 0' "$USAGE_JSON")

g_ok=$(jq -r '.gemini.ok // false' "$USAGE_JSON")
g_fl=$(jq -r '.gemini.tiers.flash.pct // 0' "$USAGE_JSON")
g_fl_in=$(jq -r '.gemini.tiers.flash.resets_in // "—"' "$USAGE_JSON")
g_fll=$(jq -r '.gemini.tiers.flash_lite.pct // 0' "$USAGE_JSON")
g_fll_in=$(jq -r '.gemini.tiers.flash_lite.resets_in // "—"' "$USAGE_JSON")
g_pr=$(jq -r '.gemini.tiers.pro.pct // 0' "$USAGE_JSON")
g_pr_in=$(jq -r '.gemini.tiers.pro.resets_in // "—"' "$USAGE_JSON")

x_ok=$(jq -r '.codex.ok // false' "$USAGE_JSON")
x_s_pct=$(jq -r '.codex.session.pct // 0' "$USAGE_JSON")
x_w_pct=$(jq -r '.codex.weekly.pct // 0' "$USAGE_JSON")
x_s_in=$(jq -r '.codex.session.resets_in // "—"' "$USAGE_JSON")
x_w_in=$(jq -r '.codex.weekly.resets_in // "—"' "$USAGE_JSON")

c_s_pct="$(safe_pct "$c_s_pct")"
c_w_pct="$(safe_pct "$c_w_pct")"
c_w_all="$(safe_pct "$c_w_all")"
c_w_son="$(safe_pct "$c_w_son")"
g_fl="$(safe_pct "$g_fl")"
g_fll="$(safe_pct "$g_fll")"
g_pr="$(safe_pct "$g_pr")"
x_s_pct="$(safe_pct "$x_s_pct")"
x_w_pct="$(safe_pct "$x_w_pct")"

# ------- text version -------
# acct_label, _join sourced from lib/snapshot-helpers.sh

source_summary() {
  local lc lx lg
  case "$c_src" in api) lc="server-truth";; jsonl) lc="jsonl-estimate";; *) lc="$c_src";; esac
  case "$x_src" in api) lx="server-truth";; jsonl) lx="jsonl-estimate";; *) lx="$x_src";; esac
  case "$g_src" in stub|"") lg="";; *) lg="server-truth";; esac
  local server=() jsonl=()
  if [ "$lc" = "server-truth" ]; then
    server+=("Claude")
  elif [ "$lc" = "jsonl-estimate" ]; then
    jsonl+=("Claude")
  fi
  if [ "$lx" = "server-truth" ]; then
    server+=("Codex")
  elif [ "$lx" = "jsonl-estimate" ]; then
    jsonl+=("Codex")
  fi
  [ "$lg" = "server-truth" ] && server+=("Gemini")
  local parts=()
  [ "${#server[@]}" -gt 0 ] && parts+=("server-truth ($(_join "${server[@]}"))")
  [ "${#jsonl[@]}" -gt 0 ]  && parts+=("jsonl-estimate ($(_join "${jsonl[@]}"))")
  if [ "${#parts[@]}" -eq 0 ]; then
    echo "no data"
  else
    _join "${parts[@]}"
  fi
}

{
  echo "AI Usage Snapshot · $when"
  printf '─%.0s' {1..60}; echo
  echo "Plans: $(acct_label "$c_acc" "Claude $c_plan") · $(acct_label "$g_acc" "Gemini $g_plan") · $(acct_label "$x_acc" "Codex $x_plan")"
  echo
  if [ "$c_ok" = "true" ]; then
    c_stale_mark=""; [ "$c_stale" = "true" ] && c_stale_mark=" · cached (rate-limited)"
    if [ -n "$c_models" ]; then
      printf "Claude Code · %s · models: %s%s\n" "$(acct_label "$c_acc" "$c_plan")" "$c_models" "$c_stale_mark"
    else
      printf "Claude Code · %s%s\n" "$(acct_label "$c_acc" "$c_plan")" "$c_stale_mark"
    fi
    printf "  Session  %s  %3d%%  resets in %s\n" "$(bar_fill "$c_s_pct")" "$(printf '%.0f' "$c_s_pct")" "$c_s_in"
    if [ "$c_src" != "api" ]; then
      printf "             billable: %s\n" "$(humanize "$c_s_bill")"
    fi
    printf "  Weekly   %s  %3d%%  resets in %s\n" "$(bar_fill "$c_w_pct")" "$(printf '%.0f' "$c_w_pct")" "$c_w_in"
    printf "             all-models %.0f%% · sonnet-only %.0f%%\n" "$c_w_all" "$c_w_son"
    if [ "$c_src" != "api" ]; then
      printf "             by model: opus %s · sonnet %s · haiku %s\n" "$(humanize "$c_op_b")" "$(humanize "$c_so_b")" "$(humanize "$c_ha_b")"
      printf "             billable: %s\n" "$(humanize "$c_w_bill")"
    fi
    echo
  fi
  if [ "$g_ok" = "true" ]; then
    printf "Gemini CLI · %s · models: %s\n" "$(acct_label "$g_acc" "$g_plan")" "${g_models:-—}"
    printf "  Flash      %s  %3d%%  resets in %s\n" "$(bar_fill "$g_fl")"  "$(printf '%.0f' "$g_fl")"  "$g_fl_in"
    printf "  Flash Lite %s  %3d%%  resets in %s\n" "$(bar_fill "$g_fll")" "$(printf '%.0f' "$g_fll")" "$g_fll_in"
    printf "  Pro        %s  %3d%%  resets in %s\n" "$(bar_fill "$g_pr")"  "$(printf '%.0f' "$g_pr")"  "$g_pr_in"
    echo
  fi
  if [ "$x_ok" = "true" ]; then
    printf "Codex CLI · %s · GPT-5.5\n" "$(acct_label "$x_acc" "$x_plan")"
    printf "  Session  %s  %3d%%  resets in %s\n" "$(bar_fill "$x_s_pct")" "$(printf '%.0f' "$x_s_pct")" "$x_s_in"
    printf "  Weekly   %s  %3d%%  resets in %s\n" "$(bar_fill "$x_w_pct")" "$(printf '%.0f' "$x_w_pct")" "$x_w_in"
  fi
  echo
  echo "Local Stack"
  if [ "${#clis[@]}" -gt 0 ]; then
    echo "  CLIs: $(printf '%s\n' "${clis[@]}" | awk 'NR>1{printf " · "} {printf "%s", $0}')"
  fi
  if [ "${#apps[@]}" -gt 0 ]; then
    echo "  Apps: $(printf '%s\n' "${apps[@]}" | awk 'NR>1{printf " · "} {printf "%s", $0}')"
  fi
  if [ -n "$ollama_models" ]; then
    echo "  Ollama (${ollama_count} model$([ "$ollama_count" -ne 1 ] && echo s)): $ollama_models"
  fi
  echo
  echo "via eco-commander · $(source_summary)"
} > "$TXT_PATH"
chmod 0600 "$TXT_PATH" 2>/dev/null || true

# ------- copy text to clipboard -------
if [ "$ECO_SNAPSHOT_CLIPBOARD" = "1" ] && command -v pbcopy >/dev/null 2>&1; then
  pbcopy < "$TXT_PATH"
fi

# ------- HTML card (rendered to PNG via qlmanage) -------
HTML_TMP="$(mktemp -d)/card.html"

# color_for, pace_glyph, target_mark, html_escape sourced from lib/snapshot-helpers.sh
c_s_color=$(color_for "$c_s_pct"); c_w_color=$(color_for "$c_w_pct")
g_fl_color=$(color_for "$g_fl"); g_fll_color=$(color_for "$g_fll"); g_pr_color=$(color_for "$g_pr")
x_s_color=$(color_for "$x_s_pct"); x_w_color=$(color_for "$x_w_pct")

suggestion=$(python3 - "$USAGE_JSON" <<'PY' 2>/dev/null || true
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)

def pct(path):
    node = data
    for key in path:
        if not isinstance(node, dict):
            return 0.0
        node = node.get(key)
    try:
        return float(node or 0)
    except (TypeError, ValueError):
        return 0.0

checks = [
    ("Claude session", pct(["claude", "session", "pct"])),
    ("Claude weekly", pct(["claude", "weekly", "pct"])),
    ("Codex session", pct(["codex", "session", "pct"])),
    ("Codex weekly", pct(["codex", "weekly", "pct"])),
    ("Gemini Flash", pct(["gemini", "tiers", "flash", "pct"])),
    ("Gemini Pro", pct(["gemini", "tiers", "pro", "pct"])),
]
label, value = max(checks, key=lambda item: item[1])
if value >= 90:
    print(f"{label} is near its cap; route new work to another available model.")
elif value >= 75:
    print(f"{label} is heating up; prefer lighter or alternate lanes for the next batch.")
PY
)

# Build account header strings
c_acct_html="Claude $c_plan"; [ "$c_acc" -gt 1 ] && c_acct_html="Claude $c_plan × $c_acc"
g_acct_html="Gemini $g_plan"; [ "$g_acc" -gt 1 ] && g_acct_html="Gemini $g_plan × $g_acc"
x_acct_html="Codex $x_plan"; [ "$x_acc" -gt 1 ] && x_acct_html="Codex $x_plan × $x_acc"

# h2 subtitle for each section
c_h2_acct="$c_plan"; [ "$c_acc" -gt 1 ] && c_h2_acct="$c_plan × $c_acc"
g_h2_acct="$g_plan"; [ "$g_acc" -gt 1 ] && g_h2_acct="$g_plan × $g_acc"
x_h2_acct="$x_plan"; [ "$x_acc" -gt 1 ] && x_h2_acct="$x_plan × $x_acc"

when_html="$(printf '%s' "$when" | html_escape)"
c_acct_html="$(printf '%s' "$c_acct_html" | html_escape)"
g_acct_html="$(printf '%s' "$g_acct_html" | html_escape)"
x_acct_html="$(printf '%s' "$x_acct_html" | html_escape)"
c_h2_acct_html="$(printf '%s' "$c_h2_acct" | html_escape)"
g_h2_acct_html="$(printf '%s' "$g_h2_acct" | html_escape)"
x_h2_acct_html="$(printf '%s' "$x_h2_acct" | html_escape)"
c_models_html="$(printf '%s' "$c_models" | html_escape)"
g_models_html="$(printf '%s' "$g_models" | html_escape)"
c_s_in_html="$(printf '%s' "$c_s_in" | html_escape)"
c_w_in_html="$(printf '%s' "$c_w_in" | html_escape)"
g_fl_in_html="$(printf '%s' "$g_fl_in" | html_escape)"
g_fll_in_html="$(printf '%s' "$g_fll_in" | html_escape)"
g_pr_in_html="$(printf '%s' "$g_pr_in" | html_escape)"
x_s_in_html="$(printf '%s' "$x_s_in" | html_escape)"
x_w_in_html="$(printf '%s' "$x_w_in" | html_escape)"
suggestion_html="$(printf '%s' "$suggestion" | html_escape)"
source_summary_html="$(source_summary | html_escape)"
x_h2_org_label="${ECO_ORG_LABEL:-}"
x_h2_org_html=""; [ -n "$x_h2_org_label" ] && x_h2_org_html=" · $(printf '%s' "$x_h2_org_label" | html_escape)"
x_h2_stale=""; [ "$x_stale" = "true" ] && x_h2_stale=' · <span style="color:#f59e0b">cached (rate-limited)</span>'

c_s_target=$(jq -r '.claude.session.target_pct // 0' "$USAGE_JSON")
c_s_pace=$(jq -r '.claude.session.pace_label // ""' "$USAGE_JSON")
c_w_target=$(jq -r '.claude.weekly.target_pct // 0' "$USAGE_JSON")
c_w_pace=$(jq -r '.claude.weekly.pace_label // ""' "$USAGE_JSON")
g_fl_target=$(jq -r '.gemini.tiers.flash.target_pct // 0' "$USAGE_JSON")
g_fl_pace=$(jq -r '.gemini.tiers.flash.pace_label // ""' "$USAGE_JSON")
g_fll_target=$(jq -r '.gemini.tiers.flash_lite.target_pct // 0' "$USAGE_JSON")
g_fll_pace=$(jq -r '.gemini.tiers.flash_lite.pace_label // ""' "$USAGE_JSON")
g_pr_target=$(jq -r '.gemini.tiers.pro.target_pct // 0' "$USAGE_JSON")
g_pr_pace=$(jq -r '.gemini.tiers.pro.pace_label // ""' "$USAGE_JSON")
x_s_target=$(jq -r '.codex.session.target_pct // 0' "$USAGE_JSON")
x_s_pace=$(jq -r '.codex.session.pace_label // ""' "$USAGE_JSON")
x_w_target=$(jq -r '.codex.weekly.target_pct // 0' "$USAGE_JSON")
x_w_pace=$(jq -r '.codex.weekly.pace_label // ""' "$USAGE_JSON")
c_s_target="$(safe_pct "$c_s_target")"
c_w_target="$(safe_pct "$c_w_target")"
g_fl_target="$(safe_pct "$g_fl_target")"
g_fll_target="$(safe_pct "$g_fll_target")"
g_pr_target="$(safe_pct "$g_pr_target")"
x_s_target="$(safe_pct "$x_s_target")"
x_w_target="$(safe_pct "$x_w_target")"

cat > "$HTML_TMP" <<HTML
<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 32px;
    font: 14px/1.5 -apple-system, "SF Pro Display", system-ui, sans-serif;
    background: #0b0e14; color: #d6deeb;
    width: 760px;
  }
  h1 { font-size: 22px; margin: 0 0 4px 0; color: #fff; letter-spacing: -0.4px; }
  .when { color: #6b7280; font-size: 12px; margin-bottom: 14px; }
  .plans { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 22px; }
  .suggestion { background: #1e2937; border-left: 4px solid #f59e0b; padding: 10px; margin-bottom: 20px; font-size: 13px; color: #f3f4f6; }
  .chip { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; background: #1e2937; border-radius: 999px; font-size: 11px; color: #cbd5e1; }
  .chip .x { color: #818cf8; font-weight: 700; font-variant-numeric: tabular-nums; }
  h2 { font-size: 13px; margin: 18px 0 4px 0; color: #f3f4f6; font-weight: 600; letter-spacing: 0.2px; }
  h2 .sub { color: #6b7280; font-weight: 400; font-size: 11px; margin-left: 6px; }
  .models { color: #6b7280; font-size: 10px; margin: 0 0 8px 0; font-family: ui-monospace, "SF Mono", monospace; letter-spacing: 0.1px; }
  .row { display: flex; align-items: center; margin: 6px 0; gap: 12px; }
  .label { width: 90px; font-size: 13px; color: #cbd5e1; }
  .bar { flex: 1; height: 10px; border-radius: 5px; background: #1e2937; overflow: hidden; position: relative; }
  .fill { height: 100%; border-radius: 5px; }
  .pct { width: 45px; text-align: right; font-variant-numeric: tabular-nums; font-weight: 600; }
  .reset { width: 130px; color: #6b7280; font-size: 12px; text-align: right; font-variant-numeric: tabular-nums; }
  .breakdown { color: #6b7280; font-size: 11px; margin: 2px 0 6px 102px; font-family: ui-monospace, "SF Mono", monospace; }
  .stack-row { display: flex; gap: 14px; margin: 4px 0; align-items: baseline; }
  .stack-label { width: 90px; color: #9aa5b1; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; flex-shrink: 0; }
  .stack-val { color: #cbd5e1; font-size: 11px; font-family: ui-monospace, "SF Mono", monospace; word-break: break-all; }
  .footer { color: #4b5563; font-size: 10px; margin-top: 20px; padding-top: 12px; border-top: 1px solid #1e2937; }
  .brand { color: #818cf8; font-weight: 700; }
</style></head><body>
  <h1>AI Usage Snapshot</h1>
  <div class="when">$when_html</div>
HTML

if [ -n "$suggestion" ]; then
  cat >> "$HTML_TMP" <<HTML
  <div class="suggestion">💡 Suggestion: $suggestion_html</div>
HTML
fi

cat >> "$HTML_TMP" <<HTML
  <div class="plans">
    <span class="chip">$c_acct_html</span>
    <span class="chip">$g_acct_html</span>
    <span class="chip">$x_acct_html</span>
  </div>
HTML

if [ "$c_ok" = "true" ]; then
  c_h2_stale=""; [ "$c_stale" = "true" ] && c_h2_stale=' · <span style="color:#f59e0b">cached (rate-limited)</span>'
  cat >> "$HTML_TMP" <<HTML
  <h2>Claude Code <span class="sub">$c_h2_acct_html$c_h2_stale</span></h2>
HTML
  if [ -n "$c_models" ]; then
    cat >> "$HTML_TMP" <<HTML
  <div class="models">$c_models_html</div>
HTML
  fi
  cat >> "$HTML_TMP" <<HTML
  <div class="row">
    <div class="label">Session</div>
    <div class="bar"><div class="fill" style="width:${c_s_pct}%; background:$c_s_color"></div>$(target_mark "$c_s_target")</div>
    <div class="pct" style="color:$c_s_color">$(printf '%.0f' "$c_s_pct")%$(pace_glyph "$c_s_pace")</div>
    <div class="reset">resets in $c_s_in_html</div>
  </div>
HTML
  if [ "$c_src" != "api" ]; then
    cat >> "$HTML_TMP" <<HTML
  <div class="breakdown">billable $(humanize "$c_s_bill")</div>
HTML
  fi
  cat >> "$HTML_TMP" <<HTML
  <div class="row">
    <div class="label">Weekly</div>
    <div class="bar"><div class="fill" style="width:${c_w_pct}%; background:$c_w_color"></div>$(target_mark "$c_w_target")</div>
    <div class="pct" style="color:$c_w_color">$(printf '%.0f' "$c_w_pct")%$(pace_glyph "$c_w_pace")</div>
    <div class="reset">resets in $c_w_in_html</div>
  </div>
  <div class="breakdown">all-models $(printf '%.0f' "$c_w_all")% · sonnet-only $(printf '%.0f' "$c_w_son")%</div>
HTML
  if [ "$c_src" != "api" ]; then
    cat >> "$HTML_TMP" <<HTML
  <div class="breakdown">opus $(humanize "$c_op_b") · sonnet $(humanize "$c_so_b") · haiku $(humanize "$c_ha_b") · billable $(humanize "$c_w_bill")</div>
HTML
  fi
fi

if [ "$g_ok" = "true" ]; then
  cat >> "$HTML_TMP" <<HTML
  <h2>Gemini CLI <span class="sub">$g_h2_acct_html</span></h2>
  <div class="models">${g_models_html:-—}</div>
  <div class="row">
    <div class="label">Flash</div>
    <div class="bar"><div class="fill" style="width:${g_fl}%; background:$g_fl_color"></div>$(target_mark "$g_fl_target")</div>
    <div class="pct" style="color:$g_fl_color">$(printf '%.0f' "$g_fl")%$(pace_glyph "$g_fl_pace")</div>
    <div class="reset">resets in $g_fl_in_html</div>
  </div>
  <div class="row">
    <div class="label">Flash Lite</div>
    <div class="bar"><div class="fill" style="width:${g_fll}%; background:$g_fll_color"></div>$(target_mark "$g_fll_target")</div>
    <div class="pct" style="color:$g_fll_color">$(printf '%.0f' "$g_fll")%$(pace_glyph "$g_fll_pace")</div>
    <div class="reset">resets in $g_fll_in_html</div>
  </div>
  <div class="row">
    <div class="label">Pro</div>
    <div class="bar"><div class="fill" style="width:$g_pr%; background:$g_pr_color"></div>$(target_mark "$g_pr_target")</div>
    <div class="pct" style="color:$g_pr_color">$(printf '%.0f' "$g_pr")%$(pace_glyph "$g_pr_pace")</div>
    <div class="reset">resets in $g_pr_in_html</div>
  </div>

HTML
fi

if [ "$x_ok" = "true" ]; then
  cat >> "$HTML_TMP" <<HTML
  <h2>Codex CLI <span class="sub">$x_h2_acct_html$x_h2_org_html$x_h2_stale</span></h2>
  <div class="models">gpt-5.5 (default)</div>
  <div class="row">
    <div class="label">Session</div>
    <div class="bar"><div class="fill" style="width:${x_s_pct}%; background:$x_s_color"></div>$(target_mark "$x_s_target")</div>
    <div class="pct" style="color:$x_s_color">$(printf '%.0f' "$x_s_pct")%$(pace_glyph "$x_s_pace")</div>
    <div class="reset">resets in $x_s_in_html</div>
  </div>
  <div class="row">
    <div class="label">Weekly</div>
    <div class="bar"><div class="fill" style="width:${x_w_pct}%; background:$x_w_color"></div>$(target_mark "$x_w_target")</div>
    <div class="pct" style="color:$x_w_color">$(printf '%.0f' "$x_w_pct")%$(pace_glyph "$x_w_pace")</div>
    <div class="reset">resets in $x_w_in_html</div>
  </div>
HTML
fi

# ---------- Local Stack section ----------
clis_html=""
if [ "${#clis[@]}" -gt 0 ]; then
  clis_html="$(printf '%s\n' "${clis[@]}" | awk 'NR>1{printf " · "} {printf "%s", $0}')"
  clis_html="$(printf '%s' "$clis_html" | html_escape)"
fi
apps_html=""
if [ "${#apps[@]}" -gt 0 ]; then
  apps_html="$(printf '%s\n' "${apps[@]}" | awk 'NR>1{printf " · "} {printf "%s", $0}')"
  apps_html="$(printf '%s' "$apps_html" | html_escape)"
fi
ollama_models_html="$(printf '%s' "$ollama_models" | html_escape)"

if [ -n "$clis_html" ] || [ -n "$apps_html" ] || [ -n "$ollama_models" ]; then
  cat >> "$HTML_TMP" <<HTML
  <h2>Local Stack</h2>
HTML
  if [ -n "$clis_html" ]; then
    cat >> "$HTML_TMP" <<HTML
  <div class="stack-row"><span class="stack-label">CLIs</span><span class="stack-val">$clis_html</span></div>
HTML
  fi
  if [ -n "$apps_html" ]; then
    cat >> "$HTML_TMP" <<HTML
  <div class="stack-row"><span class="stack-label">Apps</span><span class="stack-val">$apps_html</span></div>
HTML
  fi
  if [ -n "$ollama_models" ]; then
    ol_label="Ollama"
    [ "$ollama_count" -gt 0 ] && ol_label="Ollama · $ollama_count model$([ "$ollama_count" -ne 1 ] && echo s)"
    ol_label_html="$(printf '%s' "$ol_label" | html_escape)"
    cat >> "$HTML_TMP" <<HTML
  <div class="stack-row"><span class="stack-label">$ol_label_html</span><span class="stack-val">$ollama_models_html</span></div>
HTML
  fi
fi

if jq -e '.alternatives' "$USAGE_JSON" >/dev/null 2>&1; then
  alt_ollama_html="$(jq -r '.alternatives.ollama.models[]?.name' "$USAGE_JSON" | tr '\n' ' ' | html_escape)"
  cat >> "$HTML_TMP" <<HTML
  <h2>Alternatives</h2>
  <div class="stack-row"><span class="stack-val">Antigravity ⚙ stub · Cursor ⚙ stub · VS Code ✓ always_available · Ollama $alt_ollama_html</span></div>
HTML
fi

cat >> "$HTML_TMP" <<HTML
  <div class="footer">via <span class="brand">eco-commander</span> · $source_summary_html</div>
</body></html>
HTML

# Render HTML → PNG via Quick Look (built-in macOS).
ql_out_dir="$(mktemp -d)"
if /usr/bin/qlmanage -t -s 1600 -o "$ql_out_dir" "$HTML_TMP" >/dev/null 2>&1; then
  rendered="$ql_out_dir/$(basename "$HTML_TMP").png"
  if [ -f "$rendered" ]; then
    mv "$rendered" "$PNG_PATH"
    chmod 0600 "$PNG_PATH" 2>/dev/null || true
  fi
fi

# Fallback: if qlmanage didn't produce a usable PNG, screenshot the HTML
# opened in a hidden window. (Rare — qlmanage handles HTML on every recent
# macOS.) For now, leave PNG_PATH absent if it failed.

copy_png_to_clipboard() {
  [ "$ECO_SNAPSHOT_CLIPBOARD" = "1" ] || return 0
  osascript - "$1" 2>/dev/null <<'OSA' || true
on run argv
  set pngPath to item 1 of argv
  set the clipboard to (read (POSIX file pngPath) as «class PNGf»)
end run
OSA
}

reveal_path() {
  [ "$ECO_SNAPSHOT_REVEAL" = "1" ] || return 0
  /usr/bin/open -R "$1" 2>/dev/null || true
}

notify_snapshot() {
  [ "$ECO_SNAPSHOT_NOTIFY" = "1" ] || return 0
  osascript - "$1" "$2" "$3" 2>/dev/null <<'OSA' || true
on run argv
  display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)
end run
OSA
}

if [ -f "$PNG_PATH" ]; then
  # Copy PNG to clipboard (overrides the text we put earlier — image is
  # what the user wants for sharing).
  copy_png_to_clipboard "$PNG_PATH"
  # Reveal the PNG in Finder so the user knows where it is.
  reveal_path "$PNG_PATH"
  notify_snapshot "PNG saved & copied to clipboard
Text also at $(basename "$TXT_PATH")" "Usage snapshot ready" "$(basename "$PNG_PATH")"
else
  # Text-only path
  reveal_path "$TXT_PATH"
  notify_snapshot "PNG render failed — text saved & copied" "Usage snapshot ready" "$(basename "$TXT_PATH")"
fi

# Cleanup tmp HTML
rm -rf "$(dirname "$HTML_TMP")" "$ql_out_dir" 2>/dev/null || true
