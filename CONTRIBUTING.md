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
5. **Test battery** — `h3-test --endpoint <harness>` must pass 46/46

## Running the Round-Trip Verification

> **Prerequisite:** the sibling SDK repos (`sdk-python`, `sdk-go`, `sdk-typescript`)
> must exist next to this repo on disk — `roundtrip.sh` resolves them as siblings
> of the umbrella directory (e.g. `../sdk-python`). A standalone clone of `h3/`
> alone cannot run it; clone the SDKs from the repo table above first. The script
> exits 1 with a clear message if any sibling is missing.

```bash
# Canonical invocation — from the repo root:
make verify-roundtrip

# Equivalent, if you are already in the directory:
cd integration/roundtrip
./roundtrip.sh
```

`make verify-roundtrip` is the advertised entry point for code-level
verification and propagates the script's exit code — a failed round-trip fails
the make target. It also requires `go`, `node` and `npx` on `PATH` (the
TypeScript phase runs through `npx tsx`).

### What `make verify` does *not* cover

`make verify` (the zero-dependency target that runs on a fresh clone) is a
docs + repo-consistency check only: docs-link resolution, spec-index vs. files,
the canonical compliance-test count, json-fence payloads, the QA-target
contract guard, the DuckBrain tick-chain drift census (H3-GAP-098), and the
commit-message skip-directive guard. It executes **no
SDK code** — a green `make verify` on a bare clone exercises none of the
round-trip suite above. Use `make verify-all` when you want both in one command.

The tick-chain census is the one check that reaches outside the repo: it probes
DuckBrain on `localhost:3000` read-only (see `make verify-tick-chain`). When the
service, `jq`, `curl`, the token file or the board header is absent it prints an
explicit `UNVERIFIED` and exits 0 — absent tooling is UNVERIFIED, never a pass.

### Why CI only runs this on `integration/roundtrip/**`

`.github/workflows/roundtrip.yml` is path-filtered to `integration/roundtrip/**`
on purpose: the round-trip needs the sibling SDK repos and the Go/Node
toolchains, so it is gated to pushes that actually change it rather than run on
every docs edit. The consequence is that a docs-only push gets green CI without
any code having executed there — which is exactly why the local targets above
are named so the difference is visible.

This verifies Python → Go, Go → Python, and Go → TypeScript fixture consistency. All three language pairs must pass.

## Spec System

Specs live in `specs/` and follow a numbered scheme (S01 through S26). They are the single source of truth — if behavior isn't in a spec, it doesn't exist.

## Task Board

The cross-repo task board is `.coding-hermes/board/tasks.jsonl` (JSONL canonical). It tracks phases from spec completion through deployment. Each sub-repo has its own board.

## Quality Gates

- **GitReins** — git-native guard pipeline on every repo
- **h3-test** — 46-test compliance battery across 6 categories
- **roundtrip.sh** — cross-language wire format verification
- **redocly lint** — OpenAPI schema validation

### Targeting this repo for QA / verification

The QA/verification target of the `h3` project is **this repository**. Resolve
it from the checkout itself (`git rev-parse --show-toplevel`) or from the
owning row's `workdir` in `~/.hermes/coding-hermes/scheduler.db` — never by
turning a project name into `/home/<user>/<project>`, which is how a QA battery
once targeted a path that does not exist and drove zero cells (row `QA-H3-1`).

Validate a target before recording any QA cell:

```bash
sh scripts/check-qa-target.sh <candidate-dir>   # 0 = this repo; non-zero = not a valid target
make verify-qa-target                           # same check against this checkout
sh scripts/check-duckbrain-tick-chain.sh        # DuckBrain tick-key drift + window census (H3-GAP-098)
make verify-tick-chain-selftest                 # its fixture-driven positive + negative proof (no network)
```

An empty, no-cell QA result is **UNVERIFIED — never a pass**. Full contract and
the reproducible real-target verification commands:
[docs/qa-target-contract.md](docs/qa-target-contract.md).

## Commit messages and CI

Never write a GitHub workflow-skip directive in a commit message — not even while
discussing one, and not in prose. GitHub matches the directive **anywhere** in the
message of the pushed head commit. The tick #355 subject ended with
`NO [ci skip]: this push carries the docs/badge fix` and CI was skipped anyway: the
token was matched, the surrounding words were not read. A commit message is not a
place to state an intention — the token is a control signal.

Rejected tokens (case-insensitive): `[skip ci]`, `[ci skip]`, `[no ci]`,
`[skip actions]`, `[actions skip]`.

A board-only commit (`.coding-hermes/`) produces no workflow run because the
workflows filter on paths — `docs/**`, `specs/**`, `scripts/**`, `**.md` for
pages.yml; `integration/roundtrip/**` for roundtrip.yml. That is by design, not a
bug. To keep a workflow from running, use its paths filter; never a message token.

Check the message locally before you commit:

```sh
sh scripts/check-ci-skip-tokens.sh      # checks HEAD
make verify                             # all umbrella checks, includes the guard
```

Audit existing history (report only, always exits 0):

```sh
sh scripts/check-ci-skip-tokens.sh --audit <rev-range>
sh scripts/check-ci-skip-tokens.sh --audit 59ecfeb~40..59ecfeb
```

## Getting Started

Pick up a task from the board. If you're new to H3, start with:

1. Read the [Protocol Spec](https://github.com/get-h3/h3/tree/main/specs)
2. Read the [Quickstart](https://github.com/get-h3/h3#quick-start)
3. Clone the umbrella and sibling repos (independent repos — the umbrella has no submodules):
   ```bash
   git clone https://github.com/get-h3/h3.git
   git clone https://github.com/get-h3/protocol.git
   git clone https://github.com/get-h3/shim.git
   git clone https://github.com/get-h3/sdk-go.git
   git clone https://github.com/get-h3/sdk-python.git
   git clone https://github.com/get-h3/sdk-typescript.git
   ```
4. Run the test battery: `git clone https://github.com/get-h3/shim && cd shim && pip install -e . && h3-test --endpoint http://localhost:9191` (source install — PyPI publishing pending, see P3-10)
