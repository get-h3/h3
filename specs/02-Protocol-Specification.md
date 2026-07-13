# S02 — H3 Protocol Specification

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Protocol Versioning

| Header | Value |
|---|---|
| `H3-Protocol-Version` | `1.0` |
| `Content-Type` | `application/json` |
| `H3-Harness-Name` | `consensus`, `langchain`, etc. |

Version negotiation: Hermes sends its supported version. Harness responds with its version. If incompatible, Hermes falls back to native with error logged.

---

## 2. Endpoint: `GET /v1/health`

### Request
```
GET /v1/health
```

### Response (200)
```json
{
  "status": "ok",
  "version": "1.0.0",
  "transport": "rest",
  "protocol_version": "1.0",
  "uptime_seconds": 84320,
  "active_sessions": 7,
  "capabilities": ["tool_call", "llm_call", "text", "wait", "delegate", "end"]
}
```

### Response (degraded)
```json
{
  "status": "degraded",
  "version": "1.0.0",
  "transport": "rest",
  "protocol_version": "1.0",
  "degraded_reason": "Model backend unreachable",
  "capabilities": ["text", "end"]
}
```

### Response (down)
```json
{
  "status": "down",
  "version": "1.0.0",
  "error": "Database connection lost"
}
```

### Health Check Contract
- Hermes polls `/v1/health` every 30 seconds
- Harness MUST respond within 5 seconds
- Three consecutive failures → harness marked unreachable → sessions routed to native
- Harness returns to pool on first successful health check

---

## 3. Endpoint: `POST /v1/process`

Hermes calls this when a new user message arrives. The harness receives full context and must return a Decision.

### Request Body

```json
{
  "session_id": "s_abc123",
  "message": {
    "role": "user",
    "content": "Deploy the auth endpoint to staging",
    "attachments": [
      {
        "type": "image",
        "url": "file:///home/kara/.hermes/cache/img_abc.png",
        "mime_type": "image/png"
      }
    ],
    "timestamp": "2026-07-12T22:30:00Z"
  },
  "identity": {
    "platform": "telegram",
    "chat_id": "-1003310984808",
    "thread_id": "84802",
    "user_name": "Bane",
    "user_id": "6849342682"
  },
  "context": {
    "history": [
      {"role": "user", "content": "What's the auth endpoint status?"},
      {"role": "assistant", "content": "It's defined in /app/auth but not deployed yet."}
    ],
    "tools": [
      {
        "name": "terminal",
        "description": "Execute shell commands on a Linux environment",
        "parameters": {
          "command": {"type": "string", "description": "The command to execute"},
          "workdir": {"type": "string", "description": "Working directory"},
          "timeout": {"type": "integer", "description": "Max seconds to wait"}
        }
      },
      {
        "name": "web_search",
        "description": "Search the web",
        "parameters": {
          "query": {"type": "string", "description": "Search query"},
          "limit": {"type": "integer", "description": "Max results"}
        }
      }
    ],
    "models": [
      {
        "name": "deepseek-v4-pro",
        "provider": "deepseek-foreman",
        "cost_per_1k_input": 0.0011,
        "cost_per_1k_output": 0.0044,
        "context_window": 128000,
        "supports_vision": true,
        "supports_tool_calling": true
      },
      {
        "name": "glm-5.2",
        "provider": "zai-glm",
        "cost_per_1k_input": 0.0008,
        "cost_per_1k_output": 0.0032,
        "context_window": 131072,
        "supports_vision": true,
        "supports_tool_calling": true
      }
    ],
    "memory": "Last deployment used Docker Compose. Auth endpoint lives in /app/auth. Staging server is at 10.0.0.5:3000.",
    "skills": ["coding-hermes-foreman", "gitreins"],
    "config": {
      "max_iterations": 50,
      "timeout_seconds": 600,
      "project_dir": "/home/kara/helios",
      "max_tool_calls_per_turn": 1,
      "temperature": 0.7
    },
    "session_state": {
      "turn_count": 4,
      "total_tool_calls": 3,
      "total_llm_calls": 2,
      "cost_so_far": 0.0156,
      "started_at": "2026-07-12T22:25:00Z"
    }
  }
}
```

