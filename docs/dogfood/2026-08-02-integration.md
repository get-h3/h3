# H3 Dogfood Integration Report — 2026-08-02

Real-user integration run against the get-h3 fleet (umbrella repo: `h3`).
Everything below was executed live; nothing is hypothetical. Scratch work in
`/tmp/dogfood-h3` (throwaway; the working harnesses from this report are
reproducible in ~30 minutes with the commands below).

## 1. What was tested (the promise)

README Quick Start promises two paths to an H3-compliant harness:

1. **Scaffold path:** `pip install hermes-h3-shim` → `hermes h3 scaffold
   --lang go` → `cd h3-harness && go run .` → `h3-test --endpoint
   http://localhost:9191` → 43/43.
2. **Custom-harness path:** "or your own custom harness" — implement the
   protocol from the spec and pass the same battery.

## 2. Environment

- Host: Linux, Go 1.26.5, Python 3.13 (uv 0.11.17), network OK.
- The fleet repos were already checked out at `/home/kara/get-h3/`
  (h3, protocol, shim, sdk-go, sdk-python, sdk-typescript).

## 3. What happened, step by step

### 3.1 Install the shim — ❌ FAILED (P0, DOGFOOD-01)

```bash
pip install hermes-h3-shim
# → ERROR: No matching distribution found for hermes-h3-shim
```

Also checked `h3-harness-sdk` (sdk-python docs), `h3-shim`, `h3-sdk-python`
on pypi.org — **all HTTP 404**. Nothing from this fleet is published.

**Workaround (used for the rest of the run):** install from source:

```bash
uv venv /tmp/dogfood-h3/.venv
uv pip install --python /tmp/dogfood-h3/.venv/bin/python -e /home/kara/get-h3/shim
```

This yields two working CLIs: `h3-test` (battery) and `hermes-h3`
(management). Note: the README calls the second one `hermes h3` — the
standalone binary is `hermes-h3`; `hermes h3` only exists inside a wired-up
live Hermes (WIRING-01, still open).

### 3.2 Scaffold a Go harness — ⚠️ WORKS, but doesn't build (P0, DOGFOOD-02)

```bash
hermes-h3 scaffold --lang go --output-dir /tmp/dogfood-h3
# → Generated go harness at: /tmp/dogfood-h3/h3-harness-go
cd h3-harness-go && go mod tidy
# → go: github.com/get-h3/sdk-go@v0.0.0: unknown revision v0.0.0
```

The template's `go.mod` requires `github.com/get-h3/sdk-go v0.0.0` (no such
revision — **sdk-go has zero published tags/versions**) and ships with the
fix commented out:

```go
// replace github.com/get-h3/sdk-go => ../../sdk-go
```

**Workaround:** uncomment the replace, pointing at the local checkout:

```bash
sed -i 's|// replace github.com/get-h3/sdk-go => ../../sdk-go|replace github.com/get-h3/sdk-go => /home/kara/get-h3/sdk-go|' go.mod
go mod tidy && go build -o h3harness . && ./h3harness &
```

### 3.3 Run the battery against the scaffolded harness — ✅ 43/43

```bash
h3-test --endpoint http://localhost:9191
# Health & Protocol 7/7 · Process 8/8 · Decision Types 6/6
# Result Handling 7/7 · Error & Edge 10/10 · Stress 5/5
# TOTAL 43/43 PASSED · Duration 0.22s · p50 0.85ms
```

### 3.4 Build a CUSTOM harness from the spec alone — ✅ 41/43 → 43/43 (P1, DOGFOOD-03)

The README's core claim is "your own custom harness". Test: implement a
harness using **only** `specs/02-Protocol-Specification.md` — stdlib Python
(http.server), zero SDK code, zero generated types. The spec is genuinely
complete on endpoints (`GET /v1/health`, `POST /v1/process`, `POST
/v1/result`, `POST /v1/cancel`, `GET|DELETE /v1/sessions/:id`), decision
envelopes (`tool_call`, `llm_call`, `text`, `wait`, `delegate`, `end`), and
error shapes (§9).

**Result: 41/43 on the first run** — every health, decision-type, result,
error, and stress test passed from the docs alone. Two Process-Basic-Flow
tests failed, and the spec did not contain the information needed to pass
them:

| Failing test | What the battery demands | Where it's documented |
|---|---|---|
| `process_text_finished_true` | A text decision must have `finished=true` unless the user content contains the streaming marker `"do not finish"` | Only in the Go/Python echo example code — NOT in specs/02 or specs/05 |
| `process_preserves_history` | The decision envelope may carry a top-level `history` field echoing `context.history` | Only in SDK protocol types (Go `Decision.History`, Python `Decision(history=...)`) — absent from specs/02 §4 examples |

