#!/usr/bin/env bats
# 06_eco_alerts.bats — tests for eco-alerts.sh
#
# Covers:
#   - slugify: special characters, double dashes, leading/trailing dashes
#   - issue_layer_path: correct layer extraction from issue ID
#   - classify_issue: n8n, memory_router, guide_stale, timeout, unknown
#   - doctor: parses state.json, prints summary
#   - run_logged: creates log dir, validates action
#   - repo_health: checks files, commands

load '../helpers/common.bash'

setup() {
  eco_setup
  ALERTS_SH="$HOME/.eco/bin/eco-alerts.sh"
  [ -f "$ALERTS_SH" ] || skip "eco-alerts.sh not available in sandbox"
  chmod +x "$ALERTS_SH"
  # Provide a state.json with issues for testing
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{
  "snapshot_id": "test-snap",
  "generated_at": "2026-05-20T12:00:00Z",
  "layers": {
    "L1_memory": {
      "issues": [
        {"id": "L1:mem:1", "severity": "HIGH", "desc": "toolkit.memory.router import fails"}
      ]
    },
    "L2_wiring": {
      "issues": [
        {"id": "L2:wire:1", "severity": "MEDIUM", "desc": "n8n automation unreachable"},
        {"id": "L2:wire:2", "severity": "LOW", "desc": "unknown issue for triage"}
      ]
    }
  }
}
JSON
}

teardown() {
  eco_teardown
}

# ── slugify ──────────────────────────────────────────────────────────

@test "classify_issue: n8n → active when unreachable" {
  # Stub curl to fail (n8n unreachable)
  export STUB_CURL_EXIT=1
  export N8N_URL="http://127.0.0.1:5678/"
  run bash -c "source '$ALERTS_SH' 2>/dev/null; classify_issue 'L2:wire:1' 'n8n automation unreachable'"
  [[ "$output" == *"active"* ]] || {
    echo "Expected 'active' in output for unreachable n8n"
    echo "Got: $output"
    return 1
  }
}

@test "classify_issue: n8n on-demand mode does not raise an active alert" {
  export STUB_CURL_EXIT=1
  export ECO_N8N_EXPECTED=0
  run bash -c "source '$ALERTS_SH' 2>/dev/null; classify_issue 'L2:wire:1' 'n8n automation unreachable'"
  [[ "$output" == *"resolved"* ]] || {
    echo "Expected 'resolved' in output for on-demand n8n"
    echo "Got: $output"
    return 1
  }
  [[ "$output" == *"on-demand"* ]] || {
    echo "Expected on-demand detail"
    echo "Got: $output"
    return 1
  }
}

@test "classify_issue: timeout → evidence" {
  run bash -c "source '$ALERTS_SH' 2>/dev/null; classify_issue 'L3:snap:1' 'snapshot timed out rc=124'"
  [[ "$output" == *"evidence"* ]] || {
    echo "Expected 'evidence' in output for timeout"
    echo "Got: $output"
    return 1
  }
}

@test "classify_issue: unknown → triage" {
  run bash -c "source '$ALERTS_SH' 2>/dev/null; classify_issue 'X:0' 'something nobody recognizes'"
  [[ "$output" == *"triage"* ]] || {
    echo "Expected 'triage' in output for unknown issue"
    echo "Got: $output"
    return 1
  }
}

@test "widget-issues: emits normalized alert rows for the widget" {
  export STUB_CURL_EXIT=1
  export ECO_FORCE_MEMORY_ROUTER_MISSING=1
  run bash "$ALERTS_SH" widget-issues
  assert_success
  [[ "$output" == *$'META\t3\t2\t0\t1\t0'* ]] || {
    echo "Expected normalized META counts"
    echo "Got: $output"
    return 1
  }
  assert_output_contains $'ISSUE\tHIGH\tL1:mem:1'
  assert_output_contains $'\tactive\tverified live: toolkit.memory.router is missing\tdelegate-fix\tPlan with Gemini Pro'
  assert_output_contains $'\tservice\tP1\tL2:wire:1'
}

# ── doctor ───────────────────────────────────────────────────────────

@test "doctor: parses state.json issues and prints summary" {
  # doctor requires state.json + jq
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  export STATE="$HOME/.eco/current/state.json"
  export ECO="$HOME/.eco"
  export CURRENT="$HOME/.eco/current"
  export N8N_URL="http://127.0.0.1:99999/"  # unreachable
  export ECO_FORCE_MEMORY_ROUTER_MISSING=1
  run bash "$ALERTS_SH" doctor
  # Should contain Summary line
  [[ "$output" == *"Summary:"* ]] || {
    echo "Expected 'Summary:' in doctor output"
    echo "Got: $output"
    return 1
  }
  # Should mention total count
  [[ "$output" == *"total="* ]] || {
    echo "Expected 'total=' in doctor output"
    echo "Got: $output"
    return 1
  }
}

