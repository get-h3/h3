# S04 — SDK Libraries

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. SDK Architecture

Each SDK provides:

| Layer | Purpose |
|---|---|
| **Protocol types** | Go structs / Python dataclasses / TS interfaces for ProcessRequest, Decision, ResultRequest |
| **HTTP server** | Quick-start HTTP handler that marshals/unmarshals the protocol |
| **Base Harness class** | Abstract class/interface with `on_process()` and `on_result()` methods |
| **Validation** | Request validation, Decision validation before sending to Hermes |
| **Test helpers** | Mock Hermes client for unit testing harness logic |

### Cross-Language Consistency

All SDKs share the same JSON wire format. The SDK's job is idiomatic language binding, NOT format translation.

---

## 2. Go SDK (`github.com/coding-herms/h3-sdk-go`)

### 2.1 Package Structure

```
h3-sdk-go/
├── protocol/
│   ├── types.go         # ProcessRequest, Decision, ResultRequest, all JSON tags
│   ├── validate.go      # Request/Decision validation
│   └── types_test.go
├── harness/
│   ├── harness.go       # Harness interface + HTTP handler
│   ├── middleware.go     # Logging, recovery, timeout
│   └── harness_test.go
├── testbed/
│   ├── mock_hermes.go   # Mock Hermes for unit testing harness logic
│   └── assertions.go    # Decision matchers
├── examples/
│   ├── minimal/          # Bare minimum harness
│   ├── echo/             # Echo harness — returns user input
│   └── consensus/        # Consensus integration reference
├── go.mod
└── README.md
```

### 2.2 Core Types

```go
package protocol

type ProcessRequest struct {
    SessionID string       `json:"session_id"`
    Message   Message      `json:"message"`
    Identity  Identity     `json:"identity"`
    Context   Context      `json:"context"`
}

type Decision struct {
    Decision   DecisionType `json:"decision"`
    DecisionID string       `json:"decision_id"`
    ToolCall   *ToolCall    `json:"tool_call,omitempty"`
    LLMCall    *LLMCall     `json:"llm_call,omitempty"`
    Text       *TextResp    `json:"text,omitempty"`
    Wait       *Wait        `json:"wait,omitempty"`
    Delegate   *Delegate    `json:"delegate,omitempty"`
    End        *End         `json:"end,omitempty"`
}

type DecisionType string

const (
    DecisionToolCall DecisionType = "tool_call"
    DecisionLLMCall  DecisionType = "llm_call"
    DecisionText     DecisionType = "text"
    DecisionWait     DecisionType = "wait"
    DecisionDelegate DecisionType = "delegate"
    DecisionEnd      DecisionType = "end"
)
```

### 2.3 Harness Interface

```go
type Harness interface {
    // OnProcess is called when a new user message arrives.
    // Return the first Decision in the agent loop.
    OnProcess(req *protocol.ProcessRequest) (*protocol.Decision, error)

    // OnResult is called after Hermes executes a Decision.
    // Return the next Decision. Return DecisionEnd to finish.
    OnResult(req *protocol.ResultRequest) (*protocol.Decision, error)

    // OnCancel is called when the user interrupts.
    OnCancel(req *protocol.CancelRequest) error

    // OnSessionTerminate is called on DELETE /v1/sessions/:id.
    OnSessionTerminate(sessionID string) error

    // Health returns harness health status.
    Health() *protocol.HealthResponse
}
```

### 2.4 HTTP Handler

```go
// ServeHTTP implements http.Handler. Register it directly.
func NewHTTPServer(h Harness) http.Handler {
    mux := http.NewServeMux()
    mux.HandleFunc("/v1/health", healthHandler(h))
    mux.HandleFunc("/v1/process", processHandler(h))
    mux.HandleFunc("/v1/result", resultHandler(h))
    mux.HandleFunc("/v1/cancel", cancelHandler(h))
    mux.HandleFunc("/v1/sessions/", sessionHandler(h))
    return withMiddleware(mux) // logging, recovery, timeout
}
```

### 2.5 Minimal Harness Example

