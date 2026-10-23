#!/usr/bin/env bash
# install-board-close-hook-selftest.sh — QA-H3-22-R2 regression proof.
#
# The defect: install-board-close-hook.sh wrote $repo/.git/hooks/pre-commit
# unconditionally, so on any host with core.hooksPath set the block was
# installed into a directory git never reads — "installed OK", never ran, and
# the stale-header class recurred eight times.
#
# This battery proves, in throwaway clones (never the live tree):
#
#   1  unset core.hooksPath          -> installs in .git/hooks
#   2  absolute core.hooksPath       -> installs THERE, and NOT in .git/hooks
#   3  relative core.hooksPath       -> resolved against the repo toplevel
#   4  linked worktree               -> resolved through the COMMON git dir
#   5  an existing hook is preserved, the block lands BEFORE its final exit
#   6  idempotent re-run             -> no-op, byte-identical hook
#   7  a dead copy in .git/hooks is reported (the recurrence's fingerprint)
#   8  refuses to install when scripts/pre-commit-board-close.sh is absent
#   9  the block is INERT in a repo that does not carry the script (shared dir)
#  10  RED/GREEN on a real board commit, host hooksPath set:
#        RED   - no hook in the resolved dir: the commit succeeds and leaves
#                the header stale (the defect, reproduced)
#        GREEN - block installed in the resolved dir: the same commit leaves
#                last_commit == the commit's PARENT sha (the fix, proven)
#  11  REINSTALL-THEN-BOARD-COMMIT (QA-H3-27, the 9th recurrence): the block is
#      installed, then a gitreins-style hook install OVERWRITES the resolved
#      pre-commit from its own template and the block is gone. Proves
#        a  the reinstall removes the block (the fingerprint)
#        b  the probe fails LOUDLY and names the remedy (--check, exit 1)
#        c  RED - a board commit while the block is missing leaves the header
#                stale: the recurrence, reproduced end to end
#        d  the close-out path (ensure-board-close-hook.sh) reasserts the block
#           WITHOUT clobbering the foreign hook, before the header write-back
#        e  GREEN - the next board commit re-pins the header to its parent
#      Installing once is a one-shot; this arm is what makes the battery see
#      the difference between "installed" and "still installed".
#
# Run: bash scripts/install-board-close-hook-selftest.sh
set -u

# Isolate git config: the host's global core.hooksPath must not choose where
# these tests install, and the host's global hooks (the gitreins guard) must not
# run during scratch commits.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO="$(CDPATH= cd -- "$HERE/.." && pwd)"
# H3_INSTALLER_UNDER_TEST exists for the negative control: run this battery
# against a pre-fix installer and watch it FAIL (the battery must be able to
# see the defect, or it proves nothing).
INSTALLER="${H3_INSTALLER_UNDER_TEST:-$REPO/scripts/install-board-close-hook.sh}"
SCRATCH="$(mktemp -d /tmp/h3-hookresolve-selftest.XXXXXX)"
MARK='# >>> board-close managed block (pre-commit-board-close) >>>'
PASS=0
FAIL=0

cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); echo "  ok  $*"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $*"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1 = $3"; else bad "$1: got '$2' want '$3'"; fi; }
neq()  { if [ "$2" != "$3" ]; then ok "$1 (got '$2', not '$3')"; else bad "$1: got '$2', expected it to differ from '$3'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1 (contains: $3)" ;; *) bad "$1 (missing: $3) in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpectedly contains: $3)" ;; *) ok "$1 (does not contain: $3)" ;; esac; }

# new_clone <name> — a clean checkout of this repo with a local identity.
new_clone() {
    local c="$SCRATCH/$1"
    git clone --quiet "$REPO" "$c" || return 1
    git -C "$c" config user.name h3-selftest
    git -C "$c" config user.email selftest@example.invalid
    printf '%s\n' "$c"
}

echo "install-board-close-hook-selftest: repo=$REPO"
echo "  (git config isolated: GIT_CONFIG_GLOBAL=/dev/null)"

