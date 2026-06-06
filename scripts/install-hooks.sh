#!/usr/bin/env bash
# Install local Git hooks managed by pre-commit.
set -euo pipefail

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "pre-commit not installed. Run: python3 -m pip install -r requirements-dev.txt" >&2
  exit 127
fi

pre-commit install --install-hooks
pre-commit install --hook-type commit-msg
echo "installed pre-commit and commit-msg hooks"
