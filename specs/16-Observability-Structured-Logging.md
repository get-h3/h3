# S16 — H3 Observability & Structured Logging (OBS-01)

**Status:** Spec
**Version:** 1.0.0
**Depends on:** S02 (Protocol), S06 (Hermes Core Integration), S12 (Security §8 — Secret Handling)
**Last Updated:** 2026-07-21

---

## 1. Overview

The H3 protocol currently has ad-hoc logging across all components. The Shim uses Python `logging` with inconsistent key-value pairs. The SDKs use `log.Printf` (Go) and `console.info` (TypeScript) with no structured format. When a session goes wrong, debugging requires correlating logs across 4+ components (Hermes, Shim, harness, SDK middleware) with no common identifier.

**This spec defines:** structured JSON logging with mandatory `session_id`, `decision_id`, and `trace_id` fields on every log line across all H3 components.

**Design principle:** "Every log line is a self-contained diagnostic." A single log line, isolated from all context, should tell you: what happened, in which session, at what decision step, and how to find the corresponding log in every other component.

**Scope:** OBS-01 on the task board. Covers the logging format, trace propagation, and implementation contracts for all 4 H3 components (Shim, SDK-Go, SDK-Python, SDK-TS). Metrics (OBS-02), distributed tracing backend (OBS-03), health check v2 (OBS-04), dashboard (OBS-05), and alerting (OBS-06) are separate specs.

**Implementation targets:**
- `shim/` — Structured JSON logger replacing bare `logging` calls
- `sdk-go/` — `slog` adapter in middleware + harness helper
- `sdk-python/` — `structlog` adapter in middleware
- `sdk-typescript/` — JSON `.toJSON()` adapter in middleware
- `protocol/` — `trace_id` field added to ProcessRequest and Decision schemas (new optional field, backward-compatible)

---

## 2. Structured Log Format

### 2.1 Canonical Fields

Every log line across all H3 components MUST include these fields when available:

| Field | Type | Required | Source | Description |
|-------|------|----------|--------|-------------|
| `timestamp` | RFC3339Nano | ✅ Always | Logger | When the event occurred |
| `level` | string | ✅ Always | Logger | `debug`, `info`, `warn`, `error`, `critical` |
| `logger` | string | ✅ Always | Logger | Component name: `h3.shim`, `h3.harness.go`, `h3.harness.py`, `h3.harness.ts` |
| `session_id` | string | ✅ Always | Protocol | H3 session ID — `uuid4` or `uuid7` (time-ordered) |
| `decision_id` | string | When available | Protocol | H3 decision ID — present on process/result paths, absent on health/startup |
| `trace_id` | string | ✅ Always | Generated on entry | Propagated across all components. Same format as W3C traceparent: 32 hex chars |
| `span_id` | string | ✅ Always | Generated per-hop | 16 hex chars. New span per component boundary. |
| `event` | string | ✅ Always | Developer | What happened: `process_request`, `result_submitted`, `tool_executed`, `health_check`, `harness_error`, `shim_error`, `session_start`, `session_end`, `auth_failed`, `rate_limited` |
| `component` | string | ✅ Always | Logger | `hermes`, `shim`, `harness.go`, `harness.py`, `harness.ts` |
| `duration_ms` | float | When available | Logger | Wall-clock duration of the operation |
| `status_code` | int | When available | Logger | HTTP status code (for HTTP handlers) |
| `error` | string | When error | Logger | Error message (no stack trace in production) |
| `msg` | string | ✅ Always | Developer | Human-readable description |

### 2.2 JSON Format

```
{"timestamp":"2026-07-21T16:48:07.123456789Z","level":"info","logger":"h3.shim","session_id":"a1b2c3d4-...","decision_id":"d56b78e5-...","trace_id":"0af7651916cd43dd8448eb211c80319c","span_id":"b7ad6b7169203331","event":"process_request","component":"shim","duration_ms":12.5,"status_code":200,"msg":"Process request sent to harness"}
```

**Rules:**
- Single line per event (no multiline). Use `\n` → `\\n` escaping in `msg` and `error`.
- JSON only. No `key=value` formats, no unstructured text.
- Keys are snake_case.
- Values are JSON-native: strings, numbers, booleans, null.
- `null` for absent optional fields — never omit the key.

### 2.3 Log Levels

