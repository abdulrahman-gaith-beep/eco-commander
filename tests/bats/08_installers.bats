#!/usr/bin/env bats
# 08_installers.bats — installer safety checks.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
ORIG_HOME="${HOME:-}"
ORIG_PATH="${PATH:-}"

setup() {
  unset SUDO_USER ECO_INSTALL_LAUNCHAGENTS ECO_SCHEDULER_PERSIST ECO_SCHEDULER_AUTO_LOAD
  export HOME="$BATS_TEST_TMPDIR/home"
  export ECO_HOME="$HOME/.eco"
  export ECO_LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
  export SWIFTBAR_PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
  mkdir -p "$HOME" "$(dirname "$SWIFTBAR_PLUGIN_DIR")" "$(dirname "$ECO_LAUNCHAGENTS_DIR")"

  export STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/launchctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${LAUNCHCTL_LOG:?}"
exit 0
SH
  chmod +x "$STUB_BIN/launchctl"
  export PATH="$STUB_BIN:$ORIG_PATH"
  export LAUNCHCTL_LOG="$BATS_TEST_TMPDIR/launchctl.log"
}

teardown() {
  export HOME="$ORIG_HOME"
  export PATH="$ORIG_PATH"
}

@test "installer scripts contain no rm -rf" {
  run rg -n "rm -rf" \
    "$REPO_ROOT/scripts/install.sh" \
    "$REPO_ROOT/scripts/uninstall.sh" \
    "$REPO_ROOT/scripts/install-launchagents.sh" \
    "$REPO_ROOT/scripts/uninstall-launchagents.sh"
  [ "$status" -eq 1 ]
}

@test "install.sh refuses sudo/root environment before writes" {
  export SUDO_USER=testuser
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sudo/root"* ]]
  [ ! -e "$ECO_HOME/bin" ]
}

@test "install.sh refuses to clobber foreign bin file" {
  mkdir -p "$ECO_HOME/bin"
  printf 'keep me\n' > "$ECO_HOME/bin/eco"
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to overwrite non-symlink"* ]]
  [ "$(cat "$ECO_HOME/bin/eco")" = "keep me" ]
}

@test "install.sh refuses sensitive ECO_HOME path by string" {
  export ECO_HOME="$HOME/Library/Keychains/eco"
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive install path"* ]]
}

@test "install.sh refuses symlinked ECO_HOME" {
  target="$BATS_TEST_TMPDIR/real-eco"
  mkdir -p "$target"
  ln -s "$target" "$ECO_HOME"
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlinked install path"* ]]
}

@test "install.sh refuses symlinked ECO_HOME parent" {
  real_parent="$BATS_TEST_TMPDIR/real-parent"
  link_parent="$BATS_TEST_TMPDIR/link-parent"
  mkdir -p "$real_parent"
  ln -s "$real_parent" "$link_parent"
  export ECO_HOME="$link_parent/.eco"
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlinked ancestor"* ]]
}

@test "install.sh preserves foreign legacy SwiftBar files" {
  mkdir -p "$SWIFTBAR_PLUGIN_DIR"
  printf 'foreign\n' > "$SWIFTBAR_PLUGIN_DIR/usage-monitor.15s.sh"
  run bash "$REPO_ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$SWIFTBAR_PLUGIN_DIR/usage-monitor.15s.sh")" = "foreign" ]
}

@test "install-launchagents.sh does not install scheduler by default" {
  export ECO_LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
  run bash "$REPO_ROOT/scripts/install-launchagents.sh"
  [ "$status" -eq 0 ]
  [ -f "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.usage-poller.plist" ]
  [ ! -e "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.scheduler.plist" ]
}

@test "install-launchagents.sh persists scheduler only when explicit" {
  export ECO_LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
  export ECO_SCHEDULER_PERSIST=1
  run bash "$REPO_ROOT/scripts/install-launchagents.sh"
  [ "$status" -eq 0 ]
  [ -f "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.scheduler.plist" ]
  ! grep -q "com.eco-commander.scheduler" "$LAUNCHCTL_LOG"
}

@test "install-launchagents.sh refuses foreign existing plist label" {
  export ECO_LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$ECO_LAUNCHAGENTS_DIR"
  cat > "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.usage-poller.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>foreign.label</string></dict></plist>
XML
  run bash "$REPO_ROOT/scripts/install-launchagents.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected label"* ]]
  grep -q "foreign.label" "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.usage-poller.plist"
}

@test "install-launchagents.sh refuses symlinked LaunchAgents parent" {
  real_parent="$BATS_TEST_TMPDIR/real-la-parent"
  link_parent="$BATS_TEST_TMPDIR/link-la-parent"
  mkdir -p "$real_parent"
  ln -s "$real_parent" "$link_parent"
  export ECO_LAUNCHAGENTS_DIR="$link_parent/LaunchAgents"
  run bash "$REPO_ROOT/scripts/install-launchagents.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlinked ancestor"* ]]
}

@test "uninstall-launchagents.sh skips plist with foreign Label key" {
  export ECO_LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$ECO_LAUNCHAGENTS_DIR"
  cat > "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.scheduler.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>foreign.label</string></dict></plist>
XML
  run bash "$REPO_ROOT/scripts/uninstall-launchagents.sh"
  [ "$status" -eq 0 ]
  [ -f "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.scheduler.plist" ]
}

@test "uninstall-launchagents.sh removes scheduler plist too" {
  export ECO_LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$ECO_LAUNCHAGENTS_DIR"
  for label in com.eco-commander.usage-poller com.eco-commander.swiftbar com.eco-commander.scheduler; do
    cat > "$ECO_LAUNCHAGENTS_DIR/$label.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>$label</string></dict></plist>
XML
  done
  run bash "$REPO_ROOT/scripts/uninstall-launchagents.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.usage-poller.plist" ]
  [ ! -e "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.swiftbar.plist" ]
  [ ! -e "$ECO_LAUNCHAGENTS_DIR/com.eco-commander.scheduler.plist" ]
}
