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
