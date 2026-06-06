#!/usr/bin/env bats
# 00_smoke.bats — Wave 0 foundation gate. Verifies the sandbox works.

load '../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "sandbox: HOME is a tmpdir and has a .eco skeleton" {
  [ -d "$HOME/.eco/bin" ]
  [ -d "$HOME/.eco/recipes" ]
  [ -x "$HOME/.eco/bin/eco" ]
  [ -x "$HOME/.eco/bin/eco-commander.15s.sh" ]
  [[ "$HOME" == /*eco-bats* ]]
}

@test "sandbox: stubs are first on PATH" {
  run command -v open
  assert_success
  [[ "$output" == "$ECO_TESTS_REAL/helpers/stubs/open" ]]
}

@test "sandbox: state.json fixture is present" {
  [ -f "$HOME/.eco/current/state.json" ]
  run jq -r '.snapshot_id' "$HOME/.eco/current/state.json"
  assert_success
  [ "$output" = "2026-04-18T00-00Z" ]
}

@test "eco help runs and prints usage" {
  run "$ECO_BIN" help
  assert_success
  assert_output_contains "eco"
  assert_output_contains "List recipes"
}

@test "eco list runs without error" {
  run "$ECO_BIN" list
  assert_success
  assert_output_contains "Eco Recipes"
}

@test "open stub records calls" {
  open http://example.com
  [ -s "$HOME/.stub-open.log" ]
  run cat "$HOME/.stub-open.log"
  assert_output_contains "http://example.com"
}

@test "gemini stub echoes canned response" {
  export STUB_GEMINI_OUTPUT="hello from stub"
  run gemini -p "anything"
  assert_success
  [ "$output" = "hello from stub" ]
}

@test "ollama stub simulates running state" {
  run ollama ps
  assert_success
  assert_output_contains "qwen2.5:3b"
}

@test "ollama stub simulates daemon down" {
  export STUB_OLLAMA_RUNNING=0
  run ollama ps
  assert_failure
}

@test "vm_stat stub is deterministic" {
  run vm_stat
  assert_success
  assert_output_contains "Pages free:"
}
