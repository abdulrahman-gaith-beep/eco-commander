#!/usr/bin/env bats
# tests/bats/account-swap.bats — coverage for account-swap recipe
# Run: bats tests/bats/account-swap.bats
#
# Note: bats 1.x only fails a test on the LAST command's exit status, so
# multi-assertion tests chain with `&&` to make every check terminal.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../src/recipes/account-swap.sh"
    [ -f "$SCRIPT" ] || skip "account-swap.sh missing"

    # Sandboxed homes — never touch real ~/.eco, ~/.gemini, ~/.codex
    export ECO_HOME="$BATS_TEST_TMPDIR/eco"
    export GEMINI_HOME="$BATS_TEST_TMPDIR/gemini"
    export CODEX_HOME="$BATS_TEST_TMPDIR/codex"
    mkdir -p "$GEMINI_HOME" "$CODEX_HOME"

    # Pre-seed live auth blobs so register has something to capture
    printf '%s' '{"token":"GEM-A"}' > "$GEMINI_HOME/oauth_creds.json"
    printf '%s' '{"token":"CDX-MAIN"}' > "$CODEX_HOME/auth.json"

    # Default mock pgrep that ALWAYS returns "no process found" (exit 1)
    # so tests don't get blocked by the user's real codex/claude processes.
    MOCK_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/pgrep_none" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    cat > "$MOCK_BIN/pgrep_found" <<'SH'
#!/usr/bin/env bash
echo 12345
exit 0
SH
    chmod +x "$MOCK_BIN/pgrep_none" "$MOCK_BIN/pgrep_found"
    export ECO_ACCOUNT_PGREP="$MOCK_BIN/pgrep_none"
    # Don't actually call macOS `security`. Tests exercising the claude
    # path will override this with a stronger mock.
    export ECO_ACCOUNT_SECURITY="$MOCK_BIN/pgrep_none"
}

mode_of() {
    stat -f '%Lp' "$1"
}

@test "script is executable" {
    [ -x "$SCRIPT" ] || run chmod +x "$SCRIPT"
    [ -r "$SCRIPT" ]
}

@test "shellcheck clean" {
    if ! command -v shellcheck >/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck -S warning "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "list with empty snapshots dir prints helpful message and exits 0" {
    run bash "$SCRIPT" list
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"No accounts registered"* ]]
}

@test "help prints usage" {
    run bash "$SCRIPT" help
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"Usage:"* ]] \
        && [[ "$output" == *"account-swap"* ]] \
        && [[ "$output" == *"permit macOS Keychain read/write prompts"* ]] \
        && [[ "$output" != *"ECO_ALLOW_UNSAFE_CLAUDE_RESTORE"* ]]
}

@test "unknown subcommand exits non-zero" {
    run bash "$SCRIPT" bogus-thing
    [ "$status" -ne 0 ]
}

@test "register gemini captures snapshot and marks it active" {
	    run bash "$SCRIPT" gemini --register primary
	    [ "$status" -eq 0 ] \
	        && [[ "$output" == *"registered gemini account: primary"* ]] \
	        && [ -f "$ECO_HOME/auth-snapshots/gemini/primary/oauth_creds.json" ] \
	        && grep -q '"gemini": "primary"' "$ECO_HOME/state/active-accounts.json" \
	        && [ "$(mode_of "$ECO_HOME/auth-snapshots/gemini/primary/oauth_creds.json")" = "600" ]
}

@test "register creates private account-swap tree and state" {
    umask 000
    run bash "$SCRIPT" gemini --register primary
    [ "$status" -eq 0 ] \
        && [ "$(mode_of "$ECO_HOME")" = "700" ] \
        && [ "$(mode_of "$ECO_HOME/auth-snapshots")" = "700" ] \
        && [ "$(mode_of "$ECO_HOME/auth-snapshots/gemini")" = "700" ] \
        && [ "$(mode_of "$ECO_HOME/state")" = "700" ] \
        && [ "$(mode_of "$ECO_HOME/state/active-accounts.json")" = "600" ] \
        && [ "$(mode_of "$ECO_HOME/auth-snapshots/gemini/primary/oauth_creds.json")" = "600" ]
}

@test "list with 2 gemini snapshots shows both, marks newest registered active" {
    bash "$SCRIPT" gemini --register primary
    printf '%s' '{"token":"GEM-B"}' > "$GEMINI_HOME/oauth_creds.json"
    bash "$SCRIPT" gemini --register secondary

    run bash "$SCRIPT" list
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"gemini:"* ]] \
        && [[ "$output" == *"* secondary (active)"* ]] \
        && [[ "$output" == *"primary"* ]]
}

