#!/bin/sh
# check-json-fences.sh — every ```json fenced block in the tracked markdown must parse (H3-GAP-083).
#
# CAPABILITY LIMIT — read this before trusting a PASS
#   This is a FENCE + PAYLOAD guard. It answers exactly one question: does the text INSIDE
#   each ```json block parse as JSON? It is:
#     * NOT a markdown renderer. It implements only the two fence rules it needs:
#         open  = a line whose first non-space run is >=3 backticks (or tildes) immediately
#                 followed by the info word `json`;
#         close = the next line carrying the SAME fence char, at least as many of them, and
#                 NO info string (CommonMark).
#       A ``` sequence that is not line-initial — e.g. one sitting mid-line inside a JSON
#       string value — is CONTENT, not a fence, and is treated as content here too.
#     * NOT a schema validator. A payload is never checked against protocol/schemas (or any
#       other schema); a block that parses but says nothing true about the protocol PASSes.
#     * NOT a statement about untracked files. Discovery is `git ls-files`, so a foreign
#       store dropped into the working tree (e.g. an untracked namespaces/) is never read.
#
# WHY THIS EXISTS (H3-GAP-083)
#   A board row claimed that the `llm_call` example in specs/02 section 4.2 "is not valid
#   JSON". Extracting that block BY LINE NUMBERS (the ```json at specs/02-Protocol-Specification.md:221
#   through the closing fence at :235) and running json.loads over lines 222-234 returns
#   ["decision","decision_id","llm_call"] — the payload was always valid JSON.
#   What was actually true: that block embedded a Go snippet whose opening ``` sequence sat
#   MID-LINE inside the message-content string, so a naive NON-GREEDY extractor
#   (regex ```json\n(.*?)```) truncated the block at that point, and the truncated text then
#   failed json.loads with "Unterminated string starting at: line 8 column 35". The example
#   is the canonical llm_call payload a harness author copies, so extractor-hostile is a real
#   (small) documentation defect: the fence was made extractor-safe in the same change, and
#   this guard pins the class so it is measured instead of re-argued.
#
#   Four blocks in this repo fail json.loads ON PURPOSE: they abbreviate the payload (`...`)
#   instead of spelling out every member. Abbreviation is a legitimate documentation form, so
#   a failing block whose FAILING LINE carries a documented placeholder token (`...`, `{...}`,
#   `[...]`, `/*`, `*/` — the brace/bracket forms are matched through their `...` substring)
#   is reported `ALLOWED (abbreviated)` and does not fail the guard. Every other failure fails
#   with file:line.
#
# ENGINES
#   python3 (preferred): `python3 -c 'import json,sys;json.load(sys.stdin)'` fed the block.
#   Structural fallback (when python3 is absent): per-line unterminated-string detection plus
#   brace/bracket balance. WEAKER — it cannot see a comma-less `...` member inside an array
#   (python3 can), so it is a floor, not a parser; it announces itself loudly when used.
#   No python3 AND no awk (extraction needs awk), or no usable temp dir: a LOUD `SKIP` line
#   and exit 0 — this repo's other checks are zero-dependency, so a skip must never be silent.
#
# Discovery: README.md, specs/*.md, docs/*.md and docs/**/*.md, tracked only.
#
# Exit codes: 0 = pass (or a loud skip), 1 = at least one block failed, 2 = guard misconfigured.
#
# Modes:
#   (no flags)          scan the repo this script lives in
#   --root <dir>        scan another directory (used by --self-test and negative controls)
#   --self-test         build a temp fixture set — a clean block must PASS, an abbreviated
#                       block must be ALLOWED, an unterminated string must FAIL — assert the
#                       exit codes, print SELF-TEST PASS, remove the fixtures. No network, and
#                       no writes inside the repo.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# Failing-line placeholder tokens. One ERE; a leading `*` is written as `[*]` because a bare
# leading `*` is undefined in POSIX ERE.
PLACEHOLDERS='\.\.\.|/\*|[*]/'

