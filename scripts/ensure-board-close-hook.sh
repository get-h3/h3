#!/usr/bin/env bash
# ensure-board-close-hook.sh — QA-H3-27: the board-close block must SURVIVE a
# hook reinstall, not merely be installed once.
#
# WHY THIS EXISTS (the 9th recurrence of the stale-header class)
# QA-H3-22-R2 taught install-board-close-hook.sh to resolve the hooks directory
# the way git does (core.hooksPath / worktrees) instead of hardcoding
# .git/hooks. That fix is correct, and it is still not enough: the block lives
# INSIDE a pre-commit file that this project does not own. On this host the
# resolved dir is a SHARED, foreign one (/var/tmp/foreign-hooks, written by the
# gitreins hook install), and a reinstall REWRITES that file from its own
# template — the managed block is gone, silently, while the installer still
# reports nothing (it is not running; nobody re-ran it).
#
# Measured: a fresh public clone at 22bc708 failed `make verify`
# (check-board-header-consistency A: last_commit 8ac9385 was six commits behind,
# PUBLIC-HEAD-VERIFY-FAIL); the two board commits in between (1b6f49f, 4bd9265)
# ran with the block ABSENT from the resolved dir, so no header write-back
# happened. Installing once is a one-shot; a shared hooks file is rewritten by
# whoever else owns it.
#
# WHAT THIS DOES
# Called by `make board-close` BEFORE the header write-back, i.e. at the one
# close-out step a board-writing tick must run. It:
#
#   * resolves the hooks directory exactly as the installer does
#     (`git rev-parse --git-path hooks`, ~ expanded, relative resolved against
#     the toplevel);
#   * reports whether the managed block is there AND the hook is executable
#     (a non-executable hook is a hook git silently skips);
#   * if it is missing, REASSERTS it by running this repo's own tracked
#     installer, then re-verifies the file it wrote;
#   * FAILS LOUDLY (non-zero, with the remedy) if the block cannot be put back —
#     so the close-out stops before a stale header can be committed, instead of
#     leaving the repair to the next failed `make verify` on a fresh clone.
#
# MODES
#   bash scripts/ensure-board-close-hook.sh            # ensure (reassert if missing)
#   bash scripts/ensure-board-close-hook.sh --check    # report only; writes nothing
#
# --check never creates the hooks directory, never touches the shared file, and
# exits 1 when the block is missing: it is the read-only probe a runner or a
# tick can call before deciding to repair.
#
# OPT-OUT (H3_SKIP_HOOK_ENSURE)
# A host whose shared hooks dir must not be touched (it belongs to another tool
# and is not writable, or the operator forbids writes there) can set
# H3_SKIP_HOOK_ENSURE=1. It is handled HERE, not in the Makefile recipe, so the
# recipe stays the documented three: echo, ensure, sync. The opt-out is loud —
# it names the close-out as unguarded — and `--check` ignores it (probing never
# writes, so there is nothing to skip).
#
# SCOPE / SAFETY
# Additive: it never rewrites the foreign hook itself — it delegates to
# scripts/install-board-close-hook.sh, which backs the file up, inserts the
# block BEFORE the final exit statement, preserves every existing block, and
# writes a block that is SILENT in any repo that does not carry
# scripts/pre-commit-board-close.sh (so a shared hooks dir stays inert for
# unrelated repos). This script writes nothing else: no board files, no git
# state, no network.
#
# Exit codes:
#   0 = the resolved hook carries the managed block (already, or after reassert);
#       or this checkout is not an h3 tree (no scripts/pre-commit-board-close.sh)
#       — there is nothing to ensure and nothing to break;
#   1 = the block is missing (--check) or could not be reasserted (ensure).
#
# Usage:
#   bash scripts/ensure-board-close-hook.sh
#   bash scripts/ensure-board-close-hook.sh --check
# Proof: bash scripts/install-board-close-hook-selftest.sh (arm 11:
# reinstall-then-board-commit), or make verify-board-close-hook-selftest.
set -u

block_start="# >>> board-close managed block (pre-commit-board-close) >>>"

NAME=ensure-board-close-hook

die() {
    echo "$NAME: FAIL — $*" >&2
    exit 1
}

note() {
    echo "$NAME: $*" >&2
}

mode="ensure"
case "${1:-}" in
    "")          mode=ensure ;;
    --check|-c)  mode=check ;;
    -h|--help)
        echo "usage: bash scripts/ensure-board-close-hook.sh [--check]"
        echo "  (no argument)  reassert the board-close block in the hooks dir git resolves"
        echo "  --check        report only; exit 1 when the block is missing"
        exit 0
        ;;
    *) die "unknown argument: $1 (use --check, or no argument)" ;;
esac

