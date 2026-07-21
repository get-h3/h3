# S19 — H3 Health Check v2 (OBS-04)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S02 (Protocol), S06 (Hermes Core Integration), S17 (Metrics), S18 (Tracing)  
**Last Updated:** 2026-07-21

---

## 1. Overview

S02 defines the baseline `GET /v1/health` endpoint — it returns `status`, `version`, `protocol_version`, `uptime_seconds`, `active_sessions`, and a flat `capabilities` array. This is sufficient for basic monitoring but too coarse for production operations.

**This spec defines Health Check v2** — a richer diagnostic endpoint that tells operators not just "is it up?" but "what can it do, what does it depend on, and how healthy is each component?"

**Design principle:** "A health check is a contract between the harness and the platform. v1 proves the harness is alive. v2 proves the harness is capable and its dependencies are intact."

**What v2 adds over v1:**

| Field | v1 | v2 |
|---|---|---|
| `capabilities` | Flat array of string tokens | Structured object with metadata per capability |
| Models | Not reported | Full model list with availability, cost, context window |
| Version | Simple string | Semantic + build metadata, changelog URL |
| Uptime | Seconds since start | Seconds + start timestamp + restart count |
| Dependencies | Not reported | Backend health (LLM provider, DB, cache) with latency |
| Config hash | Not reported | Checksum of harness config for drift detection |
| Resource usage | Not reported | CPU %, memory MB, goroutine/thread count |
| Recent errors | Not reported | Last N errors with timestamps for fast triage |

**Scope:** OBS-04 on the task board. Covers the extended health response schema, all 8 new field groups, SDK middleware contracts (Go/Python/TypeScript), CLI surface (`hermes h3 health`), compatibility with existing h3-test battery, and a staged rollout plan. Health check v2 extends — never replaces — `/v1/health`.

**Implementation targets:**
- `shim/` — `h3/client.py`: parse v2 health, fall back to v1. `h3/shim_loop.py`: health-based routing decisions.
- `sdk-go/` — Health v2 middleware: collect model list, dependency status, resource usage.
- `sdk-python/` — Health v2 middleware with same interfaces.
- `sdk-typescript/` — Health v2 middleware with same interfaces.
- `protocol/` — New optional health endpoint response schema. Backward-compatible with v1.

---

## 2. Endpoint: `GET /v1/health` (Extended)

### Request (unchanged)

```
GET /v1/health
```

### Response — v2 Harness (200 OK)

