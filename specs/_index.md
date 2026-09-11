# H3 Specification Index

> **Org:** [get-h3](https://github.com/get-h3) — 6 repos, spec-driven

## Repo Collection

| Repo | Purpose | Language |
|---|---|---|
| [get-h3/h3](https://github.com/get-h3/h3) | Spec hub, task board, docs, integration tests | Markdown |
| [get-h3/protocol](https://github.com/get-h3/protocol) | OpenAPI 3.1 spec — single source of truth | YAML/JSON |
| [get-h3/shim](https://github.com/get-h3/shim) | Hermes plugin — shim loop, test battery, CLI | Python |
| [get-h3/sdk-go](https://github.com/get-h3/sdk-go) | Go SDK for harness developers | Go |
| [get-h3/sdk-python](https://github.com/get-h3/sdk-python) | Python SDK for harness developers | Python |
| [get-h3/sdk-typescript](https://github.com/get-h3/sdk-typescript) | TypeScript SDK for harness developers | TypeScript |

---

## Specs — 26 Specifications

| # | Spec | Status | Pages |
|---|---|---|---|
| 01 | [Overview & Architecture](01-Overview-Architecture.md) | Spec | ~8 |
| 02 | [Protocol Specification](02-Protocol-Specification.md) | Spec | ~12 |
| 03 | [Installer & Version Compatibility](03-Installer-Version-Compat.md) | Spec | ~8 |
| 04 | [SDK Libraries](04-SDK-Libraries.md) | Spec | ~10 |
| 05 | [Shim Test Battery](05-Test-Battery.md) | Spec | ~10 |
| 06 | [Hermes Core Integration](06-Hermes-Core-Integration.md) | Spec | ~12 |
| 07 | [OpenAPI & JSON Schema Design](07-OpenAPI-JSON-Schema.md) | Spec | ~8 |
| 08 | [Cross-Repo Release Pipeline](08-Cross-Repo-Release-Pipeline.md) | Spec | ~6 |
| 09 | [Testing Framework Architecture](09-Testing-Framework-Architecture.md) | Spec | ~10 |
| 10 | [H3 Website & Developer Docs](10-Website-Docs.md) | Spec | ~5 |
| 11 | [Hermes Upgrade Survival](11-Hermes-Upgrade-Survival.md) | Spec | ~8 |
| 12 | [Security & Authentication](12-Security-Authentication.md) | Spec | ~14 |
| 13 | [Token Rotation & Revocation](13-Token-Rotation-Revocation.md) | Spec | ~15 |
| 14 | [TLS Enforcement](14-TLS-Enforcement.md) | Spec | ~19 |
| 15 | [Rate Limiting](15-Rate-Limiting.md) | Spec | ~14 |
| 16 | [Observability & Structured Logging](16-Observability-Structured-Logging.md) | Spec | ~12 |
| 17 | [Metrics & Performance Monitoring](17-Metrics-Performance-Monitoring.md) | Spec | ~13 |
| 18 | [Distributed Tracing](18-Distributed-Tracing.md) | Spec | ~15 |
| 19 | [Health Check v2](19-Health-Check-v2.md) | Spec | ~14 |
| 20 | [Operational Dashboard](20-Operational-Dashboard.md) | Spec (planned) | ~20 |
| 21 | [Resilience & Fallback](21-Resilience-Fallback.md) | Spec | ~14 |
| 22 | [Performance Architecture](22-Performance-Architecture.md) | Complete | ~10 |
| 23 | [Multi-Tenancy Architecture](23-Multi-Tenancy-Architecture.md) | Complete | ~16 |
| 24 | [Compatibility Matrix](24-Compatibility-Matrix.md) | Complete | ~15 |
| 25 | [Conformance Certification](25-Conformance-Certification.md) | Spec (planned) | ~16 |
| 26 | [Chaos Engineering](26-Chaos-Engineering.md) | Spec (planned) | ~16 |

**Total: 26 specs, ~318 pages. Shipped: 3/26 Complete (S22/S23/S24); designed: 23/26 Spec (S20/S25/S26 planned — no implementation artifacts yet).**

Status values mirror each spec's own header `**Status:**` line — they describe document/implementation state, not just document existence.

---

## Implementation Audit (2026-08-24)

Spec headers are the source of truth for per-spec status, and they are NOT all "Complete":

- 23/26 specs are design-level `**Status:** Spec` — specification documents, not implemented guarantees.
- 3/26 marked Complete (S22/S23/S24: 22-Performance-Architecture, 23-Multi-Tenancy-Architecture, 24-Compatibility-Matrix).
- S20/S25/S26 have no implementation artifacts: S20 Operational Dashboard, S25 Conformance Certification, and S26 Chaos Engineering currently have zero implementation artifacts anywhere in fleet sources — treat them as forward-looking specifications.

The table's Status column mirrors each spec's own header (`Spec` / `Complete`), not *document existence* — before GAP-069 (2026-09-11) the column showed ✅ on all 26 rows, which meant only "document exists". The README badge reflects the spec count (26 specs), not a completion claim. Any future "specs complete" claim must cite per-spec header status, not the table.

---

## Foreman

| Job ID | Name | Schedule | Status |
|---|---|---|---|
| `291a17144cf2` | h3-coding-hermes-foreman | every 6h (21600s cooldown) | ✅ Running |
| `05b5a3276fdc` | h3-duckbrain-sync | every 1h | ✅ Running |

---

## DuckBrain Seeds

| Key | Content |
|---|---|
| `/spec/h3/overview` | Architecture, design principles, component map |
| `/spec/h3/protocol` | Endpoint contracts, decision types, error codes |
| `/spec/h3/installer` | Install flow, version matrix, compatibility |
| `/spec/h3/sdks` | Go/Python/TS SDKs, code generation |
| `/spec/h3/test-battery` | 44 compliance tests, CI integration, region-style |
| `/spec/h3/shim` | Hermes-side code structure, integration points |

---

*Generated July 21, 2026. Architecture from h3.html design doc.*
