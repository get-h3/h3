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

expect_sub() {  # <name> <text> <substring that must be present>
    CASES_TOTAL=$((CASES_TOTAL + 1))
    case $2 in
        *"$3"*)
            CASES_PASS=$((CASES_PASS + 1))
            echo "  ok  $1 (contains: $3)"
            ;;
        *)
            fail_case "$1: text does not contain '$3'"
            ;;
    esac
}

expect_not_sub() {  # <name> <text> <substring that must be absent>
    CASES_TOTAL=$((CASES_TOTAL + 1))
    case $2 in
        *"$3"*)
            fail_case "$1: text unexpectedly contains '$3'"
            ;;
        *)
            CASES_PASS=$((CASES_PASS + 1))
            echo "  ok  $1 (does not contain: $3)"
            ;;
    esac
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

# ---- 7b. C: the THIRD shape — a top-level numeric `tick` (DF-H3-25) --------
# The current board writer emits `"tick": N` on the event object itself, with no
# tick_number and a detail that holds no tick. Until the guard read that shape,
# such a tick was invisible: it read as a hole in the recent window (the case
# below fails without the modern row) and could not size the header. This pair
# is the falsification proof — the same fixture PASSES with the modern row and
# FAILs on the phantom hole without it.
B7b=$WORK/b7b
board_fixture "$B7b" 10 "$FAKE_HEAD" 10 10
printf '{"id": 100, "tick": 10, "event": "audit"}\n' >> "$B7b/events.jsonl"
case_run "tick present only as a top-level .tick -> read (max + no hole)" 0 "B PASS — ticks_total 10 == highest recorded tick" "$B7b"
B7c=$WORK/b7c
board_fixture "$B7c" 10 "$FAKE_HEAD" 10 10
case_run "the same tick, top-level .tick row absent -> a real hole is still a hole" 1 "C: tick(s) with NO event" "$B7c"

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

# ---- 9d. QA-H3-18: missing last_commit object in a shallow fresh copy -------
# The QA evidence class: a shallow sync of this repo carries a self-consistent
# board (B/C/D green) but lacks the header's commit object (bfd3cf6, which on
# a shallow copy is an unfetched ancestor), so A's rev-parse could not tell
# "the hash is wrong" from "the object is not fetched" and hard-FAILED, red
# `make verify` on an otherwise-consistent copy. In a shallow copy the local
# history is not provenance for the header's hash, so the guard now reports
# missing provenance as UNVERIFIED (degraded, greppable) instead of FAILED.
SH=$WORK/shallow
git clone -q --depth 1 "file://$FAKE" "$SH"
git -C "$SH" -c user.email=t@t -c user.name=t commit -q --allow-empty -m four
SH_HEAD=$(git -C "$SH" rev-parse HEAD)
board_fixture "$SH/.coding-hermes/board" 3 "$SH_HEAD" 3
case_run "shallow copy, last_commit = its own HEAD -> VERIFIED" 0 "VERDICT: VERIFIED" "$SH/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SH"

SHc=$WORK/shallow-missing
git clone -q --depth 1 "file://$FAKE" "$SHc"
board_fixture "$SHc/.coding-hermes/board" 3 "$FAKE_PARENT" 3
case_run "shallow copy, unresolvable last_commit -> UNVERIFIED + degraded, exit 0" 0 "VERDICT: UNVERIFIED (last_commit provenance unavailable" "$SHc/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SHc"
case_run "shallow copy, unresolvable last_commit -> A UNVERIFIED line" 0 "A UNVERIFIED — last_commit" "$SHc/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SHc"
case_run "shallow copy, unresolvable last_commit -> greppable degraded line" 0 "PUBLIC-HEAD-VERIFY-UNVERIFIED" "$SHc/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SHc"
set +e
SHc_OUT=$(env H3_BOARD_HEADER_ROOT="$SHc" H3_BOARD_HEADER_RECENT=3 H3_BOARD_HEADER_DIR="$SHc/.coding-hermes/board" sh "$GUARD" 2>&1)
set -e
expect_not_sub "shallow copy, unresolvable last_commit -> no PUBLIC-HEAD-VERIFY-FAIL (not a stale-board failure)" "$SHc_OUT" "PUBLIC-HEAD-VERIFY-FAIL"
expect_not_sub "shallow copy, unresolvable last_commit -> no A FAIL line (degraded, not failed)" "$SHc_OUT" "FAIL — A: last_commit"
expect_sub "shallow copy, unresolvable last_commit -> B/C continue and pass" "$SHc_OUT" "C PASS — every tick 1..3"

