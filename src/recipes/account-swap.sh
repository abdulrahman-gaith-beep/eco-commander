#!/usr/bin/env bash
# DESC: Rotate auth between multiple Claude/Gemini/Codex accounts without re-OAuth
# INPUTS: subcommand: list | <tool> <slug> | <tool> --register <slug> [--force]
# OUTPUT: ~/.eco/auth-snapshots/<tool>/<slug>/ + ~/.eco/state/active-accounts.json
# USES: filesystem snapshots; macOS `security` CLI for Claude Keychain (gated)
# HUMAN: human picks slug; AI never logs auth contents.
#
# Tools:
#   claude   — auth lives in macOS Keychain (service: "Claude Code-credentials").
#              Updating it may prompt for the user's login password.
#              Gated behind --allow-keychain-prompt for that reason.
#   gemini   — ~/.gemini/oauth_creds.json + ~/.gemini/accounts/.active_slug.
#              Native multi-account scaffolding already present.
#   codex    — ~/.codex/auth.json (single file).
#
# Storage layout under $ECO_HOME (default $HOME/.eco):
#   auth-snapshots/
#     claude/<slug>/keychain.b64        (base64-encoded password blob, mode 0600)
#     gemini/<slug>/oauth_creds.json    (mode 0600)
#     codex/<slug>/auth.json            (mode 0600)
#   state/
#     active-accounts.json              ({"claude":"max","gemini":"primary","codex":"main"})
#
# Refuses to swap if the target tool has an active process running (claude/codex).
# Gemini is treated as swap-safe (stateless per-call).

set -eu
umask 077

ECO_HOME="${ECO_HOME:-$HOME/.eco}"
SNAP_ROOT="$ECO_HOME/auth-snapshots"
STATE_DIR="$ECO_HOME/state"
ACTIVE_JSON="$STATE_DIR/active-accounts.json"

# Live auth locations (override for tests)
CLAUDE_KEYCHAIN_SERVICE="${CLAUDE_KEYCHAIN_SERVICE:-Claude Code-credentials}"
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"
GEMINI_CREDS="$GEMINI_HOME/oauth_creds.json"
GEMINI_ACCOUNTS_DIR="$GEMINI_HOME/accounts"
GEMINI_ACTIVE_SLUG_FILE="$GEMINI_ACCOUNTS_DIR/.active_slug"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_AUTH="$CODEX_HOME/auth.json"

# Test/CI hooks
ECO_ACCOUNT_PGREP="${ECO_ACCOUNT_PGREP:-pgrep}"
ECO_ACCOUNT_SECURITY="${ECO_ACCOUNT_SECURITY:-security}"
ALLOW_KEYCHAIN_PROMPT="${ECO_ALLOW_KEYCHAIN_PROMPT:-0}"

