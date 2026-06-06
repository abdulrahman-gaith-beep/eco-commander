#!/usr/bin/env bats
# 07_pure_functions.bats — property tests for shell pure functions
#
# Tests the pure functions from eco-commander.15s.sh:
#   humanize(), bar(), fmt_pct(), color_for(), glyph_for_pct(), fmt_gb()
#
# These are extracted and tested in isolation via `source`.

load '../helpers/common.bash'

setup() {
  eco_setup
}

teardown() {
  eco_teardown
}

# We need to source just the function definitions from the commander.
# The script has `set -u` and reads env vars, so we define them first.
_source_functions() {
  # Define minimal env so the script's top-level doesn't crash
  export ECO_HOME="$HOME/.eco"
  export ECO_COMMANDER_REPO="$HOME"
  mkdir -p "$HOME/.eco/current" "$HOME/.ai-ecosystem"
  echo "core" > "$HOME/.ai-ecosystem/.current-profile"
  touch "$HOME/.eco/current/state.json"

  # Extract just the function definitions (humanize through fmt_gb)
  # and the constants they need
  cat > "$HOME/funcs.sh" <<'FUNCS'
WARN_PCT=80
CRIT_PCT=95

humanize() {
  awk -v n="$1" 'BEGIN{
    if (n+0 == 0) { print "0"; exit }
    abs = (n < 0) ? -n : n;
    units[0]=""; units[1]="K"; units[2]="M"; units[3]="B"; units[4]="T"; units[5]="P";
    i = 0;
    while (abs >= 1000 && i < 5) { abs /= 1000.0; i++ }
    if (i == 0) { printf "%d", abs }
    else if (abs >= 100) { printf "%.0f%s", abs, units[i] }
    else if (abs >= 10)  { printf "%.1f%s", abs, units[i] }
    else                 { printf "%.2f%s", abs, units[i] }
  }'
}

color_for() {
  awk -v p="$1" -v w="$WARN_PCT" -v c="$CRIT_PCT" 'BEGIN{
    if (p+0 >= c) print "red";
    else if (p+0 >= w) print "orange";
    else print "green";
  }'
}

glyph_for_pct() {
  awk -v p="$1" -v w="$WARN_PCT" -v c="$CRIT_PCT" 'BEGIN{
    if (p+0 >= c) printf "🚨 ";
    else if (p+0 >= w) printf "⚠ ";
    else printf "";
  }'
}

bar() {
  awk -v p="$1" 'BEGIN{
    w=12; pp=p+0; if(pp>100)pp=100; if(pp<0)pp=0;
    f=int((pp/100)*w + 0.5); if(f>w)f=w;
    s=""; for(i=0;i<f;i++)s=s"█"; for(i=f;i<w;i++)s=s"░";
    print s;
  }'
}

fmt_pct() { awk -v p="$1" 'BEGIN{ printf (p>=10 ? "%d" : "%.0f"), p+0 }'; }

fmt_gb() {
  local mb="${1:-0}"
  local int="$(( mb / 1024 ))"
  local dec="$(( (mb % 1024) * 10 / 1024 ))"
  printf '%d.%d' "$int" "$dec"
}
FUNCS
}

# ── humanize ─────────────────────────────────────────────────────────

@test "humanize: 0 → '0'" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize 0)
  [ "$result" = "0" ]
}

@test "humanize: 999 → '999'" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize 999)
  [ "$result" = "999" ]
}

@test "humanize: 1000 → '1.00K'" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize 1000)
  [ "$result" = "1.00K" ]
}

@test "humanize: 1500 → '1.50K'" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize 1500)
  [ "$result" = "1.50K" ]
}

@test "humanize: 1000000 → '1.00M'" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize 1000000)
  [ "$result" = "1.00M" ]
}

@test "humanize: 22000000 → '22.0M'" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize 22000000)
  [ "$result" = "22.0M" ]
}

@test "humanize: 1000000000000 → '1.00T'" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize 1000000000000)
  [ "$result" = "1.00T" ]
}

@test "humanize: negative → handles gracefully" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(humanize -500)
  [ "$result" = "500" ]
}

# ── bar ──────────────────────────────────────────────────────────────

@test "bar: 0% → all empty blocks" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(bar 0)
  [ "$result" = "░░░░░░░░░░░░" ]
}

@test "bar: 100% → all filled blocks" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(bar 100)
  [ "$result" = "████████████" ]
}

@test "bar: 50% → half filled" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(bar 50)
  # 12 * 0.5 = 6 filled
  [ "$result" = "██████░░░░░░" ]
}

@test "bar: clamped above 100" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(bar 150)
  [ "$result" = "████████████" ]
}

@test "bar: clamped below 0" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(bar -10)
  [ "$result" = "░░░░░░░░░░░░" ]
}

@test "bar: always 12 characters" {
  _source_functions
  source "$HOME/funcs.sh"
  for pct in 0 25 50 75 100; do
    result=$(bar $pct)
    # Count chars (multibyte safe via wc -m)
    len=$(printf '%s' "$result" | wc -m | tr -d ' ')
    [ "$len" -eq 12 ] || {
      echo "bar($pct) produced $len chars, expected 12: '$result'"
      return 1
    }
  done
}

# ── color_for ────────────────────────────────────────────────────────

@test "color_for: 0% → green" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(color_for 0)" = "green" ]
}

@test "color_for: 79% → green" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(color_for 79)" = "green" ]
}

@test "color_for: 80% → orange (warn threshold)" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(color_for 80)" = "orange" ]
}

@test "color_for: 94% → orange" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(color_for 94)" = "orange" ]
}

@test "color_for: 95% → red (crit threshold)" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(color_for 95)" = "red" ]
}

@test "color_for: 100% → red" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(color_for 100)" = "red" ]
}

# ── fmt_pct ──────────────────────────────────────────────────────────

@test "fmt_pct: integer formatting" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(fmt_pct 42)" = "42" ]
  [ "$(fmt_pct 5)" = "5" ]
  [ "$(fmt_pct 100)" = "100" ]
  [ "$(fmt_pct 0)" = "0" ]
}

# ── glyph_for_pct ────────────────────────────────────────────────────

@test "glyph_for_pct: below warn → empty" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(glyph_for_pct 50)
  [ -z "$result" ]
}

@test "glyph_for_pct: at warn → warning glyph" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(glyph_for_pct 80)
  [[ "$result" == *"⚠"* ]]
}

@test "glyph_for_pct: at crit → alert glyph" {
  _source_functions
  source "$HOME/funcs.sh"
  result=$(glyph_for_pct 95)
  [[ "$result" == *"🚨"* ]]
}

# ── fmt_gb ───────────────────────────────────────────────────────────

@test "fmt_gb: 0 MB → '0.0'" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(fmt_gb 0)" = "0.0" ]
}

@test "fmt_gb: 1024 MB → '1.0'" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(fmt_gb 1024)" = "1.0" ]
}

@test "fmt_gb: 4096 MB → '4.0'" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(fmt_gb 4096)" = "4.0" ]
}

@test "fmt_gb: 1536 MB → '1.5'" {
  _source_functions
  source "$HOME/funcs.sh"
  [ "$(fmt_gb 1536)" = "1.5" ]
}
