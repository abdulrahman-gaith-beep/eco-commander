#!/usr/bin/env bats
# 14_swarm.bats — exercises ~/.eco/recipes/swarm.sh
# Fans out N parallel Gemini agents (stubbed) and synthesizes SUMMARY.md.

load '../../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "swarm.sh: DESC/INPUTS/OUTPUT/USES/HUMAN headers present" {
  run grep -E '^# DESC:'   "$HOME/.eco/recipes/swarm.sh"
  assert_success
  run grep -E '^# INPUTS:' "$HOME/.eco/recipes/swarm.sh"
  assert_success
  run grep -E '^# OUTPUT:' "$HOME/.eco/recipes/swarm.sh"
  assert_success
  run grep -E '^# USES:'   "$HOME/.eco/recipes/swarm.sh"
  assert_success
  run grep -E '^# HUMAN:'  "$HOME/.eco/recipes/swarm.sh"
  assert_success
}

@test "swarm.sh: N=1 is rejected with 'N must be 2-15'" {
  run bash "$HOME/.eco/recipes/swarm.sh" "a task" 1
  assert_failure
  assert_output_contains "N must be 2-15"
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called with invalid N"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "swarm.sh: N=16 is rejected with 'N must be 2-15'" {
  run bash "$HOME/.eco/recipes/swarm.sh" "a task" 16
  assert_failure
  assert_output_contains "N must be 2-15"
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called with invalid N"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "swarm.sh: non-numeric N is rejected before gemini runs" {
  run bash "$HOME/.eco/recipes/swarm.sh" "a task" nope
  assert_failure
  assert_output_contains "N must be 2-15"
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called with invalid N"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "swarm.sh: N>=10 keeps local models resident" {
  export STUB_GEMINI_OUTPUT="stub agent output"
  run bash "$HOME/.eco/recipes/swarm.sh" "large task" 10
  assert_success
  assert_output_contains "N>=10 — keeping local models resident; no pre-swarm unload."
  assert_output_not_contains "running ai-clear"
}

@test "swarm.sh: happy path (N=3) creates agent outputs and SUMMARY.md" {
  export STUB_GEMINI_OUTPUT="stub agent output"
  run bash "$HOME/.eco/recipes/swarm.sh" "short task" 3
  assert_success
  assert_output_contains "=== Swarm: 3 agents ==="
  assert_output_contains "Task: short task"
  assert_output_contains "=== All 3 agents complete ==="

  # Locate the timestamped workspace under Documents/research/_swarm
  local swarm_root="$HOME/Documents/research/_swarm"
  [ -d "$swarm_root" ] || {
    echo "Expected swarm root at $swarm_root"
    return 1
  }
  local ws
  ws="$(ls -1 "$swarm_root" | head -n1)"
  [ -n "$ws" ] || {
    echo "Expected a timestamped subdir under $swarm_root"
    ls -la "$swarm_root"
    return 1
  }
  local work="$swarm_root/$ws"
  [ -f "$work/agent-1.md" ]
  [ -f "$work/agent-2.md" ]
  [ -f "$work/agent-3.md" ]
  [ -f "$work/SUMMARY.md" ]

  # gemini stub should have been called exactly 3 times (one per agent).
  # Each call writes `echo "gemini $*"` — since prompts contain newlines,
  # a single call spans multiple lines in the log. Count invocations by
  # counting lines that start with `gemini `.
  assert_stub_called gemini
  run grep -c '^gemini ' "$HOME/.stub-gemini.log"
  assert_success
  [ "$output" = "3" ] || {
    echo "Expected gemini to be called 3 times, got: $output"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "swarm.sh: failed agents are reported and make recipe fail" {
  export STUB_GEMINI_EXIT=6
  export STUB_GEMINI_STDERR="quota exceeded in stub"

  run bash "$HOME/.eco/recipes/swarm.sh" "failing task" 3
  assert_failure 1
  assert_output_contains "Swarm failed: 3 of 3 agents failed."
  assert_output_contains "agent-1 log (rc=6)"
  assert_output_contains "quota exceeded in stub"
  assert_output_not_contains "=== All 3 agents complete ==="
  assert_stub_called gemini
}

@test "swarm.sh: empty agent outputs are reported and make recipe fail" {
  cat > "$HOME/empty-gem-smart" <<'SH'
#!/usr/bin/env bash
echo "gemini $*" >> "$HOME/.stub-gemini.log"
exit 0
SH
  chmod +x "$HOME/empty-gem-smart"
  export ECO_GEM_SMART_BIN="$HOME/empty-gem-smart"

  run bash "$HOME/.eco/recipes/swarm.sh" "empty output task" 3
  assert_failure 1
  assert_output_contains "Swarm failed: 3 of 3 agents failed."
  assert_output_contains "produced no output"
  assert_output_not_contains "=== All 3 agents complete ==="
  assert_stub_called gemini
}

@test "swarm.sh: SUMMARY.md synthesizes all three agent outputs" {
  export STUB_GEMINI_OUTPUT="agent body content"
  run bash "$HOME/.eco/recipes/swarm.sh" "synth task" 3
  assert_success

  local swarm_root="$HOME/Documents/research/_swarm"
  local ws
  ws="$(ls -1 "$swarm_root" | head -n1)"
  local summary="$swarm_root/$ws/SUMMARY.md"
  [ -f "$summary" ]

  run cat "$summary"
  assert_success
  assert_output_contains "# Swarm Summary"
  assert_output_contains "**Task:** synth task"
  assert_output_contains "**Agents:** 3"
  assert_output_contains "## Agent 1"
  assert_output_contains "## Agent 2"
  assert_output_contains "## Agent 3"
  # The stub output should appear (once per agent body inlined into SUMMARY).
  run grep -c "agent body content" "$summary"
  assert_success
  [ "$output" -ge 3 ] || {
    echo "Expected agent body content to appear >=3 times in SUMMARY, got $output"
    cat "$summary"
    return 1
  }
}
