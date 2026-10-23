#!/usr/bin/env bash
# H3 Cross-Language Protocol Round-Trip Verification
#
# QV-PROTO-03: Verify Python and Go SDKs produce consistent wire format.
# Python generates fixtures → Go verifies. Go generates fixtures → Python verifies.
# QV-PROTO-04: ... plus Go → TypeScript.
#
# SELF-CONTAINED ON A FRESH CLONE (H3-REVIEW-20261021-01)
# ------------------------------------------------------
# The suite needs three sibling SDK checkouts, and the programs resolve them by
# RELATIVE PATH from their own location — that is what makes a bare `h3/` clone
# unable to run at all:
#
#   generate_fixtures.py / verify_go_fixtures.py   sys.path → ../../../sdk-python/src
#   verify_go_fixtures.ts                          import   → ../../../sdk-typescript/src/protocol
#   integration/roundtrip/go.mod                   replace  → ../../../sdk-go
#
# So this script no longer demands that the siblings already exist next to the
# clone. It stages a DECLARED TEMPORARY WORKSPACE that reproduces the umbrella
# layout, and runs every phase from inside it:
#
#   <workspace>/sdk-python                 local sibling (symlinked) OR pinned clone
#   <workspace>/sdk-go                     local sibling (symlinked) OR pinned clone
#   <workspace>/sdk-typescript             local sibling (symlinked) OR pinned clone
#   <workspace>/h3/integration/roundtrip/  copy of this suite (fixtures land here)
#
# Sibling revisions are PINNED in integration/roundtrip/siblings.lock (full commit
# SHAs, fetched with `git fetch --depth 1 origin <sha>`) so a fresh clone verifies
# against a known SDK revision instead of whatever HEAD happens to be. When a
# sibling checkout is present next to this repo it is REUSED (symlinked, so a
# local .venv/node_modules is not reinstalled) — local development keeps testing
# working-tree state. The workspace is removed on exit unless it was declared by
# the caller or keeping was requested.
#
# Fixtures are generated INSIDE the workspace, so a verification run no longer
# rewrites the tracked fixtures in this checkout; pass --sync-fixtures (or
# H3_ROUNDTRIP_SYNC_FIXTURES=1) after a green run to copy them back.
#
# Knobs (all optional):
#   --workspace <dir>               declare the workspace (kept, never deleted)
#   --resolve-only                  stage + report resolution, run nothing (test seam)
#   --sync-fixtures                 copy generated fixtures back into this checkout
#   H3_ROUNDTRIP_WORKSPACE=<dir>    same as --workspace
#   H3_ROUNDTRIP_REPO_BASE=<base>   repo base URL for fetches (file:// works offline)
#   H3_ROUNDTRIP_FORCE_FETCH=1      ignore local siblings, use the pinned refs
#   H3_ROUNDTRIP_KEEP_WORKSPACE=1   keep the temp workspace after the run
#   H3_ROUNDTRIP_SYNC_FIXTURES=1    same as --sync-fixtures
#   H3_SDK_PYTHON_REF=<ref>         override the sdk-python pin
#   H3_SDK_GO_REF=<ref>             override the sdk-go pin
#   H3_SDK_TS_REF=<ref>             override the sdk-typescript pin
#
# Exit 0 = all pass, exit 1 = failure (including "could not obtain a sibling").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"  # h3/ repo root
UMBRELLA_DIR="$(cd "$ROOT_DIR/.." && pwd)"   # get-h3/ umbrella (sibling search path)

LOCK_FILE="$SCRIPT_DIR/siblings.lock"
SDK_NAMES="sdk-python sdk-go sdk-typescript"
REPO_BASE="${H3_ROUNDTRIP_REPO_BASE:-https://github.com/get-h3/}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: bash integration/roundtrip/roundtrip.sh [--workspace DIR] [--resolve-only] [--sync-fixtures]"
    echo ""
    echo "Stages a temporary workspace (pinned sibling SDKs + a copy of this suite)"
    echo "and verifies Python ↔ Go ↔ TypeScript wire-format parity inside it."
    echo ""
    echo "  --workspace DIR   declare the workspace instead of a temp dir (kept on exit)"
    echo "  --resolve-only    stage the workspace and report what was resolved; run nothing"
    echo "  --sync-fixtures   copy generated fixtures back into this checkout (after PASS)"
    echo ""
    echo "See the header of this file (and CONTRIBUTING.md) for the full set of"
    echo "H3_ROUNDTRIP_* / H3_SDK_*_REF environment knobs."
}

