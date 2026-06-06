#!/usr/bin/env bash
# scripts/lib/common.sh — Shared functions for eco-commander scripts.
#
# @category  library
# @depends   python3
# @sourced-by install.sh, uninstall.sh, install-launchagents.sh, uninstall-launchagents.sh,
#             install-commander.sh
#
# Usage:
#   REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
#   source "$REPO_ROOT/scripts/lib/common.sh"
#
# Source guard — prevents double-sourcing.
# shellcheck disable=SC2154
[ "${_ECO_LIB_COMMON_LOADED:-}" = "1" ] && return 0
_ECO_LIB_COMMON_LOADED=1

# ── validate_install_path ────────────────────────────────────────────
# Refuse to write into sensitive macOS paths, symlinked targets, root,
# other users' home directories, iCloud-managed directories, or unsafe
# installer destinations.
#
# Usage: validate_install_path LABEL "/path/to/check"
# Exits non-zero (via die) if the path is unsafe.
validate_install_path() {
  local label="$1" path="$2"
  [ -n "$path" ] || die "$label is empty"

  local expanded_path validation_status
  if expanded_path="$(python3 - "$path" <<'PY'
from pathlib import Path
import sys

raw = sys.argv[1]
expanded = Path(raw).expanduser()

if not expanded.is_absolute():
    sys.exit(2)
if ".." in expanded.parts:
    sys.exit(3)

canonical = expanded.resolve(strict=False)
home = Path.home().resolve(strict=False)
users_root = Path("/Users").resolve(strict=False)
cloud_storage = (home / "Library" / "CloudStorage").resolve(strict=False)
sensitive_dirs = [
    home / "Library" / "Mobile Documents",
    home / "Library" / "Keychains",
    home / "Library" / "Mail",
    home / "Library" / "Messages",
    home / "Library" / "Safari",
    home / "Library" / "Contacts",
    home / "Library" / "Calendars",
    home / "Library" / "Photos",
    home / "Library" / "Notes",
    home / "Library" / "HomeKit",
    home / "Library" / "Cookies",
    home / ".ssh",
]
sensitive_dirs = [p.resolve(strict=False) for p in sensitive_dirs]

def contains(path, base):
    return path == base or base in path.parents

if canonical == Path("/"):
    sys.exit(4)
if canonical == home:
    sys.exit(5)
if any(contains(canonical, sensitive) for sensitive in sensitive_dirs):
    sys.exit(6)
for candidate in (canonical, *canonical.parents):
    if candidate.parent == cloud_storage and candidate.name.startswith("iCloud"):
        sys.exit(6)
if contains(canonical, users_root) and not contains(canonical, home):
    sys.exit(7)

print(str(expanded))
PY
  )"; then
    validation_status=0
  else
    validation_status=$?
  fi
  case "$validation_status" in
    0) path="$expanded_path" ;;
    2) die "$label must be an absolute path after ~ expansion: $path" ;;
    3) die "$label must not contain .. components: $path" ;;
    4) die "$label must not be /" ;;
    5) die "$label must not be your home directory: $path" ;;
    6) die "refusing sensitive install path for $label: $path" ;;
    7) die "refusing install path outside your home directory for $label: $path" ;;
    *) die "failed to validate install path for $label: $path" ;;
  esac

  [ ! -L "$path" ] || die "refusing symlinked install path for $label: $path"
  python3 - "$path" <<'PY' || die "refusing path with symlinked ancestor for $label: $path"
from pathlib import Path
import sys

p = Path(sys.argv[1]).expanduser()
allowed_system_symlink_anchors = {
    Path("/tmp"),
    Path("/var"),
    Path("/etc"),
    Path("/private/tmp"),
    Path("/private/var"),
    Path("/private/etc"),
}
for parent in reversed((p, *p.parents)):
    if parent in allowed_system_symlink_anchors:
        continue
    if parent.exists() and parent.is_symlink():
        sys.exit(1)
sys.exit(0)
PY

  case "$label" in
    ECO_HOME|SWIFTBAR_PLUGIN_DIR|ECO_LAUNCHAGENTS_DIR|LAUNCHAGENTS_DIR)
      local system_path_status=0
      python3 - "$path" <<'PY' || system_path_status=$?
from pathlib import Path
import sys

p = Path(sys.argv[1]).expanduser()
canonical = p.resolve(strict=False)
home = Path.home().resolve(strict=False)
default_eco = (home / ".eco").resolve(strict=False)

def contains(path, base):
    return path == base or base in path.parents

if canonical == default_eco:
    sys.exit(0)

