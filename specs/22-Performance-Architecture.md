# S22 — Performance Architecture & Benchmarks

**Version:** 1.0.0
**Date:** 2026-07-21
**Status:** Complete
**Phase:** PERF (Performance)
**Covers:** PERF-01 through PERF-05
**Cross-references:** S15 (Rate Limiting), S17 (Metrics), S21 (Resilience — RES-04 Backpressure)

---

## 1. Overview

H3 adds a network hop between Hermes and the harness. Performance must be measured, budgeted, and optimized so the protocol overhead is negligible compared to model inference time. This spec defines latency budgets, load testing methodology, memory profiling, gRPC transport, and connection pooling.

### 1.1 Performance Budget Hierarchy

```
┌─────────────────────────────────────────────────────┐
│ TOTAL REQUEST BUDGET: <200ms p95                    │
│                                                     │
│ ┌───────────────────────────────────────────────┐   │
│ │ NETWORK: <5ms (localhost), <20ms (LAN/WAN)    │   │
│ │ ┌─────────────────────────────────────────┐   │   │
│ │ │ SHIM OVERHEAD: <1ms                      │   │   │
│ │ │ ┌───────────────────────────────────┐    │   │   │
│ │ │ │ HARNESS PROCESSING: <50ms p95     │    │   │   │
│ │ │ │ ┌─────────────────────────────┐   │    │   │   │
│ │ │ │ │ RESULT PROCESSING: <100ms   │   │    │   │   │
│ │ │ │ └─────────────────────────────┘   │    │   │   │
│ │ │ └───────────────────────────────────┘    │   │   │
│ │ └─────────────────────────────────────────┘   │   │
│ └───────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### 1.2 Measurement Methodology

All latency measurements use CLOCK_MONOTONIC (Python `time.monotonic()`, Go `time.Now()` via monotonic clock, TypeScript `performance.now()`). Wall-clock time, not CPU time.

---

## 2. PERF-01: Latency Budgets

### 2.1 Targets

| Metric | Target (p95) | Target (p99) | Measurement Point |
|--------|-------------|-------------|-------------------|
| process_end_to_end | <50ms | <100ms | Shim POST /v1/process → response received |
| result_end_to_end | <100ms | <200ms | Shim POST /v1/result → response received |
| health_check | <5ms | <10ms | GET /v1/health |
| shim_overhead | <1ms | <2ms | Internal shim processing (serialize, validate, route) |
| network_rtt | <5ms | <20ms | TCP SYN → SYN-ACK (localhost), extended for LAN/WAN |
| total_turn | <200ms | <400ms | User message → shim → harness → shim → Hermes → result → shim → harness → shim |

### 2.2 Measurement Code

```python
# Shim — latency instrumentation
@dataclass
class TurnLatency:
    turn_number: int
    process_network_ms: float     # HTTP round-trip for /v1/process
    process_harness_ms: float     # harness-reported processing time (from response header)
    result_network_ms: float      # HTTP round-trip for /v1/result
    result_harness_ms: float      # harness-reported result processing time
    shim_serialize_ms: float      # JSON serialization time inside shim
    shim_validate_ms: float       # schema validation time
    total_ms: float               # full turn

    def within_budget(self) -> bool:
        return (
            self.process_network_ms < 50 and
            self.result_network_ms < 100 and
            self.total_ms < 200
        )
```

### 2.3 Harness Response Headers

Harnesses SHOULD include timing headers so the shim can separate network latency from processing time:

```
X-H3-Process-Time-Ms: 12.4
X-H3-Result-Time-Ms: 8.1
```

This allows the shim to compute:
```
network_rtt = total_latency - harness_processing_time
```

### 2.4 Budget Enforcement

| Violation | Action |
|-----------|--------|
| Single p95 exceed | Log warning (S16) |
| 3+ consecutive p95 exceeds | Degrade to L1 (S21 §7) |
| p99 > 10x budget | Circuit breaker consideration (S21 §4) |
| Consistent exceed over 15 min | OBS-06 alert (S20) |

---

## 3. PERF-02: Load Testing

### 3.1 Test Harness (`h3-load`)

A CLI tool that generates synthetic H3 sessions with configurable concurrency and decision rate:

```bash
h3-load \
  --endpoint http://localhost:9191 \
  --concurrency 100 \
  --sessions 50 \
  --decisions-per-session 100 \
  --decision-rate 10/s \
  --duration 5m \
  --ramp-up 30s \
  --output results.json
