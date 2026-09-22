#!/bin/sh
# check-duckbrain-tree-census-selftest.sh — executable negative proof for
# scripts/duckbrain-tree-census.py (H3-GAP-099, tick #474 census-promotion row).
#
# WHY THIS EXISTS
#   scripts/duckbrain-tree-census.py is the promoted /tmp walker the 79th (#469)
#   and 80th (#474) NEVER-DONE audits censused with. It sits in the gate
#   (`make verify-tick-chain`) and its census line is published in audit events
#   ("present=<N> missing=[..] unknown_drift=[..]"), so every one of its verdicts
#   has to be provable without network and without the live namespace. That is
#   what this file is: the census is only as trustworthy as its worst case, and
#   the worst case of a census is a broken tree that still reads as whole.
#
# THE CONTRACT THIS PINS, IN BOTH DIRECTIONS
#   * a CLEAN tree verifies: present=N missing=[] unknown_drift=[] exit 0;
#   * a HOLE fails and NAMES the missing N (exit 1);
#   * a wrong-shaped key ALONE (complete window, 0 holes) fails — the whole
#     point of the class: a census that reads only bare keys calls a drifted
#     chain contiguous (ticks #452/#453 did exactly that);
#   * the legacy class is TOLERATED but BOUNDED: /project/h3/tick/<N> with
#     N <= 427 (LEGACY_MAX) is not drift, the same shape above it IS — the live
#     tick-#466 specimen;
#   * the known-twin allowlist (452,453,464, the sibling guard's list) moves a
#     repaired key out of the failure class while `--allowlist ''` proves the
#     allowlist is what did it, not a broken classifier;
#   * a non-fatal key (timestamped slug, /tick/<N>/supplement note) is reported
#     and never fails the census;
#   * the documented --end default is pinned: no --end = EMPTY window (no hole
#     check, drift census still runs);
#   * every unreadable state (token env unset, unreachable API, missing /
#     unparseable tree file, capped listing, unreadable board header) degrades
#     to UNVERIFIED at exit 0 — never a PASS and never a FAIL over a tree that
#     was not read (QA-H3-1: zero cells is not a pass).
#
# Exit codes: 0 = every case behaved as specified, 1 = at least one did not,
#             2 = the selftest itself could not run (census script/fixtures).
#
# Zero network, zero DuckBrain contact: every case runs against a fixture in the
# scratch dir or against an unreachable URL, and every case pins the token env
# var explicitly so an inherited token cannot turn a fixture case into a live
# fetch. Dependencies: POSIX sh, python3 (stdlib only).

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CENSUS="$SCRIPT_DIR/duckbrain-tree-census.py"

if [ ! -f "$CENSUS" ]; then
    echo "FAIL: census script not found beside this selftest: $CENSUS" >&2
    exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tree-census-selftest.XXXXXX")
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

# run <tree-file> <args...> — the census with a pinned-empty token env, so a
# fixture case can never reach the network even if the ambient env has a token.
run() {
    tree=$1
    shift
    H3OPS_DUCKBRAIN_API_KEY= python3 "$CENSUS" h3 --tree-file "$tree" "$@"
}

echo "check-duckbrain-tree-census-selftest: positive + negative proof for scripts/duckbrain-tree-census.py"
echo "  scratch: $WORK"

# ---- fixtures ---------------------------------------------------------------
CLEAN="$WORK/clean.json"
cat > "$CLEAN" <<'JSON'
{
  "total": 12,
  "tree": [
    { "id": "/tick/418", "path": "/tick/418" },
    { "id": "/tick/419", "path": "/tick/419" },
    { "id": "/tick/420", "path": "/tick/420" },
    { "id": "/project/h3/tick/427", "path": "/project/h3/tick/427" },
    { "id": "/tick/419/supplement", "path": "/tick/419/supplement" },
    { "id": "/foreman/h3/tick/2026-09-19-08-01", "path": "/foreman/h3/tick/2026-09-19-08-01" }
  ]
}
JSON

# A HOLE at 419 (the window is complete at 418 and 420 only).
HOLE="$WORK/hole.json"
cat > "$HOLE" <<'JSON'
{
  "total": 2,
  "tree": [
    { "id": "/tick/418", "path": "/tick/418" },
    { "id": "/tick/420", "path": "/tick/420" }
  ]
}
JSON