# ---------------------------------------------------------------------------
# 1. core.hooksPath unset -> .git/hooks/pre-commit (the legacy shape still works)
# ---------------------------------------------------------------------------
echo "== 1. unset core.hooksPath installs in .git/hooks =="
C1="$(new_clone c1)" || { echo "  FAIL cannot clone"; exit 1; }
[ -z "$(git -C "$C1" config --get core.hooksPath || true)" ] && ok "clone 1 has no core.hooksPath" || bad "clone 1 unexpectedly has core.hooksPath"
OUT1="$(cd "$C1" && bash "$INSTALLER" 2>&1)"; RC1=$?
eq "1 installer exit" "$RC1" 0
has "1 installer reports the resolved dir" "$OUT1" "core.hooksPath=<unset>"
if grep -qF "$MARK" "$C1/.git/hooks/pre-commit" 2>/dev/null; then ok "1 block installed in .git/hooks/pre-commit"; else bad "1 block missing from .git/hooks/pre-commit: $OUT1"; fi
eq "1 resolved dir == git's own resolution" "$(cd "$C1" && git rev-parse --git-path hooks)" ".git/hooks"

# ---------------------------------------------------------------------------
# 2. absolute core.hooksPath -> installed THERE, never in .git/hooks
# ---------------------------------------------------------------------------
echo "== 2. absolute core.hooksPath is honoured =="
C2="$(new_clone c2)" || { echo "  FAIL cannot clone"; exit 1; }
ABS="$SCRATCH/hooks-abs"
git -C "$C2" config core.hooksPath "$ABS"
OUT2="$(cd "$C2" && bash "$INSTALLER" 2>&1)"; RC2=$?
eq "2 installer exit" "$RC2" 0
has "2 installer names the configured hooksPath" "$OUT2" "core.hooksPath=$ABS"
if grep -qF "$MARK" "$ABS/pre-commit" 2>/dev/null; then ok "2 block installed in the configured hooks dir"; else bad "2 block missing from $ABS/pre-commit: $OUT2"; fi
if [ -e "$C2/.git/hooks/pre-commit" ]; then bad "2 REGRESSION: a hook was also written to .git/hooks"; else ok "2 nothing written to .git/hooks (the old defect)"; fi

# ---------------------------------------------------------------------------
# 3. relative core.hooksPath -> resolved against the repo toplevel
# ---------------------------------------------------------------------------
echo "== 3. relative core.hooksPath resolves under the repo root =="
C3="$(new_clone c3)" || { echo "  FAIL cannot clone"; exit 1; }
git -C "$C3" config core.hooksPath .githooks
OUT3="$(cd "$C3" && bash "$INSTALLER" 2>&1)"; RC3=$?
eq "3 installer exit" "$RC3" 0
if grep -qF "$MARK" "$C3/.githooks/pre-commit" 2>/dev/null; then ok "3 block installed at <repo>/.githooks/pre-commit"; else bad "3 block missing from <repo>/.githooks/pre-commit: $OUT3"; fi

# ---------------------------------------------------------------------------
# 4. linked worktree -> common git dir (a worktree has no hooks of its own)
# ---------------------------------------------------------------------------
echo "== 4. linked worktree resolves through the common git dir =="
C4="$(new_clone c4)" || { echo "  FAIL cannot clone"; exit 1; }
git -C "$C4" worktree add -q "$SCRATCH/wt4" 2>/dev/null || bad "4 could not create a worktree"
OUT4="$(cd "$SCRATCH/wt4" && bash "$INSTALLER" 2>&1)"; RC4=$?
eq "4 installer exit in the worktree" "$RC4" 0
if grep -qF "$MARK" "$C4/.git/hooks/pre-commit" 2>/dev/null; then ok "4 block installed in the COMMON .git/hooks"; else bad "4 block missing from the common .git/hooks: $OUT4"; fi
if [ -e "$C4/.git/worktrees/wt4/hooks/pre-commit" ]; then bad "4 wrote into the per-worktree git dir (git never reads it)"; else ok "4 nothing written into .git/worktrees/wt4/hooks"; fi

