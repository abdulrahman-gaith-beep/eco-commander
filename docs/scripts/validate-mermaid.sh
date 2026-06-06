#!/usr/bin/env bash
# Purpose: Lint Mermaid code blocks for unescaped angle-bracket placeholders.
#
# Mermaid renders node/edge labels as HTML by default, so a literal token like
# `<slug>` or `<job-id>` is parsed as an (invalid) HTML tag: the text silently
# vanishes from the rendered diagram, and in flowcharts with subgraphs it can
# corrupt layout entirely (`translate(undefined, NaN)`). Placeholders must be
# escaped as `&lt;...&gt;`. This guard fails CI before such a diagram lands.
#
# Scans all tracked *.md files for ```mermaid blocks and reports any raw
# `<word>` token that is not a `<br>` line break. Exits non-zero on any hit.
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# File list: tracked markdown, or a find fallback outside a git checkout.
# Filter to files that still exist (git ls-files also reports staged deletions).
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    raw=$(git ls-files '*.md')
else
    raw=$(find . -name '*.md' -not -path './.venv/*')
fi
files=$(printf '%s\n' "$raw" | while IFS= read -r p; do [ -f "$p" ] && printf '%s\n' "$p"; done)

# Single awk pass; per-file fence state resets on FNR==1. Prints offenders and
# exits 1 if any were found.
# shellcheck disable=SC2016
if printf '%s\n' "$files" | xargs awk '
    FNR==1 { inblk=0 }
    /^```mermaid[[:space:]]*$/ { inblk=1; next }
    /^```[[:space:]]*$/        { inblk=0; next }
    inblk {
        line=$0
        gsub(/<br[[:space:]]*\/?>/, "", line)   # ignore valid <br> line breaks
        if (match(line, /<[A-Za-z][^>]*>/)) {
            printf "%s:%d: %s\n", FILENAME, FNR, $0
            found=1
        }
    }
    END { exit(found ? 1 : 0) }
'; then
    echo "✓ Mermaid blocks: no unescaped angle-bracket placeholders."
else
    echo ""
    echo "✖ Found unescaped angle-bracket placeholders in Mermaid blocks (see above)."
    echo "  Replace e.g. <slug> with &lt;slug&gt; — Mermaid eats raw <...> as HTML tags."
    exit 1
fi
