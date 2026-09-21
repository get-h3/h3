# H3 Release Guide — Pinning and Verifying a Tagged Release

The umbrella repo (`get-h3/h3`) holds the specs, the cross-repo task board and
the docs guards. Its release tags are the anchors a consumer pins to: a tag names
one verified commit, so a fresh install has a fixed starting point and a
regression can be bisected with `git bisect` between two tags.

## Tag convention

- **Form:** `vX.Y.Z` (semver) — `v0.1.0`, `v0.2.0`, …
- **Kind:** annotated (`git tag -a`), so the release note travels with the tag.
- **Where:** cut on `main`, at a commit where `make verify` exits 0.
- **When:** at each docs-shipped milestone. A pushed tag is never moved — a
  mistake is a new tag, not a moved one.
- **Not the protocol version:** the changelog entry `[1.0.0] — 2026-07-19` is the
  protocol v1.0.0 record (`get-h3/protocol`); it is not an umbrella tag.

## Tags

| Tag | Date | Notes |
|-----|------|-------|
| `v0.1.0` | 2026-09-18 | First tagged release of the umbrella repo — spec hub, 46-test battery era |

List them from any clone with `git ls-remote --tags origin`.

## Pin and verify a release

```bash
git clone https://github.com/get-h3/h3 && cd h3
git checkout v0.1.0
make verify
```

Expected result: every guard prints PASS, the run ends with
`make verify: ALL PASS — umbrella repo is self-consistent`, and the exit code is
0 (`echo $?` → `0`) — on a bare clone of the tag: no venv, no network, no siblings.

## What `make verify` covers — and what it does not

| Guard | Checks |
|-------|--------|
| `verify-docs` | every relative `.md` link in `README.md` and `specs/_index.md` resolves to a file in the repo |
| `verify-specs` | every spec file under `specs/` is listed in `specs/_index.md`, and every listed spec exists |
| `verify-count` | the compliance-test count (46) in `scripts/test-count.txt` agrees with the sibling battery and the per-region lists in specs 05/09/25; no current-state doc quotes a retired count |
| `verify-json-fences` | every JSON fenced block in the tracked markdown parses, and an abbreviated payload says so on the failing line |
| `verify-qa-target` | the QA target is a real checkout of THIS repo — zero cells is UNVERIFIED, never a pass |
| `verify-tick-chain` | the DuckBrain tick-key census (H3-GAP-098): the bare `/tick/<N>` chain is complete from 418 to the board's `ticks_total - 1`, and no unknown-shaped tick key exists — the #459 backfill twins 452/453 are allowlisted, the pre-#418 legacy series and timestamped slugs are reported non-fatally. Reports UNVERIFIED when DuckBrain, `jq`, `curl`, the token or the board header is absent. Negative proof: `make verify-tick-chain-selftest` |
| `verify-commit-msg` | the HEAD commit message carries no workflow-skip directive |

It does **not** execute SDK code: these are docs/repo-consistency guards, which is what
keeps them runnable on a dependency-free clone (the one exception is the tick-chain
census, which reads DuckBrain's key tree read-only over HTTP and prints UNVERIFIED when
it cannot). Code-level verification is
`make verify-roundtrip` — the cross-language round-trip suite, run in CI by
`.github/workflows/roundtrip.yml` against the sibling SDK repos; `make verify-all` runs both.

## Establishing "CI green on this commit"

A tag claims that the commit under it was verified. Here the commit-level
verification is CI — and CI in this repo is **path-filtered on purpose**, so the
run history alone cannot answer "is this commit green?". Two traps, both
measured on this repo:

**Trap 1 — an absent run is not a red.** The two push-triggered workflows fire on
narrow path filters:

| Workflow | Push `paths` |
|----------|--------------|
| `.github/workflows/pages.yml` | `docs/**`, `scripts/**`, `*.md` |
| `.github/workflows/roundtrip.yml` | `integration/roundtrip/**`, its own file |

A commit range that touches only `.coding-hermes/board/**` (board bookkeeping) or
only `specs/**` produces **zero** runs. That is deliberate: `specs/**` was
removed from `pages.yml` (H3-PM-007) because every specs-only push redeployed a
byte-identical artifact. So `gh run list` returning nothing for a sha means "this
change never needed a run" — the commit is **UNVERIFIED**: not failed, and not
green either. Measured: HEAD `b01fa7a` (a board-only commit) has no run in either
workflow, and the newest `pages.yml` run is on its parent `99f9811`.

**Trap 2 — a run-level `conclusion: success` is not evidence.** `pages.yml` has
exactly one `continue-on-error: true` and it wraps the sibling-shim checkout —
not a test job, but a step whose failure quietly degrades the count guard to
"parity skipped" while the run still reports green. The evidence is therefore
**per-job and per-step `success`**:

```bash
gh run view <run-id> --repo get-h3/h3 --json jobs \
  --jq '.jobs[] | .name as $j | .steps[] | "\($j) | \(.number) | \(.name) | \(.conclusion)"'
```

A step that `skipped` ran nothing (it proves nothing, and is tolerated); any
other non-`success` step fails the release.

### The dispatch, and the citation

