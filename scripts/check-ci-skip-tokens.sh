#!/bin/sh
# check-ci-skip-tokens.sh — reject GitHub workflow-skip directives in commit messages (H3-CI-001).
#
# Why this exists: GitHub matches a workflow-skip directive ANYWHERE in the message
# of the pushed head commit — prose included. The umbrella board commits carried one
# as a habit, so the push-triggered workflows stopped firing: the newest
# push-triggered pages.yml run before 2026-09-18 was 2026-09-08T16:30:39Z (dc96324),
# while the next pushed commit with a clean message (59ecfeb, docs fix, pushed
# 2026-09-18T07:25:23Z) produced a run again — same repo, same workflow files, same
# permissions. The commit message was the only variable.
#
# A board-only commit legitimately produces no run: pages.yml triggers on
# docs/**, specs/**, scripts/** and **.md, roundtrip.yml only on
# integration/roundtrip/**, so .coding-hermes/** is excluded by the workflows'
# paths filters. That is by design. To keep a workflow from running, use its paths
# filter — never a message token.
#
# Checks:
#   a. default              — the message of HEAD carries no skip directive
#   b. --rev <rev>          — same check against another commit
#   c. --message-file <path>— same check against a message file (hooks / testing)
#   d. --audit <range>      — report only: list every offending sha + subject in the
#                             range, always exit 0 (historical audit, kept for ops)
#
# Exit codes: 0 = pass, 1 = a skip directive was found, 2 = guard misconfigured.
# Zero dependencies: POSIX sh + coreutils + grep. No venv, no network.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# THE token list. Both the check and the explainer are built from this ONE variable,
# so they cannot drift apart. Bare phrases; the bracket wrapper and the inner
# spacing tolerance (the form GitHub documents, e.g. "[ ci skip ]") are added by
# the pattern below.
SKIP_TOKENS='skip ci|ci skip|no ci|skip actions|actions skip'
PATTERN="\\[[[:space:]]*($SKIP_TOKENS)[[:space:]]*\\]"

usage() {
    cat <<'EOF'
usage: sh scripts/check-ci-skip-tokens.sh [--rev <git-rev> | --message-file <path> | --audit <rev-range>]

  (no flags)              check the message of HEAD (git log -1 --format=%B)
  --rev <git-rev>         check another commit's message
  --message-file <path>   check a message file instead of git (hook / testability)
  --audit <rev-range>     report only: list offending sha + subject in the range (exit 0)
EOF
}

# Renders the ONE token list as bracketed directives, one per line.
render_token_list() {
    printf '%s\n' "$SKIP_TOKENS" | tr '|' '\n' | while IFS= read -r t; do
        printf '  [%s]\n' "$t"
    done
}

# Hits in a message (stdin): one per line as "<line-no>:<line text>".
hits_in() {
    grep -n -i -E -- "$PATTERN" 2>/dev/null || true
}

# The matched directives themselves (stdin): space-separated, whitespace-collapsed.
tokens_in() {
    grep -o -i -E -- "$PATTERN" 2>/dev/null \
        | tr '\n' ' ' \
        | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//' || true
}

explain() {
    echo
    echo "Why this matters: GitHub matches a workflow-skip directive ANYWHERE in the"
    echo "message of the pushed head commit — prose counts. Tick #355 ended with"
    echo "\"NO [ci skip]: this push carries the docs/badge fix\" and CI was skipped"
    echo "anyway: the token was matched, the words around it were not read."
    echo
    echo "How to keep a workflow from running: use its paths filter"
    echo "(.github/workflows/*.yml -> on: push: paths:). A board-only commit under"
    echo ".coding-hermes/ produces no run because of those filters — by design."
    echo
    echo "Directives rejected (case-insensitive), all read from the one list in this script:"
    render_token_list
}

# Check one message. $1 = label for the report; the message arrives on stdin.
run_check() {
    LABEL=$1
    # Read the message ONCE: a redirected file and a pipe both advance their offset,
    # so a second read (or a second helper hitting the same fd) would see EOF.
    MSG=$(cat)
    HITS=$(printf '%s\n' "$MSG" | hits_in)
    TOKENS=$(printf '%s\n' "$MSG" | tokens_in)

    if [ -z "$HITS" ]; then
        echo "check-ci-skip-tokens: PASS — no workflow-skip directive in the message of $LABEL"
        return 0
    fi

    echo "offending source: $LABEL"
    printf '%s\n' "$HITS" | while IFS= read -r l; do
        printf '  line %s: %s\n' "${l%%:*}" "${l#*:}"
    done
    echo "matched directive(s): $TOKENS"
    explain
    echo "FAIL: the message of $LABEL carries the GitHub workflow-skip directive(s) $TOKENS" >&2
    echo "      — GitHub will skip every push-triggered workflow for the pushed head commit." >&2
    return 1
}

