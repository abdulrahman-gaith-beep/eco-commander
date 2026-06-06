#!/usr/bin/env bash
# Eco Commander bootstrap — installs SwiftBar + wires the plugin.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"
WIDGET="$ECO_HOME/bin/eco-commander.15s.sh"
SWIFTBAR_PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/Library/Application Support/SwiftBar/Plugins}"

die() { printf "install-commander: %s\n" "$*" >&2; exit 1; }

# shellcheck source=../../scripts/lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
  die "do not run with sudo/root; install as the target macOS user"
fi

validate_install_path SWIFTBAR_PLUGIN_DIR "$SWIFTBAR_PLUGIN_DIR"

remove_link_if_ours() {
  local link="$1"
  [ -e "$link" ] || [ -L "$link" ] || return 0
  [ -L "$link" ] || return 0
  local target
  target="$(readlink "$link")"
  if [[ "$target" == "$ECO_HOME/bin/"* ]]; then
    rm -f "$link"
  fi
}

replace_symlink_if_safe() {
  local src="$1" dst="$2"
  [ -e "$src" ] || die "widget missing: $src"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    [ -L "$dst" ] || die "refusing to overwrite non-symlink plugin: $dst"
    local target
    target="$(readlink "$dst")"
    [[ "$target" == "$ECO_HOME/bin/"* ]] || die "refusing to overwrite foreign symlink: $dst -> $target"
    rm -f "$dst"
  fi
  ln -s "$src" "$dst"
}

echo "=== Eco Commander setup ==="

if [ ! -d "/Applications/SwiftBar.app" ]; then
  echo "SwiftBar not installed."
  if command -v brew >/dev/null 2>&1; then
    read -r -p "Install SwiftBar now via brew? [y/N] " ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      brew install --cask swiftbar
    else
      echo "Skipping SwiftBar install. You can still run the widget manually:"
      echo "  $WIDGET --cli"
      exit 0
    fi
  else
    echo "Homebrew not found. Install it (https://brew.sh) then re-run this script."
    exit 1
  fi
fi

chmod +x "$WIDGET"
ensure_owned_dir "$SWIFTBAR_PLUGIN_DIR"

for old_plugin in eco-commander.30s.sh usage-monitor.15s.sh; do
  remove_link_if_ours "$SWIFTBAR_PLUGIN_DIR/$old_plugin"
done
replace_symlink_if_safe "$WIDGET" "$SWIFTBAR_PLUGIN_DIR/eco-commander.15s.sh"

echo
echo "Installed:"
echo "  widget:   $WIDGET"
echo "  plugin:   $SWIFTBAR_PLUGIN_DIR/eco-commander.15s.sh -> widget"
echo
echo "Next steps:"
echo "  1. Open SwiftBar and choose the plugin folder if prompted:"
echo "     $SWIFTBAR_PLUGIN_DIR"
echo "  2. Preview in a terminal:"
echo "     $WIDGET --cli"
