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

## Specs — All 26 Complete ✅

| # | Spec | Status | Pages |
|---|---|---|---|
| 01 | [Overview & Architecture](01-Overview-Architecture.md) | ✅ | ~8 |
| 02 | [Protocol Specification](02-Protocol-Specification.md) | ✅ | ~12 |
| 03 | [Installer & Version Compatibility](03-Installer-Version-Compat.md) | ✅ | ~8 |
| 04 | [SDK Libraries](04-SDK-Libraries.md) | ✅ | ~10 |
| 05 | [Shim Test Battery](05-Test-Battery.md) | ✅ | ~10 |
| 06 | [Hermes Core Integration](06-Hermes-Core-Integration.md) | ✅ | ~12 |
| 07 | [OpenAPI & JSON Schema Design](07-OpenAPI-JSON-Schema.md) | ✅ | ~8 |
| 08 | [Cross-Repo Release Pipeline](08-Cross-Repo-Release-Pipeline.md) | ✅ | ~6 |
| 09 | [Testing Framework Architecture](09-Testing-Framework-Architecture.md) | ✅ | ~10 |
| 10 | [h3.sh Website & Developer Docs](10-Website-Docs.md) | ✅ | ~5 |
| 11 | [Hermes Upgrade Survival](11-Hermes-Upgrade-Survival.md) | ✅ | ~8 |
| 12 | [Security & Authentication](12-Security-Authentication.md) | ✅ | ~14 |
| 13 | [Token Rotation & Revocation](13-Token-Rotation-Revocation.md) | ✅ | ~15 |
| 14 | [TLS Enforcement](14-TLS-Enforcement.md) | ✅ | ~19 |
| 15 | [Rate Limiting](15-Rate-Limiting.md) | ✅ | ~14 |
| 16 | [Observability & Structured Logging](16-Observability-Structured-Logging.md) | ✅ | ~12 |
| 17 | [Metrics & Performance Monitoring](17-Metrics-Performance-Monitoring.md) | ✅ | ~13 |
| 18 | [Distributed Tracing](18-Distributed-Tracing.md) | ✅ | ~15 |
| 19 | [Health Check v2](19-Health-Check-v2.md) | ✅ | ~14 |
| 20 | [Operational Dashboard](20-Operational-Dashboard.md) | ✅ | ~20 |
| 21 | [Resilience & Fallback](21-Resilience-Fallback.md) | ✅ | ~14 |
| 22 | [Performance Architecture](22-Performance-Architecture.md) | ✅ | ~10 |
| 23 | [Multi-Tenancy Architecture](23-Multi-Tenancy-Architecture.md) | ✅ | ~16 |
| 24 | [Compatibility Matrix](24-Compatibility-Matrix.md) | ✅ | ~15 |
| 25 | [Conformance Certification](25-Conformance-Certification.md) | ✅ | ~16 |
| 26 | [Chaos Engineering](26-Chaos-Engineering.md) | ✅ | ~16 |

**Total: 26 specs, ~318 pages.**

---

## Foreman

| Job ID | Name | Schedule | Status |
|---|---|---|---|
| `291a17144cf2` | h3-coding-hermes-foreman | every 30m | ✅ Running |
| `05b5a3276fdc` | h3-duckbrain-sync | every 1h | ✅ Running |

---

## DuckBrain Seeds

| Key | Content |
|---|---|
| `/spec/h3/overview` | Architecture, design principles, component map |
| `/spec/h3/protocol` | Endpoint contracts, decision types, error codes |
| `/spec/h3/installer` | Install flow, version matrix, compatibility |
| `/spec/h3/sdks` | Go/Python/TS SDKs, code generation |
| `/spec/h3/test-battery` | 43 compliance tests, CI integration, region-style |
| `/spec/h3/shim` | Hermes-side code structure, integration points |

---

*Generated July 21, 2026. Architecture from h3.html design doc.*
