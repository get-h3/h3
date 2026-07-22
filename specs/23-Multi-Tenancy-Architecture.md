# S23 — Multi-Tenancy Architecture

**Version:** 1.0.0
**Date:** 2026-07-21
**Status:** Complete
**Phase:** MULTI (Multi-Tenancy)
**Covers:** MULTI-01 through MULTI-04
**Cross-references:** S12 (Security — per-harness auth keys), S15 (Rate Limiting — per-harness buckets), S17 (Metrics — per-harness stats), S19 (Health v2 — per-harness capability status), S21 (Resilience — circuit breaker per harness)

---

## 1. Overview

H3 currently supports a single harness per Hermes instance. As adoption grows, Hermes administrators need to run multiple harnesses simultaneously — different agent back-ends for different chat types, A/B testing of new harnesses against native loop, and zero-downtime harness rotation. This spec defines the multi-tenancy layer: harness registry, per-session routing, isolation guarantees, weighted A/B routing, and hot-reload without restarting Hermes.

### 1.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ HERMES GATEWAY                                                  │
│                                                                 │
│  ┌──────────┐    ┌─────────────────┐    ┌────────────────────┐  │
│  │ Incoming │───►│ Session Router  │───►│ Harness Registry   │  │
│  │ Message  │    │ (weighted,      │    │ ┌────────────────┐ │  │
│  │          │    │  per-session)    │    │ │ echo-harness    │ │  │
│  └──────────┘    └─────────────────┘    │ │ :9191 (100%)    │ │  │
│                                         │ ├────────────────┤ │  │
│  ┌──────────┐    ┌─────────────────┐    │ │ langchain-harn  │ │  │
│  │ Native   │◄───┤ Fallback Router │    │ │ :9192 (0%)      │ │  │
│  │ Loop     │    │ (one crash →    │    │ ├────────────────┤ │  │
│  │          │    │  native)         │    │ │ native-loop     │ │  │
│  └──────────┘    └─────────────────┘    │ │ (always active) │ │  │
│                                         │ └────────────────┘ │  │
│                                         └────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Harness A (echo)    Harness B (langchain)   Harness C    │   │
│  │ PID: 12345          PID: 12346              PID: 12347   │   │
│  │ Port: 9191          Port: 9192              Port: 9193   │   │
│  │ Sessions: 12        Sessions: 0             Sessions: 8  │   │
│  │ Weight: 1.0         Weight: 0.0             Weight: 0.5  │   │
│  │ Circuit: CLOSED     Circuit: OPEN            Circuit: HALF│   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Key Design Principles

1. **One session, one harness.** A session is bound to a harness at creation time and never changes mid-session. No session-level handoff between harnesses.
2. **Harness identity.** Each harness has a unique ID, API key (S12), and endpoint. The registry maps harness ID to connection config.
3. **Native is always a harness.** The native Hermes loop is represented as a harness entry (`type: native`) in the registry. It's always available and never fails health checks.
4. **Configuration is dynamic.** The registry lives in a watched config file. Changes are picked up without restart.
5. **Isolation by process.** Each external harness runs as a separate process (Docker container, systemd unit, or standalone binary). One crash cannot affect another.

---

## 2. MULTI-01: Multiple Harnesses Simultaneously (Per-Session Routing)

### 2.1 Harness Registry

The shim maintains a `HarnessRegistry` — an in-memory data structure backed by a watched configuration file:

```yaml
# ~/.hermes/h3/harnesses.yaml — registry config file
harnesses:
  - id: echo
    name: Echo Harness
    type: external          # external | native
    endpoint: http://localhost:9191
    api_key: h3_aGVsbG93b3JsZF9lY2hvX2hhcm5lc3M
    enabled: true
    weight: 1.0             # 0.0 - 1.0, relative weight for A/B routing
    max_sessions: 50        # soft cap, rejects new sessions when reached
    tags: [echo, testing, dev]
    description: Reference echo harness for compliance testing

  - id: langchain
    name: LangChain Agent
    type: external
    endpoint: http://localhost:9192
    api_key: h3_bGFuZ2NoYWluX2FnZW50X2tleV8yMDI2
    enabled: false          # disabled — no sessions routed
    weight: 0.0
    max_sessions: 100
    tags: [langchain, python, production]
    description: LangChain-powered agent for complex reasoning

  - id: native
    name: Native Hermes Loop
    type: native
    enabled: true
    weight: 0.5             # 50% of sessions go to native
    tags: [native, always-available]
    description: Built-in Hermes agent loop (fallback)

# Routing rules applied in order — first match wins
routing:
  - match:
      chat_type: [group, channel]  # group chats route to native
    harness: native
  - match:
      user_id: ["U12345", "U67890"]  # specific users → langchain
    harness: langchain
  - match:
      tags: [production]           # untagged sessions → weighted random
    strategy: weighted_random      # among all enabled harnesses with weight > 0
```

