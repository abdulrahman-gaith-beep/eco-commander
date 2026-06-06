#!/usr/bin/env bats
# 04_switch_profile.bats — profile switcher safety/transaction semantics.

load '../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

_write_profile() {
  local name="${1:-core}"
  mkdir -p "$HOME/.ai-ecosystem/profiles"
  cat > "$HOME/.ai-ecosystem/profiles/${name}.mcpServers.json" <<'JSON'
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    }
  }
}
JSON
}

@test "switch-profile: valid profile writes Cursor config and current profile" {
  _write_profile core
  mkdir -p "$HOME/.cursor"

  run bash "$SWITCH_PROFILE_BIN" core
  assert_success
  assert_output_contains "Cursor"
  assert_output_contains "Summary: 1 updated"
  [ -f "$HOME/.cursor/mcp.json" ]
  [ "$(cat "$HOME/.ai-ecosystem/.current-profile")" = "core" ]
}

@test "switch-profile: malformed profile JSON is rejected before writes" {
  mkdir -p "$HOME/.ai-ecosystem/profiles" "$HOME/.cursor"
  printf '{bad json\n' > "$HOME/.ai-ecosystem/profiles/core.mcpServers.json"
  rm -f "$HOME/.ai-ecosystem/.current-profile"

  run bash "$SWITCH_PROFILE_BIN" core
  assert_failure 1
  assert_output_contains "invalid profile JSON"
  [ ! -e "$HOME/.cursor/mcp.json" ]
  [ ! -e "$HOME/.ai-ecosystem/.current-profile" ]
}

@test "switch-profile: configured target failure does not publish current profile" {
  _write_profile core
  mkdir -p "$HOME/.cursor" "$HOME/.gemini"
  printf '{bad settings\n' > "$HOME/.gemini/settings.json"
  rm -f "$HOME/.ai-ecosystem/.current-profile"

  run bash "$SWITCH_PROFILE_BIN" core
  assert_failure 2
  assert_output_contains "Gemini CLI"
  assert_output_contains "Active profile was NOT changed"
  [ -f "$HOME/.cursor/mcp.json" ]
  [ ! -e "$HOME/.ai-ecosystem/.current-profile" ]
}

@test "switch-profile: profile validation follows files in profiles directory" {
  _write_profile custom
  mkdir -p "$HOME/.cursor"
  rm -f "$HOME/.ai-ecosystem/.current-profile"

  run bash "$SWITCH_PROFILE_BIN" custom
  assert_success
  assert_output_contains "Switching to profile: custom"
  [ "$(cat "$HOME/.ai-ecosystem/.current-profile")" = "custom" ]
}
