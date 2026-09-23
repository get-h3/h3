#!/bin/sh
# Positive + negative proof for scripts/sync-board-header.sh — the board-header
# WRITER (DF-H3-25). Every case is a REAL run of the writer (and, where it
# matters, of the guard that checks its output) against an isolated throwaway
# git repo; the exit code and the bytes on disk are what is asserted, never a
# claim about what the code would do (QA-H3-1: zero cells is not a pass).
#
# The row this proves: a fresh public clone failed `make verify` because the
# header's last_commit and ticks_total had been left behind by the two ticks
# that skipped the write-back. The cases below start from exactly that fixture
# (a stale header with the event log ahead of it), run the writer, and then
# require the GUARD to go green on the result — a writer is worth only what the
# checker says about its output, so the guard is asserted on the tree the writer
# just produced, not on a hand-written expectation.
#
# Falsification: delete the write (or let ticks_total come from a different
# reader than the guard uses) and the matching case flips red — case 1b/1d and
# the real-data agreement case 9 are the ones that pin it.
#
# Nothing outside ${TMPDIR:-/tmp} is written. The repository's own board is
# COPIED for the real-data case and asserted unchanged afterwards, so running
# this selftest cannot dirty the work tree it lives in.
#
# Dependencies: POSIX sh, coreutils, git, jq. No network.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SYNC=$ROOT/scripts/sync-board-header.sh
GUARD=$ROOT/scripts/check-board-header-consistency.sh

NAME=sync-board-header-selftest
CASES_TOTAL=0
CASES_PASS=0

fail_case() {
    echo "  FAIL: $1"
}

# ---- expectation helpers (every assertion is counted) ------------------------
expect_eq() {  # <name> <got> <want>
    CASES_TOTAL=$((CASES_TOTAL + 1))
    if [ "$2" = "$3" ]; then
        CASES_PASS=$((CASES_PASS + 1))
        echo "  ok  $1 = $2"
    else
        fail_case "$1: got '$2', wanted '$3'"
    fi
}

expect_sub() {  # <name> <text> <substring>
    CASES_TOTAL=$((CASES_TOTAL + 1))
    case $2 in
        *"$3"*)
            CASES_PASS=$((CASES_PASS + 1))
            echo "  ok  $1 (contains: $3)"
            ;;
        *)
            fail_case "$1: text does not contain '$3'"
            printf '%s\n' "$2" | sed 's/^/      /'
            ;;
    esac
}

expect_not_sub() {  # <name> <text> <substring that must be absent>
    CASES_TOTAL=$((CASES_TOTAL + 1))
    case $2 in
        *"$3"*)
            fail_case "$1: text unexpectedly contains '$3'"
            printf '%s\n' "$2" | sed 's/^/      /'
            ;;
        *)
            CASES_PASS=$((CASES_PASS + 1))
            echo "  ok  $1 (does not contain: $3)"
            ;;
    esac
}

# ---- runners -----------------------------------------------------------------
# run_sync <root> [env ...]  -> OUT, RC
run_sync() {
    rs_root=$1; shift
    set +e
    OUT=$(env H3_BOARD_HEADER_ROOT="$rs_root" "$@" sh "$SYNC" 2>&1)
    RC=$?
    set -e
}

# run_guard <root> <board-dir|-> [env ...]  -> GOUT, GRC
# "-" leaves H3_BOARD_HEADER_DIR at the repo default, so the guard's check D
# (committed header == working header) is live; an absolute path elsewhere
# makes D skip, which is how the copy of the real board is checked.
run_guard() {
    rg_root=$1; rg_bd=$2; shift 2
    if [ "$rg_bd" = "-" ]; then
        set +e
        GOUT=$(env H3_BOARD_HEADER_ROOT="$rg_root" H3_BOARD_HEADER_RECENT=3 "$@" sh "$GUARD" 2>&1)
        GRC=$?
        set -e
    else
        set +e
        GOUT=$(env H3_BOARD_HEADER_ROOT="$rg_root" H3_BOARD_HEADER_RECENT=3 H3_BOARD_HEADER_DIR="$rg_bd" "$@" sh "$GUARD" 2>&1)
        GRC=$?
        set -e
    fi
}

