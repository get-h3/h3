# S17 — H3 Metrics & Performance Monitoring (OBS-02)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S02 (Protocol), S06 (Hermes Core Integration), S16 (Structured Logging)  
**Last Updated:** 2026-07-21

---

## 1. Overview

S16 defines the structured logging format with `trace_id`, `session_id`, and `decision_id` on every log line. That solves the *forensic* problem — when something went wrong, you can trace it. But it does not solve the *proactive* problem — knowing things are going wrong *before* a user reports it.

**This spec defines:** a metrics layer that continuously measures H3's runtime behavior — decision latency, error rate, throughput, harness health — and exposes those measurements for dashboards, alerting, and capacity planning.

**Design principle:** "Measure what matters, expose it simply, and never let metrics collection slow down the critical path." Every metric update must be O(1) and non-blocking. The metrics endpoint must be cheap enough to poll every 5 seconds from a monitoring system without impacting harness performance.

**Scope:** OBS-02 on the task board. Covers metric definitions, collection architecture, exposition format, SDK middleware contracts, CLI surface, and test scenarios. Distributed tracing backend (OBS-03), health check v2 (OBS-04), dashboard (OBS-05), and alerting (OBS-06) are separate specs.

**Implementation targets:**
- `shim/` — Metrics collector engine (`h3/metrics.py`), Prometheus/JSON exposition endpoint
- `sdk-go/` — Metrics middleware: record latency, error count, throughput per harness
- `sdk-python/` — Metrics middleware with same interfaces
- `sdk-typescript/` — Metrics middleware with same interfaces
- `protocol/` — New optional health endpoint field: `/v1/health` response extended with `metrics` object

**Key metric types:**
- **Latency:** p50, p95, p99 decision processing time (ms)
- **Error rate:** 5xx errors / total decisions over 1-minute windows
- **Throughput:** decisions per second (1-min and 5-min moving averages)
- **Harness health:** uptime, last success timestamp, consecutive failures

---

## 2. Metric Architecture

### 2.1 Collection Pipeline

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Hermes     │───▶│    Shim      │───▶│  SDK Middle- │───▶│   Harness    │
│   (native)   │    │  (metrics    │    │    ware      │    │  (custom     │
│              │    │   collector) │    │  (recorder)  │    │   logic)     │
└──────────────┘    └──────┬───────┘    └──────────────┘    └──────────────┘
                           │
                    ┌──────▼───────┐
                    │  Exposition  │
                    │  Endpoint    │
                    │ :9191/metrics│
                    └──────────────┘
```

**Shim collects:** decision latency (time between process request sent and result received), error rate (4xx/5xx responses from harness), throughput (decisions/sec), harness health (consecutive failures, uptime).

**SDK middleware records:** the metrics on the harness side, then the shim collects them from the harness via the health/metrics endpoint. This gives two independent measurement points — shim's measured RTT and harness's self-reported processing time.

### 2.2 Measurement Independence

Each component measures what it directly observes:

| Component | Measures | Method |
|-----------|----------|--------|
| Shim | Round-trip latency (process → result) | `time.monotonic()` before request, after response |
| Shim | Error rate (4xx/5xx from harness) | Counter of HTTP status codes |
| Shim | Throughput (decisions/sec) | Sliding window counter |
| SDK Middleware | Server-side processing time | `time.monotonic()` before handler, after handler |
| SDK Middleware | Error rate (exceptions thrown) | Exception counter per endpoint |
| SDK Middleware | Active sessions | Session registry count |

When shim-measured round-trip ≠ harness self-reported processing time, the delta is network latency + serialization overhead. This difference is itself a useful diagnostic metric.

---

## 3. Metric Definitions

### 3.1 Decision Latency

**Metric family:** `h3_decision_latency_ms`

| Label | Description |
|-------|-------------|
| `quantile` | `p50`, `p95`, `p99` |
| `harness` | Harness name (e.g., `echo`, `consensus`) |
| `decision_type` | `process`, `result`, `end` |

**Collection:** Use a t-digest or DDSketch approximation (O(1) update, configurable accuracy). Exact quantile storage is too expensive at high throughput.

**Reference implementation (Python):**
```python
# Use tdigest for approximate quantiles — O(1) update, O(1) query
from tdigest import TDigest