# ---- 9e. QA-H3-18: full clone — an unresolvable hash is still a FAIL --------
# Provenance IS available in a full clone: an unknown hash there is a bogus
# value, not an unfetched ancestor, so the honest verdict stays FAILED (a
# degrade must never swallow a real defect).
FKe=$WORK/full-foreign
git clone -q "file://$FAKE" "$FKe"
board_fixture "$FKe/.coding-hermes/board" 3 "0000000" 3
case_run "full clone, unresolvable last_commit -> FAILED, exit 1" 1 "does not resolve to a commit" "$FKe/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$FKe"

# ---- 9f. QA-H3-18: provenance available — resolvable foreign commit FAILs ----
# Same shape as the failing arm but resolvable: the hash names a REAL commit
# this branch does not contain. Provenance is available and refutes the value,
# so this is a genuine inconsistency, not missing provenance.
FKf=$WORK/full-resolvable-foreign
git clone -q "file://$FAKE" "$FKf"
FKf_BASE=$(git -C "$FKf" rev-parse --abbrev-ref HEAD)
# A REAL commit that HEAD's history does not contain: an orphan-branch commit
# created inside the full clone itself — a resolvable object the provenance
# data refutes (not an ancestor of HEAD).
git -C "$FKf" checkout -q --orphan h3-foreign
git -C "$FKf" -c user.email=t@t -c user.name=t commit -q --allow-empty -m foreign
git -C "$FKf" checkout -q "$FKf_BASE"
FKf_TARGET=$(git -C "$FKf" rev-parse h3-foreign)
board_fixture "$FKf/.coding-hermes/board" 3 "$FKf_TARGET" 3
case_run "full clone, resolvable foreign last_commit -> FAILED (provenance refutes it)" 1 "not an ancestor of HEAD" "$FKf/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$FKf"

# ---- 9g. QA-H3-21: a git-init single-root-commit copy (FROZEN sync) --------
# The QA-H3-18 degrade keys on shallow/grafted, but the bunker FROZEN sync
# builds its copy as `git archive HEAD | tar -x` + `git init && git add -A &&
# git commit`: is-shallow-repository is FALSE and there is NO .git/shallow file,
# so the shallow probe cannot see it — yet the copy carries ONE synthetic root
# commit and the header's upstream commit is not in that history at all.
# Measured before the fix: A hard-FAILED ("does not resolve to a commit") on a
# copy whose B/C/D were all green. Fewer than two commits is a history-less
# copy, not provenance, so A degrades; a second real commit restores the hard
# FAIL — the last case in this block is that control.
SRS=$WORK/single-root-src
mkdir -p "$SRS/.coding-hermes/board"
git -C "$SRS" init -q
printf 'payload\n' > "$SRS/payload.txt"
git -C "$SRS" -c user.email=t@t -c user.name=t add -A
git -C "$SRS" -c user.email=t@t -c user.name=t commit -q -m upstream-one
SRS_HEAD=$(git -C "$SRS" rev-parse HEAD)
# The header pins the upstream commit (the documented two-phase state), and
# upstream then moves on — so the copy below is nobody's shallow clone, it is
# simply missing this history.
board_fixture "$SRS/.coding-hermes/board" 3 "$SRS_HEAD" 3
git -C "$SRS" -c user.email=t@t -c user.name=t add -A
git -C "$SRS" -c user.email=t@t -c user.name=t commit -q -m upstream-two