```

### 3.2 Load Profiles

| Profile | Concurrency | Sessions | Decisions/s | Duration | Purpose |
|---------|------------|----------|-------------|----------|---------|
| Smoke | 10 | 5 | 1/s | 30s | Quick sanity |
| Baseline | 50 | 25 | 5/s | 2m | CI gate |
| Production | 100 | 50 | 10/s | 5m | Pre-release |
| Stress | 500 | 100 | 50/s | 10m | Capacity planning |
| Soak | 50 | 20 | 5/s | 1h | Memory leak detection |

### 3.3 Output Metrics

```json
{
  "profile": "production",
  "duration_s": 300,
  "total_turns": 5000,
  "process": {
    "count": 5000,
    "p50_ms": 18.2,
    "p95_ms": 42.1,
    "p99_ms": 87.3,
    "max_ms": 156.4,
    "errors": 0
  },
  "result": {
    "count": 5000,
    "p50_ms": 22.5,
    "p95_ms": 68.7,
    "p99_ms": 145.2,
    "max_ms": 310.8,
    "errors": 0
  },
  "budget_violations": {
    "process_p95_exceeded": false,
    "result_p95_exceeded": false,
    "total_turns_violated": 12
  },
  "throughput": {
    "decisions_per_second": 16.7,
    "target": 10.0,
    "target_met": true
  }
}
```

### 3.4 CI Integration

```yaml
# .github/workflows/perf.yml
perf-baseline:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Start echo harness
      run: cd examples/echo && go run . &
    - name: Wait for harness
      run: sleep 2 && curl -s http://localhost:9191/v1/health
    - name: Run baseline load test
      run: h3-load --endpoint http://localhost:9191 --profile baseline --fail-on-violation
```

---

## 4. PERF-03: Memory Profiling

### 4.1 Shim Memory Budget

| Component | Steady-State | Peak (100 sessions) | Notes |
|-----------|-------------|---------------------|-------|
| Session store | <10KB/session | <1MB total | Dict of HarnessSession objects |
| Decision queue | <1KB/decision | <10KB total | Capped at 10 (S21 §5) |
| HTTP connection pool | <5KB/connection | <50KB total | 10 pooled connections |
| JSON serialization buffers | <50KB | <100KB | Reusable buffer pool |
| Pydantic model cache | <100KB | <100KB | Compile-once schemas |
| **Total** | **<200KB** | **<2MB** | Well within any container limit |

### 4.2 Profiling Methodology

```bash
# 500-decision stress test with memory sampling
h3-load --endpoint http://localhost:9191 --profile stress --mem-profile=mprof.dat

# Analyze
python -c "
import pickle
with open('mprof.dat', 'rb') as f:
    data = pickle.load(f)
peak_mb = max(s['memory'] for s in data) / (1024*1024)
print(f'Peak memory: {peak_mb:.1f} MB')
"

# Expected: <5MB peak for 500-decision stress test
```

### 4.3 Go/Python/TS SDK Memory Budgets

| SDK | Idle | Per-Session | Notes |
|-----|------|-------------|-------|
| Go SDK | <500KB | <50KB/session | goroutines + channels |
| Python SDK | <2MB | <100KB/session | asyncio event loop overhead |
| TypeScript SDK | <10MB (Node) | <50KB/session | V8 heap baseline |

### 4.4 Memory Leak Detection

The soak test profile (1 hour) includes periodic RSS sampling. A leak is defined as:

```
RSS(t_end) - RSS(t_start) > 2 × (expected_per_session × session_count)
```

If detected, the load test fails with a memory-leak verdict and the OBS-06 alert fires.

---

## 5. PERF-04: gRPC Transport

### 5.1 Rationale

REST/JSON adds serialization overhead (~1-5ms for large decision payloads) and requires a separate HTTP connection for each process/result call. gRPC with protobuf reduces both.

### 5.2 Protobuf Schema

```protobuf
syntax = "proto3";
package h3.v1;

service H3Harness {
  rpc Process(ProcessRequest) returns (ProcessResponse);
  rpc Result(ResultRequest) returns (ResultResponse);
  rpc Health(HealthRequest) returns (HealthResponse);
  rpc StreamDecisions(stream ProcessRequest) returns (stream ProcessResponse);  // bidirectional streaming
}

message ProcessRequest {
  string session_id = 1;
  Message message = 2;
  Identity identity = 3;
  Context context = 4;
  string trace_id = 5;
}

message ProcessResponse {
  Decision decision = 1;
  string trace_id = 2;
  double process_time_ms = 3;
}
// ... (full protobuf schema mirrors JSON Schema from protocol/)
```

### 5.3 Performance Comparison

| Transport | Per-Call Latency (localhost) | Serialization Overhead | Connection Overhead |
|-----------|----------------------------|----------------------|-------------------|
| REST/JSON | ~3-8ms | ~1-3ms (json.dumps/loads) | ~1ms (new HTTP connection or keep-alive) |
| gRPC/Protobuf | ~0.5-2ms | ~0.1ms (protobuf marshal) | ~0ms (multiplexed stream) |
| **Speedup** | **3-5x** | **10-30x** | **N/A** |

### 5.4 Transport Selection

```yaml
# harness.yaml
transport:
  type: grpc                          # rest | grpc | auto
  grpc:
    address: localhost:9192
    use_tls: false                    # localhost only
    max_message_size: 16777216        # 16MB
    keepalive_time: 30                # seconds
    keepalive_timeout: 10             # seconds
    stream_decisions: true            # use bidirectional streaming for decision pipeline
