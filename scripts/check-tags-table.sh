#!/bin/sh
# check-tags-table.sh — docs/releases.md tag table vs the tags git actually has.
#
# The "## Tags" table in docs/releases.md is on the GitHub Pages publish path
# (pages.yml publishes docs/), so it is PUBLIC. It went stale once: v0.2.0 and
# v0.3.0 were cut+pushed while the table still listed only v0.1.0 (DF-H3-44).
# This guard makes that drift catchable without a human re-reading the page.
#
# Checks (two-directional):
#   a. every tag git reports (git ls-remote --tags origin; peeled ^{} lines
#      dropped) appears in the table;
#   b. every tag row in the table names a tag git actually has;
#   c. origin unreachable  -> degrade honestly to `git tag -l`, note it in the
#      output, and mark the verdict "PASS (local degrade)";
#   c2. degraded AND the local tag set is empty while the table HAS rows ->
#      UNVERIFIED exit 0 (a history-less sync/git-init copy has no tags to
#      compare; ruling every table row phantom here is a false verdict —
#      QA-H3-24). Keep hard FAIL for real local-vs-table drift.
#   c3. $ROOT is not a git work tree at all (fresh-install shape: `git archive
#      HEAD | tar -x` into a plain directory, history-less sync copy) ->
#      UNVERIFIED exit 0. There is no history to enumerate tags from, so the
#      table's rows cannot be ruled phantom — same false-verdict class as (c2).
#   d. misconfigured inputs (docs/releases.md missing, git unusable) -> exit 2.
#
# PASS = the tag set and the table name exactly each other.
#
# Exit codes: 0 = pass or an honest UNVERIFIED degrade, 1 = drift,
#             2 = guard misconfigured (docs/releases.md missing, git unusable).
# Zero dependencies: POSIX sh + git + grep + coreutils (sed/awk/sort/comm).
# No network beyond `git ls-remote`. Selftest: `--selftest` builds a throwaway
# fixture repo and proves both drift directions fail, the clean state passes, and
# every degrade (ls-remote-unreachable local-only tags, history-less empty tag
# set, no git work tree at all) reports honestly instead of failing.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DOC="$ROOT/docs/releases.md"
NAME="check-tags-table"

# Tag-shaped names only: vX.Y.Z (the repo's tag convention). Anything else on
# a ref is not a release tag this table documents.
TAG_RX='v[0-9]+\.[0-9]+\.[0-9]+'

