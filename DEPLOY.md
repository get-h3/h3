# H3 Deployment Guide

Deploy H3 (Hermes Harness Hooks) — the brain-swap protocol that lets external agent systems become the thinking brain of Hermes.

## Architecture

```
Hermes Core (the body)
    │
    │ H3 protocol (REST/gRPC over HTTP)
    │
    ▼
Harness (the brain)
    — Your agent: OpenCode, Consensus, CrewAI, LangChain, custom logic
    — Receives ProcessRequest, returns Decision
    — Hermes executes the decision, sends Result, loop continues
```

## Prerequisites

- Hermes Agent (any version compatible per `protocol/versions.yaml`)
- Python 3.11+ (for the shim)
- Python, Go, or TypeScript runtime (for the harness — pick your SDK language)
- `h3-test` (bundled with the shim; install from source: `git clone https://github.com/get-h3/shim && cd shim && pip install -e .`)

> **CLI note (WIRING-01):** the shipped standalone CLI is `hermes-h3` (subcommands:
> `install`, `list`, `pre-update-check`, `route`, `scaffold`, `test`, `uninstall`,
> `use`, `verify`). The `hermes h3` plugin space-form requires H3 wired into a live
> Hermes install (tracked as [WIRING-01](specs/06-Hermes-Core-Integration.md)) and is
> NOT yet available — this guide uses the working `hermes-h3` forms throughout.

## Step 1: Install the H3 Shim

```bash
# Install the shim from source (PyPI publishing pending — tracked as P3-10)
git clone https://github.com/get-h3/shim && cd shim && pip install -e .

# Verify the CLI installed
hermes-h3 --help
```

This installs the `hermes-h3` CLI and the `h3-test` battery. The Hermes-side plugin
registration (the `hermes h3` plugin form) is WIRING-01-gated and not yet shipped.

## Step 2: Build a Harness

Choose your language. The scaffold command generates a working harness project that passes `h3-test` immediately.

### Option A: Scaffold (recommended for new harnesses)

```bash
# Generate a Go harness
hermes-h3 scaffold --lang go --output-dir ./my-harnesses
cd ./my-harnesses/h3-harness-go

# Generate a Python harness
hermes-h3 scaffold --lang py --output-dir ./my-harnesses
cd ./my-harnesses/h3-harness-py

# Generate a TypeScript harness
hermes-h3 scaffold --lang ts --output-dir ./my-harnesses
cd ./my-harnesses/h3-harness-ts
```

### Option B: Manual (use SDK directly)

**Go** — `github.com/get-h3/sdk-go`

```go
package main

import (
    "net/http"
    "github.com/get-h3/sdk-go/harness"
    "github.com/get-h3/sdk-go/protocol"
)

type MyHarness struct{}

func (h *MyHarness) OnProcess(req *protocol.ProcessRequest) (*protocol.Decision, error) {
    return &protocol.Decision{
        Decision: protocol.DecisionText,
        Text: &protocol.TextResp{Content: "Hello from Go!", Finished: true},
    }, nil
}

func (h *MyHarness) OnResult(req *protocol.ResultRequest) (*protocol.Decision, error) {
    return &protocol.Decision{
        Decision: protocol.DecisionEnd,
        End:      &protocol.EndResult{Reason: "task_complete"},
    }, nil
}

func main() {
    http.ListenAndServe(":9191", harness.NewHTTPServer(&MyHarness{}))
}
```

```bash
go run .
```

**Python** — `github.com/get-h3/sdk-python` (PyPI publishing pending — install from source)

```python
from h3_harness import (
    BaseHarness, Decision, DecisionType, End, TextResponse, create_router,
)
from fastapi import FastAPI

class MyHarness(BaseHarness):
    async def on_process(self, req):
        return Decision(
            decision=DecisionType.TEXT,
            text=TextResponse(content="Hello from Python!", finished=True),
        )
    async def on_result(self, req):
        return Decision(decision=DecisionType.END, end=End(reason="task_complete"))

app = FastAPI()
app.include_router(create_router(MyHarness()))
```

```bash
pip install git+https://github.com/get-h3/sdk-python
uvicorn main:app --port 9191
```

**TypeScript** — `github.com/get-h3/sdk-typescript` (npm publishing pending — install from source; imports use the package name `@get-h3/h3-harness-sdk`)

```typescript
import { Hono } from 'hono';
import { Harness, Decision, DecisionType, createH3Router } from '@get-h3/h3-harness-sdk';

class MyHarness implements Harness {
  async onProcess(req) {
    return { decision: DecisionType.TEXT, decision_id: crypto.randomUUID(),
             text: { content: 'Hello from TypeScript!', finished: true } };
  }
  async onResult(req) {
    return { decision: DecisionType.END, decision_id: crypto.randomUUID(),
             end: { reason: 'task_complete' } };
  }
  health() {
    return { status: 'ok', version: '1.0.0', transport: 'rest',
             protocol_version: '1.0', capabilities: ['text', 'end'] };
  }
}

const app = new Hono();
app.route('/', createH3Router(new MyHarness()));
export default app;
```

```bash
npm install github:get-h3/sdk-typescript
npx tsx main.ts  # listens on :9191
```

## Step 3: Test the Harness

The test battery is the gate. 44 tests across 6 categories. Exit code 0 = compliant.

```bash
h3-test --endpoint http://localhost:9191
```

