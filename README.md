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
# Install the test battery + CLI from PyPI — always in a venv (PEP 668 distros
# refuse a bare `pip install`; the shim's sibling `h3-harness-sdk` is on PyPI too)
python3 -m venv .venv && source .venv/bin/activate
pip install hermes-h3-shim

# A commit that is not in a release yet (or local development)? Install the
# source checkout instead, into the same venv:
#   git clone https://github.com/get-h3/shim && cd shim && pip install -e .

# Start a Go echo harness — the echo example lives in the sdk-go repo, not in the shim
git clone https://github.com/get-h3/sdk-go
cd sdk-go/examples/echo && go run .

# Run the compliance tests
h3-test --endpoint http://localhost:9191
```

> **`python3 -m venv` fails with `ensurepip is not available`?** That host has no
> python3-venv package (and no sudo to `apt install python3-venv`). Create the venv
> without pip, then bootstrap pip into it:
>
> ```bash
> python3 -m venv --without-pip .venv
> curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
> .venv/bin/python /tmp/get-pip.py
> .venv/bin/pip install hermes-h3-shim   # or: -e .  (the source fallback)
> ```

> **`h3-test` and `hermes-h3` live inside the venv you installed into — a new
> terminal does not have them.** `pip install hermes-h3-shim` puts both console
> scripts in that venv's `bin/` and `source .venv/bin/activate` adds them to
> PATH **for that shell only**; pip never puts them on the system PATH (a bare
> system-wide `pip install` is refused anyway on PEP 668 distros). So in a fresh
> shell — or any shell that has since changed directory — pick one; the paths
> below are absolute, so they work from anywhere:
>
> ```bash
> source /path/to/.venv/bin/activate                # re-activate (the venv you installed into)
> export PATH="/path/to/.venv/bin:$PATH"            # or put the venv on PATH, no activation
> /path/to/.venv/bin/h3-test --endpoint http://localhost:9191   # or call the script by path
> ```
>
> All three are equivalent; the exported PATH and the explicit path work from
> every directory and need no activation. The scaffold block below still needs
> the CLI on PATH (it runs `hermes-h3`, then `h3-test` from inside the generated
> `h3-harness-go/`):

46 tests — 6 categories — exit code 0 means your harness is H3-compliant. For 46/46: a message containing `do not finish` must return `text` with `finished: false` — see [docs/integration.md §5.1](docs/integration.md#51-conventions-the-battery-enforces).

Or scaffold a new harness in 30 seconds:

```bash
hermes-h3 scaffold --lang go
cd h3-harness-go && go mod tidy && go run .
h3-test --endpoint http://localhost:9191
```

> **Run one harness at a time — both quick-start paths bind `:9191`.** The Go
> echo example and a freshly scaffolded harness use the same default port, so
> stop the running one (Ctrl-C) before starting the other; otherwise the second
> exits with `listen tcp :9191: bind: address already in use`. All four targets
> honor `PORT` (`PORT=9291 python main.py`, `PORT=9291 npm run dev`, `PORT=9291
> go run .`), so stop the first harness or give the second one a different port.

> The CLI is `hermes-h3` (standalone binary with `install`, `scaffold`, `test`,
> `verify`, and more). The `hermes h3` plugin form requires H3 wired into a
> live Hermes install (tracked as WIRING-01).

## Make your first call

A harness exposes six REST endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v1/health` | GET | Liveness + capabilities |
| `/v1/process` | POST | Send a user message; the harness answers with a `Decision` |
| `/v1/result` | POST | Report the outcome of the previous decision |
| `/v1/cancel` | POST | Abort a running session |
| `/v1/sessions/{session_id}` | GET | Session metadata (`session_id`, `started_at`, `last_active`, `turn_count`, `status`); 404 for an unknown session |
| `/v1/sessions/{session_id}` | DELETE | Tear down a session's server-side state |

With a harness on `:9191` (see Quick Start), this is a complete first call. All
four top-level objects are REQUIRED, and the JSON Schemas also require
`message.timestamp` and the five `context.session_state` fields. Omitting any of
them makes the payload schema-invalid — harnesses that validate against the
schemas reject it, while the bundled echo examples are laxer and may accept it
silently. Copy this payload and you are schema-valid:

```bash
curl -s http://localhost:9191/v1/process \
  -H 'Content-Type: application/json' \
  -d '{
  "session_id": "s_abc123",
  "message": {"role": "user", "content": "Deploy the auth endpoint to staging",
              "timestamp": "2026-09-18T14:00:00Z"},
  "identity": {"platform": "telegram", "chat_id": "-1003310984808",
               "thread_id": "84802", "user_name": "Bane", "user_id": "6849342682"},
  "context": {
    "history": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}],
    "tools": [{"name": "terminal", "description": "Execute shell commands", "parameters": {}}],
    "models": [{"name": "deepseek-v4-pro", "provider": "deepseek-foreman", "context_window": 128000}],
    "memory": "Last deployment used Docker Compose.",
    "config": {"max_iterations": 50, "timeout_seconds": 600},
    "session_state": {"turn_count": 4, "total_tool_calls": 3, "total_llm_calls": 2,
                      "cost_so_far": 0.0156, "started_at": "2026-09-18T13:55:00Z"}
  }
}'
```

The harness answers with a `Decision` — verbatim body (HTTP 200) captured from
the Go echo example on `:9191`:

```json
{"decision":"text","decision_id":"echo-001","history":[{"role":"user","content":"..."},{"role":"assistant","content":"..."}],"text":{"content":"Echo: Deploy the auth endpoint to staging","finished":true}}
```

