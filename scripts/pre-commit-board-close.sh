#!/usr/bin/env bash
# pre-commit-board-close.sh — QA-H3-22 structural fix.
#
# Board-writing ticks kept skipping `make board-close`, so board.jsonl's
# header last_commit went stale behind HEAD and every fresh public clone
# failed `make verify` (PUBLIC-HEAD-VERIFY-FAIL). The guard caught it every
# time; the writer kept forgetting. This hook makes the correction structural:
# when board files are STAGED, re-pin the header to the current HEAD and
# re-stage it before the commit lands.
#
# Usage (from a pre-commit hook, in the repo root):
#   bash scripts/pre-commit-board-close.sh
#
# Exit codes: 0 on all skip/no-op paths; non-zero only if the sync script
# itself fails. Idempotent (sync-board-header.sh no-ops when in sync).
set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
SYNC="$REPO_ROOT/scripts/sync-board-header.sh"

# Skip cleanly when the sync script is missing or not executable.
[ -f "$SYNC" ] && [ -x "$SYNC" ] || { echo "board-close: skipped (scripts/sync-board-header.sh missing or not executable)" >&2; exit 0; }

# Detect staged board files only.
STAGED="$(git diff --cached --name-only -- .coding-hermes/board/board.jsonl .coding-hermes/board/events.jsonl)"
if [ -z "$STAGED" ]; then
    echo "board-close: skipped (no board files staged)" >&2
    exit 0
fi

if sh "$SYNC"; then
    :
else
    echo "board-close: sync-board-header.sh FAILED — commit rejected" >&2
    exit 1
fi

# If the sync rewrote board.jsonl, re-stage the header so the commit carries it.
if git diff --name-only -- .coding-hermes/board/board.jsonl | grep -q .; then
    git add .coding-hermes/board/board.jsonl
    echo "board-close: re-staged .coding-hermes/board/board.jsonl after header re-pin" >&2
fi
exit 0