usage() {
    cat <<'EOF'
usage: sh scripts/check-json-fences.sh [--root <dir>] [--self-test]

  (no flags)        validate every ```json block in the tracked markdown of this repo
  --root <dir>      validate another directory instead (fixtures / negative controls)
  --self-test       build temp fixtures and assert this guard's exit codes
EOF
}

# ---------------------------------------------------------------------------------------
# Temp workspace (no mktemp: POSIX sh + coreutils only)
# ---------------------------------------------------------------------------------------
TMP=

make_tmp() {
    TMP=${TMPDIR:-/tmp}/check-json-fences.$$
    rm -rf "$TMP" 2>/dev/null || true
    if ! mkdir -p "$TMP" 2>/dev/null; then
        echo "SKIP: check-json-fences — could not create a temp dir under ${TMPDIR:-/tmp}; guard not run" >&2
        exit 0
    fi
}

clean_tmp() {
    [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
}

# ---------------------------------------------------------------------------------------
# Discovery (git ls-files: untracked trees are never scanned)
# ---------------------------------------------------------------------------------------
list_files() {
    if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$ROOT" ls-files -- 'README.md' 'specs/*.md' 'docs/*.md' 'docs/**/*.md'
        return 0
    fi
    # Fixture mode (not a git work tree): the same file set by glob, so --self-test and a
    # negative-control copy exercise the same discovery rules as the repo run.
    if [ -f "$ROOT/README.md" ]; then printf '%s\n' 'README.md'; fi
    for f in "$ROOT"/specs/*.md; do
        [ -f "$f" ] || continue
        printf 'specs/%s\n' "$(basename "$f")"
    done
    if [ -d "$ROOT/docs" ]; then
        ( cd "$ROOT" && find docs -type f -name '*.md' ) 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------------------
# Extraction: one manifest record per ```json block.
#   record = <file>|<open-line>|<payload-file>|<nested-fence-count>
#   payload lines are written VERBATIM to <payload-file> (payload line 1 == file line open+1)
#   an unclosed block is reported as: UNCLOSED|<file>|<open-line>
# ---------------------------------------------------------------------------------------
write_extract_awk() {
    cat > "$TMP/extract.awk" <<'AWK'
BEGIN { inb = 0; n = 0 }
{
    t = $0
    i = 0
    while (i < 3 && substr(t, 1, 1) == " ") { t = substr(t, 2); i++ }
    ch = substr(t, 1, 1)
    c = 0
    if (ch == "`" || ch == "~") { while (substr(t, c + 1, 1) == ch) c++ }
    if (c >= 3) {
        info = substr(t, c + 1)
        sub(/^[ \t]+/, "", info)
        sub(/[ \t]+$/, "", info)
        if (!inb) {
            if (info == "json") {
                inb = 1
                n++
                start = FNR
                mark = ch
                marklen = c
                nested = 0
                payload = out "/block" n ".txt"
            }
        } else if (ch == mark && c >= marklen && info == "") {
            printf "%s|%d|%s|%d\n", FILENAME, start, payload, nested
            inb = 0
        } else if (info != "") {
            # A line-initial fence WITH an info string never closes a block (CommonMark); it is
            # content. It is almost always an authoring accident inside a JSON payload, so count
            # it and keep the line as payload.
            nested++
            print $0 >> payload
        }
        next
    }
    if (inb) print $0 >> payload
}
END { if (inb) printf "UNCLOSED|%s|%d\n", FILENAME, start }
AWK
}

extract_blocks() {
    : > "$TMP/manifest.txt"
    (
        cd "$ROOT"
        set --
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            [ -f "$f" ] || continue
            set -- "$@" "$f"
        done < "$TMP/files.txt"
        [ "$#" -gt 0 ] || exit 0
        awk -v out="$TMP" -f "$TMP/extract.awk" "$@" >> "$TMP/manifest.txt"
    )
}

# ---------------------------------------------------------------------------------------
# Engines. Both print "<payload-relative-line> <message>" on failure and return 1.
# ---------------------------------------------------------------------------------------
write_structural_awk() {
    cat > "$TMP/structural.awk" <<'AWK'
# Structural fallback payload check: per-line unterminated-string detection + brace/bracket
# balance. NOT a JSON parser (no comma/colon/trailing-token checks) — see the header.
BEGIN { depth = 0; bad = 0 }
{
    instr = 0
    for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (instr) {
            if (c == "\\") { i++; continue }
            if (c == "\"") instr = 0
            continue
        }
        if (c == "\"") { instr = 1; continue }
        if (c == "{" || c == "[") { depth++; continue }
        if (c == "}" || c == "]") {
            depth--
            if (depth < 0 && !bad) { print FNR " unexpected closing bracket '" c "'" ; bad = 1 }
            continue
        }
    }
    if (instr && !bad) { print FNR " unterminated string" ; bad = 1 }
}
END {
    if (!bad && depth != 0) { print FNR " unbalanced braces/brackets (depth " depth ")" ; bad = 1 }
    exit bad ? 1 : 0
}
AWK
}