### 2.2 Registry Data Model

```python
# Python reference — shim/src/h3_shim/registry.py
from dataclasses import dataclass, field
from typing import Optional, Literal
from enum import Enum

class HarnessType(Enum):
    EXTERNAL = "external"
    NATIVE = "native"

@dataclass
class HarnessEntry:
    id: str
    name: str
    type: HarnessType
    endpoint: Optional[str] = None       # None for native
    api_key: Optional[str] = None         # Bearer token (S12), None for native
    enabled: bool = True
    weight: float = 1.0                  # 0.0–1.0 (relative)
    max_sessions: int = 100
    tags: list[str] = field(default_factory=list)
    description: str = ""
    
    # Runtime state (not in config file)
    active_sessions: int = 0
    circuit_state: str = "CLOSED"        # CLOSED / HALF_OPEN / OPEN
    consecutive_failures: int = 0
    last_health_check: float = 0.0
    health_status: str = "unknown"       # healthy / degraded / unhealthy

@dataclass
class RoutingRule:
    match: dict                          # conditions: chat_type, user_id, tags, etc.
    harness: str                         # harness ID to route to
    strategy: Optional[str] = None       # weighted_random (default) | round_robin
```

### 2.3 Session Routing Algorithm

```
1. RECEIVE: new session request (chat_id, user_id, chat_type)
2. ROUTING RULES: iterate rules in order, first match wins
3. FALLBACK: if no rule matches → weighted_random among enabled harnesses
4. SESSION CAP CHECK: reject (503) if harness at max_sessions
5. BIND: record session_id → harness_id in session map
6. CREATE: POST /v1/process with harness_id in metadata
7. DELIVER: route all subsequent decisions through bound harness
```

```python
def route_session(self, chat_id: str, user_id: str, chat_type: str) -> str:
    """Return harness_id for a new session."""
    # 1. Check explicit rules (first match wins)
    for rule in self.rules:
        if self._match_rule(rule, chat_id, user_id, chat_type):
            target = rule["harness"]
            if self._harness_available(target):
                return target
    
    # 2. Weighted random among enabled, non-full harnesses
    candidates = [
        h for h in self.harnesses.values()
        if h.enabled and h.weight > 0 and h.active_sessions < h.max_sessions
    ]
    if not candidates:
        raise NoAvailableHarness("All harnesses at capacity or disabled")
    
    total_weight = sum(h.weight for h in candidates)
    r = random.uniform(0, total_weight)
    cumulative = 0
    for h in candidates:
        cumulative += h.weight
        if r <= cumulative:
            return h.id
    
    return candidates[-1].id  # fallback — shouldn't reach here
```

### 2.4 Session Binding

Once bound, a session NEVER changes harness:

```python
class SessionRouter:
    _bindings: dict[str, str] = {}  # session_id → harness_id
    
    def get_harness(self, session_id: str) -> HarnessEntry:
        harness_id = self._bindings.get(session_id)
        if harness_id is None:
            raise UnboundSession(f"Session {session_id} not bound to any harness")
        return self.harnesses[harness_id]
    
    def unbind(self, session_id: str):
        harness_id = self._bindings.pop(session_id, None)
        if harness_id:
            self.harnesses[harness_id].active_sessions -= 1
```

### 2.5 SDK Contracts

No SDK changes required for multi-tenancy. Harnesses receive the same ProcessRequest/ResultRequest and are unaware of other harnesses. The `Identity` and `Context` fields in the protocol carry session identification; the shim adds a `harness_id` metadata field.

