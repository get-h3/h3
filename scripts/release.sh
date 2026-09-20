#!/usr/bin/env bash
# release.sh — the H3 umbrella RELEASE DRIVER (RELEASE-H3-003).
#
# Usage:
#   bash scripts/release.sh [--dry-run] [--execute|--apply] [--no-changelog]
#                           [--tag vX.Y.Z] [--help]
#
#   (no flag) / --dry-run   DEFAULT. Report what a cut WOULD do and prove the
#                           gate is green. Mutates nothing: no tag, no push, no
#                           CHANGELOG write, no `gh` call.
#   --execute / --apply     Perform the cut, in the order below. This is the
#                           ONLY flag that mutates anything.
#   --no-changelog          Skip the CHANGELOG promote step (execute mode). Use
#                           when the [X.Y.Z] section was written by hand.
#   --tag vX.Y.Z            Override the proposed version. Still checked for
#                           existence; still cut from a clean verified tree.
#
# Exit codes (the convention the sibling guards use):
#   0 = ok — dry-run reported a coherent, gate-green plan / execute completed
#       and the GitHub Release object was verified with `gh release view`
#   1 = a release PRECONDITION failed: dirty work tree, `make verify` red, a
#       tag that already exists, nothing to promote, unreachable origin
#   2 = misuse: unknown flag, contradictory flags, bad --tag value, missing tool
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
#     mutating step sits behind the single `--execute` opt-in.
#   * The dirty-work-tree refusal (step 1) is a CUT precondition, not a read
#     precondition: in dry-run a dirty tree is reported as a WARN and the run
#     continues, because a read-only report has nothing to refuse and blocking
#     it would make the safe path the unusable one. `--execute` REFUSES.
#   * A pushed tag is NEVER moved (docs/releases.md, "Tag convention"): the
#     driver refuses to reuse an existing tag instead of force-setting one.
#   * The changelog promote (step 5) is the only step that writes inside the
#     repo and it NEVER runs in dry-run, and never as part of `make verify`.
#
# STEPS (in order — the order is load-bearing)
#   1. refuse on a dirty work tree (--execute)
#   2. `make verify` — stop on non-zero, and assert the gate printed its own
#      `make verify: ALL PASS` line rather than trusting the exit code alone
#   3. compute the next version + its evidence: previous tag, commit count
#      since it, feat commits, breaking commits -> MAJOR / MINOR / PATCH
#   4. assert the proposed tag exists neither locally nor at origin
#   5. promote `[Unreleased]` into `[X.Y.Z]` and re-open an empty `[Unreleased]`
#      (--execute only), commit it, then re-run `make verify` so the commit the
#      tag lands on is a commit this driver has seen the gate pass on
#   6. `git tag -a` on that commit
#   7. `git push origin refs/tags/vX.Y.Z` — the tag only, never the branch
#   8. `gh release create` + `gh release view` (must exit 0)
#   9. print the rollback path (the previous tag)
#
# Zero dependencies beyond bash, git, make and coreutils. `gh` is required only
# by the execute path, and its absence is caught in the preflight — before
# anything is mutated.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

REPO_SLUG="get-h3/h3"
CHANGELOG_FILE="CHANGELOG.md"

EXECUTE=0
DRY_FLAG=0
PROMOTE=1
REQUESTED_TAG=""

usage() {
    cat <<'EOF'
usage: bash scripts/release.sh [--dry-run] [--execute|--apply] [--no-changelog]
                               [--tag vX.Y.Z] [--help]

  (default)              dry-run: print the plan, mutate nothing (exit 0)
  --dry-run              the same, stated explicitly
  --execute, --apply     perform the cut (changelog promote, annotated tag,
                         tag-only push, GitHub Release object + verification)
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

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY_FLAG=1 ;;
        --execute|--apply) EXECUTE=1 ;;
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

if [ "$EXECUTE" -eq 1 ]; then
    MODE="execute"
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
# 0. preflight — tools, work tree, and (for a real cut) gh auth
# --------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || misuse "git not found"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || fail "$ROOT is not a git work tree"
command -v make >/dev/null 2>&1 || misuse "make not found — step 2 runs 'make verify'"

cd "$ROOT"

[ -f "$CHANGELOG_FILE" ] || fail "$CHANGELOG_FILE not found in $ROOT — the driver reads its [Unreleased] section for the promote step (5) and its [X.Y.Z] section for the Release notes (step 8). A release cannot be cut or planned without it; nothing was mutated."

echo "release: mode: $MODE (repository: $ROOT, origin: $(git config --get remote.origin.url 2>/dev/null || echo '<none>'))"

