#!/usr/bin/env bash
# Alert workflow helper for Eco Commander.
#
# The SwiftBar widget calls this script for evidence review and targeted
# remediation. It is intentionally terminal-friendly: actions print what they
# are about to do, then verify the result where practical.

set -euo pipefail
umask 077

ECO="${ECO:-${ECO_HOME:-$HOME/.eco}}"
CURRENT="$ECO/current"
STATE="$CURRENT/state.json"
RECIPES_DIR="$ECO/recipes"
RUN_LOG_DIR="$ECO/alert-runs"
FIX_PLAN_DIR="$ECO/fix-plans"
GEMINI_FIX_MODEL="${GEMINI_FIX_MODEL:-gemini-3.1-pro-preview}"
GEMINI_FIX_AGENTS="${GEMINI_FIX_AGENTS:-3}"
REPO_ROOT="${ECO_COMMANDER_REPO:-}"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$HOME/Projects/toolkit}"
TOOLKIT_MEMORY_DIR="$TOOLKIT_ROOT/python/src/toolkit/memory"
MEMORY_ROUTER_MODULE="$TOOLKIT_MEMORY_DIR/router.py"
MEMORY_HOOK="$HOME/.claude/hooks/memory_router.py"
GUIDE_FILE="${GUIDE_FILE:-$HOME/ai-ecosystem-guide.html}"
N8N_URL="${N8N_URL:-http://127.0.0.1:5678/}"
ECO_N8N_EXPECTED="${ECO_N8N_EXPECTED:-1}"

say() { printf '%s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

open_path() {
  local path="$1"
  if command -v open >/dev/null 2>&1; then
    open "$path"
  else
    say "$path"
  fi
}

tail_log_in_terminal() {
  local log="$1"
  [ "${ECO_ALERT_OPEN_TERMINAL:-1}" = "1" ] || return 0
  command -v osascript >/dev/null 2>&1 || return 0

  # Open our own clean Terminal session because SwiftBar's terminal=true mode
  # prints a large environment export prelude before the actual command.
  osascript - "$log" >/dev/null 2>&1 <<'OSA' || true
on run argv
  set logPath to item 1 of argv
  tell application "Terminal"
    activate
    do script "printf '%s\n' " & quoted form of ("Eco alert action log: " & logPath) & " ''; tail -n +1 -f " & quoted form of logPath
  end tell
end run
OSA
}

run_logged() {
  local action="${1:-}"
  [ -n "$action" ] || die "run-logged requires an action"
  shift || true

  case "$action" in
    doctor|repo-health|debug-ollama|delegate-fix|orchestrate-fix|run-recipe|fix-snapshot-timeout|fix-n8n|fix-memory-router|fix-dashboard-refresh|fix-guide-stale|rebuild-memory-indexes)
      ;;
    *)
      die "run-logged does not allow action: $action"
      ;;
  esac

  mkdir -p "$RUN_LOG_DIR"
  local safe_action="${action//[^[:alnum:]_.-]/_}"
  local log
  log="$RUN_LOG_DIR/$(date +%Y%m%dT%H%M%S)-${safe_action}.log"

  (
    rc=0
    {
      say "Eco alert action: $action"
      say "Started: $(date)"
      say
      "$0" "$action" "$@"
    } || rc=$?
    {
      say
      say "Finished: $(date)"
      say "Exit: $rc"
    }
    exit "$rc"
  ) > "$log" 2>&1 &

  local pid=$!
  printf '%s\n' "$pid" > "$RUN_LOG_DIR/latest.pid"
  ln -sfn "$log" "$RUN_LOG_DIR/latest.log"

  case "$action" in
    fix-guide-stale)
      ;;
    *)
      tail_log_in_terminal "$log"
      ;;
  esac

  say "Started $action (pid $pid). Log: $log"
}

issue_layer_path() {
  local issue_id="$1"
  local layer="${issue_id%%:*}"
  case "$layer" in
    ""|.*|*..*|*/*|*\\*|*[[:space:]]*) return 1 ;;
  esac
  [[ "$layer" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s/layers/%s.md\n' "$CURRENT" "$layer"
}

is_safe_ollama_model() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z0-9._:/-]+$ ]] && [[ "$value" != *..* ]]
}

is_safe_action_arg() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]] && [[ "$value" != *..* ]]
}

is_safe_recipe_id() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$value" != *..* ]] && [ "$value" != "_lib" ]
}

sanitize_issue_id() {
  printf '%s' "${1:-unknown}" |
    awk '{
      gsub(/\|.*/, "", $0)
      gsub(/[^A-Za-z0-9_.:-]+/, "_", $0)
      gsub(/_+/, "_", $0)
      gsub(/^_+|_+$/, "", $0)
      print ($0 == "" ? "unknown" : $0)
    }'
}

slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//'
}