Protocol extension — new optional field in ProcessRequest metadata:

```json
{
  "metadata": {
    "harness_id": "echo",
    "harness_index": 1,
    "total_harnesses": 3
  }
}
```

Harnesses can use this for logging/tracing but must NOT depend on it for routing decisions.

---

## 3. MULTI-02: Harness Isolation

### 3.1 Isolation Guarantees

| Guarantee | Mechanism | Enforcement |
|-----------|-----------|-------------|
| Process isolation | External harnesses run as separate OS processes | Docker/systemd/standalone binary |
| Memory isolation | No shared memory between harness processes | OS-enforced (separate address spaces) |
| File isolation | Each harness has its own working directory | Docker volumes / separate home dirs |
| Network isolation | Each harness on its own port/IP | TCP port binding |
| Crash isolation | One harness crash → sessions on that harness fail over to native; other harnesses unaffected | Per-harness circuit breaker (S21 §5) |
| Resource isolation | Per-harness CPU/memory limits | cgroups (Docker) or ulimit (systemd) |
| Session isolation | Sessions are never shared between harnesses | Per-session binding (MULTI-01 §2.4) |

### 3.2 Crash Response

When a harness crashes (health check fails, connection refused, timeout):

```
1. DETECT: health check on harness returns unhealthy (S19)
2. ISOLATE: mark harness as degraded (health_status = "unhealthy")
3. ROUTE: new sessions skip this harness (weight effectively 0)
4. EXISTING: active sessions on this harness get "harness_unavailable" error
5. FAILOVER: shim auto-switches affected sessions to native loop (S21 §4.2)
6. ALERT: trigger alerting rules (S20) — harness_down, error_rate_spike
7. RECOVER: when harness returns healthy, circuit breaker enters HALF_OPEN
8. RESUME: after recovery probe passes, re-enable for NEW sessions only
```

### 3.3 Resource Quotas

```yaml
harnesses:
  - id: echo
    type: external
    endpoint: http://localhost:9191
    quotas:
      max_sessions: 50
      max_decisions_per_second: 100      # per-harness rate limit (S15)
      max_concurrent_requests: 10        # simultaneous HTTP connections
      max_request_body_bytes: 1048576    # 1MB
      session_timeout_seconds: 3600      # 1 hour idle timeout
```

Quota enforcement is advisory (logged + reported via metrics) with options for hard enforcement:

```python
# Shim — enforce quotas before routing
def check_quota(self, harness_id: str) -> bool:
    h = self.harnesses[harness_id]
    quotas = h.quotas
    
    if h.active_sessions >= quotas.get("max_sessions", 100):
        return False  # reject new session
    
    if h.requests_this_second >= quotas.get("max_decisions_per_second", 100):
        return False  # rate limit
    
    return True
```

### 3.4 Cross-Harness Communication

There is NO cross-harness communication. Each harness is a black box. Harnesses:

- Cannot discover other harnesses
- Cannot route to other harnesses
- Cannot access session data from other harnesses
- Cannot read the harness registry

The shim is the ONLY component that knows about multiple harnesses. This is a security boundary (S12 §3) — a compromised harness cannot enumerate or attack other harnesses.

---

## 4. MULTI-03: A/B Testing

### 4.1 Weighted Routing

A/B testing routes a configurable percentage of new sessions to different harnesses:

```yaml
harnesses:
  - id: native
    weight: 0.70             # 70% of new sessions → native

  - id: echo-v2
    name: Echo Harness v2.0
    endpoint: http://localhost:9194
    weight: 0.30             # 30% of new sessions → echo-v2 (canary)
    tags: [canary, echo]
```

Weights are relative — they don't need to sum to 1.0. The shim normalizes:

```
native_weight = 0.70
echo_v2_weight = 0.30
total = 1.00

native: 70% of sessions
echo-v2: 30% of sessions
```

### 4.2 Gradual Rollout Pattern

A/B testing follows a 5-phase rollout:

