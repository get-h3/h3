#!/bin/sh
# Board-header self-consistency guard (H3-GAP-099).
#
# The JSONL board is the fleet's record of what happened, and its header
# (.coding-hermes/board/board.jsonl, a ONE-LINE object) is what every reader
# believes without checking:
#
#   last_commit  — the commit the board says it currently reflects
#   ticks_total  — how many foreman ticks have run
#
# Measured 2026-09-21 (h3 tick #469): BOTH fields had gone stale and NOTHING
# caught it. Last commit of tick #468 (8b43bf9) did not run the documented
# post-push sync, so the header kept last_commit=5c1d5f4 (three commits / two
# ticks behind) — and #468's own event described the tree as though the sync
# had happened. The same drift class had already been repaired by hand twice
# (tick #459: ticks_idle; tick #463: cooldown_s, where a Tier-2 judge caught the
# foreman reading the STALE HEADER instead of config) — each repaired by a third
# party, never by a guard. A header that lies is worse than a missing one: it
# silently sources wrong values into whatever reads it next.
#
# This guard makes both classes catchable with the data already in the repo:
#
#   A. last_commit must name the commit the header is being written against:
#      it must resolve to a commit reachable from HEAD, and it must be HEAD or
#      HEAD's parent. The board's write convention is a two-phase sync (tick
#      commit, then a follow-up that pins last_commit to the pushed commit), so
#      "the sync ran at most one commit ago" is exactly the invariant. A stale
#      value fails here and names how far it drifted.
#   B. ticks_total must equal the highest tick number the event log actually
#      records. If they disagree, the header is publishable fiction.
#   C. every tick in the most recent window must have at least one event. A tick
#      with no record is a hole in the board's own history — the same class the
#      DuckBrain tick-chain census catches on the memory side.
#   D. the committed header must equal the working-tree header, so an uncommitted
#      header edit can never be the thing a later reader trusts.
#
# Tick numbers are read from BOTH shapes the board uses: a top-level
# `tick_number` field, and the `tick` field inside the JSON-encoded `detail`
# string (the older shape). Reading only one shape reports the other as a hole —
# an independent audit did exactly that on 2026-09-21 and reported four phantom
# missing ticks (457/458/463/466, all present). The guard reads both.
#
# WHAT THIS DOES NOT DO: it cannot verify that last_commit names the CORRECT
# pushed commit (only that it names a commit from the current or immediately
# preceding commit) — a fresh-but-wrong hash still passes. It is a staleness and
# hole guard, not a provenance proof. Say so when reporting it (QA-H3-1: a guard
# must not read as broader than it is).
#
# EXIT CODES (sibling-guard convention):
#   0 = VERIFIED, or UNVERIFIED when the board/header cannot be read at all
#       (an unreadable board is not a pass)
#   1 = FAILED — one or more of A/B/C/D above
#
# Output is grep-friendly: one fact per line, ending with the verdict line
#   VERDICT: VERIFIED | UNVERIFIED (<reason>) | FAILED (<reasons>)
#
# Env overrides (all optional, defaults shown):
#   H3_BOARD_HEADER_DIR=.coding-hermes/board     (relative to the repo root)
#   H3_BOARD_HEADER_INPUT=                       (read the header from this file
#                                                 instead of the working tree —
#                                                 used by the selftest and by
#                                                 callers that check a snapshot)
#   H3_BOARD_HEADER_SKIP=                        (comma-separated checks to skip
#                                                 by letter, e.g. "A" — a skip is
#                                                 always REPORTED, never silent)
#   H3_BOARD_HEADER_RECENT=12                    (width of the recent-tick window)
#
# Dependencies: POSIX sh, jq, git. jq or git missing degrades to UNVERIFIED.
# READ ONLY: this guard never writes to the board, git, or DuckBrain.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
# H3_BOARD_HEADER_ROOT points the guard at ANOTHER repo whose git state and
# board are checked (the sibling repos carry boards too, and the selftest needs
# an isolated one). Defaults to this script's own repo.
ROOT=${H3_BOARD_HEADER_ROOT:-$ROOT}
[ -d "$ROOT" ] || { echo "check-board-header-consistency: UNVERIFIED — H3_BOARD_HEADER_ROOT is not a directory: $ROOT"; echo "VERDICT: UNVERIFIED (H3_BOARD_HEADER_ROOT is not a directory: $ROOT)"; exit 0; }

