#!/usr/bin/env bats
# 01_router.bats — Wave 1: cover the router branches in ~/.eco/bin/eco.
#
# Source under test is copied into the sandbox by eco_setup. Keep tests
# hermetic and fix real router bugs in the source when they are found.

bats_require_minimum_version 1.5.0

load '../helpers/common.bash'

setup()    { eco_setup; }
teardown() { eco_teardown; }

make_fake_repo_python() {
  local repo="$1"
  mkdir -p "$repo/.venv/bin" "$repo/src"
  cat > "$repo/.venv/bin/python" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_VENV_PYTHON_LOG:?}"
if [ "${FAKE_VENV_PYTHON_FAIL_DEPS:-0}" = "1" ] && [ "${1:-}" = "-" ]; then
  count=0
  [ -f "${FAKE_VENV_PYTHON_COUNT:?}" ] && count="$(cat "$FAKE_VENV_PYTHON_COUNT")"
  count=$((count + 1))
  echo "$count" > "$FAKE_VENV_PYTHON_COUNT"
  # First stdin call is the version probe; second is the dependency probe.
  [ "$count" -eq 1 ] && exit 0
  exit 1
fi
if [ "${FAKE_VENV_PYTHON_FAIL_IMPORT:-0}" = "1" ] && [ "${1:-}" = "-c" ]; then
  exit 1
fi
if [ "${1:-}" = "-m" ]; then
  echo "fake scheduler invoked: $*"
fi
exit 0
SH
  chmod +x "$repo/.venv/bin/python"
}

make_unloaded_launchctl_stub() {
  mkdir -p "$HOME/test-bin"
  cat > "$HOME/test-bin/launchctl" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$HOME/test-bin/launchctl"
}

# ------------------------------------------------------------------
# 1. `eco` (bare) lists recipes
# ------------------------------------------------------------------
@test "eco (bare) prints === Eco Recipes === header" {
  run "$ECO_BIN"
  assert_success
  assert_output_contains "=== Eco Recipes ==="
  assert_output_contains "(call with: eco do <name>)"
  assert_output_contains "=== Utility commands ==="
}

# ------------------------------------------------------------------
# 2. `eco list` lists recipes (same behavior)
# ------------------------------------------------------------------
@test "eco list matches bare invocation" {
  run "$ECO_BIN" list
  assert_success
  assert_output_contains "=== Eco Recipes ==="
  assert_output_contains "ask"
}

# ------------------------------------------------------------------
# 3. `eco do ask "hi"` runs the recipe and forwards args to gemini
# ------------------------------------------------------------------
@test "eco do ask forwards arg to gemini stub" {
  run "$ECO_BIN" do ask "hi"
  assert_success
  [ -f "$HOME/.stub-gemini.log" ]
  assert_stub_args_contain gemini "hi"
}

# ------------------------------------------------------------------
# 4. `eco do` with no name → exit 1, prints usage
# ------------------------------------------------------------------
@test "eco do with no name exits 1 and prints usage" {
  run "$ECO_BIN" do
  assert_failure 1
  assert_output_contains "Usage: eco do <recipe>"
}

# ------------------------------------------------------------------
# 5. `eco do nonexistent` → exit 1, prints "Recipe not found"
# ------------------------------------------------------------------
@test "eco do nonexistent exits 1 and prints not-found" {
  run "$ECO_BIN" do nonexistent
  assert_failure 1
  assert_output_contains "Recipe not found: nonexistent"
}

# ------------------------------------------------------------------
# 5b. Unsafe recipe names are rejected before path lookup
# ------------------------------------------------------------------
@test "eco do rejects unsafe recipe names" {
  run "$ECO_BIN" do "../ask"
  assert_failure 2
  assert_output_contains "Invalid recipe name: ../ask"
  assert_output_contains "letters, numbers, dash, and underscore"
  [ ! -f "$HOME/.stub-gemini.log" ]
}

@test "eco shortcut rejects unsafe recipe names" {
  run "$ECO_BIN" "../ask"
  assert_failure 2
  assert_output_contains "Invalid recipe name: ../ask"
  [ ! -f "$HOME/.stub-gemini.log" ]
}

