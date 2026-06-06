#!/usr/bin/env bash
# scripts/doctor.sh — Diagnose and repair eco-commander installation.
#
# Checks:
#   1. Symlink integrity (are all expected symlinks present and pointing to this repo?)
#   2. config.json validity (is it parseable JSON with expected keys?)
#   3. Orphaned log files beyond rotation policy
#   4. Stale usage.json data (informational; poller is opt-in)
#
# Usage:
#   scripts/doctor.sh           # diagnose only
#   scripts/doctor.sh --fix     # diagnose + auto-repair where safe
#
# @category  runtime
# @depends   bash, jq, python3
# @env-vars  ECO_HOME
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"
FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

OK=0
WARN=0
FAIL=0

pass()  { OK=$((OK+1));   printf "  ✓ %s\n" "$*"; }
warn()  { WARN=$((WARN+1)); printf "  ⚠ %s\n" "$*"; }
fail()  { FAIL=$((FAIL+1)); printf "  ✗ %s\n" "$*"; }
info()  { printf "  ○ %s\n" "$*"; }

backup_symlink() {
  local link="$1" label="$2" backup
  backup="$link.bak.$(date +%s)"
  if [ -e "$backup" ] || [ -L "$backup" ]; then
    backup="$backup.$$"
  fi
  mv "$link" "$backup"
  info "backed up $label to $backup"
}

relink_if_eco_owned() {
  local link="$1" src="$2" prefix="$3" label="$4"
  local target
  target="$(readlink "$link")"
  if [[ "$target" != "$prefix"* ]]; then
    warn "not re-linking $label (--fix): existing symlink is not eco-owned"
    return 1
  fi
  backup_symlink "$link" "$label"
  ln -s "$src" "$link"
  info "re-linked $label (--fix)"
}

# ── 1. Core directory structure ──────────────────────────────────────
echo "── Directory structure ──"
for d in "$ECO_HOME" "$ECO_HOME/bin" "$ECO_HOME/recipes" "$ECO_HOME/current"; do
  if [ -d "$d" ]; then
    pass "$d exists"
  elif [ "$FIX" -eq 1 ]; then
    mkdir -p "$d"
    chmod 0700 "$d"
    pass "$d created (--fix)"
  else
    fail "$d missing (run with --fix or 'make install')"
  fi
done