issue_desc_from_state() {
  local issue_id="$1"
  [ -f "$STATE" ] || return 1
  jq -r --arg id "$issue_id" '
    def eco_issues:
      ((.layers // {}) | [to_entries[] | select(.key != "Linf_wiring") | .value.issues[]?]) as $layer_issues |
      if ($layer_issues | length) > 0 then $layer_issues else (.layers.Linf_wiring.issues // []) end;
    eco_issues[]? |
    select((.id // "unknown" | tostring) == $id) |
    (.desc // .description // "no description" | tostring)
  ' "$STATE" | head -n 1
}

issue_severity_from_state() {
  local issue_id="$1"
  [ -f "$STATE" ] || return 1
  jq -r --arg id "$issue_id" '
    def eco_issues:
      ((.layers // {}) | [to_entries[] | select(.key != "Linf_wiring") | .value.issues[]?]) as $layer_issues |
      if ($layer_issues | length) > 0 then $layer_issues else (.layers.Linf_wiring.issues // []) end;
    eco_issues[]? |
    select((.id // "unknown" | tostring) == $id) |
    (.severity // "unknown" | tostring)
  ' "$STATE" | head -n 1
}

write_issue_json() {
  local issue_id="$1"
  local out="$2"
  if [ -f "$STATE" ] && command -v jq >/dev/null 2>&1; then
    jq --arg id "$issue_id" '
      def eco_issues:
        ((.layers // {}) | [to_entries[] | select(.key != "Linf_wiring") | .value.issues[]?]) as $layer_issues |
        if ($layer_issues | length) > 0 then $layer_issues else (.layers.Linf_wiring.issues // []) end;
      eco_issues[]? |
      select((.id // "unknown" | tostring) == $id)
    ' "$STATE" > "$out"
  else
    printf '{}\n' > "$out"
  fi
}

make_fix_workspace() {
  local issue_id="$1"
  local slug
  slug="$(slugify "$issue_id")"
  mkdir -p "$FIX_PLAN_DIR"
  local dir
  dir="$FIX_PLAN_DIR/$(date +%Y%m%dT%H%M%S)-${slug}"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

collect_fix_evidence() {
  local issue_id="$1"
  local work="$2"
  local desc="${3:-}"
  local severity="${4:-unknown}"
  local source
  source="$(issue_layer_path "$issue_id" 2>/dev/null || true)"

  write_issue_json "$issue_id" "$work/issue.json"
  [ -f "$STATE" ] && cp "$STATE" "$work/state.json"
  [ -n "$source" ] && [ -f "$source" ] && cp "$source" "$work/source-layer.md"

  {
    say "# Eco Alert Fix Evidence"
    say
    say "- Issue: \`$issue_id\`"
    say "- Severity: \`$severity\`"
    say "- Description: $desc"
    say "- State: \`$STATE\`"
    say "- Source layer: \`${source:-invalid or unavailable}\`"
    say "- Generated: $(date)"
    say
    say "## Live Checks"
    say
    if [ -n "$desc" ]; then
      classified="$(classify_issue "$issue_id" "$desc" 2>/dev/null || true)"
      say "- Classification: ${classified:-unavailable}"
    fi
    if curl -s -m 2 "$N8N_URL" >/dev/null 2>&1; then
      say "- n8n: online at $N8N_URL"
    else
      say "- n8n: offline/unreachable at $N8N_URL"
    fi
    if verify_memory_router_missing >/dev/null 2>&1; then
      say "- toolkit.memory.router: missing"
    else
      say "- toolkit.memory.router: importable"
    fi
    if guide_has_stale_banner; then
      say "- guide stale banner: present"
    elif guide_has_static_numbers; then
      say "- guide stale banner: absent; static count markers present"
    else
      say "- guide stale banner/static markers: no active marker found"
    fi
    say
    say "## Working Tree"
    say
    if git -C "$HOME/projects/eco-commander" status --short >/dev/null 2>&1; then
      git -C "$HOME/projects/eco-commander" status --short
    else
      say "(eco-commander git status unavailable)"
    fi
  } > "$work/evidence.md"
}

write_fix_prompt() {
  local issue_id="$1"
  local work="$2"
  local desc="$3"
  local severity="$4"
  local mode="$5"
  cat > "$work/prompt.md" <<EOF
You are Gemini 3.1 Pro acting as a senior fix evaluator for the Eco Commander alert workflow.

Mode: $mode
Issue ID: $issue_id
Severity: $severity
Description: $desc

Rules:
- Do not modify files. Produce an evidence-grounded plan only.
- Distinguish verified facts from assumptions.
- Decide whether this is safe/direct, bounded-with-validation, or complex/risky.
- If complex, propose sub-agent workstreams and acceptance criteria.
- Include pre-checks, exact commands, rollback notes, post-fix validation, and residual risk.
- Prefer existing local tools and repo patterns over inventing new tooling.
- Keep the recommendation actionable enough that Codex/Claude Code can implement it later.

Evidence files in this workspace:
- evidence.md
- issue.json
- state.json
- source-layer.md, when available

Return Markdown with these headings:
1. Verdict
2. Evidence Read
3. Complexity Tier
4. Proposed Fix
5. Validation Plan
6. Sub-Agent Plan
7. Apply/Do-Not-Apply Decision
EOF
}

gemini_plan_fix() {
  local issue_id="$1"
  local mode="${2:-plan}"
  local desc severity work
  desc="$(issue_desc_from_state "$issue_id")"
  [ -n "$desc" ] || desc="${3:-Manual fix planning request}"
  severity="$(issue_severity_from_state "$issue_id")"
  [ -n "$severity" ] || severity="unknown"
  work="$(make_fix_workspace "$issue_id")"

  collect_fix_evidence "$issue_id" "$work" "$desc" "$severity"
  write_fix_prompt "$issue_id" "$work" "$desc" "$severity" "$mode"

  say "Fix workspace: $work"
  if ! command -v gemini >/dev/null 2>&1; then
    say "Gemini CLI not found. Prompt is ready at: $work/prompt.md"
    return 0
  fi

  say "Assigning to Gemini model: $GEMINI_FIX_MODEL"
  (
    cd "$work"
    gemini -p "$(cat prompt.md)" -m "$GEMINI_FIX_MODEL" -y --allowed-mcp-server-names none \
      > gemini-plan.md 2> gemini-plan.log
  )
  say "Gemini plan: $work/gemini-plan.md"
}

gemini_orchestrate_fix() {
  local issue_id="$1"
  local desc severity work
  desc="$(issue_desc_from_state "$issue_id")"
  [ -n "$desc" ] || desc="${2:-Manual fix orchestration request}"
  severity="$(issue_severity_from_state "$issue_id")"
  [ -n "$severity" ] || severity="unknown"
  work="$(make_fix_workspace "$issue_id")"

  collect_fix_evidence "$issue_id" "$work" "$desc" "$severity"
  say "Fix workspace: $work"
  if ! command -v gemini >/dev/null 2>&1; then
    write_fix_prompt "$issue_id" "$work" "$desc" "$severity" "orchestrate"
    say "Gemini CLI not found. Prompt is ready at: $work/prompt.md"
    return 0
  fi

  local agents="$GEMINI_FIX_AGENTS"
  if ! [[ "$agents" =~ ^[0-9]+$ ]] || [ "$agents" -lt 2 ]; then
    agents=3
  fi
  [ "$agents" -gt 6 ] && agents=6

  say "Orchestrating $agents Gemini Pro evaluators via model: $GEMINI_FIX_MODEL"
  local role prompt_file
  for i in $(seq 1 "$agents"); do
    case "$i" in
      1) role="Evidence verifier: prove whether the alert is real and current." ;;
      2) role="Implementation strategist: propose the smallest durable fix." ;;
      3) role="Risk and rollback evaluator: find failure modes and validation gaps." ;;
      4) role="Test designer: specify automated and manual acceptance checks." ;;
      5) role="Operations reviewer: assess local services, secrets, and runtime side effects." ;;
      *) role="Challenger: argue against premature or unsafe fixes." ;;
    esac
    prompt_file="$work/agent-$i-prompt.md"
    cat > "$prompt_file" <<EOF
You are Gemini 3.1 Pro agent $i of $agents.

Role: $role
Issue ID: $issue_id
Severity: $severity
Description: $desc

Read the evidence in evidence.md, issue.json, state.json, and source-layer.md if present.
Do not modify files. Produce a focused Markdown evaluation for your role.
Include exact checks, risks, and a clear apply/do-not-apply recommendation.
EOF
    (
      cd "$work"
      gemini -p "$(cat "agent-$i-prompt.md")" -m "$GEMINI_FIX_MODEL" -y --allowed-mcp-server-names none \
        > "agent-$i.md" 2> "agent-$i.log"
    ) &
    sleep 0.2
  done
  wait

  {
    say "# Gemini Fix Orchestration Summary"
    say
    say "- Issue: \`$issue_id\`"
    say "- Model: \`$GEMINI_FIX_MODEL\`"
    say "- Agents: \`$agents\`"
    say
    for i in $(seq 1 "$agents"); do
      say "---"
      say
      say "## Agent $i"
      cat "$work/agent-$i.md" 2>/dev/null || say "(empty)"
      say
    done
  } > "$work/agent-bundle.md"

  cat > "$work/synthesis-prompt.md" <<EOF
You are Gemini 3.1 Pro synthesizing a multi-agent fix evaluation.

Issue ID: $issue_id
Severity: $severity
Description: $desc

Use agent-bundle.md and evidence.md. Do not modify files.
Return:
1. Final verdict
2. Whether to apply now, defer, or ask for human approval
3. Minimal implementation plan
4. Validation and rollback
5. Open questions
EOF
  (
    cd "$work"
    gemini -p "$(cat synthesis-prompt.md)" -m "$GEMINI_FIX_MODEL" -y --allowed-mcp-server-names none \
      > synthesis.md 2> synthesis.log
  )
  say "Gemini orchestration synthesis: $work/synthesis.md"
}

delegate_fix() {
  local issue_id="${1:-}"
  [ -n "$issue_id" ] || die "delegate-fix requires an issue id"
  local desc lower
  desc="$(issue_desc_from_state "$issue_id")"
  [ -n "$desc" ] || desc="Manual fix delegation request"
  lower="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *toolkit.memory.router*|*memory\ router\ import*|*memory\ submodules*|*not\ found*|*missing*)
      gemini_orchestrate_fix "$issue_id" "$desc"
      ;;
    *)
      gemini_plan_fix "$issue_id" "plan" "$desc"
      ;;
  esac
}

verify_memory_router_missing() {
  [ "${ECO_FORCE_MEMORY_ROUTER_MISSING:-0}" = "1" ] && return 0
  python3 - <<'PY'
import importlib.util
import sys

try:
    missing = importlib.util.find_spec("toolkit.memory.router") is None
except ModuleNotFoundError:
    missing = True

sys.exit(0 if missing else 1)
PY
}

verify_n8n_unreachable() {
  case "${ECO_N8N_STATUS:-}" in
    online) return 1 ;;
    offline) return 0 ;;
  esac
  ! curl -s -m 2 "$N8N_URL" >/dev/null 2>&1
}

n8n_expected() {
  [ "$ECO_N8N_EXPECTED" != "0" ]
}

guide_has_static_numbers() {
  [ -f "$GUIDE_FILE" ] || return 1
  grep -Eq '430 chunks|44 MCP servers|11 hooks|9 MCP servers|22 plugins|238 memory|52 MCP' "$GUIDE_FILE"
}

guide_has_stale_banner() {
  [ -f "$GUIDE_FILE" ] || return 1
  grep -q 'eco-alert-stale-counts-banner' "$GUIDE_FILE"
}

classify_issue() {
  local issue_id="$1"
  local desc="$2"
  local severity="${3:-unknown}"
  local lower status detail action_key action_label color icon category priority
  lower="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"
  category="repo-ops"
  status="triage"
  detail="snapshot finding has no live verifier yet"
  action_key="delegate-fix"
  action_label="Plan with Gemini Pro"

  case "$lower" in
    *n8n*)
      category="service"
      if ! n8n_expected; then
        status="resolved"
        detail="on-demand: n8n is not configured as an expected service"
        action_key=""
        action_label=""
      elif verify_n8n_unreachable; then
        status="active"
        detail="verified live: n8n is unreachable"
        action_key="fix-n8n"
        action_label="Start n8n"
      else
        status="resolved"
        detail="live check now passes: n8n responds"
        action_key=""
        action_label=""
      fi
      ;;
    *toolkit.memory.router*|*memory\ router\ import*|*memory\ submodules*)
      category="repo-ops"
      if verify_memory_router_missing; then
        status="active"
        detail="verified live: toolkit.memory.router is missing"
        action_key="delegate-fix"
        action_label="Plan with Gemini Pro"
      else
        status="resolved"
        detail="live check now passes: toolkit.memory.router imports"
        action_key=""
        action_label=""
      fi
      ;;
    *ai-ecosystem-guide.html*|*dashboard\ stale*|*dashboard\ freshness*)
      category="data-freshness"
      if guide_has_stale_banner; then
        status="resolved"
        detail="mitigated: stale-count banner is already present"
        action_key=""
        action_label=""
      elif guide_has_static_numbers; then
        status="active"
        detail="verified live: guide contains stale hand-written counts"
        action_key="fix-guide-stale"
        action_label="Add stale-count banner"
      else
        status="resolved"
        detail="live check no longer finds stale count markers"
        action_key=""
        action_label=""
      fi
      ;;
    *rc=124*|*timed*out*|*quota*)
      category="data-freshness"
      status="evidence"
      detail="evidence-backed snapshot failure; rerun to clear"
      action_key="fix-snapshot-timeout"
      action_label="Rerun snapshot"
      ;;
    *)
      category="repo-ops"
      ;;
  esac

  case "$status" in
    active) color="orange"; icon="⚠" ;;
    evidence) color="orange"; icon="◆" ;;
    resolved) color="gray"; icon="✓" ;;
    *) color="gray"; icon="◇" ;;
  esac

  case "$(printf '%s' "$severity" | tr '[:lower:]' '[:upper:]'):$status" in
    HIGH:active|CRITICAL:active) priority="P1" ;;
    *:active) priority="P1" ;;
    *:evidence) priority="P2" ;;
    HIGH:triage|CRITICAL:triage) priority="P2" ;;
    *:triage) priority="P3" ;;
    *) priority="P3" ;;
  esac

  : "$issue_id"
  say "$status|$detail|$action_key|$action_label|$color|$icon|$category|$priority"
}