# ---------------------------------------------------------------------------
# 5. an existing hook survives; the block lands BEFORE the final exit
# ---------------------------------------------------------------------------
echo "== 5. existing hook content preserved, block before the final exit =="
C5="$(new_clone c5)" || { echo "  FAIL cannot clone"; exit 1; }
PRES="$SCRATCH/hooks-preserve"
mkdir -p "$PRES"
cat > "$PRES/pre-commit" <<'EOF'
#!/bin/sh
# EXISTING-BLOCK-SENTINEL: another tool owns this line
echo existing-guard >&2
exit 7
EOF
chmod +x "$PRES/pre-commit"
git -C "$C5" config core.hooksPath "$PRES"
OUT5="$(cd "$C5" && bash "$INSTALLER" 2>&1)"; RC5=$?
eq "5 installer exit" "$RC5" 0
has "5 reports insertion before the final statement" "$OUT5" "block inserted before the final statement"
if grep -q 'EXISTING-BLOCK-SENTINEL' "$PRES/pre-commit"; then ok "5 pre-existing hook content preserved"; else bad "5 pre-existing content was clobbered"; fi
has "5 final exit preserved" "$(cat "$PRES/pre-commit")" "exit 7"
mark_line="$(grep -nF "$MARK" "$PRES/pre-commit" | cut -d: -f1)"
exit_line="$(grep -n '^exit 7' "$PRES/pre-commit" | cut -d: -f1)"
if [ -n "$mark_line" ] && [ -n "$exit_line" ] && [ "$mark_line" -lt "$exit_line" ]; then ok "5 block line $mark_line precedes exit line $exit_line"; else bad "5 block not before the exit (mark=$mark_line exit=$exit_line)"; fi
if sh -n "$PRES/pre-commit" 2>/dev/null; then ok "5 rewritten hook parses (sh -n)"; else bad "5 rewritten hook does not parse"; fi
[ -x "$PRES/pre-commit" ] && ok "5 rewritten hook executable" || bad "5 rewritten hook not executable"

# ---------------------------------------------------------------------------
# 6. idempotent re-run -> no-op, byte-identical
# ---------------------------------------------------------------------------
echo "== 6. re-run is a no-op =="
BEFORE6="$(sha256sum "$ABS/pre-commit" | awk '{print $1}')"
OUT6="$(cd "$C2" && bash "$INSTALLER" 2>&1)"; RC6=$?
eq "6 re-run exit" "$RC6" 0
has "6 re-run reports no-op" "$OUT6" "already installed"
eq "6 hook byte-identical after re-run" "$(sha256sum "$ABS/pre-commit" | awk '{print $1}')" "$BEFORE6"

# ---------------------------------------------------------------------------
# 7. a dead copy in .git/hooks (while hooksPath points elsewhere) is reported
# ---------------------------------------------------------------------------
echo "== 7. dead copy in .git/hooks is reported =="
mkdir -p "$C2/.git/hooks"
printf '#!/bin/sh\n%s\n' "$MARK" > "$C2/.git/hooks/pre-commit"
chmod +x "$C2/.git/hooks/pre-commit"
OUT7="$(cd "$C2" && bash "$INSTALLER" 2>&1)"
has "7 warns about the dead copy" "$OUT7" "DEAD copy"

# ---------------------------------------------------------------------------
# 8. missing scripts/pre-commit-board-close.sh -> refuse, write nothing
# ---------------------------------------------------------------------------
echo "== 8. refuses when the close script is absent =="
C8="$(new_clone c8)" || { echo "  FAIL cannot clone"; exit 1; }
mv "$C8/scripts/pre-commit-board-close.sh" "$C8/scripts/pre-commit-board-close.sh.gone"
ABS8="$SCRATCH/hooks-refuse"
git -C "$C8" config core.hooksPath "$ABS8"
OUT8="$(cd "$C8" && bash "$INSTALLER" 2>&1)"; RC8=$?
eq "8 exit on a missing close script" "$RC8" 1
has "8 names the missing script" "$OUT8" "pre-commit-board-close.sh not found"
if [ -e "$ABS8/pre-commit" ]; then bad "8 installed a hook anyway"; else ok "8 wrote nothing"; fi

# ---------------------------------------------------------------------------
# 9. inert in a repo without the script (safe to sit in a SHARED hooks dir)
# ---------------------------------------------------------------------------
echo "== 9. block is inert in a repo that does not carry the script =="
OUT9="$(cd "$C8" && sh "$ABS/pre-commit" 2>&1)"; RC9=$?
eq "9 hook exit in a repo without the script" "$RC9" 0
eq "9 hook output in a repo without the script" "$OUT9" ""