# DRIFT ALONE: the window 418..420 is complete, but a wrong-shaped tick key
# exists at 419 — the class a bare-key-only census cannot see (H3-GAP-098/099).
DRIFT="$WORK/drift.json"
cat > "$DRIFT" <<'JSON'
{
  "total": 4,
  "tree": [
    { "id": "/tick/418", "path": "/tick/418" },
    { "id": "/tick/419", "path": "/tick/419" },
    { "id": "/tick/420", "path": "/tick/420" },
    { "id": "/project/h3/shim/tick/419", "path": "/project/h3/shim/tick/419" }
  ]
}
JSON

# The known-twin shape at N=452 (allowlisted by default) and the chain-A shape
# above LEGACY_MAX at 430 (NOT allowlisted): 452 is tolerated, 430 is drift.
BOUNDED="$WORK/bounded.json"
cat > "$BOUNDED" <<'JSON'
{
  "total": 6,
  "tree": [
    { "id": "/tick/418", "path": "/tick/418" },
    { "id": "/tick/419", "path": "/tick/419" },
    { "id": "/tick/420", "path": "/tick/420" },
    { "id": "/project/h3/tick/427", "path": "/project/h3/tick/427" },
    { "id": "/project/h3/protocol/tick/452", "path": "/project/h3/protocol/tick/452" },
    { "id": "/project/h3/tick/430", "path": "/project/h3/tick/430" }
  ]
}
JSON

# A capped listing: total reached the limit -> possibly truncated -> UNVERIFIED.
TRUNCATED="$WORK/truncated.json"
cat > "$TRUNCATED" <<'JSON'
{
  "total": 100,
  "tree": [
    { "id": "/tick/418", "path": "/tick/418" },
    { "id": "/tick/419", "path": "/tick/419" },
    { "id": "/tick/420", "path": "/tick/420" }
  ]
}
JSON

printf 'this is not json\n' > "$WORK/not-json.json"

# --- (a) a clean chain verifies ---------------------------------------------
case_run "(a) clean chain verifies: present=3 missing=[] unknown_drift=[]" 0 \
    "total leaf keys: 12 | tick-shaped keys: 4|window 418..420 (required 3|present=3 missing=[] unknown_drift=[]|legacy 1 keys|VERDICT: VERIFIED" \
    run "$CLEAN" --start 418 --end 420

# --- (b) a hole fails and is named ------------------------------------------
case_run "(b) hole at 419 fails: missing=[419] exit 1" 1 \
    "present=2 missing=[419] unknown_drift=[]|hole 419 (/tick/419 missing)|VERDICT: FAILED (1 hole(s): 419)" \
    run "$HOLE" --start 418 --end 420

# --- (c) drift ALONE fails (0 holes) ---------------------------------------
case_run "(c) complete window + wrong-shaped /project/h3/shim/tick/419 fails" 1 \
    "present=3 missing=[] unknown_drift=[419]|drift-key 419 /project/h3/shim/tick/419|VERDICT: FAILED" \
    run "$DRIFT" --start 418 --end 420

# --- (c2) the allowlist reclassifies a repaired twin, never a real drift ----
case_run "(c2) known twin 452 is drift-known, 430 stays unknown drift (bounded legacy class)" 1 \
    "drift-known 1 (allowlist 452,453,464|drift-known-key 452 /project/h3/protocol/tick/452|unknown_drift=[430]|drift-key 430 /project/h3/tick/430|VERDICT: FAILED" \
    run "$BOUNDED" --start 418 --end 420

case_run "(c3) --allowlist '' proves the allowlist is doing the work (452 becomes unknown drift)" 1 \
    "present=3 missing=[] unknown_drift=[430,452]|drift-key 452 /project/h3/protocol/tick/452" \
    run "$BOUNDED" --start 418 --end 420 --allowlist ''

case_run "(c4) with 430 allowlisted too the same tree verifies (2 known twins, 0 holes)" 0 \
    "present=3 missing=[] unknown_drift=[]|drift-known 2 (allowlist 430,452|VERDICT: VERIFIED" \
    run "$BOUNDED" --start 418 --end 420 --allowlist 430,452

# --- (e) the legacy class is tolerated, not drift --------------------------
# /project/h3/tick/427 (N <= LEGACY_MAX=427) must NOT be drift; the same shape
# one number above the bound IS (proved by the 430 case above).
case_run "(e) legacy /project/h3/tick/427 (N <= LEGACY_MAX) is not drift" 0 \
    "present=3 missing=[] unknown_drift=[]|legacy 1 keys|VERDICT: VERIFIED" \
    run "$CLEAN" --start 418 --end 420

case_run "(e2) the bound is real: --legacy-max 426 turns /project/h3/tick/427 into unknown drift" 1 \
    "unknown_drift=[427]|drift-key 427 /project/h3/tick/427" \
    run "$CLEAN" --start 418 --end 420 --legacy-max 426