All 44 must pass. No exceptions.

## Step 4: Register the Harness

```bash
# Register with Hermes
hermes-h3 install my-harness --endpoint http://localhost:9191

# Set as default
hermes-h3 install my-harness --endpoint http://localhost:9191 --set-default

# List registered harnesses
hermes-h3 list

# Health check
hermes-h3 verify --harness my-harness
```

Config lives at `~/.hermes/h3/config.yaml`:

```yaml
harnesses:
  my-harness:
    endpoint: http://localhost:9191
    transport: rest
    timeout_ms: 30000
default_harness: my-harness

sessions:
  platform:chat_id:thread_id: my-harness
```

Only sessions listed under `sessions` route through H3. All others use native Hermes loop.

## Step 5: Docker Deployment

For production isolation or running on separate hosts.

### Python harness (example)

```dockerfile
FROM python:3.11-slim
RUN pip install git+https://github.com/get-h3/sdk-python
COPY harness.py .
EXPOSE 9191
CMD ["python", "harness.py"]
```

```bash
docker build -t h3-harness .
docker run -d --name h3-harness -p 9191:9191 h3-harness
```

### Go harness (example)

```dockerfile
FROM golang:1.24 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o harness .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/harness /harness
EXPOSE 9191
ENTRYPOINT ["/harness"]
```

### Then register

```bash
hermes-h3 install my-harness --endpoint http://h3-harness:9191
```

## Step 6: Route Sessions Through H3

To swap a session's agent loop to your harness:

```bash
# Route a specific session — edit ~/.hermes/h3/config.yaml:
#   sessions:
#     telegram:-1001234567890:17585: my-harness
#     matrix:!roomid:server: my-harness

# Show routing table
hermes-h3 route
```

Only the listed sessions use H3. All others continue with the native Hermes loop. This is gradual cutover — never big-bang swap every session.

## Step 7: Monitor

```bash
# Health check (run in cron or monitoring)
hermes-h3 verify --harness my-harness

# Test battery (periodic compliance)
h3-test --endpoint http://localhost:9191

# Harness logs — every request should log:
# METHOD /v1/process STATUS DURATION_MS
# METHOD /v1/result  STATUS DURATION_MS
```

Expected log format:

```
POST /v1/process 200 12ms
POST /v1/result  200 8ms
POST /v1/process 200 15ms
POST /v1/result  200 9ms
GET  /health      200 1ms
```

## Production Checklist

- [ ] `h3-test --endpoint <url>` passes 44/44
- [ ] Harness logs every request with METHOD, path, status, duration
- [ ] Health endpoint returns `{"status": "ok", "version": "...", "capabilities": [...]}`
- [ ] Harness runs behind a process manager (systemd, Docker restart policy, k8s)
- [ ] Only specific sessions routed through H3 (not all sessions)
- [ ] Fallback tested: if harness is unreachable, sessions fall back to native Hermes loop
- [ ] Harness API keys configured (TLS if over public network)
- [ ] Harness deployed on same network as Hermes (< 5ms latency)
- [ ] `hermes-h3 verify` responds within 10s
- [ ] `versions.yaml` checked — Hermes and H3 versions are compatible

## Upgrade Flow

```bash
# 1. Check compatibility
hermes-h3 pre-update-check 0.19.0

# 2. Upgrade shim (source install)
cd shim && git pull && pip install -e .

# 3. Upgrade SDK in harness
# Go:  go get github.com/get-h3/sdk-go@latest
# Python: pip install --upgrade git+https://github.com/get-h3/sdk-python
# TS:   npm install github:get-h3/sdk-typescript@latest

# 4. Rerun test battery
h3-test --endpoint http://localhost:9191

# 5. Verify
hermes-h3 verify --harness my-harness
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `hermes-h3 install my-harness` fails | Shim not installed | `pip install -e .` from the shim checkout (Step 1) |
| Plugin loads but no harness config | Config not created | `hermes-h3 scaffold` to regenerate config |
| "Protocol version mismatch" | SDK too old/new | Install matching SDK version (check `versions.yaml`) |
| Health check timeout | Harness not running | `hermes-h3 scaffold --lang go` then `go run .` |
| `h3-test` returns non-zero | Harness doesn't implement full protocol | Check failed test region for missing handlers |
| Session not routing through harness | Session not in routing table | Add the session to `sessions` in `~/.hermes/h3/config.yaml` |
| 422 on /v1/process | Pydantic models too strict | Update to latest sdk-python (lenient defaults) or pass all optional fields |
| Hermes falls back to native loop | Harness unreachable | Check harness is running: `curl http://localhost:9191/health` |

## Reference Repos

| Repo | Purpose |
|---|---|
| `get-h3/h3` | Spec hub, cross-repo task board, this guide |
| `get-h3/protocol` | OpenAPI 3.1 spec + JSON Schema |
| `get-h3/shim` | Hermes plugin (`hermes-h3` CLI, test battery) |
| `get-h3/sdk-go` | Go SDK for harness developers |
| `get-h3/sdk-python` | Python SDK for harness developers |
| `get-h3/sdk-typescript` | TypeScript SDK for harness developers |

## Version Compatibility

See `protocol/versions.yaml` for the full Hermes↔H3 compatibility matrix.

H3 follows the protocol. The shim translates. The harness decides. Hermes executes. That's the loop.