widget_issues() {
  if [ ! -f "$STATE" ] || ! command -v jq >/dev/null 2>&1; then
    say $'META\t0\t0\t0\t0\t0\tunknown\tunknown'
    return 0
  fi

  local rows=()
  local total=0 active=0 evidence=0 triage=0 resolved=0
  local gen_at snap_id
  gen_at="$(jq -r '.generated_at // "unknown"' "$STATE" 2>/dev/null || printf 'unknown')"
  snap_id="$(jq -r '.snapshot_id // "unknown"' "$STATE" 2>/dev/null || printf 'unknown')"

  while IFS=$'\t' read -r severity raw_id safe_id desc; do
    [ -n "${raw_id:-}" ] || continue
    total=$((total + 1))

    local classified status detail action_key action_label color icon category priority action_issue_id
    classified="$(classify_issue "$raw_id" "$desc" "$severity")"
    IFS='|' read -r status detail action_key action_label color icon category priority <<< "$classified"
    case "$status" in
      active) active=$((active + 1)) ;;
      evidence) evidence=$((evidence + 1)) ;;
      resolved) resolved=$((resolved + 1)) ;;
      *) triage=$((triage + 1)) ;;
    esac

    action_issue_id=""
    if is_safe_action_arg "$raw_id"; then
      action_issue_id="$raw_id"
    fi
    rows+=("ISSUE"$'\t'"$severity"$'\t'"$safe_id"$'\t'"$desc"$'\t'"$status"$'\t'"$detail"$'\t'"$action_key"$'\t'"$action_label"$'\t'"$color"$'\t'"$icon"$'\t'"$category"$'\t'"$priority"$'\t'"$action_issue_id")
  done < <(
    jq -r '
      def eco_issues:
        ((.layers // {}) | [to_entries[] | select(.key != "Linf_wiring") | .value.issues[]?]) as $layer_issues |
        if ($layer_issues | length) > 0 then $layer_issues else (.layers.Linf_wiring.issues // []) end;
      eco_issues[]? |
      (.id // "unknown" | tostring) as $raw_id |
      ($raw_id | split("|")[0] | gsub("[^A-Za-z0-9_.:-]+"; "_") | gsub("_+"; "_") | gsub("^_|_$"; "") | if . == "" then "unknown" else . end) as $safe_id |
      [
        (.severity // "unknown" | tostring | ascii_upcase | gsub("[\t\r\n]+"; " ")),
        ($raw_id | gsub("[\t\r\n]+"; " ")),
        $safe_id,
        (.desc // .description // "no description" | tostring | gsub("[\t\r\n]+"; " "))
      ] | @tsv
    ' "$STATE" 2>/dev/null
  )

  say "META"$'\t'"$total"$'\t'"$active"$'\t'"$evidence"$'\t'"$triage"$'\t'"$resolved"$'\t'"$gen_at"$'\t'"$snap_id"
  local row
  for row in "${rows[@]}"; do
    say "$row"
  done
}

doctor() {
  say "=== Eco Alert Doctor ==="
  say "state: $STATE"
  say

  if [ ! -f "$STATE" ]; then
    say "No state.json is present. Run a snapshot first:"
    say "  $RECIPES_DIR/snapshot.sh"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    say "jq is not installed, so alert JSON cannot be audited."
    return 0
  fi

  local total=0 active=0 evidence=0 triage=0 resolved=0
  while IFS=$'\t' read -r severity issue_id desc; do
    [ -n "${issue_id:-}" ] || continue
    total=$((total + 1))
    local classified status detail action_key action_label color icon category priority
    classified="$(classify_issue "$issue_id" "$desc" "$severity")"
    IFS='|' read -r status detail action_key action_label color icon category priority <<< "$classified"
    case "$status" in
      active) active=$((active + 1)) ;;
      evidence) evidence=$((evidence + 1)) ;;
      resolved) resolved=$((resolved + 1)) ;;
      *) triage=$((triage + 1)) ;;
    esac

    say "[$status] [$severity] $issue_id"
    say "  $desc"
    local evidence_path
    evidence_path="$(issue_layer_path "$issue_id" 2>/dev/null || true)"
    say "  evidence: ${evidence_path:-invalid issue layer}"
    say "  category: ${category:-unknown} · priority: ${priority:-P3}"
    say "  check: $detail"
    if [ -n "${action_key:-}" ]; then
      case "$action_key" in
        delegate-fix|orchestrate-fix|fix-n8n|fix-snapshot-timeout)
          say "  fix: $0 $action_key $issue_id    # $action_label" ;;
        *)
          say "  fix: $0 $action_key    # $action_label" ;;
      esac
    fi
    say
  done < <(
    jq -r '
      def eco_issues:
        ((.layers // {}) | [to_entries[] | select(.key != "Linf_wiring") | .value.issues[]?]) as $layer_issues |
        if ($layer_issues | length) > 0 then $layer_issues else (.layers.Linf_wiring.issues // []) end;
      eco_issues[]? |
      [
        (.severity // "unknown" | tostring | ascii_upcase | gsub("[\t\r\n]+"; " ")),
        (.id // "unknown" | tostring | gsub("[\t\r\n]+"; " ")),
        (.desc // .description // "no description" | tostring | gsub("[\t\r\n]+"; " "))
      ] | @tsv
    ' "$STATE"
  )

  say "Summary: total=$total active=$active evidence=$evidence triage=$triage resolved=$resolved"
  say
  say "Use the widget submenus to open evidence or run the listed fix actions."
}

repo_health() {
  say "=== Eco Commander Repo Health ==="
  say "repo: $REPO_ROOT"
  say "runtime: $ECO"
  say

  local pass=0 warn=0 fail=0
  local health_log_dir="$RUN_LOG_DIR"
  report() {
    local level="$1"
    shift
    case "$level" in
      PASS) pass=$((pass + 1)) ;;
      WARN) warn=$((warn + 1)) ;;
      FAIL) fail=$((fail + 1)) ;;
    esac
    say "[$level] $*"
  }
  check_file() {
    local rel="$1"
    if [ -f "$REPO_ROOT/$rel" ]; then
      report PASS "$rel"
    else
      report FAIL "$rel missing"
    fi
  }
  check_exec() {
    local rel="$1"
    if [ -x "$REPO_ROOT/$rel" ]; then
      report PASS "$rel executable"
    elif [ -f "$REPO_ROOT/$rel" ]; then
      report WARN "$rel present but not executable"
    else
      report FAIL "$rel missing"
    fi
  }
  check_cmd() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
      report PASS "$cmd on PATH"
    else
      report WARN "$cmd not on PATH"
    fi
  }

  check_file README.md
  check_file CHANGELOG.md
  check_file docs/INDEX.md
  check_file docs/architecture.md
  check_file docs/getting-started/installation.md
  check_file docs/getting-started/usage.md
  check_file docs/getting-started/troubleshooting.md
  check_file docs/reference/data-model.md
  check_file docs/reference/configuration.md
  check_file docs/reference/environment-variables.md
  check_file docs/reference/glossary.md
  check_file docs/subsystems/scheduler.md
  check_file docs/subsystems/usage-monitor.md
  check_file docs/subsystems/usage-monitor-integration.md
  check_file docs/subsystems/alerts.md
  check_file docs/subsystems/widget-health.md
  check_file docs/subsystems/recipes.md
  check_file docs/subsystems/snapshots.md
  check_file docs/subsystems/launchd-best-practices.md
  check_file docs/operations/runbook.md
  check_file docs/operations/security-model.md
  check_file docs/contributing/CONTRIBUTING-DOCS.md
  check_file docs/contributing/developer-hygiene.md
  check_file docs/contributing/repository-governance.md
  check_file docs/contributing/testing.md
  check_exec src/bin/eco-commander.15s.sh
  check_exec src/bin/eco-alerts.sh
  check_exec src/recipes/snapshot.sh
  check_exec scripts/lint.sh
  if [ -d "$REPO_ROOT/tests/bats" ]; then
    report PASS "tests/bats present"
  else
    report FAIL "tests/bats missing"
  fi

  check_cmd jq
  check_cmd curl
  check_cmd python3
  check_cmd gemini
  check_cmd claude
  check_cmd ollama
  check_cmd shellcheck
  check_cmd bats

  if ! { mkdir -p "$health_log_dir" 2>/dev/null && touch "$health_log_dir/.repo-health-write-test" 2>/dev/null; }; then
    health_log_dir="${TMPDIR:-/tmp}/eco-alert-runs"
    mkdir -p "$health_log_dir"
    report WARN "$RUN_LOG_DIR not writable; using $health_log_dir for repo-health scratch logs"
  else
    rm -f "$health_log_dir/.repo-health-write-test" 2>/dev/null || true
  fi

  if [ -L "$ECO/bin/eco-commander.15s.sh" ] || [ -f "$ECO/bin/eco-commander.15s.sh" ]; then
    report PASS "$ECO/bin/eco-commander.15s.sh installed"
  else
    report WARN "$ECO/bin/eco-commander.15s.sh not installed"
  fi
  if [ -L "$ECO/bin/eco-alerts.sh" ] || [ -f "$ECO/bin/eco-alerts.sh" ]; then
    report PASS "$ECO/bin/eco-alerts.sh installed"
  else
    report WARN "$ECO/bin/eco-alerts.sh not installed"
  fi

  if [ -f "$STATE" ] && command -v jq >/dev/null 2>&1; then
    if jq empty "$STATE" >/dev/null 2>&1; then
      report PASS "current state.json parses"
    else
      report FAIL "current state.json is malformed"
    fi
  else
    report WARN "current state.json unavailable"
  fi

  if [ -x "$REPO_ROOT/src/bin/eco-commander.15s.sh" ]; then
    if ECO_ALERT_OPEN_TERMINAL=0 bash "$REPO_ROOT/src/bin/eco-commander.15s.sh" --cli > "$health_log_dir/repo-health-widget.out" 2>&1; then
      report PASS "widget CLI renders"
    else
      report FAIL "widget CLI failed; see $health_log_dir/repo-health-widget.out"
    fi
  fi

  if command -v shellcheck >/dev/null 2>&1 && [ -x "$REPO_ROOT/scripts/lint.sh" ]; then
    if (cd "$REPO_ROOT" && bash scripts/lint.sh >/tmp/eco-repo-health-lint.out 2>&1); then
      report PASS "scripts/lint.sh"
    else
      report FAIL "scripts/lint.sh failed; see /tmp/eco-repo-health-lint.out"
    fi
  else
    report WARN "shellcheck lint skipped"
  fi

  say
  say "Summary: pass=$pass warn=$warn fail=$fail"
  [ "$fail" -eq 0 ]
}

debug_ollama() {
  say "=== Ollama Debug ==="
  say "PATH: $PATH"
  local ollama_bin
  ollama_bin="$(command -v ollama 2>/dev/null || true)"
  if [ -z "$ollama_bin" ]; then
    say "ollama: not found on PATH"
    return 0
  fi

  say "ollama: $ollama_bin"
  if curl -s -m 2 http://127.0.0.1:11434/ >/dev/null 2>&1; then
    say "daemon: reachable at http://127.0.0.1:11434/"
  else
    say "daemon: unreachable at http://127.0.0.1:11434/"
  fi
  say
  say "ollama ps:"
  "$ollama_bin" ps 2>&1 || true
  say
  say "ollama list:"
  "$ollama_bin" list 2>&1 || true
}

open_source() {
  local issue_id="${1:-}"
  [ -n "$issue_id" ] || die "open-source requires an issue id"
  local path
  path="$(issue_layer_path "$issue_id")" || die "invalid issue layer in issue id"
  [ -e "$path" ] || die "source layer not found: $path"
  open_path "$path"
}

prewarm_ollama() {
  local model="${1:-}"
  is_safe_ollama_model "$model" || die "invalid ollama model name"
  local ollama_bin
  ollama_bin="$(command -v ollama 2>/dev/null || true)"
  [ -n "$ollama_bin" ] || die "ollama is not installed or not on PATH"
  printf '\n' | "$ollama_bin" run "$model" >/dev/null 2>&1
}

run_recipe() {
  local recipe_name="${1:-}"
  shift || true
  is_safe_recipe_id "$recipe_name" || die "invalid recipe name"
  local recipe="$RECIPES_DIR/${recipe_name}.sh"
  [ -f "$recipe" ] || die "recipe not found: $recipe_name"
  [ -x "$recipe" ] || die "recipe is not executable: $recipe_name"
  "$recipe" "$@"
}

fix_snapshot_timeout() {
  local snapshot="$RECIPES_DIR/snapshot.sh"
  [ -x "$snapshot" ] || die "snapshot recipe missing or not executable: $snapshot"
  say "Rerunning ecosystem snapshot to replace timeout/quota findings..."
  "$snapshot"
}

pick_n8n_compose() {
  if [ -n "${ECO_N8N_COMPOSE:-}" ]; then
    [ -f "$ECO_N8N_COMPOSE" ] || die "ECO_N8N_COMPOSE does not exist: $ECO_N8N_COMPOSE"
    printf '%s\n' "$ECO_N8N_COMPOSE"
    return 0
  fi

  local preferred="${ECO_N8N_COMPOSE_DEFAULT:-$HOME/my-project/n8n/docker-compose.yml}"
  if [ -f "$preferred" ]; then
    printf '%s\n' "$preferred"
    return 0
  fi

  die "no n8n compose path configured. Set ECO_N8N_COMPOSE or use the preferred path: $preferred"
}

fix_n8n() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"
  local compose
  compose="$(pick_n8n_compose)"
  local dir
  dir="$(dirname "$compose")"
  say "Starting n8n via docker compose:"
  say "  compose: $compose"
  (
    cd "$dir"
    docker compose -f "$compose" up -d n8n
  )
  say
  if curl -s -m 5 "$N8N_URL" >/dev/null 2>&1; then
    say "n8n is responding at $N8N_URL"
  else
    say "n8n was started, but $N8N_URL is not responding yet. Check docker compose logs:"
    say "  cd \"$dir\""
    say "  docker compose -f \"$compose\" logs -f n8n"
  fi
}

