#!/bin/sh
# check-verdict-census-selftest.sh — executable positive + negative proof for
# scripts/check-verdict-census.sh (DF-H3-41 / DF-H3-46).
#
# The contract this pins, in both directions:
#   * a CLEAN substrate (both guards' mirrors pass: offline fixture tree for
#     the tick-chain guard, offline fixture tree / sane args for the walker
#     mirror) exits 0 with "verdict census PASS" and the 2/0 census line;
#   * a BLOCKED substrate (no readable token anywhere the guards look) exits 1
#     and NAMES both unverified guards in the census line and the FAIL line —
#     the composite must NOT reach ALL PASS over an unchecked substrate;
#   * a TOKEN-LESS machine (DF-H3-48: no DuckBrain token dir anywhere either
#     guard looks — the same predicate scripts/verify-duckbrain-census.sh
#     applies before its own QA-H3-25 skip) exits 0 with the disclosed
#     "make verify: verdict census SKIP — ... token-less machine" line naming
#     the missing token dir, so `make verify` is green on a fresh clone; a
#     machine whose token dir EXISTS — even one carrying no *.token at all —
#     keeps the strict FAIL;
#   * H3_ALLOW_UNVERIFIED=1 turns that same blocked run into an explicit
#     degrade acceptance: exit 0 with the "(local degrade: N UNVERIFIED
#     accepted via H3_ALLOW_UNVERIFIED)" line; any other value (0) does NOT;
#   * single-guard attribution, both directions: only the tick-chain mirror
#     degraded -> the census line names tick-chain alone; only the tree-census
#     mirror degraded -> it names tree-census alone;
#   * both drift directions of the census counter, proven against MUTATED
#     COPIES of the census script (the same mutation discipline the sibling
#     selftests use for their fixtures): an under-count (blinding both
#     classify calls) must flip a BLOCKED substrate to a plain PASS with a
#     0-unverified census line, and an over-count (forcing both classify calls
#     to report unverified) must flip a CLEAN substrate to FAIL — a mutated
#     copy that did NOT drift would mean the verdict is not driven by the
#     counter this guard exists to enforce;
#   * a bad flag is a usage error (exit 2), never a verdict.
#
# HERMETIC: every case pins its own H3_TICK_CHAIN_* / H3_TREE_CENSUS_*
# variables explicitly (empty where the census must ignore the ambient
# value), so an inherited environment cannot change an outcome. DF-H3-48 adds
# the MACHINE's token state to that list: the census now has a token-less
# skip arm, so HOME (with no .duckbrain in it) and one EXISTING token dir are
# pinned for the whole run below and re-pinned by every arm that asserts a
# FAIL/hatch verdict — without those pins a fresh CI host would silently
# re-classify those arms as the skip arm and the proof would be vacuous. No
# network,
# no DuckBrain contact, no jq requirement (the offline fixtures take both
# mirrors down the tree-file path; the blocked case degrades on the token
# before any tool lookup matters). Dependencies: POSIX sh + coreutils + sed.
#
# Exit codes: 0 = every case behaved as specified, 1 = at least one did not,
#             2 = the selftest itself could not run (census/fixtures missing).

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CENSUS="$SCRIPT_DIR/check-verdict-census.sh"
FIXDIR="$SCRIPT_DIR/fixtures/tick-chain"
CLEAN="$FIXDIR/clean.json"

if [ ! -f "$CENSUS" ]; then
    echo "FAIL: census script not found beside this selftest: $CENSUS" >&2
    exit 2
fi
if [ ! -f "$CLEAN" ]; then
    echo "FAIL: fixture not found: $CLEAN" >&2
    exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/verdict-census-selftest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# ---- DF-H3-48 machine-state pins ---------------------------------------------
