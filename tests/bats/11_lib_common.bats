#!/usr/bin/env bats
# 11_lib_common.bats — tests for scripts/lib/common.sh shared functions
#
# Validates validate_install_path and plist_label_matches from the
# extracted shared library.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export ECO_HOME="$HOME/.eco"
  mkdir -p "$HOME"
}

# Helper: run validate_install_path in a subshell that sources common.sh.
# die() calls exit 1, so we must isolate it.
_run_validate() {
  local label="$1" path="$2"
  bash -c '
    die() { printf "DIE: %s\n" "$*" >&2; exit 1; }
    source "'"$REPO_ROOT"'/scripts/lib/common.sh"
    validate_install_path "$@"
  ' -- "$label" "$path"
}

# Helper: source common.sh in the current shell (for non-exit functions)
_source_common() {
  source "$REPO_ROOT/scripts/lib/common.sh"
}

# ── validate_install_path ────────────────────────────────────────────

@test "lib/common: validate_install_path accepts normal path" {
  run _run_validate TEST "$HOME/.eco"
  [ "$status" -eq 0 ]
}

@test "lib/common: validate_install_path accepts tilde eco path" {
  run _run_validate TEST "~/.eco"
  [ "$status" -eq 0 ]
}

@test "lib/common: validate_install_path accepts default ECO_HOME" {
  mkdir -p "$HOME/.eco"
  printf 'local file\n' > "$HOME/.eco/local.txt"
  run _run_validate ECO_HOME "~/.eco"
  [ "$status" -eq 0 ]
}

@test "lib/common: validate_install_path accepts empty custom ECO_HOME" {
  mkdir -p "$HOME/custom-eco"
  run _run_validate ECO_HOME "$HOME/custom-eco"
  [ "$status" -eq 0 ]
}

@test "lib/common: validate_install_path accepts marked custom ECO_HOME" {
  mkdir -p "$HOME/custom-eco/bin"
  printf '#!/usr/bin/env bash\n' > "$HOME/custom-eco/bin/eco-commander.15s.sh"
  run _run_validate ECO_HOME "$HOME/custom-eco"
  [ "$status" -eq 0 ]
}

@test "lib/common: validate_install_path rejects existing unmarked ECO_HOME" {
  mkdir -p "$HOME/Documents"
  printf 'keep me\n' > "$HOME/Documents/notes.txt"
  run _run_validate ECO_HOME "$HOME/Documents"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unmarked ECO_HOME"* ]]
}

@test "lib/common: validate_install_path rejects system ECO_HOME" {
  run _run_validate ECO_HOME "/usr/local/eco-commander"
  [ "$status" -ne 0 ]
  [[ "$output" == *"system/package-manager ECO_HOME"* ]]
}

@test "lib/common: validate_install_path rejects system SwiftBar plugin dir" {
  run _run_validate SWIFTBAR_PLUGIN_DIR "/Library/Application Support/SwiftBar/Plugins"
  [ "$status" -ne 0 ]
  [[ "$output" == *"system/package-manager SWIFTBAR_PLUGIN_DIR"* ]]
}

@test "lib/common: validate_install_path rejects system LaunchAgents dir" {
  run _run_validate ECO_LAUNCHAGENTS_DIR "/Library/LaunchAgents"
  [ "$status" -ne 0 ]
  [[ "$output" == *"system/package-manager ECO_LAUNCHAGENTS_DIR"* ]]
}

@test "lib/common: validate_install_path rejects empty path" {
  run _run_validate TEST ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "lib/common: validate_install_path rejects root path" {
  run _run_validate TEST "/"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be /"* ]]
}

@test "lib/common: validate_install_path rejects bare home path" {
  run _run_validate TEST "$HOME"
  [ "$status" -ne 0 ]
  [[ "$output" == *"home directory"* ]]
}

@test "lib/common: validate_install_path rejects relative path" {
  run _run_validate TEST ".eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute path"* ]]
}

@test "lib/common: validate_install_path rejects dot path" {
  run _run_validate TEST "."
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute path"* ]]
}

@test "lib/common: validate_install_path rejects Keychains path" {
  run _run_validate TEST "$HOME/Library/Keychains/eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive install path"* ]]
}

@test "lib/common: validate_install_path rejects iCloud path" {
  run _run_validate TEST "$HOME/Library/Mobile Documents/eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive install path"* ]]
}

@test "lib/common: validate_install_path rejects CloudStorage iCloud path" {
  run _run_validate TEST "$HOME/Library/CloudStorage/iCloud Drive/eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive install path"* ]]
}

@test "lib/common: validate_install_path rejects dot-dot bypass into iCloud path" {
  run _run_validate TEST "$HOME/Library/../Library/Mobile Documents/eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *".. components"* ]]
}

@test "lib/common: validate_install_path rejects .ssh path" {
  run _run_validate TEST "$HOME/.ssh/eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive install path"* ]]
}

@test "lib/common: validate_install_path rejects dot-dot bypass into .ssh path" {
  run _run_validate TEST "$HOME/Library/../.ssh/eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *".. components"* ]]
}

@test "lib/common: validate_install_path rejects another user's home" {
  foreign_home="/Users"
  run _run_validate TEST "$foreign_home/example-foreign/eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside your home directory"* ]]
}

@test "lib/common: validate_install_path rejects symlinked path" {
  target="$BATS_TEST_TMPDIR/real"
  mkdir -p "$target"
  ln -s "$target" "$BATS_TEST_TMPDIR/link"
  run _run_validate TEST "$BATS_TEST_TMPDIR/link"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlinked install path"* ]]
}

@test "lib/common: validate_install_path rejects symlinked parent" {
  real_parent="$BATS_TEST_TMPDIR/real-parent"
  link_parent="$BATS_TEST_TMPDIR/link-parent"
  mkdir -p "$real_parent"
  ln -s "$real_parent" "$link_parent"
  run _run_validate TEST "$link_parent/.eco"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlinked ancestor"* ]]
}

# ── plist_label_matches ──────────────────────────────────────────────

@test "lib/common: plist_label_matches returns 0 for matching label" {
  _source_common
  plist="$BATS_TEST_TMPDIR/test.plist"
  cat > "$plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>com.test.label</string></dict></plist>
XML
  run plist_label_matches "$plist" "com.test.label"
  [ "$status" -eq 0 ]
}

@test "lib/common: plist_label_matches returns 1 for mismatched label" {
  _source_common
  plist="$BATS_TEST_TMPDIR/test.plist"
  cat > "$plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>com.test.label</string></dict></plist>
XML
  run plist_label_matches "$plist" "com.other.label"
  [ "$status" -ne 0 ]
}

@test "lib/common: plist_label_matches returns 1 for missing file" {
  _source_common
  run plist_label_matches "/nonexistent/file.plist" "any.label"
  [ "$status" -ne 0 ]
}

# ── source guard ─────────────────────────────────────────────────────

@test "lib/common: source guard prevents double-loading" {
  unset _ECO_LIB_COMMON_LOADED
  source "$REPO_ROOT/scripts/lib/common.sh"
  [ "$_ECO_LIB_COMMON_LOADED" = "1" ]
  # Second source should return immediately (no error)
  source "$REPO_ROOT/scripts/lib/common.sh"
  [ "$_ECO_LIB_COMMON_LOADED" = "1" ]
}
