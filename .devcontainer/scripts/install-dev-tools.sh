#!/usr/bin/env bash
# Install Go-distributed tools that are present in CI via Homebrew.
set -euo pipefail

ACTIONLINT_VERSION="${ACTIONLINT_VERSION:-v1.7.7}"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-v8.28.0}"
GOBIN="${GOBIN:-$HOME/go/bin}"

mkdir -p "$GOBIN"
export PATH="$GOBIN:$PATH"

log() { printf "[devcontainer:tools] %s\n" "$*"; }
warn() { printf "[devcontainer:tools] warning: %s\n" "$*" >&2; }

install_go_tool() {
  local binary="$1"
  local module="$2"
  local version="$3"

  if command -v "$binary" >/dev/null 2>&1; then
    log "$binary already available: $(command -v "$binary")"
    return 0
  fi

  if ! command -v go >/dev/null 2>&1; then
    warn "go is not available; cannot install $binary"
    return 0
  fi

  log "installing $binary from $module@$version"
  if GOBIN="$GOBIN" go install "$module@$version"; then
    log "$binary installed to $GOBIN"
  else
    warn "failed to install $binary; rerun this script after network access is available"
  fi
}

install_go_tool actionlint github.com/rhysd/actionlint/cmd/actionlint "$ACTIONLINT_VERSION"
install_go_tool gitleaks github.com/gitleaks/gitleaks/v8 "$GITLEAKS_VERSION"
