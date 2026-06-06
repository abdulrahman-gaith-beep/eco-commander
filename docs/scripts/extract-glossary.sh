#!/usr/bin/env bash
# extract-glossary.sh — Export glossary as structured data
# Usage: docs/scripts/extract-glossary.sh [--format json|csv|plain]
set -euo pipefail

DOCS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FORMAT="plain"

usage() {
  echo "Usage: docs/scripts/extract-glossary.sh [--format json|csv|plain|--json|--csv]" >&2
}

case "${1:-}" in
  "")
    ;;
  --format)
    if [[ $# -ne 2 ]]; then
      usage
      exit 2
    fi
    FORMAT="$2"
    ;;
  --json)
    if [[ $# -ne 1 ]]; then
      usage
      exit 2
    fi
    FORMAT="json"
    ;;
  --csv)
    if [[ $# -ne 1 ]]; then
      usage
      exit 2
    fi
    FORMAT="csv"
    ;;
  *)
    usage
    exit 2
    ;;
esac

case "$FORMAT" in
  json|csv|plain) ;;
  *)
    usage
    exit 2
    ;;
esac

GLOSSARY="$DOCS_DIR/reference/glossary.md"

if [[ ! -f "$GLOSSARY" ]]; then
  echo "Glossary not found: $GLOSSARY" >&2
  exit 1
fi

json_escape() {
  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

csv_escape() {
  local s="${1-}"
  s=${s//\"/\"\"}
  printf '%s' "$s"
}

case "$FORMAT" in
  json)
    echo "{"
    echo "  \"source\": \"docs/reference/glossary.md\","
    echo "  \"terms\": ["
    FIRST=true
    while IFS='|' read -r _ term definition _; do
      # Skip header rows
      term=$(echo "$term" | sed 's/^ *//;s/ *$//')
      definition=$(echo "$definition" | sed 's/^ *//;s/ *$//')
      [[ "$term" == "Term" ]] && continue
      [[ "$term" == "------" ]] && continue
      [[ -z "$term" ]] && continue

      # Strip bold markers
      clean_term="${term//\*\*/}"
      clean_term=$(json_escape "$clean_term")
      clean_def=$(json_escape "$definition")

      $FIRST || echo ","
      FIRST=false
      printf '    {"term": "%s", "definition": "%s"}' "$clean_term" "$clean_def"
    done < <(grep '^|' "$GLOSSARY" | tail -n +3)
    echo ""
    echo "  ]"
    echo "}"
    ;;

  csv)
    echo "term,definition"
    while IFS='|' read -r _ term definition _; do
      term=$(echo "$term" | sed 's/^ *//;s/ *$//')
      definition=$(echo "$definition" | sed 's/^ *//;s/ *$//')
      [[ "$term" == "Term" ]] && continue
      [[ "$term" == "------" ]] && continue
      [[ -z "$term" ]] && continue
      clean_term="${term//\*\*/}"
      clean_term=$(csv_escape "$clean_term")
      clean_def=$(csv_escape "$definition")
      echo "\"$clean_term\",\"$clean_def\""
    done < <(grep '^|' "$GLOSSARY" | tail -n +3)
    ;;

  plain|*)
    echo "═══════════════════════════════════════════════════════"
    echo "  Eco-Commander Glossary"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    while IFS='|' read -r _ term definition _; do
      term=$(echo "$term" | sed 's/^ *//;s/ *$//')
      definition=$(echo "$definition" | sed 's/^ *//;s/ *$//')
      [[ "$term" == "Term" ]] && continue
      [[ "$term" == "------" ]] && continue
      [[ -z "$term" ]] && continue
      clean_term="${term//\*\*/}"
      printf "  %-20s %s\n" "$clean_term" "$definition"
      echo ""
    done < <(grep '^|' "$GLOSSARY" | tail -n +3)
    echo "═══════════════════════════════════════════════════════"
    ;;
esac
