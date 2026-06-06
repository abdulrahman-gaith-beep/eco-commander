#!/usr/bin/env bash
# Tag and push a release. Usage: scripts/release.sh 0.3.0
set -euo pipefail

V=${1:?usage: release.sh X.Y.Z}
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version: $V" >&2; exit 2; }

branch=$(git branch --show-current)
[[ "$branch" == "main" ]] || { echo "release must run from main, current branch: $branch" >&2; exit 1; }

git remote get-url origin >/dev/null 2>&1 || { echo "missing origin remote" >&2; exit 1; }

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "working tree not clean" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/v$V" >/dev/null; then
  echo "tag already exists: v$V" >&2
  exit 1
fi

grep -q "## \[$V\]" CHANGELOG.md || { echo "CHANGELOG.md missing entry for $V" >&2; exit 1; }
grep -qx "$V" VERSION || { echo "VERSION missing $V" >&2; exit 1; }
grep -qx "__version__ = \"$V\"" src/scheduler/__init__.py || {
  echo "src/scheduler/__init__.py missing __version__ = \"$V\"" >&2
  exit 1
}

make lint
make test

git tag -a "v$V" -m "eco-commander v$V"
git push origin "v$V"
echo "pushed v$V"
