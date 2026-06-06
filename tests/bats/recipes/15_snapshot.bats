#!/usr/bin/env bats
# 15_snapshot.bats — exercises ~/.eco/recipes/snapshot.sh
# Runs the 7-agent Gemini ecosystem snapshot against a stubbed prompt library.

load '../../helpers/common.bash'

setup() {
  eco_setup
  # snapshot.sh shells out to a Gemini wrapper (gem-smart). Point it at the
  # hermetic gemini stub so the snapshot runs entirely inside the sandbox and
  # records calls to .stub-gemini.log.
  export ECO_GEM_SMART_BIN="$ECO_TESTS_REAL/helpers/stubs/gemini"
}
teardown() { eco_teardown; }

# Populate the sandbox with a minimal but complete prompt library: _SHARED.md
# plus the 7 layer prompts snapshot.sh iterates over.
_populate_prompt_library() {
  local dir="$HOME/.eco/ecosystem-audit/prompts"
  mkdir -p "$dir"
  echo "shared preamble" > "$dir/_SHARED.md"
  for p in GA-hardware-llm GB-ai-clients GC-mcp GD-hooks-plugins \
           GE-agents-memory GF-toolkit-projects-external GG-wiring-behavior; do
    echo "prompt body for $p" > "$dir/${p}.md"
  done
}

@test "snapshot.sh: DESC and INPUTS headers present" {
  run grep -E '^# DESC:'   "$HOME/.eco/recipes/snapshot.sh"
  assert_success
  run grep -E '^# INPUTS:' "$HOME/.eco/recipes/snapshot.sh"
  assert_success
}

