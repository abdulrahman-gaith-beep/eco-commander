#!/usr/bin/env bash
# scripts/bootstrap.sh — One-command development environment setup.
#
# Usage:
#   bash scripts/bootstrap.sh
#
# This script:
#   1. Installs Homebrew dependencies (Brewfile)
#   2. Sets up the Python virtual environment
#   3. Installs pre-commit and commit-msg hooks
#   4. Symlinks src/ into ~/.eco/ (make install)
#   5. Runs a quick smoke test
#
# Idempotent: safe to re-run at any time.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

# ── 1. Homebrew dependencies ───────────────────────────────────────────────
step "Installing Homebrew dependencies"
if command -v brew &>/dev/null; then
  brew bundle --file=Brewfile --no-upgrade --quiet
  ok "Brewfile installed"
else
  warn "Homebrew not found — skipping Brewfile. Install manually: https://brew.sh"
fi

# ── 2. Python virtual environment ─────────────────────────────────────────
step "Setting up Python virtual environment"
bash scripts/setup-venv.sh
ok "Virtual environment ready at .venv/"

# ── 3. Pre-commit hooks ──────────────────────────────────────────────────
step "Installing Git hooks"
bash scripts/install-hooks.sh
ok "Pre-commit and commit-msg hooks installed"

# ── 4. Symlink installation ───────────────────────────────────────────────
step "Installing eco-commander (symlinks to ~/.eco/)"
bash scripts/install.sh
ok "Installed — eco CLI available at ~/.eco/bin/eco"

# ── 5. Smoke test ─────────────────────────────────────────────────────────
step "Running smoke test"
if [[ -L "$HOME/.eco/bin/eco" ]]; then
  ok "$HOME/.eco/bin/eco symlink exists"
else
  warn "$HOME/.eco/bin/eco symlink not found — install may have used a custom ECO_HOME"
fi

if command -v shellcheck &>/dev/null; then
  ok "shellcheck $(shellcheck --version 2>/dev/null | head -2 | tail -1)"
else
  warn "shellcheck not found"
fi

if [[ -f .venv/bin/python ]]; then
  py_version=$(.venv/bin/python --version 2>&1)
  ok "$py_version"
else
  warn "Python venv not found"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  eco-commander development environment ready!  ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo "    make test       # run all tests"
echo "    make lint       # shellcheck + ruff"
echo "    make hygiene    # full pre-commit + workflow lint"
echo "    eco status      # check ecosystem status"
echo ""
