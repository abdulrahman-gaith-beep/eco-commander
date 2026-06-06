#!/usr/bin/env bash
# DESC: Research a topic with Gemini (fast, cheap, wide — 1M context)
# INPUTS: <topic string> (prompted if omitted)
# OUTPUT: ~/Documents/research/<slug>/YYYY-MM-DD-<slug>.md
# USES: gem-smart or Gemini CLI for a structured research brief
# HUMAN: reviews the topic framing before Gemini runs
set -eu

TOPIC="${*:-}"
if [ -z "$TOPIC" ]; then
  echo -n "Research topic: "
  read -r TOPIC
fi
[ -z "$TOPIC" ] && { echo "No topic. Abort."; exit 1; }

SLUG=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-50)
[ -z "$SLUG" ] && SLUG="topic-$(printf '%s' "$TOPIC" | cksum | awk '{print $1}')"
DATE=$(date +%Y-%m-%d)
OUTDIR="$HOME/Documents/research/$SLUG"
OUTFILE="$OUTDIR/${DATE}-${SLUG}.md"
mkdir -p "$OUTDIR"

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

echo "=== Recipe: research ==="
echo "Topic: $TOPIC"
echo "Output: $OUTFILE"
echo

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

PROMPT="You are a research assistant for your AI ecosystem.

Topic: $TOPIC

Produce a structured research brief covering:
1. What it is (2-3 paragraphs)
2. Key concepts / terminology
3. Relevant libraries, tools, or services (name + URL + one-line)
4. Current state-of-the-art as of $(date +%Y)
5. Practical trade-offs (cost, complexity, alternatives)
6. Recommended next steps for someone evaluating this for a real project

Cite sources inline as [url]. Plain markdown output. Be direct and specific; avoid filler."

cd "$HOME" || exit 1
ERR_LOG="$(mktemp "${TMPDIR:-/tmp}/eco-research-provider.XXXXXX.log")"
cleanup_provider_log() {
  rm -f "$ERR_LOG" 2>/dev/null || true
}
trap cleanup_provider_log EXIT

if [ "$GEM_BACKEND" = "gem-smart" ]; then
  if "$GEM_SMART" 3.5f -p "$PROMPT" -y --allowed-mcp-server-names none > "$OUTFILE" 2>"$ERR_LOG"; then
    :
  else
    rc=$?
    [ -s "$OUTFILE" ] || rm -f "$OUTFILE"
    provider_failure_hint "$rc" "$ERR_LOG"
    exit "$rc"
  fi
else
  if gemini -p "$PROMPT" > "$OUTFILE" 2>"$ERR_LOG"; then
    :
  else
    rc=$?
    [ -s "$OUTFILE" ] || rm -f "$OUTFILE"
    provider_failure_hint "$rc" "$ERR_LOG"
    exit "$rc"
  fi
fi

if [ -s "$OUTFILE" ]; then
  echo "=== Done ==="
  wc -l "$OUTFILE"
  echo
  head -20 "$OUTFILE"
  echo "..."
  echo
  echo "Full file: $OUTFILE"
  open "$OUTFILE" 2>/dev/null || true
else
  echo "Gemini returned no output. Check: gemini --version"
  rm -f "$OUTFILE"
  exit 1
fi