```json
{
  "status": "ok",
  "version": "2.1.0",
  "build": {
    "commit": "abc1234",
    "timestamp": "2026-07-21T14:30:00Z",
    "go_version": "go1.23.4",
    "changelog_url": "https://github.com/get-h3/sdk-go/releases/tag/v2.1.0"
  },
  "transport": "rest",
  "protocol_version": "1.1",
  "uptime_seconds": 84320,
  "uptime_since": "2026-07-20T15:14:40Z",
  "restart_count": 0,
  "active_sessions": 7,
  "capabilities": {
    "decisions": ["tool_call", "llm_call", "text", "wait", "delegate", "end"],
    "transports": ["rest"],
    "auth": ["bearer_token", "mtls"],
    "tracing": ["w3c_trace_context"],
    "rate_limiting": ["token_bucket"]
  },
  "models": [
    {
      "id": "deepseek-v4-flash",
      "provider": "deepseek",
      "status": "available",
      "context_window": 1048576,
      "max_output_tokens": 8192,
      "cost_per_1k_input": 0.00014,
      "cost_per_1k_output": 0.00028,
      "supports_vision": false,
      "supports_tools": true,
      "latency_ms_p50": 120,
      "latency_ms_p95": 350,
      "error_rate_1h": 0.001
    },
    {
      "id": "deepseek-v4-pro",
      "provider": "deepseek",
      "status": "available",
      "context_window": 1048576,
      "max_output_tokens": 32768,
      "cost_per_1k_input": 0.00055,
      "cost_per_1k_output": 0.00220,
      "supports_vision": false,
      "supports_tools": true,
      "latency_ms_p50": 250,
      "latency_ms_p95": 800,
      "error_rate_1h": 0.000
    },
    {
      "id": "gpt-5.6-sol",
      "provider": "openai",
      "status": "degraded",
      "degraded_reason": "Elevated latency — p95 at 2400ms (threshold: 1000ms)",
      "context_window": 262144,
      "max_output_tokens": 16384,
      "cost_per_1k_input": 0.00375,
      "cost_per_1k_output": 0.01500,
      "supports_vision": true,
      "supports_tools": true,
      "latency_ms_p50": 350,
      "latency_ms_p95": 2400,
      "error_rate_1h": 0.005
    }
  ],
  "dependencies": {
    "llm_provider": {
      "status": "healthy",
      "latency_ms": 45,
      "last_checked": "2026-07-21T14:30:00Z",
      "endpoint": "https://api.deepseek.com/v1",
      "error_rate_1h": 0.0
    },
    "database": {
      "status": "healthy",
      "latency_ms": 2,
      "last_checked": "2026-07-21T14:29:55Z",
      "type": "sqlite3",
      "size_bytes": 10485760
    },
    "cache": {
      "status": "healthy",
      "latency_ms": 1,
      "last_checked": "2026-07-21T14:29:58Z",
      "type": "redis",
      "hit_rate_1h": 0.94
    }
  },
  "config": {
    "hash": "sha256:abc123def456",
    "last_reloaded": "2026-07-21T12:00:00Z",
    "reload_count": 3
  },
  "resources": {
    "cpu_percent": 12.5,
    "memory_mb": 145.3,
    "memory_limit_mb": 512,
    "goroutines": 34,
    "open_file_descriptors": 28,
    "max_file_descriptors": 1024,
    "gc_pause_ms_p95": 1.2
  },
  "recent_errors": [
    {
      "timestamp": "2026-07-21T14:29:30Z",
      "decision_id": "d_abc123",
      "session_id": "s_xyz789",
      "error_type": "llm_timeout",
      "message": "DeepSeek API timeout after 30s",
      "retryable": true
    }
  ],
  "components": {
    "harness_loop": "healthy",
    "decision_executor": "healthy",
    "session_manager": "healthy",
    "auth_validator": "healthy",
    "metrics_collector": "healthy",
    "trace_exporter": "degraded",
    "trace_exporter_reason": "OTLP collector unreachable — buffering spans locally"
  }
}
```

### Response — v1 Harness (200 OK, backward-compatible)

v1 harnesses return the original format defined in S02. The shim detects the absence of the `capabilities` key as an object (v2) vs array (v1) and handles both:

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

### Response — Degraded (200 OK)

The harness is operational but one or more components have reduced functionality:

```json
{
  "status": "degraded",
  "version": "2.1.0",
  "transport": "rest",
  "protocol_version": "1.1",
  "degraded_reason": "LLM provider degraded (p95 latency 2400ms), Trace exporter unreachable",
  "degraded_components": ["llm_provider", "trace_exporter"],
  "capabilities": {
    "decisions": ["tool_call", "llm_call", "text", "wait", "delegate", "end"],
    "transports": ["rest"],
    "auth": ["bearer_token"],
    "tracing": ["w3c_trace_context"],
    "rate_limiting": ["token_bucket"]
  },
  "models": [...],
  "dependencies": {...},
  "resources": {...}
}
```

### Response — Down (503 Service Unavailable)

```json
{
  "status": "down",
  "version": "2.1.0",
  "error": "Database connection lost",
  "error_code": "DB_UNREACHABLE",
  "error_since": "2026-07-21T14:25:00Z",
  "dependencies": {
    "database": {
      "status": "down",
      "latency_ms": null,
      "last_checked": "2026-07-21T14:25:00Z",
      "error": "connection refused"
    }
  }
}
```

---

## 3. Field Specifications

### 3.1 `status`

| Value | Meaning | HTTP Status | Hermes Action |
|---|---|---|---|
| `ok` | All components healthy | 200 | Route sessions to harness |
| `degraded` | ≥1 component impaired but harness functional | 200 | Route sessions with lower priority |
| `down` | Harness non-functional | 503 | Do not route — fall back to native |