### Key Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `session_id` | string | ✅ | Unique session identifier. Stable across turns. |
| `message` | object | ✅ | The user's message |
| `message.role` | string | ✅ | Always `"user"` for /v1/process |
| `message.content` | string | ✅ | Message text |
| `message.attachments` | array | ❌ | Images, files, etc. |
| `identity` | object | ✅ | Who sent it, from where |
| `context.history` | array | ✅ | Last N messages (configurable, default 20) |
| `context.tools` | array | ✅ | Available Hermes tools with full JSON Schema params |
| `context.models` | array | ✅ | Available LLMs with pricing and capabilities |
| `context.memory` | string | ❌ | DuckBrain memory relevant to this session |
| `context.skills` | array | ❌ | Loaded skill names |
| `context.config` | object | ✅ | Session-level configuration |
| `context.session_state` | object | ✅ | Running counters for this session |

---

## 4. Decision Types

The harness MUST return exactly ONE decision per response.

### 4.1 `tool_call` — Execute a tool

```json
{
  "decision": "tool_call",
  "decision_id": "d_7b2c",
  "tool_call": {
    "name": "terminal",
    "params": {
      "command": "cd /app/auth && docker compose up -d",
      "workdir": "/home/kara/helios",
      "timeout": 120
    },
    "reasoning": "Deploying auth endpoint to staging via Docker Compose"
  }
}
```

| Field | Required | Description |
|---|---|---|
| `name` | ✅ | Tool name matching one from `context.tools` |
| `params` | ✅ | Parameters matching the tool's JSON Schema |
| `reasoning` | ❌ | Why this tool call — logged for auditing |

### 4.2 `llm_call` — Run an LLM prompt

