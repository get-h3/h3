#!/usr/bin/env bash
# install-board-close-hook.sh — tracked installer for the QA-H3-22 board-close
# pre-commit block (GitReins H3-QA22-HOOK criterion B).
#
# WHAT IT INSTALLS
# A "# >>> board-close managed block (pre-commit-board-close) >>>" section that
# runs scripts/pre-commit-board-close.sh (which re-pins the board header and
# re-stages it). It is INSERTED BEFORE the hook's final exit statement so it
# actually runs (appending after the last `exit` is dead code — the failure mode
# the Tier-2 verdict e816a5b8 caught in DEPLOY.md's old `cat >> ` recipe).
# Every existing block in the hook is preserved (boardctl board-lint, the
# gitreins guard, anything else).
#
# WHERE IT INSTALLS — THE QA-H3-22-R2 FIX (2026-10-21)
# This installer used to write `$repo/.git/hooks/pre-commit` unconditionally.
# On a host with `core.hooksPath` set (here: the global gitconfig points at
# ~/.hermes/hooks) git NEVER looks in `.git/hooks`, so the block was installed,
# reported OK, and never ran. That generator defect is behind eight recurrences
# of the stale-header class (DF-H3-25, DF-H3-32, QA-H3-18, QA-H3-20, QA-H3-21,
# QA-H3-2026-09-26-001, QA-H3-22, QA-H3-22-R2): every "structural" fix since
# QA-H3-22 was dead code on any host with a hooks path.
#
# The hooks directory is now RESOLVED the way git resolves it:
#
#   git rev-parse --git-path hooks
#
# which honours `core.hooksPath` (absolute or repo-relative) and, in a linked
# worktree, resolves through the COMMON git dir (`.git/worktrees/<name>` holds
# no hooks of its own — its hooks live in the main repo's). A relative
# `core.hooksPath` is resolved against the repo toplevel, which is the directory
# git runs hooks in. Only if that resolution fails does it fall back to
# `$repo/.git/hooks`.
#
# Because the resolved dir may be SHARED by every repo on the host, the managed
# block is deliberately inert outside this project: it looks for
# scripts/pre-commit-board-close.sh at the committing repo's toplevel and does
# nothing at all when that file is absent — no output, no non-zero exit. An
# install into a shared hooks dir therefore cannot change commits in unrelated
# repos.
#
# Idempotent: re-running detects the marker in the RESOLVED hook and exits 0
# without touching the file. It also warns when a stale copy of the block is
# sitting in `.git/hooks/pre-commit` while git is looking somewhere else — that
# dead copy is how this class survived eight fixes.
#
# Usage:   bash scripts/install-board-close-hook.sh
# Verify:  bash scripts/install-board-close-hook-selftest.sh
#          (red/green proof for every resolution shape + a real board commit)
set -euo pipefail

block_start="# >>> board-close managed block (pre-commit-board-close) >>>"
block_end="# <<< board-close managed block <<<"

die() {
    echo "install-board-close: FAIL — $*" >&2
    exit 1
}

note() {
    echo "install-board-close: $*" >&2
}

repo="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git working tree"
[ -n "$repo" ] || die "not inside a git working tree (git rev-parse --show-toplevel returned nothing)"
repo="$(CDPATH= cd -- "$repo" && pwd)" || die "cannot resolve the repo toplevel: $repo"

script="$repo/scripts/pre-commit-board-close.sh"
[ -f "$script" ] || die "scripts/pre-commit-board-close.sh not found in $repo (nothing installed)"

# ---------------------------------------------------------------------------
# 1. Resolve the hooks directory the way git does (core.hooksPath, worktrees).
# ---------------------------------------------------------------------------
hooks_path_cfg="$(git config --get core.hooksPath 2>/dev/null || true)"

raw="$(git rev-parse --git-path hooks 2>/dev/null || true)"
[ -n "$raw" ] || raw=".git/hooks"       # last-resort fallback if --git-path is unavailable

# core.hooksPath may carry a leading ~ (git does not always expand it for us).
case "$raw" in
    '~')   raw="$HOME" ;;
    '~/'*) raw="$HOME/${raw#\~/}" ;;
esac