err() { printf 'account-swap: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }
note() { printf '%s\n' "$*"; }

TMP_FILES=()
cleanup_tmp_files() {
  local tmp
  for tmp in "${TMP_FILES[@]:-}"; do
    [ -n "$tmp" ] && rm -f "$tmp"
  done
  return 0
}
trap cleanup_tmp_files EXIT
trap 'cleanup_tmp_files; exit 129' HUP
trap 'cleanup_tmp_files; exit 130' INT
trap 'cleanup_tmp_files; exit 143' TERM

make_private_tmp() {
  local var_name="$1" template="$2" created
  created="$(mktemp "$template")"
  chmod 0600 "$created"
  TMP_FILES+=("$created")
  printf -v "$var_name" '%s' "$created"
}

ensure_private_dir() {
  local dir
  for dir in "$@"; do
    mkdir -p "$dir"
    chmod 0700 "$dir"
  done
}

ensure_dirs() {
  ensure_private_dir "$ECO_HOME" "$SNAP_ROOT" "$SNAP_ROOT/claude" "$SNAP_ROOT/gemini" "$SNAP_ROOT/codex" "$STATE_DIR"
}

# ──────────────────────────────────────────────────────────────────────
# active-accounts.json read/write (python3 fallback if jq missing)
read_active() {
  local tool="$1"
  [ -f "$ACTIVE_JSON" ] || { echo ""; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg t "$tool" '.[$t] // ""' "$ACTIVE_JSON" 2>/dev/null || echo ""
  else
    python3 - "$ACTIVE_JSON" "$tool" <<'PY' 2>/dev/null || echo ""
import json, sys
try:
    with open(sys.argv[1]) as f: d = json.load(f)
    print(d.get(sys.argv[2], ""))
except Exception:
    print("")
PY
  fi
}

write_active() {
  local tool="$1" slug="$2"
  ensure_dirs
  local tmp; make_private_tmp tmp "$STATE_DIR/.active-accounts.XXXXXX"
  if [ -f "$ACTIVE_JSON" ]; then
    python3 - "$ACTIVE_JSON" "$tmp" "$tool" "$slug" <<'PY'
import json, sys
src, dst, tool, slug = sys.argv[1:]
try:
    with open(src) as f: d = json.load(f)
except Exception:
    d = {}
if not isinstance(d, dict): d = {}
d[tool] = slug
with open(dst, "w") as f: json.dump(d, f, indent=2); f.write("\n")
PY
  else
    printf '{\n  "%s": "%s"\n}\n' "$tool" "$slug" > "$tmp"
  fi
  mv -f "$tmp" "$ACTIVE_JSON"
  chmod 0600 "$ACTIVE_JSON"
}

# ──────────────────────────────────────────────────────────────────────
# Process guards
has_active_cli_process() {
  local tool="$1" pattern="$2" line
  # Prefer -fl so we can ignore this recipe and GUI helper processes. Tests
  # use tiny mock pgrep scripts; numeric-only output still counts as active.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *account-swap*|*pgrep*) continue ;;
    esac
    if [ "$tool" = "codex" ]; then
      case "$line" in
        *"Codex.app"*|*"Codex Helper"*|*"Codex Desktop"*) continue ;;
      esac
    fi
    return 0
  done < <("$ECO_ACCOUNT_PGREP" -fl "$pattern" 2>/dev/null || true)
  return 1
}

check_no_active_process() {
  local tool="$1"
  case "$tool" in
    claude)
      if has_active_cli_process claude "claude"; then
        die "refusing to swap: a 'claude' process is running. Quit Claude Code/CLI first."
      fi
      ;;
    codex)
      if has_active_cli_process codex "codex"; then
        die "refusing to swap: a 'codex' process is running. Quit Codex CLI first."
      fi
      ;;
    gemini)
      :  # gemini CLI is stateless per-call — safe
      ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────
# Per-tool: capture / restore. Never logs content.

snapshot_claude() {
  local dest="$1"
  ensure_private_dir "$dest"
  if [ "$ALLOW_KEYCHAIN_PROMPT" != "1" ]; then
    die "Claude auth lives in macOS Keychain. Re-run with --allow-keychain-prompt (or ECO_ALLOW_KEYCHAIN_PROMPT=1). You may be prompted for your login password."
  fi
  local tmp; make_private_tmp tmp "$dest/.keychain.XXXXXX"
  if ! "$ECO_ACCOUNT_SECURITY" find-generic-password \
        -s "$CLAUDE_KEYCHAIN_SERVICE" -a "$(whoami)" -w >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "could not read Claude keychain item '$CLAUDE_KEYCHAIN_SERVICE' for user $(whoami). Is Claude Code signed in?"
  fi
  base64 < "$tmp" > "$dest/keychain.b64"
  rm -f "$tmp"
  chmod 0600 "$dest/keychain.b64"
}

restore_claude() {
  local src="$1"
  [ -f "$src/keychain.b64" ] || die "missing snapshot file: $src/keychain.b64"
  if [ "$ALLOW_KEYCHAIN_PROMPT" != "1" ]; then
    die "Claude swap modifies the macOS Keychain. Re-run with --allow-keychain-prompt (or ECO_ALLOW_KEYCHAIN_PROMPT=1). You may be prompted for your login password."
  fi
  local tmp; make_private_tmp tmp "$src/.keychain.restore.XXXXXX"
  if ! base64 -D < "$src/keychain.b64" > "$tmp" 2>/dev/null; then
    base64 -d < "$src/keychain.b64" > "$tmp"
  fi
  chmod 0600 "$tmp"
  case "$(basename "$ECO_ACCOUNT_SECURITY")" in
    security)
      rm -f "$tmp"
      die "Claude Keychain restore is disabled for safety: macOS security -w exposes the secret in process arguments. Re-authenticate Claude Code manually."
      ;;
    *)
      if [ "${ECO_ACCOUNT_SECURITY_STDIN_PASSWORD:-0}" != "1" ]; then
        rm -f "$tmp"
        die "refusing to send Claude secret to helper stdin without ECO_ACCOUNT_SECURITY_STDIN_PASSWORD=1"
      fi
      if ! "$ECO_ACCOUNT_SECURITY" add-generic-password \
            -U -s "$CLAUDE_KEYCHAIN_SERVICE" -a "$(whoami)" < "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        die "failed to update Claude keychain item. You may need to unlock the login keychain."
      fi
      ;;
  esac
  rm -f "$tmp"
}

