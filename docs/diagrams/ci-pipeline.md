# CI/CD Pipeline

GitHub Actions workflow topography for eco-commander.

## Workflow Triggers

```mermaid
flowchart TB
    subgraph Triggers["Push / PR Triggers"]
        Push["Push to main"]
        PR["Pull Request to main"]
    end

    subgraph Scheduled["Scheduled Triggers"]
        CronDaily["Daily (cron)"]
        CronWeekly["Weekly (cron)"]
    end

    subgraph Manual["Manual Triggers"]
        ReleaseDispatch["workflow_dispatch\n(make release)"]
    end

    subgraph Workflows[".github/workflows/"]
        CI["ci.yml\n(Main test matrix)"]
        CodeQL["codeql.yml\n(Security scan)"]
        Hygiene["hygiene.yml\n(Linting, docs)"]
        Security["security.yml\n(Dependencies, secrets)"]
        Release["release.yml\n(Tag & publish)"]
        Stale["stale.yml\n(Issue/PR triage)"]
        Dependabot["dependabot-automerge.yml\n(Merge passing deps)"]
        DepReview["dependency-review.yml\n(PR dependency checks)"]
        CommitLint["commitlint.yml\n(PR title check)"]
        Labeler["labeler.yml\n(Auto-label PRs)"]
    end

    Push --> CI
    Push --> CodeQL
    Push --> Hygiene
    Push --> Security

    PR --> CI
    PR --> CodeQL
    PR --> Hygiene
    PR --> Security
    PR --> DepReview
    PR --> CommitLint
    PR --> Labeler

    CronDaily --> Stale
    CronWeekly --> Security

    ReleaseDispatch --> Release

    PR -.->|"Dependabot only\n(on success)"| Dependabot
```

## `ci.yml` — Main Test Matrix

```mermaid
flowchart TB
    subgraph CI["ci.yml"]
        direction TB
        Setup["Checkout\nSetup Python\nInstall requirements"]

        subgraph Jobs["Parallel Test Jobs"]
            BATS["BATS (Bash unit)\nmake test-bats"]
            Python["Python Unit\nmake test-python"]
            E2E["End-to-End\nmake test-e2e\n(uses mock binaries)"]
        end

        subgraph Gates["Pass/Fail"]
            Status{"All jobs\npassed?"}
            Pass["✅ Ready for merge"]
            Fail["❌ Blocked"]
        end

        Setup --> Jobs
        Jobs --> Status
        Status -->|Yes| Pass
        Status -->|No| Fail
    end
```

## `hygiene.yml` — Repository Health

```mermaid
flowchart TB
    subgraph Hygiene["hygiene.yml"]
        direction TB
        PreCommit["Pre-commit Hooks\n(trailing whitespace,\nyaml check)"]
        Docs["Docs Validation\nmake validate-docs\n(check dead links,\nINDEX.md coverage)"]
        ActionLint["Actionlint\n(Validate workflow YAML)"]
        ShellCheck["Shellcheck + ruff\nmake lint"]

        PreCommit --> PassH
        Docs --> PassH
        ActionLint --> PassH
        ShellCheck --> PassH
        PassH["✅ Hygiene Pass"]
    end
```

## `release.yml` — Tag and Publish

```mermaid
flowchart TB
    subgraph Release["make release V=0.3.0"]
        Local1["Update CHANGELOG.md"]
        Local2["git tag v0.3.0"]
        Local3["git push --tags"]
    end

    subgraph GitHubRelease["release.yml (triggered by push --tags)"]
        GH1["Extract changelog section"]
        GH2["Create GitHub Release"]
        GH3["Attach zip/tarball"]
    end

    Release --> GitHubRelease
```

## Source References

| Component | Source |
|-----------|--------|
| CI workflow | [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) |
| Release workflow | [`.github/workflows/release.yml`](../../.github/workflows/release.yml) |
| Security workflow | [`.github/workflows/security.yml`](../../.github/workflows/security.yml) |
| Hygiene workflow | [`.github/workflows/hygiene.yml`](../../.github/workflows/hygiene.yml) |
| Release script | [`scripts/release.sh`](../../scripts/release.sh) |
| Lint script | [`scripts/lint.sh`](../../scripts/lint.sh) |

**Related docs:** [Architecture](../architecture.md) · [CONTRIBUTING.md](../../CONTRIBUTING.md) · [Testing](../contributing/testing.md) · [Developer Hygiene](../contributing/developer-hygiene.md)