if [ "$EXECUTE" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 || misuse "gh not found — step 8 publishes the GitHub Release object; install gh or use the dry-run"
    if ! gh auth status >/dev/null 2>&1; then
        fail "gh is installed but not authenticated (gh auth status failed) — step 8 cannot publish the Release object. Run 'gh auth login', then re-run. Nothing was mutated."
    fi
fi

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
        echo "release: step 1/9 dirty work tree — REFUSING to cut" >&2
        printf '%s\n' "$DIRTY" | sed 's/^/    /' >&2
        fail "work tree has $DIRTY_N changed path(s). A release is cut from a clean tree: the tag must name 'the commit where make verify exited 0' (docs/releases.md), and uncommitted content is not in any commit. Commit or discard them, then re-run."
    fi
    echo "release: step 1/9 work tree is DIRTY ($DIRTY_N path(s)) — a real cut (--execute) would REFUSE here. Dry-run continues: nothing is mutated, so there is nothing to refuse."
    printf '%s\n' "$DIRTY" | sed 's/^/release:           /'
else
    echo "release: step 1/9 clean work tree (git status --porcelain is empty)"
fi

# --------------------------------------------------------------------------
# 2. make verify — the gate, run for real
# --------------------------------------------------------------------------
echo "release: step 2/9 running 'make verify' (the real gate; a non-zero exit stops the release)"
if ! make verify 2>&1 | tee "$VERIFY_LOG"; then
    fail "'make verify' exited non-zero — the release is refused. Nothing was tagged, nothing was pushed, $CHANGELOG_FILE is untouched. Fix the guard output above."
fi
if ! grep -q '^make verify: ALL PASS' "$VERIFY_LOG"; then
    fail "'make verify' exited 0 but never printed its own 'make verify: ALL PASS' line — the gate's shape changed, so the exit code alone is not trustworthy. Refusing to tag a commit this driver cannot name as gate-green."
fi
echo "release: step 2/9 gate green — the 'make verify: ALL PASS' line above came from that real run (not from this script)"

# --------------------------------------------------------------------------
# 3. version evidence + the proposed tag
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

echo "release: step 3/9 version evidence:"
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
# 4. the tag must not exist — a tag is NEVER moved
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
    echo "release: step 4/9 WARN — could not reach origin: tag $RELEASE_TAG local-absence verified, REMOTE absence UNVERIFIED (dry-run continues; --execute refuses here)"
fi
if [ "$REMOTE_OK" -eq 1 ]; then
    if [ -n "$REMOTE_TAGS" ]; then
        fail "tag $RELEASE_TAG already exists at origin: $(printf '%s' "$REMOTE_TAGS" | tr '\n' ' ')— a tag is never moved. Cut the next version instead."
    fi
    echo "release: step 4/9 tag $RELEASE_TAG is unused (absent locally and at origin)"
else
    echo "release: step 4/9 tag $RELEASE_TAG is unused locally"
fi

# --------------------------------------------------------------------------
# 5. changelog: promote [Unreleased] -> [X.Y.Z], re-open an empty [Unreleased]
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
    echo "release: step 5/9 changelog: promote '## [Unreleased]' -> '## [$RELEASE_SECTION] — $TODAY' and re-open an empty '## [Unreleased] — $TODAY' above it"
    if [ "$HAS_SUBSTANCE" -eq 0 ]; then
        echo "release: step 5/9 WARN — $CHANGELOG_FILE's [Unreleased] section has no substance ('Nothing yet.')" >&2
        if [ "$EXECUTE" -eq 1 ]; then
            fail "$CHANGELOG_FILE has nothing to promote: promoting '$RELEASE_SECTION' would publish an empty release section. Write the entries first, or pass --no-changelog if the [$RELEASE_SECTION] section already exists by hand. Nothing was mutated."
        fi
        echo "release: step 5/9 WARN — a real cut would REFUSE here until [Unreleased] carries entries"
    fi
else
    echo "release: step 5/9 changelog: SKIPPED (--no-changelog) — expecting an existing '## [$RELEASE_SECTION]' section to use as the Release notes"
fi

# --------------------------------------------------------------------------
# 6-8. MUTATING STEPS — only ever reachable behind --execute
# --------------------------------------------------------------------------
if [ "$EXECUTE" -eq 0 ]; then
    echo "release: step 6/9 (execute only) would run: git tag -a $RELEASE_TAG -m 'H3 umbrella $RELEASE_TAG'"
    echo "release: step 7/9 (execute only) would run: git push origin refs/tags/$RELEASE_TAG   (tag only — never the branch)"
    echo "release: step 8/9 (execute only) would run: gh release create $RELEASE_TAG --title $RELEASE_TAG --notes-file <$CHANGELOG_FILE [$RELEASE_SECTION] section> --repo $REPO_SLUG"
    echo "release: step 8/9 (execute only) would then verify: gh release view $RELEASE_TAG --repo $REPO_SLUG   (must exit 0)"
    echo "release: step 9/9 rollback anchor: the previous tag, $PREV_TAG (a pushed tag is never moved — a mistake is a new tag)"
    echo "release: DRY-RUN COMPLETE — 0 mutations: no tag created, nothing pushed, $CHANGELOG_FILE byte-identical, no gh call made."
    echo "release: PASS (dry-run) — the plan above is gate-green and coherent; re-run with --execute to perform the cut."
    exit 0
fi

# --- step 5 (cont.): commit the promoted changelog, then re-verify ----------
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
    echo "release: step 5/9 changelog committed — re-running 'make verify' so the tag lands on a commit the gate has passed on"
    if ! make verify 2>&1 | tee "$VERIFY_LOG"; then
        fail "'make verify' exited non-zero on the changelog commit — refusing to tag it. The changelog commit is in place; fix the guard and re-run."
    fi
    grep -q '^make verify: ALL PASS' "$VERIFY_LOG" || \
        fail "'make verify' passed the changelog commit without printing 'make verify: ALL PASS' — refusing to tag it."
    echo "release: step 5/9 changelog commit is gate-green"
fi

# --- step 6: annotated tag ------------------------------------------------
if ! git tag -a "$RELEASE_TAG" -m "H3 umbrella $RELEASE_TAG — annotated tag on a commit where 'make verify' exits 0 (see $CHANGELOG_FILE and docs/releases.md)."; then
    fail "'git tag -a $RELEASE_TAG' failed — no tag was created." 
fi
TAG_SHA=$(git rev-list -n 1 "$RELEASE_TAG") || fail "created tag $RELEASE_TAG but could not resolve its commit sha"
echo "release: step 6/9 created annotated tag $RELEASE_TAG at $TAG_SHA"

# --- step 7: push the tag only --------------------------------------------
echo "release: step 7/9 pushing the tag only (refs/tags/$RELEASE_TAG — never the branch)"
if ! git push origin "refs/tags/$RELEASE_TAG"; then
    fail "git push origin refs/tags/$RELEASE_TAG failed. The local tag $RELEASE_TAG exists; re-run the push or delete it with 'git tag -d $RELEASE_TAG'. Nothing else was mutated."
fi

# --- step 8: the GitHub Release object ------------------------------------
NOTES_FILE=$(mktemp -t "h3-release-notes-${RELEASE_TAG}.XXXXXX") || fail "mktemp failed for the Release notes"
extract_section "$RELEASE_SECTION" > "$NOTES_FILE" || fail "could not extract the [$RELEASE_SECTION] section from $CHANGELOG_FILE for the Release notes"
if ! grep -qvE '^[[:space:]]*$' "$NOTES_FILE"; then
    fail "the [$RELEASE_SECTION] section of $CHANGELOG_FILE is empty — refusing to publish a Release with empty notes. The tag is pushed; write the section, then re-run with '--no-changelog' or publish the Release by hand."
fi
echo "release: step 8/9 Release notes ($(wc -l < "$NOTES_FILE" | tr -d ' ') lines) taken from $CHANGELOG_FILE [$RELEASE_SECTION]"
if ! gh release create "$RELEASE_TAG" --title "$RELEASE_TAG" --notes-file "$NOTES_FILE" --repo "$REPO_SLUG"; then
    fail "gh release create failed. The tag $RELEASE_TAG is pushed and is NOT moved; publish the Release object by hand (gh release create $RELEASE_TAG --title $RELEASE_TAG --repo $REPO_SLUG) — the cut is incomplete until it exists."
fi
if ! gh release view "$RELEASE_TAG" --repo "$REPO_SLUG" >/dev/null; then
    fail "gh release create ran but 'gh release view $RELEASE_TAG' does not exit 0 — the Release object is UNVERIFIED. Verify by hand before recording the cut as done."
fi
echo "release: step 8/9 GitHub Release object published and verified (gh release view $RELEASE_TAG exits 0)"

# --- step 9: rollback path -------------------------------------------------
echo "release: step 9/9 rollback anchor: the previous tag, $PREV_TAG"
echo "release: step 9/9 a pushed tag is never moved. To withdraw an UNPUBLISHED cut: 'git tag -d $RELEASE_TAG' (local only). If the Release object exists: 'gh release delete $RELEASE_TAG --yes' then delete the pushed tag. A published release is superseded by the NEXT tag, not rewritten — consumers roll back by pinning $PREV_TAG."
echo "release: PASS — $RELEASE_TAG tagged at $TAG_SHA, pushed tag-only, Release object published and verified. Record the tag sha and the Release URL on the cross-repo board (docs/releases.md, step 6)."