refuse_nonempty_snapshot() {
  local dest="$1"
  if find "$dest" -mindepth 1 -maxdepth 1 | grep -q .; then
    die "snapshot directory contains unexpected files; refusing to overwrite: $dest"
  fi
}

snapshot_gemini() {
  local dest="$1"
  ensure_private_dir "$dest"
  [ -f "$GEMINI_CREDS" ] || die "no Gemini auth found at $GEMINI_CREDS"
  cp -p "$GEMINI_CREDS" "$dest/oauth_creds.json"
  chmod 0600 "$dest/oauth_creds.json"
}

restore_gemini() {
  local src="$1" slug="$2"
  [ -f "$src/oauth_creds.json" ] || die "missing snapshot file: $src/oauth_creds.json"
  ensure_private_dir "$GEMINI_HOME" "$GEMINI_ACCOUNTS_DIR"
  local tmp; make_private_tmp tmp "$GEMINI_HOME/.oauth_creds.swap.XXXXXX"
  cp -p "$src/oauth_creds.json" "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$GEMINI_CREDS"
  cp -p "$src/oauth_creds.json" "$GEMINI_ACCOUNTS_DIR/oauth_creds.$slug.json"
  chmod 0600 "$GEMINI_ACCOUNTS_DIR/oauth_creds.$slug.json"
  printf '%s' "$slug" > "$GEMINI_ACTIVE_SLUG_FILE"
  chmod 0600 "$GEMINI_ACTIVE_SLUG_FILE"
}

snapshot_codex() {
  local dest="$1"
  ensure_private_dir "$dest"
  [ -f "$CODEX_AUTH" ] || die "no Codex auth found at $CODEX_AUTH"
  cp -p "$CODEX_AUTH" "$dest/auth.json"
  chmod 0600 "$dest/auth.json"
}

restore_codex() {
  local src="$1"
  [ -f "$src/auth.json" ] || die "missing snapshot file: $src/auth.json"
  ensure_private_dir "$CODEX_HOME"
  local tmp; make_private_tmp tmp "$CODEX_HOME/.auth.swap.XXXXXX"
  cp -p "$src/auth.json" "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$CODEX_AUTH"
}

# ──────────────────────────────────────────────────────────────────────
# Subcommands

cmd_list() {
  ensure_dirs
  local any=0
  for tool in claude gemini codex; do
    local dir="$SNAP_ROOT/$tool"
    local active; active=$(read_active "$tool")
    local slugs=()
    if [ -d "$dir" ]; then
      while IFS= read -r d; do
        [ -z "$d" ] && continue
        slugs+=("$(basename "$d")")
      done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    fi
    if [ "${#slugs[@]}" -gt 0 ]; then
      any=1
      printf '%s:\n' "$tool"
      for s in "${slugs[@]}"; do
        if [ "$s" = "$active" ]; then
          printf '  * %s (active)\n' "$s"
        else
          printf '    %s\n' "$s"
        fi
      done
    fi
  done
  if [ "$any" = 0 ]; then
    echo "No accounts registered. Use --register to capture current auth:"
    echo "  eco account-swap gemini --register primary"
    echo "  eco account-swap codex  --register main"
    echo "  eco account-swap claude --register max --allow-keychain-prompt"
  fi
}

