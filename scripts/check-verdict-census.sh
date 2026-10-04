#!/bin/sh
# check-verdict-census.sh — composite verdict census over the DuckBrain guards
# (DF-H3-41 / DF-H3-46).
#
# WHY THIS EXISTS
#   Each DuckBrain guard is honest ALONE: with no token, no jq, no curl or no
#   board it prints UNVERIFIED lines and exits 0 — absent substrate is
#   UNVERIFIED, never a pass (the repo's gate philosophy, QA-H3-1). But
#   `make verify` composes the guards and unconditionally ended with
#       make verify: ALL PASS — umbrella repo is self-consistent   (rc=0)
#   so scripts/release.sh step 2 (exit code + the literal ALL PASS line under
#   set -euo pipefail) passed a release over a substrate nobody checked.
#   Proven twice: the /nonexistent-token probe (DF-H3-41, scratch worktree at
#   3864dbb) and a REAL fresh machine — bunker las-bunker-03 agent 1027e20b,
#   fresh clone at v0.3.0: 6 UNVERIFIED lines, final ALL PASS, rc=0
#   (DF-H3-46). An unchecked substrate was indistinguishable from a verified
#   one in the final line. This guard is the composite's verdict census: the
#   ALL PASS line is only printed when no guard reported UNVERIFIED this run.
#
# MECHANISM (the choice the board row asked to be stated here)
#   It does NOT re-run the guards against DuckBrain, and it does not scan a
#   verdict log: `make verify` does not tee per-prerequisite output, so a log
#   would need Makefile plumbing beyond the one extra prerequisite target.
#   Instead it re-derives — cheaply and read-only — the predicates under
#   which each DuckBrain guard DEGRADES to UNVERIFIED on THIS run: the same
#   env vars, the same token-dir globs, the same tool lookups, the same board
#   read, in each guard's own order and with each guard's own semantics (the
#   two guards genuinely differ: the sh guard SKIPS an unreadable *.token and
#   tries the next; the python walker PINS on the first directory that
#   contains one, and treats a set-but-empty token env as an explicit offline
#   pin). Each mirrored predicate is printed as a grep-friendly fact line
#   naming the guard and the exact degrade reason the guard would print.
#
#   Counted UNVERIFIED (mirror of the guards' own degrade conditions, in the
#   guards' own order):
#     tick-chain (scripts/check-duckbrain-tick-chain.sh):
#       H3_TICK_CHAIN_{START,LEGACY_MAX,NAMESPACE,LIMIT} malformed; jq or
#       curl not on PATH; no readable non-empty *.token in
#       $H3_TICK_CHAIN_TOKEN_DIR (default ~/.duckbrain); tree file
#       missing/unreadable/unparseable when H3_TICK_CHAIN_TREE_FILE is set;
#       board header missing or its line 1 carrying no integer ticks_total
#       (unless H3_TICK_CHAIN_TICKS_TOTAL overrides the read).
#     tree-census (scripts/duckbrain-tree-census.py, as `make verify-tick-chain`
#       invokes it: `h3 --start 418 --end auto --url http://localhost:3000
#       $H3_TREE_CENSUS_ARGS`):
#       python3 not on PATH; --start/--legacy-max negative or --limit < 1;
#       an --allowlist entry that is not an integer; --end auto/board with no
#       --ticks-total override and a board header that is missing or carries
#       no integer ticks_total; token env $H3OPS_DUCKBRAIN_API_KEY set but
#       empty (explicit offline pin); --token-file missing/unreadable/empty;
#       no *.token in --token-dir, else in $H3_TREE_CENSUS_TOKEN_DIR, then
#       ~/.duckbrain, then <repo>/scripts/.duckbrain (first directory that
#       CONTAINS a *.token pins the resolution: an unreadable or empty token
#       there degrades, it does not fall through). H3_TREE_CENSUS_ARGS is
#       parsed for --tree-file/--token-*/--board/--ticks-total/--start/
#       --end/--limit/--legacy-max/--allowlist/--token-env so the mirror
#       follows whatever the operator actually asked for; args that would
#       make argparse exit 2 (unknown flag, missing value, non-integer) are
#       counted VERIFIED — `make verify` would die on the walker's exit 2
#       before any verdict, so the composite is already not green.
#   Zero cells / absent board is UNVERIFIED, never a pass (QA-H3-1) — the
#   same vocabulary as the tick-chain guard.
#
# RESIDUAL (documented, deliberate)
#   A degrade that depends on the ANSWER rather than the pre-flight substrate
#   — a reachable DuckBrain that returns truncated (total >= limit) or
#   unparseable JSON — is visible in the guards' own UNVERIFIED lines but is
#   NOT re-derived here: the census performs no network read (it is not a
#   third reader of the tree). That class requires a REACHABLE service with a
#   WORKING token — the opposite of the substrate-unreachable fresh-machine
#   path this guard closes (DF-H3-41/46) — and on such a host the census's
#   other predicates pass, so it reports a clean census and the guards' own
#   honest UNVERIFIED lines remain the visible record. Operators who want the
#   census to tolerate a substrate they KNOW is absent set the escape hatch
#   below rather than weakening a guard.
#
# VERDICT LINES (grep-friendly; the composite's Makefile recipe must print
# ALL PASS only after this guard passed):
#   make verify: verdict census — N verified / M unverified (guard: <names>)
#   M = 0:                     "make verify: verdict census PASS"; exit 0
#   M > 0, no H3_ALLOW_UNVERIFIED:
#                              "make verify: verdict census FAIL — ..." exit 1
#   M > 0, H3_ALLOW_UNVERIFIED=1:
#                              "make verify: verdict census PASS (local
#                              degrade: M UNVERIFIED accepted via
#                              H3_ALLOW_UNVERIFIED)"; exit 0
#
# ENV (all optional — the census reads exactly the variables the guards read,
# with the guards' defaults; it never reads token CONTENTS, only paths):
#   H3_TICK_CHAIN_URL, H3_TICK_CHAIN_NAMESPACE, H3_TICK_CHAIN_TOKEN_DIR,
#   H3_TICK_CHAIN_TREE_FILE, H3_TICK_CHAIN_TICKS_TOTAL, H3_TICK_CHAIN_START,
#   H3_TICK_CHAIN_ALLOWLIST (parsed for the walker mirror only),
#   H3_TICK_CHAIN_LEGACY_MAX, H3_TICK_CHAIN_LIMIT,
#   H3OPS_DUCKBRAIN_API_KEY, H3_TREE_CENSUS_TOKEN_DIR, H3_TREE_CENSUS_ARGS,
#   H3_ALLOW_UNVERIFIED (=1 is the only enabling value; any other value,
#   including set-but-empty, does NOT enable the degrade acceptance).
#
# SELFTEST
#   ./scripts/check-verdict-census.sh --selftest   (or: make
#   verify-verdict-census-selftest) — positive + negative proof: clean
#   substrate PASS, blocked-token FAIL naming both guards, the
#   H3_ALLOW_UNVERIFIED degrade acceptance, single-guard attribution, and
#   both drift directions of the census counter via mutated copies of this
#   script (an under-count that would wrongly PASS a blocked substrate and
#   an over-count that would wrongly FAIL a clean one — the mutated copy
#   MUST produce the drifted verdict, proving the composite verdict is
#   driven by this census counter and nothing else).
#
# Exit codes: 0 = census passed (possibly with the explicit degrade), 1 =
# census failed (M > 0 without the escape hatch), 2 = usage error.
# Dependencies: POSIX sh + coreutils. jq is invoked ONLY where the tick-chain
# mirror checks tree-file parseability — and jq's absence degrades that guard
# earlier anyway, so the census never NEEDS jq to count correctly. READ ONLY.
#
# GUARD-FILES: check-duckbrain-tick-chain.sh duckbrain-tree-census.py

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SELF=$SCRIPT_DIR/check-verdict-census.sh