| Phase | Weight Distribution | Duration | Gate |
|-------|-------------------|----------|------|
| 1. Canary | native: 0.95, canary: 0.05 | 1 hour | Error rate < 1%, latency p95 < native +20% |
| 2. Expand | native: 0.80, canary: 0.20 | 4 hours | Error rate stable, no P1 alerts |
| 3. Split | native: 0.50, canary: 0.50 | 24 hours | Metrics parity with native |
| 4. Migrate | native: 0.20, canary: 0.80 | 24 hours | Stable under load |
| 5. Replace | native: 0.00, canary: 1.00 | Permanent | All sessions on canary |

Rollback: revert weight to 0.0, all existing canary sessions fail over to native (S21 §4.2). Rollback is instantaneous — change the config file, shim picks it up on next read.

### 4.3 A/B Metrics

The shim tracks per-harness metrics (S17) and exposes A/B comparison:

```
GET /v1/metrics?compare=harnesses

{
  "harnesses": {
    "native": {
      "sessions": 142,
      "decisions_processed": 2840,
      "error_rate": 0.007,
      "latency_p50_ms": 12,
      "latency_p95_ms": 45,
      "latency_p99_ms": 89
    },
    "echo-v2": {
      "sessions": 61,
      "decisions_processed": 1220,
      "error_rate": 0.011,
      "latency_p50_ms": 14,
      "latency_p95_ms": 52,
      "latency_p99_ms": 95
    }
  },
  "comparison": {
    "echo-v2_vs_native": {
      "error_rate_delta": "+0.004",
      "latency_p95_delta": "+15.6%",
      "sessions_ratio": "30.1% / 69.9%",
      "recommendation": "WATCH — latency regression within tolerance"
    }
  }
}
```

### 4.4 CLI Surface

```bash
# View current routing weights
hermes h3 routing show
# ┌──────────────┬────────┬──────────┬──────────┐
# │ Harness      │ Weight │ Sessions │ Health   │
# ├──────────────┼────────┼──────────┼──────────┤
# │ native       │ 0.70   │ 142      │ healthy  │
# │ echo-v2      │ 0.30   │ 61       │ healthy  │
# └──────────────┴────────┴──────────┴──────────┘

# Set canary weight
hermes h3 routing set-weight echo-v2 --weight 0.30

# Compare harness metrics
hermes h3 routing compare native echo-v2

# Rollback canary
hermes h3 routing set-weight echo-v2 --weight 0.0
```

---

## 5. MULTI-04: Hot-Reload

### 5.1 Config File Watching

The harness registry is backed by a YAML file watched for changes:

```python
# Shim — watchdog-based config reload
import time
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class HarnessConfigWatcher(FileSystemEventHandler):
    def on_modified(self, event):
        if event.src_path == self.config_path:
            self.registry.reload()
            self._log_reload()

# Start watching
observer = Observer()
observer.schedule(HarnessConfigWatcher(config_path), path=config_dir)
observer.start()
```

### 5.2 Add Harness Without Restart

```bash
# 1. Start a new harness process (separate terminal/Docker)
cd sdk-go/examples/echo && go run . -port 9194 &

# 2. Verify it's running
curl http://localhost:9194/v1/health
# {"status": "healthy", "harness": "echo-v2", "version": "2.0.0"}

# 3. Register in config
hermes h3 harness add echo-v2 \
  --endpoint http://localhost:9194 \
  --api-key h3_ZWNob192Ml9rZXlfdjIwMjY \
  --weight 0.0 \
  --tags canary,echo

# 4. Start canary
hermes h3 routing set-weight echo-v2 --weight 0.05

# New sessions now route 5% to echo-v2. Existing sessions unaffected.
```

### 5.3 Remove Harness Without Restart

```bash
# 1. Drain traffic
hermes h3 routing set-weight echo-v2 --weight 0.0

# 2. Wait for active sessions to end (or force-failover)
hermes h3 harness drain echo-v2 --timeout 300

# 3. Remove from registry
hermes h3 harness remove echo-v2

# 4. Stop harness process (optional — it's no longer receiving traffic)
```

### 5.4 Hot-Reload Guarantees

