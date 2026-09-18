#!/bin/sh
# check-qa-target-selftest.sh — executable negative proof for scripts/check-qa-target.sh (QA-H3-1).
#
# The contract this pins: a QA target that does not exist, is not a checkout,
# or is the wrong repository must FAIL LOUDLY (non-zero), and only a real
# get-h3/h3 checkout may pass. The first case is the QA-H3-1 incident verbatim
# (a target path that was never there); if the guard ever regresses to
# "nothing to check = ok", this script goes red.
#
# Exit codes: 0 = every case behaved as specified, 1 = at least one did not,
#             2 = the selftest itself could not run (misconfigured).
#
# Zero dependencies beyond POSIX sh, coreutils and git.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/check-qa-target.sh"
REPO=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ ! -f "$GUARD" ]; then
    echo "FAIL: guard not found beside this selftest: $GUARD" >&2
    exit 2
fi
command -v git >/dev/null 2>&1 || { echo "FAIL: git not found" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/qa-target-selftest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

# A scratch dir inside a git work tree would make the "not a git work tree"
# case vacuous, so refuse to run rather than report a false pass.
if git -C "$WORK" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "FAIL: selftest scratch dir is inside a git work tree: $WORK" >&2
    exit 2
fi

pass=0
fail=0

# case_run <name> <expected-rc> <expected-substring-or-empty> [args...]
case_run() {
    name=$1
    want=$2
    want_text=$3
    shift 3
    out=$(sh "$GUARD" "$@" 2>&1) && rc=0 || rc=$?
    # shellcheck disable=SC2086
    if [ "$rc" != "$want" ]; then
        echo "  FAIL: $name — expected exit $want, got $rc" >&2
        printf '%s\n' "$out" | sed 's/^/        | /' >&2
        fail=$((fail + 1))
        return 0
    fi
    if [ -n "$want_text" ]; then
        case "$out" in
            *"$want_text"*) : ;;
            *)
                echo "  FAIL: $name — exit $rc as expected, but output does not mention '$want_text'" >&2
                printf '%s\n' "$out" | sed 's/^/        | /' >&2
                fail=$((fail + 1))
                return 0
                ;;
        esac
    fi
    echo "  ok: $name (exit $rc)"
    pass=$((pass + 1))
}

echo "check-qa-target-selftest: negative proof for scripts/check-qa-target.sh"
echo "  scratch: $WORK"

# --- the incident shape: a target path that was never there -------------------
case_run "missing target directory fails closed (QA-H3-1 shape)" 1 "does not exist" "$WORK/gone"

# --- a path that exists but is not a directory --------------------------------
touch "$WORK/afile"
case_run "target that is a plain file fails closed" 1 "does not exist" "$WORK/afile"

# --- a directory that is not a checkout ---------------------------------------
mkdir -p "$WORK/notarepo"
case_run "non-git directory fails closed" 1 "not a git work tree" "$WORK/notarepo"

# --- a checkout of something else --------------------------------------------
mkdir -p "$WORK/foreign"
git -C "$WORK/foreign" init -q
case_run "git repo without the umbrella markers fails closed" 1 "wrong repository" "$WORK/foreign"

# --- a sibling get-h3 repo shape (markers present, origin contradicts) --------
SIB="$WORK/sibling-shape"
mkdir -p "$SIB/specs" "$SIB/integration/roundtrip"
: > "$SIB/specs/_index.md"
: > "$SIB/integration/roundtrip/roundtrip.sh"
git -C "$SIB" init -q
git -C "$SIB" remote add origin git@github.com:get-h3/shim.git
case_run "sibling origin is reported as a sibling, not as the umbrella" 1 "SIBLING repository" "$SIB"

# --- positive control: a correctly shaped clone passes ------------------------
CLONE="$WORK/umbrella-shape"
mkdir -p "$CLONE/specs" "$CLONE/integration/roundtrip"
: > "$CLONE/specs/_index.md"
: > "$CLONE/integration/roundtrip/roundtrip.sh"
git -C "$CLONE" init -q
git -C "$CLONE" remote add origin git@github.com:get-h3/h3.git
case_run "correctly shaped umbrella clone passes" 0 "valid QA target" "$CLONE"

# --- the real checkout --------------------------------------------------------
case_run "this repository passes when passed explicitly" 0 "valid QA target" "$REPO"
case_run "a subdirectory resolves to its work-tree root" 0 "resolved to git work tree" "$REPO/specs"

# --- default resolution -------------------------------------------------------
case_run "no argument validates this repository" 0 "PASS" 

# --- guard misuse -------------------------------------------------------------
case_run "two arguments is a usage error" 2 "at most one TARGET_DIR" "$REPO" "$REPO"
case_run "empty argument is a usage error" 2 "is empty" ""

TOTAL=$((pass + fail))
echo "selftest: $pass/$TOTAL PASSED"
if [ "$fail" -ne 0 ]; then
    echo "selftest: FAILED — scripts/check-qa-target.sh no longer fails closed on a phantom target" >&2
    exit 1
fi
echo "selftest: scripts/check-qa-target.sh fails closed on a missing, non-checkout or foreign QA target (QA-H3-1)"
exit 0
