# Changelog

All notable changes to the H3 protocol and umbrella project.

## [Unreleased]

Nothing yet. This section is re-opened empty by every cut; the substance that
shipped in a release lives under that release's section below.

## [0.2.0] — 2026-09-20

Second tagged release of the umbrella repo, cut by the release driver added in
this cycle (RELEASE-H3-005; authorized once the v0.1.0 release-lane work
RELEASE-H3-002..004 had landed).

### Added
- `scripts/release.sh` + `make release` (RELEASE-H3-003): the umbrella release
  driver — dry-run by default, refuses a dirty tree, runs `make verify` and
  asserts the gate's own ALL PASS line, computes MAJOR/MINOR/PATCH from the
  commit range, refuses to move a pushed tag, promotes the CHANGELOG, pushes
  the tag only (never the branch), and publishes + verifies the GitHub Release
  object.
- CI-green-on-HEAD for path-filtered ranges (RELEASE-H3-004): the driver (and
  `--verify-ci`) dispatch `pages.yml` + `roundtrip.yml` via `workflow_dispatch`,
  assert PER-JOB and PER-STEP success (a run-level green is not evidence —
  pages.yml carries a continue-on-error step), wait a bounded window, and cite
  the run ids. The absence of a push-event run on a board-only or specs-only
  range is UNVERIFIED — neither red nor green.

### Changed
- v0.1.0 re-issued as a real GitHub Release object (RELEASE-H3-002): it had sat
  tag-only since 2026-09-18, invisible to `gh release list` and the Releases tab.
- Releng sweep 2026-09-20 (RELEASE-H3-001): v0.2.0 declared GO; the cut is
  authorized by RELEASE-H3-005, gated on RELEASE-H3-002..004.
- 42 operator-decision board rows (LOGSEY/PULSE/LORE/DIGEST families) marked
  blocked-operator with the owning decision recorded (H3-GAP-097).
- PM-ledger reconciliation is a single implementation that stops the stand-in
  PM ledger from overstating open work (H3-GAP-093).

### Fixed
- False sibling-tag claim in the v0.1.0 notes: sdk-go's tag range is
  v0.1.0–v0.1.6.
- Curated `.vfs` artifacts stageable again (ignore vs tracked paths,
  H3-GAP-094); the whole `.vfs` working-state directory is ignored (QA-H3-9).
- JSON-fence guard validates in one batched pass instead of one interpreter
  spawn per fence (GAP-075).
- DuckBrain tick-key write gaps reconciled from board evidence (405/409
  standing; 415–421 backfilled from the tick records).

### Verification
- E2E-001 closing run: 46/46 on `:9191`, window #412–#417; NEVER-DONE desk
  audits #61–#64, read-only gate ALL PASS on every idle tick.
- Window scope: work landed on `main` after the `v0.1.0` cut (tick #392, tag
  `v0.1.0` at `482a316`) across foreman ticks #392–#422, which opened the
  `RELEASE-H3-*` rows.
- JSON-fence guard validates every tracked fenced block in one batched `python3`
  pass instead of one interpreter per fence (GAP-075, `7bfb5b8`).
- `.vfs` curated artifacts stageable again and the whole working-state directory
  ignored (H3-GAP-094 / QA-H3-9).
- Cross-repo gap work in this window: H3-GAP-086 (sdk-go quickstart port sync),
  H3-GAP-095/096, H3-CI-002 (sdk-typescript round-trip, CI run 35421835252).

## [0.1.0] — 2026-09-18

First tagged release of the umbrella repo. The Added/Changed/Fixed entries below
shipped in the untagged 2026-08 window; the tag is cut at the `main` commit where
`make verify` exits 0 (QA-H3-6).

### Added
- Board v2: JSONL-canonical workboard (board.jsonl + tasks.jsonl + events.jsonl + fixtures.jsonl) — JSONL-NORM-001 (2026-08-07)
- GitHub Pages documentation site (`get-h3.github.io/h3/`) as the working fallback for the dead `h3.sh` domain
- 44-test compliance battery (43 baseline + sibling GAP-DOG-002 test) — verified live on ticks #270/#275

### Changed
- 20 H3-GAP closures (H3-GAP-001 through H3-GAP-020): dead install refs → source install, stale board paths → JSONL, battery counts 43 → 44, dead-domain refs → GitHub Pages fallback, quickstart ENOENT fix
- README quickstart now clones sibling repos explicitly before `cd` (sdk-go is a sibling repo, not part of shim/)
- Spec install blocks replaced dead `pip install hermes-h3-shim` lines with the working source-install command (PyPI publish gated on P3-10)
- Source-install forms replace unpublished PyPI package references (`git clone` + `pip install -e .`)
- Changelog resumed (was frozen at [1.0.0])

### Fixed
- Dead marketing-domain references (NXDOMAIN) replaced with `get-h3.github.io/h3/` in live docs
- README quickstart ENOENT (`cd sdk-go/examples/echo` failed from a shim clone — clone step added)
- `pip install hermes-h3-shim` dead lines inside copy-paste code blocks (specs 08/09/10/26)
- sdk-python battery CI now installs the shim from source instead of the unpublished PyPI package (CI-GAP-01)

### Release
- **First tagged release** of `get-h3/h3`: annotated tag `v0.1.0` on `main`.
- **Tag convention:** `vX.Y.Z`, annotated (`git tag -a`), cut on `main` at a commit where `make verify` exits 0. A pushed tag is never moved.
- The umbrella tags at each docs-shipped milestone. That says nothing about the sibling repos: tag state, measured 2026-09-20 with `git ls-remote --tags` against each remote, is this repo `v0.1.0`, `get-h3/protocol` `v1.0.0`, `get-h3/sdk-go` `v0.1.0`–`v0.1.6`, and `get-h3/shim`, `get-h3/sdk-python` and `get-h3/sdk-typescript` UNTAGGED. RELEASE-H3-002 removed an earlier sentence here that read as if those three were tagged; re-measured 2026-09-20 (RELEASE-H3-003). Do not restate a sibling's tag state without a fresh measurement.
- **An annotated tag is not a GitHub Release object.** The `v0.1.0` tag sat tag-only from 2026-09-18 until the Release was published 2026-09-20, invisible to `gh release list` (RELEASE-H3-002). `scripts/release.sh` / `make release` now performs both, and `docs/releases.md` names the steps.
- **Compliance battery: 46 tests** — the canonical count lives in `scripts/test-count.txt`, and `make verify`'s count guard fails any current-state doc that quotes a retired count (43/44) or a per-region list that does not sum to 46.
- Consumer recipe for pinning and verifying this tag: [`docs/releases.md`](docs/releases.md).

## [1.0.0] — 2026-07-19

### Added
- H3 protocol v1.0.0 — OpenAPI 3.1 specification
- JSON Schema definitions for all protocol types
- Go SDK (github.com/get-h3/sdk-go)
- Python SDK (h3-harness-sdk)
- TypeScript SDK (@get-h3/h3-harness-sdk)
- Hermes shim plugin (hermes-h3-shim)
- 43-test compliance battery (h3-test)
- Cross-language roundtrip verification (Go ↔ Python ↔ TypeScript)
- GitReins quality gate on all 6 repos
- Structured access logging on all echo harnesses
- Health check + circuit breaker on shim loader
- CLI: install, scaffold, verify, pre-update-check
- Test report JSON schema validation
