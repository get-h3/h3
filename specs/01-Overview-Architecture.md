# S01 — H3 Overview & Architecture

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. What Is H3

H3 (Hermes Harness Hooks) is the two-endpoint protocol that decouples Hermes Core (the platform) from agent harnesses (the brain). Any harness implementing the H3 contract can use every Hermes capability — Telegram, Discord, Slack, tools, models, credentials, skills, cron, MCP, delegation — without touching platform code.

### The Split

| Hermes Core Owns | Harness Owns |
|---|---|
| Gateway (Telegram, Discord, Slack, Web) | Agent loop — reasoning, planning, iteration |
| Tool registry & execution (sandboxing, auditing) | Context management — what goes in the window |
| Model routing (provider selection, fallback, rate limits) | Memory architecture — how state persists |
| Credential vault (API keys, rotation, scoping) | Decision strategy — when to tool-call vs respond |
| Scheduling (cron, skills, persistence) | Failure recovery — retry, fallback, escalation |
| MCP server/client management | Prompt engineering — system prompts, templates |
| Plugin system | Delegation logic — sub-task orchestration |
| Multi-platform I/O | Response formatting |

### Design Principle

> Hermes asks: "What should I do?" The harness answers. Hermes executes. Hermes reports back. Loop.

The harness never touches files, never manages API keys, never configures gateways. It *thinks*. Hermes *does*.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────┐
│                 HERMES CORE                      │
│  Gateway │ Tools │ Models │ Creds │ Cron │ MCP  │
│                     │                            │
│              H3 Shim Loop                        │
│         (hermes_cli/agent/shims/h3/)            │
│                     │                            │
│              REST / gRPC                         │
│                     │                            │
│         ┌───────────┴───────────┐               │
│         │                       │               │
│    Consensus (Go)         LangChain (Py)         │
│    CrewAI (Py)           Custom (any lang)       │
└─────────────────────────────────────────────────┘
```

### Hermes-Side Components

```
hermes_cli/agent/shims/h3/
├── __init__.py
├── protocol.py       # Pydantic models — the contract
├── client.py         # REST + gRPC client
├── loader.py         # Discover harnesses, health-check, route sessions
├── native.py          # Wraps Hermes native loop as H3 harness (symmetry)
└── test_battery.py    # Compliance tests (see S05)
```

### Harness-Side Requirements

Three endpoints. That's it.

```
GET  /v1/health    → {"status": "ok", "version": "1.0", "transport": "rest"}
POST /v1/process   → Hermes asks: "New message. What should I do?"
POST /v1/result    → Hermes reports: "I did what you asked. Now what?"
```

---

## 3. Session Lifecycle

```
USER MESSAGE ARRIVES (Telegram/Discord/Slack/Web)
  │
  ▼
Hermes Gateway
  │  Authenticate, rate-limit, resolve session
  ▼
H3 Shim Loader
  │  Look up session → harness mapping from config
  │  If harness unreachable → fallback to native
  ▼
H3 Shim Loop
  │
  ├─► POST /v1/process (session_id, message, context, tools, models)
  │     │
  │     ▼
  │   Harness thinks → returns Decision
  │     │
  │     ▼
  │   Decision Router:
  │     ├─ tool_call  → Hermes executes tool, POST /v1/result, loop
  │     ├─ llm_call   → Hermes routes to LLM, POST /v1/result, loop
  │     ├─ text       → Hermes sends to user, POST /v1/result if not finished
  │     ├─ wait       → Hermes pauses, resumes with POST /v1/process
  │     ├─ delegate   → Hermes spawns sub-agent, POST /v1/result, loop
  │     └─ end        → Session terminates
  │
  ▼
USER RECEIVES RESPONSE
```

---

## 4. Transport Comparison

| Property | REST | gRPC |
|---|---|---|
| **Language support** | Every language. Works in curl. | Proto compilation required. |
| **Streaming** | Server-Sent Events for partial results | Native bidirectional streaming |
| **Debuggability** | `curl` + `jq`. Zero tooling. | `grpcurl` + proto files needed |
| **Latency** | Good for normal loops (5-50 decisions/task) | Better for high-frequency (100+ decisions) |
| **Default** | ✅ REST first | Opt-in for advanced users |

### REST Endpoints

```
GET  /v1/health                    Health check
POST /v1/process                   New message → Decision
POST /v1/result                    Execution result → Decision
POST /v1/cancel                    Cancel in-flight decision
GET  /v1/sessions/:id              Session metadata
DELETE /v1/sessions/:id            Terminate session
```

### gRPC Service

```protobuf
service H3Harness {
  rpc Health(HealthRequest) returns (HealthResponse);
  rpc Process(ProcessRequest) returns (Decision);
  rpc Result(ResultRequest) returns (Decision);
  rpc Cancel(CancelRequest) returns (CancelResponse);
  rpc StreamProcess(stream ProcessRequest) returns (stream Decision);  // bidirectional
}
```

---

## 5. Harness Discovery & Routing

### Configuration

```yaml
# ~/.hermes/profiles/<profile>/config.yaml

harnesses:
  consensus:
    endpoint: http://localhost:9191
    transport: rest
    timeout_ms: 30000
    max_retries: 3

  langchain-agent:
    endpoint: http://localhost:9192
    transport: rest
    timeout_ms: 60000

  crewai-dev:
    endpoint: localhost:9193
    transport: grpc

  native:
    endpoint: null  # Use Hermes built-in agent loop

default_harness: native

sessions:
  "telegram:6849342682":
    harness: consensus
  "telegram:-1003310984808:83399":
    harness: native
  "discord:engineering":
    harness: langchain-agent
```

### Session Resolution

1. Look up `sessions[platform:chat_id:thread_id]`
2. Fall back to `sessions[platform:chat_id]`
3. Fall back to `sessions[platform]`
4. Fall back to `default_harness`
5. If harness unreachable → `native` with warning logged

---

## 6. Error Modes & Recovery

| Failure | Behavior |
|---|---|
| Harness unreachable at startup | Log warning, route to native |
| Harness timeout mid-session | Retry 3x with exponential backoff (1s, 2s, 4s) |
| Harness returns malformed Decision | Log error, return error to user, end session |
| Harness hangs (no response) | Timeout at `timeout_ms`, terminate session |
| Harness returns `end` with error | Relay error to user, terminate |
| Harness health check fails | Remove from pool until next health check pass (30s interval) |

---

## 7. Security Model

- Harnesses run **locally** on the Hermes host (localhost binding)
- No network exposure by default
- Hermes authenticates the *user*, the harness trusts Hermes
- User identity passed in `context.identity` — harness decides authorization
- Harness CANNOT access Hermes credential vault directly
- Harness CANNOT bypass tool sandboxing
- All tool execution is logged and attributed to the harness session

---

## 8. Project Repository

| Property | Value |
|---|---|
| **Repo** | `github.com/coding-herms/h3` |
| **Language** | Python (shim lives in Hermes Core), polyglot SDKs |
| **Namespace** | `h3` (DuckBrain) |
| **Spec prefix** | `/spec/h3/` |
| **Foreman** | TBD — coding-hermes foreman |
| **GitReins** | Mandatory quality gate |