SR=$WORK/single-root
mkdir -p "$SR"
( cd "$SRS" && git archive HEAD ) | ( cd "$SR" && tar xf - )
git -C "$SR" init -q
git -C "$SR" -c user.email=t@t -c user.name=t add -A
git -C "$SR" -c user.email=t@t -c user.name=t commit -q -m init
# Fixture sanity — the SHAPE is the point: not shallow, no shallow file, one
# commit (the assertion is the pair, so a .git/shallow appearing would break it).
expect_sub "single-root fixture: not shallow and no .git/shallow" \
    "shallowrepo=$(git -C "$SR" rev-parse --is-shallow-repository) shallowfile=$([ -f "$SR/.git/shallow" ] && echo yes || echo no)" \
    "shallowrepo=false shallowfile=no"
expect_sub "single-root fixture: exactly one commit" "commits=$(git -C "$SR" rev-list --count HEAD)" "commits=1"

case_run "git-init single-root-commit copy, unresolvable last_commit -> UNVERIFIED, exit 0 (QA-H3-21)" 0 "VERDICT: UNVERIFIED (last_commit provenance unavailable" "$SR/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR"
case_run "single-root copy -> the context line names it history-less, not shallow" 0 "git context — history-less copy: HEAD is a single synthetic root commit" "$SR/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR"
case_run "single-root copy -> A UNVERIFIED line" 0 "A UNVERIFIED — last_commit" "$SR/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR"
case_run "single-root copy -> B/C still run and pass" 0 "C PASS — every tick 1..3" "$SR/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR"
# The board sits at the default RELATIVE path inside the copy, so this arm uses
# that path and D has a committed header to compare (an ABSOLUTE
# H3_BOARD_HEADER_DIR becomes BOARD_REL, which can never match HEAD:<path> —
# the other arms here use absolute dirs and D reports "nothing to compare").
case_run "single-root copy -> D compares the committed header (relative board path)" 0 "D PASS — the working-tree header equals the committed header at HEAD" ".coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR"
case_run "single-root copy -> greppable degraded line" 0 "PUBLIC-HEAD-VERIFY-UNVERIFIED" "$SR/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR"
set +e
SR_OUT=$(env H3_BOARD_HEADER_ROOT="$SR" H3_BOARD_HEADER_RECENT=3 H3_BOARD_HEADER_DIR="$SR/.coding-hermes/board" sh "$GUARD" 2>&1)
set -e
expect_not_sub "single-root copy -> no A FAIL line (degraded, not failed)" "$SR_OUT" "FAIL — A: last_commit"
expect_not_sub "single-root copy -> no hard-FAIL text" "$SR_OUT" "does not resolve to a commit"
expect_not_sub "single-root copy -> no PUBLIC-HEAD-VERIFY-FAIL" "$SR_OUT" "PUBLIC-HEAD-VERIFY-FAIL"
expect_sub "single-root copy -> the verdict names the history-less context" "$SR_OUT" "does not resolve in this history-less single-commit copy"

# The hard-FAIL path is KEPT (criterion 2 of QA-H3-21): once the same copy has
# real history, an unresolvable last_commit is a board defect again.
git -C "$SR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m upstream-history-arrives
case_run "the same copy once real history arrives (2 commits) -> still FAILED" 1 "does not resolve to a commit" "$SR/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR"

# ---- 9h. QA-H3-21: a git init that never committed -------------------------
# The zero-commit end of the same class: an unborn HEAD cannot resolve any hash
# either, so the check cannot run at all — UNVERIFIED, never FAILED.
SR0=$WORK/history-less-no-commit
mkdir -p "$SR0/.coding-hermes/board"
git -C "$SR0" init -q
board_fixture "$SR0/.coding-hermes/board" 3 "$(printf 'd%.0s' $(seq 40))" 3
case_run "git init with no commit at all -> UNVERIFIED, exit 0 (QA-H3-21)" 0 "VERDICT: UNVERIFIED (last_commit provenance unavailable" "$SR0/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR0"
case_run "git init with no commit -> the context line says so" 0 "this repo has NO commits at all" "$SR0/.coding-hermes/board" H3_BOARD_HEADER_ROOT="$SR0"

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