```

### 5.5 Auto-Detection

When `transport.type: auto`, the shim probes both REST and gRPC endpoints on connect and selects the faster one:

```
1. GET /v1/health (REST)     → measure latency
2. gRPC Health/Check         → measure latency
3. Select fastest
4. Fall back to REST if gRPC unavailable
```

### 5.6 Bidirectional Streaming

gRPC's `StreamDecisions` replaces the REST process→result loop with a single persistent stream:

```
Shim                          Harness
  │                              │
  │── stream opened ────────────►│
  │── ProcessRequest(turn=1) ───►│
  │◄── ProcessResponse(turn=1) ──│
  │── ResultRequest(turn=1) ────►│
  │◄── ResultResponse(turn=1) ───│
  │── ProcessRequest(turn=2) ───►│
  │◄── ProcessResponse(turn=2) ──│
  │── ResultRequest(turn=2) ────►│
  │◄── ResultResponse(turn=2) ───│
  │── stream closed ────────────►│
```

Benefits:
- Zero connection establishment per turn
- Single TCP/TLS handshake per session
- Natural backpressure via stream flow control
- Server can push notifications (S19 health updates)

---

## 6. PERF-05: Connection Pooling

### 6.1 REST Connection Pool

```yaml
# harness.yaml
connection_pool:
  max_connections: 10          # max idle connections in pool
  max_connections_per_host: 5  # per harness URL
  keepalive_timeout: 60        # seconds before closing idle connection
  pool_timeout: 5              # seconds to wait for a connection from pool
  retry_on_connection_error: true
  max_retries: 2
```

### 6.2 Implementation

```python
# Python — httpx connection pooling (built-in)
import httpx

class HarnessClient:
    def __init__(self, base_url: str, config: ConnectionPoolConfig):
        limits = httpx.Limits(
            max_connections=config.max_connections,
            max_keepalive_connections=config.max_connections_per_host,
            keepalive_expiry=config.keepalive_timeout,
        )
        timeout = httpx.Timeout(config.pool_timeout)
        transport = httpx.AsyncHTTPTransport(
            limits=limits,
            retries=config.max_retries,
        )
        self.client = httpx.AsyncClient(
            base_url=base_url,
            timeout=timeout,
            transport=transport,
        )
```

```go
// Go — custom http.Transport with pooling
var transport = &http.Transport{
    MaxIdleConns:        10,
    MaxIdleConnsPerHost: 5,
    IdleConnTimeout:     60 * time.Second,
    DisableKeepAlives:   false,
}

var client = &http.Client{
    Transport: transport,
    Timeout:   30 * time.Second,
}
```

```typescript
// TypeScript — undici connection pool
import { Pool } from 'undici';