| Operation | Existing Sessions | New Sessions | Downtime |
|-----------|------------------|--------------|----------|
| Add harness (weight=0) | Unaffected | Unaffected | Zero |
| Add harness (weight>0) | Unaffected | May route to new harness | Zero |
| Set weight to 0 | Unaffected | Skip harness | Zero |
| Remove harness | Fail over to native (S21) | Skip harness | Zero |
| Change endpoint | Active connections break, fail over | New sessions use new endpoint | <1s for failover |
| Change API key | Active connections break (auth fail), fail over | New sessions use new key | <1s for failover |

### 5.5 Atomic Config Updates

The config file supports atomic writes to prevent partial reads:

```python
def reload(self):
    """Atomically reload harness configuration."""
    try:
        with open(self.config_path + ".tmp", "w") as f:
            yaml.dump(self._pending_config, f)
        os.rename(self.config_path + ".tmp", self.config_path)
    except Exception as e:
        logger.error(f"Failed to reload harness config: {e}")
        # Keep existing config — no partial state
    
    # Validate new config before applying
    new_config = yaml.safe_load(open(self.config_path))
    self._validate_config(new_config)
    
    # Apply atomically
    old_registry = self.harnesses
    self.harnesses = self._build_registry(new_config)
    
    # Migrate active session bindings
    for session_id, harness_id in list(self._bindings.items()):
        if harness_id not in self.harnesses:
            # Harness was removed — sessions fail over to native
            self._failover_session(session_id)
```

---

## 6. SDK Middleware Contracts

### 6.1 Go SDK

```go
// HarnessInfo — passed to harness on startup for logging/identity
type HarnessInfo struct {
    ID      string
    Name    string
    Tags    []string
    Index   int    // 0-based index in registry
    Total   int    // total harnesses in registry
}

// Harness interface — unchanged. Harnesses don't need multi-tenancy awareness.
type Harness interface {
    Process(ctx context.Context, req ProcessRequest) (Decision, error)
    Result(ctx context.Context, req ResultRequest) (Decision, error)
    Health(ctx context.Context) (HealthResponse, error)
}
```

### 6.2 Python SDK

```python
@dataclass
class HarnessInfo:
    id: str
    name: str
    tags: list[str]
    index: int
    total: int

class BaseHarness(ABC):
    harness_info: Optional[HarnessInfo] = None  # Set by SDK on startup
    
    @abstractmethod
    async def process(self, request: ProcessRequest) -> Decision: ...
    
    @abstractmethod
    async def result(self, request: ResultRequest) -> Decision: ...
    
    @abstractmethod
    async def health(self) -> HealthResponse: ...
```

### 6.3 TypeScript SDK

```typescript
interface HarnessInfo {
    id: string;
    name: string;
    tags: string[];
    index: number;
    total: number;
}

abstract class BaseHarness {
    harnessInfo?: HarnessInfo;
    
    abstract process(request: ProcessRequest): Promise<Decision>;
    abstract result(request: ResultRequest): Promise<Decision>;
    abstract health(): Promise<HealthResponse>;
}
```

**Key design:** Harnesses receive `harness_info` for logging/diagnostics but do NOT use it for routing. The harness is a single-tenant component — multi-tenancy is entirely a shim concern.

---

## 7. Test Plan

### 7.1 Unit Tests (MULTI-UT-01 through MULTI-UT-12)

| ID | Test | Description |
|----|------|-------------|
| MULTI-UT-01 | test_registry_load | Load valid harnesses.yaml → registry has 3 entries |
| MULTI-UT-02 | test_registry_duplicate_id | Duplicate harness ID → ValueError |
| MULTI-UT-03 | test_routing_weighted | 10000 sessions with weights [0.7, 0.3] → within 3% tolerance |
| MULTI-UT-04 | test_routing_rule_first_match | Explicit user_id rule overrides weighted random |
| MULTI-UT-05 | test_session_binding | Route → bind → subsequent decisions use same harness |
| MULTI-UT-06 | test_session_unbind | Session ends → active_sessions decremented |
| MULTI-UT-07 | test_capacity_reject | Harness at max_sessions → new session rejected (503) |
| MULTI-UT-08 | test_crash_isolation | Harness A crashes → sessions on A fail over, sessions on B unaffected |
| MULTI-UT-09 | test_hot_reload_add | Add harness to config file → registry picks up within watch interval |
| MULTI-UT-10 | test_hot_reload_remove | Remove harness → active sessions on it fail over to native |
| MULTI-UT-11 | test_hot_reload_weight_change | Change weight → new session distribution updates |
| MULTI-UT-12 | test_ab_metrics_comparison | GET /v1/metrics?compare=harnesses → correct deltas |