WORKSPACE=""
RESOLVE_ONLY=0
SYNC_FIXTURES=0
WS_KIND=""
WS=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace)
            if [ "$#" -lt 2 ]; then
                echo -e "${RED}ERROR${NC}: --workspace needs a directory argument" >&2
                exit 2
            fi
            WORKSPACE="$2"
            shift 2
            ;;
        --workspace=*)
            WORKSPACE="${1#*=}"
            shift
            ;;
        --resolve-only|--dry-run)
            RESOLVE_ONLY=1
            shift
            ;;
        --sync-fixtures)
            SYNC_FIXTURES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR${NC}: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$WORKSPACE" ] && [ -n "${H3_ROUNDTRIP_WORKSPACE:-}" ]; then
    WORKSPACE="${H3_ROUNDTRIP_WORKSPACE}"
fi
if [ "${H3_ROUNDTRIP_SYNC_FIXTURES:-0}" = "1" ]; then
    SYNC_FIXTURES=1
fi

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

fail() {
    echo -e "${RED}ERROR${NC}: $*" >&2
    exit 1
}

# The exact sibling layout this suite resolves, plus the one-command bootstrap
# that satisfies it without relying on the pinned fetch (offline / no-git path).
print_layout_hint() {
    echo "" >&2
    echo "Required layout (the fixture programs resolve these by relative path):" >&2
    echo "  ${UMBRELLA_DIR}/h3" >&2
    echo "  ${UMBRELLA_DIR}/sdk-python" >&2
    echo "  ${UMBRELLA_DIR}/sdk-go" >&2
    echo "  ${UMBRELLA_DIR}/sdk-typescript" >&2
    echo "" >&2
    echo "One-command bootstrap (clone the siblings next to this repo):" >&2
    echo "  cd \"${UMBRELLA_DIR}\" && for s in sdk-python sdk-go sdk-typescript; do git clone --depth 1 \"https://github.com/get-h3/\$s.git\"; done" >&2
    echo "" >&2
    echo "Alternative: leave them absent and let this script fetch the pinned" >&2
    echo "revisions (needs network + git; see integration/roundtrip/siblings.lock)." >&2
}

cleanup() {
    local rc=$?
    trap - EXIT
    if [ -n "${WS:-}" ] && [ -d "${WS:-}" ]; then
        if [ "${H3_ROUNDTRIP_KEEP_WORKSPACE:-0}" = "1" ] || [ "$WS_KIND" = "declared" ]; then
            echo ""
            echo "workspace kept: ${WS}"
        else
            rm -rf "${WS}"
        fi
    fi
    exit "$rc"
}
trap cleanup EXIT

# ─── Workspace + sibling resolution ─────────────────────────────

sdk_marker() {
    case "$1" in
        sdk-python) echo "src/h3_harness/protocol.py" ;;
        sdk-go) echo "protocol/types.go" ;;
        sdk-typescript) echo "src/protocol.ts" ;;
        *) echo "" ;;
    esac
}

# URL for one sibling repo. An https/base URL gets the conventional `.git`
# suffix; a file:// base (used by the offline selftest, and handy for a local
# mirror) points at the bare checkout directory.
sibling_url() {
    local base="${REPO_BASE%/}" name="$1"
    case "$base" in
        file://*) printf '%s/%s\n' "$base" "$name" ;;
        *) printf '%s/%s.git\n' "$base" "$name" ;;
    esac
}

sdk_ref_override() {
    case "$1" in
        sdk-python) printf '%s' "${H3_SDK_PYTHON_REF:-}" ;;
        sdk-go) printf '%s' "${H3_SDK_GO_REF:-}" ;;
        sdk-typescript) printf '%s' "${H3_SDK_TS_REF:-${H3_SDK_TYPESCRIPT_REF:-}}" ;;
        *) printf '%s' "" ;;
    esac
}