const pool = new Pool(baseUrl, {
  connections: 10,
  pipelining: 1,
  keepAliveTimeout: 60000,
  keepAliveMaxTimeout: 60000,
});
```

### 6.3 Pool Health Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|----------------|
| pool_available | Idle connections available | <2 → pool under pressure |
| pool_active | Connections in use | >8 → near max |
| pool_wait_ms | Time waiting for a connection | >100ms → pool contention |
| connection_errors | Failed connection attempts | >0 → harness connectivity issue |

These feed into S17 metrics and S20 dashboard.

---

## 7. Performance Test Plan

### 7.1 Unit Benchmarks (PERF-B-01 through PERF-B-10)

| ID | Benchmark | Target |
|----|-----------|--------|
| PERF-B-01 | Shim JSON serialize 1KB ProcessRequest | <100µs |
| PERF-B-02 | Shim JSON deserialize 1KB ProcessResponse | <200µs |
| PERF-B-03 | Shim JSON validate (Pydantic model validation) | <500µs |
| PERF-B-04 | Go SDK JSON marshal ProcessRequest | <50µs |
| PERF-B-05 | Python SDK JSON dump ProcessRequest | <150µs |
| PERF-B-06 | TypeScript SDK JSON stringify ProcessRequest | <100µs |
| PERF-B-07 | gRPC protobuf marshal ProcessRequest | <10µs |
| PERF-B-08 | gRPC protobuf unmarshal ProcessResponse | <15µs |
| PERF-B-09 | Connection pool acquire/release cycle | <50µs |
| PERF-B-10 | HTTP keep-alive round-trip (localhost, empty body) | <1ms |

### 7.2 Integration Benchmarks (PERF-I-01 through PERF-I-06)

| ID | Benchmark | Target |
|----|-----------|--------|
| PERF-I-01 | Echo harness: 100 turns, single session, REST | <5s total, <50ms/turn |
| PERF-I-02 | Echo harness: 100 turns, single session, gRPC | <2s total, <20ms/turn |
| PERF-I-03 | Load test: 100 concurrent sessions, 10 decisions/s each, 60s | Zero budget violations |
| PERF-I-04 | Memory: 500 decisions, REST, measure peak RSS | <5MB peak |
| PERF-I-05 | Memory: 500 decisions, gRPC, measure peak RSS | <3MB peak |
| PERF-I-06 | Connection pool: 1000 consecutive requests, verify reuse | <5ms p50 per request |

### 7.3 CI Gate

All unit benchmarks (PERF-B-01 through PERF-B-10) run in CI as a performance gate. Integration benchmarks (PERF-I-01 through PERF-I-06) run on PR to main as a pre-merge gate.

---

## 8. SDK Middleware Contracts

### 8.1 Go SDK

```go
// PerfConfig holds performance tuning parameters
type PerfConfig struct {
    LatencyBudget    LatencyBudget     // process/result p95 targets
    ConnectionPool   ConnectionPoolConfig
    Transport        TransportType     // rest, grpc, auto
    GRPCConfig       *GRPCConfig       // nil if not using gRPC
}

// LatencyMetrics is returned after each turn
type LatencyMetrics struct {
    ProcessNetworkMs  float64
    ProcessHarnessMs  float64
    ResultNetworkMs   float64
    ResultHarnessMs   float64
    SerializeMs       float64
    ValidateMs        float64
    TotalMs           float64
}
```

### 8.2 Python SDK

```python
@dataclass
class PerfConfig:
    latency_budget: LatencyBudget
    connection_pool: ConnectionPoolConfig
    transport: TransportType = TransportType.AUTO
    grpc_config: Optional[GRPCConfig] = None

@dataclass
class LatencyMetrics:
    process_network_ms: float
    process_harness_ms: float
    result_network_ms: float
    result_harness_ms: float
    serialize_ms: float
    validate_ms: float
    total_ms: float
```

### 8.3 TypeScript SDK

```typescript
interface PerfConfig {
  latencyBudget: LatencyBudget;
  connectionPool: ConnectionPoolConfig;
  transport: TransportType;
  grpcConfig?: GRPCConfig;
}

interface LatencyMetrics {
  processNetworkMs: number;
  processHarnessMs: number;
  resultNetworkMs: number;
  resultHarnessMs: number;
  serializeMs: number;
  validateMs: number;
  totalMs: number;
}
```

---

## 9. CLI Surface

```bash
# Load testing
hermes h3 load-test --endpoint URL [--profile baseline|production|stress|soak] [--output FILE.json]

# Latency check
hermes h3 perf check [--harness HARNESS_ID] [--turns 100]
# Output: p50/p95/p99 for process, result, total. PASS/FAIL against budget.

# Benchmark
hermes h3 bench [--transport rest|grpc] [--iterations 1000]

# Transport info
hermes h3 transport show [--harness HARNESS_ID]
hermes h3 transport switch --harness HARNESS_ID --to grpc|rest
```

---

## 10. Migration & Implementation Plan

| Phase | What | Dependencies | Timeline |
|-------|------|-------------|----------|
| 1 | PERF-01: Latency instrumentation (S16/S17 integration) | S16, S17 | First — measure before optimizing |
| 2 | PERF-02: Load testing CLI (`h3-load`) | PERF-01 | Second — needs latency metrics |
| 3 | PERF-03: Memory profiling | PERF-02 | Third — run under load |
| 4 | PERF-05: Connection pooling | None (infrastructure) | Parallel to 1-3 |
| 5 | PERF-04: gRPC transport + protobuf | None (new transport) | Fourth — after REST baseline |

---

## 11. Cross-Reference Integration

| Related Spec | Integration Point |
|-------------|-------------------|
| S15 (Rate Limiting) | Throughput metrics feed into rate limiter. Load test validates rate limit behavior. |
| S17 (Metrics) | All latency measurements export to Prometheus/JSON metrics endpoint. |
| S20 (Dashboard) | Performance gauges on dashboard: p95 latency, throughput, budget violations. |
| S21 (Resilience) | Latency spikes trigger degradation (L1 at p95>1s). Memory pressure triggers backpressure. |
| S19 (Health) | Heath v2 reports transport type, connection pool status, gRPC availability. |
