# H3 Project Makefile
# Spec hub + cross-repo integration tests

.PHONY: all lint test clean guard setup

all: lint test

# ── Python setup (test battery tooling) ──
VENV := .venv
PYTHON := $(VENV)/bin/python

setup:
	python3 -m venv $(VENV)
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -e ".[dev]"

# ── Lint ──
lint:
	@echo "=== Linting ==="
	@if [ -f "$(VENV)/bin/ruff" ]; then \
		$(VENV)/bin/ruff check .; \
	else \
		echo "venv not set up — run 'make setup'"; \
	fi

# ── Guard (GitReins Tier 1) ──
guard:
	timeout 120 gitreins guard

# ── Tests ──
test:
	@echo "=== Running integration tests ==="
	@if [ -f "$(VENV)/bin/pytest" ]; then \
		$(VENV)/bin/pytest tests/ -v --tb=short; \
	else \
		echo "venv not set up — run 'make setup'"; \
	fi

# ── Clean ──
clean:
	rm -rf $(VENV) .pytest_cache __pycache__ dist *.egg-info
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