fix_dashboard_refresh() {
  local recipe="$RECIPES_DIR/dashboard-refresh.sh"
  [ -x "$recipe" ] || die "dashboard-refresh recipe missing or not executable: $recipe"
  say "Refreshing dashboard metrics from live ecosystem state..."
  "$recipe"
}

fix_memory_router() {
  if [ "${ECO_ALLOW_DIRECT_COMPLEX_FIX:-0}" != "1" ]; then
    say "Direct memory-router patching is disabled by default because this is a cross-project code fix."
    say "Routing to Gemini Pro evaluation instead."
    delegate_fix "GG-wiring-behavior:26"
    say
    say "To force the legacy direct adapter patch, rerun with ECO_ALLOW_DIRECT_COMPLEX_FIX=1."
    return 0
  fi

  [ -d "$TOOLKIT_MEMORY_DIR" ] || die "toolkit memory package not found: $TOOLKIT_MEMORY_DIR"

  if [ -f "$MEMORY_ROUTER_MODULE" ]; then
    say "Existing module found: $MEMORY_ROUTER_MODULE"
  else
    say "Creating compatibility adapter: $MEMORY_ROUTER_MODULE"
    cat > "$MEMORY_ROUTER_MODULE" <<'PY'
"""Compatibility facade for memory routing helpers.

The live Claude hook still lives at ``~/.claude/hooks/memory_router.py``.
This module makes the reusable toolkit memory primitives importable from
``toolkit.memory.router`` for scripts that expect a router namespace.
"""

from toolkit.memory.chunking import chunk_directory, chunk_markdown, chunk_text
from toolkit.memory.embeddings import batch_embed, get_embedding, is_available
from toolkit.memory.search import cosine_similarity, search_index, semantic_search
from toolkit.memory.spaces import (
    build_all_indices,
    build_space_index,
    load_config,
    resolve_spaces,
)
from toolkit.memory.store import FlatStore, VectorStore, build_index

__all__ = [
    "batch_embed",
    "build_all_indices",
    "build_index",
    "build_space_index",
    "chunk_directory",
    "chunk_markdown",
    "chunk_text",
    "cosine_similarity",
    "FlatStore",
    "get_embedding",
    "is_available",
    "load_config",
    "resolve_spaces",
    "search_index",
    "semantic_search",
    "VectorStore",
]
PY
  fi

  say "Verifying import..."
  python3 - <<'PY'
import toolkit.memory.router as router

print("toolkit.memory.router OK")
print("exports:", ", ".join(router.__all__[:5]) + " ...")
PY
}

