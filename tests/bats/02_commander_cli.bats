#!/usr/bin/env bats
# 02_commander_cli.bats — exercise eco-commander.15s.sh in CLI + SwiftBar modes.

load '../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "commander --cli prints CLI header banner" {
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "Eco Commander (CLI)"
}

@test "commander --cli shows live profile core (set by eco_setup)" {
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "Profile: core"
}

@test "commander --cli shows live profile placeholder when profile file is missing" {
  rm -f "$HOME/.ai-ecosystem/.current-profile"
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "Profile: —"
}

@test "commander --cli shows live profile placeholder when profile file is empty" {
  : > "$HOME/.ai-ecosystem/.current-profile"
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "Profile: —"
}

@test "commander --cli output contains Ollama status sections" {
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "Ollama:"
  assert_output_contains "Local LLMs"
}

@test "commander --cli shows Ollama loaded over installed counts" {
  export STUB_OLLAMA_LOADED=""
  export STUB_OLLAMA_LIST=$'qwen2.5:3b\t-\t2.0 GB\t-\nbge-m3:latest\t-\t1.2 GB\t-'
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "Ollama: 0/2 loaded"
  assert_output_contains "Unloaded Models"
}

@test "commander --cli with ollama daemon down shows unreachable or 0 loaded" {
  export STUB_OLLAMA_RUNNING=0
  export STUB_CURL_EXIT=1
  run bash "$ECO_CMD" --cli
  assert_success
  # Either the explicit 'daemon unreachable' message or zero loaded count
  if [[ "$output" != *"daemon unreachable"* ]] && [[ "$output" != *"Ollama: 0/"* ]]; then
    echo "Expected either 'daemon unreachable' or an Ollama zero-loaded count in output"
    echo "--- actual output ---"
    echo "$output"
    return 1
  fi
}

@test "commander --cli output has no SwiftBar markup (| bash= / | color=)" {
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_not_contains "| bash="
  assert_output_not_contains "| color="
}

@test "commander (no --cli) emits SwiftBar markup (| color=)" {
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "| color="
}

@test "commander exposes recipes under Do Task menu" {
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "🧰 Recipes"
  assert_output_contains "snapshot — run snapshot"
  assert_output_contains "ask — Ask a question fast"
}

@test "commander routes recipes through fixed helper instead of direct recipe paths" {
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "ask — Ask a question fast"
  assert_output_contains "bash=$HOME/.eco/bin/eco-alerts.sh param1=run-recipe param2=ask terminal=true refresh=true"
  assert_output_not_contains "bash=$HOME/.eco/recipes/ask.sh"
}

@test "commander does not expose legacy model-unload helper" {
  run bash "$ECO_CMD"
  assert_success
  assert_output_not_contains "ai-clear"
  assert_output_not_contains "bash=$HOME/.eco/bin/ai-clear.sh"
  assert_output_not_contains "source ${HOME}/.ai-ecosystem/shell-aliases.sh"
}

@test "commander exposes alert doctor workflow from quick actions" {
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "Alert doctor"
  assert_output_contains "bash=$HOME/.eco/bin/eco-alerts.sh param1=run-logged param2=doctor terminal=false refresh=true"
}

@test "commander exposes docs and repo health workflow" {
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "📚 Docs"
  assert_output_contains "Widget health"
  assert_output_contains "Repo health check"
  assert_output_contains "param1=run-logged param2=repo-health terminal=false refresh=true"
  assert_output_contains "Refresh dashboard metrics"
  assert_output_contains "param1=run-logged param2=fix-dashboard-refresh terminal=false refresh=true"
}

@test "commander profile switches open terminal so failures are visible" {
  mkdir -p "$HOME/.ai-ecosystem/profiles"
  cat > "$HOME/.ai-ecosystem/profiles/research.mcpServers.json" <<'JSON'
{"mcpServers":{"docs":{"command":"npx","args":["docs"]}}}
JSON
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "→ research"
  assert_output_contains "bash=$HOME/.ai-ecosystem/switch-profile.sh param1=research terminal=true refresh=true"
}

@test "commander: heavy unloaded model (>=10 GB) has no Pre-warm button" {
  # Large local models must NOT get a fat-finger Pre-warm button in the menu
  export STUB_OLLAMA_LOADED=""   # nothing loaded
  export STUB_OLLAMA_LIST=$'qwen2.5:3b\t-\t2.0 GB\t-\ngemma4:31b\t-\t24 GB\t-\nbge-m3:latest\t-\t1.2 GB\t-'
  run bash "$ECO_CMD"
  assert_success
  # Light model should still offer pre-warm
  assert_output_contains "Pre-warm qwen2.5:3b"
  # Heavy model: no Pre-warm button, replaced with advisory label
  assert_output_not_contains "Pre-warm gemma4:31b"
  assert_output_contains "gemma4:31b (24 GB) — heavy"
}

@test "commander: light unloaded model (<10 GB) still gets Pre-warm button" {
  export STUB_OLLAMA_LOADED=""
  export STUB_OLLAMA_LIST=$'qwen2.5:3b\t-\t2.0 GB\t-'
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "Pre-warm qwen2.5:3b"
  assert_output_contains "bash=$HOME/.eco/bin/eco-alerts.sh param1=prewarm-ollama param2=qwen2.5:3b terminal=false refresh=true"
  assert_output_not_contains "bash=/bin/bash param1=-c"
  assert_output_not_contains "echo hi |"
}

@test "commander escapes SwiftBar label pipes from recipe descriptions" {
  cat > "$HOME/.eco/recipes/inject.sh" <<'SH'
#!/usr/bin/env bash
# DESC: safe text | bash=/tmp/pwn terminal=true
exit 0
SH
  chmod +x "$HOME/.eco/recipes/inject.sh"

  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "inject — safe text \\| bash=/tmp/pwn terminal=true"
  assert_output_not_contains "inject — safe text | bash=/tmp/pwn terminal=true"
}

@test "commander suppresses unsafe recipe action params" {
  cat > "$HOME/.eco/recipes/bad param1=pwn.sh" <<'SH'
#!/usr/bin/env bash
# DESC: unsafe name
exit 0
SH
  chmod +x "$HOME/.eco/recipes/bad param1=pwn.sh"

  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "bad param1=pwn — unsafe name (manual run only)"
  assert_output_not_contains "param2=bad param1=pwn"
  assert_output_not_contains "bash=$HOME/.eco/recipes/bad param1=pwn.sh"
}

@test "commander suppresses unsafe Ollama model action params" {
  export STUB_OLLAMA_LOADED=""
  export STUB_OLLAMA_LIST=$'bad|refresh=true\t-\t2.0 GB\t-'
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "Pre-warm unavailable: unsafe model name"
  assert_output_not_contains "param2=bad|refresh=true"
}

@test "commander sanitizes alert issue ids before action params" {
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{"generated_at":"2026-05-20","snapshot_id":"test","layers":{"L1":{"issues":[{"severity":"HIGH","id":"bad id|refresh=true","desc":"Test alert"}]}}}
JSON
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "bad_id: Test alert"
  assert_output_not_contains "param2=bad id|refresh=true"
  assert_output_not_contains "param3=bad id|refresh=true"
}
