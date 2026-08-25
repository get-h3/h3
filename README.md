# H3 — Brain-Swap Protocol for AI Agents

[![H3 Spec](https://img.shields.io/badge/specs-26%20specs-8b5cf6)](specs/)
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
# Install the test battery + CLI (source install — hermes-h3-shim is not on PyPI yet; install from source per docs/integration.md. h3-harness-sdk IS published: pip install h3-harness-sdk)
git clone https://github.com/get-h3/shim && cd shim
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

# Start a Go echo harness — clone the sibling sdk-go repo first (it is NOT part of shim/)
git clone https://github.com/get-h3/sdk-go
cd sdk-go/examples/echo && go run .

# Run the compliance tests
h3-test --endpoint http://localhost:9191
```

44 tests — 6 categories — exit code 0 means your harness is H3-compliant.

Or scaffold a new harness in 30 seconds:

```bash
hermes-h3 scaffold --lang go
cd h3-harness-go && go mod tidy && go run .
h3-test --endpoint http://localhost:9191
```

> The CLI is `hermes-h3` (standalone binary with `install`, `scaffold`, `test`,
> `verify`, and more). The `hermes h3` plugin form requires H3 wired into a
> live Hermes install (tracked as WIRING-01).

## Repositories

| Repo | Purpose | Language |
|------|---------|----------|
| [h3](https://github.com/get-h3/h3) | **You are here.** Spec hub, task board, documentation website | Markdown |
| [protocol](https://github.com/get-h3/protocol) | OpenAPI 3.1 spec + JSON Schema — single source of truth | YAML/JSON |
| [shim](https://github.com/get-h3/shim) | Hermes plugin: shim loop, 44-test battery, CLI (`hermes-h3`; `hermes h3` plugin form is WIRING-01-gated) | Python |
| [sdk-go](https://github.com/get-h3/sdk-go) | Go SDK for building harnesses | Go |
| [sdk-python](https://github.com/get-h3/sdk-python) | Python SDK for building harnesses | Python |
| [sdk-typescript](https://github.com/get-h3/sdk-typescript) | TypeScript SDK for building harnesses — **not on npm** (GitHub dependency) | TypeScript |

## Architecture

H3 follows a **spec-driven, protocol-first** architecture:

```
protocol/  (OpenAPI 3.1 — single source of truth)
    │
    ├──► shim/           (Hermes-side plugin — Python)
    │     └── test_battery.py  (44 compliance tests)
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

- **Website:** [get-h3.github.io/h3/](https://get-h3.github.io/h3/) — landing page, language picker, quickstart (old marketing domain is dead — NXDOMAIN)
- **Specs:** [`specs/`](specs/) — 26 specs, ~320 pages covering architecture, protocol, SDKs, installer, test battery, release pipeline, website, and upgrade survival
- **Protocol reference:** [`docs/protocol.html`](docs/protocol.html) — auto-generated from OpenAPI
- **SDK reference:** [`docs/sdk.html`](docs/sdk.html) — auto-generated
- **Build guide:** [`docs/guide.html`](docs/guide.html) — "Build Your First H3 Harness" tutorial
- **Migration guide:** [`docs/migration.html`](docs/migration.html) — migrating from native Hermes to H3
- **Integration guide:** [`docs/integration.md`](docs/integration.md) — for external harness developers (OpenCode, Consensus, CrewAI, LangChain) wiring H3 into their own systems

## Compliance

A harness is H3-compliant when it passes all 44 tests in the [test battery](https://github.com/get-h3/shim). Current compliance status across SDK examples:

| Language | Evidence | CI-verified | Published |
|----------|----------|:-----------:|-----------|
| Go (echo) | 44/44 — foreman E2E tick #340 ran the battery against the Go echo harness on :9191 (p50 0.60ms / p95 19.66ms) | ✅ | source (`go get github.com/get-h3/sdk-go`) |
| Python (echo) | 44/44 — local battery run | — | PyPI: `pip install h3-harness-sdk` |
| TypeScript (echo) | 44/44 — local battery run | — | **not published on npm** (`npm view @get-h3/h3-harness-sdk` → E404) — install from source (GitHub dependency) |

**CI-verified** means the run is captured in repo CI or a foreman E2E tick; Go is currently the only SDK with in-repo E2E evidence (tick #340 on :9191). Python and TypeScript pass locally but have no in-repo runnable CI evidence yet.

## Development

This project uses **coding-hermes** foremen for spec-driven autonomous development. Each repo has its own foreman cron that reads the task board, spawns coding workers, runs GitReins quality gates, and reports results.

| Foreman | Watches | Cadence |
|---------|---------|---------|
| h3-foreman | Coordination, task board, docs | Every 6h (21600s cooldown) |
| protocol-foreman | OpenAPI spec, JSON Schema | Every 30m (cron-managed) |
| shim-foreman | Python plugin, test battery | Every 2h (7200s cooldown) |
| sdk-go-foreman | Go SDK | Every 2h (7200s cooldown) |
| sdk-python-foreman | Python SDK | Every 2h (7200s cooldown) |
| sdk-typescript-foreman | TypeScript SDK | Every 15m (900s cooldown) |

> Cadence = scheduler `cooldown_s` per project (verified live 2026-08-13). The h3 foreman's 21600s was raised deliberately after the idle-tick-flood fix (H3-GAP-003); it self-restores to 21600s after stand-in-PM wake cycles (cooldown-policy pin).

**Quality gates:** GitReins on every repo (secrets scan, lint, tests). GitHub Actions CI on protocol (redocly lint) and shim (pytest).

**Verification:** this repo is self-checking — `make verify` (docs-link + spec-index checks, zero dependencies) runs from a fresh clone, and `integration/roundtrip/roundtrip.sh` verifies cross-language wire consistency across the Python, Go, and TypeScript SDKs (requires the sibling repos; see CONTRIBUTING.md).

**Contributing:** see [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow, code of conduct, and governance.

## License

[MIT](LICENSE) — The get-h3 organization.