# ── 2. Symlink integrity ────────────────────────────────────────────
echo ""
echo "── Symlink integrity ──"
for src in "$REPO_ROOT"/src/bin/*; do
  name="$(basename "$src")"
  link="$ECO_HOME/bin/$name"
  if [ -L "$link" ]; then
    target="$(readlink "$link")"
    if [ "$target" = "$src" ]; then
      pass "$name -> correct target"
    else
      fail "$name -> $target (expected $src)"
      if [ "$FIX" -eq 1 ]; then
        relink_if_eco_owned "$link" "$src" "$REPO_ROOT/src/bin/" "$name" || true
      fi
    fi
  elif [ -e "$link" ]; then
    warn "$name is a regular file, not a symlink"
  else
    fail "$name missing from $ECO_HOME/bin/"
    if [ "$FIX" -eq 1 ]; then
      ln -s "$src" "$link"
      info "linked $name (--fix)"
    fi
  fi
done

for src in "$REPO_ROOT"/src/recipes/*.sh; do
  [ -e "$src" ] || continue
  name="$(basename "$src")"
  link="$ECO_HOME/recipes/$name"
  if [ -L "$link" ]; then
    target="$(readlink "$link")"
    if [ "$target" = "$src" ]; then
      pass "recipe $name -> correct target"
    else
      fail "recipe $name -> $target (expected $src)"
      if [ "$FIX" -eq 1 ]; then
        relink_if_eco_owned "$link" "$src" "$REPO_ROOT/src/recipes/" "recipe $name" || true
      fi
    fi
  elif [ -e "$link" ]; then
    warn "recipe $name is a regular file, not a symlink"
  else
    fail "recipe $name missing"
    if [ "$FIX" -eq 1 ]; then
      ln -s "$src" "$link"
      info "linked recipe $name (--fix)"
    fi
  fi
done

# ── 3. config.json validity ─────────────────────────────────────────
echo ""
echo "── Configuration ──"
CFG="$ECO_HOME/config.json"
if [ -f "$CFG" ]; then
  if jq empty "$CFG" 2>/dev/null; then
    pass "config.json is valid JSON"
    # Check for expected keys
    if jq -e '.server_truth' "$CFG" >/dev/null 2>&1; then
      pass "config.json has server_truth key"
    else
      warn "config.json missing server_truth key"
      if [ "$FIX" -eq 1 ]; then
        payload=$(jq '. + {"server_truth": {}}' "$CFG")
        printf '%s\n' "$payload" > "$CFG"
        info "added server_truth key (--fix)"
      fi
    fi
  else
    fail "config.json is invalid JSON"
    if [ "$FIX" -eq 1 ]; then
      cp "$CFG" "$CFG.bak.$(date +%s)"
      printf '{"server_truth":{}}\n' > "$CFG"
      info "reset config.json (backup saved as .bak.*) (--fix)"
    fi
  fi
else
  info "config.json does not exist (will be created on first toggle-precise run)"
fi

# ── 4. Usage data freshness ─────────────────────────────────────────
echo ""
echo "── Usage data ──"
USAGE_JSON="$ECO_HOME/current/usage.json"
if [ -f "$USAGE_JSON" ]; then
  if jq empty "$USAGE_JSON" 2>/dev/null; then
    pass "usage.json is valid JSON"
    AGE=$(( $(date +%s) - $(stat -f %m "$USAGE_JSON") ))
    if [ "$AGE" -le 300 ]; then
      pass "usage.json is fresh ($AGE s old)"
    elif [ "$AGE" -le 3600 ]; then
      warn "usage.json is stale ($AGE s old) — poller may not be running"
    else
      warn "usage.json is very stale ($AGE s old) — poller may not be running"
    fi
  else
    fail "usage.json is invalid JSON"
  fi
else
  warn "usage.json does not exist — run the poller first"
fi

# ── 5. Log directory health ─────────────────────────────────────────
echo ""
echo "── Log health ──"
LOGS_DIR="$ECO_HOME/logs"
if [ -d "$LOGS_DIR" ]; then
  TOTAL_KB=$(du -sk "$LOGS_DIR" 2>/dev/null | awk '{print $1}')
  if [ "${TOTAL_KB:-0}" -lt 10000 ]; then
    pass "logs directory is ${TOTAL_KB:-0} KB (<10 MB)"
  elif [ "${TOTAL_KB:-0}" -lt 50000 ]; then
    warn "logs directory is ${TOTAL_KB} KB — consider log rotation"
  else
    fail "logs directory is ${TOTAL_KB} KB (>50 MB) — install log rotation"
  fi

  # Check for orphaned/oversized individual logs
  while IFS= read -r -d '' logfile; do
    size_kb=$(du -k "$logfile" 2>/dev/null | awk '{print $1}')
    if [ "${size_kb:-0}" -gt 10000 ]; then
      warn "large log: $(basename "$logfile") is ${size_kb} KB"
    fi
  done < <(find "$LOGS_DIR" -type f -name "*.log" -print0 2>/dev/null)
else
  info "logs directory does not exist yet"
fi

# ── 6. Stale symlinks (dangling) ────────────────────────────────────
echo ""
echo "── Dangling symlinks ──"
dangling=0
for dir in "$ECO_HOME/bin" "$ECO_HOME/recipes"; do
  [ -d "$dir" ] || continue
  case "$dir" in
    "$ECO_HOME/bin") owned_prefix="$REPO_ROOT/src/bin/" ;;
    "$ECO_HOME/recipes") owned_prefix="$REPO_ROOT/src/recipes/" ;;
    *) owned_prefix="" ;;
  esac
  while IFS= read -r -d '' link; do
    if [ -L "$link" ] && [ ! -e "$link" ]; then
      target="$(readlink "$link")"
      fail "dangling symlink: $link -> $target"
      dangling=$((dangling + 1))
      if [ "$FIX" -eq 1 ]; then
        if [ -n "$owned_prefix" ] && [[ "$target" == "$owned_prefix"* ]]; then
          backup_symlink "$link" "dangling symlink $(basename "$link")"
        else
          warn "not removing dangling symlink (--fix): target is not eco-owned"
        fi
      fi
    fi
  done < <(find "$dir" -maxdepth 1 -type l -print0 2>/dev/null)
done
[ "$dangling" -eq 0 ] && pass "no dangling symlinks"

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "── Summary ── ✓ $OK passed · ⚠ $WARN warnings · ✗ $FAIL failed"
if [ "$FAIL" -gt 0 ] && [ "$FIX" -eq 0 ]; then
  echo ""
  echo "Run with --fix to auto-repair: scripts/doctor.sh --fix"
fi

[ "$FAIL" -eq 0 ]
