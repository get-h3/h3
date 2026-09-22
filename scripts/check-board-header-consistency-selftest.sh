#!/bin/sh
# Positive + negative proof for scripts/check-board-header-consistency.sh
# (H3-GAP-099). Every case below is a REAL run of the guard against an isolated
# fake repo, and the guard's exit code is what is asserted — never a claim about
# what the code would do (QA-H3-1: zero cells is not a pass).
#
# Method: build a throwaway git repo with a board at the same relative path, a
# header, and an event log; then run the guard against it with -C-equivalent
# env overrides. The guard resolves ROOT from its own location, so the cases
# run it with H3_BOARD_HEADER_DIR pointing at an ABSOLUTE path outside the h3
# repo (the only supported way to point it elsewhere).
#
# Falsification proof: each negative case is asserted to FAIL the guard, and the
# summary reports the case count — disable a check and the matching case flips,
# which is how the last two cases (skip semantics) are themselves proven.
#
# Dependencies: POSIX sh, jq, git. No network.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
GUARD=$ROOT/scripts/check-board-header-consistency.sh

NAME=check-board-header-consistency-selftest
CASES_TOTAL=0
CASES_PASS=0

fail_case() {
    echo "  FAIL: $1"
}

# case_run <name> <expected-exit> <expected-substring> <board-dir> [extra env ...]
# Every case runs the guard against the FAKE repo (H3_BOARD_HEADER_ROOT) with a
# 3-tick recent window, so the C check has a tractable span.
case_run() {
    cname=$1; want_exit=$2; want_sub=$3; bdir=$4; shift 4
    CASES_TOTAL=$((CASES_TOTAL + 1))
    set +e
    OUT=$(env H3_BOARD_HEADER_ROOT="$FAKE" H3_BOARD_HEADER_RECENT=3 H3_BOARD_HEADER_DIR="$bdir" "$@" sh "$GUARD" 2>&1)
    RC=$?
    set -e
    ok=1
    [ "$RC" -eq "$want_exit" ] || { ok=0; fail_case "$cname: exit $RC, expected $want_exit"; }
    case "$OUT" in
        *"$want_sub"*) : ;;
        *) ok=0; fail_case "$cname: output does not contain '$want_sub'" ;;
    esac
    if [ "$ok" -eq 1 ]; then
        CASES_PASS=$((CASES_PASS + 1))
        echo "  ok  $cname (exit $RC)"
    else
        echo "  --- output of failing case $cname ---"
        printf '%s\n' "$OUT" | sed 's/^/      /'
    fi
}

