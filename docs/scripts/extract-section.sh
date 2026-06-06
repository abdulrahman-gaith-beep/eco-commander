#!/usr/bin/env bash
# extract-section.sh — Extract a specific section from a doc by heading
# Usage: docs/scripts/extract-section.sh <file> <heading>
# Example: docs/scripts/extract-section.sh subsystems/scheduler.md "Meter system"
set -euo pipefail

DOCS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FILE="${1:?Usage: extract-section.sh <file> <heading>}"
HEADING="${2:?Usage: extract-section.sh <file> <heading>}"

# Resolve file path
if [[ "$FILE" = /* ]]; then
  FULL_PATH="$FILE"
elif [[ -f "$DOCS_DIR/$FILE" ]]; then
  FULL_PATH="$DOCS_DIR/$FILE"
elif [[ -f "$FILE" ]]; then
  FULL_PATH="$FILE"
else
  echo "File not found: $FILE" >&2
  echo "Searched: $DOCS_DIR/$FILE and $FILE" >&2
  exit 1
fi

# Find the heading line number (case-insensitive, literal heading text).
HEADING_LINE=$(awk -v heading="$HEADING" '
  BEGIN { needle = tolower(heading) }
  /^#+[[:space:]]+/ {
    if (index(tolower($0), needle) > 0) {
      print FNR
      exit
    }
  }
' "$FULL_PATH")

if [[ -z "$HEADING_LINE" ]]; then
  echo "Heading not found: \"$HEADING\" in $FILE" >&2
  echo ""
  echo "Available headings:" >&2
  grep '^#' "$FULL_PATH" | head -20 >&2 || true
  exit 1
fi

# Get the heading level
HEADING_LEVEL=$(sed -n "${HEADING_LINE}p" "$FULL_PATH" | grep -o '^#*' | wc -c)
HEADING_LEVEL=$((HEADING_LEVEL - 1))  # Remove trailing newline count

# Find the next heading at the same or higher level
TOTAL_LINES=$(wc -l < "$FULL_PATH" | tr -d ' ')
END_LINE="$TOTAL_LINES"

SEARCH_START=$((HEADING_LINE + 1))
if [[ $SEARCH_START -le $TOTAL_LINES ]]; then
  NEXT_HEADING_LINE=$(awk -v start="$SEARCH_START" -v max="$HEADING_LEVEL" '
    FNR >= start {
      hashes = 0
      while (substr($0, hashes + 1, 1) == "#") {
        hashes++
      }
      if (hashes >= 1 && hashes <= max && substr($0, hashes + 1, 1) == " " && substr($0, hashes + 2, 1) != "#") {
        print FNR
        exit
      }
    }
  ' "$FULL_PATH")
  if [[ -n "$NEXT_HEADING_LINE" ]]; then
    END_LINE=$((NEXT_HEADING_LINE - 1))
  fi
fi

# Extract and output
REL_PATH="${FULL_PATH#"$DOCS_DIR"/}"
echo "# Extracted from: $REL_PATH (lines ${HEADING_LINE}–${END_LINE})"
echo ""
sed -n "${HEADING_LINE},${END_LINE}p" "$FULL_PATH"