validate_python3() {
    # The engine is the canonical one-liner; an uncaught JSONDecodeError prints a full
    # traceback, so the machine-readable message is the LAST non-blank stderr line
    # ("json.decoder.JSONDecodeError: Expecting value: line 3 column 5 (char 25)").
    if E=$(python3 -c 'import json,sys;json.load(sys.stdin)' < "$1" 2>&1 >/dev/null); then
        return 0
    fi
    LAST=$(printf '%s\n' "$E" | sed -n '/[^[:space:]]/p' | tail -n 1)
    [ -n "$LAST" ] || LAST='python3 json.load failed with empty stderr'
    L=$(printf '%s\n' "$LAST" | sed -n 's/.*line \([0-9][0-9]*\).*/\1/p' | head -n 1)
    [ -n "$L" ] || L=$(printf '%s\n' "$E" | sed -n 's/.*line \([0-9][0-9]*\).*/\1/p' | head -n 1)
    [ -n "$L" ] || L=0
    MSG=$(printf '%s\n' "$LAST" | sed -e 's/^json\.decoder\.JSONDecodeError: //' -e 's/^[A-Za-z_][A-Za-z0-9_.]*Error: //')
    printf '%s %s\n' "$L" "$MSG"
    return 1
}

validate_structural() {
    if E=$(awk -f "$TMP/structural.awk" "$1" 2>&1); then
        return 0
    fi
    L=${E%% *}
    printf '%s %s\n' "$L" "structural: ${E#* }"
    return 1
}

validate() {
    if [ "$ENGINE" = python3 ]; then
        validate_python3 "$1"
    else
        validate_structural "$1"
    fi
}

# ---------------------------------------------------------------------------------------
# Main run
# ---------------------------------------------------------------------------------------
run_guard() {
    command -v awk >/dev/null 2>&1 || {
        echo "SKIP: check-json-fences — awk not found; fence extraction needs it, guard not run" >&2
        exit 0
    }
    if command -v python3 >/dev/null 2>&1; then
        ENGINE=python3
    else
        ENGINE=structural
        echo "NOTE: check-json-fences — python3 unavailable, using the structural fallback engine." >&2
        echo "      Weaker: it finds unterminated strings and unbalanced braces/brackets only." >&2
        echo "      A comma-less '...' member inside an array is a python3-only catch." >&2
    fi

    list_files | sort -u > "$TMP/files.txt"
    if [ ! -s "$TMP/files.txt" ]; then
        echo "FAIL: check-json-fences — no markdown files discovered under $ROOT (guard misconfigured)" >&2
        exit 2
    fi

    write_extract_awk
    write_structural_awk
    extract_blocks

    TOTAL=0
    ALLOWED=0
    FAILED=0
    while IFS='|' read -r bfile bline payload nested; do
        [ -n "$bfile" ] || continue
        if [ "$bfile" = "UNCLOSED" ]; then
            # UNCLOSED|<file>|<open-line>
            echo "FAIL: check-json-fences — $bline:$payload unclosed \`\`\`json fence (no closing fence found)" >&2
            FAILED=$((FAILED + 1))
            continue
        fi
        [ -n "$payload" ] || continue
        [ -f "$payload" ] || continue
        TOTAL=$((TOTAL + 1))
        if [ "${nested:-0}" -gt 0 ]; then
            echo "NOTE: check-json-fences — $bfile:$bline carries $nested line-initial nested fence(s); they are content per CommonMark but almost always an authoring accident" >&2
        fi
        if ERR=$(validate "$payload" 2>&1); then
            continue
        fi
        L=${ERR%% *}
        MSG=${ERR#* }
        case "$L" in
            ''|*[!0-9]*) L=0 ;;
        esac
        FAILLINE=$bline
        [ "$L" -gt 0 ] && FAILLINE=$((bline + L))
        FAILTEXT=
        [ "$L" -gt 0 ] && FAILTEXT=$(sed -n "${L}p" "$payload")
        if [ "$L" -gt 0 ] && printf '%s\n' "$FAILTEXT" | grep -q -E "$PLACEHOLDERS"; then
            ALLOWED=$((ALLOWED + 1))
            printf 'check-json-fences: ALLOWED (abbreviated) %s:%s — failing line carries a placeholder token\n' "$bfile" "$FAILLINE"
            printf '                   %s\n' "$MSG"
        else
            FAILED=$((FAILED + 1))
            printf 'check-json-fences: FAIL %s:%s — %s\n' "$bfile" "$FAILLINE" "$MSG" >&2
            [ -n "$FAILTEXT" ] && printf '                   %s\n' "$FAILTEXT" >&2
        fi
    done < "$TMP/manifest.txt"

    if [ "$FAILED" -eq 0 ]; then
        printf 'check-json-fences: PASS — %d json blocks scanned, %d allowed (abbreviated), 0 failures\n' "$TOTAL" "$ALLOWED"
        return 0
    fi
    printf 'check-json-fences: FAIL — %d json blocks scanned, %d allowed (abbreviated), %d failures\n' "$TOTAL" "$ALLOWED" "$FAILED" >&2
    return 1
}

