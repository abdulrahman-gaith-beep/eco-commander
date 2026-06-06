# scripts/lib/ — Shared Bash Libraries

Reusable functions sourced by multiple scripts in the `scripts/` directory.
All libraries use **source guards** to prevent double-inclusion.

## Files

### `common.sh`

Shared security and validation functions for install/uninstall scripts.

| Function | Purpose |
|----------|---------|
| `validate_install_path` | Refuse sensitive macOS paths (iCloud, Keychains), other users' home directories, symlinked targets, and root `/` |
| `plist_label_matches` | Check a plist file's `Label` key against an expected value |
| `die` | Fallback error handler (callers may define their own `die()` before sourcing) |

**Sourced by:** `install.sh`, `uninstall.sh`, `install-launchagents.sh`, `uninstall-launchagents.sh`

**Usage:**
```bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
die() { printf "[my-script] error: %s\n" "$*" >&2; exit 1; }
# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
```

### `snapshot-helpers.sh`

Pure formatting functions with zero side effects. Originally inlined in
`usage-snapshot.sh` (and partially duplicated in the SwiftBar widget).

| Function | Signature | Purpose |
|----------|-----------|---------|
| `humanize` | `humanize <number>` | Format large numbers (1500 → "1.50K") |
| `bar_fill` | `bar_fill <pct>` | Render 20-char Unicode progress bar |
| `safe_pct` | `safe_pct <number>` | Clamp to [0,100], format as %.1f |
| `color_for` | `color_for <pct>` | Return hex color (green/amber/red) |
| `html_escape` | `echo "text" \| html_escape` | Escape HTML entities via stdin→stdout |
| `pace_glyph` | `pace_glyph <label>` | Return pace emoji (🐎 ahead / 🐢 behind) |
| `target_mark` | `target_mark <pct>` | Return HTML div for target-line overlay |
| `acct_label` | `acct_label <n> <plan>` | Format "Plan × N" if N > 1 |
| `_join` | `_join arg1 arg2 ...` | Join arguments with " · " separator |

**Sourced by:** `usage-snapshot.sh`

## Conventions

1. **Source guard** — Every library starts with:
   ```bash
   [ "${_ECO_LIB_<NAME>_LOADED:-}" = "1" ] && return 0
   _ECO_LIB_<NAME>_LOADED=1
   ```

2. **`die()` precedence** — Callers should define their own `die()` **before** sourcing
   `common.sh`. The library only defines a fallback if no `die()` exists.

3. **shellcheck directive** — Always annotate the source line:
   ```bash
   # shellcheck source=lib/common.sh
   source "$REPO_ROOT/scripts/lib/common.sh"
   ```