The `degraded` status is new in v2. v1 only had `ok` and `down`. v1 harnesses will never return `degraded`.

**Decision matrix for routing:**

| Harness Status | Native Available? | Route? |
|---|---|---|
| `ok` | — | ✅ Route to harness |
| `degraded` | Yes | ✅ Route to harness (lower priority) |
| `degraded` | No | ✅ Route to harness (only option) |
| `down` | Yes | ❌ Fall back to native |
| `down` | No | ⚠️ Fail with graceful error |

### 3.2 `capabilities` (v2 Structured)

The v1 `capabilities` field is a flat string array. v2 replaces it with a structured object where each key is a capability category and the value is an array of supported values.

**Category definition:**

| Key | Values | Required? |
|---|---|---|
| `decisions` | `tool_call`, `llm_call`, `text`, `wait`, `delegate`, `end`, `stream` | Required |
| `transports` | `rest`, `grpc`, `websocket` | Required |
| `auth` | `none`, `bearer_token`, `mtls`, `hmac` | Required |
| `tracing` | `none`, `w3c_trace_context`, `b3`, `jaeger` | Optional |
| `rate_limiting` | `none`, `token_bucket`, `sliding_window`, `leaky_bucket` | Optional |
| `streaming` | `none`, `sse`, `chunked_transfer`, `websocket_stream` | Optional |

**Backward compatibility:** When the shim receives a v1 response (`capabilities` is an array), it wraps it: `{"decisions": <array>}`. A v2 harness communicating with a v1 shim (which ignores the structured format) loses no functionality — the `decisions` key is the only one the v1 shim reads.

### 3.3 `models` (NEW)

Array of model descriptors. Each entry:

| Field | Type | Description |
|---|---|---|
| `id` | string | Canonical model ID (e.g., `deepseek-v4-flash`) |
| `provider` | string | Provider backend (e.g., `deepseek`, `openai`, `anthropic`) |
| `status` | enum(`available`, `degraded`, `unavailable`) | Current availability |
| `degraded_reason` | string (optional) | Present when status is `degraded` |
| `context_window` | integer | Max input tokens |
| `max_output_tokens` | integer | Max output tokens per request |
| `cost_per_1k_input` | float | USD per 1000 input tokens |
| `cost_per_1k_output` | float | USD per 1000 output tokens |
| `supports_vision` | boolean | Can process image inputs |
| `supports_tools` | boolean | Can use function/tool calling |
| `latency_ms_p50` | float | 50th percentile decision latency (last hour) |
| `latency_ms_p95` | float | 95th percentile decision latency (last hour) |
| `error_rate_1h` | float | Error ratio over last hour (0.0–1.0) |

**Purpose:** The model list enables:
- **Dashboard display:** operators see available models at a glance
- **Cost estimation:** per-model pricing for session budgeting (S15 §7)
- **Auto-selection:** Hermes can route tasks to harnesses based on model availability
- **Degradation detection:** `error_rate_1h > 0.05` triggers alert (OBS-06)

**SDK responsibility:** Each SDK provides a `RegisterModel(...)` function. Harness authors call it during initialization for each configured model. The health endpoint aggregates all registered models automatically.

### 3.4 `dependencies` (NEW)

Object mapping dependency names to their health status:

| Field | Type | Description |
|---|---|---|
| `<name>.status` | enum(`healthy`, `degraded`, `down`, `unknown`) | Component health |
| `<name>.latency_ms` | float or null | Last health check latency |
| `<name>.last_checked` | ISO 8601 timestamp | When this check was performed |
| `<name>.type` | string | Component type (e.g., `sqlite3`, `redis`, `http`) |
| `<name>.error` | string (optional) | Error message when down/degraded |
| `<name>.error_rate_1h` | float (optional) | Error rate over last hour |

**Standard dependency keys:**