Green on a path-filter-exempt commit is established by an **explicit
`workflow_dispatch` on that commit**:

```bash
gh workflow run pages.yml     --repo get-h3/h3 --ref main
gh workflow run roundtrip.yml --repo get-h3/h3 --ref main
```

`workflow_dispatch` always runs on a **branch head**, so this establishes green
for the sha `origin/main` currently points at — push first, then dispatch. Read
the runs back, per-job, and record the ids:

```bash
gh run list --repo get-h3/h3 --workflow pages.yml --limit 20 \
  --json databaseId,headSha,status,conclusion,event \
  --jq '.[] | select(.headSha == "<40-char sha>") | "\(.databaseId) \(.event) \(.status) \(.conclusion)"'
```

Worked example (2026-09-20): both workflows dispatched on
`dc225dc2a9c976159007f8c56c1d242adb4372ef` — `pages.yml` run `35502402177`
(jobs `Compliance-test count guard` ✓ and `deploy` ✓) and `roundtrip.yml` run
`35502403234` (job `Python ↔ Go Round-Trip` ✓).

The run ids are part of the release record, not a convenience. The tag must land
on a commit whose dispatch run ids are cited **per-job** green: record the tag sha
and its run ids together (step 7 below), and treat a cut without them as
unfinished in the same way a tag without a Release object is unfinished.
`scripts/release.sh` is the mechanism that enforces this — step 3 of a cut
(`--execute`) does the dispatch-and-cite and aborts on anything that is not
per-job/per-step green, and `bash scripts/release.sh --verify-ci` does exactly
that dispatch-and-cite **without** performing a cut.

One consequence worth knowing before you cut: when the driver's own promote step
writes the changelog commit, the tag names a commit one step AFTER the dispatched
sha — a commit that is not on `origin` and therefore cannot be dispatched
(`workflow_dispatch` runs on a branch head). The driver prints that relationship
and the measured delta at tag time, and the cited ids cover the tag's parent. To
cite CI on the exact tagged sha, push the `[X.Y.Z]` section first and cut with
`--no-changelog`.

## Cutting the next release

Two paths, one destination: a tag **and** a published GitHub Release object.
A tag on its own is not a release (RELEASE-H3-002).

**The driver (preferred).** `scripts/release.sh`, exposed as `make release`:

```bash
make release                        # dry-run: prints the plan, mutates nothing
bash scripts/release.sh --verify-ci # dispatch + cite CI green on HEAD, then exit
bash scripts/release.sh --execute   # performs the cut
```

The dry-run is the default deliberately — it runs `make verify`, derives the
next version from the conventional commits since the last tag (`feat` → MINOR,
breaking → MAJOR, otherwise PATCH), proves the tag is unused locally and at
origin, and prints every step a cut would take (at step 3: exactly which
workflows it would dispatch, on which sha, and whether that sha is dispatchable
at all). `--execute` is the opt-in that performs the cut, and it works through
the numbered procedure below including the Release object, verifying that object
before it reports success; it also establishes CI green on the commit being cut
and aborts — before creating anything — on anything that is not per-job and
per-step green. `--verify-ci` performs ONLY that dispatch-and-cite, prints the
run ids and exits, without a cut. `--no-changelog` skips step 3 when the new
section was written by hand; `--tag vX.Y.Z` overrides the proposed version.

**By hand.** The same procedure, in order — it is not finished at step 5:

1. `make verify` is green at the commit you intend to tag.
2. Establish and record **CI green on that commit** — dispatch both workflows and
   read them back per-job. `bash scripts/release.sh --verify-ci` does both and
   prints the ids:

   ```bash
   bash scripts/release.sh --verify-ci
   ```

   An absent push-event run is expected on a board-only or specs-only range and
   is not a red (Trap 1); a run-level `success` is not the evidence either
   (Trap 2) — every job and every step must be `success`. The two run ids are
   recorded with the tag at step 7.
3. Update `CHANGELOG.md`: promote the `[Unreleased]` substance into a new
   `[X.Y.Z]` section **and RE-OPEN an empty `[Unreleased]` section above it**.
   The rule: `[Unreleased]` is always present, and after a cut it is empty again
   ("Nothing yet.") — never renamed into the release, never carried forward
   un-promoted. Commit that edit before tagging, so the tag names the released
   text.
4. `git tag -a vX.Y.Z -m "…"` on that commit (annotated, on `main`).
5. `git push origin vX.Y.Z` — the tag only, never the branch.
6. Publish the GitHub Release object — the tag alone is NOT one (RELEASE-H3-002:
   `v0.1.0` sat tag-only from 2026-09-18 until 2026-09-20, invisible to
   `gh release list` and anyone browsing the Releases tab):

   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <notes.md> --repo get-h3/h3
   gh release view vX.Y.Z --repo get-h3/h3   # must exit 0
   ```

   `gh release create` on an existing tag attaches the Release to that tag — it
   does not move or recreate it.
7. Only then record the tag's 40-char sha, its dispatch run ids **and** the
   Release URL on the cross-repo board. The cut is not done until step 6 has run:
   a procedure that stops at step 5 is exactly how the `v0.1.0` Release went
   missing for two days.
