#!/usr/bin/env bash
# DESC: Dispatch N parallel Gemini agents on a task; synthesize results
# INPUTS: <task description>, optional N (default 5)
# OUTPUT: ~/Documents/research/_swarm/<ts>/ with N agent outputs + summary
# USES: gem-smart or Gemini CLI for parallel agent runs
# HUMAN: you define the task; agents execute in parallel; you review
set -eu

TASK="${1:-}"
N="${2:-5}"
if [ -z "$TASK" ]; then
  echo -n "Task for swarm: "
  read -r TASK
fi
[ -z "$TASK" ] && { echo "No task."; exit 1; }

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "N must be 2-15. Got $N."
  exit 1
fi

if [ "$N" -lt 2 ] || [ "$N" -gt 15 ]; then
  echo "N must be 2-15. Got $N."
  exit 1
fi

TS=$(date +%Y-%m-%d_%H-%M-%S)
WORK="$HOME/Documents/research/_swarm/$TS"
mkdir -p "$WORK"

echo "=== Swarm: $N agents ==="
echo "Task: $TASK"
echo "Workspace: $WORK"
echo

# Legacy note: older low-RAM builds unloaded Ollama before large swarms.
# That ritual is now disabled; this Mac is dedicated to AI work and can keep
# local models resident while agents run.
if [ "$N" -ge 10 ]; then
  echo "N>=10 — keeping local models resident; no pre-swarm unload."
fi

print_failed_log() {
  local label="$1"
  local rc="$2"
  local log="$3"

  echo "--- ${label} log (rc=$rc) ---" >&2
  if [ -s "$log" ]; then
    tail -20 "$log" >&2
  else
    echo "(no stderr captured)" >&2
  fi
}

# Resolve the Gemini backend once: prefer gem-smart, else the plain Gemini CLI.
GEM_SMART="${ECO_GEM_SMART_BIN:-$HOME/bin/gem-smart}"
if [ -x "$GEM_SMART" ] || command -v "$GEM_SMART" >/dev/null 2>&1; then
  GEM_BACKEND="gem-smart"
elif command -v gemini >/dev/null 2>&1; then
  GEM_BACKEND="gemini"
else
  echo "gem-smart not found, and no 'gemini' CLI on PATH." >&2
  echo "Install the Gemini CLI (https://github.com/google-gemini/gemini-cli) or set ECO_GEM_SMART_BIN." >&2
  exit 1
fi

PROMPT_BASE="You are agent #{AGENT_ID} of $N working in parallel on the same task.

Task: $TASK

Your angle: agent #{AGENT_ID}. Each agent should approach this from a DIFFERENT angle so the group's synthesis is richer than any single pass. Pick an angle no other numbered agent would naturally take.

Produce a focused markdown section. Be specific and cite sources where relevant. 300–500 words. Do not include other agents' sections."

pids=()
agents=()
for i in $(seq 1 "$N"); do
  PROMPT=${PROMPT_BASE//\{AGENT_ID\}/$i}
  (
    cd "$HOME" || exit 1
    if [ "$GEM_BACKEND" = "gem-smart" ]; then
      "$GEM_SMART" "${ECO_GEM_MODEL:-3f}" -p "$PROMPT" -y --allowed-mcp-server-names none \
        > "$WORK/agent-$i.md" 2> "$WORK/agent-$i.log"
    else
      gemini -p "$PROMPT" > "$WORK/agent-$i.md" 2> "$WORK/agent-$i.log"
    fi
    if [ ! -s "$WORK/agent-$i.md" ]; then
      echo "ERROR: agent-$i produced no output" >> "$WORK/agent-$i.log"
      exit 1
    fi
    echo "  agent-$i done"
  ) &
  pids+=("$!")
  agents+=("$i")
  sleep 0.2
done

failures=0
failed_agents=()
for idx in "${!pids[@]}"; do
  pid="${pids[$idx]}"
  agent="${agents[$idx]}"
  if wait "$pid"; then
    :
  else
    rc=$?
    failures=$((failures + 1))
    failed_agents+=("${agent}:${rc}")
  fi
done

if [ "$failures" -gt 0 ]; then
  echo >&2
  echo "Swarm failed: $failures of $N agents failed." >&2
  for failed in "${failed_agents[@]}"; do
    agent="${failed%%:*}"
    rc="${failed##*:}"
    print_failed_log "agent-$agent" "$rc" "$WORK/agent-$agent.log"
  done
  echo "Workspace: $WORK" >&2
  exit 1
fi

echo
echo "=== All $N agents complete ==="

# Quick synthesis
SUMMARY="$WORK/SUMMARY.md"
{
  echo "# Swarm Summary"
  echo "**Task:** $TASK"
  echo "**Agents:** $N"
  echo "**Timestamp:** $TS"
  echo
  for i in $(seq 1 "$N"); do
    echo "---"
    echo "## Agent $i"
    cat "$WORK/agent-$i.md" 2>/dev/null || echo "(empty)"
    echo
  done
} > "$SUMMARY"

wc -l "$WORK"/*.md
echo
echo "Summary: $SUMMARY"
open "$SUMMARY" 2>/dev/null || true