# ---- fixture builders --------------------------------------------------------
sha_of() { sha256sum -- "$1" | cut -d' ' -f1; }
hfield() { head -n 1 -- "$1" | jq -r "$2"; }

# normalise_l1 <header-line> — blank the four fields the writer owns, so the
# before/after comparison proves nothing ELSE on the line moved.
normalise_l1() {
    printf '%s\n' "$1" | sed -E \
        -e 's/("ticks_total"[[:space:]]*:[[:space:]]*)[0-9]+/\1X/' \
        -e 's/("last_commit"[[:space:]]*:[[:space:]]*")[^"]*(")/\1X\2/' \
        -e 's/("last_tick"[[:space:]]*:[[:space:]]*")[^"]*(")/\1X\2/' \
        -e 's/("updated_at"[[:space:]]*:[[:space:]]*")[^"]*(")/\1X\2/'
}

# mk_repo <dir> — three commits, board dir present, nothing in it yet
mk_repo() {
    d=$1
    mkdir -p "$d/.coding-hermes/board"
    git -C "$d" init -q
    git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
    git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
    git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m three
}

# write_events <dir> <max> [gap-tick]
# Covers all three recorded shapes, deliberately: the HIGHEST tick is written in
# the CURRENT writer's shape (a top-level numeric "tick", no tick_number and no
# detail-embedded tick) — a two-shape reader cannot see it, so every case that
# reaches <max> proves the reader reads the third shape too.
write_events() {
    we_bd=$1/.coding-hermes/board; we_max=$2; we_gap=${3:-}
    : > "$we_bd/events.jsonl"
    n=0
    while [ "$n" -lt "$we_max" ]; do
        n=$((n + 1))
        [ -n "$we_gap" ] && [ "$we_gap" -eq "$n" ] && continue
        if [ "$n" -eq "$we_max" ]; then
            printf '{"id": %s, "tick": %s, "event": "audit"}\n' "$n" "$n" >> "$we_bd/events.jsonl"
        else
            case $((n % 3)) in
                0) printf '{"id": %s, "tick": %s, "event": "audit"}\n' "$n" "$n" >> "$we_bd/events.jsonl" ;;
                1) printf '{"id": %s, "tick_number": %s, "event": "audit"}\n' "$n" "$n" >> "$we_bd/events.jsonl" ;;
                *) printf '{"id": %s, "event": "audit", "detail": "{\\"tick\\": %s}"}\n' "$n" "$n" >> "$we_bd/events.jsonl" ;;
            esac
        fi
    done
}

# write_board <dir> <ticks_total> <last_commit> [extra-line]
write_board() {
    wb_bd=$1/.coding-hermes/board; wb_tt=$2; wb_lc=$3; wb_extra=${4:-}
    printf '{"project": "FAKE", "namespace": "fake", "version": 2, "last_tick": "2026-01-01 00:00:00", "ticks_total": %s, "ticks_idle": 0, "cooldown_s": 43200, "last_commit": "%s", "updated_at": "2026-01-01 00:00:00"}\n' \
        "$wb_tt" "$wb_lc" > "$wb_bd/board.jsonl"
    if [ -n "$wb_extra" ]; then
        printf '%s\n' "$wb_extra" >> "$wb_bd/board.jsonl"
    fi
}

commit_board() {
    git -C "$1" add .coding-hermes
    git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "${2:-board}"
}

# new_commit <dir> <msg>
new_commit() {
    git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$2"
}

