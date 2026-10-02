#!/usr/bin/env bash
# install-board-close-hook.sh — tracked installer for the QA-H3-22 board-close
# pre-commit block (GitReins H3-QA22-HOOK criterion B).
#
# Installs a "# >>> board-close managed block (pre-commit-board-close) >>>"
# section into .git/hooks/pre-commit, INSERTED BEFORE the hook's final exit
# statement so it actually runs (appending after the last `exit` is dead code —
# the failure mode the Tier-2 verdict e816a5b8 caught in DEPLOY.md's old
# `cat >> ` recipe). Preserves every existing block (boardctl board-lint etc.).
#
# Idempotent: re-running detects the marker and exits 0 without changes.
#
# Usage:   bash scripts/install-board-close-hook.sh
# Verify:  bash scripts/pre-commit-board-close-selftest.sh
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
hook="$repo/.git/hooks/pre-commit"
block_start="# >>> board-close managed block (pre-commit-board-close) >>>"
block_end="# <<< board-close managed block <<<"

if [ ! -f "$repo/scripts/pre-commit-board-close.sh" ]; then
    echo "install-board-close: FAIL — scripts/pre-commit-board-close.sh not found" >&2
    exit 1
fi

if [ ! -f "$hook" ]; then
    echo "install-board-close: no existing pre-commit hook — creating one" >&2
    printf '#!/bin/sh\n' > "$hook"
fi

if grep -qF "$block_start" "$hook"; then
    echo "install-board-close: board-close block already installed in .git/hooks/pre-commit (no-op)"
    exit 0
fi

chmod +x "$hook"

BLOCK='# >>> board-close managed block (pre-commit-board-close) >>>
# QA-H3-22: auto-run scripts/pre-commit-board-close.sh when board files are
# staged, re-pinning the board.jsonl header (last_commit) and re-staging it.
# Skips cleanly if the script is missing or not executable.
_bc_repo="$(git rev-parse --show-toplevel 2>/dev/null)" && _bc_script="$_bc_repo/scripts/pre-commit-board-close.sh"
if [ -f "$_bc_script" ]; then
	bash "$_bc_script" || exit 1
else
	echo "board-close: skipped (scripts/pre-commit-board-close.sh not present)" >&2
fi
unset _bc_script _bc_repo
# <<< board-close managed block <<<'

# Insert BEFORE the last line if it is an exit statement (boardctl epilogue
# ends the hook with `exit "$boardctl_lint_existing_status"`); otherwise append.
last_line="$(tail -n 1 "$hook")"
case "$last_line" in
    exit*)
        tmp="$(mktemp)"
        head -n -1 "$hook" > "$tmp"
        printf '%s\n' "$BLOCK" >> "$tmp"
        printf '%s\n' "$last_line" >> "$tmp"
        mv "$tmp" "$hook"
        echo "install-board-close: block inserted before final exit line"
        ;;
    *)
        printf '%s\n' "$BLOCK" >> "$hook"
        echo "install-board-close: block appended to hook"
        ;;
esac

# Post-install sanity: the marker must appear before the last exit line.
if [ "$(grep -nF "$block_start" "$hook" | cut -d: -f1)" -ge "$(grep -n '^exit' "$hook" | tail -1 | cut -d: -f1)" ]; then
    echo "install-board-close: WARNING — block installed after the final exit; hook may never run it" >&2
    exit 1
fi
echo "install-board-close: OK — .git/hooks/pre-commit carries the board-close block"