read_pin() {
    # Prints the pinned ref for a sibling (empty + rc 1 when unknown).
    local name="$1" ref=""
    if [ -f "$LOCK_FILE" ]; then
        ref="$(awk -v n="$name" '!/^[[:space:]]*#/ && NF >= 2 && $1 == n { print $2; exit }' "$LOCK_FILE")"
    fi
    if [ -z "$ref" ]; then
        return 1
    fi
    printf '%s\n' "$ref"
}

is_full_sha() {
    case "$1" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
            return 0
            ;;
        *) return 1 ;;
    esac
}

reuse_local_sibling() {
    # Symlinks an existing sibling checkout into the workspace. Returns 1 when
    # there is nothing usable to reuse (absent dir, or a dir without the marker).
    local name="$1" pin="$2" dir="$UMBRELLA_DIR/$1" marker head
    marker="$(sdk_marker "$name")"
    if [ ! -d "$dir" ]; then
        return 1
    fi
    if [ ! -e "$dir/$marker" ]; then
        echo -e "${YELLOW}WARN${NC}: ${dir} exists but has no ${marker} — not a usable ${name} checkout; fetching the pin instead." >&2
        return 1
    fi
    ln -s "$dir" "$WS/$name"
    head="not-a-git-repo"
    if [ -d "$dir/.git" ]; then
        head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo unknown)"
    fi
    # A local checkout is reused on purpose (local development verifies its own
    # working tree), but a reused revision that is NOT the pin means this run is
    # not the reproducible one — say so instead of letting a green run imply it.
    if [ "$head" != "not-a-git-repo" ] && [ "$head" != "unknown" ] && [ "$head" != "$pin" ]; then
        echo -e "${YELLOW}WARN${NC}: reusing local ${name} at ${head}, which is NOT the pin ${pin} — set H3_ROUNDTRIP_FORCE_FETCH=1 to verify against the pinned revision." >&2
    fi
    printf 'source=local dir=%s head=%s\n' "$dir" "$head"
    return 0
}

fetch_sibling() {
    # Fetches one pinned sibling into the workspace. Fails loudly (rc 1) with the
    # exact repo/ref/url that could not be obtained.
    local name="$1" ref="$2" dest="$WS/$1"
    local url
    url="$(sibling_url "$name")"
    if ! command -v git >/dev/null 2>&1; then
        echo -e "${RED}ERROR${NC}: git is required to fetch ${name} (no ${UMBRELLA_DIR}/${name} sibling to reuse)" >&2
        return 1
    fi
    mkdir -p "$dest"
    git -C "$dest" init -q
    if git -C "$dest" remote get-url origin >/dev/null 2>&1; then
        git -C "$dest" remote set-url origin "$url"
    else
        git -C "$dest" remote add origin "$url"
    fi
    local marker
    marker="$(sdk_marker "$name")"
    # Re-running against a declared workspace: reuse the checkout when it already
    # sits on the requested ref (no network round-trip).
    if [ -e "$dest/$marker" ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo none)" = "$ref" ]; then
        printf 'source=cached url=%s ref=%s head=%s\n' "$url" "$ref" "$ref"
        return 0
    fi
    local err="$WS/.fetch-${name}.err"
    if ! git -C "$dest" fetch --quiet --depth 1 origin "$ref" 2>"$err"; then
        # Non-advertised SHA on some transports: fall back to a full ref fetch.
        if ! git -C "$dest" fetch --quiet origin '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*' 2>>"$err"; then
            echo -e "${RED}ERROR${NC}: could not fetch ${name} at ${ref} from ${url}" >&2
            sed -n '1,5p' "$err" 2>/dev/null >&2 || true
            return 1
        fi
    fi
    if git -C "$dest" cat-file -e "${ref}^{commit}" 2>/dev/null; then
        git -C "$dest" checkout -q "$ref"
    else
        git -C "$dest" checkout -q FETCH_HEAD
    fi
    local head
    head="$(git -C "$dest" rev-parse HEAD)"
    if is_full_sha "$ref" && [ "$head" != "$ref" ]; then
        echo -e "${RED}ERROR${NC}: ${name} pin mismatch — asked for ${ref}, checked out ${head}" >&2
        return 1
    fi
    if [ ! -e "$dest/$marker" ]; then
        echo -e "${RED}ERROR${NC}: ${name} at ${head} has no ${marker} — the pinned revision is not a usable SDK checkout" >&2
        return 1
    fi
    printf 'source=fetched url=%s ref=%s head=%s\n' "$url" "$ref" "$head"
    return 0
}

