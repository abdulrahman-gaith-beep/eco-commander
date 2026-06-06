#!/usr/bin/env bash
# Strict devcontainer verifier.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/readiness.sh" --strict