@test "eco refuses safe-named recipe symlink outside recipes dir" {
  command -v realpath >/dev/null 2>&1 || skip "realpath not installed"
  cat > "$HOME/outside.sh" <<'SH'
#!/usr/bin/env bash
echo "outside executed"
SH
  chmod +x "$HOME/outside.sh"
  ln -s "$HOME/outside.sh" "$HOME/.eco/recipes/evil.sh"

  run "$ECO_BIN" do evil
  assert_failure 1
  assert_output_contains "Refusing to run recipe outside recipes directory: evil"
  assert_output_not_contains "outside executed"
}

# ------------------------------------------------------------------
# 6. `eco status` runs the commander script and prints ecosystem state.
#    The merged widget now renders the compact v2 CLI status view.
# ------------------------------------------------------------------
@test "eco status runs the commander and prints ecosystem state" {
  run "$ECO_BIN" status
  assert_success
  assert_output_contains "Eco Commander (CLI)"
  assert_output_contains "Status:"
  assert_output_contains "Profile:"
}

# ------------------------------------------------------------------
# 7. `eco dashboard` calls open with dashboard.html
# ------------------------------------------------------------------
@test "eco dashboard calls open on dashboard.html" {
  run "$ECO_BIN" dashboard
  assert_success
  assert_stub_called open
  assert_stub_args_contain open "$HOME/.eco/current/dashboard.html"
}

@test "eco dashboard reports missing dashboard file" {
  rm -f "$HOME/.eco/current/dashboard.html"
  run "$ECO_BIN" dashboard
  assert_failure 1
  assert_output_contains "Dashboard not found: $HOME/.eco/current/dashboard.html"
  assert_output_contains "eco snapshot"
  [ ! -f "$HOME/.stub-open.log" ]
}

# ------------------------------------------------------------------
# 8. `eco map` calls open with map.md
# ------------------------------------------------------------------
@test "eco map calls open on map.md" {
  run "$ECO_BIN" map
  assert_success
  assert_stub_called open
  assert_stub_args_contain open "$HOME/.eco/current/map.md"
}

# ------------------------------------------------------------------
# 9. `eco audit` opens the configured ECO_AUDIT_DIR (and errors if missing)
# ------------------------------------------------------------------
@test "eco audit opens the configured audit dir when it exists" {
  mkdir -p "$HOME/.eco/ecosystem-audit"
  run env ECO_AUDIT_DIR="$HOME/.eco/ecosystem-audit" "$ECO_BIN" audit
  assert_success
  assert_stub_called open
  assert_stub_args_contain open "$HOME/.eco/ecosystem-audit"
}

@test "eco audit errors when the audit dir is missing" {
  run env ECO_AUDIT_DIR="$HOME/.eco/does-not-exist" "$ECO_BIN" audit
  assert_failure
  assert_output_contains "Audit directory not found"
}

# ------------------------------------------------------------------
# 10. `eco scheduler` uses the repo virtualenv Python
# ------------------------------------------------------------------
@test "eco scheduler prefers repo .venv python" {
  local repo="$HOME/repo"
  make_fake_repo_python "$repo"

  run env ECO_COMMANDER_REPO="$repo" \
    FAKE_VENV_PYTHON_LOG="$HOME/.stub-venv-python.log" \
    "$ECO_BIN" scheduler status

  assert_success
  assert_output_contains "fake scheduler invoked: -m scheduler.cli status"
  grep -q -- "-m scheduler.cli status" "$HOME/.stub-venv-python.log"
  [ ! -f "$HOME/.stub-python3.log" ]
}

# ------------------------------------------------------------------
# 11. `eco scheduler` errors clearly when scheduler deps are missing
# ------------------------------------------------------------------
@test "eco scheduler reports missing scheduler dependencies" {
  local repo="$HOME/repo"
  make_fake_repo_python "$repo"

  run env ECO_COMMANDER_REPO="$repo" \
    FAKE_VENV_PYTHON_LOG="$HOME/.stub-venv-python.log" \
    FAKE_VENV_PYTHON_COUNT="$HOME/.stub-venv-python.count" \
    FAKE_VENV_PYTHON_FAIL_DEPS=1 \
    "$ECO_BIN" scheduler status

  assert_failure 1
  assert_output_contains "missing scheduler Python dependencies"
  assert_output_contains "pip install -e"
}

