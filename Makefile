SHELL := /bin/bash
ROOT  := $(shell pwd)
PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

.PHONY: help bootstrap venv install uninstall install-hooks test test-fast test-bats test-python test-e2e lint lint-python validate-docs generate-docs hygiene precommit actionlint security-audit snapshot release clean clean-venv

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## One-command full development environment setup
	bash scripts/bootstrap.sh

venv: ## Set up Python virtual environment and dependencies
	bash scripts/setup-venv.sh

install: ## Create ~/.eco dirs with per-file symlinks and register SwiftBar plugin
	bash scripts/install.sh

uninstall: ## Remove ~/.eco symlinks installed by us (preserves data)
	bash scripts/uninstall.sh

install-hooks: ## Install pre-commit and commit-msg hooks
	bash scripts/install-hooks.sh

test: test-bats test-python test-e2e ## Run ALL test suites (BATS + Python + E2E)

test-fast: test-bats test-python ## Run fast local tests (BATS + Python)

test-bats: ## Run BATS suites
	@echo "=== BATS ==="
	bash tests/run-all.sh bats

test-python: ## Run Python unit tests
	@echo ""
	@echo "=== Python ==="
	PYTHONPATH=src $(PYTHON) -m unittest discover -s tests/python -p "test_*.py"

test-e2e: ## Run end-to-end integration tests
	@echo ""
	@echo "=== E2E ==="
	bash tests/e2e/run_e2e.sh

lint: ## shellcheck + ruff on src/ and scripts/
	bash scripts/lint.sh
	$(PYTHON) -m ruff check src/ tests/python/

lint-python: ## Run ruff linter on Python code only
	$(PYTHON) -m ruff check src/ tests/python/ --fix

hygiene: lint precommit actionlint security-audit validate-docs ## Run repository hygiene checks
	git diff --check

validate-docs: ## Validate documentation links, INDEX.md coverage, and Mermaid diagrams
	@echo "=== Documentation Validation ==="
	bash docs/scripts/validate-links.sh
	bash docs/scripts/validate-mermaid.sh

precommit: ## Run all pre-commit hooks
	pre-commit run --all-files --show-diff-on-failure

actionlint: ## Validate GitHub Actions workflows
	actionlint

security-audit: ## Run current-tree secret scan and Python dependency audit
	gitleaks detect --no-git --source . --redact --config .gitleaks.toml
	$(PYTHON) -m pip_audit -r requirements.txt --strict

snapshot: ## Capture an ecosystem snapshot via the installed CLI
	~/.eco/bin/eco snapshot

release: ## Tag and push a release (usage: make release V=0.3.0)
	@test -n "$(V)" || (echo "usage: make release V=X.Y.Z" && exit 1)
	bash scripts/release.sh "$(V)"

clean: ## Remove local test artefacts
	rm -rf tests/reports tests/.tmp

generate-docs: ## Auto-generate CLI reference documentation
	bash docs/api/generate-cli-reference.sh

clean-venv: ## Remove the Python virtual environment
	rm -rf .venv
