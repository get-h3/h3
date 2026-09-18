# H3 Integration Guide — Wiring an Existing Agent System

H3 (Hermes Harness Hooks) is a **brain-swap protocol**: your existing agent
system (OpenCode, CrewAI, LangChain, Consensus, or any custom loop) becomes
the *brain* of Hermes. Hermes stays the *body* — messaging platforms,
tool execution, memory, session routing — and delegates every thinking step
to your agent over plain HTTP.

This guide is for integrators who already HAVE an agent system and want to
wire it into Hermes. It covers the harness side: exposing your agent as an
H3 endpoint, translating its decisions into H3's Decision envelope, and
proving compliance with the 46-test battery.

If you instead want to install and manage the Hermes side (registering
harnesses, routing sessions, the `hermes-h3` CLI), see the shim's own
[integration guide](https://github.com/get-h3/shim/blob/main/docs/integration.md).

## 1. The contract in one picture

```
user message ──► Hermes (body) ──► shim loop ──► YOUR AGENT (brain, HTTP)
                     ▲                              │
                     └────── result/tools ──────────┘
```

Your agent exposes five REST endpoints (OpenAPI source of truth:
`get-h3/protocol` → `h3-protocol.yaml`):

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v1/health` | GET | Liveness + capabilities. Hermes health-checks this every 30 s. |
| `/v1/process` | POST | Give the agent a user message + context; it returns a `Decision`. |
| `/v1/result` | POST | Report the outcome of the previous decision (tool output, LLM text). |
| `/v1/cancel` | POST | Abort a running session. |
| `/v1/sessions/{session_id}` | DELETE | Tear down a session's server-side state. |

Any language works. The protocol is JSON over HTTP; the SDKs below generate
the types and provide a `Harness` interface + HTTP server so you only
implement the decision logic.

## 2. Step 1 — register your harness endpoint

Health payload (`GET /v1/health`) — the four fields are REQUIRED; exit code
2 from `h3-test` means exactly one of them was missing or malformed:

```json
{
  "status": "ok",
  "version": "1.0.0",
  "transport": "rest",
  "protocol_version": "1.0",
  "capabilities": ["text", "tool_call", "llm_call"]
}
```

`capabilities` lists the Decision types your agent can emit (see §3). The
minimal compliant harness is `["text"]`.

## 3. Step 2 — translate your agent's decisions into the Decision envelope

`POST /v1/process` carries the turn:

```json
{
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
}
```

Every field list above is enforced by the JSON Schemas in `get-h3/protocol`
→ `schemas/v1/` (`process-request.json` + `common.json`); this example is
validated against them. A payload that omits a required field (for example
`message.timestamp`) is schema-invalid: a schema-validating harness rejects it,
while the bundled echo examples are laxer and may accept it silently.

Your agent replies with a `Decision` — a discriminator + `decision_id`
(both REQUIRED) plus the type-specific payload:

`decision_id` is a plain string per the protocol schema, but the TypeScript SDK validates
RFC 4122 UUIDs — emit a UUID (`uuid4()` / `crypto.randomUUID()`) so the same decision
is accepted by every SDK.

| `decision` | Payload | Meaning |
|------------|---------|---------|
| `text` | `text: {content, finished}` | Produce (streamed) reply text. `finished:false` = more text coming. |
| `tool_call` | `tool_call: {name, arguments}` | Ask Hermes to run a tool from `context.tools` and send the result back via `/v1/result`. |
| `llm_call` | `llm_call: {model, prompt, ...}` | Ask Hermes to run an LLM call (e.g. for small sub-tasks). |
| `wait` | `wait: {reason, ...}` | Pause the session (human approval, long-running work). |
| `delegate` | `delegate: {target, prompt}` | Hand the turn to another agent/harness. |
| `end` | `end: {reason, summary}` | Terminate the session. `reason` is `task_complete` or `task_failed`. |

Minimal text decision:

```json
{
  "decision": "text",
  "decision_id": "194854c3-ac0d-4f67-96a9-9a0a1c359597",
  "text": {"content": "Found the issue in auth.go:142 — missing JWT expiry check.", "finished": false}
}
```

## 4. Step 3 — wire the session loop

The shim drives the loop; your agent just answers it:

1. Hermes POSTs the user message to `/v1/process`.
2. Your agent returns a `Decision`.
3. Hermes executes it locally (tool call, LLM call, text delivery, …).
4. Hermes POSTs the outcome to `/v1/result`:

```json
{
  "session_id": "s_abc123",
  "decision_id": "dba151bd-5558-4e7f-af34-65f960b22cf2",
  "result": {
    "type": "tool_result",
    "tool_name": "terminal",
    "data": {"output": "✓ Auth endpoint deployed", "exit_code": 0},
    "duration_ms": 2843,
    "success": true
  }
}
```

5. Your agent inspects the result, returns the next `Decision`… repeat until
   you return `decision: "end"`.

The loop enforces a hard iteration cap (default 50) so a misbehaving harness
cannot spin forever, and propagates cancellation through `/v1/cancel`.

## 5. Step 4 — prove compliance: `h3-test`

Install the shim from source (the package is not on PyPI yet): clone the
repository and install the checkout in editable mode. Use a virtual
environment — required on PEP 668-managed Pythons (Ubuntu 24.04+,
Debian 12+), where a bare `pip install` fails with
externally-managed-environment:

```bash
git clone https://github.com/get-h3/shim && cd shim
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
```

`pip install -e .` writes the two console scripts — `h3-test` and
`hermes-h3` — into that venv's `bin/`. Activation is **shell-local**: it adds
them to PATH for the current shell only, so a fresh terminal (or a shell opened
before the install) has neither and fails with `h3-test: command not found`.
There is no global install — the package is not on PyPI. In a new shell pick one
of the three, all equivalent:

```bash
source .venv/bin/activate                            # re-activate (run from the venv's directory)
export PATH="/path/to/shim/.venv/bin:$PATH"          # or export the venv's bin dir once per shell
/path/to/shim/.venv/bin/h3-test --endpoint http://localhost:9191   # or call the script by path
```

Then run the 46-test compliance battery (6 categories — exact
`--categories` names: health, process, decisions, results, errors, stress)
against your harness:

```bash
h3-test --endpoint http://localhost:9191          # human-readable
h3-test --endpoint http://localhost:9191 --json   # machine-readable
```

| Exit | Meaning |
|------|---------|
| `0` | Compliant — the target is an H3 endpoint and all 46 checks passed. |
| `1` | Compliance failure — the target answered `/v1/health` correctly but some protocol checks failed. Fix the harness (run with `--json` for per-test detail). |
| `2` | NOT an H3 endpoint — connection refused, non-JSON body, HTTP ≥ 400, or a `/v1/health` payload missing required fields. This is not a protocol regression: check the URL and that the harness is running. |

The SDK echo examples are battery-passing reference implementations — if
your harness fails a check, diff your payloads against theirs.

### 5.1 Conventions the battery enforces

The battery is a black-box HTTP probe, but several of its checks key off the
*phrasing* of the message it sends and the *lifecycle* of the session it
creates — not only your status codes. A harness that is otherwise
protocol-correct can still fail them. Implement these deliberately; they are
the behaviours the battery asserts, quoted from the shipped source.

Line references are to the shipped battery
(`get-h3/shim` → `src/h3_shim/test_battery.py`, 46 tests — the count is pinned
by `EXPECTED_TEST_COUNT`, `test_battery.py:104`) and to the CLI
(`get-h3/shim` → `src/h3_shim/cli.py`).

**Unfinished-text trigger**

- The battery sends exactly `"Just start a thought, do not finish it yet."` —
  `test_battery.py:565` (the same string is sent again by the cancel test,
  `:1506`).
- It asserts the reply is a `text` decision whose `text.finished` is `false` —
  `test_battery.py:576-587`.
- Trigger detection is a **substring check on the message content**: the prompt
  contains both `"do not finish"` and `"start a thought"`, so matching either
  one is sufficient. The battery never sends `"incomplete"` or `"partial"` —
  those two extra keywords exist only in the TypeScript echo example's
  heuristic (`sdk-typescript/src/examples/echo.ts:23-28`), not in the battery.
- ⚠️ The test **skips and passes** when your harness answers that prompt with a
  non-`text` decision such as `end` — `test_battery.py:576-580`. It fails only
  when the answer *is* `text` and `finished` is not `false` (`:582-586`). So
  `finished=false` is required of harnesses that answer this prompt with text;
  it is not a hard failure for every harness.

**Finished-text counterpart**

- `"Give me the final answer in one short sentence."` — `test_battery.py:597`.
- It must come back as a `text` decision with `finished: true` —
  `test_battery.py:608-618` (same skip rule at `:608-612`).
- These two prompts are the battery's only phrasing-sensitive pair: a hardcoded
  `finished: true` fails 2.4 (`test_battery.py:582-586`) and a hardcoded
  `finished: false` fails 2.5 (`:614-617`).

**Multi-turn continuation contract**

- **`/v1/result` must accept the decision your harness returned.** The battery
  posts seven result types — `tool_result` (success and failure),
  `llm_response`, `text_sent`, `delegate_result`, `error`, `wait_timeout` —
  keyed by `decision_id`, and requires a response below HTTP 400
  (`test_battery.py:1189-1210` for `text_sent`; `:1240-1262` for `error`, where
  any non-5xx passes). An unreachable result endpoint fails the test
  (`:1204-1205`).
- **A `/v1/result` response may itself be the next decision.** The battery stops
  its round-trip loop early when the response carries `decision: "end"` —
  `test_battery.py:1631` (5.11) and `:1031` (3.6).
- **The battery does not post `/v1/result` after the "do not finish" prompt.**
  What it asserts after unfinished text is the **cancel path**: test 5.9
  creates a session with that prompt specifically to keep the session in flight
  (`test_battery.py:1500-1507`) and then requires `POST /v1/cancel` → 200 for
  that session (`:1514-1524`). If your harness treats an unfinished turn as
  "done" and discards the session, cancel answers 404 and the test fails — the
  source comment at `:1500-1504` names exactly this failure mode ("a
  non-streaming session completes in <1ms and can be purged before the cancel
  lands, causing an intermittent 404 race").
- **Unknown sessions must 404.** `POST /v1/cancel` for a session that never
  existed must return 404 (any 4xx accepted) — `test_battery.py:1528-1546`;
  `GET /v1/sessions/{unknown}` must return 404 or 405 — `:1550-1568`. A session
  that just accepted a process call must still be retrievable: 200, the echoed
  `session_id`, and an ISO-8601 `started_at` — `:1669-1731`.
- **Turn-to-turn state.** Ten consecutive `/v1/process` calls on one
  `session_id` must each return 200 — `test_battery.py:622-650`; two sessions
  must not bleed state into each other (`:654-687`); and each decision should
  echo a top-level `history` list that does not shrink relative to the
  request's `context.history` (`:691-728` — an absent `history` reads as `[]`
  and fails).
- **Not ending is not a failure.** 5.11 and 6.3 soft-pass when a session never
  reaches `end` (`test_battery.py:1634-1638`, `:1838-1843`) — but when your
  harness *does* emit `end`, `end.reason` must be one of `task_complete`,
  `user_requested`, `error`, `timeout`, `rate_limited`, `cancelled`
  (`:978-985`).
- **Timing budgets.** `/v1/health` under 500 ms (`test_battery.py:436`), each
  `/v1/process` under 5 s (`:1867`), 50 process calls inside 10 s (`:1776`);
  the client's per-request ceiling is 10 s (`:123`).

**Where the normative text lives.** The protocol-level statements of these
conventions are [specs/02 §4](../specs/02-Protocol-Specification.md)
(`finished` doubles as the streaming marker; the battery convention is spelled
out at `specs/02-Protocol-Specification.md:268`) and
[specs/05 §3](../specs/05-Test-Battery.md) (test 2.4 at
`specs/05-Test-Battery.md:76`, the compliance conventions at `:82-85`). This
subsection is the integrator-side summary of what the shipped battery does
when you run it.

**Running it, and the exit code.** `h3-test --endpoint http://localhost:9191`
(add `--json` for a machine-readable report). The process exits with exactly
one of three codes, defined in `shim/src/h3_shim/cli.py`:

| Exit | Meaning | Source |
|------|---------|--------|
| `0` | Compliant — the target is an H3 endpoint and every check passed. | `cli.py:417`; epilog at `cli.py:462` |
| `1` | Compliance failure — the target answered `/v1/health` correctly but protocol checks failed. | `cli.py:417`; epilog at `cli.py:463-464` |
| `2` | NOT an H3 endpoint — connection refused, non-JSON body, HTTP ≥ 400, or a `/v1/health` payload missing required fields (`cli.py:384`). Also returned for an unknown `--categories` token (`cli.py:393-401`). | `cli.py:384`, `cli.py:401` |

**The 6 categories and their counts.** Health & Protocol 7, Process Basic Flows
8, Decision Types 6, Result Handling 7, Error & Edge Cases 13, Stress &
Performance 5 — 46 total. The category lists are registered in the battery at
`test_battery.py:321-327`, `:470-477`, `:738-743`, `:1048-1054`, `:1298-1310`
and `:1741-1745`; the total is pinned at `:104`.

## 6. SDKs and scaffolding

| SDK | Install | Echo example (reference, passes 46/46) |
|-----|---------|----------------------------------------|
| Go | `go get github.com/get-h3/sdk-go` | `sdk-go/examples/echo` → `go run .` on :9191 |
| Python | `pip install git+https://github.com/get-h3/sdk-python` | `sdk-python/src/h3_harness/examples/echo.py` |
| TypeScript | `npm install github:get-h3/sdk-typescript` | `sdk-typescript/src/examples/echo.ts` |

Or scaffold a fresh harness project:

```bash
hermes-h3 scaffold --lang go     # or py / ts
cd h3-harness-go && go mod tidy && go run .
```

> `hermes-h3` is the same venv console script as `h3-test` — in a fresh shell see
> the three invocation forms in §5 (re-activate, PATH export, or the explicit
> `/path/to/shim/.venv/bin/hermes-h3` path) before running this block.

> **Echo, then scaffold — one at a time.** The Go echo example and a freshly
> scaffolded Go harness both bind `:9191`; stop one (Ctrl-C) before starting the
> other, or the second fails with `listen tcp :9191: bind: address already in
> use`. py/ts scaffolds honor `PORT`; Go echo and Go scaffold hardcode it (DF-H3-9).

Each SDK implements the `Harness` interface (Go: 5 methods — `OnProcess`,
`OnResult`, `OnCancel`, `OnSessionTerminate`, `Health`); you implement those
methods over your existing agent loop and the HTTP server, middleware,
routing, and type generation are handled for you.

## 7. Next steps

- **Full protocol spec**: `get-h3/protocol` → `h3-protocol.yaml` (OpenAPI 3.1) + `schemas/v1/`
- **Specs**: `get-h3/h3` → `specs/02-Protocol-Specification.md`, `specs/04-SDK-Libraries.md`, `specs/05-Test-Battery.md`, `specs/06-Hermes-Core-Integration.md`
- **Hermes-side wiring** (config, session routing, circuit breaker): shim `docs/integration.md`
- **Live example end to end**: `docs/dogfood/2026-08-02-integration.md`

## 8. Cross-repo round-trip CI (protocol-updated)

The umbrella's cross-language round-trip verification runs when the protocol
changes, and now also when an SDK repo is touched via its own sync workflow.

**Trigger chain.** The protocol repo sends a `repository_dispatch` event to
each SDK repo (and to `get-h3/h3` directly) when the OpenAPI spec changes.
Each SDK's `sync-protocol.yml` runs its sync/regenerate job, then a
`roundtrip` job that calls
`get-h3/h3/.github/workflows/roundtrip.yml@main` via a reusable workflow
(`workflow_call` — no secrets or PAT required). The h3 workflow itself can
also be run manually via `workflow_dispatch`, or directly dispatched with
`repository_dispatch` types `[protocol-updated]`. On `push`/`pull_request`
it fires only for in-repo changes under `integration/roundtrip/**`.

**Removed `../` path limitation.** The h3 round-trip workflow previously
listed `../` path filters (`../sdk-go/protocol/**`,
`../sdk-python/src/h3_harness/protocol.py`,
`../sdk-typescript/src/protocol.ts`) intending to trigger on SDK changes.
GitHub Actions path filters are repo-scoped — `../` patterns silently never
match — so the workflow never fired on SDK changes. Those filters are
removed; SDK-side triggers now come from each repo's own sync workflow
calling the reusable workflow instead.

**Sibling callers.** Each SDK repo's `sync-protocol.yml` ends with a
`roundtrip` job calling `get-h3/h3/.github/workflows/roundtrip.yml@main`:

| SDK repo | Caller job | Depends on |
|----------|------------|------------|
| sdk-go | `roundtrip` | `sync` |
| sdk-python | `roundtrip` | `regenerate` |
| sdk-typescript | `roundtrip` | `check-schema-alignment` |

`sdk-typescript` deliberately depends on `check-schema-alignment` (not
`release`, which is gated to `workflow_dispatch` only) so the round-trip
runs on both `repository_dispatch` and `workflow_dispatch` triggers.
