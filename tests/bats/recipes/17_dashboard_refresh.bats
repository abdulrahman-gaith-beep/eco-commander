#!/usr/bin/env bats
# 17_dashboard_refresh.bats — tests for dashboard-refresh.sh recipe
#
# Covers:
#   - Replaces metric placeholders in all quoting forms
#   - Errors on missing dashboard file
#   - Errors when no metric placeholders found
#   - Preserves non-metric HTML content
#   - Handles missing dependency directories gracefully

load '../../helpers/common.bash'

setup() {
  eco_setup
  RECIPE="$HOME/.eco/recipes/dashboard-refresh.sh"
  [ -f "$RECIPE" ] || skip "dashboard-refresh.sh not available in sandbox"
  chmod +x "$RECIPE"

  # Set up required infrastructure
  mkdir -p "$HOME/.claude/agents"
  echo "# Agent 1" > "$HOME/.claude/agents/agent1.md"
  echo "# Agent 2" > "$HOME/.claude/agents/agent2.md"

  cat > "$HOME/.ai-ecosystem/mcp-master.json" <<'JSON'
{"mcpServers": {"server1": {}, "server2": {}, "server3": {}}}
JSON

  cat > "$HOME/.claude/settings.json" <<'JSON'
{"enabledPlugins": {"plugin1": true, "plugin2": true, "plugin3": false}}
JSON
}

teardown() {
  eco_teardown
}

# ── Basic metric replacement ────────────────────────────────────────

@test "dashboard-refresh: replaces unquoted data-id" {
  cat > "$HOME/.eco/current/dashboard.html" <<'HTML'
<html><body>
Agents: <span class=metric data-id=agents>0</span>
MCPs: <span class=metric data-id=mcps>0</span>
</body></html>
HTML
  export STATE_JSON="$HOME/.eco/current/state.json"
  run bash "$RECIPE" "$HOME/.eco/current/dashboard.html"
  assert_success
  content=$(cat "$HOME/.eco/current/dashboard.html")
  [[ "$content" == *"data-id=agents>2"* ]] || {
    echo "Expected agents count of 2"
    echo "Got: $content"
    return 1
  }
  [[ "$content" == *"data-id=mcps>3"* ]] || {
    echo "Expected MCPs count of 3"
    echo "Got: $content"
    return 1
  }
}

@test "dashboard-refresh: replaces double-quoted data-id" {
  cat > "$HOME/.eco/current/dashboard.html" <<'HTML'
<html><body>
Agents: <span class="metric" data-id="agent-count">0</span>
</body></html>
HTML
  export STATE_JSON="$HOME/.eco/current/state.json"
  run bash "$RECIPE" "$HOME/.eco/current/dashboard.html"
  assert_success
  content=$(cat "$HOME/.eco/current/dashboard.html")
  [[ "$content" == *">2<"* ]] || {
    echo "Expected agent count 2 in output"
    echo "Got: $content"
    return 1
  }
}

@test "dashboard-refresh: replaces plugin count" {
  cat > "$HOME/.eco/current/dashboard.html" <<'HTML'
<html><body>
Plugins: <span class=metric data-id=plugins>0</span>
</body></html>
HTML
  export STATE_JSON="$HOME/.eco/current/state.json"
  run bash "$RECIPE" "$HOME/.eco/current/dashboard.html"
  assert_success
  content=$(cat "$HOME/.eco/current/dashboard.html")
  # plugin3 is false, so only 2 enabled
  [[ "$content" == *"data-id=plugins>2"* ]] || {
    echo "Expected plugins count of 2"
    echo "Got: $content"
    return 1
  }
}

# ── Error handling ───────────────────────────────────────────────────

@test "dashboard-refresh: errors on missing dashboard file" {
  run bash "$RECIPE" "/nonexistent/dashboard.html"
  [ "$status" -ne 0 ]
}

@test "dashboard-refresh: errors when no metric placeholders" {
  cat > "$HOME/.eco/current/dashboard.html" <<'HTML'
<html><body><p>No metric spans here</p></body></html>
HTML
  export STATE_JSON="$HOME/.eco/current/state.json"
  run bash "$RECIPE" "$HOME/.eco/current/dashboard.html"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No metric"* ]]
}

@test "dashboard-refresh: --help shows usage" {
  run bash "$RECIPE" --help
  assert_success
  assert_output_contains "Usage:"
}

# ── Content preservation ─────────────────────────────────────────────

@test "dashboard-refresh: preserves non-metric HTML content" {
  cat > "$HOME/.eco/current/dashboard.html" <<'HTML'
<html><body>
<h1>My Dashboard</h1>
<p>Important text that must survive</p>
<span class=metric data-id=agents>0</span>
<footer>Footer content</footer>
</body></html>
HTML
  export STATE_JSON="$HOME/.eco/current/state.json"
  run bash "$RECIPE" "$HOME/.eco/current/dashboard.html"
  assert_success
  content=$(cat "$HOME/.eco/current/dashboard.html")
  [[ "$content" == *"Important text that must survive"* ]]
  [[ "$content" == *"Footer content"* ]]
  [[ "$content" == *"My Dashboard"* ]]
}

# ── Snapshot age ─────────────────────────────────────────────────────

@test "dashboard-refresh: snapshot age metric produces integer" {
  cat > "$HOME/.eco/current/dashboard.html" <<'HTML'
<html><body>
<span class=metric data-id=snapshot-age-hours>0</span>
<span class=metric data-id=agents>0</span>
</body></html>
HTML
  cat > "$HOME/.eco/current/state.json" <<'JSON'
{"snapshot_id": "test", "generated_at": "2026-05-20T00:00:00Z"}
JSON
  export STATE_JSON="$HOME/.eco/current/state.json"
  run bash "$RECIPE" "$HOME/.eco/current/dashboard.html"
  assert_success
  assert_output_contains "snapshot_age_hours:"
}
