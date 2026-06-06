#!/usr/bin/env bash
# Remove the eco-commander newsyslog drop-in. Preserves logs.
set -euo pipefail

DST="/etc/newsyslog.d/eco-commander.conf"
MARKER="newsyslog(5) config for eco-commander logs."

log() { printf "uninstall-log-rotation: %s\n" "$*"; }
die() { printf "uninstall-log-rotation: %s\n" "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
  die "do not run with sudo/root; uninstall log rotation as the target macOS user"
fi

if [ ! -e "$DST" ] && [ ! -L "$DST" ]; then
  log "not installed: $DST"
  exit 0
fi

if [ -L "$DST" ]; then
  log "skipping symlinked config: $DST"
  exit 0
fi

[ -f "$DST" ] || die "refusing to remove non-file config path: $DST"

if grep -Fq "$MARKER" "$DST"; then
  echo "Removing newsyslog rule (requires sudo): $DST"
  sudo rm -f "$DST"
  log "removed $DST"
else
  log "skipping config without eco-commander marker: $DST"
fi
