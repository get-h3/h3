#!/bin/sh
# check-duckbrain-tick-chain-selftest.sh — executable negative proof for
# scripts/check-duckbrain-tick-chain.sh (H3-GAP-098).
#
# The contract this pins, in both directions:
#   * a CLEAN tick-key tree (fixtures/tick-chain/clean.json) exits 0 with
#     VERDICT: VERIFIED;
#   * a BROKEN tree (fixtures/tick-chain/broken.json — bare /tick/419 missing,
#     wrong-shaped /project/h3/shim/tick/420 present) exits 1 and NAMES both the
#     hole and the drifted path. A broken fixture that does NOT fail the checker
#     fails HERE — that is the whole point of this selftest: an undetected drift
#     must never read as contiguous;
#   * drift ALONE (0 holes, 1 unknown wrong-shaped key) already fails;
#   * the allowlist moves a known twin out of the failure class without
#     excusing a real hole;
#   * every unreadable state (missing tree file, no token, unreachable service,
#     unparseable JSON, no board header) degrades to UNVERIFIED at exit 0 —
#     never a PASS claim over a chain that was not read.
#
# Exit codes: 0 = every case behaved as specified, 1 = at least one did not,
#             2 = the selftest itself could not run (checker/fixtures missing).
#
# Zero network, zero DuckBrain contact: every case runs against a fixture file
# or an unreachable URL, with H3_TICK_CHAIN_TREE_FILE pinned or absent, and with
# all H3_TICK_CHAIN_* variables set explicitly so an inherited environment
# cannot change an outcome. Dependencies: POSIX sh, jq.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CHECK="$SCRIPT_DIR/check-duckbrain-tick-chain.sh"
FIXDIR="$SCRIPT_DIR/fixtures/tick-chain"
CLEAN="$FIXDIR/clean.json"
BROKEN="$FIXDIR/broken.json"

if [ ! -f "$CHECK" ]; then
    echo "FAIL: checker not found beside this selftest: $CHECK" >&2
    exit 2
fi
for f in "$CLEAN" "$BROKEN"; do
    if [ ! -f "$f" ]; then
        echo "FAIL: fixture not found: $f" >&2
        exit 2
    fi
done
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq not found" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tick-chain-selftest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

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
            IFS='|'
        done
        IFS=$OLDIFS
    fi
    echo "  ok: $name (exit $rc)"
    pass=$((pass + 1))
}

# Every case pins the full env surface, so an inherited H3_TICK_CHAIN_* value
# cannot leak into an outcome. The URL is deliberately unreachable: a case that
# ever reaches the network would fail here instead of passing by accident.
NO_TOKENS="$WORK/no-tokens"
mkdir -p "$NO_TOKENS"
CLEAN_ENV="H3_TICK_CHAIN_URL=http://localhost:1/ H3_TICK_CHAIN_NAMESPACE=h3 H3_TICK_CHAIN_TOKEN_DIR=$NO_TOKENS H3_TICK_CHAIN_START=418 H3_TICK_CHAIN_ALLOWLIST=452,453"

echo "check-duckbrain-tick-chain-selftest: positive + negative proof for scripts/check-duckbrain-tick-chain.sh"
echo "  scratch: $WORK"

# --- fixtures: a clean tree passes ------------------------------------------
# shellcheck disable=SC2086
case_run "clean fixture (418,419,420 present) verifies" 0 \
    "window 418..419 (required|window-present 2/2|holes 0|drift-unknown 0|VERDICT: VERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$CLEAN" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# --- fixtures: a hole AND a drifted key fail, both named --------------------
# shellcheck disable=SC2086
case_run "broken fixture (hole 419 + unknown drift) fails and names both" 1 \
    "hole 419 (/tick/419 missing|drift-unknown 1|drift-unknown-key 420 /project/h3/shim/tick/420|VERDICT: FAILED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$BROKEN" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# --- drift ALONE fails: the whole point of H3-GAP-098 ------------------------
# A tree whose window is complete but which also carries an unknown wrong-shaped
# key (the tick #452/#453 shape, under a different subtree) must go red. If the
# checker ever stops failing on drift, this case fails.
DRIFT_ONLY="$WORK/drift-only.json"
cat > "$DRIFT_ONLY" <<'JSON'
{
  "tree": [
    { "path": "/tick/418" },
    { "path": "/tick/419" },
    { "path": "/tick/420" },
    { "path": "/project/h3/protocol/tick/419" }
  ]
}
JSON
# shellcheck disable=SC2086
case_run "unknown drift with a complete window still fails (H3-GAP-098 core)" 1 \
    "holes 0|window-present 2/2|drift-unknown-key 419 /project/h3/protocol/tick/419|VERDICT: FAILED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$DRIFT_ONLY" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# --- the allowlist reclassifies a known twin, but never excuses a hole -------
# shellcheck disable=SC2086
case_run "allowlisted drift is reported as known, the hole still fails" 1 \
    "drift-known-key 420 /project/h3/shim/tick/420|drift-unknown 0|hole 419|VERDICT: FAILED" \
    env $CLEAN_ENV H3_TICK_CHAIN_ALLOWLIST=452,453,420 H3_TICK_CHAIN_TREE_FILE="$BROKEN" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# --- the legacy class is BOUNDED: a chain-A key above LEGACY_MAX is DRIFT ----
