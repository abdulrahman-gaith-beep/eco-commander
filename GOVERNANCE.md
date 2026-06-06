# Governance

## Decision-making

`eco-commander` is maintained by a single owner-operator
([@abdulrahman-gaith-beep](https://github.com/abdulrahman-gaith-beep)).
All decisions — feature approval, release timing, security patches — are the
maintainer's responsibility.

Contributions from others are welcome via pull requests. The maintainer has
final authority on all merges.

## Merge requirements

- Branch protection on `main` enforces CI pass, commitlint, CodeQL, dependency
  review, security scan, and hygiene checks.
- The maintainer may request review on risky changes, especially changes that
  touch security-sensitive paths listed in `CODEOWNERS`.
- Release, security, and governance changes remain maintainer-owned even when
  no second approving reviewer is required by branch protection.

## Architecture decisions

Material design choices are captured as Architecture Decision Records (ADRs)
in [`docs/adr/`](./docs/adr/). Add a new ADR for any change that:

- Alters the public CLI contract or exit codes.
- Changes the recipe annotation format.
- Modifies the snapshot directory layout.
- Introduces a new runtime dependency.
- Adds or removes a subsystem.

## Release authority

Only the maintainer may tag releases. The process is documented in
[`CONTRIBUTING.md`](./CONTRIBUTING.md#release-process) and enforced by the
release workflow.

## Conduct

All participants are expected to follow the
[Code of Conduct](./CODE_OF_CONDUCT.md).

## Amendments

This governance document can be amended by the maintainer at any time.
Material changes will be documented in the CHANGELOG.
