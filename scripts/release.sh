#!/usr/bin/env bash
# release.sh — the H3 umbrella RELEASE DRIVER (RELEASE-H3-003).
#
# Usage:
#   bash scripts/release.sh [--dry-run] [--execute|--apply] [--verify-ci]
#                           [--no-changelog] [--tag vX.Y.Z] [--help]
#
#   (no flag) / --dry-run   DEFAULT. Report what a cut WOULD do and prove the
#                           gate is green. Mutates nothing: no tag, no push, no
#                           CHANGELOG write, no `gh` call, no workflow dispatch.
#   --execute / --apply     Perform the cut, in the order below. Together with
#                           --verify-ci this is a flag that mutates.
#   --verify-ci             Establish "CI green on HEAD" ONLY (RELEASE-H3-004):
#                           dispatch both path-filtered workflows on HEAD, wait
#                           for the runs, assert PER-JOB and PER-STEP success,
#                           print the cited run ids, exit. No cut: no tag, no
#                           push, no CHANGELOG write, no `gh release` call.
#                           A dispatch is a mutation, so this is an explicit
#                           opt-in and NOT part of the dry-run.
#   --no-changelog          Skip the CHANGELOG promote step (execute mode). Use
#                           when the [X.Y.Z] section was written by hand.
#   --tag vX.Y.Z            Override the proposed version. Still checked for
#                           existence; still cut from a clean verified tree.
#
# Exit codes (the convention the sibling guards use):
#   0 = ok — dry-run reported a coherent, gate-green plan / execute completed
#       and the GitHub Release object was verified with `gh release view` /
#       --verify-ci cited both workflows green on HEAD, per-job and per-step
#   1 = a release PRECONDITION failed: dirty work tree, `make verify` red, a
#       tag that already exists, nothing to promote, unreachable origin, a
#       commit that is not origin/main's head (so it cannot be dispatched),
#       a non-success run/job/step, or a run that did not complete inside the
#       bounded wait
#   2 = misuse: unknown flag, contradictory flags (--dry-run/--execute,
#       --verify-ci/--execute, --verify-ci/--dry-run), bad --tag value,
#       missing tool
#
# WHY THIS EXISTS
#   Until this script the whole cut lived as prose in docs/releases.md, and the
#   prose was wrong in a way that shipped: the numbered procedure produced a git
#   tag but never a GitHub Release object, so `v0.1.0` sat tag-only from
#   2026-09-18 to 2026-09-20 — invisible to `gh release list` and to anyone on
#   the Releases tab (RELEASE-H3-002). A tag is not a Release. This driver
#   performs both, in order, and verifies the second one before it reports PASS.
#
# SAFETY MODEL
#   * DRY-RUN IS THE DEFAULT and is the path `make release` takes. Every
#     mutating step sits behind an explicit opt-in: `--execute` (the cut) or
#     `--verify-ci` (the workflow dispatch). A `workflow_dispatch` IS a
#     mutation — it starts real CI runs — so the dry-run only PRINTS what the
#     execute path would dispatch, on which sha (step 3).
#   * The dirty-work-tree refusal (step 1) is a CUT precondition, not a read
#     precondition: in dry-run a dirty tree is reported as a WARN and the run
#     continues, because a read-only report has nothing to refuse and blocking
#     it would make the safe path the unusable one. `--execute` REFUSES.
#   * A pushed tag is NEVER moved (docs/releases.md, "Tag convention"): the
#     driver refuses to reuse an existing tag instead of force-setting one.
#   * The changelog promote (step 6) is the only step that writes inside the
#     repo and it NEVER runs in dry-run, and never as part of `make verify`.
#
# STEPS (in order — the order is load-bearing)
#   1. refuse on a dirty work tree (--execute)
#   2. `make verify` — stop on non-zero, and assert the gate printed its own
#      `make verify: ALL PASS` line rather than trusting the exit code alone
#   3. establish CI green on the commit the tag will name (--execute; see
#      "CI ON HEAD" below) — dispatch both workflows, assert per-job/per-step,
#      print the cited run ids. Any non-success aborts before anything mutates.
#      In dry-run this step only PRINTS the dispatch plan: the dry-run never
#      dispatches.
#   4. compute the next version + its evidence: previous tag, commit count
#      since it, feat commits, breaking commits -> MAJOR / MINOR / PATCH
#   5. assert the proposed tag exists neither locally nor at origin
#   6. promote `[Unreleased]` into `[X.Y.Z]` and re-open an empty `[Unreleased]`
#      (--execute only), commit it, then re-run `make verify` so the commit the
#      tag lands on is a commit this driver has seen the gate pass on
#   7. `git tag -a` on that commit
#   8. `git push origin refs/tags/vX.Y.Z` — the tag only, never the branch
#   9. `gh release create` + `gh release view` (must exit 0)
#  10. print the rollback path (the previous tag)
#
# CI ON HEAD (RELEASE-H3-004)
#   Both push-triggered workflows are PATH-FILTERED on purpose (H3-PM-007):
#   pages.yml fires on docs/**, scripts/** and *.md; roundtrip.yml fires on
#   integration/roundtrip/** and its own file. A range that touches only
#   `.coding-hermes/board/**` or only `specs/**` therefore produces ZERO runs.
#   Consequences this driver encodes:
#     * An ABSENT push-event run is neither a red nor a green — it is
#       UNVERIFIED. Green on such a sha is established by an explicit
#       `workflow_dispatch`, which is exactly what step 3 does.
#     * A run-level `conclusion: success` is NOT evidence: pages.yml's
#       sibling-shim checkout carries `continue-on-error`, which a run-level
#       green hides. Step 3 therefore asserts that EVERY job concludes
#       `success` AND every step does too (a `skipped` step is reported and
#       tolerated, because it ran nothing; anything else fails the cut).
#     * `workflow_dispatch` always runs on a BRANCH HEAD, so the sha must be
#       origin/main's head. If it is not, step 3 FAILS loudly rather than
#       dispatching something else and citing it as this commit's green.
#     * The wait is BOUNDED (CI_MAX_POLLS x CI_POLL_INTERVAL, defaults 60 x 5s)
#       and it is never the only way to learn the result: each run id and URL
#       is printed the moment the run appears, BEFORE the wait starts, and a
#       timeout points at `gh run view <id>`. CI_DISCOVER_POLLS and
#       CI_RUN_LIST_LIMIT tune discovery and read-back.
#   Step 3 cites the sha the cut is based on. When the promote step (6) writes
#   a CHANGELOG commit, the tag names THAT commit, which is not on origin and
#   therefore cannot be dispatched; step 6 re-runs `make verify` on it and
#   prints the delta. To cite CI on the exact tagged sha, push main with the
#   [X.Y.Z] section already written and cut with `--no-changelog`.
#
# Zero dependencies beyond bash, git, make and coreutils. `gh` is required only
# by the execute and --verify-ci paths, and its absence is caught in the
# preflight — before anything is mutated.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

