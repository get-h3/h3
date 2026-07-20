# H3 — Brain-Swap Protocol for AI Agents

[![H3 Spec](https://img.shields.io/badge/specs-11/11-8b5cf6)](specs/)
[![Go SDK](https://img.shields.io/badge/go-sdk-00ADD8)](https://github.com/get-h3/sdk-go)
[![Python SDK](https://img.shields.io/badge/python-sdk-3776AB)](https://github.com/get-h3/sdk-python)
[![TypeScript SDK](https://img.shields.io/badge/typescript-sdk-3178C6)](https://github.com/get-h3/sdk-typescript)

**Swap your agent's brain. Keep the Hermes platform.**

H3 (Hermes Harness Hooks) is an open protocol that lets external agent systems — OpenCode, Consensus, CrewAI, LangChain, or your own custom harness — become the thinking brain of Hermes. Hermes is the body. H3 is the neural link.

```
┌─────────────┐     H3 Protocol      ┌──────────────┐
│   Hermes    │ ◄─────────────────►  │   Harness    │
│  (the body) │  process / result    │  (the brain) │
└─────────────┘     decisions        └──────────────┘
```

## Quick Start

The fastest way to see H3 in action:

```bash
# Install the test battery
pip install hermes-h3-shim

# Start a Go echo harness (clone get-h3/sdk-go examples)
cd sdk-go/examples/echo && go run .

# Run the compliance tests
h3-test --endpoint http://localhost:9191
```

43 tests — 6 categories — exit code 0 means your harness is H3-compliant.

Or scaffold a new harness in 30 seconds:

```bash
hermes h3 scaffold --lang go
cd h3-harness && go run .
h3-test --endpoint http://localhost:9191
```

## Repositories

| Repo | Purpose | Language |
|------|---------|----------|
| [h3](https://github.com/get-h3/h3) | **You are here.** Spec hub, task board, documentation website | Markdown |
| [protocol](https://github.com/get-h3/protocol) | OpenAPI 3.1 spec + JSON Schema — single source of truth | YAML/JSON |
| [shim](https://github.com/get-h3/shim) | Hermes plugin: shim loop, 43-test battery, CLI (`hermes h3`) | Python |
| [sdk-go](https://github.com/get-h3/sdk-go) | Go SDK for building harnesses | Go |
| [sdk-python](https://github.com/get-h3/sdk-python) | Python SDK for building harnesses | Python |
| [sdk-typescript](https://github.com/get-h3/sdk-typescript) | TypeScript SDK for building harnesses | TypeScript |

## Architecture

H3 follows a **spec-driven, protocol-first** architecture:

```
protocol/  (OpenAPI 3.1 — single source of truth)
    │
    ├──► shim/           (Hermes-side plugin — Python)
    │     └── test_battery.py  (43 compliance tests)
    │
    ├──► sdk-go/         (Harness Go SDK — generated types)
    ├──► sdk-python/     (Harness Python SDK — generated types)
    └──► sdk-typescript/ (Harness TS SDK — generated types)
```

All SDKs generate their types from the same OpenAPI spec. A change to the protocol propagates to every SDK. The test battery verifies compliance against any harness in any language.

### The Loop

1. Hermes sends a **ProcessRequest** (text, tool_call, or tool_result)
2. The harness returns a **Decision** (text, tool_use, end, or wait)
3. Hermes executes the decision and sends back a **ResultRequest**
4. The harness returns another Decision
5. Loop until the harness returns `Decision.end`

## Documentation

- **Website:** [h3.sh](https://h3.sh) — landing page, language picker, quickstart
- **Specs:** [`specs/`](specs/) — 11 specs, ~97 pages covering architecture, protocol, SDKs, installer, test battery, release pipeline, website, and upgrade survival
- **Protocol reference:** [`docs/protocol.html`](docs/protocol.html) — auto-generated from OpenAPI
- **SDK reference:** [`docs/sdk.html`](docs/sdk.html) — auto-generated
- **Build guide:** [`docs/guide.html`](docs/guide.html) — "Build Your First H3 Harness" tutorial
- **Migration guide:** [`docs/migration.html`](docs/migration.html) — migrating from native Hermes to H3

## Compliance

A harness is H3-compliant when it passes all 43 tests in the [test battery](https://github.com/get-h3/shim). Current compliance scores across SDK examples:

| Language | Tests Passing |
|----------|:------------:|
| Go (echo) | 43/43 |
| Python (echo) | ~15/43* |
| TypeScript (echo) | 43/43 |

*\*Python SDK has a Pydantic strictness issue with optional fields. [Tracked as QV-SDK-06.](.coding-hermes/tasks.md)*

## Development

This project uses **coding-hermes** foremen for spec-driven autonomous development. Each repo has its own foreman cron that reads the task board, spawns coding workers, runs GitReins quality gates, and reports results.

| Foreman | Watches | Cadence |
|---------|---------|---------|
| h3-foreman | Coordination, task board, docs | Every 30m |
| protocol-foreman | OpenAPI spec, JSON Schema | Every 30m |
| shim-foreman | Python plugin, test battery | Every 30m |
| sdk-go-foreman | Go SDK | Every 2h |
| sdk-python-foreman | Python SDK | Every 2h |
| sdk-typescript-foreman | TypeScript SDK | Every 2h |

**Quality gates:** GitReins on every repo (secrets scan, lint, tests). GitHub Actions CI on protocol (redocly lint) and shim (pytest).

## License

[MIT](LICENSE) — The get-h3 organization.