# ---- selftest ---------------------------------------------------------------
if [ "${1:-}" = "--selftest" ]; then
    TMP=$(mktemp -d "${TMPDIR:-/tmp}/h3-tags-selftest.XXXXXX")
    trap 'rm -rf "$TMP"' EXIT INT TERM
    mkdir -p "$TMP/scripts" "$TMP/docs"
    cp "$SCRIPT_DIR/$(basename -- "$0")" "$TMP/scripts/"
    G="$TMP/scripts/$(basename -- "$0")"

    write_table() {   # $1..: tag rows to include
        {
            printf '# Release Guide\n\n## Tags\n\n'
            printf '| Tag | Date | Notes |\n|-----|------|-------|\n'
            for r in "$@"; do printf '%s\n' "$r"; done
            printf '\n## Pin and verify\n'
        } > "$TMP/docs/releases.md"
    }
    R1='| `v0.1.0` | 2026-09-18 | first |'
    R2='| `v0.2.0` | 2026-09-20 | second |'
    R3='| `v0.3.0` | 2026-09-29 | third |'

    # Fixture repo + a local bare "origin" so the ls-remote path is exercised
    # with no network (file transport), then the remote is removed to exercise
    # the honest local degrade.
    git -C "$TMP" init -q
    git -C "$TMP" checkout -q -b main
    git -C "$TMP" -c user.email=g@g -c user.name=g commit -q --allow-empty -m init
    git -C "$TMP" tag -a v0.1.0 -m t1
    git -C "$TMP" tag -a v0.2.0 -m t2
    git -C "$TMP" tag -a v0.3.0 -m t3
    git init -q --bare "$TMP/origin.git"
    git -C "$TMP" remote add origin "$TMP/origin.git"
    git -C "$TMP" push -q origin HEAD:refs/heads/main
    git -C "$TMP" push -q origin --tags

    FAILS=0
    expect() {   # $1 arm label, $2 want-rc, $3 want-grep ('' = any), then the command
        arm=$1; want_rc=$2; want_grep=$3; shift 3
        rc=0; out=$("$@" 2>&1) || rc=$?
        if [ "$rc" -ne "$want_rc" ]; then
            echo "selftest arm $arm: FAIL — exit $rc, wanted $want_rc. Output:" >&2
            printf '%s\n' "$out" | sed 's/^/    /' >&2
            FAILS=$((FAILS + 1))
            return 0
        fi
        if [ -n "$want_grep" ] && ! printf '%s\n' "$out" | grep -qF -- "$want_grep"; then
            echo "selftest arm $arm: FAIL — output lacks '$want_grep'. Output:" >&2
            printf '%s\n' "$out" | sed 's/^/    /' >&2
            FAILS=$((FAILS + 1))
            return 0
        fi
        echo "selftest arm $arm: ok (exit $rc${want_grep:+, says '$want_grep'})"
    }

    # arm 1 — clean state over ls-remote (origin present): plain PASS
    write_table "$R1" "$R2" "$R3"
    expect "1 clean-over-ls-remote" 0 "PASS" sh "$G"

    # arm 2 — drift direction A: git has v0.3.0, the table does not -> exit 1
    write_table "$R1" "$R2"
    expect "2 tag-missing-from-table" 1 "v0.3.0" sh "$G"

    # arm 3 — drift direction B: the table names v9.9.9, git does not -> exit 1
    write_table "$R1" "$R2" "$R3" '| `v9.9.9` | 2026-10-01 | phantom |'
    expect "3 phantom-table-row" 1 "v9.9.9" sh "$G"

    # arm 4 — origin unreachable: honest degrade, still PASS. Both the remote
    # config AND the bare repo must go: with no configured remote git resolves
    # the name `origin` as a PATH and helpfully tries `origin.git`, which would
    # keep serving the tags from disk.
    git -C "$TMP" remote remove origin
    rm -rf "$TMP/origin.git"
    write_table "$R1" "$R2" "$R3"
    expect "4 local-degrade" 0 "PASS (local degrade)" sh "$G"

    # arm 4b — QA-H3-24: history-less copy (no tags at all, no origin) with a
    # populated table must degrade to UNVERIFIED exit 0, NOT a phantom-tag FAIL.
    git -C "$TMP" tag -d v0.1.0 v0.2.0 v0.3.0 >/dev/null
    write_table "$R1" "$R2" "$R3"
    expect "4b no-tags-no-origin" 0 "UNVERIFIED" sh "$G"
    git -C "$TMP" tag -a v0.1.0 -m t1
    git -C "$TMP" tag -a v0.2.0 -m t2
    git -C "$TMP" tag -a v0.3.0 -m t3

    # arm 4c — H3-GAP-100: the fresh-install shape. `git archive HEAD | tar -x`
    # into a plain directory (and every history-less sync copy) leaves a tree
    # with NO .git at all. With a populated table this must degrade to
    # UNVERIFIED exit 0 — NOT `FAIL: <dir> is not a git work tree` exit 2, which
    # is what turned `make verify` into rc=2 on the QA fresh copy.
    rm -rf "$TMP/.git"
    write_table "$R1" "$R2" "$R3"
    expect "4c non-git-tree" 0 "UNVERIFIED — not a git work tree" sh "$G"
    expect "4c non-git-tree names the doc" 0 "cannot enumerate tags to compare against docs/releases.md" sh "$G"

    # arm 4d — same non-git tree with an EMPTY table: still UNVERIFIED, never a
    # PASS the guard cannot back (it cannot enumerate this tree's tags at all).
    write_table
    expect "4d non-git-tree-empty-table" 0 "UNVERIFIED — not a git work tree" sh "$G"

    # arm 5 — misconfigured: docs/releases.md missing -> exit 2. Re-init a .git
    # so this arm exercises the doc-missing path on a git tree (arm 4c consumed
    # the only non-git fixture).
    git -C "$TMP" init -q
    rm "$TMP/docs/releases.md"
    expect "5 missing-releases-md" 2 "" sh "$G"

    if [ "$FAILS" -ne 0 ]; then
        echo "$NAME: SELFTEST FAIL — $FAILS arm(s) failed above" >&2
        exit 1
    fi
    echo "$NAME: SELFTEST PASS — clean passes (ls-remote + local degrade), both drift directions fail, non-git tree reports UNVERIFIED exit 0 (4c/4d), misconfigured exits 2"
    exit 0