REPO_SLUG="get-h3/h3"
CHANGELOG_FILE="CHANGELOG.md"

EXECUTE=0
DRY_FLAG=0
VERIFY_CI=0
PROMOTE=1
REQUESTED_TAG=""

usage() {
    cat <<'EOF'
usage: bash scripts/release.sh [--dry-run] [--execute|--apply] [--verify-ci]
                               [--no-changelog] [--tag vX.Y.Z] [--help]

  (default)              dry-run: print the plan, mutate nothing (exit 0)
  --dry-run              the same, stated explicitly
  --execute, --apply     perform the cut (CI green on the commit, changelog
                         promote, annotated tag, tag-only push, GitHub Release
                         object + verification)
  --verify-ci            establish "CI green on HEAD" ONLY: dispatch both
                         workflows on HEAD, wait, assert per-job/per-step
                         success, print the cited run ids, exit. No tag, no
                         push, no cut
  --no-changelog         skip the CHANGELOG.md promote-and-reopen step
  --tag vX.Y.Z           override the proposed version
EOF
}

fail() {   # precondition failure -> 1
    echo "release: FAIL — $*" >&2
    exit 1
}

misuse() { # usage error -> 2
    echo "release: FAIL (misuse) — $*" >&2
    usage >&2
    exit 2
}

# --------------------------------------------------------------------------
# CI ON HEAD — dispatch both path-filtered workflows on one sha and assert
# PER-JOB and PER-STEP success (RELEASE-H3-004). See the header, "CI ON HEAD".
# A dispatch is a mutation, reachable only from --execute (step 3) and from
# --verify-ci; the dry-run never calls any of this.
# --------------------------------------------------------------------------
CI_WORKFLOWS="pages.yml roundtrip.yml"
CI_MAX_POLLS=${CI_MAX_POLLS:-60}            # polls per run before the wait gives up
CI_POLL_INTERVAL=${CI_POLL_INTERVAL:-5}     # seconds between polls
CI_DISCOVER_POLLS=${CI_DISCOVER_POLLS:-12}  # polls to wait for a dispatched run to appear
CI_RUN_LIST_LIMIT=${CI_RUN_LIST_LIMIT:-30}  # runs read back per workflow when matching headSha

# One workflow's runs filtered to one headSha: "<id> <event> <status> <conclusion>".
# `--jq` (gh's built-in) rather than `--template`: gh's Go templates render
# databaseId as a float — 3.5502402177e+10 is not a run id.
ci_runs_for_sha() {   # $1 = workflow file, $2 = sha
    [ -n "$2" ] || return 1
    gh run list --repo "$REPO_SLUG" --workflow "$1" --limit "$CI_RUN_LIST_LIMIT" \
        --json databaseId,headSha,status,conclusion,event \
        --jq '.[] | select(.headSha == "'"$2"'") | "\(.databaseId) \(.event) \(.status) \(.conclusion)"'
}

# Highest run id this workflow has already produced for $2 (0 when none) —
# the watermark that separates THIS dispatch from earlier runs on the same sha.
ci_max_run_id() {     # $1 = workflow file, $2 = sha
    local rows
    rows=$(ci_runs_for_sha "$1" "$2") || return 1
    if [ -z "$rows" ]; then echo 0; return 0; fi
    printf '%s\n' "$rows" | awk '{ if ($1+0 > m) m = $1+0 } END { printf "%d\n", m }'
}

# Newest workflow_dispatch run for $2 with an id above the pre-dispatch
# watermark $3. Prints the id, or returns 1 when none appeared in the window.
ci_find_new_run() {   # $1 = workflow file, $2 = sha, $3 = watermark
    local polls=0 rows id
    while :; do
        rows=$(ci_runs_for_sha "$1" "$2" 2>/dev/null || true)
        if [ -n "$rows" ]; then
            id=$(printf '%s\n' "$rows" | awk -v since="$3" \
                '$2 == "workflow_dispatch" && $1+0 > since+0 { printf "%d\n", $1; exit }')
            if [ -n "$id" ]; then printf '%s\n' "$id"; return 0; fi
        fi
        polls=$((polls + 1))
        if [ "$polls" -ge "$CI_DISCOVER_POLLS" ]; then
            echo "release: ci: $1 — no workflow_dispatch run on $2 appeared within $((CI_DISCOVER_POLLS * CI_POLL_INTERVAL))s" >&2
            return 1
        fi
        sleep "$CI_POLL_INTERVAL"
    done
}