| Level | When |
|-------|------|
| `debug` | Development: full request/response bodies, tool arguments, raw LLM messages |
| `info` | Production: session lifecycle, decisions, tool calls, HTTP requests, health checks |
| `warn` | Recoverable errors: harness timeout (retrying), non-critical tool failure, auth warning |
| `error` | Unrecoverable: harness crash, decision parse failure, HTTP 5xx, tool crash |
| `critical` | System-level: shim loop panic, multiple harness failures in a row, Hermes integration broken |

**Sensitive data:** Never log API keys, tokens, or full LLM message content at `info` or above. See §5 (Security).

---

## 3. Trace ID Propagation

### 3.1 Generation

The **first H3 component to handle a session** generates `trace_id`. This is always the Shim (Hermes-side), since the harness is stateless and receives sessions from Hermes via the Shim.

```
trace_id = uuid4().hex  # 32 hex chars, lowercase
span_id  = uuid4().hex[:16]  # 16 hex chars
```

### 3.2 Propagation Chain

```
Hermes Core → Shim (generates trace_id)
    │
    │  HTTP Header: X-H3-Trace-ID, X-H3-Span-ID
    ▼
SDK Middleware (reads trace_id, generates new span_id)
    │
    ▼
Harness (uses same trace_id, same span_id)
    │
    │  HTTP Response Header: X-H3-Trace-ID (echo back)
    ▼
Shim (receives trace_id back, generates new span_id for result phase)
```

### 3.3 HTTP Headers

| Header | Value | Direction |
|--------|-------|-----------|
| `X-H3-Trace-ID` | 32 hex chars | Shim → Harness, Harness → Shim (echo) |
| `X-H3-Span-ID` | 16 hex chars | Shim → Harness (new per request) |
| `X-H3-Session-ID` | uuid4 | Shim → Harness (redundant with body, but available before body parse) |

These are **optional** headers for backward compatibility. Harnesses that don't implement tracing still work — they just won't log trace_id. The Shim always sends them; the SDK middleware auto-reads them.

### 3.4 Trace Lifecycle

```
trace_id: 0af7651916cd43dd8448eb211c80319c  (generated once, session lifetime)
  span_id: b7ad6b7169203331  (Shim — process phase)
  span_id: 00f067aa0ba902b7  (Harness SDK — receive process)
  span_id: 1bad0c1a2b3c4d5e  (Harness user code — onProcess)
  span_id: 6ba7b8109dad0d1e  (Shim — result phase)
  span_id: 2bad1c2b3d4e5f6a  (Harness SDK — receive result)
  span_id: 7da8c9110ebe1e2f  (Harness user code — onResult)
  ...continues per turn...
```

---

## 4. Component Implementations

### 4.1 Shim (Python — `h3_shim`)

**Current state:** Uses `logging` module. Has `session_id` in most lines, `decision_id` in one place. No trace_id.

**Target:** Replace `logging.getLogger(__name__)` with a `h3_logger` that wraps `structlog`.

```python
# shim/src/h3_shim/logging.py (new file)
import structlog
import uuid
from datetime import datetime, timezone

def h3_log(session_id: str, event: str, **kwargs) -> None:
    """Structured H3 log line. Always includes session_id + trace_id."""
    log = structlog.get_logger("h3.shim")
    log.info(
        event,
        session_id=session_id,
        timestamp=datetime.now(timezone.utc).isoformat(),
        **kwargs,
    )
```

**Migration plan:**
1. Add `structlog` to dev dependencies
2. Create `logging.py` with `h3_log()` helper
3. Replace all `logger.info(...)` / `logger.warning(...)` / `logger.error(...)` calls with `h3_log(session_id, event, ...)`
4. Add `trace_id` generation in `shim_loop.py` entry point
5. Add `X-H3-Trace-ID` / `X-H3-Span-ID` headers in `client.py`

**Example before/after:**

```python
# BEFORE
logger.info("H3ShimLoop: session started %s", self.session_id)

# AFTER
h3_log(self.session_id, "session_start",
       trace_id=self.trace_id, span_id=new_span(),
       decision_id=None, component="shim")
```

### 4.2 SDK-Go (Go)

**Current state:** Uses `log.Printf` with free-form text. Captures method, path, status, duration.

**Target:** Add `slog` support via a configurable `*slog.Logger` field.

