#!/usr/bin/env bash
# scripts/lib/snapshot-helpers.sh — Pure helper functions for usage-snapshot.sh
#
# @category  library
# @depends   awk, python3
# @sourced-by usage-snapshot.sh
#
# All functions here are pure (no side effects, no file I/O, no network).
# They format numbers, build text/HTML fragments, and compute colors.
#
# Source guard
[ "${_ECO_LIB_SNAPSHOT_HELPERS_LOADED:-}" = "1" ] && return 0
_ECO_LIB_SNAPSHOT_HELPERS_LOADED=1

# ── humanize ─────────────────────────────────────────────────────────
# Convert a raw number to human-readable form (e.g., 1500 → "1.50K").
# Shared with the SwiftBar widget's rendering logic.
humanize() {
  awk -v n="$1" 'BEGIN{
    if (n+0 == 0) { print "0"; exit }
    abs = (n < 0) ? -n : n;
    units[0]=""; units[1]="K"; units[2]="M"; units[3]="B"; units[4]="T";
    i = 0;
    while (abs >= 1000 && i < 4) { abs /= 1000.0; i++ }
    if (i == 0)         printf "%d", abs;
    else if (abs >= 100) printf "%.0f%s", abs, units[i];
    else if (abs >= 10)  printf "%.1f%s", abs, units[i];
    else                 printf "%.2f%s", abs, units[i];
  }'
}

# ── bar_fill ─────────────────────────────────────────────────────────
# Render a 20-char progress bar using █ and ░ for a given percentage.
bar_fill() {
  awk -v p="$1" 'BEGIN{
    w=20; pp=p+0; if(pp>100)pp=100; if(pp<0)pp=0;
    f=int((pp/100)*w + 0.5); if(f>w)f=w;
    s=""; for(i=0;i<f;i++)s=s"█"; for(i=f;i<w;i++)s=s"░"; print s;
  }'
}

# ── safe_pct ─────────────────────────────────────────────────────────
# Clamp a number to [0, 100] and format as "%.1f".
safe_pct() {
  awk -v n="${1:-0}" 'BEGIN{p=n+0; if(p<0)p=0; if(p>100)p=100; printf "%.1f", p}'
}

# ── html_escape ──────────────────────────────────────────────────────
# Escape HTML special characters via stdin → stdout.
html_escape() {
  python3 -c 'import html, sys; sys.stdout.write(html.escape(sys.stdin.read(), quote=True))'
}

# ── color_for ────────────────────────────────────────────────────────
# Return a hex color for a usage percentage (green/amber/red).
color_for() {
  awk -v p="$1" 'BEGIN{
    pp=p+0;
    if (pp>=90) print "#ef4444";
    else if (pp>=75) print "#f59e0b";
    else print "#10b981";
  }'
}

# ── pace_glyph ───────────────────────────────────────────────────────
# Return a pace indicator emoji: 🐎 (ahead), 🐢 (behind), or empty.
pace_glyph() {
  local label="$1"
  if [ "$label" = "ahead" ]; then echo " 🐎";
  elif [ "$label" = "behind" ]; then echo " 🐢";
  else echo ""; fi
}

# ── target_mark ──────────────────────────────────────────────────────
# Return an HTML div for a target-line overlay on a progress bar.
target_mark() {
  local pct
  pct="$(safe_pct "${1:-0}")"
  echo "<div style=\"position:absolute; left:${pct}%; top:0; bottom:0; width:2px; background:#fff; opacity:0.5;\"></div>"
}

# ── acct_label ───────────────────────────────────────────────────────
# Format an account label, appending "× N" if N > 1.
acct_label() {
  local n="$1"
  case "$n" in ""|*[!0-9]*) n=0 ;; *) n=$((10#$n)) ;; esac
  if [ "$n" -gt 1 ]; then printf "%s × %d" "$2" "$n"; else printf "%s" "$2"; fi
}

# ── _join ────────────────────────────────────────────────────────────
# Join arguments with " · " separator.
_join() {
  local sep=" · " first=1
  for s in "$@"; do
    if [ "$first" -eq 1 ]; then printf '%s' "$s"; first=0
    else printf '%s%s' "$sep" "$s"; fi
  done
}