### 7.2 Integration Tests (MULTI-I-01 through MULTI-I-06)

| ID | Test | Description |
|----|------|-------------|
| MULTI-I-01 | test_three_harnesses_concurrent | Start echo:9191, echo:9192, native → 30 sessions, verify distribution |
| MULTI-I-02 | test_crash_recovery | Kill harness A mid-session → verify failover + other harnesses unaffected |
| MULTI-I-03 | test_hot_add_routing | Start registry without echo-v2 → add echo-v2 to config → new sessions route |
| MULTI-I-04 | test_hot_remove_drain | Remove echo-v2 with active sessions → drain completes → sessions on native |
| MULTI-I-05 | test_ab_rollout_phases | Simulate 5-phase rollout → verify weight transitions + metrics |
| MULTI-I-06 | test_cross_harness_isolation | Harness A cannot access harness B session data (security boundary) |

### 7.3 Performance Tests (MULTI-P-01 through MULTI-P-03)

| ID | Test | Description |
|----|------|-------------|
| MULTI-P-01 | test_routing_latency | 10,000 route decisions → p95 < 100µs |
| MULTI-P-02 | test_registry_reload_latency | 1000-harness registry → reload < 100ms |
| MULTI-P-03 | test_10_harnesses_concurrent | 10 harnesses, 1000 sessions, 100 decisions/sec each → throughput within 5% of single-harness |

---

## 8. Configuration Reference

### 8.1 Full Config Schema

```yaml
# ~/.hermes/h3/harnesses.yaml
version: "1.0"

# Default settings for all harnesses
defaults:
  max_sessions: 100
  max_decisions_per_second: 100
  session_timeout_seconds: 3600
  health_check_interval_seconds: 30

# Individual harness definitions
harnesses:
  - id: echo                    # REQUIRED: unique, alphanumeric + hyphens
    name: Echo Harness          # REQUIRED: human-readable
    type: external              # REQUIRED: external | native
    endpoint: http://localhost:9191  # REQUIRED for external
    api_key: h3_<base64url>     # REQUIRED for external (S12)
    enabled: true               # default: true
    weight: 1.0                 # default: 1.0, 0.0–1.0
    max_sessions: 50            # override defaults.max_sessions
    tags: [echo, testing]       # default: []
    description: "..."          # default: ""

  - id: native
    name: Native Hermes Loop
    type: native                # no endpoint, no api_key
    enabled: true
    weight: 0.5
    tags: [native]

# Routing rules — first match wins
routing:
  - match:
      chat_type: [group]       # group chats always go to native
    harness: native
  - match:
      user_id: ["U12345"]      # specific users → specific harness
    harness: langchain
  - match:
      tags: [production]       # untagged → weighted random
    strategy: weighted_random
```

### 8.2 CLI Commands

| Command | Description |
|---------|-------------|
| `hermes h3 harness list [--json]` | List all registered harnesses with status |
| `hermes h3 harness add <id> --endpoint URL --api-key KEY [--weight W] [--tags T]` | Register a new harness |
| `hermes h3 harness remove <id>` | Remove a harness (drain first) |
| `hermes h3 harness drain <id> [--timeout SEC]` | Drain active sessions, then remove |
| `hermes h3 harness info <id>` | Detailed info for one harness |
| `hermes h3 routing show` | Show routing table + weights |
| `hermes h3 routing set-weight <id> --weight W` | Set harness weight for A/B |
| `hermes h3 routing compare <id1> <id2>` | A/B metrics comparison |

---

## 9. Migration Plan

### Phase 1: Registry Backend (Shim)

- Implement `HarnessRegistry` class in shim
- Add `harnesses.yaml` config file support
- Add watchdog-based hot-reload
- Unit tests: MULTI-UT-01 through MULTI-UT-04
- **Gate:** Load config with 3 harnesses, verify routing distribution