# ------------------------------------------------------------------
# 12. `eco help` prints clean public usage
# ------------------------------------------------------------------
@test "eco help prints usage block" {
  run "$ECO_BIN" help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "List recipes and utility commands"
  assert_output_contains "Run a recipe"
  assert_output_contains "scheduler <sub>"
  assert_output_contains "hygiene <sub>"
  assert_output_contains "account-swap <sub>"
  assert_output_contains "doctor"
  assert_output_not_contains "EROR"
  assert_output_not_contains "ECO_HELP_BEGIN"
}

# ------------------------------------------------------------------
# 13. `eco -h` same as help
# ------------------------------------------------------------------
@test "eco -h prints usage block" {
  run "$ECO_BIN" -h
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "List recipes and utility commands"
  assert_output_contains "scheduler <sub>"
}

# ------------------------------------------------------------------
# 14. `eco --help` same as help
# ------------------------------------------------------------------
@test "eco --help prints usage block" {
  run "$ECO_BIN" --help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "Run a recipe"
  assert_output_contains "doctor"
}

# ------------------------------------------------------------------
# 15. Shortcut: `eco ask "hi"` should fall through *) → run recipe
# ------------------------------------------------------------------
@test "eco ask shortcut runs the ask recipe" {
  run "$ECO_BIN" ask "hi"
  assert_success
  [ -f "$HOME/.stub-gemini.log" ]
  assert_stub_args_contain gemini "hi"
}

# ------------------------------------------------------------------
# 16. Unknown command → exit 1
# ------------------------------------------------------------------
@test "eco unknown command exits 1 and prints Unknown command" {
  run "$ECO_BIN" totally-not-a-thing
  assert_failure 1
  assert_output_contains "Unknown command:"
  assert_output_contains "totally-not-a-thing"
}

# ------------------------------------------------------------------
# 17. List shows DESC parsed from recipe "# DESC:" headers
# ------------------------------------------------------------------
@test "eco list shows parsed DESC lines" {
  run "$ECO_BIN" list
  assert_success
  assert_output_contains "Ask a question fast"
}

# ------------------------------------------------------------------
# 18. List shows INPUTS line when present
# ------------------------------------------------------------------
@test "eco list shows INPUTS line when present" {
  run "$ECO_BIN" list
  assert_success
  assert_output_contains "inputs:"
  assert_output_contains "<question>"
}

# ------------------------------------------------------------------
# 19. _lib.sh entries are hidden
# ------------------------------------------------------------------
@test "eco list hides _lib.sh" {
  cat > "$HOME/.eco/recipes/_lib.sh" <<'EOF'
#!/usr/bin/env bash
# DESC: internal lib — should NEVER appear in list
echo "lib"
EOF
  chmod +x "$HOME/.eco/recipes/_lib.sh"
  run "$ECO_BIN" list
  assert_success
  assert_output_not_contains "_lib"
  assert_output_not_contains "internal lib"
}

# ------------------------------------------------------------------
# 20. Recipe with no DESC shows "(no description)"
# ------------------------------------------------------------------
@test "eco list shows (no description) for DESC-less recipe" {
  cat > "$HOME/.eco/recipes/nodesc.sh" <<'EOF'
#!/usr/bin/env bash
echo "hi"
EOF
  chmod +x "$HOME/.eco/recipes/nodesc.sh"
  run "$ECO_BIN" list
  assert_success
  assert_output_contains "nodesc"
  assert_output_contains "(no description)"
}

# ------------------------------------------------------------------
# 21. Recipe args with spaces are forwarded intact
# ------------------------------------------------------------------
@test "eco do ask forwards multi-word arg intact" {
  run "$ECO_BIN" do ask "hello world"
  assert_success
  assert_stub_args_contain gemini "hello world"
}

# ------------------------------------------------------------------
# 22. `eco list` still works when recipes dir is empty
# ------------------------------------------------------------------
@test "eco list works with empty recipes dir" {
  # Move all recipes aside
  mkdir -p "$HOME/.eco/recipes-backup"
  mv "$HOME/.eco/recipes/"*.sh "$HOME/.eco/recipes-backup/" 2>/dev/null || true
  run "$ECO_BIN" list
  assert_success
  assert_output_contains "=== Eco Recipes ==="
  assert_output_contains "=== Utility commands ==="
}

