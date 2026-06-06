#!/usr/bin/env bash
# doc-stats.sh — Generate corpus statistics for eco-commander docs
# Usage: docs/scripts/doc-stats.sh [--json]
set -euo pipefail

DOCS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

format_size() {
  local bytes="$1"
  if [[ $bytes -lt 1024 ]]; then
    echo "${bytes} B"
  else
    echo "$((bytes / 1024)) KB"
  fi
}

# Collect stats
TOTAL_FILES=0
TOTAL_BYTES=0
TOTAL_LINES=0

# Category tracking via temp files (compatible with bash 3.2)
TMPDIR_STATS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_STATS"' EXIT

while IFS= read -r file; do
  TOTAL_FILES=$((TOTAL_FILES + 1))
  FILE_SIZE=$(wc -c < "$file" | tr -d ' ')
  FILE_LINES=$(wc -l < "$file" | tr -d ' ')
  TOTAL_BYTES=$((TOTAL_BYTES + FILE_SIZE))
  TOTAL_LINES=$((TOTAL_LINES + FILE_LINES))

  # Determine category
  REL="${file#"$DOCS_DIR"/}"
  if [[ "$REL" == */* ]]; then
    CAT=$(echo "$REL" | cut -d/ -f1)
  else
    CAT="top-level"
  fi

  # Accumulate per-category via files
  CAT_FILE="$TMPDIR_STATS/$CAT"
  if [[ -f "$CAT_FILE" ]]; then
    OLD_FILES=$(head -1 "$CAT_FILE")
    OLD_BYTES=$(tail -1 "$CAT_FILE")
    echo "$((OLD_FILES + 1))" > "$CAT_FILE"
    echo "$((OLD_BYTES + FILE_SIZE))" >> "$CAT_FILE"
  else
    echo "1" > "$CAT_FILE"
    echo "$FILE_SIZE" >> "$CAT_FILE"
  fi
done < <(find "$DOCS_DIR" -name '*.md' -not -path '*/.git/*' -not -path '*/scripts/*' | sort)

# Find largest and smallest docs
LARGEST_FILE=""
LARGEST_SIZE=0
SMALLEST_FILE=""
SMALLEST_SIZE=999999999

while IFS= read -r file; do
  SIZE=$(wc -c < "$file" | tr -d ' ')
  REL="${file#"$DOCS_DIR"/}"
  if [[ $SIZE -gt $LARGEST_SIZE ]]; then
    LARGEST_SIZE=$SIZE
    LARGEST_FILE="$REL"
  fi
  if [[ $SIZE -lt $SMALLEST_SIZE ]]; then
    SMALLEST_SIZE=$SIZE
    SMALLEST_FILE="$REL"
  fi
done < <(find "$DOCS_DIR" -name '*.md' -not -path '*/.git/*' -not -path '*/scripts/*' -not -name 'README.md' | sort)

# Count unique terms in glossary
GLOSSARY_TERMS=0
if [[ -f "$DOCS_DIR/reference/glossary.md" ]]; then
  GLOSSARY_TERMS=$(grep -c '^| \*\*' "$DOCS_DIR/reference/glossary.md" 2>/dev/null || echo 0)
fi

# Count ADRs
ADR_COUNT=$(find "$DOCS_DIR/adr" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

# Count diagrams
DIAGRAM_COUNT=$(find "$DOCS_DIR/diagrams" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

if $JSON_MODE; then
  echo "{"
  echo "  \"total_files\": $TOTAL_FILES,"
  echo "  \"total_bytes\": $TOTAL_BYTES,"
  echo "  \"total_lines\": $TOTAL_LINES,"
  echo "  \"glossary_terms\": $GLOSSARY_TERMS,"
  echo "  \"adr_count\": $ADR_COUNT,"
  echo "  \"diagram_count\": $DIAGRAM_COUNT,"
  echo "  \"largest\": {\"file\": \"$LARGEST_FILE\", \"bytes\": $LARGEST_SIZE},"
  echo "  \"smallest\": {\"file\": \"$SMALLEST_FILE\", \"bytes\": $SMALLEST_SIZE},"
  echo "  \"categories\": {"
  FIRST=true
  for cat_file in "$TMPDIR_STATS"/*; do
    [[ -f "$cat_file" ]] || continue
    cat=$(basename "$cat_file")
    cat_files=$(head -1 "$cat_file")
    cat_bytes=$(tail -1 "$cat_file")
    $FIRST || echo ","
    FIRST=false
    printf "    \"%s\": {\"files\": %d, \"bytes\": %d}" "$cat" "$cat_files" "$cat_bytes"
  done
  echo ""
  echo "  }"
  echo "}"
else
  echo "═══════════════════════════════════════════════════════"
  echo "  Eco-Commander Documentation Statistics"
  echo "═══════════════════════════════════════════════════════"
  echo ""
  echo "  Total files:       $TOTAL_FILES"
  echo "  Total size:        $((TOTAL_BYTES / 1024)) KB ($TOTAL_BYTES bytes)"
  echo "  Total lines:       $TOTAL_LINES"
  echo "  Glossary terms:    $GLOSSARY_TERMS"
  echo "  ADRs:              $ADR_COUNT"
  echo "  Diagrams:          $DIAGRAM_COUNT"
  echo ""
  echo "── By Category ──"
  echo ""
  printf "  %-20s %5s %8s\n" "Category" "Files" "Size"
  printf "  %-20s %5s %8s\n" "────────────────────" "─────" "────────"
  for cat_file in "$TMPDIR_STATS"/*; do
    [[ -f "$cat_file" ]] || continue
    cat=$(basename "$cat_file")
    cat_files=$(head -1 "$cat_file")
    cat_bytes=$(tail -1 "$cat_file")
    printf "  %-20s %5d %8s\n" "$cat" "$cat_files" "$(format_size "$cat_bytes")"
  done
  echo ""
  echo "── Extremes ──"
  echo ""
  echo "  Largest:  $LARGEST_FILE ($(format_size "$LARGEST_SIZE"))"
  echo "  Smallest: $SMALLEST_FILE ($(format_size "$SMALLEST_SIZE"))"
  echo ""
  echo "═══════════════════════════════════════════════════════"
fi
