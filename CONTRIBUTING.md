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
5. **Test battery** — `h3-test --endpoint <harness>` must pass 48/48

## Running the Round-Trip Verification

The suite needs three sibling SDK repos (`sdk-python`, `sdk-go`, `sdk-typescript`)
because the fixture programs resolve them by relative path. You do **not** have
to arrange that layout yourself: `roundtrip.sh` stages a declared workspace that
reproduces it — reusing local checkouts when the sibling repos exist next to this
repo, and otherwise fetching each SDK at the revision pinned in
[`integration/roundtrip/siblings.lock`](integration/roundtrip/siblings.lock). A
tree with only `h3/` checked out therefore runs the code-level gate.

```bash
# Canonical invocation — from the repo root (works on a bare clone of h3/):
make verify-roundtrip

# Declare the workspace yourself; a declared workspace is kept after the run:
make verify-roundtrip ROUNDTRIP_WORKSPACE=/tmp/h3-roundtrip

# Stage the workspace and report what was resolved, executing nothing:
bash integration/roundtrip/roundtrip.sh --resolve-only
```

`make verify-roundtrip` is the advertised entry point for code-level
verification and propagates the script's exit code — a failed round-trip fails
the make target. It requires `go`, `node` and `npx` on `PATH` (the TypeScript
phase runs through `npx tsx`), and — when the sibling SDKs are not already on
disk — `git` plus network access to fetch the pinned revisions.

Everything runs inside the workspace, not in your checkout:

- `<workspace>/MANIFEST.txt` records the revision used for each sibling and
  whether it was a local reuse (`source=local`) or a fetch (`source=fetched`),
  so a green run states exactly what it verified against.
- Generated fixtures land in `<workspace>/h3/integration/roundtrip/fixtures`, so
  a run no longer rewrites the tracked fixtures in this checkout. After a green
  run, `bash integration/roundtrip/roundtrip.sh --sync-fixtures` (or
  `H3_ROUNDTRIP_SYNC_FIXTURES=1`) copies them back.
- The workspace is a temp directory, removed on exit. `--workspace DIR` (or
  `H3_ROUNDTRIP_WORKSPACE=DIR`) declares one instead, and a declared workspace
  is kept.

Other knobs: `H3_ROUNDTRIP_REPO_BASE=<base>` (fetch source; a `file://` base
points at bare sibling checkouts and works offline),
`H3_ROUNDTRIP_FORCE_FETCH=1` (ignore local siblings and use the pins),
`H3_ROUNDTRIP_KEEP_WORKSPACE=1`, and `H3_SDK_PYTHON_REF` / `H3_SDK_GO_REF` /
`H3_SDK_TS_REF` to override a pin for one run.

`make verify-roundtrip-selftest` proves that resolution without network access or
SDK execution: the pins are full SHAs, an h3-only tree fetches them from a
`file://` mirror, local siblings are reused, a temp workspace is removed and a
declared one is kept, and an unreachable mirror fails loudly naming `sdk-python`
with the required layout and bootstrap command.

### What `make verify` does *not* cover

`make verify` (which needs only `make`, `git`, `awk`, `jq`, `curl`, `python3`,
POSIX shell/coreutils and a usable temp directory) is a
docs + repo-consistency check only: docs-link resolution, spec-index vs. files,
the canonical compliance-test count, json-fence payloads, the QA-target
contract guard, the DuckBrain tick-chain drift census (H3-GAP-098), and the
commit-message skip-directive guard. It executes **no
SDK code** — a green `make verify` on a bare clone exercises none of the
round-trip suite above. Use `make verify-all` when you want both in one command.

The tick-chain census is the one check that reaches outside the repo: it probes
DuckBrain on `localhost:3000` read-only (see `make verify-tick-chain`). When the
service, `jq`, `curl`, the token file or the board header is absent it prints an
explicit `UNVERIFIED` and exits 0 (`make verify` reports this as a disclosed
SKIP, not a pass) — absent tooling is UNVERIFIED, never a pass.

### Why CI only runs this on `integration/roundtrip/**`

`.github/workflows/roundtrip.yml` is path-filtered to `integration/roundtrip/**`
on purpose: the round-trip runs real Go/Node/Python toolchains, so it is gated to
pushes that actually change it rather than run on every docs edit. The workflow
has two jobs: `roundtrip` (sibling SDK checkouts laid out explicitly, plus
`make verify-roundtrip-selftest`) and `fresh-clone` (checks out **only** `h3`
and runs `make verify-roundtrip`, which fetches the pinned siblings — the shape a
new contributor gets). The consequence of the filter is that a docs-only push
gets green CI without any code having executed there — which is exactly why the
local targets above are named so the difference is visible.

This verifies Python → Go, Go → Python, and Go → TypeScript fixture consistency. All three language pairs must pass.

## Spec System

Specs live in `specs/` and follow a numbered scheme (S01 through S26). They are the single source of truth — if behavior isn't in a spec, it doesn't exist.

## Task Board

The cross-repo task board is `.coding-hermes/board/tasks.jsonl` (JSONL canonical). It tracks phases from spec completion through deployment. Each sub-repo has its own board.

## Quality Gates

- **GitReins** — git-native guard pipeline on every repo
- **h3-test** — 48-test compliance battery across 6 categories
- **roundtrip.sh** — cross-language wire format verification
- **redocly lint** — OpenAPI schema validation
- **check-tags-table.sh** — the `docs/releases.md` tags table names exactly the tags git has (`make verify-tags`); a pushed tag missing from the table, or a phantom table row, fails the gate

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
python3 scripts/duckbrain-tree-census.py h3 --start 418 --end auto   # the independent tree census (H3-GAP-099)
make verify-tick-chain-selftest                 # its fixture-driven positive + negative proof (no network)
make verify-tree-census-selftest                # the same for the independent tree-census walker (no network)
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
4. Run the test battery: `pip install hermes-h3-shim && h3-test --endpoint http://localhost:9191` (published on PyPI, so this is the primary path; source fallback for a commit that is not in a release yet — `git clone https://github.com/get-h3/shim && cd shim && pip install -e .`)
