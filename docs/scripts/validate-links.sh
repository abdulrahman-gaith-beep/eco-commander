#!/usr/bin/env bash
# validate-links.sh — Check all internal links resolve correctly
# Usage: docs/scripts/validate-links.sh
set -euo pipefail

DOCS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 0 ]]; then
  echo "Usage: docs/scripts/validate-links.sh" >&2
  exit 2
fi

BROKEN=0
ORPHANED=0
TOTAL_LINKS=0
TOTAL_FILES=0

echo "═══════════════════════════════════════════════════════"
echo "  Link Validation Report"
echo "  Docs: $DOCS_DIR"
echo "═══════════════════════════════════════════════════════"
echo ""

# Phase 1: Check all internal markdown links
echo "── Phase 1: Internal Link Check ──"
echo ""

while IFS= read -r file; do
  TOTAL_FILES=$((TOTAL_FILES + 1))
  REL_FILE="${file#"$DOCS_DIR"/}"
  FILE_DIR="$(dirname "$file")"

  # Extract markdown links: [text](path)
  # Skip http/https links and anchors-only links
  while IFS= read -r link; do
    [[ -z "$link" ]] && continue
    TOTAL_LINKS=$((TOTAL_LINKS + 1))

    # Remove anchor (#...) from link path
    LINK_PATH="${link%%#*}"
    [[ -z "$LINK_PATH" ]] && continue  # anchor-only link

    # Resolve relative to file's directory
    TARGET="$FILE_DIR/$LINK_PATH"

    if [[ ! -e "$TARGET" ]]; then
      BROKEN=$((BROKEN + 1))
      echo "  ✗ BROKEN: $REL_FILE"
      echo "    → $link"
      echo "    (resolved: ${TARGET#"$DOCS_DIR"/})"
      echo ""
    fi
  done < <(perl -ne 'print "$1\n" while /\]\(([^)]+)\)/g' "$file" 2>/dev/null | grep -v '^https\?://' | grep -v '^mailto:' | grep -v '^\$' || true)
done < <(find "$DOCS_DIR" -name '*.md' -not -path '*/.git/*' -not -path '*/scripts/*' | sort)

# Phase 2: Check for orphaned files (not referenced by INDEX.md or any other doc)
echo "── Phase 2: Orphan Check ──"
echo ""

while IFS= read -r file; do
  REL_FILE="${file#"$DOCS_DIR"/}"

  # Skip INDEX.md, MANIFEST.json, READING_ORDER.md, README.md, and .ai-context.yaml
  BASENAME="$(basename "$file")"
  case "$BASENAME" in
    INDEX.md|MANIFEST.json|READING_ORDER.md|README.md|.ai-context.yaml) continue ;;
  esac

  # Check if this file is referenced anywhere in the docs
  BASENAME_ESC="${BASENAME//./\\.}"
  REFS=$(grep -rl "$BASENAME_ESC" "$DOCS_DIR" --include='*.md' --include='*.json' 2>/dev/null | grep -v "$file" | head -1 || true)

  if [[ -z "$REFS" ]]; then
    ORPHANED=$((ORPHANED + 1))
    echo "  ⚠ ORPHAN: $REL_FILE"
    echo "    (not referenced by any other doc)"
    echo ""
  fi
done < <(find "$DOCS_DIR" -name '*.md' -not -path '*/.git/*' -not -path '*/scripts/*' | sort)

# Phase 3: Check INDEX.md covers all docs
echo "── Phase 3: INDEX.md Coverage ──"
echo ""

INDEX_FILE="$DOCS_DIR/INDEX.md"
MISSING_FROM_INDEX=0

while IFS= read -r file; do
  REL_FILE="${file#"$DOCS_DIR"/}"
  BASENAME="$(basename "$file")"

  case "$BASENAME" in
    INDEX.md|MANIFEST.json|READING_ORDER.md|README.md|.ai-context.yaml) continue ;;
  esac

  if ! grep -q "$REL_FILE" "$INDEX_FILE" 2>/dev/null; then
    MISSING_FROM_INDEX=$((MISSING_FROM_INDEX + 1))
    echo "  ⚠ MISSING from INDEX.md: $REL_FILE"
  fi
done < <(find "$DOCS_DIR" -name '*.md' -not -path '*/.git/*' -not -path '*/scripts/*' | sort)

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Summary"
echo "  Files scanned:     $TOTAL_FILES"
echo "  Links checked:     $TOTAL_LINKS"
echo "  Broken links:      $BROKEN"
echo "  Orphaned files:    $ORPHANED"
echo "  Missing from INDEX: $MISSING_FROM_INDEX"
echo "═══════════════════════════════════════════════════════"

[[ $BROKEN -gt 0 ]] && exit 1
exit 0
