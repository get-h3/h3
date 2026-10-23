#!/bin/sh
# check-roundtrip-selftest.sh — positive + negative proof for the self-contained
# round-trip workspace (H3-REVIEW-20261021-01).
#
# `integration/roundtrip/roundtrip.sh` now stages a declared workspace that
# reproduces the umbrella layout (pinned sibling SDK checkouts + a copy of the
# suite), so `make verify-roundtrip` works from a tree where only `h3/` is
# checked out. This script proves that resolution logic WITHOUT network access
# and WITHOUT running the SDK suites (--resolve-only):
#
#   PASS arms
#     1. sibling pins in siblings.lock are three full commit SHAs
#     2. a tree with ONLY h3/ + a file:// repo base fetches the pins into a
#        declared workspace (HEADs match the pins exactly, manifest records them)
#     3. a temp workspace is removed on exit; a declared one is kept
#     4. local sibling checkouts are REUSED (symlinked), not re-fetched
#
#   FAIL arms (must exit non-zero AND name the culprit)
#     5. unreachable repo base + no siblings -> names sdk-python + layout + bootstrap
#     6. bogus pin override                  -> names the sibling and the bad ref
#
#   Side effects
#     7. a resolve-only run writes nothing into this checkout (tracked fixtures
#        unchanged) — fixtures are generated inside the workspace
#     8. negative guard from the finding: `grep -c 'sdk-python' Makefile` >= 1
#
# Offline arms use the local sibling clones as the fetch SOURCE (file://): when a
# local clone does not contain the pinned revision the arm reports UNVERIFIED
# instead of pretending it ran.
#
# Exit codes: 0 = every arm passed (or honestly UNVERIFIED), 1 = at least one
# failed. Zero dependencies beyond POSIX sh, coreutils and git.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SUITE_DIR="$REPO_ROOT/integration/roundtrip"
LOCK_FILE="$SUITE_DIR/siblings.lock"
UMBRELLA_DIR=$(CDPATH= cd -- "$REPO_ROOT/.." && pwd)

FAILS=0
PASSES=0
UNVERIFIED=0

