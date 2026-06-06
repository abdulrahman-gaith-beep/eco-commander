# Account Swap Flow

Credential rotation lifecycle for `eco account-swap` (`src/recipes/account-swap.sh`).

## Command Dispatch

```mermaid
flowchart TB
    Entry["eco account-swap &lt;args&gt;"] --> Parse{"Subcommand?"}

    Parse -->|list| List["Enumerate registered slugs\nper tool (claude/gemini/codex)\nMark active with *"]

    Parse -->|"&lt;tool&gt; --register &lt;slug&gt;"| Register
    Parse -->|"&lt;tool&gt; &lt;slug&gt;"| Swap

    subgraph Register["Register Flow"]
        RCheck{"Snapshot dir\nexists?"}
        RCheck -->|"Yes, no --force"| RDie["❌ Refuse\n(use --force)"]
        RCheck -->|"Yes + --force"| RClean["Clean existing snapshot\n(refuse if symlink)"]
        RCheck -->|No| RSnapshot
        RClean --> RSnapshot["Snapshot current live auth"]
        RSnapshot --> RActive["Write active-accounts.json\n(this slug is now active)"]
    end

    subgraph Swap["Swap Flow"]
        STarget{"Target snapshot\nexists?"}
        STarget -->|No| SDie["❌ Refuse\n(register first)"]
        STarget -->|Yes| SGuard["Process guard\n(check no active CLI)"]
        SGuard --> SAutoSnap{"Previous active\nslug exists?"}
        SAutoSnap -->|Yes| SSnapPrev["Auto-snapshot outgoing\n(preserve current auth)"]
        SAutoSnap -->|No| SRestore
        SSnapPrev --> SRestore["Restore incoming auth"]
        SRestore --> SWrite["Update active-accounts.json"]
        SWrite --> SNotify["macOS notification\n(osascript)"]
    end
```

## Per-Tool Credential Paths

```mermaid
flowchart LR
    subgraph Claude["Claude (macOS Keychain)"]
        direction TB
        CSnap["Snapshot:\nsecurity find-generic-password\n→ base64 → keychain.b64\n(mode 0600)"]
        CRestore["Restore:\n❌ DISABLED for real macOS\nsecurity CLI (secret in\nprocess args)\n→ User must re-auth manually"]
        CGate["Gate:\n--allow-keychain-prompt\nrequired (may prompt\nfor login password)"]
    end

    subgraph Gemini["Gemini (OAuth file)"]
        direction TB
        GSnap["Snapshot:\ncp oauth_creds.json\n→ auth-snapshots/gemini/&lt;slug&gt;/\n(mode 0600)"]
        GRestore["Restore:\ncp snapshot → ~/.gemini/oauth_creds.json\n+ ~/.gemini/accounts/oauth_creds.&lt;slug&gt;.json\n+ write .active_slug file"]
        GGuard["Guard:\nNone (stateless per-call)\n→ safe to swap anytime"]
    end

    subgraph Codex["Codex (auth.json)"]
        direction TB
        XSnap["Snapshot:\ncp auth.json\n→ auth-snapshots/codex/&lt;slug&gt;/\n(mode 0600)"]
        XRestore["Restore:\ncp snapshot → ~/.codex/auth.json\n(atomic via mkstemp + mv)"]
        XGuard["Guard:\npgrep codex\n(refuse if CLI running,\nskip GUI helpers)"]
    end
```

## Storage Layout

```mermaid
flowchart TB
    subgraph EcoHome["~/.eco/"]
        subgraph AuthSnap["auth-snapshots/ (0700)"]
            Claude_Slugs["claude/&lt;slug&gt;/keychain.b64"]
            Gemini_Slugs["gemini/&lt;slug&gt;/oauth_creds.json"]
            Codex_Slugs["codex/&lt;slug&gt;/auth.json"]
        end
        ActiveJSON["state/active-accounts.json (0600)\n{claude: 'slot-a', gemini: 'slot-b', codex: 'slot-c'}"]
    end

    subgraph Live["Live Credential Stores"]
        Keychain["macOS Keychain\n(Claude Code-credentials)"]
        GeminiCreds["~/.gemini/oauth_creds.json"]
        CodexAuth["~/.codex/auth.json"]
    end

    AuthSnap <-->|"register / swap"| Live
    ActiveJSON -.->|"tracks which slug\nis currently live"| AuthSnap
```

## Source References

| Component | Source |
|-----------|--------|
| Recipe script | [`src/recipes/account-swap.sh`](../../src/recipes/account-swap.sh) |
| BATS tests | [`tests/bats/09_account_swap.bats`](../../tests/bats/09_account_swap.bats) |

**Related docs:** [Architecture](../architecture.md) · [Recipes](../subsystems/recipes.md) · [Security Model](../operations/security-model.md) · [Runbook §7](../operations/runbook.md)