# ---------------------------------------------------------------------------
# 10. RED/GREEN on a real board-only commit, host hooksPath set
# ---------------------------------------------------------------------------
echo "== 10. RED/GREEN: a board-only commit re-pins the header =="
# board_commit <clone> <tag> — stage a board-only change with a deliberately
# stale header, commit it, and print "<rc>|<header last_commit>|<parent sha>".
# The commit output (which carries the hook's stderr) goes to $SCRATCH/<tag>.out.
board_commit() {
    local c="$1" tag="$2" stale parent rc
    stale="$(git -C "$c" rev-parse --short HEAD~3)"
    parent="$(git -C "$c" rev-parse --short HEAD)"
    printf '{"id": 90001, "event_type": "selftest", "actor": "selftest", "detail": "hook resolution selftest"}\n' \
        >> "$c/.coding-hermes/board/events.jsonl"
    jq -c --arg c "$stale" '(.last_commit) = $c' "$c/.coding-hermes/board/board.jsonl" > "$SCRATCH/$tag.board.tmp" \
        && mv "$SCRATCH/$tag.board.tmp" "$c/.coding-hermes/board/board.jsonl"
    git -C "$c" add .coding-hermes/board/board.jsonl .coding-hermes/board/events.jsonl
    git -C "$c" commit -m "board: selftest board-only commit" > "$SCRATCH/$tag.out" 2>&1
    rc=$?
    printf '%s|%s|%s\n' "$rc" \
        "$(git -C "$c" show HEAD:.coding-hermes/board/board.jsonl | head -1 | jq -r '.last_commit')" \
        "$parent"
}

# RED: core.hooksPath points at a dir with no hooks — the pre-fix state.
CR="$SCRATCH/c-red"
git clone --quiet "$REPO" "$CR"
git -C "$CR" config user.name h3-selftest; git -C "$CR" config user.email selftest@example.invalid
EMPTY="$SCRATCH/hooks-empty"; mkdir -p "$EMPTY"
git -C "$CR" config core.hooksPath "$EMPTY"
IFS='|' read -r RRED HRED PRED <<EOF
$(board_commit "$CR" red)
EOF
ORED="$(cat "$SCRATCH/red.out")"
eq "10a RED commit exit" "$RRED" 0
hasnt "10a RED: the block did not run (no hook in the resolved dir)" "$ORED" "sync-board-header:"
if [ "$HRED" != "$PRED" ]; then ok "10a RED reproduces the defect: header '$HRED' != parent '$PRED' (stale)"; else bad "10a RED did not reproduce: header == parent ($HRED)"; fi

# GREEN: same clone shape, block installed in the resolved hooks dir.
CG="$SCRATCH/c-green"
git clone --quiet "$REPO" "$CG"
git -C "$CG" config user.name h3-selftest; git -C "$CG" config user.email selftest@example.invalid
GREEN_HOOKS="$SCRATCH/hooks-green"
git -C "$CG" config core.hooksPath "$GREEN_HOOKS"
OUTG="$(cd "$CG" && bash "$INSTALLER" 2>&1)"; RCG=$?
eq "10b GREEN installer exit" "$RCG" 0
has "10b GREEN installer resolved the configured dir" "$OUTG" "core.hooksPath=$GREEN_HOOKS"
IFS='|' read -r RG HG PG <<EOF
$(board_commit "$CG" green)
EOF
OG="$(cat "$SCRATCH/green.out")"
eq "10b GREEN commit exit" "$RG" 0
has "10b GREEN: the block RAN (sync-board-header output)" "$OG" "sync-board-header:"
eq "10b GREEN: committed header last_commit == the commit's parent sha" "$HG" "$PG"
eq "10b GREEN: committed header == worktree header (no dirty header left behind)" \
    "$(git -C "$CG" show HEAD:.coding-hermes/board/board.jsonl | head -1)" \
    "$(head -1 "$CG/.coding-hermes/board/board.jsonl")"

# ---------------------------------------------------------------------------
# 11. a gitreins hook REINSTALL does not defeat the close-out (QA-H3-27)
# ---------------------------------------------------------------------------
# The 9th recurrence: the block was installed correctly (arm 10 GREEN proves it
# works when present), then the gitreins hook install REWROTE the resolved
# shared hook from its own template and the block vanished. The next two board
# commits on Oct 23 (1b6f49f, 4bd9265) ran with no block, so the header went six
# commits stale and a fresh public clone failed `make verify`. Installing once is
# a one-shot. This arm reproduces that reinstall, proves the header goes stale
# WITHOUT the close-out repair (RED), and proves the close-out path
# (scripts/ensure-board-close-hook.sh, which `make board-close` runs) puts the
# block back and that the NEXT board commit re-pins the header (GREEN).
echo "== 11. reinstall-then-board-commit: the block survives a hook rewrite =="

