#!/usr/bin/env bash
# Validate the first line of a commit message against Conventional Commits.
set -euo pipefail

message_file=${1:?usage: validate-commit-message.sh COMMIT_MSG_FILE}
subject=$(sed -n '1p' "$message_file")
pattern='^(feat|fix|docs|test|ci|build|chore|refactor|perf|security|style|revert|audit)(\([a-z0-9._-]+\))?(!)?: .+'

if [[ "$subject" =~ $pattern ]]; then
  exit 0
fi

cat >&2 <<'EOF'
Commit subject must follow Conventional Commits:

  feat(scope): add useful thing
  fix: correct broken behavior
  docs(readme): update setup notes

Allowed types: feat, fix, docs, test, ci, build, chore, refactor, perf, security, style, revert, audit.
EOF
exit 1