F_TICK_CHAIN=check-duckbrain-tick-chain.sh
F_TREE_CENSUS=duckbrain-tree-census.py

usage() {
    echo "usage: sh scripts/check-verdict-census.sh [--selftest]" >&2
    exit 2
}

case ${1:-} in
    --selftest) exec sh "$SCRIPT_DIR/check-verdict-census-selftest.sh" ;;
    '') : ;;
    *) usage ;;
esac

# Fact lines: one per mirrored predicate, naming the guard, house style.
tc_unverified() { echo "verdict-census: tick-chain would report UNVERIFIED — $1"; }
py_unverified() { echo "verdict-census: tree-census would report UNVERIFIED — $1"; }
py_rc2() {
    echo "verdict-census: tree-census counted VERIFIED without a re-read — H3_TREE_CENSUS_ARGS would make the walker exit 2 (usage error; 'make verify' would die on it): $1"
}

# The board header's ticks_total, read the way both guards read it: line 1
# only, integer value (grep form of the guards' jq/JSON reads on the compact
# header object the board-header guard canonicalizes).
board_ticks_total() { # $1 = board path; prints the integer or nothing
    [ -f "$1" ] || return 0
    head -n 1 "$1" 2>/dev/null |
        grep -o '"ticks_total":[0-9][0-9]*' 2>/dev/null |
        head -n 1 |
        grep -o '[0-9][0-9]*' 2>/dev/null ||
        true
}

