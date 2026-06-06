# Security Model

> Purpose: expanded threat model for eco-commander. For the short-form policy
> and vulnerability reporting instructions see
> [`../../SECURITY.md`](../../SECURITY.md).

## Trust boundaries

eco-commander operates within a single trust boundary: the invoking user's
macOS session. It has no privilege escalation, no network listeners, and no
multi-user features.

```text
┌──────────────────────────────────────────────────────────────────┐
│  User session (the invoking user)                                │
│                                                                  │
│  eco-commander ──reads──► macOS Keychain                         │
│       │                   (Claude Code-credentials entry)        │
│       │                ──reads──► ~/.gemini/oauth_creds.json     │
│       │                ──reads──► ~/.codex/auth.json             │
│       │                                                          │
│       ├──writes──► ~/.eco/auth-snapshots/  (account-swap only)  │
│       │             └─ claude/<slug>/keychain.b64  (mode 0600)   │
│       │             └─ gemini/<slug>/oauth_creds.json (mode 0600)│
│       │             └─ codex/<slug>/auth.json (mode 0600)        │
│       │                                                          │
│       ├──writes──► ~/.eco/ (state, queue, logs, snapshots)      │
│       │                                                          │
│       └──shells out──► claude, gemini, codex, ollama             │
│                        (same user, same trust)                   │
└──────────────────────────────────────────────────────────────────┘
```

## Credential handling

### Product vs. audit behavior

Production commands may read the local CLI credential stores listed below when
the user intentionally enables those features. Agent audits, tests, and CI must
not probe live Keychain or OAuth stores. Use mocked subprocesses, synthetic
`$ECO_HOME` directories, and redacted excerpts provided by the operator.

### OAuth tokens (read by poller)

The poller reads OAuth tokens from the same stores the CLI tools themselves
maintain. This is the same trust boundary as running `gemini` or `claude`
directly — no new credential exposure is introduced.

| Token source | Read by | Mechanism |
|-------------|---------|-----------|
| macOS Keychain (`Claude Code-credentials`) | `src/poller/claude_oauth.py` | `security find-generic-password -s ... -w` (subprocess, timeout 3 s) |
| `~/.gemini/oauth_creds.json` | `src/poller/gemini.py` | Direct file read; refreshed token written back atomically via `os.replace` |
| `~/.codex/auth.json` | `src/poller/codex_oauth.py` | Direct file read |

**Safeguards in place:**

- Access tokens are read into memory, used for one HTTP request, then released
  — they are not held between poll cycles.
- Tokens are never written to stderr or stdout. Error paths log only error
  classes (e.g., `"http_401"`), never token contents.
- The Gemini poller refreshes expired tokens using the `refresh_token` grant and
  writes the updated credential back to `~/.gemini/oauth_creds.json` atomically
  (tmp file → `os.replace` → `chmod 0600`), matching the same write pattern
  the Gemini CLI itself uses.
- `claude_oauth.py` imposes a 3-second subprocess timeout on the `security`
  command and an 8-second HTTP timeout.

### Account rotation (account-swap recipe)

`src/recipes/account-swap.sh` lets the user snapshot and restore CLI auth
when switching between registered accounts (e.g., personal vs. work Claude).

**What it does per tool:**

| Tool | Snapshot storage | Restore mechanism |
|------|-----------------|-------------------|
| `gemini` | Copies `~/.gemini/oauth_creds.json` → `~/.eco/auth-snapshots/gemini/<slug>/oauth_creds.json` (mode 0600) | Copies back; also maintains `~/.gemini/accounts/oauth_creds.<slug>.json` |
| `codex` | Copies `~/.codex/auth.json` → `~/.eco/auth-snapshots/codex/<slug>/auth.json` (mode 0600) | Atomic copy via tmpfile + `mv` |
| `claude` | Reads Keychain blob via `security find-generic-password -w`; stores base64-encoded result to `~/.eco/auth-snapshots/claude/<slug>/keychain.b64` (mode 0600) | Restore via `security -w` is **disabled** (see Known limitations) |

**Safeguards in place:**

- All snapshot directories are created with `chmod 0700`; all snapshot files
  with `chmod 0600`.
- The script sets `umask 077` at startup so any intermediate temp files are
  owner-only by default.
- Swap is refused if the target tool has an active CLI process running.
- Snapshots use atomic tmp-file-then-`mv` writes to prevent partial overwrites.

### Known limitations

The following residual risks are present in the current implementation. They
are documented here accurately rather than understated.

**1. Claude credential blob stored on disk (base64, not encrypted)**