class LatencyCollector:
    def __init__(self, compression=100):
        self._digest = TDigest()
    
    def record(self, ms: float):
        self._digest.update(ms)
    
    def p50(self) -> float: return self._digest.percentile(50)
    def p95(self) -> float: return self._digest.percentile(95)
    def p99(self) -> float: return self._digest.percentile(99)
```

**Performance budget:** <1ms per record call. <5ms per quantile query.

**Go equivalent:** `github.com/caio/go-tdigest` or `github.com/influxdata/tdigest`.

**TypeScript equivalent:** `tdigest` npm package.

### 3.2 Error Rate

**Metric family:** `h3_error_rate`

| Label | Description |
|-------|-------------|
| `status_class` | `4xx`, `5xx`, `timeout` |
| `harness` | Harness name |
| `endpoint` | `/v1/process`, `/v1/result`, `/v1/health` |

**Collection:** Rolling 1-minute and 5-minute windows. Counter of errors divided by counter of total requests in the same window.

```
error_rate = errors_in_window / max(total_requests_in_window, 1)
```

**Reference implementation:**
```python
import time
from collections import deque

class WindowCounter:
    def __init__(self, window_seconds=60):
        self._window = window_seconds
        self._events = deque()  # (timestamp, count)
    
    def increment(self):
        now = time.monotonic()
        self._events.append((now, 1))
        self._prune(now)
    
    def count(self) -> int:
        self._prune(time.monotonic())
        return sum(c for _, c in self._events)
    
    def _prune(self, now):
        cutoff = now - self._window
        while self._events and self._events[0][0] < cutoff:
            self._events.popleft()
```

### 3.3 Throughput

**Metric family:** `h3_throughput_decisions_per_second`

| Label | Description |
|-------|-------------|
| `window` | `1m`, `5m` |
| `harness` | Harness name |

**Collection:** Simple counter with sliding window. `count / window_seconds`.

### 3.4 Harness Health

**Metric family:** `h3_harness_health`

| Metric | Type | Description |
|--------|------|-------------|
| `h3_harness_up` | Gauge (0/1) | 1 if harness responded to last health check, 0 if not |
| `h3_harness_consecutive_failures` | Gauge | Number of consecutive failed requests |
| `h3_harness_last_success_timestamp` | Gauge (unix epoch) | Last successful response timestamp |
| `h3_harness_uptime_seconds` | Gauge | Seconds since harness first registered healthy |

### 3.5 Active Sessions

**Metric family:** `h3_active_sessions`

| Label | Description |
|-------|-------------|
| `harness` | Harness name |
| `status` | `active`, `idle` (>60s since last decision), `error` |

**Collection:** Count of sessions tracked by the Shim. `idle` threshold: 60 seconds since last `process` or `result` call for that session.

---

## 4. Collection Implementation

### 4.1 Shim Metrics Collector (`h3/metrics.py`)

```python
class H3MetricsCollector:
    """Thread-safe metrics collector for the H3 Shim.
    
    All update methods are O(1) and non-blocking.
    All query methods are O(1) reads (snapshot).
    """

    def __init__(self):
        self._latency = {}       # harness_name -> LatencyCollector
        self._errors = {}        # harness_name -> WindowCounter (60s)
        self._throughput = {}    # harness_name -> WindowCounter (60s)
        self._harness_up = {}    # harness_name -> bool
        self._consec_failures = {} # harness_name -> int
        self._last_success = {}  # harness_name -> float (monotonic timestamp)
        self._active_sessions = {} # harness_name -> Set[session_id]
        self._lock = threading.Lock()
    
    def record_decision_latency(self, harness: str, ms: float, 
                                 decision_type: str = "process"):
        with self._lock:
            if harness not in self._latency:
                self._latency[harness] = LatencyCollector()
            self._latency[harness].record(ms)
            self._throughput.setdefault(harness, WindowCounter(60)).increment()
    
    def record_http_error(self, harness: str, status_code: int):
        with self._lock:
            self._errors.setdefault(harness, WindowCounter(60)).increment()
    
    def record_harness_up(self, harness: str):
        with self._lock:
            self._harness_up[harness] = True
            self._consec_failures[harness] = 0
            self._last_success[harness] = time.time()
    
    def record_harness_down(self, harness: str):
        with self._lock:
            self._harness_up[harness] = False
            self._consec_failures[harness] = \
                self._consec_failures.get(harness, 0) + 1
    
    def snapshot(self) -> dict:
        """Return all current metric values as a dict. Thread-safe."""
        with self._lock:
            return {
                "latency": {
                    h: {"p50": c.p50(), "p95": c.p95(), "p99": c.p99()}
                    for h, c in self._latency.items()
                },
                "error_rate_1m": {
                    h: self._errors.get(h, WindowCounter(60)).count() / 60.0
                    for h in self._errors
                },
                "throughput_1m": {
                    h: self._throughput.get(h, WindowCounter(60)).count() / 60.0
                    for h in self._throughput
                },
                "harness_up": dict(self._harness_up),
                "consecutive_failures": dict(self._consec_failures),
                "last_success_ts": dict(self._last_success),
                "active_sessions": {
                    h: len(s) for h, s in self._active_sessions.items()
                }
            }
