# S18 — H3 Distributed Tracing (OBS-03)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S02 (Protocol), S06 (Hermes Core Integration), S16 (Structured Logging), S17 (Metrics)  
**Last Updated:** 2026-07-21

---

## 1. Overview

S16 defines the `trace_id` and `span_id` fields on every log line — giving us the *identifiers*. S17 defines the metrics layer — giving us the *aggregate view*. Neither gives us the *timeline*: the end-to-end latency waterfall showing exactly where time was spent across every hop in the H3 decision pipeline.

**This spec defines:** a distributed tracing system that records every hop in the decision pipeline as a span, propagates trace context via HTTP headers, and stores traces in an OpenTelemetry-compatible backend for querying and visualization.

**Design principle:** "Every decision is a trace. Every trace is queryable. Tracing must not block the critical path." Span creation and context propagation must be sub-microsecond overhead. Trace export must happen asynchronously, never blocking the decision loop.

**Scope:** OBS-03 on the task board. Covers trace format, propagation protocol, storage architecture, SDK middleware contracts, CLI surface, and test scenarios. Trace backend deployment (Jaeger/Tempo), dashboard (OBS-05), and alerting (OBS-06) are separate specs.

**Implementation targets:**
- `shim/` — Trace context generator, span recorder, async trace exporter (`h3/tracing.py`)
- `sdk-go/` — Trace middleware: span creation, context propagation, trace header extraction
- `sdk-python/` — Trace middleware with same interfaces
- `sdk-typescript/` — Trace middleware with same interfaces
- `protocol/` — New HTTP headers: `traceparent`, `tracestate` (W3C Trace Context)

**Key outcomes:**
- **Latency waterfall:** See exactly how long each hop took (Hermes→Shim, Shim→Harness, Harness processing, Harness→Shim, Shim→Hermes)
- **Cross-component correlation:** One `trace_id` links Hermes logs + Shim logs + harness logs + SDK middleware logs
- **Error attribution:** When a decision fails, the trace shows which hop failed and why
- **Capacity planning:** Aggregate trace data reveals p95 latency per hop, identifying bottlenecks

---

## 2. Trace Architecture

### 2.1 Span Hierarchy

Every decision creates a trace. Each hop in the pipeline is a span:

```
Trace: trace_id=abc123 (session S1, decision D42)

  ├── Span: hermes.call                   [Hermes]
  │   ├── Span: h3.shim.process           [Shim]
  │   │   ├── Span: http.request          [Shim → Harness]
  │   │   │   └── Span: harness.process   [Harness/SDK Middleware]
  │   │   │       ├── Span: llm.call      [Harness — if LLM was called]
  │   │   │       └── Span: tool.execute  [Harness — if tools were used]
  │   │   └── Span: http.response         [Harness → Shim]
  │   └── Span: h3.shim.result            [Shim]
  │       └── Span: decision.execute      [Shim → Hermes tool execution]
  └── Span: hermes.deliver                [Hermes → user]
```

### 2.2 Collection Pipeline

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Hermes  │───▶│   Shim   │───▶│  Harness │───▶│  Trace   │
│  (root   │    │  (middle │    │  (leaf   │    │  Backend │
│   span)  │    │   span)  │    │   spans) │    │ (Jaeger/ │
│          │    │          │    │          │    │  Tempo)  │
└──────────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘
                     │               │               │
                     └───────┬───────┘               │
                             │                       │
                     ┌───────▼───────────────────────▼─────┐
                     │         Async Trace Exporter        │
                     │  (batched, gzipped, OTLP/gRPC)      │
                     └─────────────────────────────────────┘
