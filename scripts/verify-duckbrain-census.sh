#!/bin/sh
# verify-duckbrain-census.sh — composed DuckBrain census gate for make verify
# (DF-H3-46). Runs both census guards, classifies their VERDICT lines, and
# refuses to compose an UNVERIFIED substrate into a green gate.
#
# Exit codes:
#   0 = both guards VERIFIED; or UNVERIFIED explicitly allowed via
#       H3_GATE_ALLOW_UNVERIFIED=1 (disclosed on stdout); or the machine has
#       NO DuckBrain token dir at all and the legs were UNVERIFIED — degraded
#       to a disclosed skip (QA-H3-25: make verify must stay green on a fresh
#       clone; nothing was verified, and the disclosure names what was not)
#   1 = a guard FAILED; or any guard was UNVERIFIED while a token dir EXISTS
#       and the opt-in is absent (strict, unchanged)
#   2 = misuse / guard shape change (no VERDICT line to classify)
#
# Env:
#   H3_TICK_CHAIN_TOKEN_DIR, H3_TREE_CENSUS_ARGS, H3_TREE_CENSUS_TOKEN_DIR —
#   passed through to the guards unchanged.
#   H3_GATE_ALLOW_UNVERIFIED=1 — explicit opt-in to accept an UNVERIFIED
#   substrate (disclosed, never silent).
set -u

NAME="duckbrain-census-gate"
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

ALLOW=${H3_GATE_ALLOW_UNVERIFIED:-0}

# ---- guard 1: tick-chain checker (POSIX sh + jq + curl) -------------------
sh "$REPO_ROOT/scripts/check-duckbrain-tick-chain.sh" >"$WORK/tickchain.out" 2>&1
tc_rc=$?
cat "$WORK/tickchain.out"

# ---- guard 2: independent tree-census walker (python3 stdlib) -------------
if command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_ROOT/scripts/duckbrain-tree-census.py" h3 --start 418 \
        --end auto --url http://localhost:3000 ${H3_TREE_CENSUS_ARGS:-} \
        >"$WORK/census.out" 2>&1
    walk_rc=$?
    cat "$WORK/census.out"
else
    echo "duckbrain-tree-census: UNVERIFIED — python3 not found on PATH (the independent census was not run)"
    echo "VERDICT: UNVERIFIED (python3 absent)"
    walk_rc=3
    : >"$WORK/census.out"
fi

# ---- classify --------------------------------------------------------------
classify() {
    # $1 = output file, $2 = rc; prints verdict name on stdout
    if grep -q '^VERDICT: FAILED' "$1"; then
        echo FAILED
    elif grep -q '^VERDICT: VERIFIED' "$1" && [ "$2" -eq 0 ]; then
        echo VERIFIED
    elif grep -q '^VERDICT: UNVERIFIED' "$1" || [ "$2" -eq 3 ]; then
        echo UNVERIFIED
    else
        echo NOVERDICT
    fi
}

TC_VERDICT=$(classify "$WORK/tickchain.out" "$tc_rc")
WALK_VERDICT=$(classify "$WORK/census.out" "$walk_rc")

# A real failure always propagates, regardless of the other guard.
if [ "$TC_VERDICT" = "FAILED" ] || [ "$WALK_VERDICT" = "FAILED" ]; then
    echo "$NAME: FAIL — tick-chain=$TC_VERDICT census=$WALK_VERDICT"
    exit 1
fi

if [ "$TC_VERDICT" = "NOVERDICT" ] || [ "$WALK_VERDICT" = "NOVERDICT" ]; then
    echo "$NAME: FAIL — a census guard produced no VERDICT line (gate shape changed); refusing to compose" >&2
    exit 2
fi

if [ "$TC_VERDICT" = "VERIFIED" ] && [ "$WALK_VERDICT" = "VERIFIED" ]; then
    echo "$NAME: PASS — both census guards VERIFIED"
    exit 0
fi

# ---- the DF-H3-46 path: at least one guard UNVERIFIED ---------------------
echo "$NAME: tick-chain=$TC_VERDICT census=$WALK_VERDICT"

# QA-H3-25: on a machine with NO DuckBrain token dir at all there is nothing
# to verify with, and make verify must still run green on a fresh clone
# (README zero-required-dependencies claim). Degrade to a DISCLOSED skip —
# name exactly what was not proven. With a token dir present, an UNVERIFIED
# verdict stays fatal (strictness unchanged) unless explicitly allowed.
TC_TOKEN_DIR=${H3_TICK_CHAIN_TOKEN_DIR:-$HOME/.duckbrain}
WALK_TOKEN_DIR=${H3_TREE_CENSUS_TOKEN_DIR:-$HOME/.duckbrain}
if [ ! -d "$TC_TOKEN_DIR" ] && [ ! -d "$WALK_TOKEN_DIR" ] && [ ! -d "$REPO_ROOT/scripts/.duckbrain" ]; then
    echo "make verify: SKIP — DuckBrain census UNVERIFIED on a token-less machine: no DuckBrain token dir at $TC_TOKEN_DIR; the tick-chain and tree census were NOT verified (install a token in $HOME/.duckbrain or set H3_TICK_CHAIN_TOKEN_DIR/H3_TREE_CENSUS_TOKEN_DIR to enable this gate)."
    exit 0
fi

if [ "$ALLOW" = "1" ]; then
    echo "make verify: DuckBrain census UNVERIFIED — allowed by H3_GATE_ALLOW_UNVERIFIED=1 (unverified substrate, named in the summary)"
    exit 0
fi
echo "make verify: FAIL — DuckBrain census refused an UNVERIFIED substrate (a DuckBrain token dir exists but the census did not verify). Set H3_GATE_ALLOW_UNVERIFIED=1 to accept an unverified substrate explicitly." >&2
exit 1