fix_guide_stale() {
  [ -f "$GUIDE_FILE" ] || die "guide file not found: $GUIDE_FILE"
  if grep -q 'eco-alert-stale-counts-banner' "$GUIDE_FILE"; then
    say "Guide already has the stale-count banner: $GUIDE_FILE"
    return 0
  fi

  local backup
  backup="$GUIDE_FILE.bak.$(date +%Y%m%d%H%M%S)"
  cp "$GUIDE_FILE" "$backup"
  say "Backup written: $backup"

  python3 - "$GUIDE_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
banner = """
<div id="eco-alert-stale-counts-banner" style="margin:72px auto 0;max-width:1100px;padding:14px 18px;border:1px solid #f59e0b;border-radius:10px;background:rgba(245,158,11,0.12);color:#fef3c7;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',system-ui,sans-serif;">
  <strong>Snapshot note:</strong> numeric ecosystem counts in this guide are hand-written point-in-time values. Use Eco Commander state.json for live counts.
</div>
"""
if "<body>" in text:
    text = text.replace("<body>", "<body>" + banner, 1)
else:
    text = text.replace("</nav>", "</nav>" + banner, 1)
path.write_text(text, encoding="utf-8")
PY
  say "Inserted stale-count banner into: $GUIDE_FILE"
}