# ---------------------------------------------------------------------------------------
# --self-test: fixtures in a temp dir, assert this script's own exit codes
# ---------------------------------------------------------------------------------------
self_test() {
    ST=${TMPDIR:-/tmp}/check-json-fences-selftest.$$
    rm -rf "$ST" 2>/dev/null || true
    mkdir -p "$ST/clean/specs" "$ST/abbreviated/specs" "$ST/broken/specs" || {
        echo "SKIP: check-json-fences --self-test — could not create fixtures under ${TMPDIR:-/tmp}" >&2
        exit 0
    }

    cat > "$ST/clean/specs/sample.md" <<'FIXTURE'
# Clean fixture

```json
{"decision": "text", "text": "hello", "messages": [{"role": "user", "content": "hi"}]}
```
FIXTURE

    cat > "$ST/abbreviated/specs/sample.md" <<'FIXTURE'
# Abbreviated fixture (the documented, allowed form)

```json
{
  "error_codes": [
    ...existing codes...,
    "RATE_LIMITED"
  ]
}
```
FIXTURE

    cat > "$ST/broken/specs/sample.md" <<'FIXTURE'
# Broken fixture (unterminated string, no placeholder token)

```json
{
  "decision": "text",
  "text": "an unterminated string starts here
}
```
FIXTURE

    RC_CLEAN=0
    sh "$0" --root "$ST/clean" > "$ST/clean.out" 2>&1 || RC_CLEAN=$?
    RC_ABBR=0
    sh "$0" --root "$ST/abbreviated" > "$ST/abbr.out" 2>&1 || RC_ABBR=$?
    RC_BROKEN=0
    sh "$0" --root "$ST/broken" > "$ST/broken.out" 2>&1 || RC_BROKEN=$?

    ST_FAIL=0
    printf 'self-test: clean block      -> exit %s (expect 0)\n' "$RC_CLEAN"
    [ "$RC_CLEAN" -eq 0 ] || ST_FAIL=1
    printf 'self-test: abbreviated block-> exit %s (expect 0)\n' "$RC_ABBR"
    [ "$RC_ABBR" -eq 0 ] || ST_FAIL=1
    grep -q 'ALLOWED (abbreviated)' "$ST/abbr.out" || {
        echo 'self-test: abbreviated block was not reported ALLOWED (abbreviated)' >&2
        ST_FAIL=1
    }
    printf 'self-test: unterminated str -> exit %s (expect non-zero)\n' "$RC_BROKEN"
    [ "$RC_BROKEN" -ne 0 ] || ST_FAIL=1
    grep -q 'FAIL' "$ST/broken.out" || {
        echo 'self-test: broken block produced no FAIL line' >&2
        ST_FAIL=1
    }
    printf 'self-test: broken block said: %s\n' "$(grep 'FAIL ' "$ST/broken.out" | head -n 1)"

    if [ "$ST_FAIL" -eq 0 ]; then
        echo 'check-json-fences: SELF-TEST PASS — clean PASS, abbreviated ALLOWED, unterminated string FAIL'
    else
        echo 'check-json-fences: SELF-TEST FAIL — see the mismatches above' >&2
    fi

    rm -rf "$ST" 2>/dev/null || true
    [ "$ST_FAIL" -eq 0 ] || exit 1
    return 0
}

# ---------------------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------------------
ROOT=$DEFAULT_ROOT
SELF_TEST=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || { echo "FAIL: --root requires a directory" >&2; usage >&2; exit 2; }
            ROOT=$2
            shift 2
            ;;
        --root=*)
            ROOT=${1#*=}
            shift
            ;;
        --self-test)
            SELF_TEST=1
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

[ -d "$ROOT" ] || { echo "FAIL: not a directory: $ROOT" >&2; exit 2; }
ROOT=$(CDPATH= cd -- "$ROOT" && pwd)

if [ "$SELF_TEST" -eq 1 ]; then
    self_test
    exit $?
fi

make_tmp
trap 'clean_tmp' EXIT INT TERM HUP
RC=0
run_guard || RC=$?
exit "$RC"