resolve_siblings() {
    local name ref info rc
    local manifest="$WS/MANIFEST.txt"
    : >"$manifest"
    {
        echo "# h3 round-trip sibling manifest (declared temporary workspace)"
        echo "# generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "# h3 checkout: ${ROOT_DIR}"
        echo "# repo base:   ${REPO_BASE}"
    } >>"$manifest"

    for name in $SDK_NAMES; do
        ref="$(sdk_ref_override "$name" || true)"
        if [ -z "$ref" ]; then
            if ! ref="$(read_pin "$name")"; then
                fail "no pinned ref for ${name} in ${LOCK_FILE} and no H3_SDK_*_REF override"
            fi
        fi

        info=""
        rc=1
        if [ "${H3_ROUNDTRIP_FORCE_FETCH:-0}" != "1" ]; then
            if info="$(reuse_local_sibling "$name" "$ref")"; then
                rc=0
            fi
        fi
        if [ "$rc" -ne 0 ]; then
            if ! info="$(fetch_sibling "$name" "$ref")"; then
                print_layout_hint
                fail "could not obtain sibling ${name} (pinned ${ref}) — see above"
            fi
        fi
        echo "  ${name}: ${ref} (${info})"
        echo "${name} ${ref} ${info}" >>"$manifest"
    done
}

stage_suite() {
    # A copy of THIS suite, so the relative `../../../sdk-*` resolutions land in
    # the workspace and generated fixtures never rewrite the caller's checkout.
    local dest="$WS/h3/integration/roundtrip"
    mkdir -p "$(dirname "$dest")"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude '__pycache__/' "$SCRIPT_DIR/" "$dest/"
    else
        mkdir -p "$dest"
        cp -a "$SCRIPT_DIR/." "$dest/"
        rm -rf "$dest/__pycache__"
    fi
}

sync_fixtures_back() {
    local src="$RUN_DIR/fixtures" dest="$SCRIPT_DIR/fixtures" ts
    if [ ! -d "$src" ]; then
        echo -e "${YELLOW}WARN${NC}: no ${src} to sync" >&2
        return 0
    fi
    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "$src/" "$dest/"
    else
        cp -a "$src/." "$dest/"
    fi
    ts="$(git -C "$ROOT_DIR" status --porcelain -- integration/roundtrip/fixtures 2>/dev/null | wc -l | tr -d ' ')"
    echo "fixtures synced into ${dest} (${ts} path(s) now differ from the committed tree)"
}

# ─── Stage ──────────────────────────────────────────────────────

section "WORKSPACE: resolve sibling SDKs (self-contained run)"

if [ -n "$WORKSPACE" ]; then
    WS="$WORKSPACE"
    WS_KIND="declared"
    mkdir -p "$WS"
    echo "Using declared workspace: ${WS} (kept on exit)"
else
    WS="$(mktemp -d "${TMPDIR:-/tmp}/h3-roundtrip-siblings-XXXXXX")"
    WS_KIND="temp"
    echo "Declared temporary workspace: ${WS} (removed on exit)"
fi
echo "h3 checkout: ${ROOT_DIR}"
echo "repo base:   ${REPO_BASE}"
echo "pins:        ${LOCK_FILE}"

resolve_siblings
echo "manifest: ${WS}/MANIFEST.txt"
cat "$WS/MANIFEST.txt"

stage_suite
RUN_DIR="$WS/h3/integration/roundtrip"
echo "staged suite: ${RUN_DIR}"

SDK_PYTHON="${WS}/sdk-python"
SDK_GO="${WS}/sdk-go"
SDK_TYPESCRIPT="${WS}/sdk-typescript"

