# Test Architecture

Testing strategy and layer mapping for eco-commander.

```mermaid
flowchart TB
    subgraph TestSuites["Test Layers"]
        direction TB
        BATS["BATS (Bash Unit)\ntests/bats/\n(Fast, mocked filesystem)"]
        Python["Python Unit\ntests/python/\n(Fast, no IO, pytest-style assertions via unittest)"]
        E2E["End-to-End\ntests/e2e/\n(Slow, sets up synthetic ~/.eco/)"]
        HealthCheck["Health Check\nscripts/healthcheck.sh\n(Live environment validator)"]
    end

    subgraph Targets["System Under Test"]
        CLI["src/bin/"]
        Recipes["src/recipes/"]
        Poller["src/poller/"]
        Scheduler["src/scheduler/"]
        Widget["eco-commander.15s.sh"]
    end

    BATS -->|Covers| CLI
    BATS -->|Covers| Recipes
    BATS -->|Covers| Widget

    Python -->|Covers| Poller
    Python -->|Covers| Scheduler

    E2E -->|Integration| CLI
    E2E -->|Integration| Recipes
    E2E -->|Integration| Poller
    E2E -->|Integration| Scheduler

    HealthCheck -.->|Opt-in live checks| Targets
```

## Running Tests

| Command | Suite | Speed | Isolation |
|---------|-------|-------|-----------|
| `make test-bats` | Bash Unit | Very fast | Mocked binaries (`$PATH` override) |
| `make test-python` | Python Unit | Very fast | Patched objects, no IO |
| `make test-fast` | Bash + Python | Very fast | Full unit coverage |
| `make test-e2e` | End-to-End | Slow (~5s) | Synthetic `$ECO_HOME` dir |
| `make test` | All three suites | Slow | Full confidence |

## Mocking Boundaries

```mermaid
flowchart LR
    subgraph BATS_Mocks["tests/helpers/mock_binaries/"]
        MockGemini["gemini (returns fixture JSON)"]
        MockClaude["claude (returns empty)"]
        MockCodex["codex (returns stub status)"]
        MockOllama["ollama (returns 2 models)"]
        MockDocker["docker (returns 1 container)"]
    end

    BATS -.->|"Overridden PATH"| BATS_Mocks
    E2E -.->|"Overridden PATH"| BATS_Mocks

    subgraph Python_Mocks["unittest.mock"]
        PatchHTTP["patch('urllib.request.urlopen')"]
        PatchOS["patch('os.path.exists')"]
        PatchJSON["Mock JSON files"]
    end

    Python -.->|"Monkeypatch"| Python_Mocks
```

## Source References

| Component | Source |
|-----------|--------|
| BATS suites | [`tests/bats/`](../../tests/bats/) |
| Python unit tests | [`tests/python/`](../../tests/python/) |
| E2E harness | [`tests/e2e/run_e2e.sh`](../../tests/e2e/run_e2e.sh) |
| Test runner | [`tests/run-all.sh`](../../tests/run-all.sh) |
| Shared helpers | [`tests/helpers/common.bash`](../../tests/helpers/common.bash) |
| Coverage map | [`tests/COVERAGE_MAP.md`](../../tests/COVERAGE_MAP.md) |

**Related docs:** [Architecture](../architecture.md) · [Testing](../contributing/testing.md) · [CONTRIBUTING.md](../../CONTRIBUTING.md) · [CI Pipeline](ci-pipeline.md)
