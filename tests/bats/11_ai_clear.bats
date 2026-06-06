#!/usr/bin/env bats
# tests/bats/11_ai_clear.bats — tests for src/bin/ai-clear.sh
#
# Exercises the deprecated compatibility command. It must not contact Ollama or
# unload models.
#
# Run: bats tests/bats/11_ai_clear.bats

setup() {
    REAL_SCRIPT="$BATS_TEST_DIRNAME/../../src/bin/ai-clear.sh"
    [ -f "$REAL_SCRIPT" ] || skip "ai-clear.sh missing"

    # Sandbox
    export HOME="$BATS_TEST_TMPDIR"
    MOCK_BIN="$BATS_TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    SCRIPT="$BATS_TEST_TMPDIR/ai-clear.sh"
    cp "$REAL_SCRIPT" "$SCRIPT"
    chmod +x "$SCRIPT"

    # Stubs should never be called by the deprecated no-op command.
    cat > "$MOCK_BIN/curl" <<'SH'
#!/usr/bin/env bash
echo "curl should not be called: $*" >&2
exit 99
SH
    chmod +x "$MOCK_BIN/curl"

    # Prepend mock bin to PATH (for curl override)
    export PATH="$MOCK_BIN:$PATH"
}

@test "ai-clear.sh is executable" {
    [ -x "$SCRIPT" ]
    [ -r "$SCRIPT" ]
    cmp -s "$REAL_SCRIPT" "$SCRIPT"
}

@test "shellcheck clean" {
    if ! command -v shellcheck >/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck -S warning "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "ai-clear is a no-op and does not unload models" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
    [[ "$output" == *"intentionally does not unload"* ]]
    [[ "$output" == *"Ready for agent swarm"* ]]
}

@test "does not require curl" {
    export PATH="/usr/bin:/bin"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
}

@test "does not require python3" {
    export PATH="/bin"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deprecated"* ]]
}

@test "does not call curl even when curl exists" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"curl should not be called"* ]]
}

@test "manual unload guidance is explicit" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama stop <model>"* ]]
}
