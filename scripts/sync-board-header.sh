#!/bin/sh
# sync-board-header.sh — the WRITE side of the board-header contract (DF-H3-25).
#
# scripts/check-board-header-consistency.sh is the READ side: it FAILs when the
# header (.coding-hermes/board/board.jsonl line 1) has gone stale. This is the
# writer that makes it fresh again — the step a board-writing tick's closeout
# must run, and the thing that was a best-effort post-push hook until now.
#
# Measured recurrence of the SAME class, five times: ticks #459, #463/#464,
# then #480 AND #481 — the last two skipped the write-back entirely, so a fresh
# public clone at 8b3cbc5 failed `make verify` (header last_commit=125f473 was
# four commits behind, ticks_total=479 while the event log already recorded
# #481). DF-H3-24's guard caught every one of them; a guard catching a class is
# not a fix for the WRITER. Hence this script, and the unconditional closeout
# step that runs it (`make board-close`) before the board commit.
#
# Usage:
#   sh scripts/sync-board-header.sh          # sync the board of this repo
#   make board-close                         # the documented closeout step
#
# What it writes (and nothing else):
#   last_commit = git rev-parse --short HEAD
#   ticks_total = the highest tick number the event log records
#   last_tick   = now, UTC, in the header's existing format (YYYY-MM-DD HH:MM:SS)
#   updated_at  = the same value, when the header carries the field
#
# THE TICK SCAN IS THE GUARD'S OWN READER, VERBATIM. Three shapes exist in
# .coding-hermes/board/events.jsonl and the newest writer uses the third:
#   1. top-level numeric "tick_number"          (the older board writer)
#   2. numeric "tick" inside the JSON-encoded "detail" string
#   3. top-level numeric "tick"                 (the current writer, e.g. the
#      task_complete / judge_verdict rows of tick #481)
# A second, independently-written reader would be free to disagree with the
# guard that checks it — and a writer that understates ticks_total is exactly
# the defect this script exists to remove (the guard would then FAIL B on the
# very write meant to fix it). One reader, one answer, on both sides.
#
# ORDER MATTERS — the documented closeout is:
#   1. append the tick's events (and any board rows) to the board files
#   2. make board-close          <- this script: header names the current HEAD
#   3. git commit the board      <- the commit that carries the synced header
# The header then names the commit the board was written against, which is the
# board commit's parent. That is the strongest state that can exist: a commit
# cannot contain its own hash, so the guard's contract is "last_commit is HEAD
# or HEAD's parent". Syncing AFTER the commit instead leaves an uncommitted
# header edit, which the guard's check D FAILs on until it is committed — so if
# a tick has to commit again after the board commit, re-run this script and
# include the header in that commit.
#
# IDEMPOTENT: when last_commit and ticks_total already say what this run would
# write (and last_tick is present), nothing is written at all — a second run is
# a byte-identical no-op, printed as such. The timestamp therefore advances
# only when the header is actually re-pinned, which is the observed behaviour
# of the fleet's headers (one last_tick value persists across several board
# commits while the pinned commit is unchanged).
#
# WRITE SCOPE: exactly line 1 of board.jsonl. Every other line is copied
# through byte-for-byte (tail -n +2), and the rewrite is proven to have touched
# nothing else before it lands: the old and the new line are normalised (the
# four fields blanked) and must be equal, or the write is refused. The file is
# rewritten in place (cat > board, same inode and mode) and read back checked.
#
# EXIT CODES:
#   0 = written, or already in sync (one-line summary)
#   2 = a board file is missing or unreadable (nothing was written)
#   3 = REFUSED: no git history, no jq, an event log that does not parse, a
#       header that is not a JSON object or lacks last_commit/ticks_total, or a
#       self-check that did not hold. A refusal never writes — a wrong
#       ticks_total is worse than a stale one, because it reads as fresh.
#
# Env overrides (the same two names the guard honours, defaults shown), so a
# caller can point the guard AND this writer at one tree with one setting:
#   H3_BOARD_HEADER_ROOT=            (repo root; defaults to this script's repo)
#   H3_BOARD_HEADER_DIR=.coding-hermes/board   (relative to the root, or absolute)
#
# Dependencies: POSIX sh, coreutils, git, jq. jq is REQUIRED (not degraded):
# this script only ever runs where a board is being written, and writing a
# ticks_total read by a different parser than the guard's is the bug class.
# READ-ONLY outside line 1 of board.jsonl: no git state, no network, no board
# rows, no board caches.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT=${H3_BOARD_HEADER_ROOT:-$ROOT}