```

### 2.3 Sampling Strategy

| Environment | Sampling Rate | Rationale |
|-------------|---------------|-----------|
| Development | 100% | Debug every decision |
| Staging | 100% | Validate before production |
| Production (default) | 10% | Balance coverage vs cost |
| Production (error) | 100% | Always trace errors |
| Production (slow) | 100% | Always trace p99+ decisions |

**Adaptive sampling:** When error rate spikes above 5%, temporarily increase sampling to 100% for 5 minutes. When p95 latency exceeds threshold, sample all slow decisions.

**Implementation:** Head-based sampling. The Shim decides at trace root creation whether to sample. If sampled, all child spans are recorded. If not sampled, propagate trace context but don't record spans (W3C `sampled` flag = 0).

---

## 3. Trace Format

### 3.1 W3C Trace Context

H3 uses the W3C Trace Context standard for propagation:

**HTTP Header: `traceparent`**
```
traceparent: 00-{trace_id}-{span_id}-{trace_flags}
```

| Segment | Length | Description |
|---------|--------|-------------|
| `version` | 2 hex | `00` (current version) |
| `trace_id` | 32 hex | Globally unique trace identifier (16 bytes) |
| `span_id` | 16 hex | Current span identifier (8 bytes) |
| `trace_flags` | 2 hex | `01` = sampled, `00` = not sampled |

**Example:**
```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```

**HTTP Header: `tracestate`**
```
tracestate: h3=session:S1;decision:D42;harness:echo
```

Vendor-specific key-value pairs. H3 includes:
- `session` — session ID
- `decision` — decision ID (when in a process/result span)
- `harness` — harness name

### 3.2 Span Data Model

Each span records:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `trace_id` | hex(32) | ✅ | W3C trace ID |
| `span_id` | hex(16) | ✅ | W3C span ID |
| `parent_span_id` | hex(16) | ✅ | Parent span (empty for root) |
| `name` | string | ✅ | Operation name (e.g., `h3.shim.process`) |
| `kind` | enum | ✅ | `CLIENT`, `SERVER`, `INTERNAL`, `PRODUCER`, `CONSUMER` |
| `start_time` | RFC3339Nano | ✅ | Span start |
| `end_time` | RFC3339Nano | ✅ | Span end |
| `status` | {code, message} | ✅ | `OK` or `ERROR` |
| `attributes` | map[string]string | ✅ | Key-value metadata |
| `events` | [{name, timestamp, attributes}] | — | Timeline annotations |

**Standard attributes:**

| Attribute | Where | Description |
|-----------|-------|-------------|
| `h3.session_id` | All spans | Session ID |
| `h3.decision_id` | Process/result spans | Decision ID |
| `h3.decision_type` | Process/result spans | `process`, `result`, `end` |
| `h3.harness` | All spans after Shim | Harness name |
| `h3.component` | All spans | `hermes`, `shim`, `harness.go`, `harness.py`, `harness.ts` |
| `http.method` | HTTP spans | `GET`, `POST`, etc. |
| `http.url` | HTTP spans | Full URL path |
| `http.status_code` | HTTP spans | Response status code |
| `http.request_size` | HTTP spans | Request body size in bytes |
| `http.response_size` | HTTP spans | Response body size in bytes |
| `llm.model` | LLM call spans | Model name |
| `llm.tokens_in` | LLM call spans | Input token count |
| `llm.tokens_out` | LLM call spans | Output token count |
| `tool.name` | Tool execution spans | Tool name |

---

## 4. Propagation Mechanism

### 4.1 Shim: Root Span Creation

The Shim creates the root trace when it receives a process request:

```python
# shim/src/h3_shim/tracing.py
import time
import uuid
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class Span:
    trace_id: str
    span_id: str
    parent_span_id: Optional[str]
    name: str
    kind: str  # INTERNAL, CLIENT, SERVER
    start_time: float  # time.monotonic()
    end_time: Optional[float] = None
    status: str = "OK"
    attributes: dict = field(default_factory=dict)
    events: list = field(default_factory=list)

