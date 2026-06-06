#!/usr/bin/env bats
# 03_state_parsing.bats — commander's jq-based state.json parsing.

load '../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

@test "good state.json shows snapshot alerts in CLI header" {
  # eco_setup already copies state.json.good → state.json
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "2 Alerts"
  assert_output_contains "[HIGH] W1"
}

@test "state.json absent → 'Alerts (jq or state missing)' and exit 0" {
  rm -f "$HOME/.eco/current/state.json"
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "Alerts (jq or state missing)"
}

@test "malformed state.json → graceful fallback, exit 0, no crash" {
  cp "$ECO_TESTS_REAL/fixtures/state.json.malformed" "$HOME/.eco/current/state.json"
  run bash "$ECO_CMD" --cli
  assert_success
  # jq errors get swallowed (2>/dev/null || echo 0); the commander keeps running
  # and the rest of the output should still be present.
  assert_output_contains "Eco Commander (CLI)"
  assert_output_contains "0 Alerts"
}

@test "state.json with no Linf_wiring.issues shows zero snapshot alerts" {
  cp "$ECO_TESTS_REAL/fixtures/state.json.no_issues" "$HOME/.eco/current/state.json"
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "0 Alerts"
}

@test "state.json issue with missing severity still renders alert line" {
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{
  "snapshot_id": "missing-severity",
  "generated_at": "2026-04-24T00:00:00+03:00",
  "layers": {
    "Linf_wiring": {
      "issues": [
        {"id": "W-tab", "desc": "description\twith\ttabs"}
      ]
    }
  }
}
JSON
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "1 Alerts"
  assert_output_contains "[UNKNOWN] W-tab: description with tabs"
}

@test "state.json layer-local issues are preferred over legacy aggregate" {
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{
  "snapshot_id": "layer-local",
  "generated_at": "2026-04-24T00:00:00+03:00",
  "layers": {
    "GC_mcp": {
      "state": "warn",
      "issues": [
        {"severity": "high", "id": "GC-mcp:9", "desc": "MCP gateway unreachable in layer evidence."}
      ]
    },
    "Linf_wiring": {
      "issues": [
        {"severity": "med", "id": "legacy:1", "desc": "Legacy aggregate should not duplicate layer-local state."}
      ]
    }
  }
}
JSON
  run bash "$ECO_CMD" --cli
  assert_success
  assert_output_contains "1 Alerts"
  assert_output_contains "[HIGH] GC-mcp:9: MCP gateway unreachable in layer evidence."
  assert_output_not_contains "legacy:1"
}

@test "n8n snapshot alert exposes live verification and widget fix action" {
  export STUB_CURL_EXIT=1
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{
  "snapshot_id": "n8n-alert",
  "generated_at": "2026-04-24T00:00:00+03:00",
  "layers": {
    "Linf_wiring": {
      "issues": [
        {
          "severity": "high",
          "id": "GF-toolkit-projects-external:49",
          "desc": "- n8n status could not be verified (curl failed)."
        }
      ]
    }
  }
}
JSON
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "1 live"
  assert_output_contains "verified live: n8n is unreachable"
  assert_output_contains "Fix: Start n8n"
  assert_output_contains "bash=$HOME/.eco/bin/eco-alerts.sh param1=run-logged param2=fix-n8n param3=GF-toolkit-projects-external:49 terminal=false refresh=true"
}

@test "eco-alerts doctor audits every snapshot issue" {
  run "$HOME/.eco/bin/eco-alerts.sh" doctor
  assert_success
  assert_output_contains "Eco Alert Doctor"
  assert_output_contains "[triage] [HIGH] W1"
  assert_output_contains "[triage] [MED] W2"
  assert_output_contains "Summary: total=2 active=0 evidence=0 triage=2 resolved=0"
}

@test "memory router alert is delegated to Gemini Pro instead of direct patch" {
  export ECO_FORCE_MEMORY_ROUTER_MISSING=1
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{
  "snapshot_id": "memory-alert",
  "generated_at": "2026-04-24T00:00:00+03:00",
  "layers": {
    "Linf_wiring": {
      "issues": [
        {
          "severity": "high",
          "id": "GG-wiring-behavior:26",
          "desc": "- Memory router import failure: `toolkit.memory.router` not found."
        }
      ]
    }
  }
}
JSON
  run bash "$ECO_CMD"
  assert_success
  assert_output_contains "Fix: Plan with Gemini Pro"
  assert_output_contains "param1=run-logged param2=delegate-fix param3=GG-wiring-behavior:26 terminal=false refresh=true"
}

@test "eco-alerts delegate-fix writes a Gemini Pro fix workspace" {
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{
  "snapshot_id": "memory-alert",
  "generated_at": "2026-04-24T00:00:00+03:00",
  "layers": {
    "Linf_wiring": {
      "issues": [
        {
          "severity": "high",
          "id": "GG-wiring-behavior:26",
          "desc": "- Memory router import failure: `toolkit.memory.router` not found."
        }
      ]
    }
  }
}
JSON
  export STUB_GEMINI_OUTPUT="gemini fix plan"
  run "$HOME/.eco/bin/eco-alerts.sh" delegate-fix "GG-wiring-behavior:26"
  assert_success
  assert_output_contains "Orchestrating 3 Gemini Pro evaluators"
  assert_output_contains "Gemini orchestration synthesis:"
  assert_stub_called gemini

  local plan_root="$HOME/.eco/fix-plans"
  local latest
  latest="$(ls -1 "$plan_root" | tail -n1)"
  [ -f "$plan_root/$latest/evidence.md" ]
  [ -f "$plan_root/$latest/synthesis.md" ]
  assert_output_contains "$plan_root/$latest/synthesis.md"
}
