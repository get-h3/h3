# AGENTS.md — get-h3 (Umbrella)

H3 (Hermes Harness Hooks) — **brain-swap protocol**. External agent systems (OpenCode, Consensus, CrewAI, LangChain) become the thinking brain of Hermes. Hermes is the body. H3 is the neural link.

**Org:** [get-h3](https://github.com/get-h3)

## Repos Under This Umbrella

| Directory | Repo | Purpose | Language |
|---|---|---|---|
| `h3/` | get-h3/h3 | Spec hub, cross-repo task board, integration tests | Markdown |
| `protocol/` | get-h3/protocol | OpenAPI 3.1 spec + JSON Schema — single source of truth | YAML/JSON |
| `shim/` | get-h3/shim | Hermes plugin: shim loop, test battery, CLI | Python |
| `sdk-go/` | get-h3/sdk-go | Go SDK for harness developers | Go |
| `sdk-python/` | get-h3/sdk-python | Python SDK for harness developers | Python |
| `sdk-typescript/` | get-h3/sdk-typescript | TypeScript SDK for harness developers | TypeScript |

## Dependency Chain

```
protocol/  (OpenAPI spec)
    │
    ├──► shim/          (Python plugin — generated types from OpenAPI)
    │       └── test_battery.py (43 compliance tests — E2E region-style)
    │
    ├──► sdk-go/        (generated types from OpenAPI)
    ├──► sdk-python/    (generated types from OpenAPI)
    └──► sdk-typescript (generated types from OpenAPI)
```

## Foreman Topology

| Foreman | Watches | Does |
|---|---|---|
| h3-foreman | `h3/` | Coordinates cross-repo task board, integration tests |
| protocol-foreman | `protocol/` | Maintains OpenAPI spec, publishes changes |
| shim-foreman | `shim/` | Builds Python plugin, runs test battery |
| sdk-go-foreman | `sdk-go/` | Builds Go SDK |
| sdk-python-foreman | `sdk-python/` | Builds Python SDK |
| sdk-typescript-foreman | `sdk-typescript/` | Builds TypeScript SDK |

## The Tester

The test battery (`shim/test_battery.py`) is the gate. It runs against ANY harness endpoint — no code changes needed:

```bash
pip install hermes-h3-shim
h3-test --endpoint http://localhost:9191
```

43 tests across 6 categories. E2E region-style: each category tests a complete functional region (health, process flows, decision types, result handling, edge cases, stress). Exit code 0 = harness is H3-compliant.

## Development

All repos use coding-hermes foremen for spec-driven development. GitReins quality gate on every repo. Specs in `h3/specs/`, task boards in each repo's `.coding-hermes/tasks.md`.