| Key | When to report | Required? |
|---|---|---|
| `llm_provider` | Always — harness always talks to an LLM | Required |
| `database` | If harness has persistent storage | Optional |
| `cache` | If harness uses caching | Optional |
| `vector_store` | If harness uses embeddings/RAG | Optional |
| `message_queue` | If harness has async processing | Optional |
| `external_api_<name>` | Per external API dependency | Optional |

**SDK responsibility:** Each SDK provides a `RegisterDependency(name, checkFn)` function. The health endpoint calls each check function (with a 2-second timeout per check) and aggregates results.

### 3.5 `config` (NEW)

Configuration integrity metadata:

| Field | Type | Description |
|---|---|---|
| `hash` | string | SHA-256 of the loaded config (format: `sha256:<hex>`) |
| `last_reloaded` | ISO 8601 timestamp or null | Last hot-reload timestamp |
| `reload_count` | integer | Number of times config has been reloaded |

**Purpose:** Config hash enables drift detection — if the hash changes without a corresponding deploy, someone edited config by hand. Hot-reload metadata (from S11 §4) shows whether the harness supports live config updates.

### 3.6 `resources` (NEW)

Runtime resource utilization:

| Field | Type | Description |
|---|---|---|
| `cpu_percent` | float | Process CPU usage (0–100 × cores) |
| `memory_mb` | float | Resident set size in MB |
| `memory_limit_mb` | float or null | Memory limit (null if unlimited) |
| `goroutines` (Go) / `threads` (Python/TS) | integer | Active goroutines/threads |
| `open_file_descriptors` | integer | Currently open FDs |
| `max_file_descriptors` | integer | FD limit (ulimit -n) |
| `gc_pause_ms_p95` | float | 95th percentile GC pause (Go/TS) or null (Python) |

**Purpose:** Resource data enables:
- **Anomaly detection:** `goroutines > 1000` → possible goroutine leak
- **Capacity planning:** `memory_mb` trending toward `memory_limit_mb` → needs scaling
- **Correlation:** latency spike + GC pause spike → GC tuning needed

**Performance:** Resource collection must be non-blocking and cached for 5 seconds. No system call on every health poll.

### 3.7 `recent_errors` (NEW)

Last N errors for rapid triage (default: 5, configurable):

| Field | Type | Description |
|---|---|---|
| `timestamp` | ISO 8601 | When the error occurred |
| `decision_id` | string or null | Associated decision (null for infra errors) |
| `session_id` | string or null | Associated session |
| `error_type` | string | Error category (e.g., `llm_timeout`, `auth_failure`, `db_error`) |
| `message` | string | Error message (sanitized — no API keys, no PII) |
| `retryable` | boolean | Can the operation be retried |

**Security:** Error messages must be sanitized. API keys, tokens, user content, and PII must be redacted before inclusion. The SDK provides a `RecordError(err, decision_id, session_id)` function that applies sanitization.

### 3.8 `components` (NEW)

Per-component health status with reasons:

| Field | Type | Description |
|---|---|---|
| `<name>` | enum(`healthy`, `degraded`, `down`, `unknown`) | Component status |
| `<name>_reason` | string (optional) | Present when status is not `healthy` |

**Standard component keys:**

| Key | Component | When degraded/down |
|---|---|---|
| `harness_loop` | Main processing loop | Loop stalled, panic recovered |
| `decision_executor` | Decision execution | Decision type unsupported, tool crash |
| `session_manager` | Session lifecycle | DB error, memory pressure |
| `auth_validator` | Auth validation (S12) | Key validation failure, cert expired |
| `metrics_collector` | Metrics aggregation (S17) | Buffer full, exposition failure |
| `trace_exporter` | Trace export (S18) | OTLP collector unreachable |

---

## 4. SDK Middleware Contracts

### 4.1 Go SDK (`sdk-go/pkg/health`)