class TraceContext:
    """Manages trace lifecycle for one decision."""
    
    def __init__(self, session_id: str, decision_id: str, sample_rate: float = 0.10):
        self.trace_id = uuid.uuid4().hex  # 32 hex chars
        self.session_id = session_id
        self.decision_id = decision_id
        self.sampled = self._should_sample(sample_rate)
        self.spans: list[Span] = []
        self._active_span: Optional[Span] = None
    
    def start_span(self, name: str, kind: str = "INTERNAL",
                   parent: Optional[Span] = None) -> Span:
        span_id = uuid.uuid4().hex[:16]
        parent_id = parent.span_id if parent else None
        span = Span(
            trace_id=self.trace_id,
            span_id=span_id,
            parent_span_id=parent_id,
            name=name,
            kind=kind,
            start_time=time.monotonic(),
            attributes={
                "h3.session_id": self.session_id,
                "h3.decision_id": self.decision_id,
                "h3.component": "shim",
            }
        )
        if self.sampled:
            self.spans.append(span)
        self._active_span = span
        return span
    
    def end_span(self, span: Span, status: str = "OK"):
        span.end_time = time.monotonic()
        span.status = status
    
    def traceparent_header(self, span: Span) -> str:
        flags = "01" if self.sampled else "00"
        return f"00-{self.trace_id}-{span.span_id}-{flags}"
    
    def tracestate_header(self) -> str:
        return f"h3=session:{self.session_id};decision:{self.decision_id}"
```

### 4.2 HTTP Propagation

**Shim → Harness (process request):**
```http
POST /v1/process HTTP/1.1
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
tracestate: h3=session:S1;decision:D42;harness:echo
Authorization: Bearer h3_hx_...
Content-Type: application/json
```

**SDK Middleware extracts:**
```python
# sdk-python/src/h3_harness/middleware/tracing.py
def extract_trace_context(request):
    traceparent = request.headers.get("traceparent", "")
    tracestate = request.headers.get("tracestate", "")
    
    if traceparent:
        parts = traceparent.split("-")
        return {
            "trace_id": parts[1],
            "parent_span_id": parts[2],
            "sampled": parts[3] == "01",
        }
    return None
```

### 4.3 Protocol Changes

Add to ProcessRequest and Decision schemas as OPTIONAL fields (backward-compatible):

```yaml
# protocol/h3-protocol.yaml — additions
ProcessRequest:
  properties:
    # ... existing fields ...
    trace_context:
      type: object
      description: "W3C Trace Context for distributed tracing (OPTIONAL)"
      properties:
        traceparent:
          type: string
          pattern: '^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$'
        tracestate:
          type: string
```

---

## 5. Storage & Export

### 5.1 Export Protocol

Traces are exported via OTLP (OpenTelemetry Protocol) over gRPC or HTTP:

```python
# shim/src/h3_shim/tracing_exporter.py
import json
import gzip
import asyncio
from dataclasses import asdict

class OTLPExporter:
    """Async trace exporter. Never blocks the decision loop."""
    
    def __init__(self, endpoint: str, batch_size: int = 100,
                 flush_interval_s: float = 5.0):
        self.endpoint = endpoint
        self.batch_size = batch_size
        self.flush_interval_s = flush_interval_s
        self._buffer: list[Span] = []
        self._running = False
    
    async def export_span(self, span: Span):
        """Non-blocking span export. Adds to buffer, flushes when full."""
        self._buffer.append(span)
        if len(self._buffer) >= self.batch_size:
            await self._flush()
    
    async def _flush(self):
        if not self._buffer:
            return
        payload = self._serialize(self._buffer)
        self._buffer.clear()
        # Fire-and-forget — don't block if export fails
        asyncio.create_task(self._send(payload))
    
    def _serialize(self, spans: list[Span]) -> bytes:
        """OTLP JSON format, gzipped."""
        otlp_spans = []
        for s in spans:
            otlp_spans.append({
                "traceId": s.trace_id,
                "spanId": s.span_id,
                "parentSpanId": s.parent_span_id or "",
                "name": s.name,
                "kind": _SPAN_KIND_MAP.get(s.kind, 1),
                "startTimeUnixNano": str(int(s.start_time * 1e9)),
                "endTimeUnixNano": str(int(s.end_time * 1e9)),
                "status": {"code": 0 if s.status == "OK" else 2},
                "attributes": [
                    {"key": k, "value": {"stringValue": v}}
                    for k, v in s.attributes.items()
                ],
            })
        return gzip.compress(
            json.dumps({"resourceSpans": [{
                "scopeSpans": [{"spans": otlp_spans}]
            }]}).encode()
        )