# ---- mirror 1: scripts/check-duckbrain-tick-chain.sh ------------------------
# Predicate order and semantics follow the guard line by line (its header
# documents every degrade); the fetch itself is the documented residual.
classify_tick_chain_sh() {
    TC_START=${H3_TICK_CHAIN_START:-418}
    case $TC_START in
        '' | *[!0-9]*) tc_unverified "H3_TICK_CHAIN_START is not a non-negative integer: '$TC_START'"; return 1 ;;
    esac
    TC_LEGACY_MAX=${H3_TICK_CHAIN_LEGACY_MAX:-427}
    case $TC_LEGACY_MAX in
        '' | *[!0-9]*) tc_unverified "H3_TICK_CHAIN_LEGACY_MAX is not a non-negative integer: '$TC_LEGACY_MAX'"; return 1 ;;
    esac
    TC_NS=${H3_TICK_CHAIN_NAMESPACE:-h3}
    case $TC_NS in
        '' | */*) tc_unverified "H3_TICK_CHAIN_NAMESPACE is not a bare namespace name: '$TC_NS'"; return 1 ;;
    esac
    TC_LIMIT=${H3_TICK_CHAIN_LIMIT:-5000}
    case $TC_LIMIT in
        '' | *[!0-9]*) tc_unverified "H3_TICK_CHAIN_LIMIT is not a positive integer: '$TC_LIMIT'"; return 1 ;;
    esac

    command -v jq >/dev/null 2>&1 || {
        tc_unverified "jq not found on PATH — cannot classify the key tree"
        return 1
    }

    TC_TREE_FILE=${H3_TICK_CHAIN_TREE_FILE:-}
    if [ -n "$TC_TREE_FILE" ]; then
        [ -f "$TC_TREE_FILE" ] || {
            tc_unverified "tree file is missing: $TC_TREE_FILE"
            return 1
        }
        [ -r "$TC_TREE_FILE" ] || {
            tc_unverified "tree file is not readable: $TC_TREE_FILE"
            return 1
        }
        jq -e . "$TC_TREE_FILE" >/dev/null 2>&1 || {
            tc_unverified "answer is not parseable JSON (source: file:$TC_TREE_FILE)"
            return 1
        }
    else
        command -v curl >/dev/null 2>&1 || {
            tc_unverified "curl not found on PATH — cannot reach DuckBrain"
            return 1
        }
        TC_TOKEN_DIR=${H3_TICK_CHAIN_TOKEN_DIR:-${HOME:-}/.duckbrain}
        TC_TOKEN_FILE=
        # The guard SKIPS non-files and unreadable files and keeps looking.
        for f in "$TC_TOKEN_DIR"/*.token; do
            [ -f "$f" ] || continue
            [ -r "$f" ] || continue
            TC_TOKEN_FILE=$f
            break
        done
        [ -n "$TC_TOKEN_FILE" ] || {
            tc_unverified "no readable token: no *.token file in $TC_TOKEN_DIR"
            return 1
        }
        [ -s "$TC_TOKEN_FILE" ] || {
            tc_unverified "token file is empty: $TC_TOKEN_FILE"
            return 1
        }
        # (reachability, answer parseability and the truncation guard are the
        # documented residual — see MECHANISM/RESIDUAL in the header)
        :
    fi

    TC_TOTAL_OVR=${H3_TICK_CHAIN_TICKS_TOTAL:-}
    if [ -z "$TC_TOTAL_OVR" ]; then
        BOARD=$ROOT/.coding-hermes/board/board.jsonl
        [ -f "$BOARD" ] || {
            tc_unverified "board header unreadable ($BOARD is missing) and no H3_TICK_CHAIN_TICKS_TOTAL override is set"
            return 1
        }
        TC_TOTAL=$(board_ticks_total "$BOARD")
        [ -n "$TC_TOTAL" ] || {
            tc_unverified "board header ($BOARD line 1) carries no ticks_total and no H3_TICK_CHAIN_TICKS_TOTAL override is set"
            return 1
        }
    else
        TC_TOTAL=$TC_TOTAL_OVR
    fi
    case $TC_TOTAL in
        '' | *[!0-9]*) tc_unverified "ticks_total is not an integer: '$TC_TOTAL'"; return 1 ;;
    esac
    return 0
}

# ---- mirror 2: scripts/duckbrain-tree-census.py -----------------------------
# As `make verify-tick-chain` invokes it. H3_TREE_CENSUS_ARGS is parsed with
# the same shell expansion the Makefile itself applies to it (same trust
# boundary: whoever sets the env owns the words).
classify_tree_census() {
    command -v python3 >/dev/null 2>&1 || {
        py_unverified "python3 not found on PATH (the independent census was not run)"
        return 1
    }

    # ---- argparse-equivalent defaults + H3_TREE_CENSUS_ARGS ----------------
    C_START=418
    C_LEGACY_MAX=427
    C_LIMIT=20000
    C_ALLOWLIST=452,453,464
    C_END=
    C_TOKEN_ENV_NAME=H3OPS_DUCKBRAIN_API_KEY
    C_TOKEN_FILE=
    C_TOKEN_DIR=
    C_BOARD=$ROOT/.coding-hermes/board/board.jsonl
    C_TREE_FILE=
    C_TICKS_TOTAL=
    C_ARGS=${H3_TREE_CENSUS_ARGS:-}
    if [ -n "$C_ARGS" ]; then
        eval "set -- $C_ARGS" || {
            py_unverified "H3_TREE_CENSUS_ARGS does not parse as shell words: '$C_ARGS'"
            return 1
        }
        while [ $# -gt 0 ]; do
            case $1 in
                --start) [ $# -ge 2 ] || { py_rc2 "--start: expected one argument"; return 0; }; C_START=$2; shift ;;
                --start=*) C_START=${1#--start=} ;;
                --end) [ $# -ge 2 ] || { py_rc2 "--end: expected one argument"; return 0; }; C_END=$2; shift ;;
                --end=*) C_END=${1#--end=} ;;
                --limit) [ $# -ge 2 ] || { py_rc2 "--limit: expected one argument"; return 0; }; C_LIMIT=$2; shift ;;
                --limit=*) C_LIMIT=${1#--limit=} ;;
                --legacy-max) [ $# -ge 2 ] || { py_rc2 "--legacy-max: expected one argument"; return 0; }; C_LEGACY_MAX=$2; shift ;;
                --legacy-max=*) C_LEGACY_MAX=${1#--legacy-max=} ;;
                --allowlist) [ $# -ge 2 ] || { py_rc2 "--allowlist: expected one argument"; return 0; }; C_ALLOWLIST=$2; shift ;;
                --allowlist=*) C_ALLOWLIST=${1#--allowlist=} ;;
                --token-env) [ $# -ge 2 ] || { py_rc2 "--token-env: expected one argument"; return 0; }; C_TOKEN_ENV_NAME=$2; shift ;;
                --token-env=*) C_TOKEN_ENV_NAME=${1#--token-env=} ;;
                --token-file) [ $# -ge 2 ] || { py_rc2 "--token-file: expected one argument"; return 0; }; C_TOKEN_FILE=$2; shift ;;
                --token-file=*) C_TOKEN_FILE=${1#--token-file=} ;;
                --token-dir) [ $# -ge 2 ] || { py_rc2 "--token-dir: expected one argument"; return 0; }; C_TOKEN_DIR=$2; shift ;;
                --token-dir=*) C_TOKEN_DIR=${1#--token-dir=} ;;
                --board) [ $# -ge 2 ] || { py_rc2 "--board: expected one argument"; return 0; }; C_BOARD=$2; shift ;;
                --board=*) C_BOARD=${1#--board=} ;;
                --ticks-total) [ $# -ge 2 ] || { py_rc2 "--ticks-total: expected one argument"; return 0; }; C_TICKS_TOTAL=$2; shift ;;
                --ticks-total=*) C_TICKS_TOTAL=${1#--ticks-total=} ;;
                --tree-file) [ $# -ge 2 ] || { py_rc2 "--tree-file: expected one argument"; return 0; }; C_TREE_FILE=$2; shift ;;
                --tree-file=*) C_TREE_FILE=${1#--tree-file=} ;;
                # parsed but irrelevant to the pre-flight mirror
                --url | --url=* | --timeout | --timeout=*) case $1 in --url | --timeout) shift ;; esac ;;
                '') : ;; # a quoted empty word (e.g. --allowlist '') carries no flag
                *) py_rc2 "unrecognized argument: $1"; return 0 ;;
            esac
            shift
        done
    fi

    # ---- numeric validation, in main()'s order ------------------------------
    case $C_START in
        [0-9]*) : ;;
        -[0-9]*) py_unverified "--start is negative: $C_START"; return 1 ;;
        *) py_rc2 "--start: invalid int value: '$C_START'"; return 0 ;;
    esac
    case $C_LEGACY_MAX in
        [0-9]*) : ;;
        -[0-9]*) py_unverified "--legacy-max is negative: $C_LEGACY_MAX"; return 1 ;;
        *) py_rc2 "--legacy-max: invalid int value: '$C_LEGACY_MAX'"; return 0 ;;
    esac
    case $C_LIMIT in
        [0-9]*) case $C_LIMIT in 0) py_unverified "--limit is not positive: $C_LIMIT"; return 1 ;; esac ;;
        -[0-9]*) py_unverified "--limit is not positive: $C_LIMIT"; return 1 ;;
        *) py_rc2 "--limit: invalid int value: '$C_LIMIT'"; return 0 ;;
    esac

    # ---- the allowlist entries must be integers -----------------------------
    OLDIFS=$IFS
    IFS=,
    # shellcheck disable=SC2086
    for item in $C_ALLOWLIST; do
        IFS=$OLDIFS
        item=$(printf '%s' "$item" | tr -d ' \t')
        [ -n "$item" ] || continue
        case $item in
            '' | *[!0-9]*)
                py_unverified "--allowlist entry is not an integer: '$item'"
                return 1
                ;;
        esac
    done
    IFS=$OLDIFS

    # ---- the window basis (--end auto reads the board BEFORE the tree) ------
    if [ -n "$C_END" ]; then
        C_END_LC=$(printf '%s' "$C_END" | tr '[:upper:]' '[:lower:]')
        case $C_END_LC in
            auto | board)
                if [ -n "$C_TICKS_TOTAL" ]; then
                    case $C_TICKS_TOTAL in
                        '' | *[!0-9-]* | -*[!0-9]*)
                            py_rc2 "--ticks-total: invalid int value: '$C_TICKS_TOTAL'"
                            return 0
                            ;;
                    esac
                else
                    [ -f "$C_BOARD" ] || {
                        py_unverified "board header unreadable ($C_BOARD is missing) and no --ticks-total override — cannot resolve --end auto"
                        return 1
                    }
                    C_TOTAL=$(board_ticks_total "$C_BOARD")
                    [ -n "$C_TOTAL" ] || {
                        py_unverified "board header ($C_BOARD line 1) carries no integer ticks_total and no --ticks-total override — cannot resolve --end auto"
                        return 1
                    }
                fi
                ;;
            [0-9]*) : ;;
            -[0-9]*) : ;; # a negative closed END is a legal int for argparse
            *) py_rc2 "--end: not an integer, not 'auto'/'board': '$C_END'"; return 0 ;;
        esac
    fi
    # (C_END absent = the walker's EMPTY window: the hole check is skipped and
    # only the drift census runs — the tree must still be readable, so the
    # token predicates below still apply, exactly as in the walker.)

    # ---- the tree source: file (offline) or fetch ---------------------------
    if [ -n "$C_TREE_FILE" ]; then
        [ -f "$C_TREE_FILE" ] || {
            py_unverified "tree file is missing: $C_TREE_FILE"
            return 1
        }
        [ -r "$C_TREE_FILE" ] || {
            py_unverified "tree file could not be read: $C_TREE_FILE"
            return 1
        }
        # (parseability / tree-shape / truncation are the documented residual)
        return 0
    fi

    # ---- token resolution, the walker's exact precedence --------------------
    if [ -n "$C_TOKEN_ENV_NAME" ]; then
        eval "C_ENV_SET=\${$C_TOKEN_ENV_NAME+set}"
        if [ -n "$C_ENV_SET" ]; then
            eval "C_ENV_VAL=\${$C_TOKEN_ENV_NAME}"
            if [ -n "$(printf '%s' "$C_ENV_VAL" | tr -d ' \t\n\r')" ]; then
                return 0 # token from env; fetch/post-fetch residual documented
            fi
            py_unverified "token env var is set but empty: $C_TOKEN_ENV_NAME"
            return 1
        fi
    fi
    if [ -n "$C_TOKEN_FILE" ]; then
        [ -f "$C_TOKEN_FILE" ] || {
            py_unverified "token file is missing: $C_TOKEN_FILE"
            return 1
        }
        [ -r "$C_TOKEN_FILE" ] || {
            py_unverified "token file could not be read ($C_TOKEN_FILE)"
            return 1
        }
        [ -n "$(tr -d ' \t\n\r' < "$C_TOKEN_FILE" 2>/dev/null)" ] || {
            py_unverified "token file is empty: $C_TOKEN_FILE"
            return 1
        }
        return 0
    fi
    # Directory search: --token-dir alone when given, else the fallback chain.
    C_DIRS=
    if [ -n "$C_TOKEN_DIR" ]; then
        C_DIRS=$C_TOKEN_DIR
    else
        [ -n "${H3_TREE_CENSUS_TOKEN_DIR:-}" ] && C_DIRS=$H3_TREE_CENSUS_TOKEN_DIR
        C_DIRS="$C_DIRS ${HOME:-}/.duckbrain"
        C_DIRS="$C_DIRS $ROOT/scripts/.duckbrain"
    fi
    C_TOKEN_DIRS_LISTED=
    for d in $C_DIRS; do
        C_TOKEN_DIRS_LISTED="$C_TOKEN_DIRS_LISTED$d, "
        [ -d "$d" ] || continue
        found=
        for f in "$d"/*.token; do
            [ -e "$f" ] || continue
            found=$f
            break
        done
        [ -n "$found" ] || continue
        # First directory CONTAINING a *.token pins the resolution: an
        # unreadable or empty token there degrades, it does not fall through.
        if [ ! -f "$found" ] || [ ! -r "$found" ]; then
            py_unverified "token file could not be read ($found)"
            return 1
        fi
        [ -n "$(tr -d ' \t\n\r' < "$found" 2>/dev/null)" ] || {
            py_unverified "token file is empty: $found"
            return 1
        }
        return 0
    done
    py_unverified "no token: env $C_TOKEN_ENV_NAME is unset and no readable *.token file exists in ${C_TOKEN_DIRS_LISTED:-<no directories>} — set the env var, pass --token-dir/--token-file, or use --tree-file PATH for an offline census"
    return 1
}

# ---- the census --------------------------------------------------------------
# MUTATION TARGET: the selftest's drift-direction proof arms rewrite exactly
# these two `if classify_*` conditions in a COPY of this script (true = blind
# under-count, false = blind over-count) and require the mutated copy to
# produce the DRIFTED verdict — so this counter, not anything else, is what
# the composite verdict rests on.
classify_guards() {
    n_verified=0
    n_unverified=0
    guard_names=
    for gf in "$F_TICK_CHAIN" "$F_TREE_CENSUS"; do
        [ -f "$ROOT/scripts/$gf" ] ||
            echo "verdict-census: guard script missing: scripts/$gf — counted VERIFIED ('make verify' would die before printing its verdict)"
    done
    if classify_tick_chain_sh; then
        n_verified=$((n_verified + 1))
    else
        n_unverified=$((n_unverified + 1))
        guard_names=tick-chain
    fi
    if classify_tree_census; then
        n_verified=$((n_verified + 1))
    else
        n_unverified=$((n_unverified + 1))
        guard_names="$guard_names${guard_names:+ }tree-census"
    fi
}

classify_guards
echo "make verify: verdict census — $n_verified verified / $n_unverified unverified (guard: ${guard_names:-none})"
if [ "$n_unverified" -eq 0 ]; then
    echo "make verify: verdict census PASS"
    exit 0
fi
if [ "${H3_ALLOW_UNVERIFIED:-}" = "1" ]; then
    echo "make verify: verdict census PASS (local degrade: $n_unverified UNVERIFIED accepted via H3_ALLOW_UNVERIFIED)"
    exit 0
fi
echo "make verify: verdict census FAIL — $n_unverified unverified guard(s): $guard_names — an UNVERIFIED substrate must not compose into ALL PASS (DF-H3-41/DF-H3-46); set H3_ALLOW_UNVERIFIED=1 to accept this degraded run explicitly"
exit 1