# The census now takes the composite's token-less skip (see its header), so
# every arm below runs on a PINNED machine state rather than an inherited one:
# HOME holds no .duckbrain, and one really-existing token dir stands in for a
# host that has a DuckBrain token. $TOKDIR (exported as
# H3_TREE_CENSUS_TOKEN_DIR) is what makes the strict arms prove "token dir
# present + UNVERIFIED substrate -> FAIL"; the two token-less arms further
# down override both pins with their own absent/empty dirs. Ambient token and
# arg inputs are cleared here so no inherited value can move an arm between
# the skip and the FAIL verdicts.
FAKE_HOME="$WORK/home"            # HOME with no .duckbrain in it
TOKDIR="$WORK/token-dir"          # existing token dir WITH one readable token
EMPTYDIR="$WORK/empty-token-dir"  # existing token dir with NO *.token in it
mkdir -p "$FAKE_HOME" "$TOKDIR" "$EMPTYDIR"
printf 'not-a-real-token\n' > "$TOKDIR/h3.token"
HOME="$FAKE_HOME"; export HOME
H3_TREE_CENSUS_TOKEN_DIR="$TOKDIR"; export H3_TREE_CENSUS_TOKEN_DIR
unset H3OPS_DUCKBRAIN_API_KEY H3_TICK_CHAIN_TOKEN_DIR H3_TICK_CHAIN_TREE_FILE \
    H3_TREE_CENSUS_ARGS H3_ALLOW_UNVERIFIED

pass=0
fail=0

# case_run <name> <expected-rc> <required-substrings '|'-separated, may be empty> <command...>
case_run() {
    name=$1
    want=$2
    want_texts=$3
    shift 3
    out=$("$@" 2>&1) && rc=0 || rc=$?
    if [ "$rc" != "$want" ]; then
        echo "  FAIL: $name — expected exit $want, got $rc" >&2
        printf '%s\n' "$out" | sed 's/^/        | /' >&2
        fail=$((fail + 1))
        return 0
    fi
    if [ -n "$want_texts" ]; then
        OLDIFS=$IFS
        IFS='|'
        for t in $want_texts; do
            IFS=$OLDIFS
            case $out in
                *"$t"*) : ;;
                *)
                    echo "  FAIL: $name — exit $rc as expected, but the output does not mention '$t'" >&2
                    printf '%s\n' "$out" | sed 's/^/        | /' >&2
                    fail=$((fail + 1))
                    return 0
                    ;;
            esac
        done
        IFS=$OLDIFS
    fi
    echo "  ok: $name (exit $rc)"
    pass=$((pass + 1))
}

# ---- the substrate arms ------------------------------------------------------
# Clean: both mirrors take the OFFLINE tree-file path — no token, no network,
# no board read (the walker mirror passes no --end, so no window basis).

case_run "clean substrate -> PASS 2/0" 0 \
    "make verify: verdict census — 2 verified / 0 unverified (guard: none)|make verify: verdict census PASS" \
    env H3_TICK_CHAIN_TREE_FILE="$CLEAN" \
        H3_TICK_CHAIN_TICKS_TOTAL=421 \
        H3_TREE_CENSUS_ARGS="--tree-file $CLEAN" \
        sh "$CENSUS"

# Blocked: no readable token anywhere either mirror looks. The tick-chain
# guard degrades first ("no readable token: no *.token file in ..."), the
# walker mirror via its explicit --token-file (missing) — hermetic on any
# host, including one whose ~/.duckbrain carries real tokens. DF-H3-48: the
# pinned $TOKDIR (an EXISTING token dir) is exactly the "a token dir exists
# but the substrate is unverified" state, which must stay a strict FAIL.

case_run "blocked token -> FAIL naming both guards" 1 \
    "make verify: verdict census — 0 verified / 2 unverified (guard: tick-chain tree-census)|make verify: verdict census FAIL — 2 unverified guard(s): tick-chain tree-census|no readable token: no *.token file in /nonexistent-h3-census-selftest|token file is missing: /nonexistent-h3-census-selftest/h3.token|DF-H3-41/DF-H3-46" \
    env H3_TICK_CHAIN_TREE_FILE= \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_ARGS="--token-file /nonexistent-h3-census-selftest/h3.token" \
        sh "$CENSUS"

# The escape hatch: the SAME blocked substrate accepted explicitly.

case_run "blocked token + H3_ALLOW_UNVERIFIED=1 -> explicit degrade PASS" 0 \
    "make verify: verdict census — 0 verified / 2 unverified (guard: tick-chain tree-census)|make verify: verdict census PASS (local degrade: 2 UNVERIFIED accepted via H3_ALLOW_UNVERIFIED)" \
    env H3_TICK_CHAIN_TREE_FILE= \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_ARGS="--token-file /nonexistent-h3-census-selftest/h3.token" \
        H3_ALLOW_UNVERIFIED=1 \
        sh "$CENSUS"