system_or_package_roots = [
    Path("/Applications"),
    Path("/Library"),
    Path("/System"),
    Path("/bin"),
    Path("/sbin"),
    Path("/usr"),
    Path("/opt"),
    Path("/etc"),
    Path("/var"),
    Path("/private/etc"),
    Path("/private/var"),
    Path("/private/opt"),
]
system_or_package_roots = [root.resolve(strict=False) for root in system_or_package_roots]
if any(contains(canonical, root) for root in system_or_package_roots) and not contains(canonical, home):
    sys.exit(8)
sys.exit(0)
PY
      case "$system_path_status" in
        0) ;;
        8) die "refusing system/package-manager $label path: $path" ;;
        *) die "failed to validate system/package-manager destination for $label: $path" ;;
      esac
      ;;
  esac

  if [ "$label" = "ECO_HOME" ]; then
    local eco_home_status=0
    python3 - "$path" <<'PY' || eco_home_status=$?
from pathlib import Path
import sys

p = Path(sys.argv[1]).expanduser()
canonical = p.resolve(strict=False)
home = Path.home().resolve(strict=False)
default_eco = (home / ".eco").resolve(strict=False)

def contains(path, base):
    return path == base or base in path.parents

if canonical == default_eco:
    sys.exit(0)

system_or_package_roots = [
    Path("/Applications"),
    Path("/Library"),
    Path("/System"),
    Path("/bin"),
    Path("/sbin"),
    Path("/usr"),
    Path("/opt"),
    Path("/etc"),
    Path("/var"),
    Path("/private/etc"),
    Path("/private/var"),
    Path("/private/opt"),
]
system_or_package_roots = [root.resolve(strict=False) for root in system_or_package_roots]
if any(contains(canonical, root) for root in system_or_package_roots) and not contains(canonical, home):
    sys.exit(8)

if not p.exists():
    sys.exit(0)
if not p.is_dir():
    sys.exit(9)

try:
    next(p.iterdir())
except StopIteration:
    sys.exit(0)
except OSError:
    sys.exit(11)

markers = [
    p / ".eco-commander",
    p / ".eco-commander-marker",
    p / "eco-commander.marker",
    p / "bin" / "eco-commander.15s.sh",
    p / "bin" / "eco-alerts.sh",
    p / "recipes" / "snapshot.sh",
    p / "current" / "state.json",
    p / "current" / "dashboard.html",
    p / "ecosystem-audit" / "prompts",
]
if any(marker.exists() or marker.is_symlink() for marker in markers):
    sys.exit(0)

sys.exit(10)
PY
    case "$eco_home_status" in
      0) ;;
      8) die "refusing system/package-manager ECO_HOME path: $path" ;;
      9) die "ECO_HOME must be a directory or a new path: $path" ;;
      10) die "refusing existing unmarked ECO_HOME directory: $path" ;;
      11) die "failed to inspect ECO_HOME directory: $path" ;;
      *) die "failed to validate ECO_HOME destination: $path" ;;
    esac
  fi
}

# ── plist_label_matches ──────────────────────────────────────────────
# Check whether a plist file's Label key matches an expected value.
#
# Usage: plist_label_matches "/path/to/file.plist" "com.example.label"
# Returns 0 if match, 1 otherwise.
plist_label_matches() {
  local plist="$1" expected="$2"
  python3 - "$plist" "$expected" <<'PY'
import plistlib
import sys

path, expected = sys.argv[1:]
try:
    with open(path, "rb") as f:
        data = plistlib.load(f)
except Exception:
    sys.exit(1)
sys.exit(0 if data.get("Label") == expected else 1)
PY
}

# ── die ──────────────────────────────────────────────────────────────
# Print an error message and exit. Callers may override this before
# Create or validate an install-owned directory WITHOUT following a planted symlink.
# Refuses if the path exists as a symlink or as a non-directory (closes a symlink-
# TOCTOU hole where an attacker pre-plants ~/.eco/bin as a symlink). Optional 2nd
# arg sets the mode (only chmod'd when provided, so shared dirs like
# ~/Library/LaunchAgents are not forced to 0700).
ensure_owned_dir() {
  local dir="$1" mode="${2:-}"
  if [ -L "$dir" ]; then
    die "refusing to use symlinked install directory: $dir"
  fi
  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    die "refusing to use non-directory install path: $dir"
  fi
  mkdir -p "$dir"
  [ -n "$mode" ] && chmod "$mode" "$dir" 2>/dev/null || true
}

# sourcing if they need a custom prefix (the first definition wins
# because of the source guard).
if ! declare -F die >/dev/null 2>&1; then
  die() { printf "eco-commander: %s\n" "$*" >&2; exit 1; }
fi
