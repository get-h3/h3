# H3 Integration Guide — Wiring an Existing Agent System

H3 (Hermes Harness Hooks) is a **brain-swap protocol**: your existing agent
system (OpenCode, CrewAI, LangChain, Consensus, or any custom loop) becomes
the *brain* of Hermes. Hermes stays the *body* — messaging platforms,
tool execution, memory, session routing — and delegates every thinking step
to your agent over plain HTTP.

This guide is for integrators who already HAVE an agent system and want to
wire it into Hermes. It covers the harness side: exposing your agent as an
H3 endpoint, translating its decisions into H3's Decision envelope, and
proving compliance with the 44-test battery.

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
  "message": {"role": "user", "content": "Deploy the auth endpoint to staging"},
  "identity": {"platform": "telegram", "chat_id": "-1003310984808",
               "thread_id": "84802", "user_name": "Bane", "user_id": "6849342682"},
  "context": {
    "history": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}],
    "tools": [{"name": "terminal", "description": "Execute shell commands", "parameters": {}}],
    "models": [{"name": "deepseek-v4-pro", "provider": "deepseek-foreman", "context_window": 128000}],
    "memory": "Last deployment used Docker Compose.",
    "config": {"max_iterations": 50, "timeout_seconds": 600}
  }
}
```

Your agent replies with a `Decision` — a discriminator + `decision_id`
(both REQUIRED) plus the type-specific payload:

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
  "decision_id": "d_9e4f",
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
  "decision_id": "d_7b2c",
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

Install the shim (one command, from source — the package is not on PyPI
yet):

```bash
pip install git+https://github.com/get-h3/shim
```

Then run the 44-test compliance battery (6 categories: health, process,
decision types, result handling, error & edge cases, stress) against your
harness:

```bash
h3-test --endpoint http://localhost:9191          # human-readable
h3-test --endpoint http://localhost:9191 --json   # machine-readable
```

| Exit | Meaning |
|------|---------|
| `0` | Compliant — the target is an H3 endpoint and all 44 checks passed. |
| `1` | Compliance failure — the target answered `/v1/health` correctly but some protocol checks failed. Fix the harness (run with `--json` for per-test detail). |
| `2` | NOT an H3 endpoint — connection refused, non-JSON body, HTTP ≥ 400, or a `/v1/health` payload missing required fields. This is not a protocol regression: check the URL and that the harness is running. |

The SDK echo examples are battery-passing reference implementations — if
your harness fails a check, diff your payloads against theirs.

## 6. SDKs and scaffolding

| SDK | Install | Echo example (reference, passes 44/44) |
|-----|---------|----------------------------------------|
| Go | `go get github.com/get-h3/sdk-go` | `sdk-go/examples/echo` → `go run .` on :9191 |
| Python | `pip install git+https://github.com/get-h3/sdk-python` | `sdk-python/src/h3_harness/examples/echo.py` |
| TypeScript | `npm install github:get-h3/sdk-typescript` | `sdk-typescript/src/examples/echo.ts` |

Or scaffold a fresh harness project:

```bash
hermes-h3 scaffold --lang go     # or py / ts
cd h3-harness-go && go mod tidy && go run .
```

Each SDK implements the `Harness` interface (Go: 5 methods — `OnProcess`,
`OnResult`, `OnCancel`, `OnSessionTerminate`, `Health`); you implement those
methods over your existing agent loop and the HTTP server, middleware,
routing, and type generation are handled for you.

## 7. Next steps

- **Full protocol spec**: `get-h3/protocol` → `h3-protocol.yaml` (OpenAPI 3.1) + `schemas/v1/`
- **Specs**: `get-h3/h3` → `specs/02-Protocol-Specification.md`, `specs/04-SDK-Libraries.md`, `specs/05-Test-Battery.md`, `specs/06-Hermes-Core-Integration.md`
- **Hermes-side wiring** (config, session routing, circuit breaker): shim `docs/integration.md`
- **Live example end to end**: `docs/dogfood/2026-08-02-integration.md`