```go
// HealthV2 represents the full v2 health response.
type HealthV2 struct {
    Status           string                 `json:"status"`
    Version          string                 `json:"version"`
    Build            BuildInfo              `json:"build"`
    Transport        string                 `json:"transport"`
    ProtocolVersion  string                 `json:"protocol_version"`
    UptimeSeconds    int64                  `json:"uptime_seconds"`
    UptimeSince      time.Time              `json:"uptime_since"`
    RestartCount     int                    `json:"restart_count"`
    ActiveSessions   int                    `json:"active_sessions"`
    Capabilities     CapabilitiesV2         `json:"capabilities"`
    Models           []ModelInfo            `json:"models"`
    Dependencies     map[string]DepStatus   `json:"dependencies"`
    Config           ConfigInfo             `json:"config"`
    Resources        ResourceInfo           `json:"resources"`
    RecentErrors     []ErrorRecord          `json:"recent_errors"`
    Components       map[string]string      `json:"components"`

    // Degraded/Down fields
    DegradedReason    string   `json:"degraded_reason,omitempty"`
    DegradedComponents []string `json:"degraded_components,omitempty"`
    Error             string   `json:"error,omitempty"`
    ErrorCode         string   `json:"error_code,omitempty"`
    ErrorSince        *time.Time `json:"error_since,omitempty"`
}

// HealthChecker is the interface harnesses implement.
type HealthChecker interface {
    // CheckHealth returns the full v2 health status.
    CheckHealth(ctx context.Context) *HealthV2
}

// HealthRegistry collects health data from registered providers.
type HealthRegistry struct {
    startTime       time.Time
    restartCount    int
    models          []ModelInfo
    deps            map[string]DependencyChecker
    errors          *ErrorRingBuffer
    components      map[string]ComponentHealth
}

func NewHealthRegistry(version, commit, goVersion string) *HealthRegistry
func (r *HealthRegistry) RegisterModel(info ModelInfo)
func (r *HealthRegistry) RegisterDependency(name string, checker DependencyChecker)
func (r *HealthRegistry) RegisterComponent(name string, checker ComponentChecker)
func (r *HealthRegistry) RecordError(err error, decisionID, sessionID string)
func (r *HealthRegistry) SetActiveSessions(n int)
func (r *HealthRegistry) CollectResources() ResourceInfo
func (r *HealthRegistry) BuildHealth(ctx context.Context) *HealthV2
```

### 4.2 Python SDK (`sdk-python/src/h3_harness/health.py`)

```python
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, Callable, Awaitable

@dataclass
class HealthV2:
    status: str
    version: str
    build: "BuildInfo"
    transport: str = "rest"
    protocol_version: str = "1.1"
    uptime_seconds: int = 0
    uptime_since: Optional[datetime] = None
    restart_count: int = 0
    active_sessions: int = 0
    capabilities: "CapabilitiesV2" = field(default_factory=CapabilitiesV2)
    models: list["ModelInfo"] = field(default_factory=list)
    dependencies: dict[str, "DepStatus"] = field(default_factory=dict)
    config: Optional["ConfigInfo"] = None
    resources: Optional["ResourceInfo"] = None
    recent_errors: list["ErrorRecord"] = field(default_factory=list)
    components: dict[str, str] = field(default_factory=dict)
    degraded_reason: Optional[str] = None
    degraded_components: list[str] = field(default_factory=list)
    error: Optional[str] = None
    error_code: Optional[str] = None
    error_since: Optional[datetime] = None


class HealthRegistry:
    """Collects health data from registered providers."""

    def __init__(self, version: str, commit: str, python_version: str): ...
    def register_model(self, info: ModelInfo) -> None: ...
    def register_dependency(self, name: str, checker: Callable[[], Awaitable[DepStatus]]) -> None: ...
    def register_component(self, name: str, checker: Callable[[], str]) -> None: ...
    def record_error(self, err: Exception, decision_id: str | None, session_id: str | None) -> None: ...
    def set_active_sessions(self, n: int) -> None: ...
    def collect_resources(self) -> ResourceInfo: ...
    async def build_health(self) -> HealthV2: ...
```

### 4.3 TypeScript SDK (`sdk-typescript/src/health.ts`)