```go
type EchoHarness struct{}

func (e *EchoHarness) OnProcess(req *protocol.ProcessRequest) (*protocol.Decision, error) {
    return &protocol.Decision{
        Decision:   protocol.DecisionText,
        DecisionID: uuid.New().String(),
        Text: &protocol.TextResp{
            Content:  fmt.Sprintf("You said: %s", req.Message.Content),
            Finished: true,
        },
    }, nil
}

func (e *EchoHarness) OnResult(req *protocol.ResultRequest) (*protocol.Decision, error) {
    // After sending text, we're done
    return &protocol.Decision{
        Decision:   protocol.DecisionEnd,
        DecisionID: uuid.New().String(),
        End:        &protocol.End{Reason: "task_complete"},
    }, nil
}

func (e *EchoHarness) Health() *protocol.HealthResponse {
    return &protocol.HealthResponse{
        Status:          "ok",
        Version:         "1.0.0",
        Transport:       "rest",
        ProtocolVersion: "1.0",
        Capabilities:    []string{"text", "end"},
    }
}
```

---

## 3. Python SDK (`h3-harness-sdk`)

### 3.1 Package Structure

```
h3_harness/
├── __init__.py
├── protocol.py        # Pydantic models
├── harness.py          # BaseHarness ABC + FastAPI router
├── middleware.py       # Logging, timeout, error handling
├── testbed.py          # MockHermes for pytest
├── examples/
│   ├── minimal.py
│   ├── echo.py
│   └── langchain_agent.py
└── pyproject.toml
```

### 3.2 Core Types

```python
from pydantic import BaseModel
from enum import Enum
from typing import Optional, List, Any
from uuid import uuid4

class DecisionType(str, Enum):
    TOOL_CALL = "tool_call"
    LLM_CALL  = "llm_call"
    TEXT      = "text"
    WAIT      = "wait"
    DELEGATE  = "delegate"
    END       = "end"

class ToolCall(BaseModel):
    name: str
    params: dict[str, Any]
    reasoning: Optional[str] = None

class LLMCall(BaseModel):
    model: str
    messages: list[dict]
    system_prompt: Optional[str] = None
    temperature: Optional[float] = 0.7
    max_tokens: Optional[int] = None

class TextResponse(BaseModel):
    content: str
    finished: bool

class Wait(BaseModel):
    reason: str
    duration_seconds: Optional[int] = None
    poll_endpoint: Optional[str] = None

class Delegate(BaseModel):
    task: str
    context: Optional[str] = None
    model: Optional[str] = None
    provider: Optional[str] = None

class End(BaseModel):
    reason: str  # task_complete | user_requested | error | timeout
    summary: Optional[str] = None

class Decision(BaseModel):
    decision: DecisionType
    decision_id: str = None
    tool_call: Optional[ToolCall] = None
    llm_call: Optional[LLMCall] = None
    text: Optional[TextResponse] = None
    wait: Optional[Wait] = None
    delegate: Optional[Delegate] = None
    end: Optional[End] = None

    def __init__(self, **data):
        if 'decision_id' not in data or data['decision_id'] is None:
            data['decision_id'] = str(uuid4())
        super().__init__(**data)
```

### 3.3 Base Harness

```python
from abc import ABC, abstractmethod

class BaseHarness(ABC):
    @abstractmethod
    async def on_process(self, req: ProcessRequest) -> Decision:
        ...

    @abstractmethod
    async def on_result(self, req: ResultRequest) -> Decision:
        ...

    async def on_cancel(self, req: CancelRequest) -> bool:
        return True  # override for custom cancel logic

    async def on_session_terminate(self, session_id: str) -> None:
        pass

    def health(self) -> HealthResponse:
        return HealthResponse(
            status="ok",
            version="1.0.0",
            transport="rest",
            protocol_version="1.0",
            capabilities=["tool_call", "llm_call", "text", "wait", "delegate", "end"],
        )
```

### 3.4 FastAPI Router (One-Line Integration)

```python
from h3_harness import BaseHarness, create_router

class MyHarness(BaseHarness):
    async def on_process(self, req): ...
    async def on_result(self, req): ...

app = FastAPI()
app.include_router(create_router(MyHarness()))
```

---

## 4. TypeScript SDK (`@coding-herms/h3-harness-sdk`)

### 4.1 Package Structure

```
src/
├── protocol.ts        # TypeScript types + Zod schemas
├── harness.ts          # Harness interface + Hono router
├── middleware.ts       # Error handling, logging, timeout
├── testbed.ts          # MockHermes for vitest/jest
├── examples/
│   ├── minimal.ts
│   ├── echo.ts
│   └── langgraph-agent.ts
├── index.ts
└── package.json
```

### 4.2 Core Types

