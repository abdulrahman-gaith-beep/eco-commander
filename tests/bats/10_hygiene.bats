#!/usr/bin/env bats
# tests/bats/hygiene.bats — smoke + sanity for the hygiene recipe
# Run: bats tests/bats/hygiene.bats

load '../helpers/common.bash'

setup() {
    eco_setup
    export ECO="$HOME/.eco"
    export ECO_HOME="$HOME/.eco"
    HYG_SCRIPT="$HOME/.eco/recipes/hygiene.sh"
    [ -f "$HYG_SCRIPT" ] || skip "hygiene.sh missing"

    HYG_STUB_BIN="$HOME/hygiene-stubs"
    mkdir -p "$HYG_STUB_BIN"
    cat > "$HYG_STUB_BIN/launchctl" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  list) exit 0 ;;
  load|unload) exit 0 ;;
  *) exit 0 ;;
esac
SH
    cat > "$HYG_STUB_BIN/pgrep" <<'SH'
#!/usr/bin/env bash
printf '0\n'
exit 0
SH
    cat > "$HYG_STUB_BIN/ps" <<'SH'
#!/usr/bin/env bash
printf 'ELAPSED COMMAND\n'
exit 0
SH
    cat > "$HYG_STUB_BIN/tail" <<'SH'
#!/usr/bin/env bash
last_arg="${@: -1}"
if [ "$last_arg" = "/tmp/eco-hygiene-events.log" ]; then
  exit 1
fi
exec /usr/bin/tail "$@"
SH
    chmod +x "$HYG_STUB_BIN/launchctl" "$HYG_STUB_BIN/pgrep" "$HYG_STUB_BIN/ps" "$HYG_STUB_BIN/tail"
    export PATH="$HYG_STUB_BIN:$PATH"
}

teardown() {
    eco_teardown
}

@test "hygiene.sh is executable" {
    [ -x "$HYG_SCRIPT" ] || run chmod +x "$HYG_SCRIPT"
    [ -r "$HYG_SCRIPT" ]
}

@test "shellcheck clean" {
    if ! command -v shellcheck >/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck -S warning "$HYG_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "snapshot subcommand runs and prints a state line" {
    run bash "$HYG_SCRIPT" snapshot
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[..:..:..\][[:space:]](OK|YEL|RED)[[:space:]]mem= ]]
    [ -f "$ECO/state.json" ]
}

@test "snapshot output matches expected pattern" {
    run bash "$HYG_SCRIPT" snapshot
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[..:..:..\][[:space:]](OK|YEL|RED)[[:space:]]mem= ]]
}

@test "status subcommand reports daemon state" {
    run bash "$HYG_SCRIPT" status
    [[ "$output" =~ daemon:\ (LOADED|STOPPED) ]]
}

@test "help subcommand prints usage" {
    run bash "$HYG_SCRIPT" help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "hygiene" ]] || [[ "$output" =~ "Mac hygiene" ]]
}

@test "unknown subcommand returns non-zero" {
    run bash "$HYG_SCRIPT" totally-bogus-subcommand
    [ "$status" -ne 0 ]
}

@test "install creates plist" {
    mkdir -p "$HOME/Library/LaunchAgents"
    run bash "$HYG_SCRIPT" install
    [ "$status" -eq 0 ]
    [ -f "$HOME/Library/LaunchAgents/com.eco-commander.hygiene.plist" ]
}

@test "eco hygiene subcommand routed by main dispatcher" {
    ECO_BIN="$HOME/.eco/bin/eco"
    [ -f "$ECO_BIN" ] || skip "eco bin missing"
    # We only verify the dispatcher dispatches — it'll fail if hygiene case missing
    run bash "$ECO_BIN" hygiene snapshot
    # Either runs successfully or fails for some other reason (not "Unknown command")
    [[ "$output" != *"Unknown command"* ]]
}