```

### 4.2 SDK Middleware Contracts

Each SDK MUST provide middleware that records:

1. **Processing time** for every `/v1/process` call (wall-clock duration of harness handler)
2. **Exception counter** for unhandled exceptions in harness handlers
3. **Active session count** (tracked via session registry)

**Go SDK middleware contract:**
```go
// MetricsMiddleware records request latency and error count.
// Implements the H3MetricsRecorder interface.
type H3MetricsRecorder interface {
    RecordLatency(harness string, decisionType string, ms float64)
    RecordError(harness string, endpoint string)
    SetActiveSessions(harness string, count int)
    Snapshot() H3MetricsSnapshot
}

type H3MetricsSnapshot struct {
    LatencyP50       map[string]float64 `json:"latency_p50"`
    LatencyP95       map[string]float64 `json:"latency_p95"`
    LatencyP99       map[string]float64 `json:"latency_p99"`
    ErrorRate1m      map[string]float64 `json:"error_rate_1m"`
    Throughput1m     map[string]float64 `json:"throughput_1m"`
    ActiveSessions   map[string]int     `json:"active_sessions"`
    HarnessUp        map[string]bool    `json:"harness_up"`
}
```

**Python SDK middleware contract:**
```python
from abc import ABC, abstractmethod
from dataclasses import dataclass, field

@dataclass
class H3MetricsSnapshot:
    latency_p50: dict[str, float] = field(default_factory=dict)
    latency_p95: dict[str, float] = field(default_factory=dict)
    latency_p99: dict[str, float] = field(default_factory=dict)
    error_rate_1m: dict[str, float] = field(default_factory=dict)
    throughput_1m: dict[str, float] = field(default_factory=dict)
    active_sessions: dict[str, int] = field(default_factory=dict)
    harness_up: dict[str, bool] = field(default_factory=dict)

class H3MetricsRecorder(ABC):
    @abstractmethod
    def record_latency(self, harness: str, decision_type: str, ms: float): ...
    @abstractmethod
    def record_error(self, harness: str, endpoint: str): ...
    @abstractmethod
    def set_active_sessions(self, harness: str, count: int): ...
    @abstractmethod
    def snapshot(self) -> H3MetricsSnapshot: ...
```

**TypeScript SDK middleware contract:**
```typescript
interface H3MetricsSnapshot {
  latency_p50: Record<string, number>;
  latency_p95: Record<string, number>;
  latency_p99: Record<string, number>;
  error_rate_1m: Record<string, number>;
  throughput_1m: Record<string, number>;
  active_sessions: Record<string, number>;
  harness_up: Record<string, boolean>;
}

