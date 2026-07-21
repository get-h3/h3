# Contributing to H3

H3 (Hermes Harness Hooks) is a brain-swap protocol for Hermes agents. It lets external AI systems become the thinking brain while Hermes remains the body.

This repo (get-h3/h3) is the **umbrella coordination hub** — specs, cross-repo task board, integration tests, and docs. Implementation happens in sub-repos.

## Repo Map

| Repo | Language | Purpose |
|---|---|---|
| [protocol](https://github.com/get-h3/protocol) | YAML/JSON | OpenAPI 3.1 spec + JSON Schema — single source of truth |
| [shim](https://github.com/get-h3/shim) | Python | Hermes plugin: shim loop, test battery, CLI |
| [sdk-go](https://github.com/get-h3/sdk-go) | Go | Go SDK for harness developers |
| [sdk-python](https://github.com/get-h3/sdk-python) | Python | Python SDK for harness developers |
| [sdk-typescript](https://github.com/get-h3/sdk-typescript) | TypeScript | TypeScript SDK for harness developers |

## Development Cycle

1. **Spec change** — update the spec in `specs/` in this repo
2. **Protocol update** — change OpenAPI/JSON Schema in the protocol repo
3. **SDK regeneration** — each SDK has a sync-protocol workflow triggered by protocol tags
4. **Test cascade** — run `integration/roundtrip/roundtrip.sh` to verify cross-language wire consistency
5. **Test battery** — `h3-test --endpoint <harness>` must pass 43/43

## Running the Round-Trip Verification

```bash
cd integration/roundtrip
./roundtrip.sh
```

This verifies Python → Go, Go → Python, and Go → TypeScript fixture consistency. All three language pairs must pass.

## Spec System

Specs live in `specs/` and follow a numbered scheme (S01 through S11). They are the single source of truth — if behavior isn't in a spec, it doesn't exist.

## Task Board

The cross-repo task board is `.coding-hermes/tasks.md`. It tracks phases from spec completion through deployment. Each sub-repo has its own board.

## Quality Gates

- **GitReins** — git-native guard pipeline on every repo
- **h3-test** — 43-test compliance battery across 6 categories
- **roundtrip.sh** — cross-language wire format verification
- **redocly lint** — OpenAPI schema validation

## Getting Started

Pick up a task from the board. If you're new to H3, start with:

1. Read the [Protocol Spec](https://h3.sh/protocol)
2. Read the [Quickstart](https://h3.sh/#quickstart)
3. Clone the umbrella and sub-repos: `git clone --recurse-submodules https://github.com/get-h3/h3.git`
4. Run the test battery: `pip install hermes-h3-shim && h3-test --endpoint http://localhost:9191`
