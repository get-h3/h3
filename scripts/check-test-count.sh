#!/bin/sh
# check-test-count.sh — single source for the H3 compliance-test count (GAP-072).
#
# The battery ships 46 tests today. Every current-state doc that quotes the
# number must agree with -> scripts/test-count.txt <- (the ONE place the
# number is written down) and with the battery itself.
#
# Checks:
#   a. read the canonical count from scripts/test-count.txt
#   b. sibling parity  — if ../shim/src/h3_shim/test_battery.py exists, its
#      EXPECTED_TEST_COUNT must equal the canonical count (this is what catches
#      the battery going 46 -> 47 before the docs notice). Override the path
#      with H3_SHIM_BATTERY=<file> when the sibling is not at ../shim (CI checks
#      get-h3/shim out into a subdirectory and points this at it).
#   c. stale-literal sweep — no current-state doc may still advertise the old
#      counts ("44/44", "44 tests", "out of 43", ...); prints file:line for each
#   d. PASS summary naming the canonical count
#
# Exit codes: 0 = pass, 1 = drift, 2 = guard misconfigured (bad/missing inputs).
# Zero dependencies: POSIX sh + coreutils + grep. No venv, no network.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

CANON_FILE="$SCRIPT_DIR/test-count.txt"
[ -f "$CANON_FILE" ] || { echo "FAIL: canonical count file missing: scripts/test-count.txt" >&2; exit 2; }
CANON=$(tr -d ' \t\r\n' < "$CANON_FILE")
case "$CANON" in
    '' | *[!0-9]*) echo "FAIL: scripts/test-count.txt is not a bare number: '$CANON'" >&2; exit 2 ;;
esac

# ---- (b) sibling battery parity -------------------------------------------
BATTERY=${H3_SHIM_BATTERY:-$ROOT/../shim/src/h3_shim/test_battery.py}
if [ -f "$BATTERY" ]; then
    ACTUAL=$(sed -n 's/^[[:space:]]*EXPECTED_TEST_COUNT[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$BATTERY" | head -n 1)
    if [ -z "$ACTUAL" ]; then
        echo "FAIL: could not parse EXPECTED_TEST_COUNT from $BATTERY" >&2
        echo "      The battery moved or renamed the constant — update this guard." >&2
        exit 1
    fi
    if [ "$ACTUAL" != "$CANON" ]; then
        echo "FAIL: sibling battery drift — $BATTERY says EXPECTED_TEST_COUNT=$ACTUAL" >&2
        echo "      but scripts/test-count.txt says $CANON." >&2
        echo "      Fix: decide which is truth, then update scripts/test-count.txt AND every doc below." >&2
        exit 1
    fi
    echo "check-test-count: sibling battery agrees ($ACTUAL tests at $BATTERY)"
else
    echo "check-test-count: sibling shim battery not present — parity check skipped"
fi

# ---- (c) stale-literal sweep over current-state docs ----------------------
# Matches the retired counts only — never a bare "44" (which also occurs in
# dates, ports and durations).
STALE_PATTERN='44/44|44 tests|44 compliance|44-test|out of 43|43 protocol behaviors|43/43'

# Dated, era-correct records: these carry the number that was TRUE when they
# were written (release entries, field reports, audit records, old PRDs) and
# must stay byte-identical. Board/state stores and agent skills are out of
# scope for the same reason.
is_excluded() {
    case "$1" in
        CHANGELOG.md | prd.html | rabbit-hole-prd.html | h3-prd-client.html | docs/status-report.html) return 0 ;;
        docs/dogfood/* | docs/board/* | skills/* | .coding-hermes/* | .gitreins/*) return 0 ;;
        *) return 1 ;;
    esac
}

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    FILES=$(git -C "$ROOT" ls-files | grep -E '\.(md|html|svg)$' || true)
else
    FILES=$(cd "$ROOT" && find . -type f \( -name '*.md' -o -name '*.html' -o -name '*.svg' \) |
        sed 's|^\./||' || true)
fi

HITS=0
for f in $FILES; do
    case "$f" in
        *" "*) echo "FAIL: whitespace in tracked path breaks this scan: '$f'" >&2; exit 2 ;;
    esac
    if is_excluded "$f"; then continue; fi
    if [ ! -f "$ROOT/$f" ]; then continue; fi
    OUT=$(grep -n -E -- "$STALE_PATTERN" "$ROOT/$f" 2>/dev/null || true)
    if [ -n "$OUT" ]; then
        printf '%s\n' "$OUT" | sed "s|^|$f:|"
        N=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
        HITS=$((HITS + N))
    fi
done

if [ "$HITS" -ne 0 ]; then
    echo "FAIL: $HITS stale compliance-test count literal(s) above." >&2
    echo "      The battery ships $CANON tests — replace each hit with $CANON." >&2
    exit 1
fi

# ---- (d) PASS summary -----------------------------------------------------
echo "check-test-count: PASS — canonical compliance-test count is $CANON; no stale count literals in current-state docs"
exit 0