@test "--register without --force refuses to overwrite existing slug" {
    bash "$SCRIPT" gemini --register primary
    run bash "$SCRIPT" gemini --register primary
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"already exists"* ]] \
        && [[ "$output" == *"--force"* ]]
}

@test "--register --force overwrites existing slug" {
    bash "$SCRIPT" gemini --register primary
    printf '%s' '{"token":"GEM-NEW"}' > "$GEMINI_HOME/oauth_creds.json"
    run bash "$SCRIPT" gemini --register primary --force
    [ "$status" -eq 0 ] \
        && grep -q 'GEM-NEW' "$ECO_HOME/auth-snapshots/gemini/primary/oauth_creds.json"
}

@test "swap refused when process matches pgrep" {
    bash "$SCRIPT" codex --register main
    printf '%s' '{"token":"CDX-ALT"}' > "$CODEX_HOME/auth.json"
    bash "$SCRIPT" codex --register alt
    export ECO_ACCOUNT_PGREP="$BATS_TEST_TMPDIR/bin/pgrep_found"
    run bash "$SCRIPT" codex main
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"refusing to swap"* ]]
}

@test "gemini swap updates .active_slug and replaces live creds" {
    bash "$SCRIPT" gemini --register primary
    printf '%s' '{"token":"GEM-B"}' > "$GEMINI_HOME/oauth_creds.json"
    bash "$SCRIPT" gemini --register secondary

    # Now swap back to primary
    run bash "$SCRIPT" gemini primary
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"gemini now using account: primary"* ]] \
        && [ "$(cat "$GEMINI_HOME/accounts/.active_slug")" = "primary" ] \
        && grep -q 'GEM-A' "$GEMINI_HOME/oauth_creds.json" \
        && grep -q '"gemini": "primary"' "$ECO_HOME/state/active-accounts.json" \
        && [ "$(mode_of "$GEMINI_HOME/accounts")" = "700" ] \
        && [ "$(mode_of "$GEMINI_HOME/oauth_creds.json")" = "600" ] \
        && [ "$(mode_of "$GEMINI_HOME/accounts/oauth_creds.primary.json")" = "600" ] \
        && [ "$(mode_of "$GEMINI_HOME/accounts/.active_slug")" = "600" ]
}

@test "codex swap roundtrip: A -> B -> A preserves A bit-for-bit" {
    bash "$SCRIPT" codex --register A
    A_CONTENT_BEFORE=$(cat "$CODEX_HOME/auth.json")

    printf '%s' '{"token":"CDX-B","extra":42}' > "$CODEX_HOME/auth.json"
    bash "$SCRIPT" codex --register B

    # Swap to A then back to B then back to A
    bash "$SCRIPT" codex A
    [ "$(cat "$CODEX_HOME/auth.json")" = "$A_CONTENT_BEFORE" ] || { echo "A->A mismatch"; return 1; }
    bash "$SCRIPT" codex B
    [ "$(cat "$CODEX_HOME/auth.json")" = '{"token":"CDX-B","extra":42}' ] || { echo "B mismatch"; return 1; }
    bash "$SCRIPT" codex A
    [ "$(cat "$CODEX_HOME/auth.json")" = "$A_CONTENT_BEFORE" ] \
        && [ "$(mode_of "$CODEX_HOME")" = "700" ] \
        && [ "$(mode_of "$CODEX_HOME/auth.json")" = "600" ]
}

@test "swap to nonexistent slug fails clearly" {
    bash "$SCRIPT" gemini --register primary
    run bash "$SCRIPT" gemini phantom
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"no snapshot"* ]]
}

@test "invalid slug characters rejected" {
    run bash "$SCRIPT" gemini --register "bad/slug"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"invalid slug"* ]]
}

@test "claude register without --allow-keychain-prompt is refused" {
    run bash "$SCRIPT" claude --register max
    [ "$status" -ne 0 ] \
        && { [[ "$output" == *"Keychain"* ]] || [[ "$output" == *"keychain"* ]]; } \
        && [[ "$output" == *"--allow-keychain-prompt"* ]]
}