rebuild_memory_indexes() {
  [ -f "$MEMORY_HOOK" ] || die "memory router hook not found: $MEMORY_HOOK"
  say "Rebuilding memory indexes via $MEMORY_HOOK --build-all"
  python3 "$MEMORY_HOOK" --build-all
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  doctor                    Verify current snapshot alerts and list fixes
  widget-issues             Emit normalized alert rows for the SwiftBar widget
  open-source <issue-id>    Open the layer markdown behind an alert
  open-state                Open current state.json
  open-dashboard            Open current dashboard.html
  open-guide                Open ~/ai-ecosystem-guide.html
  open-run-logs             Open ~/.eco/alert-runs
  prewarm-ollama <model>    Safely pre-warm a local Ollama model
  run-recipe <name>         Safely run a recipe from ~/.eco/recipes by name
  run-logged <command>      Run an alert command in the background with logs
  repo-health               Audit widget repo/docs/tools/runtime wiring
  debug-ollama              Print Ollama path, daemon, ps, and list evidence
  delegate-fix <issue-id>   Route a complex fix to Gemini 3.1 Pro planning
  orchestrate-fix <issue-id> Run a multi-agent Gemini Pro fix evaluation
  fix-snapshot-timeout      Rerun snapshot.sh
  fix-n8n                   Start the discovered n8n compose service
  fix-dashboard-refresh     Refresh dashboard metric placeholders
  fix-memory-router         Legacy direct adapter patch (requires explicit use)
  fix-guide-stale           Add a stale-count banner to the HTML guide
  rebuild-memory-indexes    Run memory_router.py --build-all
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-doctor}"
  case "$cmd" in
    doctor) doctor ;;
    widget-issues) widget_issues ;;
    repo-health) repo_health ;;
    debug-ollama) debug_ollama ;;
    run-logged) shift; run_logged "${1:-}" "${@:2}" ;;
    delegate-fix) shift; delegate_fix "${1:-}" ;;
    orchestrate-fix) shift; gemini_orchestrate_fix "${1:-}" ;;
    open-source) shift; open_source "${1:-}" ;;
    open-state) open_path "$STATE" ;;
    open-dashboard) open_path "$CURRENT/dashboard.html" ;;
    open-guide) open_path "$GUIDE_FILE" ;;
    open-run-logs) mkdir -p "$RUN_LOG_DIR"; open_path "$RUN_LOG_DIR" ;;
    prewarm-ollama) shift; prewarm_ollama "${1:-}" ;;
    run-recipe) shift; run_recipe "${1:-}" "${@:2}" ;;
    fix-snapshot-timeout) fix_snapshot_timeout ;;
    fix-n8n) fix_n8n ;;
    fix-dashboard-refresh) fix_dashboard_refresh ;;
    fix-memory-router) fix_memory_router ;;
    fix-guide-stale) fix_guide_stale ;;
    rebuild-memory-indexes) rebuild_memory_indexes ;;
    help|-h|--help) usage ;;
    *) usage; exit 2 ;;
  esac
fi
