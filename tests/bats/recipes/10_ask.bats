#!/usr/bin/env bats
# 10_ask.bats — exercises ~/.eco/recipes/ask.sh

load '../../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "ask.sh: DESC and INPUTS headers present" {
  run grep -E '^# DESC:' "$HOME/.eco/recipes/ask.sh"
  assert_success
  run grep -E '^# INPUTS:' "$HOME/.eco/recipes/ask.sh"
  assert_success
}

@test "ask.sh: happy path routes to gemini with -p and the question" {
  export STUB_GEMINI_OUTPUT="hi from gemini"
  run bash "$HOME/.eco/recipes/ask.sh" "hello"
  assert_success
  assert_output_contains "hi from gemini"
  assert_stub_called gemini
  assert_stub_args_contain gemini "-p hello"
  [ ! -s "$HOME/.stub-ollama.log" ] || {
    echo "ollama should not have been called on happy path"
    cat "$HOME/.stub-ollama.log"
    return 1
  }
}

@test "ask.sh: gemini failure prints sanitized quota hint" {
  export STUB_GEMINI_EXIT=9
  export STUB_GEMINI_STDERR="429 QUOTA_EXHAUSTED: raw provider details"

  run bash "$HOME/.eco/recipes/ask.sh" "hello"
  assert_failure 9
  assert_output_contains "Gemini provider failed (rc=9)."
  assert_output_contains "quota or rate limit"
  assert_stub_called gemini
}

@test "ask.sh: privacy cue (English 'private') routes to ollama, not gemini" {
  export STUB_OLLAMA_OUTPUT="local answer"
  run bash "$HOME/.eco/recipes/ask.sh" "share my private key"
  assert_success
  assert_output_contains "routing: local qwen3.6:latest"
  assert_output_contains "local answer"
  assert_stub_called ollama
  assert_stub_args_contain ollama "run qwen3.6:latest"
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called on privacy cue"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "ask.sh: privacy cue (Arabic خاص) routes to ollama" {
  export STUB_OLLAMA_OUTPUT="محلي"
  run bash "$HOME/.eco/recipes/ask.sh" "خاص بي"
  assert_success
  assert_output_contains "routing: local qwen3.6:latest"
  assert_stub_called ollama
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called on Arabic privacy cue"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "ask.sh: no question (empty args, no stdin) exits 0 and calls no model" {
  # Spec: "empty args, no stdin → exits 0 with no output". Wave 3 fixed
  # the `read -r Q` under `set -eu` by appending `|| Q=""` so EOF is
  # treated as empty input and the empty-guard on the next line runs.
  run bash -c 'bash "$HOME/.eco/recipes/ask.sh" < /dev/null'
  assert_success
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called with empty input"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
  [ ! -s "$HOME/.stub-ollama.log" ] || {
    echo "ollama should not have been called with empty input"
    cat "$HOME/.stub-ollama.log"
    return 1
  }
}

@test "ask.sh: missing gemini CLI prints helpful error" {
  # PATH contains only standard system utilities — no stub dir, no
  # /opt/homebrew/bin (where the real gemini lives on this machine),
  # no $HOME/bin. That way gem-smart cannot be found.
  run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" ECO_GEM_SMART_BIN="gem-smart-missing" bash "$HOME/.eco/recipes/ask.sh" "any question"
  assert_failure
  assert_output_contains "gem-smart not found"
}