fi

# ---- (d) misconfigured inputs ----------------------------------------------
command -v git >/dev/null 2>&1 ||
    { echo "$NAME: FAIL: git not found on PATH" >&2; exit 2; }
[ -f "$DOC" ] ||
    { echo "$NAME: FAIL: docs/releases.md missing: $DOC" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/h3-tags.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# ---- collect the table's tag rows (file:line + name) -------------------------
# Read before the tree check: the not-a-git-work-tree degrade (c3) below reports
# against the table, so the table must be collected while the doc is known good.
TABLE_ROWS=$(awk '
    insec && /^## / { exit }
    /^## Tags/ { insec = 1; next }
    insec && /^\|/ && match($0, /`v[0-9]+\.[0-9]+\.[0-9]+`/) {
        print NR ":" substr($0, RSTART + 1, RLENGTH - 2)
    }
' "$DOC" || true)
printf '%s\n' "$TABLE_ROWS" | sed -n 's/^[0-9][0-9]*://p' | grep -E . | sort -u > "$WORK/table.tags" || true

# ---- (c3) no git work tree at all -> honest UNVERIFIED, never a hard FAIL ----
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # H3-GAP-100: fresh-install shape (`git archive HEAD | tar -x` into a plain
    # directory, a history-less sync copy, an ephemeral sandbox). There is no
    # history in this tree to enumerate tags from, so "the table names tags this
    # copy does not have" is not a finding about the table — it is the guard's
    # own blind spot, and hard-failing make verify here (rc=2) blocks exactly
    # the copies QA runs on. Degrade to UNVERIFIED exit 0 in the same vocabulary
    # as the QA-H3-24 history-less-tag-set degrade (c2).
    N_TABLE=$(wc -l < "$WORK/table.tags" | tr -d ' ')
    echo "$NAME: UNVERIFIED — not a git work tree; cannot enumerate tags to compare against docs/releases.md (docs/releases.md lists $N_TABLE tag row(s); history-less fresh copy?)"
    exit 0
fi

# ---- collect the tag set git reports ----------------------------------------
# Degrade rule: ls-remote must succeed AND actually list tags. When the named
# remote is gone, ls-remote falls back to "all configured remotes" and exits 0
# with EMPTY output — success-with-nothing is not evidence origin was read, so
# an empty listing degrades honestly to local tags too.
DEGRADED=0
if GIT_RAW=$(git -C "$ROOT" ls-remote --tags origin 2>/dev/null) &&
    printf '%s\n' "$GIT_RAW" | grep -q 'refs/tags/'; then
    REMOTE_NOTES='git ls-remote --tags origin'
else
    DEGRADED=1
    REMOTE_NOTES='git tag -l — ls-remote origin unreachable/empty'
    echo "$NAME: NOTE — git ls-remote --tags origin unusable; degrading to local tags"
    GIT_RAW=$(git -C "$ROOT" tag -l 2>/dev/null || true)
fi
if [ "$DEGRADED" -eq 1 ]; then
    printf '%s\n' "$GIT_RAW" | grep -E -- "^$TAG_RX\$" | sort -u > "$WORK/git.tags" || true
else
    # refs/tags/<name> lines only: drop the peeled ^{} companions and anything
    # that is not refs/tags (the --tags listing carries only tags, but stay strict).
    printf '%s\n' "$GIT_RAW" |
        sed -n 's#^[0-9a-f][0-9a-f]*[[:space:]]\{1,\}refs/tags/##p' |
        grep -v -- '\^{}$' |
        grep -E -- "^$TAG_RX\$" |
        sort -u > "$WORK/git.tags" || true
fi

# (the table's tag rows were collected above, before the tree check)
#
# ---- compare both directions --------------------------------------------------
DRIFT=0
if [ "$DEGRADED" -eq 1 ] && [ ! -s "$WORK/git.tags" ] && [ -s "$WORK/table.tags" ]; then
    # QA-H3-24: a network-less fresh copy (tar+git-init sync, ephemeral sandbox)
    # has NO local tags but the table lists the real released ones. There is no
    # tag set to compare against — emit UNVERIFIED (exit 0) instead of a
    # phantom-tag FAIL, matching the board-header guard's UNVERIFIED-degrade
    # vocabulary and the DF-H3-41/46 verdict-census degrade predicates.
    N_TABLE=$(wc -l < "$WORK/table.tags" | tr -d ' ')
    echo "$NAME: UNVERIFIED — origin unreachable/empty AND this copy has no local tags; docs/releases.md lists $N_TABLE tag(s) with nothing to compare against (history-less fresh copy?)"
    exit 0
fi
if [ ! -s "$WORK/git.tags" ] && [ ! -s "$WORK/table.tags" ]; then
    # nothing on either side (fresh fork, no tags yet): consistent, nothing to list
    echo "$NAME: no vX.Y.Z tags in git and no tag rows in docs/releases.md — nothing to verify"
    exit 0
fi
if [ ! -s "$WORK/table.tags" ]; then
    echo "$NAME: FAIL: git has tag(s) but docs/releases.md has no '## Tags' table rows:" >&2
    sed 's/^/  missing from table: /' "$WORK/git.tags" >&2
    echo "      Add a row per tag under '## Tags' (| \`vX.Y.Z\` | YYYY-MM-DD | notes |)." >&2
    DRIFT=1
else
    MISSING=$(comm -23 "$WORK/git.tags" "$WORK/table.tags")
    PHANTOM=$(comm -13 "$WORK/git.tags" "$WORK/table.tags")
    if [ -n "$MISSING" ]; then
        echo "$NAME: FAIL: tag(s) git reports are missing from the docs/releases.md '## Tags' table:" >&2
        printf '%s\n' "$MISSING" | sed 's/^/  missing from table: /' >&2
        echo "      Add a row per tag under '## Tags' (| \`vX.Y.Z\` | YYYY-MM-DD | notes |)." >&2
        DRIFT=1
    fi
    if [ -n "$PHANTOM" ]; then
        echo "$NAME: FAIL: docs/releases.md '## Tags' row(s) name a tag git does not have:" >&2
        printf '%s\n' "$PHANTOM" | while IFS= read -r t; do
            printf '%s\n' "$TABLE_ROWS" | grep -F -- ":$t" |
                sed 's/^/  docs\/releases.md:/; s/:\([^:]*\)$/ names an unknown\/unpushed tag: \1/' || true
        done
        echo "      Cut+push the tag, or fix the row (a pushed tag is never moved — a mistake is a new tag)." >&2
        DRIFT=1
    fi
fi

if [ "$DRIFT" -ne 0 ]; then
    echo "$NAME: FAIL — docs/releases.md tags table and git disagree [$REMOTE_NOTES]" >&2
    exit 1
fi

N=$(wc -l < "$WORK/table.tags" | tr -d ' ')
if [ "$DEGRADED" -eq 1 ]; then
    echo "$NAME: PASS (local degrade) — docs/releases.md tags table matches all $N local tag(s) [$REMOTE_NOTES]"
else
    echo "$NAME: PASS — docs/releases.md tags table matches all $N tag(s) at origin [$REMOTE_NOTES]"
fi
exit 0
