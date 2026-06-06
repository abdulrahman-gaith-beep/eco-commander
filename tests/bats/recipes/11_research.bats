#!/usr/bin/env bats
# 11_research.bats — exercises ~/.eco/recipes/research.sh

load '../../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "research.sh: DESC and INPUTS headers present" {
  run grep -E '^# DESC:' "$HOME/.eco/recipes/research.sh"
  assert_success
  run grep -E '^# INPUTS:' "$HOME/.eco/recipes/research.sh"
  assert_success
}

@test "research.sh: happy path creates dated markdown file with gemini content" {
  export STUB_GEMINI_OUTPUT=$'# Vertical Farming\n\nStub research brief body.'
  run bash "$HOME/.eco/recipes/research.sh" "vertical farming"
  assert_success

  local date_today
  date_today="$(date +%Y-%m-%d)"
  local outfile="$HOME/Documents/research/vertical-farming/${date_today}-vertical-farming.md"
  [ -f "$outfile" ] || {
    echo "Expected output file at $outfile"
    ls -la "$HOME/Documents/research/" 2>/dev/null || true
    return 1
  }
  run cat "$outfile"
  assert_success
  assert_output_contains "Vertical Farming"
  assert_output_contains "Stub research brief body."

  # Gemini was called; open stub was called on the outfile.
  assert_stub_called gemini
  assert_stub_called open
  assert_stub_args_contain open "$outfile"
}

@test "research.sh: gemini failure removes empty output file and prints auth hint" {
  export STUB_GEMINI_EXIT=7
  export STUB_GEMINI_STDERR="OAuth login required: raw provider details"

  run bash "$HOME/.eco/recipes/research.sh" "failed brief"
  assert_failure 7
  assert_output_contains "Gemini provider failed (rc=7)."
  assert_output_contains "authentication issue"
  assert_stub_called gemini

  local date_today
  date_today="$(date +%Y-%m-%d)"
  local outfile="$HOME/Documents/research/failed-brief/${date_today}-failed-brief.md"
  [ ! -e "$outfile" ] || {
    echo "Expected failed empty output file to be removed: $outfile"
    ls -la "$HOME/Documents/research/failed-brief"
    return 1
  }
}

@test "research.sh: slugifies 'Brackish Water Desalination!' to brackish-water-desalination" {
  export STUB_GEMINI_OUTPUT="brief"
  run bash "$HOME/.eco/recipes/research.sh" "Brackish Water Desalination!"
  assert_success

  local date_today
  date_today="$(date +%Y-%m-%d)"
  local outfile="$HOME/Documents/research/brackish-water-desalination/${date_today}-brackish-water-desalination.md"
  [ -f "$outfile" ] || {
    echo "Expected slugified output file at $outfile"
    ls -la "$HOME/Documents/research/" 2>/dev/null || true
    return 1
  }
}

@test "research.sh: non-Latin topic gets deterministic fallback slug" {
  export STUB_GEMINI_OUTPUT="brief"
  local topic="الاستزراع السمكي"
  local slug
  slug="topic-$(printf '%s' "$topic" | cksum | awk '{print $1}')"

  run bash "$HOME/.eco/recipes/research.sh" "$topic"
  assert_success

  local date_today
  date_today="$(date +%Y-%m-%d)"
  local outfile="$HOME/Documents/research/$slug/${date_today}-${slug}.md"
  [ -f "$outfile" ] || {
    echo "Expected fallback-slug output file at $outfile"
    find "$HOME/Documents/research" -maxdepth 2 -type f -print
    return 1
  }
}

@test "research.sh: missing gem-smart wrapper prints a helpful error" {
  # Minimal PATH without the stub dir and without /opt/homebrew/bin (real
  # gemini). Keeps standard utilities so tr/sed/date/mkdir still work.
  run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" ECO_GEM_SMART_BIN="$HOME/missing-gem-smart" bash "$HOME/.eco/recipes/research.sh" "anything"
  assert_failure
  assert_output_contains "gem-smart not found"
}
