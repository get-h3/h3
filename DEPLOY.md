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
- Python 3.10+ (for the shim)
- Python, Go, or TypeScript runtime (for the harness — pick your SDK language)
- `h3-test` (bundled with the shim; `pip install hermes-h3-shim`, or from source: `git clone https://github.com/get-h3/shim && cd shim && pip install -e .`)

> **CLI note (WIRING-01):** the shipped standalone CLI is `hermes-h3` (subcommands:
> `install`, `list`, `pre-update-check`, `route`, `scaffold`, `test`, `uninstall`,
> `use`, `verify`). The `hermes h3` plugin space-form requires H3 wired into a live
> Hermes install (tracked as [WIRING-01](specs/06-Hermes-Core-Integration.md)) and is
> NOT yet available — this guide uses the working `hermes-h3` forms throughout.

## Step 1: Install the H3 Shim

```bash
# Install the shim from PyPI (`pip install hermes-h3-shim`), or from source as fallback
pip install hermes-h3-shim
# source fallback: git clone https://github.com/get-h3/shim && cd shim && pip install -e .

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
	"fmt"
	"net/http"

	"github.com/get-h3/sdk-go/harness"
	"github.com/get-h3/sdk-go/protocol"
)

// MyHarness implements all five methods of harness.Harness.
type MyHarness struct{}

func (h *MyHarness) OnProcess(req *protocol.ProcessRequest) (*protocol.Decision, error) {
	return &protocol.Decision{
		Decision:   protocol.DecisionText,
		DecisionID: protocol.GenerateUUID(),
		Text:       &protocol.TextResp{Content: "Hello from Go!", Finished: true},
	}, nil
}

func (h *MyHarness) OnResult(req *protocol.ResultRequest) (*protocol.Decision, error) {
	return &protocol.Decision{
		Decision:   protocol.DecisionEnd,
		DecisionID: protocol.GenerateUUID(),
		End: &protocol.End{
			Reason:  protocol.EndTaskComplete,
			Summary: "task complete",
		},
	}, nil
}

func (h *MyHarness) OnCancel(req *protocol.CancelRequest) error { return nil }

func (h *MyHarness) OnSessionTerminate(sessionID string) error { return nil }

func (h *MyHarness) Health() *protocol.HealthResponse {
	return &protocol.HealthResponse{
		Status:          protocol.HealthOK,
		Version:         "1.0.0",
		Transport:       "rest",
		ProtocolVersion: "1.0",
		Capabilities:    []protocol.DecisionType{protocol.DecisionText, protocol.DecisionEnd},
	}
}

func main() {
	fmt.Println("H3 harness listening on :9191")
	http.ListenAndServe(":9191", harness.NewHTTPServer(&MyHarness{}))
}
```

```bash
go run .
```

**Python** — `github.com/get-h3/sdk-python` (published on PyPI as `h3-harness-sdk`; source fallback: `pip install git+https://github.com/get-h3/sdk-python`)

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
pip install h3-harness-sdk          # source fallback: pip install git+https://github.com/get-h3/sdk-python
uvicorn main:app --port 9191
```

**TypeScript** — `github.com/get-h3/sdk-typescript` (not yet on npm — install from source; imports use the package name `@get-h3/h3-harness-sdk`)

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

The test battery is the gate. 48 tests across 6 categories. Exit code 0 = compliant.

```bash
h3-test --endpoint http://localhost:9191
```

All 48 must pass. No exceptions.

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
RUN pip install h3-harness-sdk
# source fallback: RUN pip install git+https://github.com/get-h3/sdk-python
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

- [ ] `h3-test --endpoint <url>` passes 48/48
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

# 2. Upgrade shim (PyPI primary)
pip install --upgrade hermes-h3-shim
# source fallback (commit not in a release yet): cd shim && git pull && pip install -e .

# 3. Upgrade SDK in harness
# Go:  go get github.com/get-h3/sdk-go@latest
# Python: pip install --upgrade h3-harness-sdk  (source fallback: pip install --upgrade git+https://github.com/get-h3/sdk-python)
# TS:   npm install github:get-h3/sdk-typescript@latest

# 4. Rerun test battery
h3-test --endpoint http://localhost:9191

# 5. Verify
hermes-h3 verify --harness my-harness
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `hermes-h3 install my-harness` fails | Shim not installed | `pip install hermes-h3-shim` in the active venv (or `pip install -e .` from the shim checkout — Step 1) |
| Plugin loads but no harness config | Config not created | `hermes-h3 scaffold` to regenerate config |
| "Protocol version mismatch" | SDK too old/new | Install matching SDK version (check `versions.yaml`) |
| Health check timeout | Harness not running | `hermes-h3 scaffold --lang go` then `go run .` |
| `h3-test` returns non-zero | Harness doesn't implement full protocol | Check failed test region for missing handlers |
| Session not routing through harness | Session not in routing table | Add the session to `sessions` in `~/.hermes/h3/config.yaml` |
| 422 on /v1/process | Pydantic models too strict | Update to latest sdk-python (lenient defaults) or pass all optional fields |
| Hermes falls back to native loop | Harness unreachable | Check harness is running: `curl http://localhost:9191/v1/health` |

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

## Board Header Pre-Commit Hook (QA-H3-22 / QA-H3-22-R2)

