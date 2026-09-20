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
#   Both engines take ONE process per guard run (GAP-075), not one per block. Each reads the
#   job list (one payload path per line, in manifest order) and emits exactly one result line
#   per job, in that order:
#     OK
#     <status><TAB><file><TAB><open-line><TAB><nested-count><TAB><payload><TAB><inner-line><TAB><msg>
#
#   python3 (preferred): ONE `python3 "$TMP/validate.py" "$TMP/jobs.txt"` runs the canonical
#   json.load over every payload. The ENGINE SEMANTICS ARE UNCHANGED — same json.load, same
#   blocks, same failure message derivation (last non-blank traceback line, `line N` pulled out
#   of it, exception-class prefix stripped). Only the process count changed.
#   Structural fallback (when python3 is absent): per-line unterminated-string detection plus
#   brace/bracket balance, also batched into ONE awk process. WEAKER — it cannot see a
#   comma-less `...` member inside an array (python3 can), so it is a floor, not a parser; it
#   announces itself loudly when used.
#
#   WHY (GAP-075, fleet load-hygiene): the per-block form started one interpreter per ```json
#   block — 65 python3 processes for 65 blocks in this repo, ~80% of `make verify` wall clock,
#   and the only member of this repo's gate battery that fired a subprocess per artifact. The
#   batch keeps the same blocks, the same engine, the same messages and the same exit codes; it
#   removes 64 interpreter starts. Measured before/after: docs/verification/gap-075-load-hygiene.md
#
#   The batched engines are all-or-nothing: if the engine does not complete, or returns a result
#   count that disagrees with the job count, the guard fails LOUD with exit 2 (misconfigured)
#   instead of reporting a short run as a pass.
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

# Field separator for the batched engine's result lines (GAP-075). A literal tab, not a
# whitespace-collapsing default: the engine echoes each job's own fields back.
TAB=$(printf '\t')

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
# Engines (batched — GAP-075). Each takes the JOB LIST as its single operand and prints one
# result line per job, in job order:
#     OK
#     <status><TAB><file><TAB><open-line><TAB><nested-count><TAB><payload><TAB><inner-line><TAB><msg>
# The job list is one record per validate-able block:  <file>|<open-line>|<nested-count>|<payload>
# (the `|` framing already comes from the manifest — see extract_blocks).
# ---------------------------------------------------------------------------------------
write_structural_awk() {
    cat > "$TMP/structural.awk" <<'AWK'
# Structural fallback payload check: per-line unterminated-string detection + brace/bracket
# balance. NOT a JSON parser (no comma/colon/trailing-token checks) — see the header.
# Batched: reads the job list given as the single operand and validates every payload in it,
# resetting the per-file state at each job. The per-line semantics are those of the former
# per-block form; only the process count changed (one awk for the whole run, GAP-075).
BEGIN {
    list = ARGV[1]
    ARGV[1] = ""
    rc = (getline job < list)
    if (rc < 0) { print "structural: cannot read job list: " list > "/dev/stderr"; exit 2 }
    while (rc > 0) {
        if (job == "") { rc = (getline job < list); continue }
        n = split(job, f, "|")
        payload = f[4]
        for (k = 5; k <= n; k++) payload = payload "|" f[k]
        depth = 0; bad = 0; nline = 0; eline = 0; emsg = ""
        prc = (getline ln < payload)
        if (prc < 0) { bad = 1; eline = 0; emsg = "cannot read payload"; prc = 0 }
        while (prc > 0) {
            nline++
            instr = 0
            for (j = 1; j <= length(ln); j++) {
                c = substr(ln, j, 1)
                if (instr) {
                    if (c == "\\") { j++; continue }
                    if (c == "\"") instr = 0
                    continue
                }
                if (c == "\"") { instr = 1; continue }
                if (c == "{" || c == "[") { depth++; continue }
                if (c == "}" || c == "]") {
                    depth--
                    if (depth < 0 && !bad) { eline = nline; emsg = "unexpected closing bracket '" c "'"; bad = 1 }
                    continue
                }
            }
            if (instr && !bad) { eline = nline; emsg = "unterminated string"; bad = 1 }
            prc = (getline ln < payload)
        }
        close(payload)
        if (!bad && depth != 0) { eline = nline; emsg = "unbalanced braces/brackets (depth " depth ")"; bad = 1 }
        # The `structural: ` prefix is part of this engine's message format — the former
        # per-block wrapper added it, and it is what tells a reader which engine spoke.
        if (bad) printf "FAIL\t%s\t%s\t%s\t%s\t%d\tstructural: %s\n", f[1], f[2], f[3], payload, eline, emsg
        else printf "OK\t%s\t%s\t%s\t%s\n", f[1], f[2], f[3], payload
        rc = (getline job < list)
    }
    close(list)
    exit 0
}
AWK
}

