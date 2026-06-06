# Operations

> Purpose: landing page for the operations documentation cluster — runbooks,
> security model, and quick-reference links for eco-commander operators.

## Documents in this cluster

| Doc | Purpose |
|-----|---------|
| [`runbook.md`](./runbook.md) | Step-by-step procedures for 10 common scenarios: general recovery, poller issues, scheduler stuck, OAuth expired, SwiftBar missing, full reinstall, account rotation, adding jobs, post-update health checks, crash-looping |
| [`security-model.md`](./security-model.md) | Full threat model: trust boundaries, per-tool credential handling, data sensitivity classification, attack surface, known limitations (base64 snapshot risk, no gitleaks rules), and required permissions |

## Reading order

Start with **`runbook.md`** if something is broken. Start with
**`security-model.md`** if you are reviewing or auditing the credential
handling surface.

1. [`runbook.md`](./runbook.md)
2. [`security-model.md`](./security-model.md)

## Quick links

| Question | Go here |
|----------|---------|
| Something is broken right now | [`runbook.md`](./runbook.md) |
| Specific symptom I don't recognise | [`../getting-started/troubleshooting.md`](../getting-started/troubleshooting.md) |
| Security audit or vulnerability review | [`security-model.md`](./security-model.md) → [`../../SECURITY.md`](../../SECURITY.md) |
| Alert investigation | [`../subsystems/alerts.md`](../subsystems/alerts.md) |
| Widget health | [`../subsystems/widget-health.md`](../subsystems/widget-health.md) |

## Agent boundary

Commands in these docs that read `~/.eco` logs or runtime JSON are **manual
operator checks only**. Do not paste raw output into agents or external tools —
provide a short redacted excerpt or summary instead.

## Related

- [`../../SECURITY.md`](../../SECURITY.md) — short-form security policy and vulnerability reporting
- [`../architecture.md`](../architecture.md) — system architecture overview
- [`../getting-started/troubleshooting.md`](../getting-started/troubleshooting.md) — symptom-first quick reference