```go
// harness/middleware.go — new fields
type MiddlewareConfig struct {
    Logger *slog.Logger  // nil = use slog.Default()
}

// harness/harness.go — new helper type
type TraceContext struct {
    TraceID   string `json:"trace_id"`
    SpanID    string `json:"span_id"`
    SessionID string `json:"session_id"`
}

// Auto-extract from HTTP headers
func TraceFromRequest(r *http.Request) TraceContext {
    return TraceContext{
        TraceID:   r.Header.Get("X-H3-Trace-ID"),
        SpanID:    uuid.New().String()[:16],  // new span
        SessionID: r.Header.Get("X-H3-Session-ID"),
    }
}
```

**Middleware log format (before → after):**

```
// BEFORE
log.Printf("harness: %s %s %d %s", r.Method, r.URL.Path, rw.statusCode, time.Since(start))

// AFTER
logger.Info("harness_request",
    slog.String("session_id", sessionID),
    slog.String("trace_id", traceCtx.TraceID),
    slog.String("span_id", traceCtx.SpanID),
    slog.String("method", r.Method),
    slog.String("path", r.URL.Path),
    slog.Int("status_code", rw.statusCode),
    slog.Float64("duration_ms", float64(time.Since(start).Microseconds())/1000),
)
```

**Harness developer API:**
```go
// Harness interface — add optional context method
type Harness interface {
    OnProcess(ctx context.Context, req *protocol.ProcessRequest) (*protocol.Decision, error)
    OnResult(ctx context.Context, req *protocol.ResultRequest) (*protocol.Decision, error)
    Health() protocol.HealthResponse
}

// ctx carries TraceContext via context.WithValue
func TraceFromContext(ctx context.Context) TraceContext { ... }
```

### 4.3 SDK-Python (Python)

**Target:** Same as Shim — `structlog`-based. Harness developers get a `h3_log()` helper.

```python
# sdk-python/src/h3_harness/logging.py (new file)
from h3_harness.protocol import TraceContext

def harness_log(trace: TraceContext, event: str, **kwargs):
    """Log from inside harness user code."""
    import structlog
    log = structlog.get_logger("h3.harness.py")
    log.info(event,
        session_id=trace.session_id,
        trace_id=trace.trace_id,
        span_id=trace.span_id,
        **kwargs)
```

### 4.4 SDK-TypeScript (TypeScript)

**Target:** JSON serializer in middleware. Harness devs get a `harnessLog()` function.

```typescript
// sdk-typescript/src/logging.ts (new file)
export interface TraceContext {
  trace_id: string;
  span_id: string;
  session_id: string;
}

export function harnessLog(trace: TraceContext, event: string, extra: Record<string, unknown> = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level: 'info',
    logger: 'h3.harness.ts',
    session_id: trace.session_id,
    trace_id: trace.trace_id,
    span_id: trace.span_id,
    event,
    ...extra,
  };
  console.info(JSON.stringify(entry));
}

// Extract from request headers
export function traceFromHeaders(headers: Headers): TraceContext {
  return {
    trace_id: headers.get('X-H3-Trace-ID') ?? '',
    span_id: crypto.randomUUID().slice(0, 16),
    session_id: headers.get('X-H3-Session-ID') ?? '',
  };
}
```

---

## 5. Security: No Secrets in Logs

**Reference:** S12 §8 (Secret Handling)

### 5.1 Field Blacklist

These fields MUST NEVER appear in any log line at any level:

| Blacklisted Pattern | Found In |
|---|---|
| `Authorization` header value | HTTP request headers |
| `X-H3-API-Key` or any `*_API_KEY` | HTTP headers, env vars |
| `h3_` prefix tokens (harness API key) | `client.py`, config files |
| `h3_hx_` prefix tokens (Hermes identity) | `client.py`, config files |
| Private key material (PEM, Ed25519 seed) | TLS config |
| LLM API keys (`sk-*`, `sk-or-v1-*`) | Hermes-side only |

### 5.2 Redaction

Loggers MUST redact sensitive values before emission:

```python
# Python — structlog processor
def redact_sensitive(_, __, event_dict):
    for key in list(event_dict):
        if any(p in key.lower() for p in ('token', 'key', 'secret', 'authorization', 'api_key')):
            event_dict[key] = '[REDACTED]'
    return event_dict
```

### 5.3 Log Level Gating

| Content | Max Level |
|---------|-----------|
| Full request body (ProcessRequest JSON) | `debug` |
| Full response body (Decision JSON) | `debug` |
| LLM message text content | `debug` |
| Tool arguments (may contain user data) | `debug` |
| Error stack traces | `error` (production-safe — no secrets in args) |

---

## 6. Configuration

### 6.1 Shim Configuration