# Diagnostic for a dispatch that produced no run for the intended sha: name the
# run it DID produce, so "it landed on a different commit" is visible.
ci_report_other_run() {   # $1 = workflow file, $2 = intended sha
    local rows
    rows=$(gh run list --repo "$REPO_SLUG" --workflow "$1" --limit 5 \
        --json databaseId,headSha,status,conclusion,event \
        --jq '.[] | select(.event == "workflow_dispatch") | "\(.databaseId) headSha=\(.headSha) \(.status)/\(.conclusion)"' 2>/dev/null || true)
    [ -n "$rows" ] || return 0
    printf 'release: ci:   newest workflow_dispatch run for %s: %s (intended sha was %s)\n' \
        "$1" "$(printf '%s' "$rows" | head -n 1)" "$2" >&2
}

# Human phrase for why $1 cannot be dispatched when origin/main is at $2.
ci_sha_relation() {   # $1 = intended sha, $2 = origin/main head
    if git cat-file -e "$2^{commit}" 2>/dev/null && git merge-base --is-ancestor "$2" "$1" 2>/dev/null; then
        printf 'this HEAD is %s commit(s) ahead of origin/main — those commits are not on any branch head' \
            "$(git rev-list --count "$2".."$1" 2>/dev/null)"
    elif git merge-base --is-ancestor "$1" "$2" 2>/dev/null; then
        printf 'origin/main is ahead of this checkout — pull it first'
    else
        printf 'the two are unrelated, or origin/main is not in this clone — fetch and re-check'
    fi
}

ci_dispatch() {       # $1 = workflow file
    local out
    if ! out=$(gh workflow run "$1" --repo "$REPO_SLUG" --ref main 2>&1); then
        fail "gh workflow run $1 --ref main failed: ${out:-<no output>} — no run was dispatched, so no CI green can be cited for this commit. Nothing was tagged, pushed or released."
    fi
    echo "release: ci: dispatched $1 (workflow_dispatch on ref main) — ${out:-ok}"
}

# Bounded wait. Sets CI_STATUS / CI_CONCLUSION; returns 1 on timeout, loudly,
# and never treats a still-running or unreadable run as green.
ci_wait_completed() {  # $1 = run id
    local polls=0 state
    CI_STATUS=unknown
    CI_CONCLUSION=""
    while :; do
        if state=$(gh run view "$1" --repo "$REPO_SLUG" --json status,conclusion \
                --jq '"\(.status) \(.conclusion)"' 2>/dev/null); then
            CI_STATUS=${state%% *}
            CI_CONCLUSION=${state#* }
            [ "$CI_STATUS" = "completed" ] && return 0
        fi
        polls=$((polls + 1))
        if [ "$polls" -ge "$CI_MAX_POLLS" ]; then
            echo "release: ci: TIMEOUT — run $1 is still ${CI_STATUS}/${CI_CONCLUSION:-reading} after $((polls * CI_POLL_INTERVAL))s. This is NOT a green: the run was left running, not cancelled. Read it later with: gh run view $1 --repo $REPO_SLUG" >&2
            return 1
        fi
        sleep "$CI_POLL_INTERVAL"
    done
}

# The evidence gate: the run must have run on the intended sha, concluded
# success, and have EVERY job and EVERY step at `success` (`skipped` steps are
# reported and tolerated — they ran nothing).
ci_assert_green() {   # $1 = workflow file, $2 = run id, $3 = intended sha
    local wf=$1 id=$2 sha=$3 run_sha jobs steps job_bad step_bad skipped \
        n_jobs n_steps
    run_sha=$(gh run view "$id" --repo "$REPO_SLUG" --json headSha --jq '.headSha') || \
        fail "could not read run $id back (gh run view failed) — a run this driver cannot read is UNVERIFIED, never green."
    if [ "$run_sha" != "$sha" ]; then
        fail "run $id ($wf) ran on headSha $run_sha, not on the intended $sha — workflow_dispatch always targets the branch head, so origin/main moved (or was never at $sha). Refusing to cite a different commit as green, and refusing to tag on this evidence. Nothing was tagged, pushed or released."
    fi
    if [ "$CI_CONCLUSION" != "success" ]; then
        fail "run $id ($wf) concluded '${CI_CONCLUSION:-none}' (status ${CI_STATUS:-unknown}) — NOT green. Read it with: gh run view $id --repo $REPO_SLUG. Nothing was tagged, pushed or released."
    fi
    jobs=$(gh run view "$id" --repo "$REPO_SLUG" --json jobs --jq '.jobs[] | "\(.name)|\(.conclusion)"') || \
        fail "could not read the jobs of run $id — a run whose jobs cannot be enumerated is UNVERIFIED, never green."
    steps=$(gh run view "$id" --repo "$REPO_SLUG" --json jobs \
        --jq '.jobs[] | .name as $j | .steps[] | "\($j)|\(.number)|\(.name)|\(.conclusion)"') || \
        fail "could not read the steps of run $id — a run whose steps cannot be enumerated is UNVERIFIED, never green."
    n_jobs=$(printf '%s\n' "$jobs" | grep -c . || true)
    n_steps=$(printf '%s\n' "$steps" | grep -c . || true)
    job_bad=$(printf '%s\n' "$jobs" | grep -v '|success$' || true)
    step_bad=$(printf '%s\n' "$steps" | grep -vE '\|(success|skipped)$' || true)
    skipped=$(printf '%s\n' "$steps" | grep -c '|skipped$' || true)
    if [ -n "$job_bad" ]; then
        printf '%s\n' "$job_bad" | sed 's/^/release: ci:   NON-SUCCESS JOB: /' >&2
        fail "run $id ($wf) has job(s) that did not conclude 'success' (above). A run-level green is NOT evidence — this workflow carries a continue-on-error step, which the run conclusion hides. Aborting: nothing was tagged, pushed or released."
    fi
    if [ -n "$step_bad" ]; then
        printf '%s\n' "$step_bad" | sed 's/^/release: ci:   NON-SUCCESS STEP: /' >&2
        fail "run $id ($wf) has step(s) that did not conclude 'success' (above; only 'skipped' is tolerated, because it ran nothing). A run-level green is NOT evidence. Aborting: nothing was tagged, pushed or released."
    fi
    echo "release: ci: $wf → run $id https://github.com/$REPO_SLUG/actions/runs/$id"
    echo "release: ci:   headSha $run_sha (the intended sha) · run conclusion success · $n_jobs job(s) all success · $n_steps step(s): $((n_steps - skipped)) success, $skipped skipped, 0 non-success"
}

# The whole capability: dispatch both workflows on $1, publish each run id as
# soon as it exists, then wait and assert. Returns 0 only when both runs are
# green per-job and per-step. Every failure path exits through `fail` (1).
ci_establish_green_on() {   # $1 = the sha to cite as CI-green
    local sha=$1 wf remote premax id runs="" cited=""
    remote=$(git ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1; exit}') || true
    if [ -z "$remote" ]; then
        fail "could not read origin's main head (git ls-remote origin refs/heads/main returned nothing) — workflow_dispatch targets a branch head, so whether $sha can be dispatched is UNKNOWN, not green. Check the network/credential and re-run. Nothing was dispatched."
    fi
    if [ "$remote" != "$sha" ]; then
        fail "cannot dispatch CI on $sha: 'gh workflow run --ref main' always runs on origin/main's head, which is $remote ($(ci_sha_relation "$sha" "$remote")). Green-on-a-commit cannot be established for a commit that is not a branch head — push main so the commit you intend to tag IS origin/main's head, then re-run. Nothing was dispatched, tagged, pushed or released."
    fi
    for wf in $CI_WORKFLOWS; do
        if ! premax=$(ci_max_run_id "$wf" "$sha"); then
            fail "could not list the existing $wf runs for $sha (gh run list failed) — refusing to dispatch blind: a run I cannot distinguish from an earlier one is not evidence."
        fi
        ci_dispatch "$wf"
        if ! id=$(ci_find_new_run "$wf" "$sha" "$premax"); then
            ci_report_other_run "$wf" "$sha"
            fail "no $wf run appeared for $sha within the discovery window — the dispatch was accepted but there is no run to cite. Nothing was tagged, pushed or released."
        fi
        echo "release: ci: $wf → run $id https://github.com/$REPO_SLUG/actions/runs/$id (cite this id; the wait below is not the only way to read it)"
        runs="${runs}${wf} ${id}
"
        cited="${cited}${wf}=${id} "
    done
    while read -r wf id; do
        [ -n "${wf:-}" ] || continue
        ci_wait_completed "$id" || \
            fail "the $wf run $id did not complete inside the bounded wait (see the TIMEOUT line above). Read it later with 'gh run view $id --repo $REPO_SLUG'. Nothing was tagged, pushed or released."
        ci_assert_green "$wf" "$id" "$sha"
    done <<EOF
$runs
EOF
    echo "release: ci: CI-GREEN on $sha — cited run ids: ${cited}(every job and step success)"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY_FLAG=1 ;;
        --execute|--apply) EXECUTE=1 ;;
        --verify-ci) VERIFY_CI=1 ;;
        --no-changelog) PROMOTE=0 ;;
        --tag) shift; [ "$#" -gt 0 ] || misuse "--tag needs a value"; REQUESTED_TAG=$1 ;;
        --tag=*) REQUESTED_TAG=${1#--tag=} ;;
        -h|--help) usage; exit 0 ;;
        *) misuse "unknown argument: $1" ;;
    esac
    shift