write_python3_script() {
    # Batched python3 engine (GAP-075): ONE interpreter for the whole job list. The engine is
    # the canonical json.load; the failure derivation mirrors exactly what the former per-block
    # form did with an uncaught traceback on stderr — take the last non-blank line, pull
    # `line <N>` out of it, and strip the exception-class prefix.
    cat > "$TMP/validate.py" <<'PY'
import json
import re
import sys
import traceback

LINE_RE = re.compile(r"line (\d+)")
PREFIX_RES = (
    re.compile(r"^json\.decoder\.JSONDecodeError: "),
    re.compile(r"^[A-Za-z_][A-Za-z0-9_.]*Error: "),
)


def derive(tb):
    """The derivation the shell applied to python3's stderr in the per-block form."""
    lines = [l for l in tb.splitlines() if l.strip()]
    last = lines[-1] if lines else ""
    m = LINE_RE.search(last)
    if not m:
        m = LINE_RE.search(tb)
    line = m.group(1) if m else "0"
    msg = last
    for r in PREFIX_RES:
        msg = r.sub("", msg)
    # Framing guard: the result line is TAB-separated, so a tab or newline inside the message
    # would break field pairing for the shell. Real json errors never carry one.
    msg = msg.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    return line, msg


def main():
    out = sys.stdout
    with open(sys.argv[1]) as jobs:
        for raw in jobs:
            job = raw.rstrip("\n")
            if not job:
                continue
            fields = job.split("|", 3)
            if len(fields) != 4:
                out.write("FAIL\t?\t?\t?\t%s\t0\tmalformed job record\n" % (job,))
                continue
            bfile, bline, nested, payload = fields
            try:
                with open(payload) as fh:
                    json.load(fh)
            except Exception:
                line, msg = derive(traceback.format_exc())
                out.write("FAIL\t%s\t%s\t%s\t%s\t%s\t%s\n" % (bfile, bline, nested, payload, line, msg))
                continue
            out.write("OK\t%s\t%s\t%s\t%s\n" % (bfile, bline, nested, payload))
    out.flush()


if __name__ == "__main__":
    main()
PY
}

run_engine() {
    # ONE engine process for the whole run (GAP-075). Any non-zero engine exit, or a result
    # count that disagrees with the job count, is a loud misconfiguration — never a pass.
    NRES=0
    RC=0
    : > "$TMP/results.txt"
    : > "$TMP/engine.err"
    if [ "$ENGINE" = python3 ]; then
        python3 "$TMP/validate.py" "$TMP/jobs.txt" > "$TMP/results.txt" 2> "$TMP/engine.err" || RC=$?
    else
        awk -f "$TMP/structural.awk" "$TMP/jobs.txt" < /dev/null > "$TMP/results.txt" 2> "$TMP/engine.err" || RC=$?
    fi
    if [ "$RC" -ne 0 ]; then
        echo "FAIL: check-json-fences — the $ENGINE validation pass exited $RC; guard misconfigured" >&2
        if [ -s "$TMP/engine.err" ]; then cat "$TMP/engine.err" >&2; fi
        exit 2
    fi
    NRES=$(wc -l < "$TMP/results.txt" | tr -d '[:space:]')
    if [ "$NRES" != "$TOTAL" ]; then
        echo "FAIL: check-json-fences — the $ENGINE validation pass returned $NRES result(s) for $TOTAL block(s); guard misconfigured" >&2
        if [ -s "$TMP/engine.err" ]; then cat "$TMP/engine.err" >&2; fi
        exit 2
    fi
    if [ -s "$TMP/engine.err" ]; then cat "$TMP/engine.err" >&2; fi
    return 0
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
    write_python3_script
    extract_blocks

    TOTAL=0
    ALLOWED=0
    FAILED=0

    # Pass 1: walk the manifest once to count the blocks and build the job list. Nothing is
    # validated here, so the engine can be a single process (GAP-075).
    : > "$TMP/jobs.txt"
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
        printf '%s|%s|%s|%s\n' "$bfile" "$bline" "${nested:-0}" "$payload" >> "$TMP/jobs.txt"
    done < "$TMP/manifest.txt"

    # Pass 2: validate every block in ONE engine process, then report in manifest order. The
    # engine echoes each job's own fields back, so a result line is self-identifying and the
    # per-block attribution (file, absolute line, inner line) survives the batch.
    run_engine

    while IFS="$TAB" read -r status bfile bline nested payload rline rmsg; do
        [ -n "$status" ] || continue
        if [ "${nested:-0}" -gt 0 ]; then
            echo "NOTE: check-json-fences — $bfile:$bline carries $nested line-initial nested fence(s); they are content per CommonMark but almost always an authoring accident" >&2
        fi
        if [ "$status" = "OK" ]; then
            continue
        fi
        L=$rline
        MSG=$rmsg
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
            if [ -n "$FAILTEXT" ]; then printf '                   %s\n' "$FAILTEXT" >&2; fi
        fi
    done < "$TMP/results.txt"

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