```yaml
# .hermes/h3/config.yaml
logging:
  level: info              # debug | info | warn | error | critical
  format: json             # json | text (text = human-readable for dev)
  output: stderr           # stderr | stdout | file:/path/to/h3.log
  redact_secrets: true     # always true in production
  include_tracebacks: false  # true in dev, false in prod
```

### 6.2 Harness Configuration

```yaml
# .h3-harness.yaml
logging:
  level: info
  format: json
  output: stderr
  redact_secrets: true
```

### 6.3 Environment Variable Overrides

```
H3_LOG_LEVEL=debug
H3_LOG_FORMAT=text
H3_LOG_OUTPUT=file:/var/log/h3-harness.log
H3_LOG_REDACT=false       # dev only — never in production
```

---

## 7. Diagnostic Queries

With structured JSON logging, common diagnostic queries become trivial:

### "Show me everything for session X"
```bash
cat h3.log | jq 'select(.session_id == "a1b2c3d4-...")'
```

### "Show me all harness errors in the last hour"
```bash
cat h3.log | jq 'select(.level == "error" and .component == "harness.go")'
```

### "Find slow decisions (>500ms)"
```bash
cat h3.log | jq 'select(.event == "process_request" and .duration_ms > 500)'
```

### "Trace a full session through all components"
```bash
cat h3.log | jq 'select(.trace_id == "0af7651916cd43dd8448eb211c80319c")' | jq -s 'sort_by(.timestamp)'
```

### "Count decision types per harness"
```bash
cat h3.log | jq -r 'select(.event == "decision_executed") | [.component, .decision_type] | @tsv' | sort | uniq -c
```

---

## 8. Performance

### 8.1 Overhead Budget

| Component | Max Log Overhead per Request | Notes |
|-----------|------------------------------|-------|
| Shim | <1ms | `structlog` is async-capable. JSON serialization is ~50µs. |
| SDK middleware | <0.5ms | `slog` is zero-alloc when disabled. At `info`, ~200ns per attribute. |

### 8.2 Production Configuration

- `level: warn` → only warnings/errors in production (minimal overhead)
- `format: json` → machine-parseable
- Disable `debug` logging entirely: `level >= info` prevents expensive object serialization

### 8.3 Sampling

For high-throughput harnesses (>100 decisions/sec), sample non-error events:

```yaml
logging:
  sample_rate: 0.10  # log 10% of info+warn, 100% of error+critical
```

Sampling is per-trace_id — all events in a sampled trace are logged; all events in a non-sampled trace are dropped. This preserves trace coherence.

---

## 9. Testing

### 9.1 Test Categories

| ID | Test | Category |
|----|------|----------|
| LOG-01 | Shim logs contain session_id, trace_id, span_id on every line | Unit |
| LOG-02 | Shim generates unique trace_id per session | Unit |
| LOG-03 | Shim generates new span_id per hop (process → result) | Unit |
| LOG-04 | Shim sends X-H3-Trace-ID and X-H3-Span-ID headers | Integration |
| LOG-05 | Go SDK middleware extracts trace_id from headers | Unit |
| LOG-06 | Go SDK logs contain session_id, trace_id, span_id | Unit |
| LOG-07 | Python SDK middleware extracts trace_id from headers | Unit |
| LOG-08 | TypeScript SDK middleware extracts trace_id from headers | Unit |
| LOG-09 | Auth headers are redacted in logs (all 4 components) | Security |
| LOG-10 | API keys never appear in log output (grep audit) | Security |
| LOG-11 | Sample rate: 10% logs 1 in 10; 100% logs all | Unit |
| LOG-12 | JSON output is valid, parsable by `jq` | Integration |
| LOG-13 | Error stack traces are logged at `error` level only | Unit |
| LOG-14 | Harness without tracing (no headers) → trace_id empty, still logs | Backward Compat |
| LOG-15 | Trace persists across 10-turn session (same trace_id throughout) | Integration |

### 9.2 CI Integration

- `h3-test` — add Region 7: Observability (3 tests: LOG-01, LOG-02, LOG-14 as smoke tests)
- SDK unit tests — per-SDK: LOG-05/06/07/08
- Security audit — LOG-09, LOG-10 as part of SEC-06 audit pipeline

---

## 10. Migration Guide

### 10.1 Phase 1: Shim Structured Logging (OBS-IMPL-01)

