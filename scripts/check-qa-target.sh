#!/bin/sh
# check-qa-target.sh — fail-closed QA/verification TARGET validator (QA-H3-1).
#
# Usage:
#   sh scripts/check-qa-target.sh [TARGET_DIR]
#
#   TARGET_DIR  candidate checkout to validate. When omitted, this repository
#               is validated, resolved from this script's own location through
#               `git rev-parse --show-toplevel` — never a hardcoded path.
#
# Exit codes (the convention used by the sibling guards):
#   0 = TARGET_DIR exists, is a git work tree, and carries this repo's markers
#   1 = TARGET_DIR is not a valid target for this umbrella:
#       missing / not a directory / not a git work tree / the wrong repository
#   2 = this guard was misused (usage error) — nothing was validated
#
# WHY THIS EXISTS
#   The QA battery for project `h3` was once pointed at /home/kara/h3, which
#   does not exist. `cd` failed, no cells were driven, and the empty result was
#   carried forward as if it were a clean run (board rows QA-H3-1 / QA-H3-10 /
#   QA-H3-11). Project names are NOT paths: the umbrella repos live under
#   get-h3/<repo>, so a lane that derives "/home/<user>/<project>" targets a
#   directory that was never there. An empty / no-cell result is UNVERIFIED —
#   it is never a pass.
#
#   This guard is the pre-flight for anyone about to record QA cells: it makes
#   a phantom or foreign target FAIL LOUDLY and non-zero BEFORE any cell is
#   recorded, instead of degrading into silence that reads as green. It cannot
#   conjure a checkout that does not exist — nothing repo-owned can, which is
#   why the resolution rule in docs/qa-target-contract.md is normative for
#   lane configuration — but a runner holding a candidate directory can settle
#   "is this really the h3 umbrella checkout?" here, in one command.
#
# IT DOES NOT RUN THE SUITE. A validated target is a real checkout, not a
# passing one: `make verify` (docs/consistency), `make verify-roundtrip`
# (cross-language code suite) and `h3-test --endpoint <harness>` (compliance
# battery) are the things that measure the code.
#
# Zero dependencies beyond POSIX sh, coreutils and git — `make verify` already
# requires a git work tree (the commit-message guard inspects HEAD).

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_HINT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# Markers that are present in get-h3/h3 and in none of its sibling repos
# (verified 2026-09-18; `scripts/test-count.txt` is NOT one of them — the shim
# and the SDKs carry their own copy — so it cannot be used for identity).
MARKERS="specs/_index.md integration/roundtrip/roundtrip.sh"

usage() {
    echo "usage: sh scripts/check-qa-target.sh [TARGET_DIR]" >&2
}

if [ "$#" -gt 1 ]; then
    echo "FAIL: at most one TARGET_DIR argument is accepted (got $#)" >&2
    usage
    exit 2
fi

if [ "$#" -eq 1 ]; then
    TARGET=$1
    SOURCE="argument"
else
    TARGET=$REPO_HINT
    SOURCE="default (this repository)"
fi

if [ -z "$TARGET" ]; then
    echo "FAIL: TARGET_DIR is empty — nothing to validate" >&2
    usage
    exit 2
fi

# ---- 1. the path must exist -------------------------------------------------
if [ ! -d "$TARGET" ]; then
    echo "FAIL: QA target does not exist (or is not a directory): $TARGET" >&2
    echo "      source: $SOURCE" >&2
    echo "      A target that does not resolve is UNVERIFIED — an empty, no-cell" >&2
    echo "      QA run on it must never be recorded as a pass." >&2
    echo "      Project names are not paths: resolve the workdir from" >&2
    echo "      ~/.hermes/coding-hermes/scheduler.db, or from the checkout itself." >&2
    echo "      Portable resolution:  git -C <checkout> rev-parse --show-toplevel" >&2
    echo "      Contract + reproducible verification: docs/qa-target-contract.md" >&2
    exit 1
fi

# ---- 2. it must be a git work tree -----------------------------------------
if ! command -v git >/dev/null 2>&1; then
    echo "FAIL: git not found — cannot validate a QA target" >&2
    exit 2
fi

if ! TOP=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null); then
    echo "FAIL: QA target is not a git work tree: $TARGET" >&2
    echo "      source: $SOURCE" >&2
    echo "      A directory that is not a checkout cannot be QA'd: the battery," >&2
    echo "      the round-trip suite and every cell read repository state." >&2
    echo "      Contract + reproducible verification: docs/qa-target-contract.md" >&2
    exit 1
fi

[ -n "$TOP" ] || {
    echo "FAIL: git reported an empty work-tree root for: $TARGET" >&2
    exit 1
}

# ---- 3. a contradicting origin wins the message -----------------------------
# Ordered before the marker check so that a real sibling checkout (whose own
# board exists) is reported as the wrong repo rather than as a marker mismatch.
ORIGIN=$(git -C "$TOP" remote get-url origin 2>/dev/null || true)
case "$ORIGIN" in
    '' ) : ;;
    */protocol | */protocol.git | */shim | */shim.git | */sdk-go | */sdk-go.git | \
    */sdk-python | */sdk-python.git | */sdk-typescript | */sdk-typescript.git)
        echo "FAIL: QA target is a SIBLING repository, not the h3 umbrella: $TOP" >&2
        echo "      origin: $ORIGIN" >&2
        echo "      Each get-h3 repo is its own QA target with its own board; a row" >&2
        echo "      for one project must not be verified against another repo." >&2
        exit 1
        ;;
esac

# ---- 4. it must be THIS repository -----------------------------------------
MISSING=""
for m in $MARKERS; do
    [ -e "$TOP/$m" ] || MISSING="${MISSING} ${m}"
done
if [ -n "$MISSING" ]; then
    echo "FAIL: wrong repository for the h3 umbrella QA target: $TOP" >&2
    echo "      source: $SOURCE" >&2
    echo "      missing h3-only marker(s):${MISSING}" >&2
    echo "      The umbrella QA/verification target is get-h3/h3 (this repo);" >&2
    echo "      protocol, shim and the SDKs are separate targets." >&2
    exit 1
fi

# ---- 5. valid ---------------------------------------------------------------
if [ "$TOP" != "$TARGET" ]; then
    echo "check-qa-target: $TARGET resolved to git work tree $TOP"
fi
if [ -n "$ORIGIN" ]; then
    echo "check-qa-target: origin $ORIGIN"
else
    echo "check-qa-target: no origin remote (snapshot / fresh copy) — identity decided by markers"
fi
echo "check-qa-target: OK — $TOP is a valid QA target (git work tree, umbrella markers present)"
echo "check-qa-target: PASS — record cells against this directory; an empty/no-cell result is UNVERIFIED, never a pass."
exit 0
