# AGENTS.md — H3

H3 (Hermes Harness Hooks) is the two-endpoint protocol that decouples Hermes Core from agent harnesses.

**Org:** [get-h3](https://github.com/get-h3) — 6 repos

## Repo Collection

| Repo | Purpose | Language |
|---|---|---|
| [h3](https://github.com/get-h3/h3) | Spec hub, task board, docs, integration tests | Markdown |
| [protocol](https://github.com/get-h3/protocol) | OpenAPI 3.1 spec — single source of truth | YAML/JSON |
| [shim](https://github.com/get-h3/shim) | Hermes plugin — shim loop, test battery, CLI | Python |
| [sdk-go](https://github.com/get-h3/sdk-go) | Go SDK for harness developers | Go |
| [sdk-python](https://github.com/get-h3/sdk-python) | Python SDK for harness developers | Python |
| [sdk-typescript](https://github.com/get-h3/sdk-typescript) | TypeScript SDK for harness developers | TypeScript |

## Architecture

- H3 Shim: `hermes_cli/agent/shims/h3/` — Python plugin inside Hermes Core
- SDKs: Go (`h3-sdk-go`), Python (`h3-harness-sdk`), TypeScript (`@get-h3/h3-harness-sdk`)
- Test Battery: 43 compliance tests, runs against any harness endpoint
- Protocol: REST (default) or gRPC. Two main endpoints: `/v1/process`, `/v1/result`

See `specs/` for full specification files (S01–S06).

## Key Decisions

- **REST first, gRPC optional** — REST is debuggable with curl, works everywhere
- **Two endpoints, not a framework** — minimize the contract surface
- **Harness owns the loop** — Hermes asks "what should I do?", harness decides
- **Test battery is the gate** — 43 tests, if they pass, your harness works
- **SDKs in 3 languages** — Go, Python, TypeScript cover the ecosystem

## Repo Layout

```
h3/
├── specs/               # S01-S06 specification files
├── sdks/                # Go, Python, TypeScript SDKs
├── tests/               # Test battery implementation
├── .coding-hermes/      # Task board for coding-hermes foreman
├── .gitreins/           # GitReins quality guard config
└── AGENTS.md            # This file
```

## Development

This project uses coding-hermes for spec-driven development. Foreman loads `coding-hermes-foreman`, `coding-hermes-cron`, `hilo-usage`, `gitreins`.

All agents read `specs/_index.md`, `AGENTS.md`, and `.coding-hermes/tasks.md` at task start.

## GitReins Quality Harness (MANDATORY)

```bash
PATH="$HOME/go/bin:$HOME/gitreins-poc/.venv/bin:$PATH" gitreins guard
```

- **secrets** — BLOCKS on fail
- **build** — BLOCKS on fail (when code exists)
- **lint** — WARNS on fail
- **tests** — BLOCKS on fail
