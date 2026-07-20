#!/usr/bin/env bash
# H3 Cross-Language Protocol Round-Trip Verification
#
# QV-PROTO-03: Verify Python and Go SDKs produce consistent wire format.
# Python generates fixtures → Go verifies. Go generates fixtures → Python verifies.
#
# Exit 0 = all pass, exit 1 = failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"  # h3/ repo root
UMBRELLA_DIR="$(cd "$ROOT_DIR/.." && pwd)"   # get-h3/ umbrella

SDK_PYTHON="${UMBRELLA_DIR}/sdk-python"
SDK_GO="${UMBRELLA_DIR}/sdk-go"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

phase_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    pass_count=$((pass_count + 1))
}

phase_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    fail_count=$((fail_count + 1))
}

# ─── Setup ───────────────────────────────────────────────────────

section "SETUP: Python SDK"
echo "Installing Python SDK from ${SDK_PYTHON}..."
cd "$SDK_PYTHON"
if [ ! -d ".venv" ]; then
    uv venv 2>&1 || python3 -m venv .venv
fi
.venv/bin/pip install -e ".[dev]" -q 2>&1
echo "Python SDK installed."
echo "Python: $(.venv/bin/python --version)"

section "SETUP: Go SDK"
cd "$SDK_GO"
echo "Go version: $(go version)"
echo "Go SDK at ${SDK_GO}"

# ─── Phase 1: Python → Go ───────────────────────────────────────

section "PHASE 1: Python generates → Go verifies"

cd "$SCRIPT_DIR"

echo "Step 1a: Generate Python fixtures..."
if ${SDK_PYTHON}/.venv/bin/python generate_fixtures.py; then
    phase_pass "Python fixture generation"
else
    phase_fail "Python fixture generation"
fi

echo "Step 1b: Verify with Go..."
if go run ./cmd/verify-python-fixtures/; then
    phase_pass "Go verification of Python fixtures"
else
    phase_fail "Go verification of Python fixtures"
fi

# ─── Phase 2: Go → Python ───────────────────────────────────────

section "PHASE 2: Go generates → Python verifies"

echo "Step 2a: Generate Go fixtures..."
if go run ./cmd/generate-go-fixtures/; then
    phase_pass "Go fixture generation"
else
    phase_fail "Go fixture generation"
fi

echo "Step 2b: Verify with Python..."
if ${SDK_PYTHON}/.venv/bin/python verify_go_fixtures.py; then
    phase_pass "Python verification of Go fixtures"
else
    phase_fail "Python verification of Go fixtures"
fi

# ─── Results ────────────────────────────────────────────────────

section "RESULTS"

echo ""
echo "Passed: ${pass_count}  Failed: ${fail_count}"
echo ""

if [ "$fail_count" -eq 0 ]; then
    echo -e "${GREEN}QV-PROTO-03: Cross-language protocol round-trip verification PASSED${NC}"
    echo "Python ↔ Go wire format is consistent."
    exit 0
else
    echo -e "${RED}QV-PROTO-03: Cross-language protocol round-trip verification FAILED${NC}"
    echo "${fail_count} phase(s) failed. See above for details."
    exit 1
fi