# Tick-#466 live specimen: tick 464 wrote its DuckBrain record at the drifted
# /project/h3/tick/464 while bare /tick/464 was missing. The old checker's
# legacy branch was UNBOUNDED, so a future drifted chain-A key would be
# silently tolerated forever. LEGACY_MAX=427 bounds the pre-#418 hub series;
# anything above it is drift. (Window 418..419 via TICKS_TOTAL=420 in both
# cases so the drift class is exercised on an otherwise hole-less tree.)
LEGACY_DRIFT="$WORK/legacy-drift.json"
cat > "$LEGACY_DRIFT" <<'JSON'
{
  "tree": [
    { "path": "/tick/418" },
    { "path": "/tick/419" },
    { "path": "/project/h3/tick/464" }
  ]
}
JSON
# shellcheck disable=SC2086
case_run "chain-A key above LEGACY_MAX is unknown drift (bounded legacy class, tick-#466 specimen)" 1 \
    "drift-unknown 1|drift-unknown-key 464 /project/h3/tick/464|VERDICT: FAILED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$LEGACY_DRIFT" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# shellcheck disable=SC2086
case_run "the same key with 464 allowlisted is only the known twin (tree then verifies)" 0 \
    "drift-known-key 464 /project/h3/tick/464|drift-unknown 0|holes 0|VERDICT: VERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_ALLOWLIST=452,453,464 H3_TICK_CHAIN_TREE_FILE="$LEGACY_DRIFT" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# --- degrade: the tree listing is possibly truncated (the capped-listing guard)
# A tree answer whose "total" reaches the LIMIT must be UNVERIFIED: a capped
# listing can omit bare keys (measured 2026-09-21: total:100 tree reported
# bare /tick/418 as a hole that exists) — judging a partial tree is the exact
# false-failure class this guard exists for.
TRUNCATED="$WORK/truncated.json"
cat > "$TRUNCATED" <<'JSON'
{
  "total": 100,
  "tree": [
    { "path": "/tick/418" },
    { "path": "/tick/419" },
    { "path": "/project/h3/tick/420" }
  ]
}
JSON
# shellcheck disable=SC2086
case_run "tree total >= limit degrades to UNVERIFIED (capped-listing guard)" 0 \
    "UNVERIFIED (key-tree answer is possibly truncated|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$TRUNCATED" H3_TICK_CHAIN_TICKS_TOTAL=420 H3_TICK_CHAIN_LIMIT=100 sh "$CHECK"

# --- positive: a total below the limit is judged normally ---------------------
# shellcheck disable=SC2086
case_run "tree total below limit still VERIFIES (guard does not over-fire)" 0 \
    "window-present 2/2|holes 0|VERDICT: VERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$TRUNCATED" H3_TICK_CHAIN_TICKS_TOTAL=420 H3_TICK_CHAIN_LIMIT=5000 sh "$CHECK"

# --- degrade: tree file missing ---------------------------------------------
# shellcheck disable=SC2086
case_run "missing tree file degrades to UNVERIFIED (never a PASS)" 0 \
    "UNVERIFIED|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$WORK/does-not-exist.json" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"
# --- degrade: no token, unreachable service ---------------------------------
# shellcheck disable=SC2086
case_run "no token file degrades to UNVERIFIED" 0 \
    "UNVERIFIED (no readable token|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# --- degrade: token present, service unreachable ----------------------------
printf 'not-a-real-token\n' > "$NO_TOKENS/selftest.token"
# shellcheck disable=SC2086
case_run "unreachable service (token present) degrades to UNVERIFIED" 0 \
    "UNVERIFIED (DuckBrain API unreachable|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"
rm -f "$NO_TOKENS/selftest.token"

# --- degrade: the answer is not parseable JSON ------------------------------
printf 'this is not json\n' > "$WORK/not-json.json"
# shellcheck disable=SC2086
case_run "unparseable JSON degrades to UNVERIFIED" 0 \
    "UNVERIFIED (answer is not parseable JSON|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$WORK/not-json.json" H3_TICK_CHAIN_TICKS_TOTAL=420 sh "$CHECK"

# --- degrade: ticks_total override is not an integer ------------------------
# shellcheck disable=SC2086
case_run "non-integer ticks_total degrades to UNVERIFIED" 0 \
    "UNVERIFIED (ticks_total is not an integer|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$CLEAN" H3_TICK_CHAIN_TICKS_TOTAL=four-hundred sh "$CHECK"

# --- degrade: no board header and no override -------------------------------
# The checker resolves the board relative to its OWN location, so an isolated
# copy under a scratch tree (no .coding-hermes/) is the honest way to prove the
# unreadable-header branch without touching this repository.
ISO="$WORK/isolated/scripts"
mkdir -p "$ISO"
cp "$CHECK" "$ISO/check-duckbrain-tick-chain.sh"
# shellcheck disable=SC2086
case_run "missing board header with no override degrades to UNVERIFIED" 0 \
    "UNVERIFIED (board header unreadable|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$CLEAN" sh "$ISO/check-duckbrain-tick-chain.sh"

# --- degrade: jq absent (PATH emptied) --------------------------------------
# The checker is exec'd through its own shebang, so the kernel resolves /bin/sh
# without PATH while `command -v jq` inside sees PATH=/nonexistent.
# shellcheck disable=SC2086
case_run "jq absent degrades to UNVERIFIED" 0 \
    "UNVERIFIED (jq not found|VERDICT: UNVERIFIED" \
    env $CLEAN_ENV H3_TICK_CHAIN_TREE_FILE="$CLEAN" H3_TICK_CHAIN_TICKS_TOTAL=420 PATH=/nonexistent "$CHECK"

TOTAL=$((pass + fail))
echo "selftest: $pass/$TOTAL PASSED"
if [ "$fail" -ne 0 ]; then
    echo "selftest: FAILED — scripts/check-duckbrain-tick-chain.sh no longer proves the H3-GAP-098 contract (drift must go red; unreadable states must degrade to UNVERIFIED)" >&2
    exit 1
fi
echo "selftest: scripts/check-duckbrain-tick-chain.sh detects tick-key shape drift and window holes, and never claims a pass over a chain it could not read (H3-GAP-098)"
exit 0
