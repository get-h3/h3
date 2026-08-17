---
name: h3-usage
description: >-
  How to USE the get-h3 fleet (Hermes Harness Hooks — brain-swap protocol).
  Entry points, run commands, pitfalls, and the right-way patterns, learned
  from real dogfood runs (2026-08-02, refreshed 2026-08-14). Load this
  before working with any get-h3 repo: h3 (spec hub), protocol, shim,
  sdk-go, sdk-python, sdk-typescript.
version: 1.1.0
category: software-development
---

# H3 Usage — Building and Verifying Hermes Harnesses

H3 lets an external agent system (OpenCode, LangChain, CrewAI, your own
harness) act as the thinking brain of Hermes. Hermes is the body; the H3
protocol is the neural link. This skill is the *user manual* — how to
actually build, run, and verify a harness.

## What it is / repo map

| Repo | Role | Entry point |
|---|---|---|
| `h3` | Spec hub, cross-repo board, docs | `specs/02-Protocol-Specification.md` = the protocol |
| `protocol` | OpenAPI 3.1 `h3-protocol.yaml` — single source of truth | schemas + examples |
| `shim` | Test battery + CLI | `h3-test`, `hermes-h3` |
| `sdk-go` / `sdk-python` / `sdk-typescript` | Harness SDKs | echo examples in each repo |

## The loop you implement

1. Hermes → `POST /v1/process` (message + context) → you return a **Decision**
2. Hermes executes it → `POST /v1/result` → you return the next Decision
3. Repeat until Decision `end`

Decision types: `tool_call` · `llm_call` · `text` · `wait` · `delegate` · `end`.
Error shape: `{"error": {"code", "message", "details"}}` (codes in specs/02 §9).

## Setup (IMPORTANT — read first)

- The Python SDK **`h3-harness-sdk` IS on PyPI** (0.1.2, published
  2026-08-08): `pip install h3-harness-sdk` works.
- The shim package `hermes-h3-shim` is NOT yet on PyPI (blocked P3-10 -
  PYPI_API_TOKEN). `pip install hermes-h3-shim` FAILS. Install the shim
  from source:
  ```bash
  uv venv .venv
  uv pip install --python .venv/bin/python -e $HOME/get-h3/shim
  # → gives you h3-test and hermes-h3
  ```
- The CLI binary is **`hermes-h3`**, not `hermes h3` (that form needs the
  plugin wired into live Hermes — WIRING-01, still open).
- Local SDK development only: editable install with
  `uv pip install --python .venv/bin/python -e $HOME/get-h3/sdk-python`.

## Fastest verified path to 44/44 (Go)

```bash
cd /tmp && hermes-h3 scaffold --lang go --output-dir /tmp
# creates /tmp/h3-harness-go

# ✅ Verified 2026-08-17 (GAP-054): the scaffold IS battery-clean as shipped
# (DOGFOOD-07/08/09 landed). go scaffold pins sdk-go v0.1.1 (cancel-404 fix
# addb017 is in v0.1.1+); py scaffold 404s on unknown-session cancel; ts
# scaffold installs via github:get-h3/sdk-typescript (npm E404 workaround).
# Fresh go + py scaffolds verified 44/44, exit 0 on 2026-08-17 (tick #317):
#   cd /tmp/h3-harness-go && go mod tidy && go run . &
#   h3-test --endpoint http://localhost:9191   # 44/44, exit 0
```

## Verified 44/44 paths (SDK examples)

```bash
# Go (sdk-go main has the 404 fix):
git clone https://github.com/get-h3/sdk-go && cd sdk-go/examples/echo && go run . &
h3-test --endpoint http://localhost:9191   # 44/44, exit 0

# Python:
cd sdk-python && python3 -m venv .venv && . .venv/bin/activate && pip install -e .
python src/h3_harness/examples/echo.py &   # (script runner — NOT `uvicorn ...:app`)
h3-test --endpoint http://localhost:9191   # 44/44

# TypeScript:
cd sdk-typescript && npx tsx src/examples/echo.ts &
h3-test --endpoint http://localhost:9191   # 44/44
```

## Custom harness from the spec (Python, no SDK)