1. Add `structlog` to shim dependencies
2. Create `shim/src/h3_shim/logging.py` with `h3_log()` + `redact_sensitive()` processor
3. Generate `trace_id` at session start (`shim_loop.py:__init__`)
4. Add `X-H3-Trace-ID` / `X-H3-Span-ID` to `client.py` HTTP requests
5. Replace all `logger.info/warn/error` calls with `h3_log()`
6. Verify: 178 existing tests pass + new LOG-01 through LOG-04 tests

### 10.2 Phase 2: SDK Middleware (OBS-IMPL-02)

Per SDK (Go → Python → TypeScript):
1. Add trace header extraction to middleware
2. Add structured logger (slog/structlog/JSON)
3. Add TraceContext to harness context
4. Expose `harnessLog()` helper for user code
5. Verify: existing SDK tests pass + new LOG-05 through LOG-08 tests

### 10.3 Phase 3: Protocol Update

1. Add `trace_id` (optional string) to ProcessRequest schema
2. Add `trace_id` (optional string) to Decision schema
3. Add `X-H3-Trace-ID` to protocol spec (S02) headers section
4. Version bump: protocol v1.0 → v1.1 (backward-compatible — new optional fields)

### 10.4 Phase 4: Production Rollout

1. `level: warn` in production configs
2. Log aggregation: stdout → systemd-journald / Docker json-file → Loki/Elasticsearch
3. Dashboard: Grafana panels for error rate, p95 latency, session count
4. Alerting: error rate > 5% triggers notification

---

## 11. Backward Compatibility

- **No tracing headers (v1.0 harness):** SDK middleware sets `trace_id = ""`, logs normally. All functionality preserved.
- **Shim before upgrade:** Existing `logging` calls continue to work. New `h3_log()` added alongside. Full migration is phased.
- **Log format:** Old text logs and new JSON logs coexist during migration. Log aggregators should handle both formats.

---

## 12. References

- S02 §3 — Protocol endpoint definitions
- S06 §4 — Hermes Core integration points
- S12 §8 — Secret handling, log redaction
- S13 — Token rotation (audit log events)
- S15 — Rate limiting (rate_limit_exceeded log events)
- W3C Trace Context: https://www.w3.org/TR/trace-context/

---

## Appendix A: Full Log Event Catalog

| Event | Component | Level | Fields |
|-------|-----------|-------|--------|
| `session_start` | shim | info | session_id, trace_id, span_id, chat_id, harness_endpoint |
| `session_end` | shim | info | session_id, trace_id, span_id, end_reason, total_turns, total_duration_ms |
| `process_request` | shim | info | session_id, trace_id, span_id, decision_id, duration_ms, status_code |
| `result_submitted` | shim | info | session_id, trace_id, span_id, decision_id, duration_ms, status_code |
| `tool_executed` | shim | info | session_id, trace_id, span_id, tool_name, duration_ms, success (bool) |
| `llm_call` | shim | info | session_id, trace_id, span_id, model, message_count, duration_ms |
| `health_check` | shim, harness | debug | session_id (null), trace_id, span_id, status_code, duration_ms |
| `auth_failed` | shim, harness | warn | session_id, trace_id, span_id, reason |
| `rate_limited` | shim | warn | session_id, trace_id, span_id, tier (global/harness/session), retry_after |
| `harness_error` | shim | error | session_id, trace_id, span_id, error, status_code, harness_endpoint |
| `harness_timeout` | shim | warn | session_id, trace_id, span_id, timeout_s, harness_endpoint |
| `harness_request` | harness.* | info | session_id, trace_id, span_id, method, path, status_code, duration_ms |
| `harness_process` | harness.* | info | session_id, trace_id, span_id, decision_type, duration_ms |
| `harness_result` | harness.* | info | session_id, trace_id, span_id, decision_type, duration_ms |
| `harness_panic` | harness.* | error | session_id, trace_id, span_id, error, stack_trace (truncated) |
| `key_rotated` | shim | info | session_id (null), trace_id, span_id, key_prefix (first 8 chars) |
| `key_revoked` | shim | warn | session_id (null), trace_id, span_id, key_prefix (first 8 chars) |
| `circuit_open` | shim | error | session_id (null), trace_id, span_id, harness_endpoint, error_rate |
| `fallback_native` | shim | warn | session_id, trace_id, span_id, reason |

---

*Spec S16 — Observability & Structured Logging. 12 sections, ~20KB.*
*Part of the OBS phase (OBS-01 through OBS-06). Next: OBS-02 (Metrics).*