command -v jq >/dev/null 2>&1 || { echo "$NAME: SKIP — jq not on PATH"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "$NAME: SKIP — git not on PATH"; exit 0; }
command -v sha256sum >/dev/null 2>&1 || { echo "$NAME: SKIP — sha256sum not on PATH"; exit 0; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/h3-board-sync-selftest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# =============================================================================
# 1. the row's own fixture: a stale header, an event log ahead of it
# =============================================================================
F1=$WORK/stale
mk_repo "$F1"
write_events "$F1" 10
write_board "$F1" 3 "$(git -C "$F1" rev-parse HEAD~2)" '{"id": "tail", "note": "second line must survive byte-for-byte"}'
commit_board "$F1" board-stale

F1_TAIL_BEFORE=$(tail -n +2 "$F1/.coding-hermes/board/board.jsonl")
F1_HEADER_BEFORE=$(head -n 1 "$F1/.coding-hermes/board/board.jsonl")

echo "== 1. stale header (the fresh-clone failure of record) =="
run_guard "$F1" -
expect_eq "1a guard FAILs on the stale fixture" "$GRC" "1"
expect_sub "1a guard names the staleness class" "$GOUT" "behind the board it claims to describe"
expect_sub "1a guard names ticks_total BEHIND the event log" "$GOUT" "B: ticks_total 3 is BEHIND"
expect_sub "1a guard raises the greppable fleet line" "$GOUT" "PUBLIC-HEAD-VERIFY-FAIL"
expect_sub "1a guard reads the third (top-level tick) shape" "$GOUT" "max=10"

# ---- 1b: the writer fixes it -------------------------------------------------
run_sync "$F1"
expect_eq "1b writer exit" "$RC" "0"
expect_sub "1b writer summary names the re-pin" "$OUT" "last_commit="
F1_BOARD=$F1/.coding-hermes/board/board.jsonl
F1_HEAD=$(git -C "$F1" rev-parse --short HEAD)
expect_eq "1b last_commit = HEAD" "$(hfield "$F1_BOARD" '.last_commit')" "$F1_HEAD"
expect_eq "1b ticks_total = event-log max" "$(hfield "$F1_BOARD" '.ticks_total')" "10"
F1_TICK=$(hfield "$F1_BOARD" '.last_tick')
case $F1_TICK in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) F1_TICK_FMT=ok ;;
    *) F1_TICK_FMT=bad ;;
esac
expect_eq "1b last_tick uses the header's existing format" "$F1_TICK_FMT" "ok"
if date -u -d '2000-01-01 00:00:00' +%s >/dev/null 2>&1; then
    F1_NOW=$(date -u +%s)
    F1_THEN=$(date -u -d "$F1_TICK" +%s 2>/dev/null || echo 0)
    F1_DELTA=$((F1_NOW - F1_THEN))
    [ "$F1_DELTA" -lt 0 ] && F1_DELTA=$((-F1_DELTA))
    [ "$F1_DELTA" -le 5 ] && F1_TICK_FRESH=ok || F1_TICK_FRESH="stale(${F1_DELTA}s)"
else
    F1_TICK_FRESH="unchecked(no date -d)"
fi
expect_eq "1b last_tick is now, UTC" "$F1_TICK_FRESH" "ok"
expect_eq "1b updated_at mirrors last_tick" "$(hfield "$F1_BOARD" '.updated_at')" "$F1_TICK"
expect_eq "1b every other line byte-preserved" "$(tail -n +2 "$F1_BOARD")" "$F1_TAIL_BEFORE"
expect_eq "1b only the four owned fields changed on line 1" \
    "$(normalise_l1 "$(head -n 1 "$F1_BOARD")")" \
    "$(normalise_l1 "$F1_HEADER_BEFORE")"

# ---- 1c: the ORDER rule — synced but not committed is still a FAIL (D) -------
run_guard "$F1" -
expect_eq "1c guard FAILs while the synced header is uncommitted" "$GRC" "1"
expect_sub "1c the failure is check D (commit the board next)" "$GOUT" "D: the working-tree header differs"

# ---- 1d: commit the board -> the guard goes green ---------------------------
commit_board "$F1" board-synced
run_guard "$F1" -
expect_eq "1d guard VERIFIED after the board commit" "$GRC" "0"
expect_sub "1d guard verdict" "$GOUT" "VERDICT: VERIFIED"
expect_sub "1d freshness accepted as HEAD's parent (the documented state)" "$GOUT" "A PASS — last_commit"
expect_sub "1d tick total reconciled" "$GOUT" "B PASS — ticks_total 10 == highest recorded tick"

# ---- 1e: a LATER commit -> the writer re-pins to the new HEAD ---------------
new_commit "$F1" later-commit
run_sync "$F1"
expect_eq "1e writer exit after a later commit" "$RC" "0"
expect_sub "1e writer re-pins to the new HEAD" "$OUT" "-> $(git -C "$F1" rev-parse --short HEAD);"
expect_eq "1e header names the new HEAD" "$(hfield "$F1/.coding-hermes/board/board.jsonl" '.last_commit')" "$(git -C "$F1" rev-parse --short HEAD)"

