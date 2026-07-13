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

## Phase 1 — Specs Complete ✅

| # | Spec | Status | Pages |
|---|---|---|---|
| 01 | [Overview & Architecture](01-Overview-Architecture.md) | ✅ Spec | ~8 pages |
| 02 | [Protocol Specification](02-Protocol-Specification.md) | ✅ Spec | ~12 pages |
| 03 | [Installer & Version Compatibility](03-Installer-Version-Compat.md) | ✅ Spec | ~8 pages |
| 04 | [SDK Libraries](04-SDK-Libraries.md) | ✅ Spec | ~10 pages |
| 05 | [Shim Test Battery](05-Test-Battery.md) | ✅ Spec | ~10 pages |
| 06 | [Hermes Core Integration](06-Hermes-Core-Integration.md) | ✅ Spec | ~12 pages |

**Total: 6 specs, ~60 pages, ~30K words.**

---

## Phase 2 — Implementation (pending)

Build order defined in `.coding-hermes/tasks.md`.

---

## DuckBrain Seeds

| Key | Content |
|---|---|
| `/spec/h3/overview` | Architecture, design principles, component map |
| `/spec/h3/protocol` | Endpoint contracts, decision types, error codes |
| `/spec/h3/installer` | Install flow, version matrix, compatibility |
| `/spec/h3/sdks` | Go/Python/TS SDKs, code generation |
| `/spec/h3/test-battery` | 43 compliance tests, CI integration |
| `/spec/h3/shim` | Hermes-side code structure, integration points |

---

*Generated July 12, 2026 — architecture from h3.html design doc.*