```typescript
interface HealthV2 {
  status: "ok" | "degraded" | "down";
  version: string;
  build: BuildInfo;
  transport: string;
  protocol_version: string;
  uptime_seconds: number;
  uptime_since: string | null;
  restart_count: number;
  active_sessions: number;
  capabilities: CapabilitiesV2;
  models: ModelInfo[];
  dependencies: Record<string, DepStatus>;
  config?: ConfigInfo;
  resources?: ResourceInfo;
  recent_errors: ErrorRecord[];
  components: Record<string, string>;
  degraded_reason?: string;
  degraded_components?: string[];
  error?: string;
  error_code?: string;
  error_since?: string;
}

class HealthRegistry {
  constructor(version: string, commit: string, runtimeVersion: string);
  registerModel(info: ModelInfo): void;
  registerDependency(name: string, checker: () => Promise<DepStatus>): void;
  registerComponent(name: string, checker: () => string): void;
  recordError(err: Error, decisionId?: string, sessionId?: string): void;
  setActiveSessions(n: number): void;
  collectResources(): ResourceInfo;
  async buildHealth(): Promise<HealthV2>;
}
```

---

## 5. CLI Surface: `hermes h3 health`

```bash
# Basic health check
hermes h3 health --endpoint http://localhost:9191
# Output: ok (v2.1.0, protocol 1.1, 7 sessions, 3 models)
# Degraded: degraded (LLM provider p95 2400ms, trace exporter unreachable)

# Verbose: full table
hermes h3 health --endpoint http://localhost:9191 --verbose
# Output:
#   Status:            ok
#   Version:           2.1.0 (commit abc1234)
#   Protocol:          1.1
#   Uptime:            23h 25m (since 2026-07-20 15:14, 0 restarts)
#   Sessions:          7 active
#   Capabilities:      decisions: 7 types, transports: rest, auth: bearer+mtls
#   Models:            3 registered (2 available, 1 degraded)
#   Components:        5/6 healthy (trace_exporter degraded)
#   Resources:         CPU 12.5%, Memory 145MB/512MB, 34 goroutines
#   Config:            sha256:abc123 (reloaded 3 times)

# JSON output
hermes h3 health --endpoint http://localhost:9191 --json
# Full HealthV2 JSON

# Watch mode (polling)
hermes h3 health --endpoint http://localhost:9191 --watch 5
# Polls every 5 seconds, shows delta changes

# Model list only
hermes h3 health --endpoint http://localhost:9191 --models
# Table: ID | Provider | Status | Latency p95 | Error Rate | Cost/1K

# Dependency check
hermes h3 health --endpoint http://localhost:9191 --deps
# Table: Name | Status | Latency | Last Checked | Error
```

---

## 6. Test Scenarios

### HEALTH-01 through HEALTH-10: Unit Tests (SDK)

| ID | Test | SDK |
|---|---|---|
| HEALTH-01 | `build_health_ok` — All components healthy, 3 models, 4 deps → `status: ok` | All 3 |
| HEALTH-02 | `build_health_degraded` — 1 model degraded, 1 dep degraded → `status: degraded`, `degraded_reason` populated | All 3 |
| HEALTH-03 | `build_health_down` — Database dependency down → `status: down`, HTTP 503, `error_code: DB_UNREACHABLE` | All 3 |
| HEALTH-04 | `v1_capabilities_compat` — Capabilities as array (v1 format) → parsed as `{decisions: [...]}` | All 3 |
| HEALTH-05 | `model_latency_percentiles` — Record 1000 decisions → p50/p95 within ±5% of expected | All 3 |
| HEALTH-06 | `error_ring_buffer` — Record 10 errors → `recent_errors` contains last 5 (default cap) | All 3 |
| HEALTH-07 | `config_hash_mismatch` — Reload config → `config.hash` changes, `reload_count` increments | All 3 |
| HEALTH-08 | `resource_collection` — `collect_resources()` returns valid CPU %, memory, goroutines/threads | All 3 |
| HEALTH-09 | `dep_check_timeout` — Dependency checker hangs → 2s timeout → status `unknown` | All 3 |
| HEALTH-10 | `error_sanitization` — Error message contains API key `sk-abc123` → redacted to `sk-***` | All 3 |

### HEALTH-I-01 through HEALTH-I-06: Integration Tests