done

if [ "$EXECUTE" -eq 1 ] && [ "$DRY_FLAG" -eq 1 ]; then
    misuse "--dry-run and --execute are mutually exclusive"
fi
if [ "$VERIFY_CI" -eq 1 ] && [ "$DRY_FLAG" -eq 1 ]; then
    misuse "--verify-ci dispatches workflows (a mutation) so it cannot be combined with --dry-run, which must mutate nothing (see the SAFETY MODEL in the header)"
fi
if [ "$VERIFY_CI" -eq 1 ] && [ "$EXECUTE" -eq 1 ]; then
    misuse "--verify-ci performs no cut (dispatch + assert + report, then exit) so it cannot be combined with --execute; the cut already establishes CI green at step 3"
fi

if [ "$EXECUTE" -eq 1 ]; then
    MODE="execute"
elif [ "$VERIFY_CI" -eq 1 ]; then
    MODE="verify-ci"
else
    MODE="dry-run"
fi

if [ -n "$REQUESTED_TAG" ]; then
    # Exactly vX.Y.Z — rejected shapes: "1.2", "v1.2", "v1.2.3.4", "vX.Y.Z",
    # "v1.2.3-rc1". The bump logic reads the previous tag the same way, so an
    # override that does not parse could not be compared against it.
    if [[ ! $REQUESTED_TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        misuse "--tag must be exactly vX.Y.Z with digits (got '$REQUESTED_TAG')"
    fi
fi

# --------------------------------------------------------------------------
# 0. preflight — tools, work tree, and (for a cut or a CI dispatch) gh auth
# --------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || misuse "git not found"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || fail "$ROOT is not a git work tree"
command -v make >/dev/null 2>&1 || misuse "make not found — step 2 runs 'make verify'"

cd "$ROOT"

echo "release: mode: $MODE (repository: $ROOT, origin: $(git config --get remote.origin.url 2>/dev/null || echo '<none>'))"

if [ "$EXECUTE" -eq 1 ] || [ "$VERIFY_CI" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 || misuse "gh not found — step 3 (--execute) and --verify-ci dispatch the workflows, and step 9 publishes the GitHub Release object; install gh or use the dry-run"
    if ! gh auth status >/dev/null 2>&1; then
        fail "gh is installed but not authenticated (gh auth status failed) — CI cannot be dispatched or read back, and step 9 cannot publish the Release object. Run 'gh auth login', then re-run. Nothing was mutated."
    fi
fi

# --------------------------------------------------------------------------
# --verify-ci — the CI capability ALONE, then exit. No cut, no gate, no
# version logic, no changelog read: dispatch both workflows on HEAD, assert
# per-job/per-step, print the run ids. A dispatch is the only mutation.
# --------------------------------------------------------------------------
if [ "$VERIFY_CI" -eq 1 ]; then
    VERIFY_CI_SHA=$(git rev-parse HEAD) || fail "could not resolve HEAD"
    if [ -n "$REQUESTED_TAG" ] || [ "$PROMOTE" -eq 0 ]; then
        echo "release: verify-ci: NOTE — --tag / --no-changelog describe a cut, which this mode does not perform; they are ignored"
    fi
    echo "release: verify-ci: target sha $VERIFY_CI_SHA (HEAD) · workflows: $CI_WORKFLOWS · bounds: CI_MAX_POLLS=${CI_MAX_POLLS} x CI_POLL_INTERVAL=${CI_POLL_INTERVAL}s"
    echo "release: verify-ci: no cut is performed — no tag, no push, no CHANGELOG write, no gh release call"
    ci_establish_green_on "$VERIFY_CI_SHA"
    echo "release: verify-ci: PASS — CI is green on $VERIFY_CI_SHA (cited run ids above). Record them next to the tag sha; a tag alone does not carry this evidence."
    exit 0
fi

[ -f "$CHANGELOG_FILE" ] || fail "$CHANGELOG_FILE not found in $ROOT — the driver reads its [Unreleased] section for the promote step (6) and its [X.Y.Z] section for the Release notes (step 9). A release cannot be cut or planned without it; nothing was mutated."

VERIFY_LOG=$(mktemp -t h3-release-verify.XXXXXX) || fail "mktemp failed"
NOTES_FILE=""
cleanup() {
    rm -f "$VERIFY_LOG"
    [ -n "$NOTES_FILE" ] && rm -f "$NOTES_FILE"
    return 0
}
trap cleanup EXIT

# --------------------------------------------------------------------------
# 1. dirty work tree — a CUT precondition (see SAFETY MODEL)
# --------------------------------------------------------------------------
DIRTY=$(git status --porcelain) || fail "git status --porcelain failed"
if [ -n "$DIRTY" ]; then
    DIRTY_N=$(printf '%s\n' "$DIRTY" | wc -l | tr -d ' ')
    if [ "$EXECUTE" -eq 1 ]; then
        echo "release: step 1/10 dirty work tree — REFUSING to cut" >&2
        printf '%s\n' "$DIRTY" | sed 's/^/    /' >&2
        fail "work tree has $DIRTY_N changed path(s). A release is cut from a clean tree: the tag must name 'the commit where make verify exited 0' (docs/releases.md), and uncommitted content is not in any commit. Commit or discard them, then re-run."
    fi
    echo "release: step 1/10 work tree is DIRTY ($DIRTY_N path(s)) — a real cut (--execute) would REFUSE here. Dry-run continues: nothing is mutated, so there is nothing to refuse."
    printf '%s\n' "$DIRTY" | sed 's/^/release:           /'
else
    echo "release: step 1/10 clean work tree (git status --porcelain is empty)"
fi

# --------------------------------------------------------------------------
# 2. make verify — the gate, run for real
# --------------------------------------------------------------------------
echo "release: step 2/10 running 'make verify' (the real gate; a non-zero exit stops the release)"
if ! make verify 2>&1 | tee "$VERIFY_LOG"; then
    fail "'make verify' exited non-zero — the release is refused. Nothing was tagged, nothing was pushed, $CHANGELOG_FILE is untouched. Fix the guard output above."
fi
if ! grep -q '^make verify: ALL PASS' "$VERIFY_LOG"; then
    fail "'make verify' exited 0 but never printed its own 'make verify: ALL PASS' line — the gate's shape changed, so the exit code alone is not trustworthy. Refusing to tag a commit this driver cannot name as gate-green."
fi
echo "release: step 2/10 gate green — the 'make verify: ALL PASS' line above came from that real run (not from this script)"

# --------------------------------------------------------------------------
# 3. CI green on the commit the tag will name (RELEASE-H3-004)
# --------------------------------------------------------------------------
# Green-on-a-commit is NOT readable from the push history here: both workflows
# are path-filtered on purpose, so a board-only or specs-only range produces
# zero runs — absence is UNVERIFIED, neither red nor green. Green is
# established by an explicit dispatch, and a run-level `success` is not the
# evidence (pages.yml carries a continue-on-error step) — every JOB and every
# STEP must be `success`. See the header, "CI ON HEAD".
CI_SHA=$(git rev-parse HEAD) || fail "could not resolve HEAD — the CI step must name the commit the tag will name"

if [ "$EXECUTE" -eq 0 ]; then
    echo "release: step 3/10 CI green on $CI_SHA — DRY-RUN: nothing is dispatched (a workflow_dispatch is a mutation, so it sits behind --execute or --verify-ci)"
    for wf in $CI_WORKFLOWS; do
        echo "release: step 3/10 (execute only) would run: gh workflow run $wf --repo $REPO_SLUG --ref main"
    done
    echo "release: step 3/10 (execute only) would then assert PER-JOB and PER-STEP success on the run dispatched for $CI_SHA and print the cited run ids"
    echo "release: step 3/10 the per-job rule is the point: pages.yml's sibling-shim checkout carries continue-on-error, so a run-level 'success' hides a failed step"
    REMOTE_MAIN=$(git ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1; exit}') || true
    if [ -z "$REMOTE_MAIN" ]; then
        echo "release: step 3/10 WARN — origin unreachable: whether $CI_SHA can be dispatched is UNVERIFIED (--execute would refuse there)"
    elif [ "$REMOTE_MAIN" != "$CI_SHA" ]; then
        echo "release: step 3/10 WARN — origin/main is at $REMOTE_MAIN, not $CI_SHA ($(ci_sha_relation "$CI_SHA" "$REMOTE_MAIN")): --execute would REFUSE at this step, because workflow_dispatch only ever runs on a branch head"
    else
        echo "release: step 3/10 dispatchable — $CI_SHA is origin/main's head, so --execute would dispatch both workflows on it and cite the run ids"
    fi
else
    echo "release: step 3/10 establishing CI green on $CI_SHA (dispatch both workflows + per-job/per-step assert; bounded wait)"
    ci_establish_green_on "$CI_SHA"
    echo "release: step 3/10 CI is green on $CI_SHA per-job and per-step — cite the run ids above with the tag and record them on the board"
fi

# --------------------------------------------------------------------------
# 4. version evidence + the proposed tag
# --------------------------------------------------------------------------
if ! PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null); then
    fail "no tag is reachable from HEAD (git describe --tags --abbrev=0 found none) — there is no previous release to bump from. Cut the first tag by hand, then re-run."
fi
[ -n "$PREV_TAG" ] || fail "git describe --tags --abbrev=0 returned an empty tag name"

if [[ $PREV_TAG =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    PREV_MAJOR=${BASH_REMATCH[1]}
    PREV_MINOR=${BASH_REMATCH[2]}
    PREV_PATCH=${BASH_REMATCH[3]}
else
    fail "the previous tag '$PREV_TAG' is not vX.Y.Z — refusing to guess a bump from it."
fi

COMMIT_COUNT=$(git rev-list --count "$PREV_TAG"..HEAD) || fail "could not count commits since $PREV_TAG"
FEAT_COUNT=$(git log "$PREV_TAG"..HEAD --format=%s | grep -cE '^(feat|feature)(\([^)]*\))?!?:' || true)
# Breaking changes: count COMMITS, not matching lines, and dedupe by sha — a
# single commit may carry both the `type!:` subject form and a BREAKING CHANGE
# footer, and a body line would otherwise be counted as a second commit (the
# bump decision was right either way; the evidence number was not).
BREAKING_SHAS=$(
    {
        git log "$PREV_TAG"..HEAD --format='%H %s' | grep -E '^[0-9a-f]+ [a-z]+(\([^)]*\))?!:' | cut -d' ' -f1 || true
        git log "$PREV_TAG"..HEAD --format=%H --grep='BREAKING CHANGE' --grep='BREAKING-CHANGE' || true
    } | sed '/^$/d' | sort -u
) || fail "could not inspect the commit range $PREV_TAG..HEAD"
BREAKING_COUNT=$(printf '%s\n' "$BREAKING_SHAS" | grep -c . || true)
FEAT_COUNT=${FEAT_COUNT:-0}
BREAKING_COUNT=${BREAKING_COUNT:-0}

if [ "$BREAKING_COUNT" -gt 0 ]; then
    BUMP="MAJOR"
    NEW_MAJOR=$((PREV_MAJOR + 1)); NEW_MINOR=0; NEW_PATCH=0
    BUMP_WHY="$BREAKING_COUNT breaking commit(s) in range"
elif [ "$FEAT_COUNT" -gt 0 ]; then
    BUMP="MINOR"
    NEW_MAJOR=$PREV_MAJOR; NEW_MINOR=$((PREV_MINOR + 1)); NEW_PATCH=0
    BUMP_WHY="$FEAT_COUNT feat commit(s) in range and no breaking change"
else
    BUMP="PATCH"
    NEW_MAJOR=$PREV_MAJOR; NEW_MINOR=$PREV_MINOR; NEW_PATCH=$((PREV_PATCH + 1))
    BUMP_WHY="no feat and no breaking commit in range"
fi

PROPOSED_TAG="v$NEW_MAJOR.$NEW_MINOR.$NEW_PATCH"
RELEASE_TAG=${REQUESTED_TAG:-$PROPOSED_TAG}
RELEASE_SECTION=${RELEASE_TAG#v}
TODAY=$(date +%Y-%m-%d)

echo "release: step 4/10 version evidence:"
echo "release: previous tag: $PREV_TAG"
echo "release: commits since $PREV_TAG: $COMMIT_COUNT"
echo "release: feat commits since $PREV_TAG: $FEAT_COUNT"
echo "release: breaking commits since $PREV_TAG: $BREAKING_COUNT"
echo "release: version bump: $BUMP ($BUMP_WHY)"
echo "release: proposed tag: $PROPOSED_TAG"
if [ -n "$REQUESTED_TAG" ] && [ "$REQUESTED_TAG" != "$PROPOSED_TAG" ]; then
    echo "release: NOTE — --tag overrides the proposal: cutting $RELEASE_TAG (proposal was $PROPOSED_TAG)"
fi

# --------------------------------------------------------------------------
# 5. the tag must not exist — a tag is NEVER moved
# --------------------------------------------------------------------------
if git rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null 2>&1; then
    fail "tag $RELEASE_TAG already exists in this clone — a pushed tag is never moved, so the release is refused. Cut the next version instead (a mistake is a new tag)."
fi

REMOTE_TAGS=""
REMOTE_OK=1
if ! REMOTE_TAGS=$(git ls-remote --tags origin "refs/tags/$RELEASE_TAG" 2>/dev/null); then
    REMOTE_OK=0
    if [ "$EXECUTE" -eq 1 ]; then
        fail "could not reach origin to prove that tag $RELEASE_TAG is unused — refusing to cut a tag whose remote existence is UNVERIFIED. Check the network/credential and re-run; nothing was mutated."
    fi
    echo "release: step 5/10 WARN — could not reach origin: tag $RELEASE_TAG local-absence verified, REMOTE absence UNVERIFIED (dry-run continues; --execute refuses here)"
fi
if [ "$REMOTE_OK" -eq 1 ]; then
    if [ -n "$REMOTE_TAGS" ]; then
        fail "tag $RELEASE_TAG already exists at origin: $(printf '%s' "$REMOTE_TAGS" | tr '\n' ' ')— a tag is never moved. Cut the next version instead."
    fi
    echo "release: step 5/10 tag $RELEASE_TAG is unused (absent locally and at origin)"
else
    echo "release: step 5/10 tag $RELEASE_TAG is unused locally"
fi

# --------------------------------------------------------------------------
# 6. changelog: promote [Unreleased] -> [X.Y.Z], re-open an empty [Unreleased]
# --------------------------------------------------------------------------
# Pure file transform, so it is testable and so a dry-run can describe it
# without touching the file. Prints nothing; returns non-zero on a shape it
# does not recognise (no [Unreleased] heading, or a promote that did not land).
promote_changelog() {   # $1 = file, $2 = section version (X.Y.Z), $3 = date
    local file=$1 ver=$2 day=$3 tmp
    tmp=$(mktemp) || return 1
    if ! awk -v ver="$ver" -v day="$day" '
        BEGIN { done = 0 }
        /^## \[Unreleased\]/ && !done {
            print "## [Unreleased] — " day
            print ""
            print "Nothing yet."
            print ""
            print "## [" ver "] — " day
            done = 1
            next
        }
        { print }
    ' "$file" > "$tmp"; then
        rm -f "$tmp"; return 1
    fi
    if [ "$(grep -c '^## \[Unreleased\]' "$tmp" || true)" -ne 1 ]; then
        rm -f "$tmp"; return 1
    fi
    if ! grep -q "^## \[$ver\] — $day" "$tmp"; then
        rm -f "$tmp"; return 1
    fi
    # cp (not mv) keeps the destination's mode — CHANGELOG.md must not become 0600.
    if ! cp "$tmp" "$file"; then rm -f "$tmp"; return 1; fi
    rm -f "$tmp"
    return 0
}

# Prints the body of one `## [X]` section (heading included), banner-style.
extract_section() {   # $1 = section version (X.Y.Z)
    awk -v v="$1" '
        f && /^## \[/ { exit }
        /^## \[/ {
            if (index($0, "[" v "]") == 4) { f = 1; print; next }
            f = 0; next
        }
        f
    ' "$CHANGELOG_FILE"
}

UNRELEASED_BODY=$(awk '/^## \[Unreleased\]/ { f=1; next } /^## \[/ { f=0 } f' "$CHANGELOG_FILE") || \
    fail "could not read the [Unreleased] section of $CHANGELOG_FILE"
HAS_SUBSTANCE=0
if printf '%s\n' "$UNRELEASED_BODY" | grep -qvE '^[[:space:]]*$|^Nothing yet\.?$'; then
    HAS_SUBSTANCE=1
fi

if [ "$PROMOTE" -eq 1 ]; then
    echo "release: step 6/10 changelog: promote '## [Unreleased]' -> '## [$RELEASE_SECTION] — $TODAY' and re-open an empty '## [Unreleased] — $TODAY' above it"
    if [ "$HAS_SUBSTANCE" -eq 0 ]; then
        echo "release: step 6/10 WARN — $CHANGELOG_FILE's [Unreleased] section has no substance ('Nothing yet.')" >&2
        if [ "$EXECUTE" -eq 1 ]; then
            fail "$CHANGELOG_FILE has nothing to promote: promoting '$RELEASE_SECTION' would publish an empty release section. Write the entries first, or pass --no-changelog if the [$RELEASE_SECTION] section already exists by hand. Nothing was mutated."
        fi
        echo "release: step 6/10 WARN — a real cut would REFUSE here until [Unreleased] carries entries"
    fi
else
    echo "release: step 6/10 changelog: SKIPPED (--no-changelog) — expecting an existing '## [$RELEASE_SECTION]' section to use as the Release notes"
fi

# --------------------------------------------------------------------------
# 7-9. MUTATING STEPS — only ever reachable behind --execute
# --------------------------------------------------------------------------
if [ "$EXECUTE" -eq 0 ]; then
    echo "release: step 7/10 (execute only) would run: git tag -a $RELEASE_TAG -m 'H3 umbrella $RELEASE_TAG'"
    echo "release: step 8/10 (execute only) would run: git push origin refs/tags/$RELEASE_TAG   (tag only — never the branch)"
    echo "release: step 9/10 (execute only) would run: gh release create $RELEASE_TAG --title $RELEASE_TAG --notes-file <$CHANGELOG_FILE [$RELEASE_SECTION] section> --repo $REPO_SLUG"
    echo "release: step 9/10 (execute only) would then verify: gh release view $RELEASE_TAG --repo $REPO_SLUG   (must exit 0)"
    echo "release: step 10/10 rollback anchor: the previous tag, $PREV_TAG (a pushed tag is never moved — a mistake is a new tag)"
    echo "release: CI CITATION (dry-run) — the tagged commit would be the promote commit of step 6, one commit AFTER the step-3 dispatch target $CI_SHA. Push main with the [$RELEASE_SECTION] section written and cut with --no-changelog to cite CI on the exact tagged sha."
    echo "release: DRY-RUN COMPLETE — 0 mutations: no tag created, nothing pushed, $CHANGELOG_FILE byte-identical, no gh call made, no workflow dispatched."
    echo "release: PASS (dry-run) — the plan above is gate-green and coherent; re-run with --execute to perform the cut."
    exit 0
fi

# --- step 6 (cont.): commit the promoted changelog, then re-verify ----------
if [ "$PROMOTE" -eq 1 ]; then
    if ! promote_changelog "$CHANGELOG_FILE" "$RELEASE_SECTION" "$TODAY"; then
        fail "could not promote $CHANGELOG_FILE to [$RELEASE_SECTION] (unexpected section shape) — nothing was tagged. Nothing else was mutated."
    fi
    if ! grep -q '^## \[Unreleased\]' "$CHANGELOG_FILE"; then
        fail "post-promote check failed: $CHANGELOG_FILE has no [Unreleased] section. Restore it with 'git checkout -- $CHANGELOG_FILE'."
    fi
    git add -- "$CHANGELOG_FILE"
    if git diff --cached --quiet -- "$CHANGELOG_FILE"; then
        fail "$CHANGELOG_FILE was not changed by the promote — refusing to continue with an unexplained no-op."
    fi
    git commit -m "docs(changelog): promote [$RELEASE_SECTION] and re-open [Unreleased] ($RELEASE_TAG)" -- "$CHANGELOG_FILE"
    echo "release: step 6/10 changelog committed — re-running 'make verify' so the tag lands on a commit the gate has passed on"
    if ! make verify 2>&1 | tee "$VERIFY_LOG"; then
        fail "'make verify' exited non-zero on the changelog commit — refusing to tag it. The changelog commit is in place; fix the guard and re-run."
    fi
    grep -q '^make verify: ALL PASS' "$VERIFY_LOG" || \
        fail "'make verify' passed the changelog commit without printing 'make verify: ALL PASS' — refusing to tag it."
    echo "release: step 6/10 changelog commit is gate-green"
fi

# --- step 3 (cont.): state exactly which commit the CI citation covers -------
# The citation must never overstate itself: when the promote step created a
# commit, the tag names a sha the dispatch did NOT run on (it is not on origin,
# and workflow_dispatch only ever runs on a branch head). Say so, with the
# measured delta, instead of letting the two run ids imply more than they say.
TO_TAG_SHA=$(git rev-parse HEAD) || fail "could not resolve HEAD before tagging"
if [ "$TO_TAG_SHA" = "$CI_SHA" ]; then
    echo "release: step 3/10 CI citation: the tag names $TO_TAG_SHA — the same sha the step-3 dispatch runs were read on. The cited run ids are this commit's green."
else
    CI_DELTA=$(git diff --name-only "$CI_SHA".."$TO_TAG_SHA" | tr '\n' ' ' || true)
    echo "release: step 3/10 CI citation: the tag names $TO_TAG_SHA, which is the CI-cited $CI_SHA plus the promote commit (changed path(s): ${CI_DELTA:-<none>})."
    echo "release: step 3/10 CI citation: $TO_TAG_SHA is verified by 'make verify' (step 6) but NOT by a dispatch — workflow_dispatch runs on a branch head only, and this driver never pushes the branch. To cite CI on the exact tagged sha: push main with the [$RELEASE_SECTION] section written and cut with --no-changelog."
fi

# --- step 7: annotated tag ------------------------------------------------
if ! git tag -a "$RELEASE_TAG" -m "H3 umbrella $RELEASE_TAG — annotated tag on a commit where 'make verify' exits 0 (see $CHANGELOG_FILE and docs/releases.md)."; then
    fail "'git tag -a $RELEASE_TAG' failed — no tag was created." 
fi
TAG_SHA=$(git rev-list -n 1 "$RELEASE_TAG") || fail "created tag $RELEASE_TAG but could not resolve its commit sha"
echo "release: step 7/10 created annotated tag $RELEASE_TAG at $TAG_SHA"

# --- step 8: push the tag only --------------------------------------------
echo "release: step 8/10 pushing the tag only (refs/tags/$RELEASE_TAG — never the branch)"
if ! git push origin "refs/tags/$RELEASE_TAG"; then
    fail "git push origin refs/tags/$RELEASE_TAG failed. The local tag $RELEASE_TAG exists; re-run the push or delete it with 'git tag -d $RELEASE_TAG'. Nothing else was mutated."
fi

# --- step 9: the GitHub Release object ------------------------------------
NOTES_FILE=$(mktemp -t "h3-release-notes-${RELEASE_TAG}.XXXXXX") || fail "mktemp failed for the Release notes"
extract_section "$RELEASE_SECTION" > "$NOTES_FILE" || fail "could not extract the [$RELEASE_SECTION] section from $CHANGELOG_FILE for the Release notes"
if ! grep -qvE '^[[:space:]]*$' "$NOTES_FILE"; then
    fail "the [$RELEASE_SECTION] section of $CHANGELOG_FILE is empty — refusing to publish a Release with empty notes. The tag is pushed; write the section, then re-run with '--no-changelog' or publish the Release by hand."
fi
echo "release: step 9/10 Release notes ($(wc -l < "$NOTES_FILE" | tr -d ' ') lines) taken from $CHANGELOG_FILE [$RELEASE_SECTION]"
if ! gh release create "$RELEASE_TAG" --title "$RELEASE_TAG" --notes-file "$NOTES_FILE" --repo "$REPO_SLUG"; then
    fail "gh release create failed. The tag $RELEASE_TAG is pushed and is NOT moved; publish the Release object by hand (gh release create $RELEASE_TAG --title $RELEASE_TAG --repo $REPO_SLUG) — the cut is incomplete until it exists."
fi
if ! gh release view "$RELEASE_TAG" --repo "$REPO_SLUG" >/dev/null; then
    fail "gh release create ran but 'gh release view $RELEASE_TAG' does not exit 0 — the Release object is UNVERIFIED. Verify by hand before recording the cut as done."
fi
echo "release: step 9/10 GitHub Release object published and verified (gh release view $RELEASE_TAG exits 0)"

# --- step 10: rollback path ------------------------------------------------
echo "release: step 10/10 rollback anchor: the previous tag, $PREV_TAG"
echo "release: step 10/10 a pushed tag is never moved. To withdraw an UNPUBLISHED cut: 'git tag -d $RELEASE_TAG' (local only). If the Release object exists: 'gh release delete $RELEASE_TAG --yes' then delete the pushed tag. A published release is superseded by the NEXT tag, not rewritten — consumers roll back by pinning $PREV_TAG."
echo "release: PASS — $RELEASE_TAG tagged at $TAG_SHA, pushed tag-only, Release object published and verified. Record the tag sha and the Release URL on the cross-repo board (docs/releases.md, step 7)."