# Only the literal "1" enables the hatch: 0 must still FAIL.

case_run "blocked token + H3_ALLOW_UNVERIFIED=0 -> still FAIL" 1 \
    "make verify: verdict census FAIL — 2 unverified guard(s)" \
    env H3_TICK_CHAIN_TREE_FILE= \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_ARGS="--token-file /nonexistent-h3-census-selftest/h3.token" \
        H3_ALLOW_UNVERIFIED=0 \
        sh "$CENSUS"

# ---- DF-H3-48: the token-less machine (mirror of the composite's skip) -------

# No token dir anywhere either guard looks -> the census must reach the SAME
# verdict scripts/verify-duckbrain-census.sh reaches on this machine (its
# "SKIP — ... token-less machine" line, exit 0) instead of failing the fresh
# clone. The subtests name both the census count line and the disclosure; the
# guards' own fact lines (still printed above the skip) keep naming what was
# not verified.

case_run "token-less machine -> disclosed SKIP, exit 0 (DF-H3-48)" 0 \
    "make verify: verdict census — 0 verified / 2 unverified (guard: tick-chain tree-census)|make verify: verdict census SKIP — DuckBrain census UNVERIFIED on a token-less machine: no DuckBrain token dir at /nonexistent-h3-census-selftest|the tick-chain and tree census were NOT verified|no readable token: no *.token file in /nonexistent-h3-census-selftest" \
    env HOME="$FAKE_HOME" \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_TOKEN_DIR= \
        H3_TICK_CHAIN_TREE_FILE= \
        H3_TREE_CENSUS_ARGS="--token-file /nonexistent-h3-census-selftest/h3.token" \
        H3_ALLOW_UNVERIFIED= \
        sh "$CENSUS"

# The SAME blocked substrate with a token dir that EXISTS (but holds no
# *.token) is NOT token-less: strictness is unchanged, and the skip must not
# fire on a directory that simply does not resolve a token.

case_run "existing but empty token dir -> still strict FAIL, no skip (DF-H3-48)" 1 \
    "make verify: verdict census — 0 verified / 2 unverified (guard: tick-chain tree-census)|make verify: verdict census FAIL — 2 unverified guard(s): tick-chain tree-census" \
    env HOME="$FAKE_HOME" \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_TOKEN_DIR="$EMPTYDIR" \
        H3_TICK_CHAIN_TREE_FILE= \
        H3_TREE_CENSUS_ARGS="--token-file /nonexistent-h3-census-selftest/h3.token" \
        sh "$CENSUS"

# The predicate is the composite's DIRECTORY EXISTENCE test, deliberately not
# "is there a token anywhere": a token in H3OPS_DUCKBRAIN_API_KEY with no
# token dir still takes the composite's skip, so it must take this census's
# skip too (a narrower predicate here would re-open the DF-H3-48
# disagreement). The walker mirror counts its leg VERIFIED off the env token
# and the tick-chain leg is the one that degrades — the skip still fires.

case_run "env token, no token dir -> composite's SKIP is mirrored (DF-H3-48)" 0 \
    "make verify: verdict census — 1 verified / 1 unverified (guard: tick-chain)|make verify: verdict census SKIP — DuckBrain census UNVERIFIED on a token-less machine" \
    env HOME="$FAKE_HOME" H3OPS_DUCKBRAIN_API_KEY=not-a-real-token \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_TOKEN_DIR= \
        H3_TICK_CHAIN_TREE_FILE= \
        H3_TREE_CENSUS_ARGS= \
        sh "$CENSUS"

# ---- single-guard attribution, both directions -------------------------------

case_run "only tick-chain degraded -> census names tick-chain alone" 1 \
    "make verify: verdict census — 1 verified / 1 unverified (guard: tick-chain)|tree file is missing: /nonexistent-h3-census-selftest/tree.json|make verify: verdict census FAIL — 1 unverified guard(s): tick-chain" \
    env H3_TICK_CHAIN_TREE_FILE=/nonexistent-h3-census-selftest/tree.json \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_ARGS="--tree-file $CLEAN" \
        sh "$CENSUS"

