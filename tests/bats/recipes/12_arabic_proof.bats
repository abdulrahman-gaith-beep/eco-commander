#!/usr/bin/env bats
# 12_arabic_proof.bats — exercises ~/.eco/recipes/arabic-proof.sh

load '../../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "arabic-proof.sh: DESC/INPUTS/USES/HUMAN headers present" {
  run grep -E '^# DESC:' "$HOME/.eco/recipes/arabic-proof.sh"
  assert_success
  run grep -E '^# INPUTS:' "$HOME/.eco/recipes/arabic-proof.sh"
  assert_success
  run grep -E '^# USES:' "$HOME/.eco/recipes/arabic-proof.sh"
  assert_success
  run grep -E '^# HUMAN:' "$HOME/.eco/recipes/arabic-proof.sh"
  assert_success
}

@test "arabic-proof.sh: file input routes to ollama with qwen3.6:latest" {
  export STUB_OLLAMA_OUTPUT="## التصحيح
نص مصحح"
  echo "نص عربي للتصحيح" > "$HOME/text.txt"
  run bash "$HOME/.eco/recipes/arabic-proof.sh" "$HOME/text.txt"
  assert_success
  assert_output_contains "routing: local qwen3.6:latest"
  assert_output_contains "نص مصحح"
  assert_stub_called ollama
  assert_stub_args_contain ollama "run qwen3.6:latest"
}

@test "arabic-proof.sh: stdin input invokes ollama with qwen3.6:latest" {
  export STUB_OLLAMA_OUTPUT="مصحح"
  run bash -c 'echo "نص" | bash "$HOME/.eco/recipes/arabic-proof.sh"'
  assert_success
  assert_output_contains "مصحح"
  assert_stub_called ollama
  assert_stub_args_contain ollama "run qwen3.6:latest"
}

@test "arabic-proof.sh: missing ollama binary errors with install hint" {
  # Use a minimal PATH with only core system utilities — excludes both the
  # test stub dir and any real ollama install (e.g. /usr/local/bin).
  echo "نص" > "$HOME/text.txt"
  run env PATH="/usr/bin:/bin" bash "$HOME/.eco/recipes/arabic-proof.sh" "$HOME/text.txt"
  assert_failure
  assert_output_contains "ollama not installed"
}

@test "arabic-proof.sh: empty input aborts with 'No text.'" {
  : > "$HOME/empty.txt"
  run bash -c 'bash "$HOME/.eco/recipes/arabic-proof.sh" "$HOME/empty.txt" < /dev/null'
  assert_failure
  assert_output_contains "No text."
  [ ! -s "$HOME/.stub-ollama.log" ] || {
    echo "ollama should not have been called on empty input"
    cat "$HOME/.stub-ollama.log"
    return 1
  }
}

@test "arabic-proof.sh: auto-unloads model on exit only when requested" {
  # Model NOT already loaded (default stub state: qwen2.5:3b is loaded, not qwen3.6)
  export ECO_ARABIC_PROOF_AUTO_UNLOAD=1
  export STUB_OLLAMA_LOADED="qwen2.5:3b"
  export STUB_OLLAMA_OUTPUT="ok"
  echo "نص" > "$HOME/text.txt"
  run bash "$HOME/.eco/recipes/arabic-proof.sh" "$HOME/text.txt"
  assert_success
  # Trap should have fired ollama stop qwen3.6:latest on exit
  assert_stub_args_contain ollama "stop qwen3.6:latest"
}

@test "arabic-proof.sh: does NOT unload model that was already loaded before" {
  # Pre-condition: selected model already loaded by the user
  export STUB_OLLAMA_LOADED="qwen3.6:latest"
  export STUB_OLLAMA_OUTPUT="ok"
  echo "نص" > "$HOME/text.txt"
  run bash "$HOME/.eco/recipes/arabic-proof.sh" "$HOME/text.txt"
  assert_success
  # Trap should NOT have unloaded — user wanted it loaded
  run grep -c "^ollama stop" "$HOME/.stub-ollama.log"
  [ "$output" = "0" ] || {
    echo "Expected NO 'ollama stop' calls; got $output"
    cat "$HOME/.stub-ollama.log"
    return 1
  }
}

@test "arabic-proof.sh: default keeps newly loaded model resident" {
  export STUB_OLLAMA_LOADED="qwen2.5:3b"
  export STUB_OLLAMA_OUTPUT="ok"
  echo "نص" > "$HOME/text.txt"
  run bash "$HOME/.eco/recipes/arabic-proof.sh" "$HOME/text.txt"
  assert_success
  run grep -c "^ollama stop" "$HOME/.stub-ollama.log"
  [ "$output" = "0" ] || {
    echo "Expected default to keep model resident; got $output stop calls"
    cat "$HOME/.stub-ollama.log"
    return 1
  }
}