command -v jq >/dev/null 2>&1 || { echo "$NAME: SKIP — jq not on PATH"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "$NAME: SKIP — git not on PATH"; exit 0; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/h3-board-header-selftest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# A fake repo whose HEAD is a commit, so the guard's HEAD/parent arithmetic is
# exercised for real. No board inside it: the board dirs below are separate
# absolute paths (D is expected to SKIP — proven by its own case).
FAKE=$WORK/fake-repo
mkdir -p "$FAKE"
git -C "$FAKE" init -q
git -C "$FAKE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
git -C "$FAKE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
git -C "$FAKE" -c user.email=t@t -c user.name=t commit -q --allow-empty -m three
FAKE_HEAD=$(git -C "$FAKE" rev-parse HEAD)
FAKE_PARENT=$(git -C "$FAKE" rev-parse HEAD^)
FAKE_GRANDPARENT=$(git -C "$FAKE" rev-parse HEAD~2)

# ---- fixture builders --------------------------------------------------------
# board_fixture <dir> <ticks_total> <last_commit> <max_event_tick> [<tick_with_no_event>]
# Events are written for every tick 1..max_event_tick except the named gap, so
# the fixture's own arithmetic never depends on a magic "-2".
board_fixture() {
    bd=$1; tt=$2; lc=$3; max=$4; gap=${5:-}
    mkdir -p "$bd"
    printf '{"project": "FAKE", "namespace": "fake", "version": 2, "ticks_total": %s, "ticks_idle": 0, "cooldown_s": 43200, "last_commit": "%s"}\n' \
        "$tt" "$lc" > "$bd/board.jsonl"
    : > "$bd/events.jsonl"
    i=0
    while [ "$i" -lt "$max" ]; do
        i=$((i + 1))
        [ -n "$gap" ] && [ "$gap" -eq "$i" ] && continue
        printf '{"id": %s, "tick_number": %s, "event_type": "audit"}\n' "$i" "$i" >> "$bd/events.jsonl"
    done
}

# ---- 1. VERIFIED: fresh header, complete recent window -----------------------
B1=$WORK/b1
board_fixture "$B1" 10 "$FAKE_HEAD" 10
case_run "fresh header at HEAD + complete window -> VERIFIED" 0 "VERDICT: VERIFIED" "$B1"

# ---- 2. A: last_commit one commit back is the documented two-phase state -----
B2=$WORK/b2
board_fixture "$B2" 10 "$FAKE_PARENT" 10
case_run "last_commit == HEAD's parent (post-push sync one commit ago) -> PASS" 0 "A PASS — last_commit" "$B2"

# ---- 3. A: STALE last_commit — the tick #468 drift, the finding of record ----
# A reachable-but-older commit is the exact measured failure: 5c1d5f4 was
# reachable from HEAD and three commits behind, so "is it an ancestor" alone
# would have PASSED it. This case pins the freshness bound.
B3c=$WORK/b3c
mkdir -p "$B3c"
printf '{"ticks_total": 10, "ticks_idle": 0, "last_commit": "%s"}\n' "$FAKE_GRANDPARENT" > "$B3c/board.jsonl"
: > "$B3c/events.jsonl"
i=0; while [ "$i" -lt 10 ]; do i=$((i+1)); printf '{"id": %s, "tick_number": %s}\n' "$i" "$i" >> "$B3c/events.jsonl"; done
case_run "reachable but 2 commits behind (the #468 stale-header drift) -> FAILED" 1 "behind the board it claims to describe" "$B3c"

B3=$WORK/b3
board_fixture "$B3" 10 0000000 10
case_run "unresolvable last_commit -> FAILED" 1 "does not resolve to a commit" "$B3"

B3b=$WORK/b3b
mkdir -p "$B3b"
printf '{"ticks_total": 10, "ticks_idle": 0, "last_commit": "%s"}\n' "$(printf 'a%.0s' $(seq 40))" > "$B3b/board.jsonl"
printf '{"id": 1, "tick_number": 10}\n' > "$B3b/events.jsonl"
case_run "well-formed but unknown last_commit -> FAILED" 1 "does not resolve to a commit" "$B3b"

# ---- 4. B: ticks_total behind the event log --------------------------------
B4=$WORK/b4
board_fixture "$B4" 8 "$FAKE_HEAD" 10
case_run "ticks_total BEHIND the event log -> FAILED" 1 "B: ticks_total 8 is BEHIND" "$B4"

# ---- 5. B: ticks_total == max recorded tick is fresh (not an error) ---------
B5=$WORK/b5
board_fixture "$B5" 10 "$FAKE_HEAD" 10
case_run "ticks_total == highest recorded tick -> B PASS" 0 "B PASS — ticks_total 10 == highest recorded tick" "$B5"

# ---- 6. C: the real phantom-hole trap — a tick with no event ---------------
# This is the case the 2026-09-21 independent audit got WRONG (it read only
# detail.tick and reported 457/458/463/466 as missing when all four are present
# via tick_number). Here the hole is real: tick 9 has no event, max is 10.
B6=$WORK/b6
board_fixture "$B6" 10 "$FAKE_HEAD" 10 9
case_run "a genuine tick hole in the recent window -> FAILED" 1 "C: tick(s) with NO event" "$B6"

# ---- 7. C: the detail.tick shape is READ (both shapes honoured) ------------
# Same board as B6 (tick 9 missing at top level) but tick 9 IS present in the
# detail-embedded shape — so the guard must NOT report a hole. Proves the guard
# reads both shapes; a reader of one shape reports a phantom hole here.
B7=$WORK/b7
board_fixture "$B7" 10 "$FAKE_HEAD" 10 9
printf '{"id": 99, "event_type": "audit", "detail": "{\\"tick\\": 9, \\"type\\": \\"work-tick\\"}"}\n' >> "$B7/events.jsonl"
case_run "tick present only as detail.tick -> NO hole (both shapes read)" 0 "C PASS — every tick 8..10" "$B7"

# ---- 8. A: skip semantics are REPORTED and actually skip the check ---------
B8=$WORK/b8
mkdir -p "$B8"
printf '{"ticks_total": 1, "ticks_idle": 0, "last_commit": "%s"}\n' "$(printf 'b%.0s' $(seq 40))" > "$B8/board.jsonl"
printf '{"id": 1, "tick_number": 1}\n' > "$B8/events.jsonl"
case_run "skip=A on an unresolvable last_commit -> VERIFIED + skip reported" 0 "SKIP REQUESTED" "$B8" H3_BOARD_HEADER_SKIP=A

# ---- 9. degrade: unreadable board -> UNVERIFIED, never a pass --------------
B9=$WORK/b9
mkdir -p "$B9"
case_run "empty board dir -> UNVERIFIED (not a pass)" 0 "VERDICT: UNVERIFIED" "$B9"

# ---- 9b. QA-H3-17: a tree WITHOUT .git degrades to UNVERIFIED, exit 0 -------
# The bunker 9252c745 finding: a tar --exclude=.git extraction carries the board
# but no commit history, so check A hard-FAILED ("does not resolve to a commit")
# and make verify went red on every fresh-install-shaped cell. Missing history
# is not a board defect. The tar image includes scripts/ and the board, but the
# FAKE repo is replaced via a later H3_BOARD_HEADER_ROOT (env last-wins), so the
# guard resolves ROOT to the git-less tree — exactly the tar-install shape.
NG=$WORK/no-git
mkdir -p "$NG"
( cd /home/kara/get-h3/h3 && tar --exclude=.git -cf - scripts .coding-hermes/board/board.jsonl ) | ( cd "$NG" && tar xf - )
case_run "tar extraction without .git -> UNVERIFIED, not FAILED (QA-H3-17)" 0 "UNVERIFIED (no git history" "$NG/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$NG"

# ---- 9c. QA-H3-17: SKIP=A does NOT bypass the git-less degrade --------------
# The degrade sits before check A and guards check D's git reads too, so a
# requested A-skip must not change the outcome.
case_run "SKIP=A on a git-less tree -> still UNVERIFIED (QA-H3-17)" 0 "UNVERIFIED (no git history" "$NG/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$NG" H3_BOARD_HEADER_SKIP=A

# ---- 10. degrade: RECENT is not an integer ---------------------------------
B10=$WORK/b10
board_fixture "$B10" 10 "$FAKE_HEAD" 10
case_run "H3_BOARD_HEADER_RECENT=abc -> UNVERIFIED" 0 "H3_BOARD_HEADER_RECENT is not a non-negative integer" "$B10" H3_BOARD_HEADER_RECENT=abc

# ---- 11. the real repo's own header is checked in `make verify` ------------
CASES_TOTAL=$((CASES_TOTAL + 1))
if grep -q 'check-board-header-consistency' "$ROOT/Makefile"; then
    CASES_PASS=$((CASES_PASS + 1))
    echo "  ok  Makefile wires the guard into make verify"
else
    fail_case "Makefile does not reference check-board-header-consistency"
fi

echo "$NAME: $CASES_PASS/$CASES_TOTAL PASSED"
[ "$CASES_PASS" -eq "$CASES_TOTAL" ] || exit 1
echo "$NAME: ALL PASS"
