---
name: h3-usage
description: >-
  How to USE the get-h3 fleet (Hermes Harness Hooks — brain-swap protocol).
  Entry points, run commands, pitfalls, and the right-way patterns, learned
  from real dogfood runs (2026-08-02, refreshed 2026-08-14). Load this
  before working with any get-h3 repo: h3 (spec hub), protocol, shim,
  sdk-go, sdk-python, sdk-typescript.
version: 1.2.0
category: software-development
---

# H3 Usage — Building and Verifying Hermes Harnesses

H3 lets an external agent system (OpenCode, LangChain, CrewAI, your own
harness) act as the thinking brain of Hermes. Hermes is the body; the H3
protocol is the neural link. This skill is the *user manual* — how to
actually build, run, and verify a harness. Pitfalls refreshed from real
dogfood runs (2026-08-02, 2026-08-14, 2026-09-23).

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
  # → installs h3-test + hermes-h3 into ./.venv/bin — NOT your global PATH
  ```
- **`h3-test` / `hermes-h3` are venv console scripts, and activation is
  shell-local (DF-H3-5).** `uv venv` (or `python3 -m venv`) plus the install
  above puts both scripts in the venv's `bin/`; nothing is installed globally
  (`hermes-h3-shim` is not on PyPI). A **new terminal has neither** — it fails
  with `h3-test: command not found`. In a fresh shell pick one, all equivalent:
  ```bash
  source .venv/bin/activate                 # re-activate (run from the venv's directory)
  export PATH="$PWD/.venv/bin:$PATH"        # or export the venv bin dir once per shell
  .venv/bin/h3-test --endpoint http://localhost:9191   # or call the script by explicit path
  ```
  Every bare `h3-test` / `hermes-h3` in this skill assumes one of those is in
  effect for the current shell.
- The CLI binary is **`hermes-h3`**, not `hermes h3` (that form needs the
  plugin wired into live Hermes — WIRING-01, still open).
- Local SDK development only: editable install with
  `uv pip install --python .venv/bin/python -e $HOME/get-h3/sdk-python`.

## Fastest verified path to 46/46 (Go)

# Battery count is 46 as of 2026-09-08 (GAP-045 wave); "44" anywhere = stale.

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

### Pitfall: decision_id must be a UUID in the TypeScript SDK (DF-H3-6)
`createH3Router` (TS) validates `decision_id` with a UUID Zod schema —
`"echo-001"` style ids 500 with `INVALID_DECISION`. The Go example ships
non-UUID ids and passes (Go validation is lenient). **Use
`crypto.randomUUID()` in every TS/Node harness.** Contract drift is filed
as DF-H3-6; until it's pinned in the protocol spec, treat UUID as the safe
form everywhere.

### Pitfall: the battery has undocumented trigger phrases (DF-H3-7)
`h3-test` sends messages containing "do not finish", "start a thought",
"...", "incomplete", "partial" and expects `finished:false` (continuation);
a harness that always sets `finished:true` fails ~15/46 with confusing
detail lines, and `end.reason` must be the schema enum (`task_complete`,
NOT "completed"). **Read the echo example for your SDK before writing
onProcess/onResult — the example IS the spec for the battery.**

### Pitfall: the README says decision type "tool_use" — the wire enum is `tool_call` (DF-H3-27)
README line ~171 ("text, tool_use, end, or wait") disagrees with the protocol:
the decision field is `tool_call` (py SDK `DecisionType.TOOL_CALL`; the pydantic
sub-field is still named `tool_use=`). A docs-following developer writes
`DecisionType.TOOL_USE`, gets `AttributeError`, and the router MASKS it: the
endpoint returns HTTP 200 `{decision: "end", end: {reason: "error",
summary: "<exception text>"}}` — the loop silently stops while looking
compliant. **Always read `end.summary` on an unexpected `end` decision, and
`grep end.summary server.log` — the SDK logs `on_process failed — masked as ...`
there.** `create_router(..., debug_errors=True)` raises instead (dev mode).

### Pitfall: `on_result` gets NO context, and `result` is a plain dict (DF-H3-28)
`ResultRequest` carries exactly `decision_id`, `result`, `session_id` — there is
no `context`/`history` on the result leg (echo the history you want in each
Decision yourself). `req.result` is `dict[str, Any]`: the typed `ResultPayload`
class is exported but never attached, so `req.result.success` (attribute access)
silently returns `False` — use `req.result.get("success")`. Chained-tool
example: `on_result` returns the NEXT `tool_call` decision; see
`docs/dogfood/2026-09-23-integration.md`.

### Pitfall: fresh Debian has no venv/ensurepip (DF-H3-8)
On stock Debian (docker/cloud images, rootless agents), `python3 -m venv`
dies asking for `apt install python3.13-venv`. Working no-sudo fallback:
```bash
python3 -m venv --without-pip .venv
curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
.venv/bin/python /tmp/get-pip.py && .venv/bin/pip install -e .
```

### Pitfall: Go example and Go scaffold ignore PORT (DF-H3-9)
`sdk-go/examples/echo` and the Go scaffold hardcode `:9191` (main.go:100 /
scaffold main.go:148). `PORT=9291` is silently ignored. Use a
non-default port only via source edit for Go targets; TS/py honor PORT.

- **Round-trip with curl (verified live 2026-09-08):** the working process
  shape needs the full envelope — `session_id`, `message{role,content,timestamp}`,
  `identity{user_id,platform,chat_id,user_name}`, `context{}` — and the
  result route is FLAT `POST /v1/result` (not `/v1/sessions/{id}/result`).
  The error messages walk you in one field at a time; the full working
  curl pair is in `docs/dogfood/2026-09-08-integration.md`.
- **Port collisions are silent killers — and can be silent FALSE PASSES
  (DF-H3-15 → DF-H3-26).** `h3-test` tests whatever listens on the port. The
  Python echo example hardcodes `:8000`/`:9191`; if your harness fails to bind
  (log redirect broken, port taken), the battery happily validates the
  co-tenant process — on a shared bunker a 2.6-day-old stranger's harness
  scored 46/46 while the harness under test never started. **Always
  `curl <endpoint>/v1/health` FIRST and check `uptime_seconds` is small and
  `version` matches the SDK you just installed** (git-main py SDK = 0.1.6 as
  of 2026-09-23; a mismatch means something else is listening). Use
  `ss -tlnp` to confirm ownership.
- **`go run .` fails with `unknown revision v0.0.0`** → stale local go.mod;
  sdk-go v0.1.0+ is published, so `go mod tidy` fetches it — add a
  `replace` directive only for local SDK dev.
- **Scaffolds are battery-clean since DOGFOOD-07/08/09 landed** (verified
  go + py 44/44, exit 0 on 2026-08-17, tick #317): go template pins sdk-go
  v0.1.1 (cancel-404 fix); py scaffold 404s unknown-session cancel; ts
  scaffold installs via github:get-h3/sdk-typescript (npm E404 workaround).
  Still, after scaffolding ALWAYS run `h3-test` — don't trust "it builds".
- **`POST /v1/cancel` on an unknown session must return 404**
  `SESSION_NOT_FOUND` (battery `cancel_unknown_session`); returning
  200 `{cancelled: true}` unconditionally fails the battery. Track sessions
  and check existence in the cancel route.
- **`hermes-h3` config path:** resolved highest-first as
  `--config <path>` (accepted before or after a subcommand) →
  `$HERMES_H3_CONFIG` → `~/.hermes/h3/config.yaml`. The env var is honored
  by every subcommand since the DF-H3-10 fix (shim commit 493357d) —
  on an older shim build it was silently ignored and every command fell
  back to the real `~/.hermes/h3/config.yaml`, so pin `--config` there.
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
