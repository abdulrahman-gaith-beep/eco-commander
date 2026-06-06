#!/usr/bin/env bash
# Remove eco-commander LaunchAgents. Preserves logs and snapshots.
set -euo pipefail

LA_DST="${ECO_LAUNCHAGENTS_DIR:-${LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}}"

die() { printf "uninstall-launchagents: %s\n" "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
  die "do not run with sudo/root; uninstall LaunchAgents as the target macOS user"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

validate_install_path ECO_LAUNCHAGENTS_DIR "$LA_DST"

remove_plist_if_ours() {
  local label="$1"
  local plist="$LA_DST/$label.plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  [ -e "$plist" ] || [ -L "$plist" ] || return 0
  if [ -L "$plist" ]; then
    echo "skipping symlinked plist: $plist"
    return 0
  fi
  [ -f "$plist" ] || die "refusing to remove non-file plist path: $plist"
  if plist_label_matches "$plist" "$label"; then
    rm -f "$plist"
    echo "removed $plist"
  else
    echo "skipping plist with unexpected label: $plist"
  fi
}

for label in \
  com.eco-commander.usage-poller \
  com.eco-commander.swiftbar \
  com.eco-commander.scheduler; do
  remove_plist_if_ours "$label"
done