| ID | Test | Description |
|---|---|---|
| HEALTH-I-01 | `full_v2_response` | Start harness → `curl /v1/health` → validate all 8 field groups present |
| HEALTH-I-02 | `v1_client_v2_harness` | Client expecting v1 format → harness returns v2 → client falls back to v1 parsing |
| HEALTH-I-03 | `v2_client_v1_harness` | Client expecting v2 format → harness returns v1 → client wraps `capabilities` array |
| HEALTH-I-04 | `degraded_routing` | Harness reports degraded → shim routes with lower priority → session still completes |
| HEALTH-I-05 | `down_routing` | Harness reports down → shim does NOT route → falls back to native (if available) |
| HEALTH-I-06 | `model_list_sync` | Register 3 models → remove 1 → health check reflects 2 models |

### HEALTH-P-01 through HEALTH-P-03: Performance Tests

| ID | Test | Description |
|---|---|---|
| HEALTH-P-01 | `health_latency_budget` | `/v1/health` responds in <5ms p95 with all 8 field groups populated |
| HEALTH-P-02 | `health_under_load` | 100 concurrent sessions → health check still responds in <10ms p95 |
| HEALTH-P-03 | `dep_check_parallel` | 5 dependencies (each 500ms) → total health check <600ms (parallel execution) |

---

## 7. Migration Plan

### Phase 1: Protocol Spec Update (protocol repo)

- Add v2 health response schema to `h3-protocol.yaml` under a new `HealthV2` schema
- Keep existing `Health` schema (v1) unchanged
- `protocol_version: "1.1"` harnesses return `HealthV2`; v1.0 harnesses return `Health`

### Phase 2: SDK Middleware (sdk-go, sdk-python, sdk-typescript)

- Implement `HealthRegistry` in each SDK (per §4 middleware contracts)
- Add `RegisterModel`, `RegisterDependency`, `RegisterComponent`, `RecordError` API surface
- Existing harnesses (no registrations) → health check returns v1 format (backward-compatible)
- Register at least 1 model → health check automatically upgrades to v2 format
- Write HEALTH-01 through HEALTH-10 unit tests

### Phase 3: Shim Client (shim repo)

- Update `H3Client.health()` to detect v1 vs v2 response format
- Detection: `capabilities` is object → v2; array → v1
- Update `H3Loader.health_check()` to log degraded components
- Update routing logic: `degraded` → lower priority, `down` → fall back to native
- Write HEALTH-I-01 through HEALTH-I-06 integration tests
- Add `hermes h3 health` CLI commands

### Phase 4: h3-test Battery

- `health_v2_format` (new test): GET /v1/health → verify structured capabilities object
- `health_v2_models` (new test): GET /v1/health → models array present with required fields
- `health_v2_degraded` (new test): Degrade a dependency → health returns `degraded` status
- Existing 7 health tests (1.1–1.7 from S05) continue to pass against both v1 and v2

### Phase 5: Production Rollout

- Deploy v2 SDKs to all example harnesses (echo, minimal, conformance)
- Monitor health endpoint latency — must stay under 5ms
- Enable `degraded` routing in Hermes shim (config flag, default: off)
- After 1 week of stable degraded→native fallback: enable by default

---

## 8. Backward Compatibility

**v1 harnesses are first-class.** The shim handles both formats transparently:

| Harness Version | Shim Detection | Capabilities | Models | Dependencies | Resources |
|---|---|---|---|---|---|
| v1.0 (array) | `capabilities` is array | `["tool_call", ...]` | N/A | N/A | N/A |
| v1.1 (object) | `capabilities` is object | `{decisions: [...], ...}` | Full model list | Full dep map | Full resource info |

**h3-test compatibility:** All 7 existing health tests (1.1–1.7 in S05) pass unchanged. New v2-specific tests are additive.

**Hermes shim compatibility:** The shim's `health_check()` method returns a `HealthResponse` dataclass with optional v2 fields. When connected to a v1 harness, v2 fields are `None` and the shim treats the harness as fully capable (same behavior as today).

---