# ------------------------------------------------------------------
# 23. `eco doctor` skips opt-in LaunchAgents and usage poller by default
# ------------------------------------------------------------------
@test "eco doctor treats optional components as informational" {
  local repo="$HOME/repo"
  make_fake_repo_python "$repo"
  make_unloaded_launchctl_stub

  run env PATH="$HOME/test-bin:$HOME/.eco/bin:$PATH" \
    ECO_COMMANDER_REPO="$repo" \
    FAKE_VENV_PYTHON_LOG="$HOME/.stub-venv-python.log" \
    "$ECO_BIN" doctor

  assert_success
  assert_output_contains "ℹ️  com.eco-commander.usage-poller not loaded"
  assert_output_contains "ℹ️  com.eco-commander.scheduler not loaded"
  assert_output_contains "ℹ️  usage.json missing (usage poller optional)"
  assert_output_contains "All checks passed"
}

@test "eco doctor falls back when stat -f output is not an epoch" {
  local repo="$HOME/repo"
  make_fake_repo_python "$repo"
  make_unloaded_launchctl_stub
  cat > "$HOME/test-bin/stat" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-f" ] && [ "${2:-}" = "%m" ]; then
  echo "/"
  exit 0
fi
if [ "${1:-}" = "-c" ] && [ "${2:-}" = "%Y" ]; then
  date +%s
  exit 0
fi
exit 64
SH
  chmod +x "$HOME/test-bin/stat"
  : > "$HOME/.eco/current/usage.json"

  run env PATH="$HOME/test-bin:$HOME/.eco/bin:$PATH" \
    ECO_COMMANDER_REPO="$repo" \
    FAKE_VENV_PYTHON_LOG="$HOME/.stub-venv-python.log" \
    "$ECO_BIN" doctor

  assert_success
  assert_output_contains "✅ usage.json fresh"
  assert_output_contains "All checks passed"
}

# ------------------------------------------------------------------
# 24. `eco doctor` exits 1 for real errors
# ------------------------------------------------------------------
@test "eco doctor exits 1 when Python imports fail" {
  local repo="$HOME/repo"
  make_fake_repo_python "$repo"
  make_unloaded_launchctl_stub

  run env PATH="$HOME/test-bin:$HOME/.eco/bin:$PATH" \
    ECO_COMMANDER_REPO="$repo" \
    FAKE_VENV_PYTHON_LOG="$HOME/.stub-venv-python.log" \
    FAKE_VENV_PYTHON_FAIL_IMPORT=1 \
    "$ECO_BIN" doctor

  assert_failure 1
  assert_output_contains "❌ Python import failed"
  assert_output_contains "1 issue(s) found"
}

# ------------------------------------------------------------------
# 25. Exit code is 0 for list/help; nonzero for errors
# ------------------------------------------------------------------
@test "exit codes: 0 for list, 0 for help, nonzero for errors" {
  run "$ECO_BIN" list
  assert_success
  run "$ECO_BIN" help
  assert_success
  run "$ECO_BIN" do
  assert_failure 1
  run "$ECO_BIN" do nonexistent
  assert_failure 1
  run "$ECO_BIN" totally-not-a-thing
  assert_failure 1
}

# ------------------------------------------------------------------
# 26. Error messages go to stdout (current code uses bare `echo`);
#     status is still non-zero. Documents the current design.
# ------------------------------------------------------------------
@test "errors print to stdout (current design) while status stays nonzero" {
  # `run` captures stdout+stderr merged. Re-invoke with explicit redirects
  # so we can tell them apart. Use `|| true` on every invocation so a
  # nonzero exit doesn't abort the test under bats' errexit.
  local stdout stderr rc=0
  stdout=$("$ECO_BIN" do nonexistent 2>/dev/null || true)
  stderr=$("$ECO_BIN" do nonexistent 2>&1 >/dev/null || true)
  "$ECO_BIN" do nonexistent >/dev/null 2>&1 || rc=$?
  [[ "$stdout" == *"Recipe not found"* ]]
  [ -z "$stderr" ]
  [ "$rc" -ne 0 ]
}