cmd_register() {
  local tool="$1" slug="$2" force="$3"
  ensure_dirs
  local dest="$SNAP_ROOT/$tool/$slug"
  if [ -d "$dest" ] && [ "$force" != "1" ]; then
    die "snapshot for $tool/$slug already exists at $dest. Re-run with --force to overwrite."
  fi
  if [ -d "$dest" ] && [ "$force" = "1" ]; then
    [ ! -L "$dest" ] || die "refusing to overwrite symlinked snapshot: $dest"
    rm -f "$dest/keychain.b64" "$dest/oauth_creds.json" "$dest/auth.json"
    refuse_nonempty_snapshot "$dest"
  fi
  case "$tool" in
    claude) snapshot_claude "$dest" ;;
    gemini) snapshot_gemini "$dest" ;;
    codex)  snapshot_codex  "$dest" ;;
    *) die "unknown tool: $tool" ;;
  esac
  # Register captures the *current* live auth — by definition, this slug is
  # what's live right now, so mark it active. (Without this, an auto-snapshot
  # on the next swap would overwrite the previously-active slug with the new
  # live blob, corrupting the prior snapshot.)
  write_active "$tool" "$slug"
  note "registered $tool account: $slug (now active)"
}

cmd_swap() {
  local tool="$1" slug="$2"
  ensure_dirs
  local target="$SNAP_ROOT/$tool/$slug"
  [ -d "$target" ] || die "no snapshot for $tool/$slug at $target. Register it first: eco account-swap $tool --register $slug"
  check_no_active_process "$tool"
  local prev; prev=$(read_active "$tool")
  if [ -n "$prev" ] && [ "$prev" != "$slug" ]; then
    local prev_dir="$SNAP_ROOT/$tool/$prev"
    ensure_private_dir "$prev_dir"
    case "$tool" in
      claude) snapshot_claude "$prev_dir" ;;
      gemini) snapshot_gemini "$prev_dir" ;;
      codex)  snapshot_codex  "$prev_dir" ;;
    esac
  fi
  case "$tool" in
    claude) restore_claude "$target" ;;
    gemini) restore_gemini "$target" "$slug" ;;
    codex)  restore_codex  "$target" ;;
  esac
  write_active "$tool" "$slug"
  if [ -n "$prev" ] && [ "$prev" != "$slug" ]; then
    note "$tool now using account: $slug (was: $prev)"
  else
    note "$tool now using account: $slug"
  fi
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$tool -> $slug\" with title \"eco account-swap\"" 2>/dev/null &
  fi
}

# ──────────────────────────────────────────────────────────────────────
# CLI

usage() {
  cat <<'EOF'
Usage:
  eco account-swap list
  eco account-swap <tool> <slug>
  eco account-swap <tool> --register <slug> [--force]
  eco account-swap <tool> --register <slug> --allow-keychain-prompt  (claude only)

Tools: claude | gemini | codex

Flags:
  --force                    overwrite an existing snapshot during --register
  --allow-keychain-prompt    permit macOS Keychain read/write prompts (claude)

Safety:
  Claude restore is disabled for the real macOS `security` CLI because `-w`
  exposes the restored secret in process arguments. Re-auth Claude manually.
EOF
}

main() {
  local sub="${1:-}"
  case "$sub" in
    ""|help|-h|--help) usage; exit 0 ;;
    list) cmd_list; exit 0 ;;
    claude|gemini|codex)
      local tool="$sub"; shift
      local slug="" register=0 force=0
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --register)
            register=1; shift
            slug="${1:-}"
            [ -z "$slug" ] && die "--register requires a slug"
            shift
            ;;
          --force) force=1; shift ;;
          --allow-keychain-prompt) ALLOW_KEYCHAIN_PROMPT=1; shift ;;
          -*) die "unknown flag: $1" ;;
          *)
            if [ -z "$slug" ]; then slug="$1"; else die "unexpected arg: $1"; fi
            shift
            ;;
        esac
      done
      [ -z "$slug" ] && die "missing slug. See: eco account-swap help"
      case "$slug" in
        *[!A-Za-z0-9_-]*) die "invalid slug '$slug' (allowed: A-Z a-z 0-9 _ -)" ;;
      esac
      if [ "$register" = 1 ]; then
        cmd_register "$tool" "$slug" "$force"
      else
        cmd_swap "$tool" "$slug"
      fi
      ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