# =============================================================================
# 2. idempotency: a second run with nothing to re-pin is a byte-identical no-op
# =============================================================================
F2=$WORK/idem
mk_repo "$F2"
write_events "$F2" 10
write_board "$F2" 3 "$(git -C "$F2" rev-parse HEAD~2)"
commit_board "$F2" board-stale

echo "== 2. idempotency =="
run_sync "$F2"
expect_eq "2a first run writes" "$RC" "0"
expect_not_sub "2a first run is not a no-op" "$OUT" "already in sync"
F2_SHA1=$(sha_of "$F2/.coding-hermes/board/board.jsonl")
run_sync "$F2"
expect_eq "2b second run exit" "$RC" "0"
expect_sub "2b second run reports already in sync" "$OUT" "already in sync"
expect_not_sub "2b second run reports a change" "$OUT" "-> "
expect_eq "2b second run is byte-identical" "$(sha_of "$F2/.coding-hermes/board/board.jsonl")" "$F2_SHA1"
run_sync "$F2"
expect_eq "2c third run exit" "$RC" "0"
expect_eq "2c third run still byte-identical" "$(sha_of "$F2/.coding-hermes/board/board.jsonl")" "$F2_SHA1"

# =============================================================================
# 3-8. refusals: nothing is written, the exit code is non-zero, the reason names
#      the input that was unusable
# =============================================================================
echo "== 3. missing board files =="
F3=$WORK/no-board
mk_repo "$F3"
write_events "$F3" 5
run_sync "$F3"
expect_eq "3a missing board.jsonl exit" "$RC" "2"
expect_sub "3a missing board.jsonl names the file" "$OUT" "board header is missing"

F4=$WORK/no-events
mk_repo "$F4"
write_board "$F4" 3 "$(git -C "$F4" rev-parse --short HEAD~1)"
run_sync "$F4"
expect_eq "4a missing events.jsonl exit" "$RC" "2"
expect_sub "4a missing events.jsonl names the file" "$OUT" "event log is missing"

echo "== 5-8. refusals =="
F5=$WORK/not-json
mk_repo "$F5"
write_events "$F5" 5
printf 'this is not a JSON object\n' > "$F5/.coding-hermes/board/board.jsonl"
commit_board "$F5" board-bad
F5_SHA=$(sha_of "$F5/.coding-hermes/board/board.jsonl")
run_sync "$F5"
expect_eq "5a non-JSON header exit" "$RC" "3"
expect_sub "5a non-JSON header is refused" "$OUT" "not a JSON object"
expect_eq "5a non-JSON header is left untouched" "$(sha_of "$F5/.coding-hermes/board/board.jsonl")" "$F5_SHA"

F6=$WORK/no-total
mk_repo "$F6"
write_events "$F6" 5
printf '{"project": "FAKE", "last_commit": "%s", "last_tick": "2026-01-01 00:00:00"}\n' "$(git -C "$F6" rev-parse --short HEAD)" \
    > "$F6/.coding-hermes/board/board.jsonl"
commit_board "$F6" board-no-total
F6_SHA=$(sha_of "$F6/.coding-hermes/board/board.jsonl")
run_sync "$F6"
expect_eq "6a header without ticks_total exit" "$RC" "3"
expect_sub "6a header without ticks_total is refused" "$OUT" "no numeric ticks_total"
expect_eq "6a header without ticks_total is left untouched" "$(sha_of "$F6/.coding-hermes/board/board.jsonl")" "$F6_SHA"

F7=$WORK/torn-log
mk_repo "$F7"
write_events "$F7" 5
printf '{"id": 6, "tick_number": 6, "torn\n' >> "$F7/.coding-hermes/board/events.jsonl"
write_board "$F7" 3 "$(git -C "$F7" rev-parse --short HEAD)"
commit_board "$F7" board-torn
F7_SHA=$(sha_of "$F7/.coding-hermes/board/board.jsonl")
run_sync "$F7"
expect_eq "7a torn event log exit" "$RC" "3"
expect_sub "7a torn event log is refused" "$OUT" "does not parse as JSONL"
expect_eq "7a torn event log leaves the header untouched (no partial read)" "$(sha_of "$F7/.coding-hermes/board/board.jsonl")" "$F7_SHA"