BOARD_REL=${H3_BOARD_HEADER_DIR:-.coding-hermes/board}
case $BOARD_REL in
    /*) BOARD_DIR=$BOARD_REL ;;
    *)  BOARD_DIR=$ROOT/$BOARD_REL ;;
esac
BOARD=$BOARD_DIR/board.jsonl
EVENTS=$BOARD_DIR/events.jsonl

NAME=sync-board-header

refuse() {
    echo "$NAME: REFUSED — $1" >&2
    exit "${2:-3}"
}

missing() {
    echo "$NAME: $1" >&2
    exit 2
}

# ---- 1. the board files must exist (exit 2, nothing written) -----------------
[ -d "$BOARD_DIR" ] || missing "board directory is missing: $BOARD_DIR"
[ -f "$BOARD" ] || missing "board header is missing: $BOARD"
[ -f "$EVENTS" ] || missing "event log is missing: $EVENTS (ticks_total cannot be computed)"
[ -r "$BOARD" ] || missing "board header is not readable: $BOARD"
[ -r "$EVENTS" ] || missing "event log is not readable: $EVENTS"

# ---- 2. the inputs this writer needs, or a loud REFUSAL ----------------------
command -v git >/dev/null 2>&1 || refuse "git not found on PATH — cannot resolve HEAD"
command -v jq >/dev/null 2>&1 ||
    refuse "jq not found on PATH — refusing to compute ticks_total with a reader other than the guard's"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 ||
    refuse "no git history in $ROOT (tar/archive extraction carries no commits) — there is no HEAD to pin"

NEW_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD) || refuse "git rev-parse --short HEAD failed in $ROOT"

# ---- 3. read the current header ---------------------------------------------
HEADER=$(head -n 1 -- "$BOARD")
printf '%s' "$HEADER" | jq -e 'type == "object"' >/dev/null 2>&1 ||
    refuse "board header line 1 is not a JSON object (source: $BOARD) — refusing to rewrite it"

OLD_TOTAL=$(printf '%s' "$HEADER" | jq -r 'if (.ticks_total|type) == "number" then .ticks_total else empty end')
OLD_COMMIT=$(printf '%s' "$HEADER" | jq -r 'if (.last_commit|type) == "string" then .last_commit else empty end')
OLD_TICK=$(printf '%s' "$HEADER" | jq -r 'if (.last_tick|type) == "string" then .last_tick else empty end')
[ -n "$OLD_TOTAL" ] || refuse "header carries no numeric ticks_total — repair the header first"
[ -n "$OLD_COMMIT" ] || refuse "header carries no string last_commit — repair the header first"

# ---- 4. the tick scan: the guard's reader, verbatim --------------------------
# See the third-shape note in the header comment. Reading a different set of
# shapes than the guard reads is how a writer understates the board.
TICK_RAW=$(mktemp "${TMPDIR:-/tmp}/h3-sync-board-header.XXXXXX") || refuse "mktemp failed"
TICK_TMP=$(mktemp "${TMPDIR:-/tmp}/h3-sync-board-header.XXXXXX") || refuse "mktemp failed"
trap 'rm -f "$TICK_RAW" "$TICK_TMP"' EXIT HUP INT TERM

if ! jq -r '
        if (.tick_number|type) == "number" then .tick_number|tostring
        elif (.tick|type) == "number" then .tick|tostring
        elif (.detail|type) == "string" then ((try (.detail|fromjson) catch null) | if (.tick|type) == "number" then .tick|tostring else empty end)
        else empty end
    ' "$EVENTS" > "$TICK_RAW" 2>/dev/null; then
    refuse "the event log does not parse as JSONL (jq exited non-zero on $EVENTS) — refusing to write a ticks_total from a partial read"
fi
sort -n -u "$TICK_RAW" > "$TICK_TMP"
MAX_TICK=$(tail -n 1 -- "$TICK_TMP" || echo '')
if [ -n "$MAX_TICK" ]; then
    case $MAX_TICK in
        *[!0-9]*) refuse "the highest tick read from the event log is not a number: '$MAX_TICK'" ;;
    esac
fi

if [ -n "$MAX_TICK" ]; then
    NEW_TOTAL=$MAX_TICK
    TOTAL_SOURCE="event log max tick"
else
    # No tick number in the log at all: the guard skips its B/C checks in that
    # case, so there is nothing to reconcile. Leave the field alone rather than
    # inventing a value.
    NEW_TOTAL=$OLD_TOTAL
    TOTAL_SOURCE="no tick number in the event log — left unchanged"
fi

# ---- 5. idempotency: nothing to re-pin, nothing to write --------------------
# The guard reads last_commit = HEAD or HEAD's parent as fresh; this writer
# re-pins to HEAD. Either way, if the two reconcilable fields already agree and
# a timestamp exists, the run is a no-op (so the UTC stamp marks a real re-pin,
# not the clock).
if [ "$NEW_COMMIT" = "$OLD_COMMIT" ] && [ "$NEW_TOTAL" = "$OLD_TOTAL" ] && [ -n "$OLD_TICK" ]; then
    echo "$NAME: OK — already in sync: board=$BOARD_REL last_commit=$NEW_COMMIT ticks_total=$NEW_TOTAL (nothing written; re-run is a no-op)"
    exit 0
fi

# ---- 6. build the new line: only these four fields may change ---------------
NOW=$(date -u '+%Y-%m-%d %H:%M:%S')
NEW_HEADER=$(printf '%s\n' "$HEADER" | sed -E \
    -e "s/(\"ticks_total\"[[:space:]]*:[[:space:]]*)[0-9]+/\1$NEW_TOTAL/" \
    -e "s/(\"last_commit\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1$NEW_COMMIT\2/" \
    -e "s/(\"last_tick\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1$NOW\2/" \
    -e "s/(\"updated_at\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\1$NOW\2/")

# the same normalisation applied to both sides: the fields blanked out, the
# rest of the line — key order, spacing, quoting, any foreign field — compared
normalise() {
    printf '%s\n' "$1" | sed -E \
        -e 's/("ticks_total"[[:space:]]*:[[:space:]]*)[0-9]+/\1X/' \
        -e 's/("last_commit"[[:space:]]*:[[:space:]]*")[^"]*(")/\1X\2/' \
        -e 's/("last_tick"[[:space:]]*:[[:space:]]*")[^"]*(")/\1X\2/' \
        -e 's/("updated_at"[[:space:]]*:[[:space:]]*")[^"]*(")/\1X\2/'
}

printf '%s' "$NEW_HEADER" | jq -e 'type == "object"' >/dev/null 2>&1 ||
    refuse "the rewritten header would not be a JSON object — refusing to write"
[ "$(printf '%s' "$NEW_HEADER" | jq -r '.ticks_total')" = "$NEW_TOTAL" ] ||
    refuse "the rewritten header does not carry ticks_total=$NEW_TOTAL — refusing to write"
[ "$(printf '%s' "$NEW_HEADER" | jq -r '.last_commit')" = "$NEW_COMMIT" ] ||
    refuse "the rewritten header does not carry last_commit=$NEW_COMMIT — refusing to write"
[ "$(printf '%s' "$NEW_HEADER" | jq -r '.last_tick // empty')" = "$NOW" ] ||
    refuse "the rewritten header does not carry last_tick=$NOW — refusing to write"
[ "$(normalise "$HEADER")" = "$(normalise "$NEW_HEADER")" ] ||
    refuse "the rewrite would change a byte outside ticks_total/last_commit/last_tick/updated_at — refusing to write"

# ---- 7. write line 1 in place, byte-preserving every other line --------------
OTHER_LINES=$(awk 'END { print (NR > 0 ? NR - 1 : 0) }' "$BOARD")
TMP=$(mktemp "${TMPDIR:-/tmp}/h3-sync-board-header.XXXXXX") || refuse "mktemp failed"
{ printf '%s\n' "$NEW_HEADER"; tail -n +2 -- "$BOARD"; } > "$TMP" ||
    refuse "could not build the rewritten board (temp file: $TMP)"
# in place: same inode, same mode, so a reader holding the file sees the update
cat -- "$TMP" > "$BOARD" || refuse "could not write the new header into $BOARD"
rm -f "$TMP"

READBACK=$(head -n 1 -- "$BOARD")
[ "$READBACK" = "$NEW_HEADER" ] ||
    refuse "read-back mismatch: $BOARD line 1 is not the line that was written"

echo "$NAME: OK — board=$BOARD_REL last_commit=$OLD_COMMIT -> $NEW_COMMIT; ticks_total=$OLD_TOTAL -> $NEW_TOTAL ($TOTAL_SOURCE); last_tick=$NOW UTC; 1 header line rewritten, $OTHER_LINES other line(s) byte-preserved — commit the board next (the guard's D check wants the committed header equal to this one, and the commit that carries it is the HEAD this write pins)"
exit 0
