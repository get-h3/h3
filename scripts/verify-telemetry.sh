#!/bin/sh
# Record the actual guard output and exit status; never make a verify fail on telemetry.
set -u
GUARDS='verify-docs verify-specs verify-count verify-tags verify-json-fences verify-qa-target verify-tick-chain verify-board-header verify-commit-msg'
DEST=${H3_VERIFY_TEXTFILE_DIR:-/var/lib/node_exporter/textfile}

record() {
    capture=$1
    if [ ! -d "$DEST" ] || ! [ -w "$DEST" ]; then
        echo "verify-telemetry: WARN — textfile directory unavailable or unwritable: $DEST" >&2
        return 0
    fi
    lock=$DEST/.h3_verify.lock
    tries=0
    while ! mkdir "$lock" 2>/dev/null; do
        tries=$((tries + 1))
        if [ "$tries" -ge 30 ]; then
            echo 'verify-telemetry: WARN — could not acquire counter lock' >&2
            return 0
        fi
        sleep 1
    done
    tmp=$DEST/.h3_verify.prom.$$
    previous=$DEST/h3_verify.prom
    count=$(awk '/^h3_verify_runs_total\{target="verify"\} [0-9]+$/ { n++; v=$2 } END { if (n == 1) print v }' "$previous" 2>/dev/null || :)
    case "$count" in
        ''|*[!0-9]*) echo 'verify-telemetry: WARN — missing or corrupt prior counter; starting at 1' >&2; count=0 ;;
    esac
    # A bounded integer avoids shell arithmetic overflow on corrupt state.
    if [ ${#count} -gt 12 ]; then
        echo 'verify-telemetry: WARN — corrupt prior counter; starting at 1' >&2
        count=0
    fi
    count=$(awk -v n="$count" 'BEGIN { printf "%.0f", n + 1 }')
    if ! awk -v count="$count" '
      BEGIN {
        split("verify-docs verify-specs verify-count verify-tags verify-json-fences verify-qa-target verify-tick-chain verify-board-header verify-commit-msg", names, " ")
        print "# TYPE h3_verify_runs_total counter"
        print "h3_verify_runs_total{target=\"verify\"} " count
        print "# TYPE h3_verify_guard_result gauge"
      }
      /^__H3_BEGIN__ / { current=$2; next }
      /^__H3_END__ / { rc[$2]=$3; duration[$2]=$4; ended[$2]=1; current=""; next }
      {
        if (current == "verify-docs" && /^make verify: docs-link check PASS/) pass[current]=1
        if (current == "verify-specs" && /^make verify: spec-index-vs-files check PASS/) pass[current]=1
        if (current == "verify-count" && /^check-test-count: PASS/) pass[current]=1
        if (current == "verify-tags" && /^check-tags-table: PASS/) pass[current]=1
        if (current == "verify-json-fences" && /^check-json-fences: PASS/) pass[current]=1
        if (current == "verify-qa-target" && /^check-qa-target: PASS/) pass[current]=1
        if (current == "verify-tick-chain" && /^duckbrain-census-gate: PASS/) pass[current]=1
        if (current == "verify-board-header" && /^check-board-header-consistency: PASS/) pass[current]=1
        if (current == "verify-commit-msg" && /^check-ci-skip-tokens: PASS/) pass[current]=1
        if (current == "verify-tags" && /^check-tags-table: PASS \(local degrade/) degraded[current]=1
        if (current == "verify-tick-chain" && /(^VERDICT: UNVERIFIED|^make verify: (SKIP|DuckBrain census UNVERIFIED)|^duckbrain-census-gate: (SKIP|FAIL))/) degraded[current]=1
        if (current == "verify-board-header" && /^check-board-header-consistency: (UNVERIFIED|SKIP|FAIL)/) degraded[current]=1
      }
      END {
        for (i=1;i<=9;i++) { g=names[i]; result=(ended[g] && rc[g]==0 && pass[g] && !degraded[g]) ? 1 : 0; print "h3_verify_guard_result{guard=\"" g "\"} " result }
        print "# TYPE h3_verify_duration_seconds gauge"
        for (i=1;i<=9;i++) { g=names[i]; d=duration[g]; if (d !~ /^[0-9]+(\.[0-9]+)?$/) d=0; print "h3_verify_duration_seconds{guard=\"" g "\"} " d }
      }' "$capture" > "$tmp" || ! mv -f "$tmp" "$previous"; then
        echo 'verify-telemetry: WARN — unable to publish metrics' >&2
        rm -f "$tmp"
    fi
    rmdir "$lock" 2>/dev/null || :
    return 0
}

run_guard() {
    guard=$1
    file=$2
    start=$(date +%s%N)
    printf '__H3_BEGIN__ %s\n' "$guard" > "$file"
    ${MAKE:-make} --no-print-directory "$guard" >> "$file" 2>&1
    rc=$?
    end=$(date +%s%N)
    # Nanosecond timestamps -> float seconds with 3 decimals; the arithmetic
    # lives in awk because 19-digit integers overflow POSIX shell arithmetic.
    duration=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.3f", (e - s) / 1000000000 }')
    printf '__H3_END__ %s %s %s\n' "$guard" "$rc" "$duration" >> "$file"
    return "$rc"
}

run_verify() {
    work=$(mktemp -d "${TMPDIR:-/tmp}/h3-verify.XXXXXXXX") || {
        echo 'verify-telemetry: WARN — capture unavailable; running original verification without metrics' >&2
        ${MAKE:-make} --no-print-directory verify-prereqs
        return $?
    }
    # Run in bounded parallel batches; each target has an isolated capture, so
    # output-sync cannot distort start/end timestamps or mix verdicts.
    pids=''; batch=0; failed=0
    jobs=${VERIFY_JOBS:-8}
    case "$jobs" in ''|*[!0-9]*|0) jobs=8 ;; esac
    for guard in $GUARDS; do
        run_guard "$guard" "$work/$guard" &
        pids="$pids $!"; batch=$((batch + 1))
        if [ "$batch" -ge "$jobs" ]; then
            for pid in $pids; do wait "$pid" || failed=1; done
            pids=''; batch=0
        fi
    done
    for pid in $pids; do wait "$pid" || failed=1; done
    : > "$work/capture"
    for guard in $GUARDS; do
        cat "$work/$guard" >> "$work/capture"
        sed '/^__H3_BEGIN__ /d; /^__H3_END__ /d' "$work/$guard"
    done
    if [ "$failed" -eq 0 ]; then
        ${MAKE:-make} --no-print-directory -o verify-prereqs-early verify-verdict-census || failed=1
    fi
    record "$work/capture"
    rm -rf "$work"
    return "$failed"
}

selftest() {
    work=$(mktemp -d "${TMPDIR:-/tmp}/h3-verify-selftest.XXXXXXXX") || exit 1
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    DEST=$work/out; mkdir "$DEST"
    capture=$work/capture
    : > "$capture"
    for guard in $GUARDS; do
        case "$guard" in
          verify-docs) line='make verify: docs-link check PASS' ;;
          verify-specs) line='make verify: spec-index-vs-files check PASS' ;;
          verify-count) line='check-test-count: PASS' ;;
          verify-tags) line='check-tags-table: PASS' ;;
          verify-json-fences) line='check-json-fences: PASS' ;;
          verify-qa-target) line='check-qa-target: PASS' ;;
          verify-tick-chain) line='duckbrain-census-gate: PASS' ;;
          verify-board-header) line='check-board-header-consistency: PASS' ;;
          verify-commit-msg) line='check-ci-skip-tokens: PASS' ;;
        esac
        duration=2
        case "$guard" in verify-docs) duration=0.412 ;; esac
        printf '__H3_BEGIN__ %s\n%s\n__H3_END__ %s 0 %s\n' "$guard" "$line" "$guard" "$duration" >> "$capture"
    done
    record "$capture" 2>/dev/null
    [ "$(grep -c '^h3_verify_guard_result.* 1$' "$DEST/h3_verify.prom")" -eq 9 ] || exit 1
    [ "$(grep -c '^h3_verify_duration_seconds' "$DEST/h3_verify.prom")" -eq 9 ] || exit 1
    grep -q '^h3_verify_duration_seconds{guard="verify-docs"} 0\.412$' "$DEST/h3_verify.prom" || exit 1
    [ "$(grep -c '^h3_verify_duration_seconds.* 2$' "$DEST/h3_verify.prom")" -eq 8 ] || exit 1
    sed 's/check-test-count: PASS/check-test-count: FAIL/; s/check-tags-table: PASS/check-tags-table: PASS (local degrade)/; s/duckbrain-census-gate: PASS/duckbrain-census-gate: SKIP/' "$capture" > "$work/bad"
    record "$work/bad"
    for guard in verify-count verify-tags verify-tick-chain; do
        grep -q "^h3_verify_guard_result{guard=\"$guard\"} 0$" "$DEST/h3_verify.prom" || exit 1
    done
    grep -q '^h3_verify_runs_total{target="verify"} 2$' "$DEST/h3_verify.prom" || exit 1
    DEST=$work/missing
    record "$capture" 2> "$work/warn"
    grep -q 'WARN.*unwritable' "$work/warn" || exit 1
    echo 'verify-telemetry: PASS — nine guards and durations incl. sub-second float, FAIL, SKIP/degrade, counter, unwritable directory'
}

case ${1:---run} in
    --run) run_verify ;;
    --selftest) selftest ;;
    *) echo 'verify-telemetry: WARN — unknown mode' >&2; exit 0 ;;
esac