case_run "only tree-census degraded -> census names tree-census alone" 1 \
    "make verify: verdict census — 1 verified / 1 unverified (guard: tree-census)|--allowlist entry is not an integer|make verify: verdict census FAIL — 1 unverified guard(s): tree-census" \
    env H3_TICK_CHAIN_TREE_FILE="$CLEAN" \
        H3_TICK_CHAIN_TICKS_TOTAL=421 \
        H3_TREE_CENSUS_ARGS="--allowlist 452,not-an-int,464" \
        sh "$CENSUS"

# ---- both drift directions of the census counter (mutated copies) -----------
# MUTATION DISCIPLINE: sed-rewrite exactly the two classify conditions in a
# COPY (never the original), assert the DRIFTED verdict on the same substrate.

MUT_UNDER="$WORK/census-undercount.sh"
MUT_OVER="$WORK/census-overcount.sh"
sed -e 's/if classify_tick_chain_sh; then/if true; then/' \
    -e 's/if classify_tree_census; then/if true; then/' \
    "$CENSUS" > "$MUT_UNDER"
sed -e 's/if classify_tick_chain_sh; then/if false; then/' \
    -e 's/if classify_tree_census; then/if false; then/' \
    "$CENSUS" > "$MUT_OVER"

# Under-count drift: the blocked substrate PASSes because the counter was
# blinded — the census line must show the DRIFTED 0-unverified count, and the
# plain (non-degrade) PASS line is the tell that the composite was greened by
# the mutation and by nothing else.

case_run "DRIFT under-count: blocked substrate must flip to a plain PASS 2/0" 0 \
    "make verify: verdict census — 2 verified / 0 unverified|make verify: verdict census PASS" \
    env H3_TICK_CHAIN_TREE_FILE= \
        H3_TICK_CHAIN_TOKEN_DIR=/nonexistent-h3-census-selftest \
        H3_TREE_CENSUS_ARGS="--token-file /nonexistent-h3-census-selftest/h3.token" \
        sh "$MUT_UNDER"

# Over-count drift: the clean substrate FAILs because the counter was forced —
# proving the FAIL path is counter-driven too, not substrate-driven only.

case_run "DRIFT over-count: clean substrate must flip to FAIL 0/2" 1 \
    "make verify: verdict census — 0 verified / 2 unverified|make verify: verdict census FAIL — 2 unverified guard(s)" \
    env H3_TICK_CHAIN_TREE_FILE="$CLEAN" \
        H3_TICK_CHAIN_TICKS_TOTAL=421 \
        H3_TREE_CENSUS_ARGS="--tree-file $CLEAN" \
        sh "$MUT_OVER"

# The mutations themselves are not silent: a mutated copy must DIFFER from the
# original (sha256), else the "drift" assertions above proved nothing.
orig_sum=$(sha256sum "$CENSUS" | awk '{print $1}')
under_sum=$(sha256sum "$MUT_UNDER" | awk '{print $1}')
over_sum=$(sha256sum "$MUT_OVER" | awk '{print $1}')
if [ "$under_sum" = "$orig_sum" ] || [ "$over_sum" = "$orig_sum" ]; then
    echo "  FAIL: mutation arms — a mutated copy is byte-identical to the original; the drift assertions are vacuous" >&2
    fail=$((fail + 1))
else
    echo "  ok: mutation copies differ from the original (sha256)"
    pass=$((pass + 1))
fi

# ---- usage error --------------------------------------------------------------

case_run "unknown flag -> usage error (exit 2)" 2 \
    "usage: sh scripts/check-verdict-census.sh" \
    env H3_TICK_CHAIN_TREE_FILE="$CLEAN" \
        H3_TICK_CHAIN_TICKS_TOTAL=421 \
        H3_TREE_CENSUS_ARGS="--tree-file $CLEAN" \
        sh "$CENSUS" --bogus-flag

# ---- summary ------------------------------------------------------------------
echo "check-verdict-census-selftest: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "check-verdict-census-selftest: PASS — the composite verdict census holds in both directions (DF-H3-41/DF-H3-46)"
exit 0
