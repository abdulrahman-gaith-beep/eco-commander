#!/usr/bin/env bats
# Tests for the usage-monitor SwiftBar plugin and the Python poller.

load ../helpers/common

setup() {
  eco_usage_monitor_setup
  PLUGIN="$BATS_TEST_DIRNAME/../../src/bin/eco-commander.15s.sh"
  REPO_DIR="$BATS_TEST_DIRNAME/../.."
}

teardown() {
  eco_teardown
}

# ---------- Renderer ----------

@test "usage-monitor: shows fallback when usage.json is missing" {
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Poller has not produced data yet"* ]]
}

@test "usage-monitor: renders headline from synthetic usage.json" {
  cat > "$ECO_HOME/current/usage.json" <<JSON
{
  "ts": $(date +%s), "version": 1,
  "claude": {"tool":"claude","ok":true,"source":"jsonl","plan":"Payload Plan","accounts":9,
    "session":{"tokens":1,"cap":100,"pct":12,"resets_in":"1h 00m"},
    "weekly":{"tokens":1,"cap":100,"pct":34,"resets_in":"5d 00m"}},
  "codex": {"tool":"codex","ok":true,"source":"jsonl",
    "session":{"tokens":1,"cap":100,"pct":56,"resets_in":"2h 00m"},
    "weekly":{"tokens":1,"cap":100,"pct":78,"resets_in":"6d 00m"}},
  "gemini": {"tool":"gemini","ok":false,"source":"stub","error":"stub",
    "tiers":{"flash":{"pct":0,"resets_in":"-"},"flash_lite":{"pct":0,"resets_in":"-"},"pro":{"pct":0,"resets_in":"-"}}}
}
JSON
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"C 12/34w"* ]]
  [[ "$output" == *"X 56/78w"* ]]
  [[ "$output" == *"G —"* ]]
  [[ "$output" == *"Claude Code"* ]]
  [[ "$output" == *"Claude · Unknown"* ]]
  [[ "$output" != *"Payload Plan"* ]]
  [[ "$output" != *"×9"* ]]
}

@test "usage-monitor: stale data shows warning" {
  STALE_TS=$(( $(date +%s) - 600 ))   # 10 minutes ago
  cat > "$ECO_HOME/current/usage.json" <<JSON
{"ts": $STALE_TS, "version": 1,
 "claude": {"ok":true,"session":{"pct":1,"resets_in":"-"},"weekly":{"pct":1,"resets_in":"-"}},
 "codex":  {"ok":true,"session":{"pct":1,"resets_in":"-"},"weekly":{"pct":1,"resets_in":"-"}},
 "gemini": {"ok":false,"error":"stub","tiers":{"flash":{"pct":0},"flash_lite":{"pct":0},"pro":{"pct":0}}}}
JSON
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"stale"* ]]
}

@test "usage-monitor: renders token detail grafted onto api payloads" {
  cat > "$ECO_HOME/current/usage.json" <<JSON
{
  "ts": $(date +%s), "version": 1,
  "claude": {"tool":"claude","ok":true,"source":"api",
    "session":{"pct":12,"resets_in":"1h 00m","tokens":1500,
               "input_tokens":500,"output_tokens":700,
               "cache_creation_tokens":100,"cache_read_tokens":200},
    "weekly":{"pct":34,"pct_all":34,"pct_sonnet":20,"resets_in":"5d 00m",
              "tokens":2500,"input_tokens":1000,"output_tokens":900,
              "cache_creation_tokens":300,"cache_read_tokens":300,"sessions":2}},
  "codex": {"tool":"codex","ok":true,"source":"api",
    "session":{"pct":56,"resets_in":"2h 00m","tokens":1600,
               "input_tokens":600,"output_tokens":700,"cached_input_tokens":300},
    "weekly":{"pct":78,"resets_in":"6d 00m","tokens":2600,
              "input_tokens":1100,"output_tokens":1000,"cached_input_tokens":500}},
  "gemini": {"tool":"gemini","ok":false,"source":"error","error":"stub",
    "tiers":{"flash":{"pct":0,"resets_in":"-"},"flash_lite":{"pct":0,"resets_in":"-"},"pro":{"pct":0,"resets_in":"-"}}}
}
JSON
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cache↻ 200"* ]]
  [[ "$output" == *"cached-in 300"* ]]
}

# ---------- Poller (Python) ----------

@test "poller: runs without crashing and writes usage.json" {
  [ -n "${PYTHON:-}" ] || skip "python3 not available"
  run bash "$REPO_DIR/scripts/run-poller.sh"
  [ "$status" -eq 0 ]
  [ -f "$ECO_HOME/current/usage.json" ]
  [ -f "$ECO_HOME/current/usage-claude.json" ]
  [ -f "$ECO_HOME/current/usage-codex.json" ]
  [ -f "$ECO_HOME/current/usage-gemini.json" ]
  run env USAGE_JSON_PATH="$ECO_HOME/current/usage.json" "$PYTHON" -c 'import json, os; d=json.load(open(os.environ["USAGE_JSON_PATH"], encoding="utf-8")); assert "claude" in d and "codex" in d and "gemini" in d, d.keys()'
  [ "$status" -eq 0 ]
}

@test "usage-monitor: corrupt usage.json fails clean" {
  printf 'not-json-at-all' > "$ECO_HOME/current/usage.json"
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"corrupt"* ]]
}

@test "usage-monitor: unsafe numeric timestamp fails clean" {
  printf '{"ts": 1e100, "version": 1}' > "$ECO_HOME/current/usage.json"
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"corrupt"* ]]
}

@test "usage-snapshot: default output stays under ECO_HOME" {
  run grep -F 'DEFAULT_OUT_DIR="$ECO_ROOT/usage-snapshots"' "$REPO_DIR/scripts/usage-snapshot.sh"
  [ "$status" -eq 0 ]

  run grep -F 'OUT_DIR="${ECO_SNAPSHOT_DIR:-$HOME/Desktop}"' "$REPO_DIR/scripts/usage-snapshot.sh"
  [ "$status" -ne 0 ]
}

@test "usage-monitor: humanize formats K/M/B correctly" {
  cat > "$ECO_HOME/current/usage.json" <<JSON
{
  "ts": $(date +%s), "version": 1,
  "claude": {"tool":"claude","ok":true,"source":"jsonl",
    "session":{"tokens":1500,"input_tokens":500,"output_tokens":1000,
               "cache_creation_tokens":0,"cache_read_tokens":0,
               "cap":1000000,"pct":1,"resets_in":"1h 00m","sessions":1},
    "weekly":{"tokens":2500000000,"input_tokens":1500000000,"output_tokens":1000000000,
              "cache_creation_tokens":0,"cache_read_tokens":0,
              "cap":10000000000,"pct":25,"resets_in":"5d 00m","sessions":3}},
  "codex": {"tool":"codex","ok":false,"error":"none","session":{"pct":0,"resets_in":"-"},"weekly":{"pct":0,"resets_in":"-"}},
  "gemini": {"tool":"gemini","ok":false,"error":"stub","tiers":{"flash":{"pct":0},"flash_lite":{"pct":0},"pro":{"pct":0}}}
}
JSON
  run bash "$PLUGIN"
  [ "$status" -eq 0 ]
  # 1500 → "1.50K", 2.5B billable, 1.5B input, 1.0B output
  [[ "$output" == *"1.50K"* ]] || [[ "$output" == *"1.5K"* ]]
  [[ "$output" == *"B"* ]]   # billions present
}