```

### 5.2 Backend Options

| Backend | Protocol | Setup Complexity | Query Language | Recommended For |
|---------|----------|-----------------|----------------|-----------------|
| **Jaeger** | OTLP gRPC | Low (single binary) | Jaeger UI | Small deployments |
| **Grafana Tempo** | OTLP gRPC | Medium (needs object storage) | TraceQL | Production, scales horizontally |
| **Honeycomb** | OTLP HTTP | Low (SaaS) | Honeycomb Query | Teams without ops bandwidth |
| **SigNoz** | OTLP gRPC | Medium (Docker Compose) | ClickHouse SQL | Self-hosted with metrics+traces |

**Default recommendation:** Jaeger for development (<100 decisions/day), Tempo for production (>1000 decisions/day).

### 5.3 Retention

| Tier | Retention | Sampling | Storage Estimate |
|------|-----------|----------|-----------------|
| Development | 24 hours | 100% | ~10 MB |
| Staging | 7 days | 100% | ~50 MB |
| Production | 30 days | 10% (100% errors/slow) | ~500 MB |

---

## 6. SDK Middleware Contracts

### 6.1 Python SDK

```python
# sdk-python/src/h3_harness/middleware/tracing.py
from dataclasses import dataclass
from typing import Optional, Callable
import time
import uuid

@dataclass
class TraceContext:
    trace_id: str
    parent_span_id: Optional[str]
    sampled: bool

class TracingMiddleware:
    """FastAPI/Starlette middleware for trace context extraction."""
    
    async def __call__(self, request, call_next):
        # Extract from HTTP headers
        traceparent = request.headers.get("traceparent", "")
        tracestate = request.headers.get("tracestate", "")
        
        ctx = self._parse_traceparent(traceparent) if traceparent else None
        
        # Attach to request state for handlers
        request.state.trace_context = ctx
        
        # Create server span
        span_id = uuid.uuid4().hex[:16]
        start = time.monotonic()
        
        try:
            response = await call_next(request)
            duration_ms = (time.monotonic() - start) * 1000
            
            # Emit span to harness metrics collector
            if ctx and ctx.sampled:
                self._emit_span(
                    name="harness.process",
                    trace_id=ctx.trace_id,
                    span_id=span_id,
                    parent_span_id=ctx.parent_span_id,
                    duration_ms=duration_ms,
                    status="OK" if response.status_code < 400 else "ERROR",
                    attributes={
                        "http.status_code": str(response.status_code),
                        "h3.harness": "python",
                    }
                )
            
            return response
        except Exception as e:
            duration_ms = (time.monotonic() - start) * 1000
            if ctx and ctx.sampled:
                self._emit_span(
                    name="harness.process",
                    trace_id=ctx.trace_id,
                    span_id=span_id,
                    parent_span_id=ctx.parent_span_id,
                    duration_ms=duration_ms,
                    status="ERROR",
                    attributes={"error": str(e)}
                )
            raise

    def _parse_traceparent(self, header: str) -> Optional[TraceContext]:
        parts = header.split("-")
        if len(parts) != 4 or parts[0] != "00":
            return None
        return TraceContext(
            trace_id=parts[1],
            parent_span_id=parts[2],
            sampled=parts[3] == "01",
        )
```

### 6.2 Go SDK

```go
// sdk-go/middleware/tracing.go
package middleware

import (
    "context"
    "net/http"
    "time"
)

type TraceContext struct {
    TraceID      string
    ParentSpanID string
    Sampled      bool
}

func ExtractTraceContext(r *http.Request) *TraceContext {
    tp := r.Header.Get("traceparent")
    if tp == "" {
        return nil
    }
    parts := strings.Split(tp, "-")
    if len(parts) != 4 || parts[0] != "00" {
        return nil
    }
    return &TraceContext{
        TraceID:      parts[1],
        ParentSpanID: parts[2],
        Sampled:      parts[3] == "01",
    }
}