# --- non-fatal classes stay non-fatal --------------------------------------
case_run "a /tick/<N>/supplement note and a timestamped slug are reported, not fatal" 0 \
    "other 2 (tick-like keys with no bare tick number|other-key /tick/419/supplement|VERDICT: VERIFIED" \
    run "$CLEAN" --start 418 --end 420

# --- the documented --end default: EMPTY window, no hole check --------------
case_run "no --end = EMPTY window: the same tree's hole at 419 is not reported" 0 \
    "window 418..417 (required 0|present=0 missing=[] unknown_drift=[]|VERDICT: VERIFIED" \
    run "$HOLE" --start 418

# --- --end auto: the board header is the window basis ----------------------
case_run "--end auto with --ticks-total 421 derives END=420 and verifies" 0 \
    "END=420 = ticks_total 421 - 1|present=3 missing=[] unknown_drift=[]|VERDICT: VERIFIED" \
    run "$CLEAN" --start 418 --end auto --ticks-total 421

# The board is resolved relative to the script's OWN location, so an isolated
# copy under a scratch tree (no .coding-hermes/) proves the unreadable-header
# branch without touching this repository.
ISO="$WORK/isolated/scripts"
mkdir -p "$ISO"
cp "$CENSUS" "$ISO/duckbrain-tree-census.py"
case_run "--end auto with an unreadable board header degrades to UNVERIFIED" 0 \
    "UNVERIFIED (board header unreadable|VERDICT: UNVERIFIED" \
    env H3OPS_DUCKBRAIN_API_KEY= python3 "$ISO/duckbrain-tree-census.py" h3 \
        --start 418 --end auto --tree-file "$CLEAN"

# --- (d) degrade: token env unset in live mode -----------------------------
case_run "(d) live mode with the token env unset degrades to UNVERIFIED" 0 \
    "UNVERIFIED (token env var is unset or empty: H3OPS_DUCKBRAIN_API_KEY|VERDICT: UNVERIFIED" \
    env H3OPS_DUCKBRAIN_API_KEY= python3 "$CENSUS" h3 --start 418 --end 420 \
        --url http://localhost:1/

case_run "(d2) a live fetch failure (unreachable URL) degrades to UNVERIFIED" 0 \
    "UNVERIFIED (DuckBrain API unreachable or refused|VERDICT: UNVERIFIED" \
    env H3OPS_DUCKBRAIN_API_KEY=selftest-not-a-real-token python3 "$CENSUS" h3 \
        --start 418 --end 420 --url http://localhost:1/

# --- (d3) degrade: unreadable tree in offline mode -------------------------
case_run "(d3) missing tree file degrades to UNVERIFIED" 0 \
    "UNVERIFIED (tree file is missing|VERDICT: UNVERIFIED" \
    run "$WORK/does-not-exist.json" --start 418 --end 420

case_run "(d4) unparseable tree file degrades to UNVERIFIED" 0 \
    "UNVERIFIED (answer is not parseable JSON|VERDICT: UNVERIFIED" \
    run "$WORK/not-json.json" --start 418 --end 420

case_run "(d5) a capped listing (total >= limit) degrades to UNVERIFIED" 0 \
    "UNVERIFIED (key-tree answer is possibly truncated|VERDICT: UNVERIFIED" \
    run "$TRUNCATED" --start 418 --end 420 --limit 100

case_run "(d6) the same listing below the limit is judged normally" 0 \
    "present=3 missing=[] unknown_drift=[]|VERDICT: VERIFIED" \
    run "$TRUNCATED" --start 418 --end 420 --limit 5000

case_run "(d7) a shifted window counts only the bare keys inside it (present=1, hole 419)" 1 \
    "present=1 missing=[419] unknown_drift=[]|hole 419 (/tick/419 missing)" \
    run "$HOLE" --start 419 --end 420

TOTAL=$((pass + fail))
echo "selftest: $pass/$TOTAL PASSED"
if [ "$fail" -ne 0 ]; then
    echo "selftest: FAILED — scripts/duckbrain-tree-census.py no longer proves the H3-GAP-099 contract (holes and unknown drift must go red; unreadable substrate must degrade to UNVERIFIED)" >&2
    exit 1
fi
echo "selftest: scripts/duckbrain-tree-census.py walks the DuckBrain key tree, fails on holes and unknown-shaped tick keys, and never claims a pass over a tree it could not read (H3-GAP-099)"
exit 0
