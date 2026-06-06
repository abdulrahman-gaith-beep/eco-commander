#!/usr/bin/env bash
# Install (or refresh) the eco-commander LaunchAgents.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"
LA_SRC="$REPO_ROOT/scripts/launchagents"
LA_DST="${ECO_LAUNCHAGENTS_DIR:-${LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}}"
SRC_DIR="$REPO_ROOT/src"
POLLER_PATH="$SRC_DIR/poller/main.py"

die() { printf "install-launchagents: %s\n" "$*" >&2; exit 1; }

# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
  die "do not run with sudo/root; install LaunchAgents as the target macOS user"
fi

validate_install_path ECO_HOME "$ECO_HOME"
validate_install_path ECO_LAUNCHAGENTS_DIR "$LA_DST"

ensure_owned_dir "$ECO_HOME" 0700
ensure_owned_dir "$ECO_HOME/logs" 0700
ensure_owned_dir "$LA_DST"

select_python_runner() {
  local candidate
  for candidate in "${PYTHON:-}" "${PYTHON_BIN:-}" "$REPO_ROOT/.venv/bin/python" python3.13 python3.12 python3.11 python3.10 python3; do
    [ -n "$candidate" ] || continue
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" - <<'PY' >/dev/null 2>&1; then
import sys
raise SystemExit(0 if (3, 10) <= sys.version_info[:2] < (3, 14) else 1)
PY
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

PYTHON_RUNNER="$(select_python_runner)" || die "no supported Python found (requires 3.10-3.13)"

validate_plist() {
  local plist="$1"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$plist" >/dev/null
  else
    "$PYTHON_RUNNER" - "$plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    plistlib.load(f)
PY
  fi
}

render_plist() {
  local src="$1" dst="$2" label="$3"
  [ -f "$src" ] || die "missing plist template: $src"
  [ ! -L "$dst" ] || die "refusing to overwrite symlinked plist: $dst"
  [ ! -d "$dst" ] || die "refusing to overwrite directory: $dst"
  if [ -f "$dst" ] && ! plist_label_matches "$dst" "$label"; then
    die "refusing to overwrite plist with unexpected label: $dst"
  fi

  local tmp
  tmp="$(mktemp "$LA_DST/.${label}.XXXXXX")"
  "$PYTHON_RUNNER" - "$src" "$tmp" "$POLLER_PATH" "$SRC_DIR" "$ECO_HOME" "$PYTHON_RUNNER" <<'PY'
from html import escape
from pathlib import Path
import sys

src, dst, poller, src_dir, eco_home, python_runner = sys.argv[1:]
text = Path(src).read_text(encoding="utf-8")
for key, value in {
    "__POLLER_PATH__": poller,
    "__SRC_DIR__": src_dir,
    "__ECO_HOME__": eco_home,
    "__PYTHON_BIN__": python_runner,
}.items():
    text = text.replace(key, escape(value, quote=True))
Path(dst).write_text(text, encoding="utf-8")
PY
  chmod 0644 "$tmp"
  validate_plist "$tmp"
  plist_label_matches "$tmp" "$label" || die "rendered plist has unexpected label: $tmp"
  mv "$tmp" "$dst"
}

reload_agent() {
  local label="$1"
  local plist="$2"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  launchctl enable "gui/$(id -u)/$label"
}

POLLER_LABEL="com.eco-commander.usage-poller"
POLLER_PLIST="$LA_DST/$POLLER_LABEL.plist"
render_plist "$LA_SRC/$POLLER_LABEL.plist" "$POLLER_PLIST" "$POLLER_LABEL"
reload_agent "$POLLER_LABEL" "$POLLER_PLIST"
echo "installed $POLLER_LABEL -> $POLLER_PLIST"

SCHED_LABEL="com.eco-commander.scheduler"
SCHED_PLIST_SRC="$LA_SRC/$SCHED_LABEL.plist"
if [ -f "$SCHED_PLIST_SRC" ]; then
  SCHED_PLIST="$LA_DST/$SCHED_LABEL.plist"
  if [ "${ECO_SCHEDULER_AUTO_LOAD:-0}" = "1" ]; then
    render_plist "$SCHED_PLIST_SRC" "$SCHED_PLIST" "$SCHED_LABEL"
    reload_agent "$SCHED_LABEL" "$SCHED_PLIST"
    echo "installed + loaded $SCHED_LABEL -> $SCHED_PLIST"
  elif [ "${ECO_SCHEDULER_PERSIST:-0}" = "1" ]; then
    render_plist "$SCHED_PLIST_SRC" "$SCHED_PLIST" "$SCHED_LABEL"
    echo "installed but did not load $SCHED_LABEL -> $SCHED_PLIST"
  else
    echo "skipped scheduler LaunchAgent; set ECO_SCHEDULER_PERSIST=1 or ECO_SCHEDULER_AUTO_LOAD=1"
  fi
fi

if [ -d "/Applications/SwiftBar.app" ]; then
  SB_LABEL="com.eco-commander.swiftbar"
  SB_PLIST="$LA_DST/$SB_LABEL.plist"
  render_plist "$LA_SRC/$SB_LABEL.plist" "$SB_PLIST" "$SB_LABEL"
  reload_agent "$SB_LABEL" "$SB_PLIST"
  echo "installed $SB_LABEL -> $SB_PLIST"
else
  echo "SwiftBar.app not found in /Applications; skipping SwiftBar autostart"
  echo "install: brew install --cask swiftbar"
fi

echo
echo "-- launchctl status --"
launchctl list | grep -E "com\.eco-commander\." || echo "(none loaded yet)"
