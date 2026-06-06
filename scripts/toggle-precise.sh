#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq filters legitimately use single quotes with --arg \$vars
# Toggle per-tool server-truth (precise tracking) in ~/.eco/config.json.
#
# Usage: toggle-precise.sh <claude|codex|gemini>
#
# State machine (per A2 P0.2 + R3 §3):
#   JSONL ──[click + ECO_ALLOW_LIVE_CREDENTIAL_PROBE=1]──▶ credential probe ──[granted]──▶ server_truth ON
#                                     ──[denied/missing]──▶ JSONL (no-op)
#   server_truth ──[click]──▶ JSONL
#
# Race-safe: exclusive config lock when flock is available, with a portable
# mkdir-based fallback; atomic write via mktemp + mv.
# Default-OFF is preserved for OSS — first run never auto-enables anything.

set -euo pipefail

tool="${1:?usage: toggle-precise.sh <claude|codex|gemini>}"
case "$tool" in
  claude|codex|gemini) ;;
  *) echo "unknown tool: $tool (must be claude|codex|gemini)" >&2; exit 2 ;;
esac

cfg="${ECO_HOME:-$HOME/.eco}/config.json"
lock="${ECO_HOME:-$HOME/.eco}/config.json.lock"
mkdir -p "$(dirname "$cfg")"

JQ_BIN="$(command -v jq || true)"
if [ -z "$JQ_BIN" ]; then
  echo "toggle-precise.sh: jq not found on PATH" >&2
  exit 127
fi

# Initialize empty config if missing
if [ ! -f "$cfg" ]; then
  printf '{"server_truth":{}}\n' > "$cfg"
fi

# Acquire an exclusive lock. Prefer flock when available; otherwise use mkdir,
# which is atomic on local filesystems and available on a fresh macOS install.
_with_lock() {
  if command -v flock >/dev/null 2>&1; then
    ( flock -x -w 5 9 || { echo "could not acquire config lock" >&2; exit 3; }
      "$@"
    ) 9>"$lock"
  else
    local lock_dir="${lock}.d" _attempt
    for _attempt in 1 2 3 4 5 6 7 8 9 10; do
      if mkdir "$lock_dir" 2>/dev/null; then
        (
          trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
          "$@"
        )
        return $?
      fi
      sleep 0.5
    done
    echo "could not acquire config lock" >&2
    return 3
  fi
}

_notify() {
  local msg="$1"
  # Use AppleScript's on-run-argv pattern to avoid metacharacter injection.
  # This is the same safe pattern used in usage-snapshot.sh.
  /usr/bin/osascript - "$msg" 2>/dev/null <<'OSA' || true
on run argv
  display notification (item 1 of argv) with title "eco-commander"
end run
OSA
}

_atomic_write() {
  local payload="$1"
  local tmp
  tmp=$(mktemp "${cfg}.XXXXXX")
  printf '%s\n' "$payload" > "$tmp"
  mv "$tmp" "$cfg"
}

_keychain_probe_claude() {
  /usr/bin/security find-generic-password -s "Claude Code-credentials" -w >/dev/null 2>&1
}

_keychain_probe_codex() {
  # Codex stores its OAuth in ~/.codex/auth.json — check file readable + has access_token.
  /usr/bin/python3 -c '
import json, sys, pathlib
p = pathlib.Path.home() / ".codex" / "auth.json"
if not p.exists(): sys.exit(1)
try:
    d = json.loads(p.read_text(encoding="utf-8"))
except Exception:
    sys.exit(2)
tok = (d.get("tokens") or {}).get("access_token")
sys.exit(0 if isinstance(tok, str) and tok else 3)
' >/dev/null 2>&1
}

_keychain_probe_gemini() {
  # Gemini stores its credentials in ~/.gemini/oauth_creds.json (per-account in subdirs)
  /usr/bin/find "$HOME/.gemini" -maxdepth 3 -name "oauth_creds.json" -type f 2>/dev/null \
    | head -1 | grep -q .
}

_do_toggle() {
  local cur
  cur=$("$JQ_BIN" -r --arg t "$tool" '.server_truth[$t] // false' "$cfg" 2>/dev/null || echo false)

  if [ "$cur" = "true" ]; then
    # Disabling — always allowed
    local payload
    payload=$("$JQ_BIN" --arg t "$tool" '.server_truth[$t] = false' "$cfg")
    _atomic_write "$payload"
    _notify "Precise tracking OFF for $tool — back to JSONL estimate."
    echo "$tool: server_truth disabled"
    return 0
  fi

  # Enabling probes live credential stores. Keep it fail-closed so agents and
  # accidental clicks do not touch Keychain or auth files without explicit user intent.
  if [ "${ECO_ALLOW_LIVE_CREDENTIAL_PROBE:-0}" != "1" ]; then
    _notify "Precise tracking requires explicit opt-in: ECO_ALLOW_LIVE_CREDENTIAL_PROBE=1."
    echo "$tool: live credential probe refused; set ECO_ALLOW_LIVE_CREDENTIAL_PROBE=1 to enable" >&2
    exit 0
  fi

  # Enabling — probe credential source first; surface the system prompt + bail on miss
  case "$tool" in
    claude)
      if ! _keychain_probe_claude; then
        _notify "Cannot enable Claude precise tracking — Keychain access denied or token missing."
        echo "$tool: Keychain probe failed — config unchanged" >&2
        exit 0
      fi
      ;;
    codex)
      if ! _keychain_probe_codex; then
        _notify "Cannot enable Codex precise tracking — ~/.codex/auth.json missing or invalid."
        echo "$tool: auth.json probe failed — config unchanged" >&2
        exit 0
      fi
      ;;
    gemini)
      if ! _keychain_probe_gemini; then
        _notify "Cannot enable Gemini precise tracking — no oauth_creds.json found in ~/.gemini."
        echo "$tool: oauth_creds probe failed — config unchanged" >&2
        exit 0
      fi
      ;;
  esac

  local payload
  payload=$("$JQ_BIN" --arg t "$tool" '. + {server_truth: ((.server_truth // {}) + {($t): true})}' "$cfg")
  _atomic_write "$payload"
  _notify "Precise tracking ON for $tool — using server-truth API."
  echo "$tool: server_truth enabled"
}

_with_lock _do_toggle
