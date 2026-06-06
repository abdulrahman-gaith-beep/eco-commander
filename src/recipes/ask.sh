#!/usr/bin/env bash
# DESC: Ask a question fast. Routes to Gemini (quick) by default. No ceremony.
# INPUTS: <question> (prompted if omitted)
# OUTPUT: stdout; optionally pipe to a file
# USES: gem-smart/Gemini for normal prompts; verified local Ollama model for private prompts
# HUMAN: question is the whole interface — one prompt, one answer
set -eu

Q="${*:-}"
if [ -z "$Q" ]; then
  echo -n "? "
  read -r Q || Q=""
fi
[ -z "$Q" ] && exit 0

provider_failure_hint() {
  local rc="$1"
  local log="$2"

  echo "Gemini provider failed (rc=$rc)." >&2
  if grep -qiE 'auth|oauth|login|credential|unauthori[sz]ed|forbidden|api[ _-]?key' "$log" 2>/dev/null; then
    echo "Hint: authentication issue; run the provider login flow or check credentials." >&2
  elif grep -qiE 'quota|rate[ -]?limit|429|resource[_ -]?exhausted' "$log" 2>/dev/null; then
    echo "Hint: quota or rate limit issue; wait for reset or switch provider/account." >&2
  elif grep -qiE 'network|dns|enotfound|fetch failed|timeout|timed out|connection|econn|unreachable|tls|ssl' "$log" 2>/dev/null; then
    echo "Hint: network issue; check connectivity, DNS, or proxy settings." >&2
  elif grep -qiE 'not found|command not found|no such file|enoent|install' "$log" 2>/dev/null; then
    echo "Hint: install issue; check the selected Gemini command and PATH." >&2
  else
    echo "Hint: check provider auth, quota, network, or installation." >&2
  fi
}

# Route: if question contains "private", "secret", "internal" → local Ollama
if echo "$Q" | grep -qiE "(private|secret|internal|confidential|بياناتي|خاص)"; then
  if command -v ollama >/dev/null 2>&1; then
    LOCAL_MODEL="${ECO_ASK_LOCAL_MODEL:-qwen3.6:latest}"
    if ! ollama list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$LOCAL_MODEL"; then
      echo "Private cue detected, but configured local model is not installed: $LOCAL_MODEL" >&2
      echo "Set ECO_ASK_LOCAL_MODEL to a model from: ollama list" >&2
      exit 2
    fi
    echo "[routing: local ${LOCAL_MODEL} — private cue detected]"
    echo "$Q" | ollama run "$LOCAL_MODEL"
    exit 0
  fi
  echo "Private cue detected, but Ollama is unavailable. Refusing to send this prompt to a cloud model." >&2
  exit 2
fi

# Default: Gemini. Prefer the maintained "gem-smart" wrapper when present;
# otherwise fall back to the plain Gemini CLI so the recipe works out of the box.
cd "$HOME" || exit 1
GEM_SMART="${ECO_GEM_SMART_BIN:-$HOME/bin/gem-smart}"
ERR_LOG="$(mktemp "${TMPDIR:-/tmp}/eco-ask-provider.XXXXXX.log")"
cleanup_provider_log() {
  rm -f "$ERR_LOG" 2>/dev/null || true
}
trap cleanup_provider_log EXIT

if [ -x "$GEM_SMART" ] || command -v "$GEM_SMART" >/dev/null 2>&1; then
  if "$GEM_SMART" 3.5f -p "$Q" -y --allowed-mcp-server-names none 2>"$ERR_LOG"; then
    :
  else
    rc=$?
    provider_failure_hint "$rc" "$ERR_LOG"
    exit "$rc"
  fi
elif command -v gemini >/dev/null 2>&1; then
  if gemini -p "$Q" 2>"$ERR_LOG"; then
    :
  else
    rc=$?
    provider_failure_hint "$rc" "$ERR_LOG"
    exit "$rc"
  fi
else
  echo "gem-smart not found, and no 'gemini' CLI on PATH." >&2
  echo "Install the Gemini CLI (https://github.com/google-gemini/gemini-cli) or set ECO_GEM_SMART_BIN." >&2
  exit 1
fi