if [ "$RESOLVE_ONLY" = "1" ]; then
    echo ""
    echo "resolve-only: workspace staged, nothing executed."
    for name in $SDK_NAMES; do
        if [ -d "${WS}/${name}" ]; then
            echo "  ${name}: present at ${WS}/${name}"
        else
            echo -e "${RED}  ${name}: MISSING${NC}"
            fail "resolve-only: ${name} is not in the workspace"
        fi
    done
    if [ ! -f "$RUN_DIR/roundtrip.sh" ]; then
        fail "resolve-only: staged suite missing at ${RUN_DIR}/roundtrip.sh"
    fi
    exit 0
fi

# ─── Setup ───────────────────────────────────────────────────────

section "SETUP: Python SDK"
echo "Installing Python SDK from ${SDK_PYTHON}..."
cd "$SDK_PYTHON"
if [ ! -d ".venv" ]; then
    uv venv 2>&1 || python3 -m venv .venv
fi
uv pip install --python .venv/bin/python -e ".[dev]" -q 2>&1 || .venv/bin/pip install -e ".[dev]" -q 2>&1
echo "Python SDK installed."
echo "Python: $(.venv/bin/python --version)"

section "SETUP: Go SDK"
cd "$SDK_GO"
echo "Go version: $(go version)"
echo "Go SDK at ${SDK_GO}"

# GAP-H3-REVIEW-001: install the TypeScript SDK dependencies before Phase 3.
# verify_go_fixtures.ts imports the SDK's protocol.ts (src), which imports
# zod — without an sdk-typescript/node_modules, `npx tsx verify_go_fixtures.ts`
# dies with "Cannot find module 'zod'" on a fresh clone (CI's roundtrip.yml
# has its own npm step; this script is the source of truth for the local
# `make verify-roundtrip` path).
# Idempotent + quiet-ish: npm ci / npm install are no-ops when node_modules
# already satisfies package-lock.json / package.json; npx reuses its cache
# so the tsx fetch only happens on first run.
section "SETUP: TypeScript SDK"
if [ ! -f "${SDK_TYPESCRIPT}/package.json" ]; then
    echo -e "${RED}ERROR${NC}: ${SDK_TYPESCRIPT}/package.json not found"
    exit 1
fi
cd "$SDK_TYPESCRIPT"
if [ -f package-lock.json ]; then
    echo "Installing TypeScript SDK dependencies (npm ci, lockfile present)..."
    if ! npm ci --no-audit --no-fund --loglevel=error; then
        echo -e "${RED}ERROR${NC}: npm ci failed in ${SDK_TYPESCRIPT}"
        exit 1
    fi
else
    echo "Installing TypeScript SDK dependencies (npm install, no lockfile)..."
    if ! npm install --no-audit --no-fund --loglevel=error; then
        echo -e "${RED}ERROR${NC}: npm install failed in ${SDK_TYPESCRIPT}"
        exit 1
    fi
fi
echo "TypeScript SDK dependencies installed."

# ─── Phase 1: Python → Go ───────────────────────────────────────

section "PHASE 1: Python generates → Go verifies"

cd "$RUN_DIR"

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

# ─── Phase 3: Go → TypeScript ──────────────────────────────────

section "PHASE 3: Go generates → TypeScript verifies"

echo "Step 3a: Go fixtures already generated in Phase 2..."
phase_pass "Go fixture generation (reuse from Phase 2)"

echo "Step 3b: Verify with TypeScript..."
if npx tsx verify_go_fixtures.ts; then
    phase_pass "TypeScript verification of Go fixtures"
else
    phase_fail "TypeScript verification of Go fixtures"
fi

# ─── Results ────────────────────────────────────────────────────

section "RESULTS"

echo ""
echo "Workspace: ${WS}"
echo "Passed: ${pass_count}  Failed: ${fail_count}"
echo ""

if [ "$fail_count" -eq 0 ]; then
    if [ "$SYNC_FIXTURES" = "1" ]; then
        sync_fixtures_back
    fi
    echo -e "${GREEN}QV-PROTO-04: Cross-language protocol round-trip verification PASSED${NC}"
    echo "Python ↔ Go ↔ TypeScript wire format is consistent."
    exit 0
else
    echo -e "${RED}QV-PROTO-04: Cross-language protocol round-trip verification FAILED${NC}"
    echo "${fail_count} phase(s) failed. See above for details."
    exit 1
fi