F8=$WORK/no-git
mkdir -p "$F8/.coding-hermes/board"
write_events "$F8" 5
write_board "$F8" 3 deadbee
F8_SHA=$(sha_of "$F8/.coding-hermes/board/board.jsonl")
run_sync "$F8"
expect_eq "8a tree without .git exit" "$RC" "3"
expect_sub "8a tree without .git is refused" "$OUT" "no git history"
expect_eq "8a tree without .git leaves the header untouched" "$(sha_of "$F8/.coding-hermes/board/board.jsonl")" "$F8_SHA"

# =============================================================================
# 9. the writer and the guard agree on the REAL board (543 events), and the
#    repository's own board is not the thing that got written
# =============================================================================
echo "== 9. real-data agreement (writer's tick scan vs the guard's reader) =="
REAL_SRC=$ROOT/.coding-hermes/board
if [ -f "$REAL_SRC/board.jsonl" ] && [ -f "$REAL_SRC/events.jsonl" ]; then
    REAL_SHA_BEFORE=$(sha_of "$REAL_SRC/board.jsonl")
    REAL=$WORK/real
    mkdir -p "$REAL"
    cp "$REAL_SRC/board.jsonl" "$REAL/board.jsonl"
    cp "$REAL_SRC/events.jsonl" "$REAL/events.jsonl"
    REAL_TAIL_BEFORE=$(tail -n +2 "$REAL/board.jsonl")

    run_guard "$ROOT" "$REAL"
    expect_sub "9a guard reads the real event log" "$GOUT" "event-ticks recorded="
    REAL_MAX=$(printf '%s\n' "$GOUT" | sed -n 's/.*max=\([0-9][0-9]*\).*/\1/p' | head -n 1)
    expect_eq "9a guard max is numeric" "$(printf '%s' "$REAL_MAX" | grep -cE '^[0-9]+$')" "1"

    run_sync "$ROOT" H3_BOARD_HEADER_DIR="$REAL"
    expect_eq "9b writer exit on the real board copy" "$RC" "0"
    expect_eq "9b writer's ticks_total == the guard's max" "$(hfield "$REAL/board.jsonl" '.ticks_total')" "$REAL_MAX"
    expect_eq "9b writer pins the repo's HEAD" "$(hfield "$REAL/board.jsonl" '.last_commit')" "$(git -C "$ROOT" rev-parse --short HEAD)"
    expect_eq "9b copy's other lines byte-preserved" "$(tail -n +2 "$REAL/board.jsonl")" "$REAL_TAIL_BEFORE"
    expect_eq "9c the repo's own board.jsonl was NOT written" "$(sha_of "$REAL_SRC/board.jsonl")" "$REAL_SHA_BEFORE"
else
    echo "  (skipped: this repo has no board files)"
fi

# =============================================================================
# 10. the close-out is WIRED — and stays out of `make verify`
# =============================================================================
echo "== 10. close-out wiring =="
MAKEFILE=$ROOT/Makefile
expect_eq "10a Makefile has a board-close target" "$(grep -cE '^board-close:' "$MAKEFILE" || true)" "1"
expect_sub "10a board-close runs the writer" "$(grep -A2 -E '^board-close:' "$MAKEFILE")" "scripts/sync-board-header.sh"
expect_sub "10a board-close is .PHONY" "$(grep -E '^\.PHONY:' "$MAKEFILE")" "board-close"
expect_sub "10b Makefile documents the close-out contract" "$(cat "$MAKEFILE")" "THE BOARD-WRITING CLOSE-OUT"
expect_sub "10b README documents the close-out step" "$(cat "$ROOT/README.md")" "make board-close"
expect_sub "10b README documents the greppable fleet alert" "$(cat "$ROOT/README.md")" "PUBLIC-HEAD-VERIFY-FAIL"
expect_not_sub "10c make verify does NOT write the board (read-only gate)" "$(grep -E '^verify:' "$MAKEFILE")" "board-close"
expect_eq "10d Makefile wires the writer's selftest" "$(grep -cE 'sync-board-header-selftest\.sh' "$MAKEFILE" || true)" "2"

echo "$NAME: $CASES_PASS/$CASES_TOTAL PASSED"
[ "$CASES_PASS" -eq "$CASES_TOTAL" ] || exit 1
echo "$NAME: ALL PASS"