```json
{
  "decision": "llm_call",
  "decision_id": "d_8c3d",
  "llm_call": {
    "model": "deepseek-v4-pro",
    "system_prompt": "You are an expert Go developer reviewing auth middleware.",
    "messages": [
      {"role": "user", "content": "Review this auth middleware for security issues:\n```go\nfunc AuthMiddleware..."}
    ],
    "temperature": 0.3,
    "max_tokens": 4000
  }
}
```

| Field | Required | Description |
|---|---|---|
| `model` | ✅ | Model name from `context.models` |
| `messages` | ✅ | Array of chat messages |
| `system_prompt` | ❌ | System prompt override |
| `temperature` | ❌ | 0.0–2.0, default 0.7 |
| `max_tokens` | ❌ | Max response tokens |

### 4.3 `text` — Send text to user

```json
{
  "decision": "text",
  "decision_id": "d_9e4f",
  "text": {
    "content": "Found the issue in auth.go:142 — missing JWT expiry check.",
    "finished": false
  }
}
```

| Field | Required | Description |
|---|---|---|
| `content` | ✅ | Markdown-formatted text to send |
| `finished` | ✅ | `true` = this is the final message, `false` = expect `/v1/result` with next decision |

### 4.4 `wait` — Pause for external signal

```json
{
  "decision": "wait",
  "decision_id": "d_f1a2",
  "wait": {
    "reason": "Waiting for CI pipeline to complete",
    "duration_seconds": 120,
    "poll_endpoint": "https://ci.example.com/jobs/1234/status"
  }
}
```

| Field | Required | Description |
|---|---|---|
| `reason` | ✅ | Human-readable reason for pause |
| `duration_seconds` | ❌ | Max wait time (Hermes caps at `context.config.timeout_seconds`) |
| `poll_endpoint` | ❌ | URL to poll — Hermes checks every 15s, resumes on success |

### 4.5 `delegate` — Spawn a sub-agent

```json
{
  "decision": "delegate",
  "decision_id": "d_0b3c",
  "delegate": {
    "agent": "code-reviewer",
    "task": "Review auth.go for security vulnerabilities",
    "context": "The auth endpoint handles JWT tokens. Check for expiry validation, algorithm confusion, key management issues.",
    "model": "glm-5.2",
    "provider": "zai-glm"
  }
}
```

| Field | Required | Description |
|---|---|---|
| `task` | ✅ | What the sub-agent should do |
| `context` | ❌ | Additional context for the sub-agent |
| `model` | ❌ | Model to use (defaults to cheapest available) |
| `provider` | ❌ | Provider bucket |

### 4.6 `end` — Terminate session

```json
{
  "decision": "end",
  "decision_id": "d_c4d5",
  "end": {
    "reason": "task_complete",
    "summary": "Deployed auth endpoint to staging. All tests passing. Endpoint live at https://staging.example.com/auth."
  }
}
```

| Reason | Description |
|---|---|
| `task_complete` | Task finished successfully |
| `user_requested` | User asked to stop |
| `error` | Unrecoverable error |
| `timeout` | Session timeout reached |
| `rate_limited` | Rate limit hit |
| `cancelled` | Hermes-side cancellation |

---

## 5. Endpoint: `POST /v1/result`

Hermes calls this after executing a decision. The harness receives the result and returns the next Decision.

### Request Body

```json
{
  "session_id": "s_abc123",
  "decision_id": "d_7b2c",
  "result": {
    "type": "tool_result",
    "tool_name": "terminal",
    "data": {
      "output": "Creating network auth_default...\nCreating auth_app_1... done\n✓ Auth endpoint deployed",
      "exit_code": 0
    },
    "duration_ms": 2843,
    "success": true
  }
}
```

### Result Types

| `result.type` | Description | `result.data` contents |
|---|---|---|
| `tool_result` | Tool execution completed | `output`, `exit_code`, tool-specific fields |
| `llm_response` | LLM responded | `content`, `model`, `tokens_used`, `cost` |
| `text_sent` | Text delivered to user | `message_id`, `platform` |
| `delegate_result` | Sub-agent finished | `agent`, `summary`, `output` |
| `wait_timeout` | Wait duration elapsed | `reason`, `poll_result` |
| `error` | Execution failed | `error_type`, `message`, `traceback` |

### Response: Next Decision

Same Decision format as §4. The loop continues until `end`.

---

## 6. Endpoint: `POST /v1/cancel`

Hermes calls this to cancel an in-flight operation. Used when the user sends a new message mid-processing or types `/stop`.

### Request
```json
{
  "session_id": "s_abc123",
  "reason": "user_interrupt"
}
```

### Response (200)
```json
{
  "cancelled": true,
  "cancelled_decision_id": "d_7b2c"
}
```

---

## 7. Endpoint: `GET /v1/sessions/:id`

```json
{
  "session_id": "s_abc123",
  "started_at": "2026-07-12T22:25:00Z",
  "last_active": "2026-07-12T22:30:15Z",
  "turn_count": 4,
  "status": "active",
  "current_decision": "d_7b2c",
  "current_decision_type": "tool_call"
}
```

---

## 8. Endpoint: `DELETE /v1/sessions/:id`

Forces session termination. Used for cleanup and `/new` command handling.

### Response (200)
```json
{
  "terminated": true,
  "session_id": "s_abc123"
}
```

---

## 9. Error Responses

All endpoints return standard error shape:

```json
{
  "error": {
    "code": "INVALID_DECISION",
    "message": "Decision type 'foo_bar' is not recognized",
    "details": {
      "valid_types": ["tool_call", "llm_call", "text", "wait", "delegate", "end"],
      "received": "foo_bar"
    }
  }
}
```

### Error Codes

| Code | HTTP | Meaning |
|---|---|---|
| `INVALID_REQUEST` | 400 | Malformed JSON or missing required fields |
| `INVALID_DECISION` | 400 | Decision type not recognized |
| `UNKNOWN_TOOL` | 400 | Tool name not in available tools |
| `UNKNOWN_MODEL` | 400 | Model not in available models |
| `SESSION_NOT_FOUND` | 404 | Session ID doesn't exist |
| `SESSION_EXPIRED` | 410 | Session timed out |
| `HARNESS_TIMEOUT` | 504 | Harness didn't respond in time |
| `INTERNAL_ERROR` | 500 | Harness-side crash |

---

## 10. Sequence Diagram

```
HERMES                          HARNESS
  │                                │
  │── GET /v1/health ────────────►│
  │◄──── 200 OK ──────────────────│
  │                                │
  │── POST /v1/process ──────────►│
  │   {session, msg, tools, ...}   │
  │                                │── think()
  │◄──── Decision ────────────────│
  │   {decision: "tool_call", ...} │
  │                                │
  │── execute tool ──────          │
  │                     │          │
  │── POST /v1/result ───────────►│
  │   {result: {...}}              │
  │                                │── think()
  │◄──── Decision ────────────────│
  │   {decision: "text", ...}      │
  │                                │
  │── deliver to user ──           │
  │                     │          │
  │── POST /v1/result ───────────►│
  │   {result: {type: "text_sent"}}│
  │                                │── think()
  │◄──── Decision ────────────────│
  │   {decision: "end", ...}       │
  │                                │
  ▼                                ▼
session ends                harness sleeps
```
