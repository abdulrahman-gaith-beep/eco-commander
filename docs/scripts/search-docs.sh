#!/usr/bin/env bash
# search-docs.sh — Full-text search across all eco-commander docs
# Usage: docs/scripts/search-docs.sh <query> [--context N] [--category <name>]
set -euo pipefail

DOCS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QUERY="${1:?Usage: search-docs.sh <query> [--context N] [--category <name>]}"
shift

CONTEXT=2
CATEGORY=""

die() { echo "search-docs.sh: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context|-c)
      [[ $# -ge 2 ]] || die "$1 requires a numeric value"
      case "$2" in
        ""|*[!0-9]*) die "context must be a non-negative integer: $2" ;;
      esac
      CONTEXT="$2"
      shift 2
      ;;
    --category|-C)
      [[ $# -ge 2 ]] || die "$1 requires a docs category"
      CATEGORY="$2"
      case "$CATEGORY" in
        ""|.*|*/*|*..*) die "category must be a top-level docs directory name: $CATEGORY" ;;
      esac
      shift 2
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

SEARCH_PATH="$DOCS_DIR"
if [[ -n "$CATEGORY" ]]; then
  if [[ -d "$DOCS_DIR/$CATEGORY" ]]; then
    SEARCH_PATH="$DOCS_DIR/$CATEGORY"
  else
    echo "Category not found: $CATEGORY" >&2
    echo "Available: getting-started, reference, subsystems, operations, contributing, adr, diagrams" >&2
    exit 1
  fi
fi

echo "═══════════════════════════════════════════════════════"
echo "  Search: \"$QUERY\""
[[ -n "$CATEGORY" ]] && echo "  Category: $CATEGORY"
echo "  Context: ±${CONTEXT} lines"
echo "═══════════════════════════════════════════════════════"
echo ""

MATCH_COUNT=0
while IFS= read -r file; do
  REL_PATH="${file#"$DOCS_DIR"/}"
  MATCHES=$(grep -n -i -F -- "$QUERY" "$file" 2>/dev/null || true)
  if [[ -n "$MATCHES" ]]; then
    FILE_MATCH_COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
    MATCH_COUNT=$((MATCH_COUNT + FILE_MATCH_COUNT))
    echo "┌─ $REL_PATH ($FILE_MATCH_COUNT matches)"
    echo "│"
    while IFS= read -r match; do
      LINE_NUM=$(echo "$match" | cut -d: -f1)
      echo "│  Line $LINE_NUM:"
      # Show context around the match
      START=$((LINE_NUM - CONTEXT))
      END=$((LINE_NUM + CONTEXT))
      [[ $START -lt 1 ]] && START=1
      sed -n "${START},${END}p" "$file" | while IFS= read -r ctx_line; do
        echo "│    $ctx_line"
      done
      echo "│"
    done <<< "$MATCHES"
    echo "└──────────────────────────────────────"
    echo ""
  fi
done < <(find "$SEARCH_PATH" -name '*.md' -not -path '*/.git/*' | sort)

echo "═══════════════════════════════════════════════════════"
echo "  Total: $MATCH_COUNT matches"
echo "═══════════════════════════════════════════════════════"