Read `specs/02-Protocol-Specification.md` — it is sufficient for ~41/44
immediately. To reach 44/44 you need TWO conventions that are only in SDK
example code (see docs/dogfood/2026-08-02-integration.md):

1. **History echo:** include a top-level `history` in the decision response,
   echoing `context.history` from the request:
   ```python
   dec["history"] = [{"role": e.get("role",""), "content": e.get("content","")}
                     for e in (body.get("context") or {}).get("history", [])]
   ```
2. **Streaming marker:** if the user content contains `"do not finish"`, a
   `text` decision must set `finished: false`; otherwise `true`:
   ```python
   finished = "do not finish" not in content
   ```

Minimal stdlib skeleton (proven 44/44): one handler per endpoint
(`/v1/health`, `/v1/process`, `/v1/result`, `/v1/cancel`, `/v1/sessions/:id`
GET+DELETE), a `_decision_*` helper per type, error envelope per §9.
~130 lines total.

## Common pitfalls

- **Port collisions are silent killers.** `h3-test` tests whatever listens
  on the port. The Python echo example hardcodes `:8000`; if it fails to
  bind (exit 3), the battery tests the WRONG server (looks like a baffling
  9/44 with `{"detail":"Not Found"}` health). Always `curl
  <endpoint>/v1/health` first, and use `ss -tlnp` to confirm ownership.
- **`go run .` fails with `unknown revision v0.0.0`** → stale local go.mod;
  sdk-go v0.1.0+ is published, so `go mod tidy` fetches it — add a
  `replace` directive only for local SDK dev.
- **Scaffold output is NOT 44/44 as of 2026-08-14** (DOGFOOD-07/08/09):
  `hermes-h3 scaffold --lang go` pins sdk-go v0.1.0 → 43/44
  (`cancel_unknown_session`); `--lang py` → 43/44 (same); `--lang ts` →
  `npm install` E404 (dep on unpublished `@get-h3/h3-harness-sdk`). Until the
  template fixes land, use the SDK echo examples for a guaranteed-compliant
  harness, and after scaffolding ALWAYS run `h3-test` — don't trust "it
  builds".
- **`POST /v1/cancel` on an unknown session must return 404**
  `SESSION_NOT_FOUND` (battery `cancel_unknown_session`); returning
  200 `{cancelled: true}` unconditionally fails the battery. Track sessions
  and check existence in the cancel route.
- **`hermes-h3` config path:** use `--config <file>` explicitly;
  `HERMES_H3_CONFIG` env is not honored by all subcommands.
- **Health path is `/v1/health`**, not `/health` (a plain `curl /health`
  gives 404 — that's fine).
- **Verify command:** `hermes-h3 verify --harness <name>` (it takes
  `--harness`, not a positional).
- **The board** is JSONL-canonical (`.coding-hermes/board/`): `tasks.jsonl`
  holds the live task matrix, `events.jsonl` the tick log, `fixtures.jsonl`
  the fixture windows. `tasks.md` remains only as a legacy tick-log mirror
  for transition continuity.

## Verifying compliance

```bash
h3-test --endpoint http://localhost:9191          # human report
h3-test --endpoint http://localhost:9191 --json   # machine report (per-test detail)
h3-test --endpoint http://localhost:9191 --categories health,process
echo $?  # 0 = compliant, 1 = not
```

Management flow (all verified working):

```bash
hermes-h3 --config /tmp/h3config.yaml install my-harness --endpoint http://localhost:9191
hermes-h3 --config /tmp/h3config.yaml list
hermes-h3 --config /tmp/h3config.yaml verify --harness my-harness
hermes-h3 --config /tmp/h3config.yaml test --endpoint http://localhost:9191
```

## Reference

- Protocol: `specs/02-Protocol-Specification.md` (umbrella repo)
- Battery: `specs/05-Test-Battery.md`, `shim/src/h3_shim/test_battery.py`
- SDK patterns: `sdk-go/examples/echo` (or `h3-harness-go/main.go` after
  scaffold), `sdk-python/src/h3_harness/examples/echo.py`
- This run's evidence: `docs/dogfood/2026-08-02-integration.md`,
  `docs/dogfood/diagnostics.md`
