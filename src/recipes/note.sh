#!/usr/bin/env bash
# DESC: Capture a note to long-term memory in the right space
# INPUTS: <content string> OR opens $EDITOR if empty
# OUTPUT: file in ~/.ai-memory/spaces/<space>/ when available; otherwise ~/.eco/notes/spaces/<space>/
# USES: filesystem write + optional memory_router rebuild
# HUMAN: you type/paste the note; auto-routes to the right space by CWD
set -eu

ECO_ROOT="${ECO_HOME:-${ECO:-$HOME/.eco}}"
AI_MEMORY_ROOT="${AI_MEMORY_HOME:-$HOME/.ai-memory}"
MEMORY_ROUTER="${MEMORY_ROUTER:-$HOME/.claude/hooks/memory_router.py}"

CONTENT="${*:-}"
if [ -z "$CONTENT" ]; then
  TMPFILE=$(mktemp "${TMPDIR:-/tmp}/eco-note.XXXXXX.md")
  ${EDITOR:-nano} "$TMPFILE"
  CONTENT=$(cat "$TMPFILE")
  rm "$TMPFILE"
fi
# Trim whitespace-only content
if [ -z "$(echo "$CONTENT" | tr -d '[:space:]')" ]; then
  echo "Empty note. Abort."
  exit 1
fi

# Determine space by CWD — derive from the project root basename.
# If inside a git repo, use the repo root; otherwise fall back to $PWD.
# A note taken outside any recognizable project lands in the "unified" space.
SPACE="unified"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$PWD"
BASENAME=$(basename "$PROJECT_ROOT")
# Slugify the basename: lowercase, non-alphanumerics to dashes, trim.
SLUG=$(printf '%s' "$BASENAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
# Only route to a project space when we're not sitting at $HOME itself.
if [ -n "$SLUG" ] && [ "$PROJECT_ROOT" != "$HOME" ] && [ "$PROJECT_ROOT" != "/" ]; then
  SPACE="project-$SLUG"
fi

if [ -d "$AI_MEMORY_ROOT" ]; then
  SPACE_ROOT="$AI_MEMORY_ROOT/spaces"
  NOTE_BACKEND="ai-memory"
else
  SPACE_ROOT="$ECO_ROOT/notes/spaces"
  NOTE_BACKEND="eco-local"
fi

SPACE_DIR="$SPACE_ROOT/$SPACE"
mkdir -p "$SPACE_DIR"

TS=$(date +%Y-%m-%d-%H%M%S)
FIRST_LINE=$(echo "$CONTENT" | head -1 | sed 's/^# *//' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40)
[ -z "$FIRST_LINE" ] && FIRST_LINE="note-$(printf '%s' "$CONTENT" | cksum | awk '{print $1}')"
FILE="$SPACE_DIR/note-${TS}-${FIRST_LINE:-untitled}.md"

echo "$CONTENT" > "$FILE"

echo "=== Note saved ==="
echo "Space: $SPACE"
echo "Backend: $NOTE_BACKEND"
echo "File: $FILE"
wc -c "$FILE"
echo
if [ "$NOTE_BACKEND" = "ai-memory" ]; then
  echo "Rebuilding index for $SPACE..."
  python3 "$MEMORY_ROUTER" --build-space "$SPACE" 2>/dev/null && echo "  ✓ index rebuilt" || \
    (python3 "$MEMORY_ROUTER" --build 2>/dev/null && echo "  ✓ full rebuild done") || \
    echo "  ⚠ rebuild failed (note saved, but won't be retrievable until next rebuild)"
else
  echo "Skipping index rebuild: $AI_MEMORY_ROOT not found."
fi