I had to read `shim/src/h3_shim/test_battery.py` and the Go template
`main.go` to learn both. Applying them (two small additions to my harness)
→ **43/43**:

```python
finished = "do not finish" not in content          # streaming convention
dec["history"] = [{"role": e.get("role",""), "content": e.get("content","")}
                  for e in (body.get("context") or {}).get("history", [])]
```

Takeaway: the spec hub is ~97% self-sufficient. Two one-line conventions
would make it 100% — see DOGFOOD-03.

### 3.5 Python SDK echo harness — ✅ 43/43 (after a port fix, P2, DOGFOOD-05)

```bash
uv pip install --python /tmp/dogfood-h3/.venv/bin/python -e /home/kara/get-h3/sdk-python
python src/h3_harness/examples/echo.py   # hardcodes 0.0.0.0:8000
```

`:8000` was already taken by an unrelated service on this host → uvicorn
exits (Errno 98). Worse: pointing `h3-test` at `:8000` while the OTHER
service runs gives a baffling **9/43** (the battery tests a server that
isn't yours). The board itself hit this exact trap in tick #35. Fix: run
the example on a free port (copy + `port=8001`) → **43/43**.

```bash
h3-test --endpoint http://localhost:8001
# TOTAL 43/43 PASSED · Duration 0.25s · p50 1.09ms
```

### 3.6 Management CLI (hermes-h3) — ✅ WORKS

```bash
hermes-h3 --config /tmp/dogfood-h3/h3config.yaml install my-harness --endpoint http://localhost:9191
hermes-h3 --config /tmp/dogfood-h3/h3config.yaml list
# my-harness  http://localhost:9191  rest  30000
hermes-h3 --config /tmp/dogfood-h3/h3config.yaml verify --harness my-harness
# status: HealthStatus.OK  version: 1.0.0
hermes-h3 --config /tmp/dogfood-h3/h3config.yaml test --endpoint http://localhost:9191
# 43/43
```

Battery exit-code discipline is correct: `0` on pass, `1` on failure (tested
against a dead endpoint). `--json` produces a machine-readable report with
per-test details (`passed`, `detail`, `duration_ms`, `category`).

## 4. The "aha"

The protocol is real and the gate is honest. Three different implementations
(Go SDK scaffold, Python SDK, and a from-scratch stdlib harness) all reach
43/43 against the same battery, and the from-scratch one got there with the
spec as its only teacher (41/43 immediately; 43/43 with two conventions the
spec should document). For a harness developer the loop is: read specs/02 →
implement 6 endpoints → run `h3-test` → iterate. The battery's error
messages are specific enough to debug against.

## 5. What a new user needs that isn't documented

1. Source-install instructions for the shim and SDKs (nothing is on PyPI yet).
2. The sdk-go `replace` workaround for the scaffolded harness (or a tagged release).
3. The two protocol conventions from §3.4 (DOGFOOD-03).
4. Port configurability for the Python echo example.
5. The correct binary name (`hermes-h3`, not `hermes h3`) and scaffold dir
   (`h3-harness-<lang>`).

## 6. If I had 1 hour of the maintainer's time

1. Publish `hermes-h3-shim` + `h3-harness-sdk` to PyPI (unblock P3-10) —
   the README's first command currently fails for everyone outside the fleet.
2. Tag sdk-go `v0.1.0` and make the scaffold's go.mod resolve it (or ship
   the replace uncommented).
3. Add the `history` echo + `"do not finish"` convention to specs/02 §4 —
   two sentences that save every future harness author 45 minutes.

## 7. Reproduce

```bash
mkdir -p /tmp/dogfood-h3 && cd /tmp/dogfood-h3
uv venv .venv
uv pip install --python .venv/bin/python -e /home/kara/get-h3/shim
.venv/bin/hermes-h3 scaffold --lang go --output-dir /tmp/dogfood-h3
# (uncomment the replace in h3-harness-go/go.mod pointing at your sdk-go)
cd h3-harness-go && go mod tidy && go build -o h3harness . && ./h3harness &
cd /tmp/dogfood-h3 && .venv/bin/h3-test --endpoint http://localhost:9191
```

All placeholder values; no credentials involved. The custom harness from
§3.4 is ~130 lines of stdlib Python — pattern: one handler per endpoint, one
`_decision_*` helper per decision type, error shape per specs/02 §9.