case "$raw" in
    /*) hooks_dir_raw="$raw" ;;
    *)  hooks_dir_raw="$repo/$raw" ;;   # git runs hooks from the toplevel
esac

# Canonicalise. mkdir -p first: git silently runs NO hooks when the resolved
# directory does not exist, so "the dir is missing" must never read as OK.
mkdir -p "$hooks_dir_raw" || die "cannot create the resolved hooks directory: $hooks_dir_raw"
HOOKS_DIR="$(CDPATH= cd -- "$hooks_dir_raw" && pwd)" || die "cannot resolve the hooks directory: $hooks_dir_raw"
hook="$HOOKS_DIR/pre-commit"

note "resolved hooks dir = $HOOKS_DIR (core.hooksPath=${hooks_path_cfg:-<unset>})"
if [ "$HOOKS_DIR" != "$repo/.git/hooks" ]; then
    note "NOTICE — git resolves hooks outside .git/hooks on this host; the block goes where git actually looks"
fi

# ---------------------------------------------------------------------------
# 2. Warn about a dead copy left behind by the old installer.
# ---------------------------------------------------------------------------
legacy="$repo/.git/hooks/pre-commit"
if [ "$hook" != "$legacy" ] && [ -f "$legacy" ] && grep -qF "$block_start" "$legacy" 2>/dev/null; then
    note "WARN — a DEAD copy of the block sits in $legacy; git ignores that file while core.hooksPath is set"
    note "WARN — that dead copy is the QA-H3-22 recurrence; only $hook runs. Strip the block from $legacy by hand if you want it gone"
fi

# ---------------------------------------------------------------------------
# 3. Create / inspect / back up the resolved hook.
# ---------------------------------------------------------------------------
if [ -e "$hook" ] && [ ! -f "$hook" ]; then
    die "$hook exists and is not a regular file — refusing to write through it"
fi

if [ ! -f "$hook" ]; then
    note "no existing pre-commit in $HOOKS_DIR — creating one"
    printf '#!/bin/sh\n' > "$hook" || die "cannot create $hook"
elif grep -qF "$block_start" "$hook"; then
    note "board-close block already installed in $hook (no-op)"
    if [ ! -x "$hook" ]; then
        chmod +x "$hook" || die "cannot chmod +x $hook"
        note "made the existing hook executable"
    fi
    exit 0
fi

# Back up whatever is already there: when the resolved dir is shared (a
# host-global core.hooksPath) the file is not ours, and a bad chain would cost
# every repo on the machine its pre-commit hook.
if [ -s "$hook" ]; then
    backup="$hook.bak-$(date -u '+%Y%m%dT%H%M%SZ')"
    cp -p "$hook" "$backup" || die "cannot back up $hook to $backup"
    note "backed up the existing hook to $backup"
fi

chmod +x "$hook" || die "cannot chmod +x $hook"

# The managed block. Quoted heredoc: every $ is literal, so the text written
# into the hook is exactly what is written here (no expansion at install time).
BLOCK="$(cat <<'BLOCK_EOF'
# >>> board-close managed block (pre-commit-board-close) >>>
# QA-H3-22 / QA-H3-22-R2: when board files are staged, run this repo's
# scripts/pre-commit-board-close.sh, which re-pins the board.jsonl header
# (last_commit) and re-stages it.
# SILENT SKIP by design: this block may live in a SHARED hooks dir (a
# host-global core.hooksPath), so in a repo that does not carry the script it
# must be invisible — no output, no exit code, no behaviour change.
_bc_repo="$(git rev-parse --show-toplevel 2>/dev/null)"
_bc_status=0
if [ -n "$_bc_repo" ] && [ -f "$_bc_repo/scripts/pre-commit-board-close.sh" ]; then
	bash "$_bc_repo/scripts/pre-commit-board-close.sh" || _bc_status=$?
fi
unset _bc_repo
[ "$_bc_status" -eq 0 ] || exit "$_bc_status"
# <<< board-close managed block <<<
BLOCK_EOF
)"

# ---------------------------------------------------------------------------
# 4. Insert BEFORE the final exit/exec statement (appending after it is dead).
# ---------------------------------------------------------------------------
last_nonblank="$(awk 'NF { n = NR } END { print n + 0 }' "$hook")"
last_line=""
[ "$last_nonblank" -gt 0 ] && last_line="$(sed -n "${last_nonblank}p" "$hook")"

tmp="$(mktemp "$HOOKS_DIR/.pre-commit.board-close.XXXXXX")" || die "cannot create a temp file in $HOOKS_DIR"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

case "$last_line" in
    exit*|exec*)
        {
            [ "$last_nonblank" -gt 1 ] && sed -n "1,$((last_nonblank - 1))p" "$hook"
            printf '%s\n' "$BLOCK"
            sed -n "${last_nonblank},\$p" "$hook"
        } > "$tmp" || die "cannot build the rewritten hook"
        note "block inserted before the final statement (line $last_nonblank)"
        ;;
    *)
        { cat "$hook"; printf '%s\n' "$BLOCK"; } > "$tmp" || die "cannot build the rewritten hook"
        note "block appended (the hook has no final exit/exec statement)"
        ;;
esac

chmod +x "$tmp" || die "cannot chmod +x the staged hook"
mv "$tmp" "$hook" || die "cannot move the rewritten hook into place: $hook"
trap - EXIT HUP INT TERM

# ---------------------------------------------------------------------------
# 5. Post-install verification — never report OK on an unverified install.
# ---------------------------------------------------------------------------
chmod +x "$hook" || die "cannot chmod +x $hook"

grep -qF "$block_start" "$hook" || die "the block is not in $hook after the rewrite"
grep -qF "$block_end" "$hook" || die "the block's end marker is not in $hook after the rewrite"

start_line="$(grep -nF "$block_start" "$hook" | head -n 1 | cut -d: -f1)"
exit_line="$(grep -n '^[[:space:]]*exit' "$hook" | tail -n 1 | cut -d: -f1 || true)"
if [ -n "${exit_line:-}" ] && [ "$start_line" -gt "$exit_line" ]; then
    die "the block landed after the final exit statement (line $exit_line); the hook would never run it"
fi

case "$(head -n 1 "$hook")" in
    *bash*) bash -n "$hook" || die "$hook does not parse (bash -n)" ;;
    *)      sh -n "$hook" 2>/dev/null || bash -n "$hook" || die "$hook does not parse" ;;
esac

[ -x "$hook" ] || die "$hook is not executable, so git would skip it"

echo "install-board-close: OK — $hook carries the board-close block (block line $start_line${exit_line:+, final exit line $exit_line}); hooks resolved via core.hooksPath=${hooks_path_cfg:-<unset>}"
echo "install-board-close: verify with: bash scripts/install-board-close-hook-selftest.sh"