# Opt-out, ensure mode only: probing (--check) never writes, so there is nothing
# to skip there. Loud on purpose — an unguarded close-out must be visible in the
# tick's own output, not inferred from a later failed fresh-clone verify.
if [ -n "${H3_SKIP_HOOK_ENSURE:-}" ] && [ "$mode" = ensure ]; then
    echo "$NAME: WARNING — H3_SKIP_HOOK_ENSURE is set, so the board-close hook was NOT re-asserted and this close-out is UNGUARDED (QA-H3-27): a reinstalled shared hook leaves board commits with no header write-back. Unset H3_SKIP_HOOK_ENSURE to let the close-out verify and repair the resolved hooks dir." >&2
    exit 0
fi

repo="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git working tree"
[ -n "$repo" ] || die "not inside a git working tree (git rev-parse --show-toplevel returned nothing)"
repo="$(CDPATH= cd -- "$repo" && pwd)" || die "cannot resolve the repo toplevel: $repo"

# Not an h3 checkout: the block is deliberately inert here, so there is nothing
# to ensure. This is the same condition the block itself tests before running.
if [ ! -f "$repo/scripts/pre-commit-board-close.sh" ]; then
    echo "$NAME: SKIP — $repo carries no scripts/pre-commit-board-close.sh (nothing to ensure)"
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Resolve the hooks directory the way git does — identical to the installer.
# ---------------------------------------------------------------------------
hooks_path_cfg="$(git config --get core.hooksPath 2>/dev/null || true)"

raw="$(git rev-parse --git-path hooks 2>/dev/null || true)"
[ -n "$raw" ] || raw=".git/hooks"

case "$raw" in
    '~')   raw="$HOME" ;;
    '~/'*) raw="$HOME/${raw#\~/}" ;;
esac

case "$raw" in
    /*) hooks_dir_raw="$raw" ;;
    *)  hooks_dir_raw="$repo/$raw" ;;   # git runs hooks from the toplevel
esac

# Canonicalise WITHOUT creating anything: --check must not write to the host.
if [ -d "$hooks_dir_raw" ]; then
    HOOKS_DIR="$(CDPATH= cd -- "$hooks_dir_raw" && pwd)" || die "cannot resolve the hooks directory: $hooks_dir_raw"
else
    HOOKS_DIR="$hooks_dir_raw"
fi
hook="$HOOKS_DIR/pre-commit"

where="hooks resolved via core.hooksPath=${hooks_path_cfg:-<unset>} -> $HOOKS_DIR"

# ---------------------------------------------------------------------------
# 2. Does the resolved hook carry the block, and can git actually run it?
# ---------------------------------------------------------------------------
block_state() {
    if [ ! -f "$hook" ]; then
        echo "missing-file"
    elif ! grep -qF "$block_start" "$hook" 2>/dev/null; then
        echo "missing-block"
    elif [ ! -x "$hook" ]; then
        echo "not-executable"
    else
        echo "present"
    fi
}

state="$(block_state)"

case "$mode" in
check)
    case "$state" in
        present)
            echo "$NAME: PASS — $hook carries the board-close managed block ($where)"
            exit 0
            ;;
        missing-file)
            echo "$NAME: FAIL — there is no pre-commit hook in the directory git resolves ($where); board commits get NO header write-back. Remedy: bash scripts/install-board-close-hook.sh" >&2
            exit 1
            ;;
        missing-block)
            echo "$NAME: FAIL — $hook exists but does NOT carry the board-close managed block ($where). This is the QA-H3-27 fingerprint: a hook reinstall rewrote the file from its own template. Board commits get NO header write-back, so the header goes stale and a fresh clone fails make verify (PUBLIC-HEAD-VERIFY-FAIL). Remedy: bash scripts/install-board-close-hook.sh (or make board-close, which reasserts it)" >&2
            exit 1
            ;;
        not-executable)
            echo "$NAME: FAIL — $hook carries the block but is NOT executable, so git skips it ($where). Remedy: chmod +x $hook (or bash scripts/install-board-close-hook.sh)" >&2
            exit 1
            ;;
    esac
    ;;
ensure)
    case "$state" in
        present)
            echo "$NAME: OK — block already present in $hook ($where; nothing written)"
            exit 0
            ;;
    esac

    case "$state" in
        missing-file)  why="no pre-commit exists in the resolved hooks dir" ;;
        missing-block) why="the resolved hook carries no board-close block (a hook reinstall rewrote it)" ;;
        *)             why="the resolved hook is not executable ($state)" ;;
    esac
    note "MISSING — $why ($where)"
    note "reasserting with the tracked installer (this is the QA-H3-27 reinstall case, not a one-off)"

    installer="${H3_INSTALLER_UNDER_TEST:-$repo/scripts/install-board-close-hook.sh}"
    [ -f "$installer" ] || die "the installer is missing: $installer — cannot reassert the block"
    if ! ( cd "$repo" && bash "$installer" ); then
        die "the installer failed; the board-close block is NOT in $hook. Refusing to continue the board close-out — fix the hooks dir first (see the installer output above)"
    fi

    state="$(block_state)"
    [ "$state" = present ] || die "the installer reported success but $hook still reads '$state' ($where) — the block is not live"
    echo "$NAME: REASSERTED — $hook carries the board-close block again ($where)"
    exit 0
    ;;
esac