```typescript
import { z } from 'zod';

export const DecisionType = z.enum([
  'tool_call', 'llm_call', 'text', 'wait', 'delegate', 'end'
]);
export type DecisionType = z.infer<typeof DecisionType>;

export const DecisionSchema = z.object({
  decision: DecisionType,
  decision_id: z.string().uuid(),
  tool_call: z.object({
    name: z.string(),
    params: z.record(z.unknown()),
    reasoning: z.string().optional(),
  }).optional(),
  llm_call: z.object({
    model: z.string(),
    messages: z.array(z.object({
      role: z.enum(['user', 'assistant', 'system']),
      content: z.string(),
    })),
    system_prompt: z.string().optional(),
    temperature: z.number().min(0).max(2).optional(),
    max_tokens: z.number().int().positive().optional(),
  }).optional(),
  text: z.object({
    content: z.string(),
    finished: z.boolean(),
  }).optional(),
  wait: z.object({
    reason: z.string(),
    duration_seconds: z.number().int().positive().optional(),
    poll_endpoint: z.string().url().optional(),
  }).optional(),
  delegate: z.object({
    task: z.string(),
    context: z.string().optional(),
    model: z.string().optional(),
    provider: z.string().optional(),
  }).optional(),
  end: z.object({
    reason: z.enum(['task_complete', 'user_requested', 'error', 'timeout', 'rate_limited', 'cancelled']),
    summary: z.string().optional(),
  }).optional(),
});

export type Decision = z.infer<typeof DecisionSchema>;
```

### 4.3 Harness Interface

```typescript
export interface Harness {
  onProcess(req: ProcessRequest): Promise<Decision>;
  onResult(req: ResultRequest): Promise<Decision>;
  onCancel?(req: CancelRequest): Promise<boolean>;
  onSessionTerminate?(sessionId: string): Promise<void>;
  health(): HealthResponse;
}
```

### 4.4 Hono Router

```typescript
import { Hono } from 'hono';

export function createH3Router(harness: Harness): Hono {
  const app = new Hono();

  app.get('/v1/health', (c) => c.json(harness.health()));
  app.post('/v1/process', async (c) => {
    const req = ProcessRequestSchema.parse(await c.req.json());
    const decision = await harness.onProcess(req);
    return c.json(decision);
  });
  app.post('/v1/result', async (c) => {
    const req = ResultRequestSchema.parse(await c.req.json());
    const decision = await harness.onResult(req);
    return c.json(decision);
  });

  return app;
}
```

---

## 5. SDK Code Generation

### 5.1 OpenAPI → SDK

The H3 protocol has an OpenAPI 3.1 spec (`h3-protocol.yaml`). SDKs can be regenerated from it:

```bash
# Go
openapi-generator generate -i h3-protocol.yaml -g go -o sdks/go/

# Python
openapi-generator generate -i h3-protocol.yaml -g python -o sdks/python/

# TypeScript
openapi-generator generate -i h3-protocol.yaml -g typescript-fetch -o sdks/typescript/
```

Manual SDKs (described above) provide better DX. OpenAPI generation serves as a fallback for languages without first-party SDKs.

### 5.2 First-Party SDK Priority

| Tier | Languages | Rationale |
|---|---|---|
| **Tier 1** | Go, Python, TypeScript | Covers all major harness ecosystems |
| **Tier 2** | Rust, Java, C# | User demand-driven |
| **Tier 3** | Everything else | OpenAPI-generated fallback |

---

## 6. SDK Testing

Each SDK ships with:

```
testbed/
├── mock_hermes.go      # Mock Hermes that sends ProcessRequests and validates Decisions
├── conformance_test.go  # Runs the full test battery against the harness (see S05)
└── fixtures/            # Sample requests/responses for unit tests
```

### Mock Hermes (Go)

```go
type MockHermes struct {
    harness Harness
}

func (m *MockHermes) SendMessage(content string) (*protocol.Decision, error) {
    req := &protocol.ProcessRequest{
        SessionID: "test-session",
        Message: protocol.Message{Role: "user", Content: content},
        Context: protocol.Context{
            Tools: defaultTools(),
            Models: defaultModels(),
            Config: protocol.SessionConfig{MaxIterations: 10},
        },
    }
    return m.harness.OnProcess(req)
}

func (m *MockHermes) SendResult(result *protocol.ResultRequest) (*protocol.Decision, error) {
    return m.harness.OnResult(result)
}
```

---

## 7. SDK Release Pipeline

```
Git tag push (v1.0.0)
  │
  ├─► Go: Tag triggers Go module proxy caching
  ├─► Python: CI publishes to PyPI via trusted publisher
  ├─► TypeScript: CI publishes to npm via OIDC token
  └─► OpenAPI spec: Published to docs.h3.sh
```
