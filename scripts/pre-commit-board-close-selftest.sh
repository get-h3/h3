#!/usr/bin/env bash
# pre-commit-board-close-selftest.sh — QA-H3-22.
# Exercises the pre-commit-board-close.sh hook body in an isolated scratch
# clone (never the live tree): staged board file -> header re-pinned and
# re-staged; no board files staged -> no-op exit 0; sync script failure ->
# non-zero exit. Run: bash scripts/pre-commit-board-close-selftest.sh
set -u
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO="$(CDPATH= cd -- "$HERE/.." && pwd)"
HOOK="$REPO/scripts/pre-commit-board-close.sh"
SCRATCH=$(mktemp -d /tmp/h3-precommit-selftest.XXXXXX)
PASS=0; FAIL=0

cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

check() { # check <name> <rc> <expected_rc>
    if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"; else FAIL=$((FAIL+1)); echo "FAIL: $1 (rc=$2 want $3)"; fi
}

git clone --shared --quiet "$REPO" "$SCRATCH/clone"
cp "$HOOK" "$SCRATCH/clone/scripts/"
chmod +x "$SCRATCH/clone/scripts/pre-commit-board-close.sh"
cd "$SCRATCH/clone"

# ---- Test 1: no board files staged -> no-op exit 0 ---------------------------
RC1=$(bash "$HOOK" >/dev/null 2>&1; echo $?)
check "no board files staged -> exit 0" "$RC1" 0

# ---- Test 2: missing sync script -> clean skip, exit 0 -----------------------
mv scripts/sync-board-header.sh scripts/sync-board-header.sh.bak
RC2=$(bash "$HOOK" >/dev/null 2>&1; echo $?)
check "sync script missing -> clean skip exit 0" "$RC2" 0
mv scripts/sync-board-header.sh.bak scripts/sync-board-header.sh

# ---- Test 3: staged board file with stale header -> re-pinned + re-staged ----
OLD=$(git rev-parse --short HEAD~5 2>/dev/null || git rev-parse --short HEAD)
NEW=$(git rev-parse --short HEAD)
jq -c --arg c "$OLD" '(.last_commit) = $c' .coding-hermes/board/board.jsonl > /tmp/h3-st.b.jsonl \
    && mv /tmp/h3-st.b.jsonl .coding-hermes/board/board.jsonl
git add .coding-hermes/board/board.jsonl
OUT3=$(bash "$HOOK" 2>&1); RC3=$?
check "staged board file -> hook exits 0" "$RC3" 0
case "$OUT3" in *"re-staged"*) PASS=$((PASS+1)); echo "PASS: hook reports re-staged board.jsonl";; *) FAIL=$((FAIL+1)); echo "FAIL: no re-staged message in: $OUT3";; esac
STAGED_HDR=$(git show ":.coding-hermes/board/board.jsonl" | head -1)
case "$STAGED_HDR" in *"$NEW"*) PASS=$((PASS+1)); echo "PASS: staged header re-pinned to current HEAD ($NEW)";; *) FAIL=$((FAIL+1)); echo "FAIL: staged header not re-pinned (want $NEW): $STAGED_HDR";; esac
if git diff --quiet -- .coding-hermes/board/board.jsonl; then PASS=$((PASS+1)); echo "PASS: board.jsonl fully re-staged (worktree==index)"; else FAIL=$((FAIL+1)); echo "FAIL: board.jsonl dirty after hook"; fi

# ---- Test 4: sync script failure -> non-zero ---------------------------------
mkdir -p "$SCRATCH/badroot/scripts" "$SCRATCH/badroot/.coding-hermes/board"
cp "$HERE/pre-commit-board-close.sh" "$SCRATCH/badroot/scripts/"
cp "$HERE/sync-board-header.sh" "$SCRATCH/badroot/scripts/"
echo 'not json at all' > "$SCRATCH/badroot/.coding-hermes/board/board.jsonl"
echo '{"tick":1}' > "$SCRATCH/badroot/.coding-hermes/board/events.jsonl"
(cd "$SCRATCH/badroot" && git init -q . && git -c user.email=t@t -c user.name=t add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init \
    && echo 'still not json' > .coding-hermes/board/board.jsonl \
    && git add .coding-hermes/board/board.jsonl \
    && bash scripts/pre-commit-board-close.sh >/dev/null 2>&1); RC4=$?
if [ "$RC4" -ne 0 ]; then PASS=$((PASS+1)); echo "PASS: sync failure -> non-zero exit ($RC4)"; else FAIL=$((FAIL+1)); echo "FAIL: sync failure did not propagate (rc=0)"; fi

echo
echo "pre-commit-board-close selftest: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
