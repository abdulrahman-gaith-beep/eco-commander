#!/usr/bin/env bash
# Remove symlinks created by scripts/install.sh. Preserves data.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"
SWIFTBAR_PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/Library/Application Support/SwiftBar/Plugins}"

log() { printf "[uninstall] %s\n" "$*"; }
die() { printf "[uninstall] error: %s\n" "$*" >&2; exit 1; }

# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
  die "do not run uninstaller with sudo/root; uninstall as the target macOS user"
fi

validate_install_path ECO_HOME "$ECO_HOME"
validate_install_path SWIFTBAR_PLUGIN_DIR "$SWIFTBAR_PLUGIN_DIR"

remove_link_if_ours() {
  local link=$1; shift
  if [[ -L "$link" ]]; then
    local target prefix
    target=$(readlink "$link")
    for prefix in "$@"; do
      if [[ "$target" == "$prefix"* ]]; then
        rm -f "$link"
        log "removed $link"
        return 0
      fi
    done
  fi
}

for src in "$REPO_ROOT"/src/bin/*; do
  remove_link_if_ours "$ECO_HOME/bin/$(basename "$src")" "$REPO_ROOT/src/bin/"
done

for legacy_bin in eco-commander.30s.sh usage-monitor.15s.sh; do
  remove_link_if_ours "$ECO_HOME/bin/$legacy_bin" "$REPO_ROOT/src/bin/"
done

for src in "$REPO_ROOT"/src/recipes/*.sh; do
  [[ -e "$src" ]] || continue
  remove_link_if_ours "$ECO_HOME/recipes/$(basename "$src")" "$REPO_ROOT/src/recipes/"
done

for plugin in eco-commander.15s.sh eco-commander.30s.sh usage-monitor.15s.sh; do
  remove_link_if_ours "$SWIFTBAR_PLUGIN_DIR/$plugin" "$REPO_ROOT/src/bin/" "$ECO_HOME/bin/"
done

# LaunchAgents
bash "$REPO_ROOT/scripts/uninstall-launchagents.sh"

# Optional system newsyslog drop-in
bash "$REPO_ROOT/scripts/uninstall-log-rotation.sh"

log "done. Snapshots and outputs preserved."