### Phase 2: Per-Session Binding + Isolation

- Implement `SessionRouter` with session binding
- Add capacity enforcement + crash isolation
- Wire failover to native loop (S21 integration)
- Unit tests: MULTI-UT-05 through MULTI-UT-08
- Integration tests: MULTI-I-01, MULTI-I-02
- **Gate:** 3 harnesses, one crashes, sessions on other two unaffected

### Phase 3: A/B Testing + Hot-Reload

- Implement weighted routing + A/B metrics
- Add harness add/remove/drain commands
- Wire CLI surface
- Unit tests: MULTI-UT-09 through MULTI-UT-12
- Integration tests: MULTI-I-03 through MULTI-I-06
- **Gate:** Add harness while system running, new sessions route without restart

### Phase 4: Test Battery + Production Readiness

- Add `h3-test` multi-tenancy region (10 new tests)
- Performance benchmarks
- Update protocol spec (harness_id metadata)
- Update all 3 SDKs (HarnessInfo passthrough)
- Integration tests: MULTI-P-01 through MULTI-P-03
- **Gate:** Full test battery passes with 3 harnesses (120+ tests)

---

## 10. Security Considerations

| Concern | Mitigation | Reference |
|---------|-----------|-----------|
| Harness enumeration | Registry is shim-internal. No API exposes full harness list to external callers. | S12 §3 |
| Harness impersonation | API key required for external harnesses. Key validated on connect. | S12 §4.2 |
| Cross-harness data leak | No shared session state. Session → harness binding is 1:1 and immutable. | §3.4 |
| Harness privilege escalation | Harnesses cannot access registry, cannot modify routing, cannot enumerate peers. | §3.4 |
| Config tampering | Config file permissions: 0600, owned by hermes user. Atomic writes prevent partial state. | §5.5 |
| DoS via harness flood | Max 10 harnesses by default. Configurable upper bound. | S15 §3 |
| A/B data bias | Metrics tracked per-harness. A/B comparison uses identical metric definitions. | §4.3 |

---

## 11. Cross-Phase Integration

| Phase | Integration Point | Reference |
|-------|-------------------|-----------|
| SEC | Per-harness API keys, auth headers on all requests | S12 §5.1 |
| RATE | Per-harness token bucket, capacity enforcement | S15 §3 |
| METRICS | Per-harness stats, A/B comparison endpoint | S17 §4 |
| HEALTH | Per-harness capability status, health grid | S19 §4 |
| ALERT | Harness down, latency spike per harness | S20 §5 |
| RESILIENCE | Per-harness circuit breaker, session failover | S21 §5 |
| PERF | Isolation performance overhead, routing latency | S22 §5 |
| OBS | Trace harness_id in all spans, harness tag in logs | S16 §3, S18 §3 |

---

## 12. Performance Budget

| Operation | Target | Measurement |
|-----------|--------|-------------|
| Registry load (100 harnesses) | <10ms | Wall-clock from file open to in-memory |
| Session routing decision | <100µs | Weighted random + rule check |
| Hot-reload apply | <50ms | Config change → registry updated |
| Add harness (no sessions) | <10ms | File write + watchdog detect + validate |
| Remove harness (with drain) | <O(active_sessions) × failover_time | Per-session failover cost |

---

## 13. Error Codes

| Code | HTTP | Description |
|------|------|-------------|
| HARNESS_NOT_FOUND | 404 | Harness ID not in registry |
| HARNESS_DISABLED | 503 | Harness exists but enabled=false |
| HARNESS_AT_CAPACITY | 503 | Harness at max_sessions |
| HARNESS_UNHEALTHY | 503 | Health check failed |
| NO_AVAILABLE_HARNESS | 503 | All harnesses disabled or full |
| DUPLICATE_HARNESS_ID | 409 | Harness ID already exists |
| INVALID_WEIGHT | 400 | Weight not in [0.0, 1.0] |
| HARNESS_HAS_ACTIVE_SESSIONS | 409 | Cannot remove harness with active sessions (drain first) |
| HOT_RELOAD_FAILED | 500 | Config file write/validate failed |