## 9. Security Considerations

**No API keys in health responses.** Model info includes provider name and pricing but never auth tokens or API keys. The `dependencies.llm_provider.endpoint` field shows the base URL only — no path segments containing keys.

**Error sanitization.** `recent_errors[].message` must be redacted: API keys → `sk-***`, tokens → `h3_***`, user content → `<redacted>`, file paths containing usernames → `~/***`. Each SDK's `RecordError()` function applies sanitization before storage.

**Config hash only.** The `config.hash` is a SHA-256 — irreversible. No config values are exposed in the health response.

**Rate limiting on health endpoint.** Health checks are cheap (<5ms) but could be abused. The shim's rate limiter (S15) exempts `/v1/health` from per-session limits but applies a separate endpoint-level limit: 10 requests/second from any single IP.

---

## 10. Performance Budget

| Metric | Budget | Rationale |
|---|---|---|
| Health response time (p50) | <3ms | Must not impact decision loop |
| Health response time (p95) | <5ms | Acceptable variance for GC pauses |
| Health response time under load (p95) | <10ms | 100 concurrent sessions, worst case |
| Dependency check timeout (per dep) | 2s | Prevents one slow dep from blocking health |
| Total dependency checks (parallel) | <600ms | 5 deps × 500ms each = 500ms wall clock (parallel) |
| Resource collection | <1ms | Cached for 5 seconds |
| Memory overhead per harness | <2KB | Ring buffer + model list + dep map |

---

## 11. Integration with Other Specs

| Spec | Integration Point |
|---|---|
| S02 (Protocol) | `/v1/health` extended with v2 fields |
| S05 (Test Battery) | New health v2 tests (HEALTH-I-* added to Region 1) |
| S12 (Security) | Auth status reported in `capabilities.auth`, `components.auth_validator` |
| S14 (TLS) | TLS mode reported in `capabilities.auth: ["mtls"]` |
| S15 (Rate Limiting) | Rate limiter type in `capabilities.rate_limiting`, endpoint-level rate limit on health |
| S16 (Logging) | `trace_id` in health request logs for correlation |
| S17 (Metrics) | Model latency/error-rate data sourced from metrics collector |
| S18 (Tracing) | `components.trace_exporter` reports OTLP connectivity |

---

## 12. Error Codes

| Code | HTTP | Meaning |
|---|---|---|
| `DB_UNREACHABLE` | 503 | Database connection lost |
| `LLM_PROVIDER_DOWN` | 503 | All LLM providers unreachable |
| `CONFIG_INVALID` | 503 | Config failed validation on reload |
| `OOM_IMMINENT` | 503 | Memory usage >95% of limit |
| `LLM_DEGRADED` | 200 | One or more models degraded (status is `degraded`) |
| `TRACE_EXPORTER_DOWN` | 200 | OTLP collector unreachable (status is `degraded`) |
| `DEP_DEGRADED` | 200 | One or more dependencies degraded (status is `degraded`) |

---

## 13. jq Diagnostics (for Operators)

```bash
# Quick status
curl -s http://localhost:9191/v1/health | jq '{status, version, sessions: .active_sessions, models: [.models[]?.id]}'

# Model health overview
curl -s http://localhost:9191/v1/health | jq '.models[] | {id, status, p95: .latency_ms_p95, error_rate: .error_rate_1h}'

# Dependency health
curl -s http://localhost:9191/v1/health | jq '.dependencies | to_entries[] | "\(.key): \(.value.status) (\(.value.latency_ms)ms)"'

# Degraded components
curl -s http://localhost:9191/v1/health | jq '{degraded: .degraded_components, components: .components | to_entries | map(select(.value != "healthy"))}'

# Resource usage
curl -s http://localhost:9191/v1/health | jq '{cpu: .resources.cpu_percent, mem: "\(.resources.memory_mb)/\(.resources.memory_limit_mb)MB", goroutines: .resources.goroutines}'

# Recent errors
curl -s http://localhost:9191/v1/health | jq '.recent_errors[] | "\(.timestamp): [\(.error_type)] \(.message)"'
```
