#!/usr/bin/env bats
# 18_n8n_start.bats — tests for n8n-start.sh recipe
#
# Covers:
#   - --help shows usage
#   - Rejects unexpected arguments
#   - Errors gracefully when neither docker nor npx available
#   - pick_n8n_compose: finds explicit ECO_N8N_COMPOSE

load '../../helpers/common.bash'

setup() {
  eco_setup
  RECIPE="$HOME/.eco/recipes/n8n-start.sh"
  [ -f "$RECIPE" ] || skip "n8n-start.sh not available in sandbox"
  chmod +x "$RECIPE"
}

teardown() {
  eco_teardown
}

# ── Help ─────────────────────────────────────────────────────────────

@test "n8n-start: --help shows usage" {
  run bash "$RECIPE" --help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "n8n-start.sh"
}

@test "n8n-start: -h shows usage" {
  run bash "$RECIPE" -h
  assert_success
  assert_output_contains "Usage:"
}

# ── Argument validation ─────────────────────────────────────────────

@test "n8n-start: rejects unexpected arguments" {
  run bash "$RECIPE" some-random-arg
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not accept"* ]]
}

# ── Graceful failure ─────────────────────────────────────────────────

@test "n8n-start: errors when no docker or npx available" {
  # Keep basic shell tools available while hiding Homebrew/user-installed docker/npx.
  run env PATH="$HOME/.eco/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$RECIPE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Neither"* ]] || [[ "$output" == *"unavailable"* ]] || {
    echo "Expected error about missing docker/npx"
    echo "Got: $output"
    return 1
  }
}

# ── ECO_N8N_COMPOSE ──────────────────────────────────────────────────

@test "n8n-start: ECO_N8N_COMPOSE pointing to missing file errors" {
  # Stub docker to be available but fail
  cat > "$HOME/.eco/bin/docker" <<'SH'
#!/bin/bash
exit 1
SH
  chmod +x "$HOME/.eco/bin/docker"
  export PATH="$HOME/.eco/bin:$PATH"
  export ECO_N8N_COMPOSE="/nonexistent/compose.yml"
  run /bin/bash "$RECIPE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"Error"* ]] || {
    echo "Expected error about missing compose file"
    echo "Got: $output"
    return 1
  }
}
