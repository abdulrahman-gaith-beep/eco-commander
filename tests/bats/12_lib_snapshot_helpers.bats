#!/usr/bin/env bats
# 12_lib_snapshot_helpers.bats — tests for scripts/lib/snapshot-helpers.sh
#
# Property tests for pure formatting functions extracted from usage-snapshot.sh.
# All functions are side-effect-free.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
  source "$REPO_ROOT/scripts/lib/snapshot-helpers.sh"
}

# ── humanize ─────────────────────────────────────────────────────────

@test "snapshot-helpers: humanize 0 → '0'" {
  [ "$(humanize 0)" = "0" ]
}

@test "snapshot-helpers: humanize 999 → '999'" {
  [ "$(humanize 999)" = "999" ]
}

@test "snapshot-helpers: humanize 1000 → '1.00K'" {
  [ "$(humanize 1000)" = "1.00K" ]
}

@test "snapshot-helpers: humanize 1500 → '1.50K'" {
  [ "$(humanize 1500)" = "1.50K" ]
}

@test "snapshot-helpers: humanize 1000000 → '1.00M'" {
  [ "$(humanize 1000000)" = "1.00M" ]
}

@test "snapshot-helpers: humanize 22000000 → '22.0M'" {
  [ "$(humanize 22000000)" = "22.0M" ]
}

@test "snapshot-helpers: humanize 1000000000 → '1.00B'" {
  [ "$(humanize 1000000000)" = "1.00B" ]
}

@test "snapshot-helpers: humanize 1000000000000 → '1.00T'" {
  [ "$(humanize 1000000000000)" = "1.00T" ]
}

@test "snapshot-helpers: humanize negative → absolute value" {
  [ "$(humanize -500)" = "500" ]
}

# ── bar_fill ─────────────────────────────────────────────────────────

@test "snapshot-helpers: bar_fill 0 → all empty" {
  [ "$(bar_fill 0)" = "░░░░░░░░░░░░░░░░░░░░" ]
}

@test "snapshot-helpers: bar_fill 100 → all filled" {
  [ "$(bar_fill 100)" = "████████████████████" ]
}

@test "snapshot-helpers: bar_fill 50 → half filled" {
  result=$(bar_fill 50)
  # 20 * 0.5 = 10 filled
  [ "$result" = "██████████░░░░░░░░░░" ]
}

@test "snapshot-helpers: bar_fill clamps above 100" {
  [ "$(bar_fill 150)" = "████████████████████" ]
}

@test "snapshot-helpers: bar_fill clamps below 0" {
  [ "$(bar_fill -10)" = "░░░░░░░░░░░░░░░░░░░░" ]
}

@test "snapshot-helpers: bar_fill always 20 characters" {
  for pct in 0 25 50 75 100; do
    result=$(bar_fill $pct)
    len=$(printf '%s' "$result" | wc -m | tr -d ' ')
    [ "$len" -eq 20 ] || {
      echo "bar_fill($pct) produced $len chars, expected 20: '$result'"
      return 1
    }
  done
}

# ── safe_pct ─────────────────────────────────────────────────────────

@test "snapshot-helpers: safe_pct normal → formatted" {
  [ "$(safe_pct 42.567)" = "42.6" ]
}

@test "snapshot-helpers: safe_pct clamps above 100" {
  [ "$(safe_pct 150)" = "100.0" ]
}

@test "snapshot-helpers: safe_pct clamps below 0" {
  [ "$(safe_pct -5)" = "0.0" ]
}

@test "snapshot-helpers: safe_pct empty → 0.0" {
  [ "$(safe_pct)" = "0.0" ]
}

# ── color_for ────────────────────────────────────────────────────────

@test "snapshot-helpers: color_for 0 → green" {
  [ "$(color_for 0)" = "#10b981" ]
}

@test "snapshot-helpers: color_for 74 → green" {
  [ "$(color_for 74)" = "#10b981" ]
}

@test "snapshot-helpers: color_for 75 → amber" {
  [ "$(color_for 75)" = "#f59e0b" ]
}

@test "snapshot-helpers: color_for 89 → amber" {
  [ "$(color_for 89)" = "#f59e0b" ]
}

@test "snapshot-helpers: color_for 90 → red" {
  [ "$(color_for 90)" = "#ef4444" ]
}

@test "snapshot-helpers: color_for 100 → red" {
  [ "$(color_for 100)" = "#ef4444" ]
}

# ── pace_glyph ───────────────────────────────────────────────────────

@test "snapshot-helpers: pace_glyph ahead → horse" {
  result=$(pace_glyph "ahead")
  [[ "$result" == *"🐎"* ]]
}

@test "snapshot-helpers: pace_glyph behind → turtle" {
  result=$(pace_glyph "behind")
  [[ "$result" == *"🐢"* ]]
}

@test "snapshot-helpers: pace_glyph other → empty" {
  result=$(pace_glyph "on_track")
  [ -z "$result" ]
}

# ── acct_label ───────────────────────────────────────────────────────

@test "snapshot-helpers: acct_label 1 → no multiplier" {
  result=$(acct_label 1 "Max 20x")
  [ "$result" = "Max 20x" ]
}

@test "snapshot-helpers: acct_label 2 → multiplier" {
  result=$(acct_label 2 "AI Ultra")
  [ "$result" = "AI Ultra × 2" ]
}

# ── _join ────────────────────────────────────────────────────────────

@test "snapshot-helpers: _join single → no separator" {
  result=$(_join "Claude")
  [ "$result" = "Claude" ]
}

@test "snapshot-helpers: _join multiple → separated" {
  result=$(_join "Claude" "Gemini" "Codex")
  [ "$result" = "Claude · Gemini · Codex" ]
}

# ── html_escape ──────────────────────────────────────────────────────

@test "snapshot-helpers: html_escape special chars" {
  result=$(echo '<b>"test" & done</b>' | html_escape)
  [[ "$result" == *"&lt;"* ]]
  [[ "$result" == *"&amp;"* ]]
  [[ "$result" == *"&quot;"* ]]
}

# ── target_mark ──────────────────────────────────────────────────────

@test "snapshot-helpers: target_mark renders div with percentage" {
  result=$(target_mark 50)
  [[ "$result" == *"left:50.0%"* ]]
  [[ "$result" == *"<div"* ]]
}

# ── source guard ─────────────────────────────────────────────────────

@test "snapshot-helpers: source guard prevents double-loading" {
  [ "$_ECO_LIB_SNAPSHOT_HELPERS_LOADED" = "1" ]
  # Second source should not error
  source "$REPO_ROOT/scripts/lib/snapshot-helpers.sh"
  [ "$_ECO_LIB_SNAPSHOT_HELPERS_LOADED" = "1" ]
}
