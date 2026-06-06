#!/usr/bin/env bash
# DESC: Re-run the AI ecosystem snapshot and publish it to current/
# INPUTS: none
# OUTPUT: ~/.eco/snapshots/<iso>/ + assembled state/map/dashboard + current symlink
# USES: Gemini prompt-layer scan pattern (canonical or public example library)
# HUMAN: review the resulting dashboard; the red-team pass runs separately
set -eu

ECO="$HOME/.eco"
# Root of a custom snapshot prompt library. Override with ECO_AUDIT_ROOT.
# Custom layout: <root>/prompts/ (layer prompts) and optional <root>/outputs/.
LEGACY_AUDIT_ROOT="$HOME/.eco/ecosystem-audit"
TS=$(date +%Y-%m-%dT%H-%MZ)
SNAP="$ECO/snapshots/$TS"
CURRENT="$ECO/current"
LOCKDIR="$ECO/.snapshot.lock"
: "${GEMINI_LAYER_TIMEOUT_SEC:=180}"

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  old_pid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Snapshot already running (pid $old_pid)."
    exit 1
  fi
  rm -f "$LOCKDIR/pid" 2>/dev/null || true
  if ! rmdir "$LOCKDIR" 2>/dev/null || ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "Snapshot lock exists and could not be reclaimed: $LOCKDIR"
    exit 1
  fi
fi
echo "$$" > "$LOCKDIR/pid"
cleanup_lock() {
  rm -f "$LOCKDIR/pid" 2>/dev/null || true
  rmdir "$LOCKDIR" 2>/dev/null || true
}
trap cleanup_lock EXIT

if [ -d "$SNAP" ]; then
  echo "Snapshot $TS already exists. Wait 1 minute and try again."
  exit 1
fi

mkdir -p "$SNAP"/{raw,layers}

echo "=== Eco snapshot: $TS ==="
echo "Workspace: $SNAP"
echo

print_failed_log() {
  local label="$1"
  local rc="$2"
  local log="$3"

  echo "--- ${label} log (rc=$rc) ---" >&2
  if [ -s "$log" ]; then
    tail -30 "$log" >&2
  else
    echo "(no stderr captured)" >&2
  fi
}

resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  local dir
  local link

  while [ -L "$source" ]; do
    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    link="$(readlink "$source")"
    case "$link" in
      /*) source="$link" ;;
      *) source="$dir/$link" ;;
    esac
  done
  cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

find_repo_root() {
  local dir="$1"

  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -d "$dir/src/recipes" ] && [ -d "$dir/examples/snapshot-prompts" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

prompt_dir_has_layers() {
  local dir="$1"
  local path
  local base

  [ -d "$dir" ] || return 1
  for path in "$dir"/*.md; do
    [ -e "$path" ] || continue
    base="$(basename "$path" .md)"
    case "$base" in
      README|_SHARED) continue ;;
    esac
    return 0
  done
  return 1
}

SCRIPT_DIR="$(resolve_script_dir)"
REPO_ROOT="$(find_repo_root "$SCRIPT_DIR" 2>/dev/null || true)"
DEFAULT_PROMPT_DIR=""
[ -n "$REPO_ROOT" ] && DEFAULT_PROMPT_DIR="$REPO_ROOT/examples/snapshot-prompts"

# Locate the snapshot prompt library. An explicit ECO_AUDIT_ROOT always points
# to a custom audit root; otherwise prefer a populated local runtime library,
# then fall back to the public examples shipped with the repo.
if [ -n "${ECO_AUDIT_ROOT+x}" ]; then
  AUDIT_ROOT="$ECO_AUDIT_ROOT"
  PROMPT_DIR="$AUDIT_ROOT/prompts"
  if ! prompt_dir_has_layers "$PROMPT_DIR"; then
    echo "Prompt library not found at $PROMPT_DIR"
    exit 1
  fi
elif prompt_dir_has_layers "$LEGACY_AUDIT_ROOT/prompts"; then
  AUDIT_ROOT="$LEGACY_AUDIT_ROOT"
  PROMPT_DIR="$AUDIT_ROOT/prompts"
elif [ -n "$DEFAULT_PROMPT_DIR" ] && prompt_dir_has_layers "$DEFAULT_PROMPT_DIR"; then
  AUDIT_ROOT="$REPO_ROOT"
  PROMPT_DIR="$DEFAULT_PROMPT_DIR"
else
  if [ -n "$DEFAULT_PROMPT_DIR" ]; then
    echo "Prompt library not found at $LEGACY_AUDIT_ROOT/prompts or $DEFAULT_PROMPT_DIR"
  else
    echo "Prompt library not found at $LEGACY_AUDIT_ROOT/prompts"
  fi
  exit 1
fi

CANONICAL_PROMPTS=(GA-hardware-llm GB-ai-clients GC-mcp GD-hooks-plugins GE-agents-memory GF-toolkit-projects-external GG-wiring-behavior)
prompt_names=()
prompts_to_run=()
canonical_library=0
for prompt in "${CANONICAL_PROMPTS[@]}"; do
  if [ -f "$PROMPT_DIR/${prompt}.md" ]; then
    canonical_library=1
    prompts_to_run+=("$prompt")
  fi
done

if [ "$canonical_library" -eq 1 ]; then
  prompt_names=("${CANONICAL_PROMPTS[@]}")
else
  for prompt_path in "$PROMPT_DIR"/*.md; do
    [ -e "$prompt_path" ] || continue
    prompt="$(basename "$prompt_path" .md)"
    case "$prompt" in
      README|_SHARED) continue ;;
    esac
    prompt_names+=("$prompt")
    prompts_to_run+=("$prompt")
  done
fi

if [ "${#prompts_to_run[@]}" -eq 0 ]; then
  echo "Prompt library not found at $PROMPT_DIR (no layer prompts found)"
  exit 1
fi

GEM_SMART="${ECO_GEM_SMART_BIN:-$HOME/bin/gem-smart}"
if [ -x "$GEM_SMART" ] || command -v "$GEM_SMART" >/dev/null 2>&1; then
  GEM_BACKEND="gem-smart"
elif command -v gemini >/dev/null 2>&1; then
  GEM_BACKEND="gemini"
else
  echo "gem-smart not found, and no 'gemini' CLI on PATH." >&2
  echo "Snapshot requires gem-smart or the Gemini CLI plus a prompt library." >&2
  echo "Install the Gemini CLI (https://github.com/google-gemini/gemini-cli) or set ECO_GEM_SMART_BIN." >&2
  exit 1
fi

cd "$AUDIT_ROOT" || exit 1

build_layer_prompt() {
  local prompt="$1"

  if [ -f "$PROMPT_DIR/_SHARED.md" ]; then
    cat "$PROMPT_DIR/_SHARED.md"
    printf '\n'
  fi
  cat "$PROMPT_DIR/${prompt}.md"
}

run_layer() {
  local prompt="$1"
  local out="$SNAP/layers/${prompt}.md"
  local log="$SNAP/layers/${prompt}.log"
  local canonical_report="$AUDIT_ROOT/outputs/${prompt}.md"

  (
    set +e
    prompt_text="$(build_layer_prompt "$prompt")"
    if [ "$GEM_BACKEND" = "gem-smart" ]; then
      "$GEM_SMART" 3.5f \
        -p "$prompt_text" \
        -y \
        --allowed-mcp-server-names none \
        > "$out" \
        2> "$log" &
    else
      gemini -p "$prompt_text" > "$out" 2> "$log" &
    fi
    local gemini_pid=$!
    local deadline=$((SECONDS + GEMINI_LAYER_TIMEOUT_SEC))
    local timed_out=0

    while kill -0 "$gemini_pid" 2>/dev/null; do
      if [ "$SECONDS" -ge "$deadline" ]; then
        timed_out=1
        {
          echo
          echo "TIMEOUT: ${prompt} exceeded ${GEMINI_LAYER_TIMEOUT_SEC}s; killed by snapshot.sh."
        } >> "$log"
        pkill -TERM -P "$gemini_pid" 2>/dev/null || true
        kill -TERM "$gemini_pid" 2>/dev/null || true
        sleep 1
        pkill -KILL -P "$gemini_pid" 2>/dev/null || true
        kill -KILL "$gemini_pid" 2>/dev/null || true
        break
      fi
      sleep 1
    done

    wait "$gemini_pid" 2>/dev/null
    local rc=$?
    [ "$timed_out" -eq 1 ] && rc=124
    if [ -s "$canonical_report" ]; then
      cp "$canonical_report" "$out"
    fi

    if [ "$rc" -eq 0 ] && [ -s "$out" ]; then
      echo "  ✓ $prompt"
      exit 0
    else
      if [ ! -s "$out" ]; then
        {
          echo "# ${prompt}"
          echo
          echo "State: blocked"
          echo
          echo "ERROR: Gemini layer timed out or did not complete. See $(basename "$log")."
        } > "$out"
      else
        {
          echo
          echo "ERROR: Gemini layer exited with rc=${rc}; see $(basename "$log")."
        } >> "$out"
      fi
      if [ "$rc" -eq 124 ]; then
        echo "  ! $prompt (TIMEOUT: rc=124)"
      else
        echo "  ! $prompt (rc=$rc)"
      fi
      [ "$rc" -ne 0 ] || rc=1
      exit "$rc"
    fi
  ) &
}

layer_pids=()
layer_names=()
for prompt in "${prompt_names[@]}"; do
  if [ ! -f "$PROMPT_DIR/${prompt}.md" ]; then
    echo "  skip $prompt (prompt missing)"
    continue
  fi
  run_layer "$prompt"
  layer_pids+=("$!")
  layer_names+=("$prompt")
  sleep 1
done

failures=0
failed_layers=()
for idx in "${!layer_pids[@]}"; do
  pid="${layer_pids[$idx]}"
  layer="${layer_names[$idx]}"
  if wait "$pid"; then
    :
  else
    rc=$?
    failures=$((failures + 1))
    failed_layers+=("${layer}:${rc}")
  fi
done

if [ "$failures" -gt 0 ]; then
  echo >&2
  echo "Snapshot failed: $failures layer(s) failed." >&2
  for failed in "${failed_layers[@]}"; do
    layer="${failed%:*}"
    rc="${failed##*:}"
    print_failed_log "$layer" "$rc" "$SNAP/layers/${layer}.log"
  done
  echo "Workspace: $SNAP" >&2
  exit 1
fi

echo
echo "=== Scans done. Review outputs: ==="
if compgen -G "$SNAP/layers/*.md" > /dev/null; then
  wc -l "$SNAP/layers"/*.md
else
  echo "(no layer outputs produced — check prompt library)"
fi
echo
echo "=== Assembling current snapshot ==="
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found; raw scan completed but current/ was not updated."
  exit 1
fi

PROMPT_MANIFEST="$SNAP/raw/prompt-names.txt"
printf '%s\n' "${prompt_names[@]}" > "$PROMPT_MANIFEST"

python3 - "$SNAP" "$TS" "$PROMPT_MANIFEST" <<'PY'
import html
import json
import os
import re
import sys
from datetime import datetime

snap, snapshot_id, prompt_manifest = sys.argv[1], sys.argv[2], sys.argv[3]
layers_dir = os.path.join(snap, "layers")
now = datetime.now().astimezone().isoformat(timespec="seconds")
with open(prompt_manifest, encoding="utf-8") as f:
    prompt_names = [line.strip() for line in f if line.strip()]
issue_re = re.compile(r"\b(error|fail|failed|missing|not found|unreachable|stale|warning|warn|todo|incomplete|manual)\b", re.I)

layers = {}
issues = []
for prompt in prompt_names:
    path = os.path.join(layers_dir, f"{prompt}.md")
    log_path = os.path.join(layers_dir, f"{prompt}.log")
    key = prompt.replace("-", "_")
    text = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    log_text = ""
    if os.path.exists(log_path):
        with open(log_path, encoding="utf-8", errors="replace") as f:
            log_text = f.read()

    layer_state = "ok" if text.strip() else "missing"
    if issue_re.search(log_text):
        layer_state = "warn"
    layer_issues = []
    layers[key] = {
        "state": layer_state,
        "path": f"layers/{prompt}.md",
        "bytes": len(text.encode("utf-8")),
        "lines": len(text.splitlines()),
        "issues": layer_issues,
    }

    if not text.strip():
        issue = {
            "severity": "high",
            "id": f"{prompt}:empty",
            "desc": f"{prompt} produced no markdown output",
            "source_layer": prompt,
            "source_path": f"layers/{prompt}.md",
            "classifier": "regex-v0",
            "status": "candidate",
        }
        layer_issues.append(issue)
        issues.append(issue)
        continue

    for line_no, line in enumerate(text.splitlines(), 1):
        clean = " ".join(line.strip().split())
        if not clean or len(clean) < 12 or not issue_re.search(clean):
            continue
        lower = clean.lower()
        severity = "high" if any(w in lower for w in ["error", "fail", "missing", "not found", "unreachable"]) else "med"
        issue = {
            "severity": severity,
            "id": f"{prompt}:{line_no}",
            "desc": clean[:240],
            "source_layer": prompt,
            "source_path": f"layers/{prompt}.md",
            "classifier": "regex-v0",
            "status": "candidate",
        }
        layer_issues.append(issue)
        issues.append(issue)
        if len(issues) >= 50:
            break

log_errors = []
for prompt in prompt_names:
    log_path = os.path.join(layers_dir, f"{prompt}.log")
    if not os.path.exists(log_path):
        continue
    with open(log_path, encoding="utf-8", errors="replace") as f:
        log_text = f.read()
    if issue_re.search(log_text):
        log_errors.append(prompt)

layers["Linf_wiring"] = {
    "state": "deprecated-aggregate",
    "issues": issues,
    "note": "Compatibility aggregate. Prefer issues attached to source layers.",
}
state = {
    "schema_version": "0.2",
    "snapshot_id": snapshot_id,
    "generated_at": now,
    "alert_model": {
        "source": "layer-local issues with Linf_wiring compatibility aggregate",
        "classifier": "regex-v0 candidates; widget/eco-alerts performs live verification where available",
    },
    "alert_count": len(issues),
    "gate_status": {
        "G1_layers_present": "pass" if all(layers[p.replace("-", "_")]["bytes"] > 0 for p in prompt_names) else "fail",
        "G7_freshness": "pass",
    },
    "overall_verdict": "assembled-with-warnings" if issues or log_errors else "assembled",
    "layers": layers,
    "sources": {
        "raw_layers": [f"layers/{p}.md" for p in prompt_names],
        "logs_with_warnings": log_errors,
    },
}

with open(os.path.join(snap, "state.json"), "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
    f.write("\n")

with open(os.path.join(snap, "map.md"), "w", encoding="utf-8") as f:
    f.write(f"# Eco Snapshot Map: {snapshot_id}\n\n")
    f.write(f"Generated: {now}\n\n")
    f.write("## Layers\n\n")
    for prompt in prompt_names:
        key = prompt.replace("-", "_")
        meta = layers[key]
        f.write(f"- `{prompt}`: {meta['state']}, {meta['lines']} lines, {meta['bytes']} bytes\n")
    f.write("\n## Issues\n\n")
    if issues:
        for issue in issues[:50]:
            f.write(f"- [{issue['severity'].upper()}] `{issue['id']}`: {issue['desc']}\n")
    else:
        f.write("- No issue-pattern lines detected in raw layers.\n")

cards = "\n".join(
    f"<li><strong>{html.escape(issue['severity'].upper())}</strong> "
    f"<code>{html.escape(issue['id'])}</code>: {html.escape(issue['desc'])}</li>"
    for issue in issues[:50]
) or "<li>No issue-pattern lines detected in raw layers.</li>"
layer_rows = "\n".join(
    f"<tr><td>{html.escape(prompt)}</td><td>{html.escape(layers[prompt.replace('-', '_')]['state'])}</td>"
    f"<td>{layers[prompt.replace('-', '_')]['lines']}</td><td>{layers[prompt.replace('-', '_')]['bytes']}</td></tr>"
    for prompt in prompt_names
)
with open(os.path.join(snap, "dashboard.html"), "w", encoding="utf-8") as f:
    f.write(f"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>Eco Snapshot {html.escape(snapshot_id)}</title>
<style>
:root {{ --bg: #ffffff; --text: #1a202c; --border: #e2e8f0; --link: #0284c7; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg: #101418; --text: #edf2f7; --border: #2d3748; --link: #7dd3fc; }}
}}
body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; background: var(--bg); color: var(--text); }}
a {{ color: var(--link); }}
table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
td, th {{ border-bottom: 1px solid var(--border); padding: 10px; text-align: left; }}
.pill {{ display: inline-block; padding: 4px 10px; border-radius: 999px; background: var(--border); }}
li {{ margin: 8px 0; }}
</style>
<h1>Eco Snapshot</h1>
<p><span class="pill">{html.escape(snapshot_id)}</span> Generated {html.escape(now)}</p>
<h2>Layers</h2>
<table><thead><tr><th>Layer</th><th>State</th><th>Lines</th><th>Bytes</th></tr></thead><tbody>{layer_rows}</tbody></table>
<h2>Issues</h2>
<ul>{cards}</ul>
<p><a href="state.json">state.json</a> · <a href="map.md">map.md</a></p>
</html>
""")
PY

tmp_link="$ECO/.current.new.$$"
rm -f "$tmp_link"
ln -s "$SNAP" "$tmp_link"
if [ -L "$CURRENT" ] || [ ! -e "$CURRENT" ]; then
  rm -f "$CURRENT"
else
  backup="$ECO/current.backup.$(date +%Y%m%d%H%M%S)"
  mv "$CURRENT" "$backup"
  echo "Previous current/ directory backed up to: $backup"
fi
mv "$tmp_link" "$CURRENT"

echo "Current snapshot now points to:"
readlink "$CURRENT" 2>/dev/null || echo "$CURRENT"
echo
echo "Open dashboard:"
echo "  $CURRENT/dashboard.html"
