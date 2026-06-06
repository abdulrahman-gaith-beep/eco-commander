#!/usr/bin/env bash
# Install eco-commander from this repo into ~/.eco/ via symlinks.
set -euo pipefail
umask 077

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"
SWIFTBAR_PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/Library/Application Support/SwiftBar/Plugins}"

log() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "[install/dry-run] %s\n" "$*"
  else
    printf "[install] %s\n" "$*"
  fi
}
die() { printf "[install] error: %s\n" "$*" >&2; exit 1; }

# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

if [ "$(id -u)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
  die "do not run installer with sudo/root; install as the target macOS user"
fi

validate_install_path ECO_HOME "$ECO_HOME"
validate_install_path SWIFTBAR_PLUGIN_DIR "$SWIFTBAR_PLUGIN_DIR"

remove_link_if_ours() {
  local link="$1"; shift
  [ -e "$link" ] || [ -L "$link" ] || return 0
  if [ ! -L "$link" ]; then
    log "preserving non-symlink path: $link"
    return 0
  fi

  local target prefix
  target="$(readlink "$link")"
  for prefix in "$@"; do
    if [[ "$target" == "$prefix"* ]]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        log "would remove old link: $link"
      else
        rm -f "$link"
        log "removed old link: $link"
      fi
      return 0
    fi
  done
  log "preserving foreign symlink: $link -> $target"
}

replace_symlink_if_safe() {
  local src="$1" dst="$2"; shift 2
  [ -e "$src" ] || die "source missing: $src"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    [ -L "$dst" ] || die "refusing to overwrite non-symlink path: $dst"
    local target prefix owned=0
    target="$(readlink "$dst")"
    for prefix in "$@"; do
      [[ "$target" == "$prefix"* ]] && owned=1
    done
    [ "$owned" -eq 1 ] || die "refusing to overwrite foreign symlink: $dst -> $target"
    if [ "$DRY_RUN" -eq 0 ]; then
      rm -f "$dst"
    fi
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "would link: $src -> $dst"
  else
    ln -s "$src" "$dst"
  fi
}

if [ "$DRY_RUN" -eq 1 ]; then
  log "would create: $ECO_HOME/bin $ECO_HOME/recipes (mode 0700)"
else
  ensure_owned_dir "$ECO_HOME" 0700
  ensure_owned_dir "$ECO_HOME/bin" 0700
  ensure_owned_dir "$ECO_HOME/recipes" 0700
fi

for old_bin in eco-commander.30s.sh usage-monitor.15s.sh; do
  remove_link_if_ours "$ECO_HOME/bin/$old_bin" "$REPO_ROOT/src/bin/"
done

log "linking src/bin/* into $ECO_HOME/bin/"
for src in "$REPO_ROOT"/src/bin/*; do
  name="$(basename "$src")"
  replace_symlink_if_safe "$src" "$ECO_HOME/bin/$name" "$REPO_ROOT/src/bin/"
done

log "linking src/recipes/* into $ECO_HOME/recipes/"
for src in "$REPO_ROOT"/src/recipes/*.sh; do
  [ -e "$src" ] || continue
  name="$(basename "$src")"
  replace_symlink_if_safe "$src" "$ECO_HOME/recipes/$name" "$REPO_ROOT/src/recipes/"
done

if [ -d "$(dirname "$SWIFTBAR_PLUGIN_DIR")" ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$SWIFTBAR_PLUGIN_DIR"
  fi

  # Remove old split-widget symlinks only when they are links we own.
  for old_plugin in eco-commander.30s.sh usage-monitor.15s.sh; do
    remove_link_if_ours "$SWIFTBAR_PLUGIN_DIR/$old_plugin" "$REPO_ROOT/src/bin/" "$ECO_HOME/bin/"
  done

  plugin="eco-commander.15s.sh"
  target="$SWIFTBAR_PLUGIN_DIR/$plugin"
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    die "refusing to remove directory at SwiftBar plugin target: $target"
  fi
  replace_symlink_if_safe "$REPO_ROOT/src/bin/$plugin" "$target" "$REPO_ROOT/src/bin/" "$ECO_HOME/bin/"
  log "SwiftBar plugin -> $target"
else
  log "SwiftBar dir not found, skipping widget registration"
fi

if [ "${ECO_INSTALL_LAUNCHAGENTS:-0}" = "1" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "would register LaunchAgents (usage poller + SwiftBar autostart)"
  else
    log "registering LaunchAgents (usage poller + SwiftBar autostart)"
    bash "$REPO_ROOT/scripts/install-launchagents.sh"
  fi
else
  log "skipping LaunchAgents; set ECO_INSTALL_LAUNCHAGENTS=1 to install persistence"
fi

log "done. Try: $ECO_HOME/bin/eco status"
