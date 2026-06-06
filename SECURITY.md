# Security policy

## Supported versions

Only the `main` branch and the latest tagged release receive security fixes.

## Scope

In scope:

- Repository code, GitHub Actions, release automation, install scripts, recipes,
  poller modules, scheduler modules, and LaunchAgent templates.
- Bugs that can expose local credentials, private filesystem paths, tokens,
  shell command injection, or unsafe writes under the user's home directory.

Out of scope:

- Social engineering, denial-of-service testing, physical access attacks, and
  issues in third-party CLIs or services unless eco-commander makes them worse.
- Reports that require reading private user data or prohibited local paths.

## Reporting a vulnerability

Please **do not** file a public issue for security reports. Instead:

1. Use **GitHub Private Vulnerability Reporting**: open the repository's
   **Security** tab → **Report a vulnerability** (this opens a private advisory
   visible only to the maintainers). If that is unavailable, open a regular issue
   titled `[security] contact request` (no details) and a maintainer will arrange
   a private channel.
2. Include reproduction steps, impacted version (`git rev-parse HEAD` is fine),
   and any proof-of-concept artefact.
3. You will receive an acknowledgement within 72 hours.

A coordinated disclosure timeline will be agreed before any public discussion.

## Handling timeline

- Acknowledgement: within 72 hours.
- Initial triage: within 7 calendar days when reproduction details are complete.
- Remediation target: critical fixes as soon as practical; lower-risk fixes in
  the next normal release window.
- Publication: after a fix is available or after an agreed disclosure date.

## Safe harbor

Good-faith testing is welcome when it stays within the repository and avoids
privacy-invasive actions. Do not access, modify, delete, or exfiltrate another
person's data. Stop and report immediately if testing reveals sensitive content.

### Agent privacy boundary

Agent-assisted audits are repo-only by default. Do not ask agents to scan broad
home directories, probe Keychain, ingest raw logs, upload snapshots/logs, inspect
sibling-user accounts, or touch prohibited macOS privacy surfaces. Use synthetic
fixtures, sanitized excerpts, or explicit manual operator checks instead.

## Threat model (short form)

`eco-commander` runs locally with the user's privileges. It does not open
listening sockets and does not embed credentials. Sensitive surface area:

- It executes recipes, which themselves may shell out to network tools
  (Claude, Gemini, Perplexity, Tavily). Recipes must validate and quote
  arguments.
- `~/.eco/snapshots/` may contain summaries of installed MCP servers and
  ecosystem state. Treat snapshot contents as confidential.

See [`docs/architecture.md`](./docs/architecture.md#12-security-boundaries)
for details.
