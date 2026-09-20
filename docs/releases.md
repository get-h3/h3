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
| `verify-commit-msg` | the HEAD commit message carries no workflow-skip directive |

It does **not** execute code: these are docs/repo-consistency guards, which is what
keeps them runnable on a dependency-free clone. Code-level verification is
`make verify-roundtrip` — the cross-language round-trip suite, run in CI by
`.github/workflows/roundtrip.yml` against the sibling SDK repos; `make verify-all` runs both.

## Cutting the next release

1. `make verify` is green at the commit you intend to tag.
2. Update `CHANGELOG.md`: move the `[Unreleased]` substance into a new `[X.Y.Z]` section.
3. `git tag -a vX.Y.Z -m "…"` on that commit (annotated, on `main`).
4. `git push origin vX.Y.Z` — the tag only, never the branch.
5. Record the tag's 40-char sha on the cross-repo board.
6. Publish the GitHub Release object — the tag alone is NOT one (RELEASE-H3-002:
   `v0.1.0` sat tag-only from 2026-09-18 until 2026-09-20, invisible to
   `gh release list` and anyone browsing the Releases tab):

   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <notes.md> --repo get-h3/h3
   gh release view vX.Y.Z --repo get-h3/h3   # must exit 0
   ```

   `gh release create` on an existing tag attaches the Release to that tag — it
   does not move or recreate it.