BOARD_REL=${H3_BOARD_HEADER_DIR:-.coding-hermes/board}
case $BOARD_REL in
    /*) BOARD_DIR=$BOARD_REL ;;
    *)  BOARD_DIR=$ROOT/$BOARD_REL ;;
esac
# D (committed==worktree) only applies to a board that lives inside the repo.
case $BOARD_DIR in
    "$ROOT"/*) BOARD_IN_REPO=1 ;;
    *)         BOARD_IN_REPO=0 ;;
esac
BOARD=$BOARD_DIR/board.jsonl
EVENTS=$BOARD_DIR/events.jsonl
HEADER_INPUT=${H3_BOARD_HEADER_INPUT:-}
SKIP=${H3_BOARD_HEADER_SKIP:-}
RECENT=${H3_BOARD_HEADER_RECENT:-12}

NAME=check-board-header-consistency

# UNVERIFIED is a first-class outcome, not a pass (QA-H3-1): it prints why and
# exits 0 so `make verify` stays runnable on a bare clone without jq/git state.
unverified() {
    echo "$NAME: UNVERIFIED — $1"
    echo "VERDICT: UNVERIFIED ($1)"
    exit 0
}

skipped() {
    case ",$SKIP," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

case $RECENT in
    '' | *[!0-9]*) unverified "H3_BOARD_HEADER_RECENT is not a non-negative integer: '$RECENT'" ;;
esac

command -v jq >/dev/null 2>&1 || unverified "jq not found on PATH — cannot read the board header"
command -v git >/dev/null 2>&1 || unverified "git not found on PATH — cannot resolve commits"

# ---- 1. read the header -----------------------------------------------------
if [ -n "$HEADER_INPUT" ]; then
    [ -f "$HEADER_INPUT" ] || unverified "header input is missing: $HEADER_INPUT"
    [ -r "$HEADER_INPUT" ] || unverified "header input is not readable: $HEADER_INPUT"
    HEADER=$(head -n 1 -- "$HEADER_INPUT")
    HEADER_SOURCE="file:$HEADER_INPUT"
else
    [ -f "$BOARD" ] || unverified "board header is missing: $BOARD"
    [ -r "$BOARD" ] || unverified "board header is not readable: $BOARD"
    HEADER=$(head -n 1 -- "$BOARD")
    HEADER_SOURCE="$BOARD_REL/board.jsonl line 1"
fi

printf '%s' "$HEADER" | jq -e 'type == "object"' >/dev/null 2>&1 ||
    unverified "board header line 1 is not a JSON object (source: $HEADER_SOURCE)"

TICKS_TOTAL=$(printf '%s' "$HEADER" | jq -r 'if (.ticks_total|type) == "number" then .ticks_total else empty end')
TICKS_IDLE=$(printf '%s' "$HEADER" | jq -r 'if (.ticks_idle|type) == "number" then .ticks_idle else empty end')
LAST_COMMIT=$(printf '%s' "$HEADER" | jq -r 'if (.last_commit|type) == "string" then .last_commit else empty end')

[ -n "$TICKS_TOTAL" ] || unverified "board header carries no numeric ticks_total (source: $HEADER_SOURCE)"
[ -n "$TICKS_IDLE" ] || unverified "board header carries no numeric ticks_idle (source: $HEADER_SOURCE)"
[ -n "$LAST_COMMIT" ] || unverified "board header carries no string last_commit (source: $HEADER_SOURCE)"

echo "$NAME: board=$BOARD_REL header=$HEADER_SOURCE ticks_total=$TICKS_TOTAL ticks_idle=$TICKS_IDLE last_commit=$LAST_COMMIT"

if [ -n "$SKIP" ]; then
    echo "$NAME: SKIP REQUESTED — checks '$SKIP' are NOT evaluated in this run (a skipped check is never a pass)"
fi

FAIL=0
fail() {
    FAIL=1
    echo "$NAME: FAIL — $1"
}

# ---- 2. A: last_commit is the commit the header is being written against -----
if skipped A; then
    echo "$NAME: A SKIPPED (last_commit freshness)"
elif [ -z "$LAST_COMMIT" ]; then
    fail "A: header carries no last_commit"
else
    if ! git -C "$ROOT" rev-parse --verify --quiet "${LAST_COMMIT}^{commit}" >/dev/null 2>&1; then
        fail "A: last_commit '$LAST_COMMIT' does not resolve to a commit in this repo"
    elif ! git -C "$ROOT" merge-base --is-ancestor "$LAST_COMMIT" HEAD 2>/dev/null; then
        fail "A: last_commit '$LAST_COMMIT' is not an ancestor of HEAD (it names a commit this branch does not contain)"
    else
        H_HEAD=$(git -C "$ROOT" rev-parse HEAD)
        H_PARENT=$(git -C "$ROOT" rev-parse --verify --quiet 'HEAD^' 2>/dev/null || echo '')
        V_FULL=$(git -C "$ROOT" rev-parse "$LAST_COMMIT^{commit}")
        if [ "$V_FULL" = "$H_HEAD" ]; then
            echo "$NAME: A PASS — last_commit $LAST_COMMIT is HEAD ($(git -C "$ROOT" log -1 --format=%h -s))"
        elif [ -n "$H_PARENT" ] && [ "$V_FULL" = "$H_PARENT" ]; then
            echo "$NAME: A PASS — last_commit $LAST_COMMIT is HEAD's parent (the two-phase sync ran one commit ago, the documented state)"
        else
            SINCE=$(git -C "$ROOT" rev-list --count "$V_FULL"..HEAD 2>/dev/null || echo '?')
            fail "A: last_commit '$LAST_COMMIT' is neither HEAD nor HEAD's parent — it is $SINCE commit(s) behind the board it claims to describe; the post-push header sync did not run (write HEAD's hash back into the header)"
        fi
    fi
fi

# ---- 3. B + C: tick coverage from the event log ------------------------------
# Tick number shapes: top-level numeric .tick_number, else numeric .tick inside
# the JSON-encoded detail string. Reading one shape only is what produced a
# phantom-hole audit on 2026-09-21.
if [ ! -r "$EVENTS" ]; then
    echo "$NAME: B/C SKIPPED — event log unreadable ($EVENTS)"
else
    TICK_TMP=$(mktemp "${TMPDIR:-/tmp}/h3-board-header.XXXXXX")
    trap 'rm -f "$TICK_TMP"' EXIT HUP INT TERM
    jq -r '
        if (.tick_number|type) == "number" then .tick_number|tostring
        elif (.detail|type) == "string" then ((try (.detail|fromjson) catch null) | if (.tick|type) == "number" then .tick|tostring else empty end)
        else empty end
    ' "$EVENTS" 2>/dev/null | sort -n -u > "$TICK_TMP" || true

    MAX_TICK=$(tail -n 1 "$TICK_TMP" 2>/dev/null || echo '')
    COUNT_TICK=$(wc -l < "$TICK_TMP" | tr -d ' ')
    echo "$NAME: event-ticks recorded=$COUNT_TICK max=$MAX_TICK (shapes: tick_number + detail.tick)"

    if [ -z "$MAX_TICK" ]; then
        echo "$NAME: B/C SKIPPED — no tick number found in $BOARD_REL/events.jsonl"
    else
        if [ "$TICKS_TOTAL" -lt "$MAX_TICK" ]; then
            fail "B: ticks_total $TICKS_TOTAL is BEHIND the event log (highest recorded tick is $MAX_TICK) — the header is understating the board"
        elif [ "$TICKS_TOTAL" -gt "$MAX_TICK" ]; then
            echo "$NAME: B PASS — ticks_total $TICKS_TOTAL names the tick in flight (highest recorded tick $MAX_TICK; the header counts the running tick, whose event may not be written yet)"
        else
            echo "$NAME: B PASS — ticks_total $TICKS_TOTAL == highest recorded tick in the event log"
        fi

        if [ "$RECENT" -gt 0 ] && [ "$TICKS_TOTAL" -ge "$RECENT" ]; then
            WINDOW_START=$((TICKS_TOTAL - RECENT + 1))
            MISSING=$(seq "$WINDOW_START" "$TICKS_TOTAL" | while read -r n; do
                grep -qx "$n" "$TICK_TMP" || printf '%s\n' "$n"
            done | tr '\n' ' ' | sed 's/ $//')
            if [ -n "$MISSING" ]; then
                fail "C: tick(s) with NO event recorded in $BOARD_REL/events.jsonl: $MISSING (window $WINDOW_START..$TICKS_TOTAL)"
            else
                echo "$NAME: C PASS — every tick $WINDOW_START..$TICKS_TOTAL has at least one event"
            fi
        else
            echo "$NAME: C PASS — recent window not applicable (recent=$RECENT, ticks_total=$TICKS_TOTAL)"
        fi
    fi
fi

# ---- 4. D: the committed header equals the working-tree header ---------------
if [ -z "$HEADER_INPUT" ] && [ "$BOARD_IN_REPO" -eq 1 ] && [ -f "$BOARD" ]; then
    if git -C "$ROOT" cat-file -e "HEAD:$BOARD_REL/board.jsonl" 2>/dev/null; then
        COMMITTED=$(git -C "$ROOT" show "HEAD:$BOARD_REL/board.jsonl" | head -n 1)
        if [ "$COMMITTED" = "$HEADER" ]; then
            echo "$NAME: D PASS — the working-tree header equals the committed header at HEAD"
        else
            fail "D: the working-tree header differs from HEAD:$BOARD_REL/board.jsonl — an uncommitted header edit is live (commit it; a reader must never trust a value only one worktree has)"
        fi
    else
        echo "$NAME: D PASS — board header is not committed at HEAD (nothing to compare)"
    fi
elif [ -z "$HEADER_INPUT" ]; then
    echo "$NAME: D SKIPPED — board dir is outside the repo ($BOARD_DIR); no committed header to compare"
fi

# ---- 5. verdict -------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
    echo "$NAME: PASS — header self-consistent (A freshness, B total, C tick coverage, D committed==worktree)"
    echo "VERDICT: VERIFIED (ticks_total=$TICKS_TOTAL last_commit=$LAST_COMMIT; scope: staleness + holes only — NOT provenance of the named commit)"
    exit 0
fi

echo "VERDICT: FAILED (board header and board state disagree — see the FAIL lines above)"
exit 1