// TracingMiddleware wraps an http.Handler with trace span creation
func TracingMiddleware(emitter SpanEmitter) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            ctx := ExtractTraceContext(r)
            spanID := generateSpanID()
            start := time.Now()

            // Attach to context
            if ctx != nil {
                r = r.WithContext(context.WithValue(r.Context(), traceContextKey, ctx))
            }

            // Wrap ResponseWriter to capture status code
            wrapped := &responseWriter{ResponseWriter: w, statusCode: 200}
            next.ServeHTTP(wrapped, r)

            duration := time.Since(start)
            status := "OK"
            if wrapped.statusCode >= 400 {
                status = "ERROR"
            }

            if ctx != nil && ctx.Sampled {
                emitter.EmitSpan(SpanData{
                    TraceID:       ctx.TraceID,
                    SpanID:        spanID,
                    ParentSpanID:  ctx.ParentSpanID,
                    Name:          "harness.process",
                    DurationMs:    float64(duration.Microseconds()) / 1000,
                    Status:        status,
                    StatusCode:    wrapped.statusCode,
                    Component:     "harness.go",
                })
            }
        })
    }
}
```

### 6.3 TypeScript SDK

```typescript
// sdk-typescript/src/middleware/tracing.ts
export interface TraceContext {
  traceId: string;
  parentSpanId: string | null;
  sampled: boolean;
}

export function extractTraceContext(headers: Headers): TraceContext | null {
  const tp = headers.get("traceparent");
  if (!tp) return null;
  const parts = tp.split("-");
  if (parts.length !== 4 || parts[0] !== "00") return null;
  return {
    traceId: parts[1],
    parentSpanId: parts[2],
    sampled: parts[3] === "01",
  };
}

export function tracingMiddleware(emitter: SpanEmitter) {
  return async (c: Context, next: () => Promise<void>) => {
    const ctx = extractTraceContext(c.req.raw.headers);
    const spanId = crypto.randomUUID().replace(/-/g, "").slice(0, 16);
    const start = performance.now();

    c.set("traceContext", ctx);

    await next();

    const duration = performance.now() - start;
    const status = c.res.status < 400 ? "OK" : "ERROR";

    if (ctx?.sampled) {
      emitter.emitSpan({
        traceId: ctx.traceId,
        spanId,
        parentSpanId: ctx.parentSpanId,
        name: "harness.process",
        durationMs: duration,
        status,
        statusCode: c.res.status,
        component: "harness.ts",
      });
    }
  };
}
```

---

## 7. CLI Surface

### 7.1 `hermes h3 trace`

```bash
# Show trace configuration
hermes h3 trace show [--json]

# Enable/disable tracing
hermes h3 trace enable [--sample-rate 0.10]
hermes h3 trace disable

# Change sampling rate
hermes h3 trace sample-rate 1.0     # 100% sampling (debug)
hermes h3 trace sample-rate 0.10    # 10% (production default)

# Export configuration
hermes h3 trace export --backend jaeger --endpoint http://localhost:14268/api/traces
hermes h3 trace export --backend tempo --endpoint http://localhost:4317  # gRPC
hermes h3 trace export --disable

# Test trace export
hermes h3 trace test  # sends test trace, verifies it was received
```

### 7.2 Configuration File

```yaml
# harness.yaml or h3.yaml — tracing section
tracing:
  enabled: true
  sample_rate: 0.10              # 10% head-based sampling
  error_sample_rate: 1.0         # 100% of errors
  slow_threshold_ms: 2000        # Sample all decisions slower than this
  adaptive_sampling: true        # Increase sampling during error spikes
  export:
    backend: jaeger              # jaeger | tempo | otlp | none
    endpoint: http://localhost:14268/api/traces
    protocol: http               # http | grpc
    batch_size: 100              # Spans per batch
    flush_interval_s: 5          # Max seconds between flushes
    compression: gzip            # none | gzip
    timeout_s: 10                # Export timeout