# reinstall_gitreins_hook <dir> — overwrite the pre-commit the way `gitreins
# install` does: one heredoc, the whole file, no trace of anyone else's block
# (shape copied from the live 664-byte hook in /var/tmp/foreign-hooks). The
# guard command is a stand-in: this battery is offline and must never run the
# fleet's real guard.
reinstall_gitreins_hook() {
    cat > "$1/pre-commit" <<'EOF'
#!/usr/bin/env bash
# GitReins pre-commit hook — runs Tier 1 guards on staged changes.
# GITREINS-REINSTALL-SENTINEL: this file is OURS; a reinstall rewrites it whole.
# Skip cleanly if the repo hasn't been initialised with a config.
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [ ! -f "$REPO_ROOT/.gitreins/config.yaml" ]; then
    exit 0
fi

cd "$REPO_ROOT"
# (stand-in for the pinned `gitreins guard --quality-async`)
exit $?
EOF
    chmod +x "$1/pre-commit"
}

C11="$(new_clone c11)" || { echo "  FAIL cannot clone"; exit 1; }
if [ ! -f "$C11/scripts/ensure-board-close-hook.sh" ]; then
    bad "11 the clone does not carry scripts/ensure-board-close-hook.sh (commit it before running this battery)"
    echo "install-board-close-hook-selftest: $PASS passed, $FAIL failed"
    exit 1
fi
HOOKS11="$SCRATCH/hooks-reinstall"
git -C "$C11" config core.hooksPath "$HOOKS11"
OUT11A="$(cd "$C11" && bash "$INSTALLER" 2>&1)"; RC11A=$?
eq "11a installer exit" "$RC11A" 0
if grep -qF "$MARK" "$HOOKS11/pre-commit" 2>/dev/null; then ok "11a block installed in the resolved (shared-shape) hooks dir"; else bad "11a block missing after install: $OUT11A"; fi

# --- the reinstall: the file is replaced wholesale, the block is gone --------
reinstall_gitreins_hook "$HOOKS11"
if grep -qF "$MARK" "$HOOKS11/pre-commit"; then bad "11b the simulated reinstall did NOT remove the block (fixture broken)"; else ok "11b the reinstall removed the managed block (the QA-H3-27 fingerprint)"; fi
has "11b the reinstall kept its own hook content" "$(cat "$HOOKS11/pre-commit")" "GITREINS-REINSTALL-SENTINEL"

# --- the loud half: --check must FAIL and name the remedy -------------------
SHA11R="$(sha256sum "$HOOKS11/pre-commit" | awk '{print $1}')"
OUT11C="$(cd "$C11" && bash scripts/ensure-board-close-hook.sh --check 2>&1)"; RC11C=$?
eq "11c --check exit while the block is missing" "$RC11C" 1
has "11c --check fails loudly, naming the missing block" "$OUT11C" "does NOT carry the board-close managed block"
has "11c --check prints the remedy" "$OUT11C" "Remedy: bash scripts/install-board-close-hook.sh"
eq "11c --check wrote nothing (hook bytes unchanged)" "$(sha256sum "$HOOKS11/pre-commit" | awk '{print $1}')" "$SHA11R"

# The documented opt-out must be loud and must not write: a host whose shared
# hooks dir cannot be touched can decline the repair, but never silently.
OUT11S="$(cd "$C11" && H3_SKIP_HOOK_ENSURE=1 bash scripts/ensure-board-close-hook.sh 2>&1)"; RC11S=$?
eq "11c opt-out (H3_SKIP_HOOK_ENSURE) exit" "$RC11S" 0
has "11c opt-out warns that the close-out is UNGUARDED" "$OUT11S" "UNGUARDED"
has "11c opt-out names the variable so the skip is traceable" "$OUT11S" "H3_SKIP_HOOK_ENSURE is set"
eq "11c opt-out wrote nothing (hook bytes unchanged)" "$(sha256sum "$HOOKS11/pre-commit" | awk '{print $1}')" "$SHA11R"
if grep -qF "$MARK" "$HOOKS11/pre-commit"; then bad "11c opt-out reasserted the block anyway"; else ok "11c opt-out did NOT reassert (it only reports)"; fi