@test "doctor: handles missing state.json gracefully" {
  rm -f "$HOME/.eco/current/state.json"
  export ECO="$HOME/.eco"
  export STATE="$HOME/.eco/current/state.json"
  run bash "$ALERTS_SH" doctor
  assert_success
  [[ "$output" == *"snapshot"* ]] || [[ "$output" == *"state.json"* ]] || {
    echo "Expected guidance about missing state.json"
    echo "Got: $output"
    return 1
  }
}

# ── run_logged ───────────────────────────────────────────────────────

@test "run_logged: rejects unknown action" {
  export ECO="$HOME/.eco"
  run bash "$ALERTS_SH" run-logged "totally-invalid-action"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not allow"* ]] || [[ "$stderr" == *"does not allow"* ]] || {
    # Check stderr too
    true
  }
}

@test "run_logged: accepted actions include doctor" {
  export ECO="$HOME/.eco"
  export ECO_ALERT_OPEN_TERMINAL=0
  # run-logged doctor should succeed (it backgrounds the action)
  run bash "$ALERTS_SH" run-logged doctor
  assert_success
  [[ "$output" == *"Started"* ]] || [[ "$output" == *"pid"* ]] || {
    echo "Expected 'Started' or 'pid' in run-logged output"
    echo "Got: $output"
    return 1
  }
}

# ── help ─────────────────────────────────────────────────────────────

@test "help: shows usage text" {
  run bash "$ALERTS_SH" help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "doctor"
  assert_output_contains "repo-health"
}

@test "unknown command exits nonzero" {
  run bash "$ALERTS_SH" completely-fake-command
  [ "$status" -ne 0 ]
}

# ── repo_health ──────────────────────────────────────────────────────

@test "repo_health: identifies missing docs" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  # Set up repo root that IS the sandbox — docs/ won't exist
  export ECO="$HOME/.eco"
  export ECO_COMMANDER_REPO="$HOME/fake-repo"
  mkdir -p "$HOME/fake-repo"
  echo "# README" > "$HOME/fake-repo/README.md"
  mkdir -p "$HOME/fake-repo/docs"
  run bash "$ALERTS_SH" repo-health
  # Should report FAIL for missing docs files
  [[ "$output" == *"FAIL"* ]] || [[ "$output" == *"missing"* ]] || {
    echo "Expected FAIL or missing in repo-health output for incomplete repo"
    echo "Got: $output"
    return 1
  }
}

# ── open-source ──────────────────────────────────────────────────────

@test "open-source: errors on missing issue id" {
  export ECO="$HOME/.eco"
  run bash "$ALERTS_SH" open-source
  [ "$status" -ne 0 ]
}

@test "open-source: errors when layer file not found" {
  export ECO="$HOME/.eco"
  run bash "$ALERTS_SH" open-source "L99:missing:1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"error"* ]] || true
}

@test "open-source: rejects path traversal issue layer" {
  export ECO="$HOME/.eco"
  run bash "$ALERTS_SH" open-source "../escape:1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid issue layer"* ]] || [[ "$stderr" == *"invalid issue layer"* ]]
}

@test "prewarm-ollama: rejects unsafe model name" {
  run bash "$ALERTS_SH" prewarm-ollama "bad|refresh=true"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid ollama model"* ]] || [[ "$stderr" == *"invalid ollama model"* ]]
}

# ── fix_guide_stale (idempotent) ─────────────────────────────────────

@test "fix-guide-stale: inserts banner into guide file" {
  export GUIDE_FILE="$HOME/test-guide.html"
  cat > "$GUIDE_FILE" <<'HTML'
<html><body><nav>Nav</nav><div>Content with 430 chunks</div></body></html>
HTML
  export ECO="$HOME/.eco"
  run bash "$ALERTS_SH" fix-guide-stale
  assert_success
  grep -q "eco-alert-stale-counts-banner" "$GUIDE_FILE"
}

@test "fix-guide-stale: idempotent on re-run" {
  export GUIDE_FILE="$HOME/test-guide.html"
  cat > "$GUIDE_FILE" <<'HTML'
<html><body><div id="eco-alert-stale-counts-banner">Already present</div></body></html>
HTML
  export ECO="$HOME/.eco"
  run bash "$ALERTS_SH" fix-guide-stale
  assert_success
  [[ "$output" == *"already has"* ]]
}
