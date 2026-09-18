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
#   d. spec arithmetic — the per-category list in specs/05, the region list in
#      specs/25, the report summary block in specs/25 and the six region
#      headings in specs/09 must add up to / agree with the count (a bare JSON
#      integer or a wrong region count slips past a grep)
#   e. PASS summary naming the canonical count
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

# ---- (d) spec count arithmetic --------------------------------------------
# The stale-literal sweep (c) only catches the retired STRINGS ("44/44", ...).
# Two drift shapes slip past it, and BOTH shipped once (tick #355 tier2 judge
# FAIL, verdict d6c849f4):
#   * a JSON count field carrying the old number ("total": 44 / "passed": 44) —
#     a bare integer, so no literal from (c) matches it;
#   * a per-category list that no longer SUMS to the canonical count
#     (edge_cases 10 where the battery has 13 -> the regions summed to 43).
# So: every per-category / per-region list and the report summary block must add
# up / agree.
SPEC05="$ROOT/specs/05-Test-Battery.md"
SPEC25="$ROOT/specs/25-Conformance-Certification.md"
SPEC09="$ROOT/specs/09-Testing-Framework-Architecture.md"

sum_categories_05() {
    awk '/✅/ && !/TOTAL/ {
           if (match($0, /[0-9]+\/[0-9]+/)) {
             s = substr($0, RSTART, RLENGTH); split(s, a, "/"); sum += a[1] + 0
           }
         } END { print sum + 0 }' "$SPEC05"
}

sum_regions_25() {
    awk -F'"total": ' '
         /"(health_protocol|process_flows|decision_types|result_handling|edge_cases|stress)":/ {
           v = $2; gsub(/[^0-9].*/, "", v); sum += v + 0
         } END { print sum + 0 }' "$SPEC25"
}

sum_regions_09() {
    # specs/09 names the same six regions as prose headings of the exact form
    #   ### Region N: <name> (N tests)
    # each followed by a fenced list of test names. Only those headings are
    # summed, so the ASCII tree in §2, the fenced name lists and the report's
    # "TOTAL 46/46" summary line can never leak into the arithmetic.
    # Prints: "<heading-count> <sum> <headings-without-a-count> <region-numbers>".
    awk '
         /^### Region / {
           n++
           num = $3
           sub(/:.*/, "", num)
           nums = nums num
           if (match($0, /\([0-9]+ tests?\)/)) {
             s = substr($0, RSTART, RLENGTH)
             gsub(/[^0-9]/, "", s)
             sum += s + 0
           } else {
             bad++
           }
         }
         END { printf "%d %d %d %s\n", n + 0, sum + 0, bad + 0, nums }' "$SPEC09"
}

spec_sum_ok() {   # $1 file, $2 label, $3 observed sum, $4 optional fix hint
    if [ "$3" != "$CANON" ]; then
        echo "FAIL: $2 sums to $3, but the canonical compliance-test count is $CANON." >&2
        echo "      ${4:-Update the per-category numbers (and any TOTAL row) in $1.}" >&2
        exit 1
    fi
    echo "check-test-count: $2 sums to $CANON"
}

if [ -f "$SPEC05" ]; then
    spec_sum_ok "specs/05-Test-Battery.md" "specs/05 category list" "$(sum_categories_05)"
fi

if [ -f "$SPEC25" ]; then
    spec_sum_ok "specs/25-Conformance-Certification.md" "specs/25 region list" "$(sum_regions_25)"
    SUMMARY=$(sed -n '/"results":/,/"regions":/p' "$SPEC25" | grep -oE '"(total|passed)": *[0-9]+' | grep -oE '[0-9]+' | sort -u || true)
    for v in $SUMMARY; do
        if [ "$v" != "$CANON" ]; then
            echo "FAIL: specs/25 report summary quotes $v, but the canonical count is $CANON." >&2
            exit 1
        fi
    done
    echo "check-test-count: specs/25 report summary agrees with $CANON"
fi

if [ -f "$SPEC09" ]; then
    # word-splitting the helper's single output line is intended here.
    # shellcheck disable=SC2046
    set -- $(sum_regions_09)
    R_COUNT=${1:-0}; R_SUM=${2:-0}; R_BAD=${3:-0}; R_NUMS=${4:-}
    if [ "$R_BAD" -ne 0 ]; then
        echo "FAIL: $R_BAD specs/09 '### Region' heading(s) carry no '(N tests)' count." >&2
        echo "      Expected six headings of the form '### Region N: <name> (N tests)'." >&2
        exit 1
    fi
    if [ "$R_COUNT" -ne 6 ] || [ "$R_NUMS" != "123456" ]; then
        echo "FAIL: specs/09 lists $R_COUNT region heading(s) (region numbers: ${R_NUMS:-none});" >&2
        echo "      expected exactly six — Regions 1..6. The documented per-region split must" >&2
        echo "      stay complete or the sum below is meaningless." >&2
        exit 1
    fi
    spec_sum_ok "specs/09-Testing-Framework-Architecture.md" "specs/09 region list" "$R_SUM" \
        "Fix the six '### Region N: <name> (N tests)' headings in specs/09-Testing-Framework-Architecture.md."
else
    echo "check-test-count: specs/09 not present — region-sum check skipped"
fi

# ---- (e) PASS summary -----------------------------------------------------
echo "check-test-count: PASS — canonical compliance-test count is $CANON; no stale count literals in current-state docs"
exit 0
