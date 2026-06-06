#!/usr/bin/env bash
# Link the repo command surface into a container-local ECO_HOME.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ECO_HOME="${ECO_HOME:-$HOME/.eco}"

log() { printf "[devcontainer:eco-home] %s\n" "$*"; }

mkdir -p \
  "$ECO_HOME/bin" \
  "$ECO_HOME/recipes" \
  "$ECO_HOME/current" \
  "$ECO_HOME/state" \
  "$ECO_HOME/queue" \
  "$ECO_HOME/logs" \
  "$ECO_HOME/snapshots" \
  "$ECO_HOME/alert-runs"

for src in "$REPO_ROOT"/src/bin/*; do
  [ -f "$src" ] || continue
  [ -x "$src" ] || continue
  ln -sfn "$src" "$ECO_HOME/bin/$(basename "$src")"
done

for src in "$REPO_ROOT"/src/recipes/*.sh; do
  [ -f "$src" ] || continue
  ln -sfn "$src" "$ECO_HOME/recipes/$(basename "$src")"
done

log "linked executable bins and recipes into $ECO_HOME"