@test "snapshot.sh: missing prompt library exits with 'Prompt library not found'" {
  # Sandbox creates the prompts dir as an empty directory. The source checks
  # for the directory's existence (not whether it has files), so remove it
  # to exercise the 'not found' branch deterministically.
  rm -rf "$HOME/.eco/ecosystem-audit/prompts"

  run bash "$HOME/.eco/recipes/snapshot.sh"
  assert_failure
  assert_output_contains "Prompt library not found"
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called when prompt library is missing"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "snapshot.sh: missing gem-smart falls back to plain gemini" {
  _populate_prompt_library
  export STUB_GEMINI_OUTPUT="layer stub body"

  run env ECO_GEM_SMART_BIN="$HOME/missing-gem-smart" bash "$HOME/.eco/recipes/snapshot.sh"
  assert_success
  assert_output_contains "Current snapshot now points to:"
  assert_stub_called gemini
  run grep -c '^gemini ' "$HOME/.stub-gemini.log"
  assert_success
  [ "$output" = "7" ] || {
    echo "Expected fallback gemini to be called 7 times, got: $output"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "snapshot.sh: pre-existing timestamp dir causes 'already exists' exit" {
  _populate_prompt_library
  # Reserve the minute-precision timestamp BEFORE invoking the script so the
  # duplicate-dir check trips. snapshot.sh uses `date +%Y-%m-%dT%H-%MZ`.
  local ts
  ts="$(date +%Y-%m-%dT%H-%MZ)"
  mkdir -p "$HOME/.eco/snapshots/$ts"

  run bash "$HOME/.eco/recipes/snapshot.sh"
  assert_failure
  assert_output_contains "already exists"
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called when snapshot dir already exists"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "snapshot.sh: active lock prevents concurrent snapshot runs" {
  _populate_prompt_library
  mkdir -p "$HOME/.eco/.snapshot.lock"
  echo "$$" > "$HOME/.eco/.snapshot.lock/pid"

  run bash "$HOME/.eco/recipes/snapshot.sh"
  assert_failure
  assert_output_contains "Snapshot already running"
  [ ! -s "$HOME/.stub-gemini.log" ] || {
    echo "gemini should not have been called while lock is active"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "snapshot.sh: happy path writes 7 layer outputs and calls gemini 7x" {
  _populate_prompt_library
  export STUB_GEMINI_OUTPUT="layer stub body"

  run bash "$HOME/.eco/recipes/snapshot.sh"
  assert_success
  assert_output_contains "=== Eco snapshot:"
  assert_output_contains "=== Scans done"
  assert_output_contains "=== Assembling current snapshot ==="
  assert_output_contains "Current snapshot now points to:"

  # Find the snapshot dir the script created (should be exactly one).
  local snap_root="$HOME/.eco/snapshots"
  local ts
  ts="$(ls -1 "$snap_root" | head -n1)"
  [ -n "$ts" ] || {
    echo "Expected a timestamped snapshot dir under $snap_root"
    ls -la "$snap_root"
    return 1
  }
  local layers="$snap_root/$ts/layers"
  [ -d "$layers" ]
  for p in GA-hardware-llm GB-ai-clients GC-mcp GD-hooks-plugins \
           GE-agents-memory GF-toolkit-projects-external GG-wiring-behavior; do
    [ -f "$layers/${p}.md" ] || {
      echo "Expected layer output $layers/${p}.md"
      ls -la "$layers"
      return 1
    }
  done

  # Each call writes `echo "gemini $*"` and prompts contain newlines, so a
  # single call can span multiple log lines. Count invocations by lines
  # starting with `gemini `.
  assert_stub_called gemini
  run grep -c '^gemini ' "$HOME/.stub-gemini.log"
  assert_success
  [ "$output" = "7" ] || {
    echo "Expected gemini to be called 7 times, got: $output"
    cat "$HOME/.stub-gemini.log"
    return 1
  }
}

@test "snapshot.sh: happy path assembles state, map, dashboard, and current symlink" {
  _populate_prompt_library
  export STUB_GEMINI_OUTPUT=$'Layer ok\nWarning: one stubbed issue for parser coverage'

  run bash "$HOME/.eco/recipes/snapshot.sh"
  assert_success

  [ -L "$HOME/.eco/current" ] || {
    echo "Expected current to be a symlink"
    ls -la "$HOME/.eco"
    return 1
  }
  [ -f "$HOME/.eco/current/state.json" ]
  [ -f "$HOME/.eco/current/map.md" ]
  [ -f "$HOME/.eco/current/dashboard.html" ]

  run bash "$HOME/.eco/bin/eco-commander.15s.sh" --cli
  assert_success
  assert_output_contains "7 Alerts"
  assert_output_contains "Snapshot:"

  run jq -r '.layers.GA_hardware_llm.issues[0].source_layer' "$HOME/.eco/current/state.json"
  assert_success
  [ "$output" = "GA-hardware-llm" ] || {
    echo "Expected source-layer issue provenance, got: $output"
    return 1
  }

  run jq -r '.layers.Linf_wiring.note' "$HOME/.eco/current/state.json"
  assert_success
  assert_output_contains "Compatibility aggregate"
}

@test "snapshot.sh: timed-out layers are reported and make recipe fail" {
  _populate_prompt_library
  export STUB_GEMINI_SLEEP=3

  run env GEMINI_LAYER_TIMEOUT_SEC=1 bash "$HOME/.eco/recipes/snapshot.sh"
  assert_failure 1
  assert_output_contains "Snapshot failed: 7 layer(s) failed."
  assert_output_contains "rc=124"
  assert_output_contains "TIMEOUT:"
  [ ! -L "$HOME/.eco/current" ] || {
    echo "current should not be repointed after failed layer scans"
    ls -la "$HOME/.eco/current"
    return 1
  }
}

@test "snapshot.sh: output directory contains exactly 7 .md files under layers/" {
  _populate_prompt_library
  run bash "$HOME/.eco/recipes/snapshot.sh"
  assert_success

  local snap_root="$HOME/.eco/snapshots"
  local ts
  ts="$(ls -1 "$snap_root" | head -n1)"
  local layers="$snap_root/$ts/layers"
  [ -d "$layers" ]

  run bash -c "ls -1 '$layers'/*.md 2>/dev/null | wc -l"
  assert_success
  [ "${output// /}" = "7" ] || {
    echo "Expected 7 .md files in $layers, got: $output"
    ls -la "$layers"
    return 1
  }
}