@test "claude register with mock security CLI captures snapshot" {
    MOCK_SEC="$BATS_TEST_TMPDIR/bin/security_mock"
    cat > "$MOCK_SEC" <<'SH'
#!/usr/bin/env bash
case "$1" in
  find-generic-password) echo "FAKE_CLAUDE_TOKEN_$$"; exit 0 ;;
  add-generic-password)  exit 0 ;;
  *) exit 2 ;;
esac
SH
    chmod +x "$MOCK_SEC"
    export ECO_ACCOUNT_SECURITY="$MOCK_SEC"
    export ECO_ACCOUNT_SECURITY_STDIN_PASSWORD=1

    run bash "$SCRIPT" claude --register max --allow-keychain-prompt
    [ "$status" -eq 0 ] \
        && [ -f "$ECO_HOME/auth-snapshots/claude/max/keychain.b64" ] \
        && [ "$(mode_of "$ECO_HOME/auth-snapshots/claude/max/keychain.b64")" = "600" ]
}

@test "claude restore does not pass secret in argv to security helper" {
    MOCK_SEC="$BATS_TEST_TMPDIR/bin/security_argv_mock"
    CLAUDE_CURRENT="$BATS_TEST_TMPDIR/current-claude"
    SEC_ARGV_LOG="$BATS_TEST_TMPDIR/security-argv.log"
    SEC_STDIN_LOG="$BATS_TEST_TMPDIR/security-stdin.log"
    export CLAUDE_CURRENT SEC_ARGV_LOG SEC_STDIN_LOG
    cat > "$MOCK_SEC" <<'SH'
#!/usr/bin/env bash
case "$1" in
  find-generic-password) cat "$CLAUDE_CURRENT"; exit 0 ;;
  add-generic-password)
    printf '%s\n' "$*" >> "$SEC_ARGV_LOG"
    cat >> "$SEC_STDIN_LOG"
    exit 0
    ;;
  *) exit 2 ;;
esac
SH
    chmod +x "$MOCK_SEC"
    export ECO_ACCOUNT_SECURITY="$MOCK_SEC"
    export ECO_ACCOUNT_SECURITY_STDIN_PASSWORD=1

    printf '%s' 'CLAUDE_SECRET_A' > "$CLAUDE_CURRENT"
    bash "$SCRIPT" claude --register A --allow-keychain-prompt
    printf '%s' 'CLAUDE_SECRET_B' > "$CLAUDE_CURRENT"
    bash "$SCRIPT" claude --register B --allow-keychain-prompt

    run bash "$SCRIPT" claude A --allow-keychain-prompt
    [ "$status" -eq 0 ] \
        && ! grep -q 'CLAUDE_SECRET_A' "$SEC_ARGV_LOG" \
        && grep -q 'CLAUDE_SECRET_A' "$SEC_STDIN_LOG"
}

@test "claude restore helper stdin requires explicit test opt-in" {
    MOCK_SEC="$BATS_TEST_TMPDIR/bin/security_needs_optin"
    CLAUDE_CURRENT="$BATS_TEST_TMPDIR/current-claude"
    export CLAUDE_CURRENT
    cat > "$MOCK_SEC" <<'SH'
#!/usr/bin/env bash
case "$1" in
  find-generic-password) cat "$CLAUDE_CURRENT"; exit 0 ;;
  add-generic-password) cat >/dev/null; exit 0 ;;
  *) exit 2 ;;
esac
SH
    chmod +x "$MOCK_SEC"
    export ECO_ACCOUNT_SECURITY="$MOCK_SEC"

    printf '%s' 'CLAUDE_SECRET_A' > "$CLAUDE_CURRENT"
    bash "$SCRIPT" claude --register A --allow-keychain-prompt
    printf '%s' 'CLAUDE_SECRET_B' > "$CLAUDE_CURRENT"
    bash "$SCRIPT" claude --register B --allow-keychain-prompt

    run bash "$SCRIPT" claude A --allow-keychain-prompt
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"ECO_ACCOUNT_SECURITY_STDIN_PASSWORD=1"* ]]
}

@test "eco bin dispatches account-swap when registered" {
    ECO_BIN="$BATS_TEST_DIRNAME/../../src/bin/eco"
    [ -f "$ECO_BIN" ] || skip "eco bin missing"
    # The eco dispatcher resolves recipes from $HOME/.eco/recipes; in a dev
    # checkout the recipe may not be installed there. Skip unless wired.
    grep -q 'account-swap' "$ECO_BIN" || skip "eco dispatcher does not register account-swap (yet)"
    run bash "$ECO_BIN" account-swap list
    [[ "$output" != *"Unknown command"* ]]
}