Board-writing ticks must run `make board-close` before committing board files
(see the Makefile's DF-H3-25 section). The pre-commit hook
`scripts/pre-commit-board-close.sh` makes this structural: when
`.coding-hermes/board/board.jsonl` or `events.jsonl` is staged, it re-pins the
header's `last_commit` to the current HEAD and re-stages it, so a stale header
cannot be committed.

Install (after `boardctl install` has set up the shared pre-commit hook):

    bash scripts/install-board-close-hook.sh

### The install is a one-shot; the close-out re-asserts it (QA-H3-27)

The block lives **inside a pre-commit file this project does not own**. When the
resolved hooks dir is shared (a host-global `core.hooksPath`) or re-installed by
another tool, that file is rewritten from *its* template and the block is gone —
no warning, no error, nothing this repo can hook. That is the 9th recurrence of
this class: on 2026-10-23 a fresh public clone at `22bc708` failed `make verify`
with `last_commit` six commits behind, because the gitreins hook install had
re-created the shared hook without the block and the two board commits before it
(`1b6f49f`, `4bd9265`) ran with no header write-back at all.

So the guarantee is not "installed once". `make board-close` — the close-out step
every board-writing tick runs — first calls:

    bash scripts/ensure-board-close-hook.sh          # reassert if missing
    bash scripts/ensure-board-close-hook.sh --check  # probe only, never writes

It resolves the hooks dir the same way the installer does, and:

* **already there** → no-op, nothing written (`--check` prints `PASS`, exit 0);
* **gone** (the reinstall case) → reasserts it through the tracked installer,
  which backs the file up, inserts the block before the final `exit`, and
  preserves every other line of the foreign hook; then re-verifies the file;
* **cannot be repaired** → exits non-zero and names the remedy, so the board
  close-out **stops before a stale header is written** instead of leaving the
  discovery to the next fresh-clone `make verify`.

`H3_SKIP_HOOK_ENSURE=1 make board-close` skips the reassert for a host where the
shared hooks dir must not be touched; it prints a warning that the close-out is
then unguarded. Both halves are proven by the reinstall arm of the battery below.

### Where the hook goes (and why that is the fix)

**git only runs hooks from the directory it resolves, and `core.hooksPath`
replaces `.git/hooks` entirely.** The installer therefore resolves the hooks
directory with `git rev-parse --git-path hooks` and installs into THAT:

| host state | hooks dir git uses | where the block lands |
|---|---|---|
| `core.hooksPath` unset | `<repo>/.git/hooks` | `<repo>/.git/hooks/pre-commit` |
| `core.hooksPath` absolute | that path | that path |
| `core.hooksPath` relative | `<repo>/<value>` | `<repo>/<value>/pre-commit` |
| linked worktree | the COMMON git dir | `<main-repo>/.git/hooks/pre-commit` |

Until QA-H3-22-R2 the installer wrote `$repo/.git/hooks/pre-commit`
unconditionally. On a host whose global gitconfig sets `core.hooksPath`, that
file is never read: the block installed, printed OK, and did nothing — the
generator defect behind eight recurrences of the stale-header class (DF-H3-25,
DF-H3-32, QA-H3-18, QA-H3-20, QA-H3-21, QA-H3-2026-09-26-001, QA-H3-22,
QA-H3-22-R2).

**Host-global step, stated explicitly:** when `core.hooksPath` is set
host-globally (for example `core.hooksPath=~/.hermes/hooks`, shared by every
repo on the machine), running the installer puts the managed block in that
SHARED directory, not in the clone. That is intended and safe: the block looks
for `scripts/pre-commit-board-close.sh` at the committing repo's toplevel and is
completely silent — no output, no non-zero exit — in any repo that does not
carry the script. Installing it once covers every h3 clone on the host.
`git config --get core.hooksPath` reports which shape you are in, and the
installer prints the resolved directory it used plus the `core.hooksPath` value.

The block is INSERTED BEFORE the hook's final `exit` line (appending after it
would be unreachable dead code), every existing block is preserved, an existing
hook in a shared directory is backed up first, and the install is idempotent. If
a stale copy of the block is sitting in `.git/hooks/pre-commit` while git is
looking elsewhere, the installer warns — that dead copy is the recurrence's
fingerprint.

It skips cleanly when no board files are staged or the sync script is missing;
it fails the commit only if `scripts/sync-board-header.sh` itself fails. The
hook is not tracked (`<hooks dir>/pre-commit` never is) — each clone (or its
host's shared hooks dir) installs it. Verification:

    bash scripts/install-board-close-hook-selftest.sh   # or: make verify-board-close-hook-selftest
    bash scripts/pre-commit-board-close-selftest.sh

The installer battery exercises every resolution shape above and makes a real
board-only commit twice: RED with no hook in the resolved dir (the commit
succeeds and the header is left stale — the defect) and GREEN with the block
installed (the same commit leaves `last_commit` equal to the commit's parent
sha). A third pair reproduces the **reinstall** (arm 11): the resolved hook is
overwritten with a gitreins-style hook, the block disappears, a board commit is
proven to leave the header stale (RED), then `ensure-board-close-hook.sh`
reasserts the block without clobbering the foreign hook and the next board
commit re-pins the header (GREEN). It isolates `GIT_CONFIG_GLOBAL`, so it gives
the same verdict on a host with a global `core.hooksPath` and on one without.