The full contract — every endpoint, every field — lives in
[`docs/integration.md`](docs/integration.md); the JSON Schemas in
[get-h3/protocol](https://github.com/get-h3/protocol) are the single source of
truth, and the examples in these docs are validated against them.

## Repositories

| Repo | Purpose | Language |
|------|---------|----------|
| [h3](https://github.com/get-h3/h3) | **You are here.** Spec hub, task board, documentation website | Markdown |
| [protocol](https://github.com/get-h3/protocol) | OpenAPI 3.1 spec + JSON Schema — single source of truth | YAML/JSON |
| [shim](https://github.com/get-h3/shim) | Hermes plugin: shim loop, 46-test battery, CLI (`hermes-h3`; `hermes h3` plugin form is WIRING-01-gated) | Python |
| [sdk-go](https://github.com/get-h3/sdk-go) | Go SDK for building harnesses | Go |
| [sdk-python](https://github.com/get-h3/sdk-python) | Python SDK for building harnesses | Python |
| [sdk-typescript](https://github.com/get-h3/sdk-typescript) | TypeScript SDK for building harnesses — **not on npm** (GitHub dependency) | TypeScript |

## Architecture

H3 follows a **spec-driven, protocol-first** architecture:

```
protocol/  (OpenAPI 3.1 — single source of truth)
    │
    ├──► shim/           (Hermes-side plugin — Python)
    │     └── test_battery.py  (46 compliance tests)
    │
    ├──► sdk-go/         (Harness Go SDK — generated types)
    ├──► sdk-python/     (Harness Python SDK — generated types)
    └──► sdk-typescript/ (Harness TS SDK — generated types)
```

All SDKs generate their types from the same OpenAPI spec. A change to the protocol propagates to every SDK. The test battery verifies compliance against any harness in any language.

### The Loop

1. Hermes sends a **ProcessRequest** (text, tool_call, or tool_result)
2. The harness returns a **Decision** (text, tool_call, end, or wait)
3. Hermes executes the decision and sends back a **ResultRequest**
4. The harness returns another Decision
5. Loop until the harness returns `Decision.end`

## Documentation

- **Website:** [get-h3.github.io/h3/](https://get-h3.github.io/h3/) — landing page, language picker, quickstart (old marketing domain is dead — NXDOMAIN)
- **Specs:** [`specs/`](specs/) — 26 specs, ~320 pages covering architecture, protocol, SDKs, installer, test battery, release pipeline, website, and upgrade survival
- **PRD:** [`prd.html`](prd.html) — the product requirements document (canonical)
- **Protocol reference:** [`docs/protocol.html`](docs/protocol.html) — auto-generated from OpenAPI
- **SDK reference:** [`docs/sdk.html`](docs/sdk.html) — auto-generated
- **Build guide:** [`docs/guide.html`](docs/guide.html) — "Build Your First H3 Harness" tutorial
- **Migration guide:** [`docs/migration.html`](docs/migration.html) — migrating from native Hermes to H3
- **Integration guide:** [`docs/integration.md`](docs/integration.md) — for external harness developers (OpenCode, Consensus, CrewAI, LangChain) wiring H3 into their own systems
- **Release guide:** [`docs/releases.md`](docs/releases.md) — tag convention, how to pin and verify a tagged release (`git checkout v0.1.0 && make verify`), and what `make verify` does and does not cover

## Repository Layout

This repo is the H3 spec hub. Tracked content is markdown, the JSONL task board,
and two small generated indexes — there is no build output in the tree, so
`git status` is a meaningful signal and every tracked path below is either
hand-maintained or checked by `make verify`.

| Path | What lives there |
|------|------------------|
| Root docs — `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `DEPLOY.md`, `GOVERNANCE.md`, `SECURITY.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`, `TRADEMARK_POLICY.md`, `CODEOWNERS`, `CHANGELOG.md`, `LICENSE`, `NOTICE` | Governance, onboarding, deployment and release history |
| [prd.html](prd.html) | The canonical product requirements document |
| [journey-narrative.md](journey-narrative.md) | How a Hermes agent bootstrapped its own coding fleet — the narrative behind the foreman workflow below |
| [specs/](specs/) | The specification set; [specs/_index.md](specs/_index.md) is its manifest, and `make verify` keeps index and files in agreement |
| [docs/](docs/) | The published site (`index.html`, `guide.html`, `protocol.html`, `sdk.html`, `migration.html`) plus the guides [docs/integration.md](docs/integration.md), [docs/releases.md](docs/releases.md) and [docs/qa-target-contract.md](docs/qa-target-contract.md) |
| `docs/badge/`, `docs/board/`, `docs/dogfood/` | Generated compliance badges, board decision records, and dated dogfood field reports |
| [integration/roundtrip/](integration/roundtrip/) | The cross-language round-trip code suite and its generated fixtures |
| [scripts/](scripts/) | The zero-dependency guards behind `make verify`; `scripts/test-count.txt` is the single home of the compliance-test count |
| `skills/` | Fleet agent skills — [h3-usage](skills/h3-usage/SKILL.md) and [h3-pm-usage](skills/h3-pm-usage/SKILL.md) |
| [Makefile](Makefile) | The verification entry point (`make verify`, `make verify-roundtrip`, `make verify-all`) |
| `.coding-hermes/` | The task board: `board/*.jsonl` is the git-backed store, `tasks.md` is legacy prose history, `dogfood-log.md` is the dogfood lane's own record |
| `.vfs/` | The hilo code-graph index — `manifest.yaml` and `graph/edges.jsonl` are the only tracked files in it |
| `.github/`, `.gitreins/`, `.gitignore`, `.gitleaks.toml` | CI workflows, the GitReins gate config and lane task mirror, and the ignore / secret-scan contracts |

### Not tracked on purpose

Local stores and rebuildable caches are declared in `.gitignore` instead of being
deleted, so that a clean `git status` means something:

- `.vfs/graph/` hilo caches (`graph.db*`, `.last_warm`, `.last_reconcile`, `.parse_cache.json`) and the `.vfs/.dirty` runtime marker — a local dirty flag the hilo hooks write on hosts without `hilo` on `PATH` and remove again on merge, never committed content.
- `dagger.db*` — Dagger MCP runtime state, recreated by worker sessions.
- `.gitreins/history/` and `.gitreins/logs/` — gate verdict records and guard run logs.
- `.coding-hermes/board/board.db` and `.coding-hermes/board/*.parquet` — rebuildable board caches; the JSONL files are the store.
- `namespaces/` — the local memory-bank store checkout fleet tooling drops into the workdir (H3-GAP-084). It is foreign to this repo and is never committed.
- `.cross-harness-results/` and `_run_cross_harness.sh` — cross-harness run artifacts. The tool-managed caches (`.pytest_cache/`, `.ruff_cache/`, `integration/roundtrip/__pycache__/`) carry their own ignore files inside the directory.

## Compliance

A harness is H3-compliant when it passes all 46 tests in the [test battery](https://github.com/get-h3/shim). Current compliance status across SDK examples:

| Language | Evidence | CI-verified | Published |
|----------|----------|:-----------:|-----------|
| Go (echo) | 46/46 — foreman E2E tick #355 ran the battery against the Go echo harness on :9191 (p50 1.31ms / p95 45.93ms) | ✅ | source (`go get github.com/get-h3/sdk-go`) |
| Python (echo) | 46/46 — local battery run | — | PyPI: `pip install h3-harness-sdk` |
| TypeScript (echo) | 46/46 — local battery run | — | **not published on npm** (`npm view @get-h3/h3-harness-sdk` → E404) — install from source (GitHub dependency) |

**CI-verified** means the run is captured in repo CI or a foreman E2E tick; Go is currently the only SDK with in-repo E2E evidence (tick #355 on :9191). Python and TypeScript pass locally but have no in-repo runnable CI evidence yet.

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

**Verification:** the scope is deliberately split in two.

- `make verify` — docs + repo-consistency guards **only** (docs-link, spec-index-vs-files, compliance-test count, json-fence payload, QA-target contract, DuckBrain tick-chain drift census, board-header self-consistency, commit-message skip-directive). Zero *required* dependencies, so it runs on a fresh clone, and it **executes no SDK code**.
- `make board-close` — the **board-writing close-out** (DF-H3-25), and the write side of the board-header guard. Every board-writing tick ends with it *before* the board commit: it rewrites line 1 of `.coding-hermes/board/board.jsonl` with `last_commit` = the current `HEAD`, `ticks_total` = the highest tick recorded in `events.jsonl`, and `last_tick` = now (UTC), leaving every other line byte-for-byte intact. It is idempotent, and it refuses — non-zero, nothing written — rather than guess when the board files, git history or the header itself are unreadable. The header is a *write* problem: the write-back was a best-effort post-push hook and was skipped by five ticks (#459, #463/#464, #480, #481), which is what made fresh public clones fail `make verify`; a guard catching it was never a fix. When the close-out is skipped anyway, the guard now prints the greppable fleet line `PUBLIC-HEAD-VERIFY-FAIL:` (alert recipe in `scripts/check-board-header-consistency.sh`) alongside its FAIL. Negative proof: `make verify-board-sync-selftest` (and the writer is covered by `make verify-board-header-selftest` too).
- `make verify-tick-chain` — the DuckBrain tick-key census for namespace `h3` (H3-GAP-098). It reads the whole key tree (read-only, tree endpoint) and classifies every tick-ish path: the canonical bare `/tick/<N>` chain, the pre-#418 legacy series (`/project/h3/tick/408..427`), **drift** (any other path ending in `/tick/<N>`, `N >= 418`), and legitimate timestamped slug keys (non-fatal). The bare chain must be complete from 418 to the board's `ticks_total - 1`, and no unknown-shaped tick key may exist: the two twins tick #459 deliberately backfilled (452/453) are allowlisted and warned, every other drifted key **fails** — a census that read only the bare keys is what reported the drifted ticks #452/#453 as "contiguous". When DuckBrain, `jq`, `curl`, the token file or the board header is missing it prints an explicit `UNVERIFIED` and exits 0 (absent tooling is UNVERIFIED, never a pass). Negative proof: `make verify-tick-chain-selftest` (fixtures in `scripts/fixtures/tick-chain/`).
- `make verify-roundtrip` — the cross-language round-trip **code** suite (Python → Go, Go → Python, Go → TypeScript). Requires the sibling SDK repos (`sdk-python`, `sdk-go`, `sdk-typescript`) on disk next to this one, plus `go`/`node`/`npx`; see [CONTRIBUTING.md](CONTRIBUTING.md).
- `make verify-qa-target` — asserts the QA/verification **target** is a real checkout of this repo, and takes a candidate directory as an argument so a runner can pre-flight its own target. A target path that does not exist, is not a git work tree, or is a sibling repo fails with a non-zero exit instead of degrading into an empty result that reads as clean — zero cells is UNVERIFIED, never a pass. Runs as part of `make verify`; its negative proof is `make verify-qa-target-selftest`; the contract is [docs/qa-target-contract.md](docs/qa-target-contract.md).
- `make verify-all` — both, in order.
- CI runs the round-trip only via `.github/workflows/roundtrip.yml`, which is **path-filtered to `integration/roundtrip/**`** — so a docs-only push gets green CI that never executed that suite. A green check is not by itself proof that code ran; check which workflow actually fired.

**Contributing:** see [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow, code of conduct, and governance.

## License

[MIT](LICENSE) — The get-h3 organization.