interface H3MetricsRecorder {
  recordLatency(harness: string, decisionType: string, ms: number): void;
  recordError(harness: string, endpoint: string): void;
  setActiveSessions(harness: string, count: number): void;
  snapshot(): H3MetricsSnapshot;
}
```

---

## 5. Exposition Format

### 5.1 JSON Endpoint (`GET /v1/metrics` or `GET /v1/health` extension)

The metrics are exposed as a JSON object, either at a dedicated `/v1/metrics` endpoint or as an extension to the existing `/v1/health` response:

```json
{
  "latency_ms": {
    "echo": {"p50": 12.3, "p95": 28.7, "p99": 45.1},
    "consensus": {"p50": 85.2, "p95": 210.5, "p99": 340.8}
  },
  "error_rate_1m": {
    "echo": 0.0,
    "consensus": 0.02
  },
  "throughput_1m": {
    "echo": 3.2,
    "consensus": 12.8
  },
  "harness_up": {
    "echo": true,
    "consensus": true
  },
  "consecutive_failures": {
    "echo": 0,
    "consensus": 0
  },
  "last_success_timestamp": {
    "echo": 1721583687,
    "consensus": 1721583685
  },
  "active_sessions": {
    "echo": 4,
    "consensus": 23
  }
}
```

### 5.2 Prometheus/OpenMetrics Format (`GET /v1/metrics?format=prometheus`)

For integration with Prometheus, Grafana, and Kubernetes monitoring stacks:

```
# HELP h3_decision_latency_ms_quantile Decision latency in milliseconds
# TYPE h3_decision_latency_ms_quantile gauge
h3_decision_latency_ms_quantile{harness="echo",quantile="p50"} 12.3
h3_decision_latency_ms_quantile{harness="echo",quantile="p95"} 28.7
h3_decision_latency_ms_quantile{harness="echo",quantile="p99"} 45.1

# HELP h3_error_rate Error rate over 1-minute window
# TYPE h3_error_rate gauge
h3_error_rate{harness="echo"} 0.0
h3_error_rate{harness="consensus"} 0.02

# HELP h3_throughput_decisions_per_second Throughput over 1-minute window
# TYPE h3_throughput_decisions_per_second gauge
h3_throughput_decisions_per_second{harness="echo",window="1m"} 3.2
h3_throughput_decisions_per_second{harness="consensus",window="1m"} 12.8

# HELP h3_harness_up Harness health status (1=up, 0=down)
# TYPE h3_harness_up gauge
h3_harness_up{harness="echo"} 1
h3_harness_up{harness="consensus"} 1

# HELP h3_active_sessions Active session count
# TYPE h3_active_sessions gauge
h3_active_sessions{harness="echo"} 4
h3_active_sessions{harness="consensus"} 23
```

**Design decision:** Prometheus format is implemented as a simple string generator, not a full Prometheus client library dependency. The format is well-defined (OpenMetrics spec) and ~30 lines of Python/Go/TS to generate.

---

## 6. CLI Surface

### 6.1 `hermes h3 metrics`

Show current metrics snapshot for all harnesses in a human-readable table:

```
$ hermes h3 metrics

┌──────────┬────────┬────────┬────────┬────────────┬───────────┬──────────────────┐
│ Harness  │ p50    │ p95    │ p99    │ Error Rate │ Throughput│ Active Sessions  │
├──────────┼────────┼────────┼────────┼────────────┼───────────┼──────────────────┤
│ echo     │ 12.3ms │ 28.7ms │ 45.1ms │ 0.00%      │ 3.2/s     │ 4                │
│ consensus│ 85.2ms │210.5ms │340.8ms │ 2.00%      │ 12.8/s    │ 23               │
└──────────┴────────┴────────┴────────┴────────────┴───────────┴──────────────────┘

Harness Health:
  echo       — 🟢 UP (last success: 2s ago, 0 consecutive failures)
  consensus  — 🟢 UP (last success: 4s ago, 0 consecutive failures)
