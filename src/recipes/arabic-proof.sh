#!/usr/bin/env bash
# DESC: Proofread Arabic text with local Ollama (private, zero cloud)
# INPUTS: <file path> OR stdin
# OUTPUT: proofread version to stdout + corrections list
# USES: Ollama qwen3.6:latest by default; override with ECO_ARABIC_PROOF_MODEL or ECO_ARABIC_MODEL
# HUMAN: you supply text; qwen corrects and lists changes
set -eu

MODEL="${ECO_ARABIC_PROOF_MODEL:-${ECO_ARABIC_MODEL:-qwen3.6:latest}}"

# Validate input before touching Ollama, so bad paths/empty files do not load
# or unload anything.
if [ -n "${1:-}" ]; then
  if [ -f "$1" ]; then
    TEXT=$(cat "$1")
  else
    echo "File not found: $1" >&2
    exit 1
  fi
elif [ -t 0 ]; then
  echo "Paste Arabic text (Ctrl+D when done):"
  TEXT=$(cat)
else
  TEXT=$(cat)
fi
[ -z "$TEXT" ] && { echo "No text."; exit 1; }

if ! command -v ollama >/dev/null 2>&1; then
  echo "ollama not installed. brew install ollama"
  exit 1
fi

if ! ollama list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$MODEL"; then
  echo "Configured Arabic model is not installed: $MODEL" >&2
  echo "Install it or set ECO_ARABIC_PROOF_MODEL to a model from: ollama list" >&2
  exit 2
fi

# Optional auto-unload on exit — but only if explicitly requested and only if
# we were the one to load it. Default keeps useful models resident.
WE_LOADED_MODEL=0
if ! ollama ps 2>/dev/null | grep -qF "$MODEL"; then
  WE_LOADED_MODEL=1
fi
cleanup() {
  if [ "${ECO_ARABIC_PROOF_AUTO_UNLOAD:-0}" = "1" ] && [ "$WE_LOADED_MODEL" = "1" ]; then
    ollama stop "$MODEL" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[routing: local ${MODEL} — Arabic private]"
echo "(loading model — takes ~15s if first run)"
echo

if [ "$WE_LOADED_MODEL" = "1" ]; then
  if [ "${ECO_ARABIC_PROOF_AUTO_UNLOAD:-0}" = "1" ]; then
    echo "Warming $MODEL... (will auto-unload on exit)"
  else
    echo "Warming $MODEL... (kept resident after run)"
  fi
fi

PROMPT="You are a professional Arabic proofreader.

Task: proofread and correct the following Arabic text. Respect sacred names (Allah ﷻ, Prophet ﷺ).

Output format:
## التصحيح (corrected text)
<full corrected text>

## التغييرات (changes list)
<bulleted list of corrections: original → corrected → brief reason>

Text to proofread:

$TEXT"

echo "$PROMPT" | ollama run "$MODEL"
