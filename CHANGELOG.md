# Changelog

All notable changes to the H3 protocol and umbrella project.

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

## [Unreleased] — 2026-08

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