```

**CLI flags:**
- `--json` — Output raw JSON snapshot
- `--harness <name>` — Filter to single harness
- `--watch` — Refresh every 2 seconds (like `htop`)

### 6.2 `hermes h3 metrics reset`

Reset sliding window counters. Useful for benchmarking and load testing.

### 6.3 `hermes h3 test --metrics`

Extend `h3-test` to record per-region metrics:
```
Region 1: Health & Protocol   — 7/7 PASS, 1.2ms avg, 0 errors
Region 2: Process Flows       — 8/8 PASS, 18.5ms avg, 0 errors
Region 3: Decision Types      — 6/6 PASS, 15.3ms avg, 0 errors
...
Total: 43/43 PASS, 12.8ms avg, 0 errors
```

---

## 7. Integration with Health Check

### 7.1 Extended Health Response

Add an optional `metrics` section to the `/v1/health` response (backward-compatible — omitting metrics is valid):

```json
{
  "status": "ok",
  "version": "1.0.0",
  "uptime_seconds": 84600,
  "metrics": {
    "latency_p50_ms": 12.3,
    "latency_p95_ms": 28.7,
    "latency_p99_ms": 45.1,
    "error_rate_1m": 0.0,
    "throughput_1m": 3.2,
    "active_sessions": 4
  }
}
```

The `metrics` object is optional — older harnesses that don't implement metrics still pass health checks. New harnesses add it for richer monitoring.

### 7.2 Protocol Schema Change

Add to `h3-protocol.yaml` the `HealthResponse.properties.metrics` object (optional, all fields optional):

```yaml
HealthResponse:
  type: object
  required: [status, version]
  properties:
    status:
      type: string
    version:
      type: string
    uptime_seconds:
      type: number
    metrics:
      type: object
      properties:
        latency_p50_ms: { type: number }
        latency_p95_ms: { type: number }
        latency_p99_ms: { type: number }
        error_rate_1m: { type: number }
        throughput_1m: { type: number }
        active_sessions: { type: integer }