```

---

## 8. Test Scenarios

### 8.1 Unit Tests (TRACE-01 through TRACE-15)

| ID | Test | Description |
|----|------|-------------|
| TRACE-01 | `test_trace_context_creation` | TraceContext creates valid trace_id (32 hex) and initial span |
| TRACE-02 | `test_span_parent_child` | Child span references correct parent_span_id |
| TRACE-03 | `test_traceparent_header_format` | `traceparent` header matches W3C spec: `00-{32}-{16}-{2}` |
| TRACE-04 | `test_tracestate_header_format` | `tracestate` contains session and decision IDs |
| TRACE-05 | `test_sampling_100pct` | Sample rate 1.0 → all decisions sampled |
| TRACE-06 | `test_sampling_0pct` | Sample rate 0.0 → no decisions sampled |
| TRACE-07 | `test_sampling_10pct_statistical` | Over 1000 decisions at 0.10, sampled count is 90–110 (±2σ) |
| TRACE-08 | `test_error_always_sampled` | Errors sampled at 100% regardless of base rate |
| TRACE-09 | `test_slow_always_sampled` | Decisions exceeding `slow_threshold_ms` always sampled |
| TRACE-10 | `test_non_sampled_propagates_context` | Even when not sampled, `traceparent` header is sent (flags=00) |
| TRACE-11 | `test_span_duration_accuracy` | `end_time - start_time` matches actual elapsed time (within 5ms) |
| TRACE-12 | `test_otlp_serialization` | Span serializes to valid OTLP JSON |
| TRACE-13 | `test_batch_flush` | Buffer flushes when reaching batch_size |
| TRACE-14 | `test_interval_flush` | Buffer flushes after flush_interval_s even if not full |
| TRACE-15 | `test_export_failure_non_blocking` | Trace export failure does not raise exception in decision loop |

### 8.2 Integration Tests (TRACE-I-01 through TRACE-I-08)

| ID | Test | Description |
|----|------|-------------|
| TRACE-I-01 | `test_end_to_end_trace` | Full decision produces complete trace with all spans |
| TRACE-I-02 | `test_trace_id_matches_logs` | `trace_id` in structured logs matches trace `trace_id` |
| TRACE-I-03 | `test_cross_component_correlation` | Same trace_id in Shim logs and harness logs |
| TRACE-I-04 | `test_shim_extracts_harness_spans` | Shim receives harness spans via OTLP or health endpoint |
| TRACE-I-05 | `test_harness_custom_spans` | Harness developer adds custom span → appears in trace |
| TRACE-I-06 | `test_multi_decision_session` | Session with 10 decisions produces 10 traces with same session_id |
| TRACE-I-07 | `test_http_header_preservation` | traceparent survives HTTP round-trip without modification |
| TRACE-I-08 | `test_go_python_ts_cross_language` | Trace propagates correctly across Go/Python/TS harnesses |

### 8.3 Performance Tests (TRACE-P-01 through TRACE-P-03)

| ID | Test | Description |
|----|------|-------------|
| TRACE-P-01 | `test_span_creation_overhead` | Span creation + attribute set < 1µs (benchmark) |
| TRACE-P-02 | `test_trace_non_blocking` | Decision loop latency unchanged with tracing enabled vs disabled (<1% difference) |
| TRACE-P-03 | `test_high_throughput_export` | 1000 decisions/sec → no buffer overflow, no dropped spans |

---

## 9. Integration with S16 and S17

### 9.1 Shared Identifiers

| Field | S16 (Logging) | S17 (Metrics) | S18 (Tracing) |
|-------|---------------|---------------|---------------|
| `session_id` | Log field | Metric label | Span attribute |
| `decision_id` | Log field | Metric label | Span attribute |
| `trace_id` | Log field | — | Span identity |
| `span_id` | Log field | — | Span identity |

### 9.2 Correlation Flow

```
Trace: trace_id=X

  Log: {"trace_id":"X","span_id":"A","event":"process_request","session_id":"S1",...}
  Log: {"trace_id":"X","span_id":"B","event":"harness_process","session_id":"S1",...}
  Log: {"trace_id":"X","span_id":"C","event":"result_submitted","session_id":"S1",...}
  
  Metric: h3_decision_latency_ms{quantile="p95",trace_id="X"} 342
  Metric: h3_error_rate{status_class="2xx",trace_id="X"} 0