ok() { echo "  PASS: $*"; PASSES=$((PASSES + 1)); }
bad() { echo "  FAIL: $*"; FAILS=$((FAILS + 1)); }
unverified() { echo "  UNVERIFIED: $*"; UNVERIFIED=$((UNVERIFIED + 1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/h3-roundtrip-selftest-XXXXXX")
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

pin_for() {
    awk -v n="$1" '!/^[[:space:]]*#/ && NF >= 2 && $1 == n { print $2; exit }' "$LOCK_FILE"
}

# stage_bare_tree <umbrella-dir> — creates <umbrella>/h3 containing ONLY the
# suite, so the h3 checkout has no ../sdk-* siblings: the fresh-clone shape.
stage_bare_tree() {
    mkdir -p "$1/h3/integration"
    cp -a "$SUITE_DIR" "$1/h3/integration/roundtrip"
    rm -rf "$1/h3/integration/roundtrip/__pycache__"
    printf '%s\n' "$1/h3/integration/roundtrip/roundtrip.sh"
}

echo "== check-roundtrip-selftest: self-contained round-trip workspace (H3-REVIEW-20261021-01) =="
FIXTURES_BEFORE=$(git -C "$REPO_ROOT" status --porcelain -- integration/roundtrip/fixtures 2>/dev/null || true)

# ── Arm 1: the pins are real pins ────────────────────────────────
echo ""
echo "-- arm 1: siblings.lock pins three full commit SHAs"
if [ ! -f "$LOCK_FILE" ]; then
    bad "siblings.lock is missing at $LOCK_FILE"
else
    for name in sdk-python sdk-go sdk-typescript; do
        pin=$(pin_for "$name")
        if [ -z "$pin" ]; then
            bad "$name has no pin in siblings.lock"
        elif printf '%s' "$pin" | grep -Eq '^[0-9a-f]{40}$'; then
            ok "$name pinned to $pin"
        else
            bad "$name pin '$pin' is not a full 40-character commit SHA"
        fi
    done
fi

# ── Arm 2/3: fetch path from an h3-only tree ─────────────────────
echo ""
echo "-- arm 2: h3-only tree + file:// base fetches the pins (declared workspace)"
BARE=$(mktemp -d "$TMP/bare-XXXXXX")
RUNNER=$(stage_bare_tree "$BARE")
WS_DECL="$TMP/ws-declared"
mkdir -p "$WS_DECL"

FETCHABLE=1
for name in sdk-python sdk-go sdk-typescript; do
    src="$UMBRELLA_DIR/$name"
    pin=$(pin_for "$name")
    if [ ! -d "$src/.git" ]; then
        FETCHABLE=0
        break
    fi
    if ! git -C "$src" cat-file -e "${pin}^{commit}" 2>/dev/null; then
        FETCHABLE=0
        break
    fi
done

if [ "$FETCHABLE" != "1" ]; then
    unverified "local sibling clones absent or lacking the pinned revisions — offline fetch arm not exercised"
else
    if H3_ROUNDTRIP_REPO_BASE="file://$UMBRELLA_DIR" bash "$RUNNER" --resolve-only --workspace "$WS_DECL" >"$TMP/.arm2.out" 2>&1; then
        ok "resolve-only from an h3-only tree exited 0"
    else
        bad "resolve-only from an h3-only tree exited non-zero:"
        sed -n '1,15p' "$TMP/.arm2.out" | sed 's/^/      /'
    fi
    for name in sdk-python sdk-go sdk-typescript; do
        pin=$(pin_for "$name")
        head=""
        if [ -d "$WS_DECL/$name/.git" ]; then
            head=$(git -C "$WS_DECL/$name" rev-parse HEAD 2>/dev/null || echo unknown)
        fi
        if [ "$head" = "$pin" ]; then
            ok "$name fetched at the pinned revision ($pin)"
        else
            bad "$name workspace HEAD '${head:-<absent>}' != pin $pin"
        fi
    done
    if [ -f "$WS_DECL/h3/integration/roundtrip/roundtrip.sh" ]; then
        ok "suite staged inside the workspace"
    else
        bad "suite not staged inside the workspace"
    fi
    if [ -f "$WS_DECL/MANIFEST.txt" ] && grep -q '^sdk-python ' "$WS_DECL/MANIFEST.txt"; then
        ok "workspace MANIFEST.txt records the resolved siblings"
    else
        bad "workspace MANIFEST.txt missing or does not record the siblings"
    fi
    if grep -q 'source=fetched' "$WS_DECL/MANIFEST.txt" 2>/dev/null; then
        ok "manifest records source=fetched (not a local reuse)"
    else
        bad "manifest does not record source=fetched for the fetched siblings"
    fi
fi

echo ""
echo "-- arm 3: declared workspaces are kept, temp workspaces are removed"
if [ "$FETCHABLE" = "1" ] && [ -d "$WS_DECL" ] && [ -f "$WS_DECL/MANIFEST.txt" ]; then
    ok "declared workspace still exists after the run"
else
    unverified "declared-workspace retention needs the fetch arm above"
fi

if [ "$FETCHABLE" != "1" ]; then
    unverified "temp-workspace removal needs a reachable fetch source"
else
    H3_ROUNDTRIP_REPO_BASE="file://$UMBRELLA_DIR" bash "$RUNNER" --resolve-only >"$TMP/.arm3.out" 2>&1 || true
    TEMP_WS=$(sed -n 's/^Declared temporary workspace: \(.*\) (removed on exit)$/\1/p' "$TMP/.arm3.out" | head -1)
    if [ -z "$TEMP_WS" ]; then
        bad "a temp run did not print its declared workspace path"
    elif [ -d "$TEMP_WS" ]; then
        bad "temp workspace was not removed: $TEMP_WS"
    else
        ok "temp workspace removed on exit ($TEMP_WS)"
    fi
fi

# ── Arm 4: local sibling reuse ───────────────────────────────────
echo ""
echo "-- arm 4: an existing sibling checkout is reused, not re-fetched"
BARE_LOCAL=$(mktemp -d "$TMP/bare-local-XXXXXX")
RUNNER_LOCAL=$(stage_bare_tree "$BARE_LOCAL")
LOCAL_OK=1
for name in sdk-python sdk-go sdk-typescript; do
    if [ -d "$UMBRELLA_DIR/$name" ]; then
        ln -s "$UMBRELLA_DIR/$name" "$BARE_LOCAL/$name"
    else
        LOCAL_OK=0
    fi
done
if [ "$LOCAL_OK" != "1" ]; then
    unverified "local sibling checkouts absent — reuse arm not exercised"
else
    if H3_ROUNDTRIP_REPO_BASE="file://$TMP/does-not-exist" bash "$RUNNER_LOCAL" --resolve-only --workspace "$TMP/ws-local" >"$TMP/.arm4.out" 2>&1; then
        ok "resolve-only with local siblings exited 0"
    else
        bad "resolve-only with local siblings exited non-zero:"
        sed -n '1,15p' "$TMP/.arm4.out" | sed 's/^/      /'
    fi
    if grep -q 'source=local' "$TMP/.arm4.out"; then
        ok "siblings resolved from local checkouts (source=local)"
    else
        bad "siblings were not resolved as local reuses"
    fi
    if [ -e "$TMP/ws-local/sdk-python/src/h3_harness/protocol.py" ]; then
        ok "reused sibling is linkable and usable"
    else
        bad "reused sibling is not a usable checkout"
    fi
fi

# ── Arm 5: unreachable base is a loud, actionable failure ────────
echo ""
echo "-- arm 5: unreachable repo base names the sibling and the layout"
if H3_ROUNDTRIP_REPO_BASE="file://$TMP/no-such-mirror" bash "$RUNNER" --resolve-only --workspace "$TMP/ws-neg" >"$TMP/.arm5.out" 2>&1; then
    bad "unreachable base exited 0"
else
    ok "unreachable base exited non-zero"
fi
for needle in "sdk-python" "Required layout" "git clone --depth 1"; do
    if grep -q -- "$needle" "$TMP/.arm5.out"; then
        ok "failure output names: $needle"
    else
        bad "failure output does not name: $needle"
    fi
done

# ── Arm 6: a bad pin fails naming the sibling ───────────────────
echo ""
echo "-- arm 6: a bogus pin fails and names the sibling"
BOGUS="0123456789abcdef0123456789abcdef01234567"
if H3_ROUNDTRIP_REPO_BASE="file://$UMBRELLA_DIR" H3_SDK_GO_REF="$BOGUS" \
        bash "$RUNNER" --resolve-only --workspace "$TMP/ws-pin" >"$TMP/.arm6.out" 2>&1; then
    bad "bogus pin exited 0"
else
    ok "bogus pin exited non-zero"
fi
if grep -q 'sdk-go' "$TMP/.arm6.out"; then
    ok "bogus pin failure names sdk-go"
else
    bad "bogus pin failure does not name sdk-go"
fi

# ── Arm 7: no side effects in this checkout ─────────────────────
echo ""
echo "-- arm 7: resolve-only writes nothing into this checkout"
FIXTURES_AFTER=$(git -C "$REPO_ROOT" status --porcelain -- integration/roundtrip/fixtures 2>/dev/null || true)
if [ "$FIXTURES_BEFORE" = "$FIXTURES_AFTER" ]; then
    ok "tracked fixtures unchanged"
else
    bad "tracked fixtures changed during the selftest:"
    printf '%s\n' "$FIXTURES_AFTER" | sed 's/^/      /'
fi
if [ ! -d "$SUITE_DIR/.venv" ]; then
    ok "no interpreter state created next to the suite"
else
    bad "the suite directory grew a .venv"
fi

# ── Arm 8: the finding's negative guard ─────────────────────────
echo ""
echo "-- arm 8: Makefile still names sdk-python (finding negative guard)"
COUNT=$(grep -c 'sdk-python' "$REPO_ROOT/Makefile" 2>/dev/null || true)
if [ "${COUNT:-0}" -ge 1 ]; then
    ok "grep -c 'sdk-python' Makefile = $COUNT (>= 1)"
else
    bad "grep -c 'sdk-python' Makefile = ${COUNT:-0} (< 1)"
fi

echo ""
echo "== check-roundtrip-selftest: $PASSES passed, $FAILS failed, $UNVERIFIED unverified =="
if [ "$FAILS" -ne 0 ]; then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
exit 0