# --- RED control: a board commit while the block is missing goes stale ------
IFS='|' read -r RRED11 HRED11 PRED11 <<EOF
$(board_commit "$C11" red11)
EOF
ORED11="$(cat "$SCRATCH/red11.out")"
eq "11d RED commit exit (the reinstall does not block commits)" "$RRED11" 0
hasnt "11d RED: the block did not run after the reinstall" "$ORED11" "sync-board-header:"
if [ "$HRED11" != "$PRED11" ]; then ok "11d RED reproduces the recurrence: header '$HRED11' != parent '$PRED11' (stale)"; else bad "11d RED did not reproduce: header == parent ($HRED11)"; fi

# --- the close-out path reasserts, without disturbing the foreign hook ------
OUT11E="$(cd "$C11" && bash scripts/ensure-board-close-hook.sh 2>&1)"; RC11E=$?
eq "11e ensure exit" "$RC11E" 0
has "11e ensure reports the block was missing" "$OUT11E" "MISSING"
has "11e ensure reports the reassert" "$OUT11E" "REASSERTED"
if grep -qF "$MARK" "$HOOKS11/pre-commit"; then ok "11e the block is back in the resolved hook"; else bad "11e the block is still missing: $OUT11E"; fi
has "11e the reinstall's own hook content was PRESERVED (additive, not a clobber)" "$(cat "$HOOKS11/pre-commit")" "GITREINS-REINSTALL-SENTINEL"
has "11e the reinstall's guard path was preserved" "$(cat "$HOOKS11/pre-commit")" 'cd "$REPO_ROOT"'
if sh -n "$HOOKS11/pre-commit" 2>/dev/null || bash -n "$HOOKS11/pre-commit" 2>/dev/null; then ok "11e the repaired hook parses"; else bad "11e the repaired hook does not parse"; fi
[ -x "$HOOKS11/pre-commit" ] && ok "11e the repaired hook is executable" || bad "11e the repaired hook is not executable"
mark11="$(grep -nF "$MARK" "$HOOKS11/pre-commit" | cut -d: -f1)"
exit11="$(grep -n 'exit \$?' "$HOOKS11/pre-commit" | tail -n 1 | cut -d: -f1)"
if [ -n "$mark11" ] && [ -n "$exit11" ] && [ "$mark11" -lt "$exit11" ]; then ok "11e block line $mark11 precedes the foreign hook's final exit line $exit11"; else bad "11e block not before the foreign hook's final exit (mark=$mark11 exit=$exit11)"; fi

# idempotent: the ensure step must not rewrite what is already correct
SHA11="$(sha256sum "$HOOKS11/pre-commit" | awk '{print $1}')"
OUT11F="$(cd "$C11" && bash scripts/ensure-board-close-hook.sh 2>&1)"; RC11F=$?
eq "11f ensure re-run exit" "$RC11F" 0
has "11f ensure re-run is a no-op" "$OUT11F" "already present"
eq "11f hook byte-identical after the re-run" "$(sha256sum "$HOOKS11/pre-commit" | awk '{print $1}')" "$SHA11"
OUT11G="$(cd "$C11" && bash scripts/ensure-board-close-hook.sh --check 2>&1)"; RC11G=$?
eq "11g --check exit once repaired" "$RC11G" 0
has "11g --check PASS names the resolved dir" "$OUT11G" "PASS"

# --- GREEN: with the block reasserted, the next board commit re-pins --------
IFS='|' read -r RG11 HG11 PG11 <<EOF
$(board_commit "$C11" green11)
EOF
OG11="$(cat "$SCRATCH/green11.out")"
eq "11h GREEN commit exit after the reinstall+reassert" "$RG11" 0
has "11h GREEN: the restored block RAN" "$OG11" "sync-board-header:"
eq "11h GREEN: committed header last_commit == the commit's parent sha" "$HG11" "$PG11"
eq "11h GREEN: committed header == worktree header" \
    "$(git -C "$C11" show HEAD:.coding-hermes/board/board.jsonl | head -1)" \
    "$(head -1 "$C11/.coding-hermes/board/board.jsonl")"
has "11h the repaired hook still carries the foreign hook's own lines after a real commit" "$(cat "$HOOKS11/pre-commit")" "GITREINS-REINSTALL-SENTINEL"

echo
echo "install-board-close-hook-selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
echo "install-board-close-hook-selftest: ALL PASS"