`snapshot_claude` base64-encodes the raw Keychain password blob and writes it
to `~/.eco/auth-snapshots/claude/<slug>/keychain.b64`. Base64 is encoding, not
encryption — any process running as the same user can trivially decode it.
Mode 0600 limits access to the user's own session but provides no protection if
the session is already compromised. **Risk:** a malicious process or recipe
running as the same user can read and decode this file without any Keychain
prompt. **Mitigation path:** encrypt with `openssl enc -aes-256-gcm` using a
key derived from a Keychain secret, or store the blob back in a new Keychain
item under a separate service label.

**2. Gemini and Codex OAuth files are plaintext JSON on disk**

`~/.eco/auth-snapshots/gemini/<slug>/oauth_creds.json` and
`~/.eco/auth-snapshots/codex/<slug>/auth.json` contain plaintext OAuth tokens.
Mode 0600 applies, but the same session-compromise caveat above applies.

**3. No active secret-scanning rules in `.gitleaks.toml`**

The repository includes a `.gitleaks.toml` with a title and an `[allowlist]`
section, but no `[[rules]]` blocks. This means gitleaks (if run) will not
detect accidentally committed tokens, API keys, or OAuth credentials.
**Risk:** a contributor who accidentally commits a credential will not be caught
by the scanner. **Mitigation path:** add upstream built-in rules by extending
`.gitleaks.toml` with `[extends] useDefault = true`.

---

## Data sensitivity

### Auth snapshots (`~/.eco/auth-snapshots/`)

Contains per-tool, per-slug credential snapshots (see above). Mode 0600 on
files, 0700 on directories. Treat as highly sensitive — equivalent to the live
credential stores they copy from.

### Snapshots (`~/.eco/snapshots/`)

May contain:
- Names and counts of installed MCP servers
- Active MCP profile name
- Git repository paths, branch names, and dirty state
- Installed Ollama model names
- Docker container names

**Classification:** Confidential. Reveal the user's tooling configuration and
active projects. Do not share publicly.

### Job queue (`~/.eco/queue/jobs.yaml`)

Contains prompts, file paths, and project context. Written with mode `0600`
(owner-only read/write).

### Logs (`~/.eco/logs/`)

LaunchAgent logs may contain error messages from API calls. No secrets, but
may reveal project names, model usage patterns, and timing. Agent workflows
must not copy raw logs into prompts — use sanitized summaries, fixture logs, or
manually redacted excerpts.

---

## Attack surface

| Vector | Risk | Mitigation |
|--------|------|------------|
| Malicious recipe | A recipe runs with the user's full privileges | Recipes live in a git-tracked repo; changes require `git commit`. No dynamic loading from untrusted sources. |
| Prompt injection via job queue | A crafted job prompt could cause the adapter to execute unintended commands | Adapters pass prompts as CLI arguments (not to `eval`); all arguments are quoted. |
| Symlink attacks on `~/.eco/` | A malicious symlink could redirect writes | `~/.eco/` is created by the installer with mode 0700. Queue writes use `tempfile + os.replace` in the same directory. |
| LaunchAgent persistence | An attacker with user access could modify the plist to run arbitrary commands | Plists are generated from repo templates. `scripts/healthcheck.sh` validates plist integrity via `plutil -lint`. |
| Stale OAuth tokens | A leaked OAuth file grants API access | eco-commander does not create new tokens — it reads and refreshes existing ones. If a token is compromised, revoke it at the provider (Google, Anthropic, OpenAI). |
| Claude base64 snapshot decoded | `keychain.b64` is reversible by any same-user process | Mode 0600 limits access; see Known limitations §1 for the encryption path. |
| Log exfiltration | Logs reveal usage patterns | Logs are owner-only (mode 0600). Log rotation limits accumulation. |

---

## Permissions

eco-commander requires:

- **Read** access to macOS Keychain (via `security` subprocess) — for Claude
  OAuth token
- **Read** access to `~/.gemini/` — for Gemini OAuth credentials
- **Read** access to `~/.codex/` — for Codex session data
- **Read/Write** access to `~/.eco/` — for all runtime state, snapshots, and
  auth snapshots
- **Execute** access to `claude`, `gemini`, `codex`, `ollama` CLIs
- **Write** access to `~/Library/LaunchAgents/` — for plist installation
- **Optional sudo** — only for `scripts/install-log-rotation.sh` (writes to
  `/etc/newsyslog.d/`)

No other permissions are needed. eco-commander does not request Full Disk
Access, Accessibility, or any macOS Privacy permission.

---

## Related

- [`../../SECURITY.md`](../../SECURITY.md) — short-form policy and vulnerability reporting
- [`./runbook.md`](./runbook.md) — operational procedures including account-swap usage
- [`../architecture.md`](../architecture.md) — system architecture and security considerations