```

---

## 8. Test Scenarios

### 8.1 Unit Tests (MET-01 through MET-10)

| ID | Test | What It Verifies |
|----|------|-----------------|
| MET-01 | `test_latency_collector_empty` | TDigest returns 0 for all quantiles when no data recorded |
| MET-02 | `test_latency_collector_single_value` | Single recorded value → p50=p95=p99=that value |
| MET-03 | `test_latency_collector_distribution` | Multiple values → quantiles are monotonic (p50 ≤ p95 ≤ p99) |
| MET-04 | `test_window_counter_empty` | Fresh counter returns 0 |
| MET-05 | `test_window_counter_prunes_old_events` | Events outside window are pruned |
| MET-06 | `test_metrics_snapshot_thread_safe` | Concurrent reads/writes don't corrupt snapshot dict |
| MET-07 | `test_record_harness_up_resets_failures` | `record_harness_up` sets consecutive failures to 0 |
| MET-08 | `test_record_harness_down_increments` | Each `record_harness_down` increments failure counter |
| MET-09 | `test_prometheus_format_valid` | Generated Prometheus output passes basic OpenMetrics validation |
| MET-10 | `test_health_endpoint_includes_metrics` | `/v1/health` response includes `metrics` object when middleware is active |

### 8.2 Integration Tests (MET-I-01 through MET-I-06)

| ID | Test | What It Verifies |
|----|------|-----------------|
| MET-I-01 | `test_metrics_across_multiple_decisions` | Run 50 decisions, verify latency quantiles are populated, error rate is 0 |
| MET-I-02 | `test_metrics_with_errors` | Inject harness errors (503), verify error rate > 0 |
| MET-I-03 | `test_metrics_harness_down_detection` | Stop harness, verify `harness_up: false` within health check interval |
| MET-I-04 | `test_metrics_endpoint_accessible` | `GET /v1/metrics` returns 200 with valid JSON |
| MET-I-05 | `test_metrics_prometheus_endpoint` | `GET /v1/metrics?format=prometheus` returns valid OpenMetrics text |
| MET-I-06 | `test_cli_metrics_output` | `hermes h3 metrics --json` returns valid JSON matching snapshot format |

### 8.3 Performance Benchmarks (MET-P-01 through MET-P-03)

| ID | Benchmark | Budget |
|----|-----------|--------|
| MET-P-01 | `bench_latency_record_10k` | <10ms for 10,000 record calls (1µs per call) |
| MET-P-02 | `bench_snapshot_under_load` | <1ms for snapshot() while 1,000 concurrent decisions are in flight |
| MET-P-03 | `bench_window_counter_1m_overflow` | Window counter with 1 million events stays under 50MB memory |

---

## 9. Migration Plan

### Phase 1: Shim Metrics Collector (Week 1)

- Implement `h3/metrics.py` with LatencyCollector, WindowCounter, H3MetricsCollector
- Wire metrics recording into `shim_loop.py`: record latency on each process→result cycle, error on HTTP failures
- Add `GET /v1/metrics` endpoint to shim, both JSON and Prometheus formats
- Add `hermes h3 metrics` CLI command
- Unit tests MET-01 through MET-10

**Verification gate:** `hermes h3 metrics --json` returns valid snapshot with real data from a running harness.

### Phase 2: SDK Middleware (Week 2)

- Add `H3MetricsRecorder` interface to sdk-go, sdk-python, sdk-typescript
- Implement default in-memory collector in each SDK
- Wire middleware into each SDK's HTTP handler stack
- Extend `/v1/health` response with optional `metrics` object
- Integration tests MET-I-01 through MET-I-06

**Verification gate:** Each SDK's echo harness returns `metrics` in health response. Shim can scrape SDK metrics endpoint.

### Phase 3: Protocol Update (Week 2, alongside SDK work)

- Add `metrics` object to `HealthResponse` in `h3-protocol.yaml`
- Add JSON Schema for `MetricsSnapshot` in `schemas/v1/`
- CI validation: protocol change triggers SDK regenerate + test cascade

### Phase 4: Production Rollout (Week 3+)

- Deploy metrics collection to any live H3 instances
- Integrate with Prometheus/Grafana if available
- Set alert thresholds: p99 > 500ms, error rate > 5%, harness up = 0 for >30s
- Monitor overhead: verify <1ms per record call, <1% throughput reduction

---

## 10. Security & Privacy

### 10.1 No Sensitive Data in Metrics

Metrics are aggregate statistics — they never contain:
- API keys, tokens, or credentials
- User message content
- LLM prompt/response text
- Session content beyond count

### 10.2 Access Control

The metrics endpoint follows the same auth model as the rest of H3:
- If S12 auth is enabled, `GET /v1/metrics` requires Bearer token
- Metrics are scoped to the authenticated harness — harness A cannot see harness B's metrics

### 10.3 Rate Limiting

The metrics endpoint counts toward the global rate limit (Tier 1, S15 §2.1) but with a higher default burst allowance (30 req/sec) since monitoring systems poll it frequently.

---

## 11. Performance Budget

| Operation | Budget |
|-----------|--------|
| `record_latency()` | <1µs (O(1), t-digest update) |
| `record_error()` | <1µs (deque append) |
| `snapshot()` | <5ms for 10 harnesses |
| `GET /v1/metrics` | <10ms including JSON serialization |
| Memory per harness | <1KB (t-digest) + <1KB (window counter) |
| Throughput impact | <0.1% on shim loop throughput |

**Design justification:** These budgets are aggressive but achievable. T-digest is designed for high-throughput ingestion (millions of points/sec). Window counter with deque is O(1) amortized. No database, no network calls, no disk I/O in the hot path.

---

## 12. Cross-References

| Spec | Relationship |
|------|-------------|
| S16 (Structured Logging) | Sibling spec — logging tells you *what* happened, metrics tell you *how fast* and *how often*. Same `trace_id`/`session_id` identifiers. |
| S12 (Security & Auth) | Metrics endpoint follows same auth model. Bearer token required if auth is enabled. |
| S15 (Rate Limiting) | Metrics feed into rate limiting decisions — error rate above threshold can trigger rate limit reduction. |
| S02 (Protocol) | Extends `HealthResponse` schema with optional `metrics` object. |

---

## 13. References

- [t-digest paper (Dunning, 2019)](https://arxiv.org/abs/1902.04023) — Data structure for approximate quantiles with O(1) update
- [OpenMetrics Specification](https://github.com/OpenObservability/OpenMetrics) — Prometheus exposition format
- [Prometheus Metric Naming](https://prometheus.io/docs/practices/naming/) — `h3_*` prefix conventions
- [W3C Trace Context](https://www.w3.org/TR/trace-context/) — `trace_id` format used in S16, cross-referenced here for metric-linking
