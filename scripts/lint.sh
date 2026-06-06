#!/usr/bin/env bash
# scripts/lint.sh — Static analysis for shell, YAML, and plist files.
#
# @category  ci
# @depends   shellcheck
# @called-by Makefile, release.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0

# ── shellcheck ───────────────────────────────────────────────────────
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not installed. brew install shellcheck" >&2
  exit 2
fi

if find "$REPO_ROOT/src" "$REPO_ROOT/scripts" -type f \
  \( -name "*.sh" -o -name "eco" \) -print0 \
  | sort -z \
  | xargs -0 shellcheck -x; then
  echo "  ✓ all shell files pass"
else
  echo "  ✗ shellcheck found issues"
  ERRORS=$((ERRORS + 1))
fi

# ── YAML validation ─────────────────────────────────────────────────
yaml_files=()
while IFS= read -r -d '' f; do
  yaml_files+=("$f")
done < <(find "$REPO_ROOT" -maxdepth 3 -type f \( -name "*.yaml" -o -name "*.yml" \) \
  -not -path "*/.git/*" -not -path "*/node_modules/*" -print0 2>/dev/null)

if [ "${#yaml_files[@]}" -gt 0 ]; then
  echo "── YAML validation (${#yaml_files[@]} files) ──"
  yaml_ok=0
  yaml_fail=0
  for f in "${yaml_files[@]}"; do
    if python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]))" "$f" 2>/dev/null; then
      yaml_ok=$((yaml_ok + 1))
    else
      echo "  ✗ invalid YAML: $f"
      yaml_fail=$((yaml_fail + 1))
    fi
  done
  if [ "$yaml_fail" -eq 0 ]; then
    echo "  ✓ all $yaml_ok YAML files valid"
  else
    ERRORS=$((ERRORS + yaml_fail))
  fi
fi

# ── plist validation ─────────────────────────────────────────────────
plist_files=()
while IFS= read -r -d '' f; do
  plist_files+=("$f")
done < <(find "$REPO_ROOT/scripts/launchagents" -type f -name "*.plist" -print0 2>/dev/null)

if [ "${#plist_files[@]}" -gt 0 ]; then
  echo "── plist validation (${#plist_files[@]} files) ──"
  plist_ok=0
  plist_fail=0
  for f in "${plist_files[@]}"; do
    # plists have template vars (__FOO__) — check XML structure only
    if python3 -c "
import sys, re
text = open(sys.argv[1]).read()
# Replace template vars with valid strings for XML parsing
text = re.sub(r'__[A-Z_]+__', '/tmp/placeholder', text)
import plistlib
plistlib.loads(text.encode())
" "$f" 2>/dev/null; then
      plist_ok=$((plist_ok + 1))
    else
      echo "  ✗ invalid plist: $f"
      plist_fail=$((plist_fail + 1))
    fi
  done
  if [ "$plist_fail" -eq 0 ]; then
    echo "  ✓ all $plist_ok plist templates valid"
  else
    ERRORS=$((ERRORS + plist_fail))
  fi
fi

# ── summary ──────────────────────────────────────────────────────────
echo
if [ "$ERRORS" -eq 0 ]; then
  echo "✓ all checks passed"
else
  echo "✗ $ERRORS check(s) failed" >&2
  exit 1
fi