# Report-only sweep. $1 = rev-range.
run_audit() {
    REVS=$(git -C "$ROOT" rev-list --reverse "$1" 2>/dev/null) || {
        echo "FAIL: --audit range not resolvable: $1" >&2
        echo "      Pass a git range, e.g. 59ecfeb~40..59ecfeb" >&2
        exit 2
    }

    COUNT=0
    HITS=0
    for sha in $REVS; do
        COUNT=$((COUNT + 1))
        SHORT=$(git -C "$ROOT" rev-parse --short "$sha")
        SUBJ=$(git -C "$ROOT" log -1 --format=%s "$sha")
        TOKENS=$(git -C "$ROOT" log -1 --format=%B "$sha" | tokens_in)
        if [ -n "$TOKENS" ]; then
            HITS=$((HITS + 1))
            printf 'OFFENDING %s  %s  %s\n' "$SHORT" "$TOKENS" "$SUBJ"
        fi
    done

    echo "check-ci-skip-tokens: audit $1 — $HITS of $COUNT commit(s) carry a workflow-skip directive (report only, exit 0)"
    return 0
}

MODE=rev
REV=HEAD
REV_SET=0
MSGFILE=
RANGE=

while [ $# -gt 0 ]; do
    case "$1" in
        --rev | --message-file | --audit)
            [ $# -ge 2 ] || { echo "FAIL: $1 requires an argument" >&2; usage >&2; exit 2; }
            case "$1" in
                --rev) REV=$2; REV_SET=1 ;;
                --message-file) MSGFILE=$2 ;;
                --audit) RANGE=$2 ;;
            esac
            shift 2
            ;;
        --rev=* | --message-file=* | --audit=*)
            KEY=${1%%=*}
            VAL=${1#*=}
            case "$KEY" in
                --rev) REV=$VAL; REV_SET=1 ;;
                --message-file) MSGFILE=$VAL ;;
                --audit) RANGE=$VAL ;;
            esac
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "FAIL: unknown argument '$1'" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -n "$MSGFILE" ] && [ -n "$RANGE" ]; then
    echo "FAIL: --message-file and --audit cannot be combined" >&2
    exit 2
fi
if [ "$REV_SET" -eq 1 ] && { [ -n "$MSGFILE" ] || [ -n "$RANGE" ]; }; then
    echo "FAIL: --rev cannot be combined with --message-file or --audit" >&2
    exit 2
fi

if [ -n "$MSGFILE" ]; then
    MODE=file
elif [ -n "$RANGE" ]; then
    MODE=audit
fi

if [ "$MODE" = "file" ]; then
    [ -f "$MSGFILE" ] || { echo "FAIL: message file not found: $MSGFILE" >&2; exit 2; }
    RC=0
    run_check "$MSGFILE" < "$MSGFILE" || RC=$?
    exit "$RC"
fi

command -v git >/dev/null 2>&1 || { echo "FAIL: git not found (needed for --rev / --audit)" >&2; exit 2; }
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "FAIL: not a git working tree: $ROOT" >&2
    exit 2
}

if [ "$MODE" = "audit" ]; then
    run_audit "$RANGE"
    exit 0
fi

git -C "$ROOT" rev-parse --verify --quiet "$REV^{commit}" >/dev/null || {
    echo "FAIL: not a commit: $REV" >&2
    exit 2
}
FULL=$(git -C "$ROOT" rev-parse --verify "$REV^{commit}")
SHORT=$(git -C "$ROOT" rev-parse --short "$REV^{commit}")
LABEL="commit $SHORT"
if [ "$REV" != "$SHORT" ] && [ "$REV" != "$FULL" ]; then
    LABEL="commit $SHORT ($REV)"
fi
RC=0
git -C "$ROOT" log -1 --format=%B "$REV^{commit}" | run_check "$LABEL" || RC=$?
exit "$RC"