```

One `trace_id` links: structured logs (S16) → metrics (S17) → trace spans (S18) → debug queries.

### 9.3 Debugging Workflow

1. **User reports:** "Session S1 decision D42 was slow"
2. **Query metrics** (S17): `h3_decision_latency_ms{session_id="S1"}` → p95=342ms ✓, p99=2100ms ⚠
3. **Query logs** (S16): `jq 'select(.session_id=="S1" and .decision_id=="D42")'` → trace_id=X
4. **Query trace** (S18): `trace_id=X` → waterfall shows 1800ms in harness.process → drill into LLM call span
5. **Root cause:** LLM call took 1750ms. Not an H3 bug — model latency.

---

## 10. Performance Budget

| Operation | Budget | Measurement |
|-----------|--------|-------------|
| `TraceContext` creation | <1µs | `time.monotonic()` before/after |
| `start_span()` | <500ns | Same |
| `end_span()` | <500ns | Same |
| `traceparent_header()` | <200ns | String formatting |
| OTLP serialization | <5ms for 100 spans | Batch serialization |
| gzip compression | <10ms for 100 spans | Batch compression |
| Trace export (async) | 0ms (critical path) | Fire-and-forget |
| Decision loop overhead (traced vs untraced) | <1% | A/B comparison over 1000 decisions |

**Non-negotiable:** Tracing must never add more than 1% overhead to the decision loop latency at p95.

---

## 11. Migration Plan

### Phase 1: Shim Trace Context (Week 1)
- Implement `TraceContext` and `Span` in `shim/src/h3_shim/tracing.py`
- Generate `trace_id` on every decision
- Propagate via `traceparent`/`tracestate` HTTP headers
- In-memory span buffer only (no export yet)
- 0% performance impact (just header propagation)

### Phase 2: SDK Middleware (Week 2)
- Go SDK: `middleware/tracing.go` — extract + create server spans
- Python SDK: `middleware/tracing.py` — same
- TypeScript SDK: `middleware/tracing.ts` — same
- All 3 SDKs emit spans to harness-local collector

### Phase 3: Export (Week 3)
- Shim OTLP exporter (async, batched, gzipped)
- Harness span collection via health endpoint enrichment
- Jaeger backend setup guide
- CLI: `hermes h3 trace` commands

### Phase 4: Production (Week 4)
- Adaptive sampling (error spikes → 100%)
- Tempo backend for production deployments
- Dashboard integration (OBS-05)
- Alerting integration (OBS-06)
- Runbook: "How to debug a slow decision with traces"

---

## 12. Security & Privacy

### 12.1 Data Sensitivity

| Data | In Trace? | Rationale |
|------|-----------|-----------|
| `session_id` | ✅ | Required for correlation |
| `decision_id` | ✅ | Required for correlation |
| `trace_id` | ✅ | Trace identity |
| User messages | ❌ | Never include message content in trace attributes |
| LLM prompts | ❌ | Never include prompt text |
| LLM responses | ❌ | Never include response text |
| API keys | ❌ | Never include in headers or attributes |
| Tool arguments | ❌ | Never include (only tool name) |
| Tool results | ❌ | Never include |

### 12.2 Trace Access Control

Traces contain session metadata but not content. Access control:
- Development: all developers have access
- Staging: ops team + developers on-call
- Production: ops team only; developers can request trace IDs from ops

### 12.3 Trace Deletion

- Retention-based auto-deletion (30 days default)
- Manual deletion via backend's API (Jaeger: `DELETE /api/traces/{traceID}`)
- GDPR compliance: ability to delete all traces for a specific `session_id`

---

## 13. Cross-References

| Spec | Relationship |
|------|-------------|
| S02 (Protocol) | `traceparent`/`tracestate` HTTP headers, optional `trace_context` in ProcessRequest |
| S06 (Hermes Core) | Hermes creates the root span; Shim creates child spans |
| S12 (Security §8) | Auth headers redacted from trace attributes. No secrets in spans. |
| S16 (Logging) | `trace_id` and `span_id` shared between logs and traces |
| S17 (Metrics) | Trace data enriches metrics: per-hop latency breakdown, error attribution |
| S15 (Rate Limiting) | Tracing must work at full rate — sample, don't throttle |

---

## 14. References

- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry OTLP Spec](https://opentelemetry.io/docs/specs/otlp/)
- [Jaeger Deployment](https://www.jaegertracing.io/docs/latest/deployment/)
- [Grafana Tempo](https://grafana.com/docs/tempo/latest/)
- [OTLP Span Data Model](https://opentelemetry.io/docs/specs/otel/trace/api/)
