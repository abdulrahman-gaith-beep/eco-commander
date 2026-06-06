#!/usr/bin/env bash
# Install newsyslog rotation rules for eco-commander logs.
#
# macOS runs `newsyslog` daily via a system LaunchDaemon
# (com.apple.newsyslog) that reads /etc/newsyslog.conf and any drop-ins
# in /etc/newsyslog.d/. We install a single drop-in there.
#
# This requires sudo because /etc/newsyslog.d/ is root-owned. We do NOT
# put it in install.sh's default flow; run this once manually:
#
#   bash scripts/install-log-rotation.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/scripts/log-rotate.conf"
DST="/etc/newsyslog.d/eco-commander.conf"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"

die() { printf "install-log-rotation: %s\n" "$*" >&2; exit 1; }

# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
  die "do not run with sudo/root; install log rotation as the target macOS user"
fi

validate_install_path ECO_HOME "$ECO_HOME"

[ -f "$SRC" ] || die "source config missing: $SRC"
MARKER="$(sed -n '1p' "$SRC")"
[ -n "$MARKER" ] || die "source marker missing: $SRC line 1"

validate_destination_owner() {
  local dst_marker

  [ ! -L "$DST" ] || die "refusing to overwrite symlink: $DST"
  [ ! -d "$DST" ] || die "refusing to overwrite directory: $DST"

  if [ -e "$DST" ] && [ ! -f "$DST" ]; then
    die "refusing to overwrite non-regular file: $DST"
  fi

  if [ -f "$DST" ]; then
    if ! dst_marker="$(sed -n '1p' "$DST" 2>/dev/null)"; then
      die "refusing to inspect existing destination; check permissions: $DST"
    fi
    [ "$dst_marker" = "$MARKER" ] || die "refusing to overwrite existing file without eco-commander marker: $DST"
  fi
}

validate_destination_owner

# Pre-create log files if absent so newsyslog can stat them.
ensure_owned_dir "$ECO_HOME" 0700
ensure_owned_dir "$ECO_HOME/logs" 0700
for f in usage-poller.out.log usage-poller.err.log usage-snapshot.err.log \
         swiftbar-autostart.out.log swiftbar-autostart.err.log \
         scheduler.out.log scheduler.err.log; do
  touch "$ECO_HOME/logs/$f"
done

# Render template variables.
TMP_RENDERED=$(mktemp "${DST}.XXXXXX" 2>/dev/null || mktemp)
sed -e "s|__ECO_HOME__|${ECO_HOME}|g" \
    -e "s|__USER__|$(whoami)|g" \
    "$SRC" > "$TMP_RENDERED"

if [ -f "$DST" ] && cmp -s "$TMP_RENDERED" "$DST"; then
  rm -f "$TMP_RENDERED"
  echo "✓ already installed (no change): $DST"
  exit 0
fi

echo "Installing newsyslog rule (requires sudo): $DST"
sudo install -m 0644 -o root -g wheel "$TMP_RENDERED" "$DST"
rm -f "$TMP_RENDERED"

# Validate; newsyslog -nv would dry-run. Trigger now to verify file ages.
echo "Triggering newsyslog dry-run for validation:"
sudo newsyslog -nvv -F "$DST" 2>&1 | head -20 || true

echo
echo "✓ installed: $DST"
echo "Logs will rotate when they exceed the size in scripts/log-rotate.conf"
echo "(daily check by macOS's newsyslog LaunchDaemon)."
