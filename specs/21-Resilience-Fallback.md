# S21 — H3 Resilience & Fallback Architecture (RES-01)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S02 (Protocol), S06 (Hermes Core Integration), S12 (Security & Auth), S16 (Structured Logging), S19 (Health Check v2)  
**Last Updated:** 2026-07-21

---

## 1. Overview

H3's core promise is brain-swap: Hermes delegates thinking to an external harness via the protocol. But what happens when the brain goes silent? A harness crash, network partition, or timeout must not strand the user mid-conversation. Hermes must detect the failure, fall back gracefully, and — when possible — recover.

**This spec defines:** the complete resilience architecture: timeout detection at every hop, graceful fallback from harness to native Hermes loop, circuit breaker pattern for persistent failures, session state preservation during migration, periodic health re-check for auto-recovery, and user-visible notification of fallback events.

**Design principle:** "The harness is an optimization, not a dependency. Every session must survive harness death with zero data loss and zero user-visible disruption beyond a brief latency spike."

**Scope:** RES-01 through RES-07 on the task board. This single S21 spec covers all 7 RES tasks — they share the same architecture, the same state machine, and the same implementation surface.

**Implementation targets:**
- `shim/` — Timeout detection, fallback orchestration, circuit breaker, health re-check loop (`h3/resilience.py`)
- `sdk-go/` — Harness-side timeout middleware, graceful shutdown hooks
- `sdk-python/` — Harness-side timeout middleware with same interfaces
- `sdk-typescript/` — Harness-side timeout middleware with same interfaces
- `protocol/` — New error codes: HARNESS_TIMEOUT, HARNESS_UNREACHABLE, CIRCUIT_OPEN, FALLBACK_ACTIVE

**Key outcomes:**
- **Mid-session harness death:** Session migrates to native Hermes loop with full conversation history preserved
- **Harness timeout:** Configurable per-hop timeout with retry → fallback escalation
- **Circuit breaker:** N consecutive failures → auto-disable harness for cooldown period
- **Auto-recovery:** Periodic health re-check re-enables harness when it recovers
- **User transparency:** User is notified of fallback, not confused by silence
- **Zero data loss:** All session state (messages, decisions, context) is preserved across migration

---

## 2. Resilience State Machine

Every harness has a resilience state tracked by the Shim:

```
                    ┌─────────┐
           ┌───────▶│ HEALTHY │◀──────────┐
           │        └────┬────┘           │
           │             │ failure         │ health check passes
           │             ▼                 │ (cooldown expired)
           │        ┌─────────┐           │
           │        │DEGRADED │───────────┘
           │        └────┬────┘  (auto-recover)
           │    timeout   │
           │    or crash  │ 3+ consecutive
           │             ▼    failures
           │        ┌─────────┐
           │        │ FALLBACK│
           │        └────┬────┘
           │             │ N consecutive
           │             │ failures (default: 5)
           │             ▼
           │        ┌─────────┐
           └────────│  OPEN   │
      (cooldown    └─────────┘
       expired)         │
                   manual reset or
                   extended cooldown (12h)
                        ▼
                   ┌─────────┐
                   │ HEALTHY │ (re-check)
                   └─────────┘
```

### 2.1 States

| State | Meaning | User Experience | Auto-Recovery |
|-------|---------|----------------|---------------|
| `HEALTHY` | Harness responding within SLA | Normal H3 routing | N/A (already healthy) |
| `DEGRADED` | Harness responded but exceeded latency budget | User sees slight delay; session stays on harness | Next successful response restores HEALTHY |
| `FALLBACK` | Harness timed out or crashed; session migrated to native | User notified: "Switching to native mode. Your conversation continues." | Health re-check every 60s; 3 consecutive successes → HEALTHY |
| `OPEN` | Circuit breaker tripped; harness is disabled | All sessions route native. User not notified per-session (harness is globally offline). | Cooldown period (default 5 min) → FALLBACK → health re-check → HEALTHY |

### 2.2 State Transitions

```
HEALTHY → DEGRADED:
  Trigger: Single request exceeds latency budget (process > 2s OR result > 5s)
  Action: Log warning. Session stays on harness. Metrics counter incremented.

DEGRADED → HEALTHY:
  Trigger: Next request within latency budget
  Action: Reset degradation counter. Log recovery.

DEGRADED → FALLBACK:
  Trigger: 3 consecutive DEGRADED responses OR single timeout/connection failure
  Action: Migrate ALL active sessions on this harness to native loop.
           Log CRITICAL. User notification per session.

FALLBACK → OPEN:
  Trigger: 5 consecutive failures during periodic health re-check (every 60s)
  Action: Circuit breaker opens. Harness removed from routing table.
           All new sessions route native. Log CRITICAL. Admin alert (OBS-06).

FALLBACK → HEALTHY:
  Trigger: 3 consecutive successful health checks
  Action: Harness re-enters routing table. New sessions route via H3.
           Active native sessions stay native (no mid-session re-migration).

OPEN → FALLBACK:
  Trigger: Cooldown period expires (default: 5 min)
  Action: Circuit half-opens. Single probe request sent.
           Success → FALLBACK → health re-check → HEALTHY.
           Failure → back to OPEN with exponential backoff (5m, 15m, 1h, 12h max).

OPEN → HEALTHY (manual):
  Trigger: Admin `hermes h3 reset <harness_id>` command
  Action: Circuit forced open → FALLBACK → immediate health check → HEALTHY if pass.
```

---

## 3. Timeout Detection

### 3.1 Timeout Budgets

Every hop in the decision pipeline has a configurable timeout:

| Hop | Default Timeout | Config Key | On Timeout |
|-----|----------------|------------|------------|
| `/v1/health` (health check) | 5s | `harness.health_timeout_s` | Mark harness UNREACHABLE, enter FALLBACK |
| `/v1/process` (initial decision request) | 30s | `harness.process_timeout_s` | Retry once (different connection), then FALLBACK |
| `/v1/result` (decision result delivery) | 10s | `harness.result_timeout_s` | Log warning. Decision executed natively. Session migrates after 3 result timeouts. |
| Full round-trip (process + result) | 60s | `harness.roundtrip_timeout_s` | FALLBACK if exceeded 3 times in 5-minute window |

### 3.2 Timeout Types

```python
# shim/src/h3_shim/resilience.py

class TimeoutType(Enum):
    CONNECT = "connect"        # TCP connection refused / DNS failure
    READ = "read"              # Connection established, no response within budget
    HEALTH = "health"          # Health check timeout
    PROCESS = "process"        # /v1/process timeout
    RESULT = "result"          # /v1/result timeout
```

### 3.3 Timeout Handling

**Connect timeout:**
```
1. TCP SYN to harness:port → no response within 5s
2. Mark harness UNREACHABLE
3. All active sessions → FALLBACK (native loop)
4. Log: "Harness unreachable: connection refused to <url> after 5s"
5. Enter health re-check loop (every 30s for first 2 min, then every 60s)
```

**Process timeout:**
```
1. POST /v1/process → no response within 30s
2. Cancel the HTTP request (httpx/client cancellation)
3. Retry on a fresh connection (different TCP socket)
4. If retry also times out → FALLBACK
5. Log: "Process timeout after 30s (retry failed). Migrating session <id> to native."
6. Shim calls native Hermes loop with the same messages[]
```

**Result timeout:**
```
1. POST /v1/result → no response within 10s
2. Decision is already generated — execute it natively
3. Log warning: "Result delivery timeout (10s). Decision executed. Count: N/3"
4. After 3 result timeouts in 5 min → FALLBACK
```

---

## 4. Fallback Mechanism

### 4.1 Native Loop Integration

When fallback triggers, the Shim invokes Hermes' native agent loop:

```python
# shim/src/h3_shim/resilience.py

def fallback_to_native(session: Session, reason: str):
    """
    Migrate an active session from H3 harness routing to native Hermes loop.
    
    Args:
        session: Active session state (messages, context, session_id)
        reason: Human-readable fallback reason for logs
    """
    logger.critical(
        "fallback_active",
        session_id=session.id,
        harness_id=session.harness_id,
        reason=reason,
        message_count=len(session.messages),
        decision_count=session.decision_count,
    )
    
    # 1. Preserve full session state
    native_context = {
        "messages": session.messages,          # Full conversation history
        "session_id": session.id,
        "platform": session.platform,
        "chat_id": session.chat_id,
        "thread_id": session.thread_id,
        "decision_count": session.decision_count,
        "fallback_reason": reason,
        "fallback_at": time.time(),
        "prior_harness": session.harness_id,
    }
    
    # 2. Notify user (one-time per session)
    hermes.send_message(
        platform=session.platform,
        chat_id=session.chat_id,
        thread_id=session.thread_id,
        text=f"🔄 Switching to native mode. Your conversation continues uninterrupted.",
    )
    
    # 3. Invoke native Hermes loop
    #    Hermes' native agent processes the messages array as if it had 
    #    been the brain all along — no context loss, no restart.
    native_result = hermes.invoke_native_loop(
        messages=native_context["messages"],
        session_id=session.id,
        platform=session.platform,
        chat_id=session.chat_id,
        thread_id=session.thread_id,
    )
    
    # 4. Record migration event
    metrics.increment("h3.fallback.count", tags={"harness": session.harness_id})
    metrics.gauge("h3.fallback.active_sessions", 1, tags={"harness": session.harness_id})
    
    return native_result
```

### 4.2 State Preservation Guarantees

| Data | Preserved? | How |
|------|-----------|-----|
| Message history | ✅ Full | `messages[]` array passed directly to native loop |
| Session ID | ✅ | Copied to native context |
| Platform/chat routing | ✅ | platform, chat_id, thread_id preserved |
| Decision count | ✅ | Counter carried over; no reset |
| Tool execution results | ✅ | Native loop picks up where harness left off |
| Harness identity | ✅ Metadata | Logged as `prior_harness` for debugging |
| Trace context | ✅ | Same trace_id spans both harness and native phases |

### 4.3 User Notification

Fallback notifications are sent ONCE per session:

| Event | Message | Channel |
|-------|---------|---------|
| FALLBACK triggered | "🔄 Switching to native mode. Your conversation continues uninterrupted." | Same chat/thread as session |
| FALLBACK → HEALTHY (recovery) | "✅ H3 harness recovered. Future conversations will use enhanced processing." | Admin-only log (not user-facing) |
| OPEN (circuit breaker) | Admin alert via OBS-06 notification channel | Telegram/email/webhook |

---

## 5. Circuit Breaker

### 5.1 Pattern

The circuit breaker protects against persistent harness failures burning resources on retries:

```
CLOSED (HEALTHY) ──failure──▶ OPEN ──cooldown──▶ HALF_OPEN ──success──▶ CLOSED
                                                    │
                                                    └──failure──▶ OPEN (backoff)
```

### 5.2 Configuration

```yaml
# .hermes/h3/config.yaml (new section)
resilience:
  circuit_breaker:
    failure_threshold: 5           # Consecutive failures before opening
    cooldown_base_s: 300           # Initial cooldown: 5 minutes
    cooldown_max_s: 43200          # Max cooldown: 12 hours
    cooldown_multiplier: 3.0       # Exponential backoff: 5m → 15m → 45m → ...
    half_open_probe_count: 1       # Number of probe requests in half-open state
    success_threshold: 3           # Consecutive successes to close circuit
  
  fallback:
    health_recheck_interval_s: 60  # How often to re-check harness health
    degraded_threshold: 3          # Consecutive degraded → FALLBACK
    result_timeout_threshold: 3    # Result timeouts in 5min → FALLBACK
  
  timeouts:
    health_timeout_s: 5
    process_timeout_s: 30
    result_timeout_s: 10
    roundtrip_timeout_s: 60
    connect_timeout_s: 5
```

### 5.3 Implementation

```python
class CircuitBreaker:
    def __init__(self, harness_id: str, config: ResilienceConfig):
        self.harness_id = harness_id
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.success_count = 0
        self.last_failure_time: Optional[float] = None
        self.cooldown_until: Optional[float] = None
        self.config = config
    
    def record_success(self):
        if self.state == CircuitState.HALF_OPEN:
            self.success_count += 1
            if self.success_count >= self.config.success_threshold:
                self.state = CircuitState.CLOSED
                self.failure_count = 0
                logger.info("circuit_closed", harness_id=self.harness_id)
    
    def record_failure(self) -> bool:
        """
        Returns True if the circuit just opened (caller should trigger fallback).
        """
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.config.failure_threshold:
            if self.state != CircuitState.OPEN:
                self.state = CircuitState.OPEN
                backoff = min(
                    self.config.cooldown_base_s * (self.config.cooldown_multiplier ** self.failure_count),
                    self.config.cooldown_max_s
                )
                self.cooldown_until = time.time() + backoff
                logger.critical(
                    "circuit_opened",
                    harness_id=self.harness_id,
                    failure_count=self.failure_count,
                    cooldown_s=backoff,
                )
                return True
        return False
    
    def allow_request(self) -> bool:
        if self.state == CircuitState.CLOSED:
            return True
        if self.state == CircuitState.OPEN:
            if time.time() >= self.cooldown_until:
                self.state = CircuitState.HALF_OPEN
                self.success_count = 0
                logger.info("circuit_half_open", harness_id=self.harness_id)
                return True
            return False
        # HALF_OPEN: allow probe requests
        return True
```

---

## 6. Session Migration

### 6.1 Harness → Native (Fallback)

Active sessions on a failing harness are migrated in bulk:

```python
def migrate_all_sessions_to_native(harness_id: str, reason: str):
    """
    Called when a harness enters FALLBACK state.
    All active sessions on this harness are migrated to native loop.
    """
    sessions = session_store.get_active_sessions(harness_id=harness_id)
    
    logger.critical(
        "bulk_session_migration",
        harness_id=harness_id,
        session_count=len(sessions),
        reason=reason,
    )
    
    for session in sessions:
        fallback_to_native(session, reason)
    
    # Update routing table
    routing.remove_harness(harness_id)
    routing.set_fallback_active(harness_id, True)
```

### 6.2 Native → Harness (Recovery)

When a harness recovers (FALLBACK → HEALTHY), NEW sessions route to it. Existing native sessions stay native — mid-session re-migration is complex (different agent context, different tool sets) and risks user-visible disruption.

```python
def on_harness_recovered(harness_id: str):
    """
    Called when a harness transitions FALLBACK → HEALTHY.
    New sessions will use this harness. Existing native sessions unaffected.
    """
    routing.add_harness(harness_id)
    routing.set_fallback_active(harness_id, False)
    
    logger.info(
        "harness_recovered",
        harness_id=harness_id,
        note="New sessions will route via H3. Active native sessions unchanged.",
    )
```

---

## 7. Backpressure Handling (RES-04)

### 7.1 Decision Queue

When the harness returns decisions faster than Hermes can execute them (tool calls, message delivery), a bounded queue prevents memory exhaustion:

```python
class DecisionQueue:
    def __init__(self, max_size: int = 100):
        self.queue: asyncio.Queue = asyncio.Queue(maxsize=max_size)
        self.dropped_count = 0
    
    async def enqueue(self, decision: Decision) -> bool:
        """Returns False if queue is full (decision dropped)."""
        try:
            self.queue.put_nowait(decision)
            return True
        except asyncio.QueueFull:
            self.dropped_count += 1
            logger.warning(
                "decision_dropped_backpressure",
                decision_id=decision.decision_id,
                queue_size=self.queue.qsize(),
                total_dropped=self.dropped_count,
            )
            return False
```

### 7.2 Backpressure Signals

The Shim sends backpressure signals to the harness via HTTP headers:

| Header | Meaning | Harness Action |
|--------|---------|---------------|
| `X-H3-Backpressure: warn` | Queue > 75% full | Slow down decision production |
| `X-H3-Backpressure: block` | Queue full | Stop sending decisions; wait for drain |
| `X-H3-Queue-Depth: N` | Current queue depth | Informational |

Harnesses that ignore backpressure signals and continue flooding decisions → per-harness rate limit kicks in (S15 §4.3).

---

## 8. Graceful Degradation (RES-06)

When a harness responds but with errors, the Shim extracts usable parts:

```python
def handle_partial_response(response: ProcessResponse) -> Optional[Decision]:
    """
    Extract usable decisions from a partially-failed harness response.
    Returns None if nothing is salvageable (full fallback needed).
    """
    if response.decisions:
        # Harness returned some valid decisions — use them
        logger.warning(
            "partial_response",
            session_id=response.session_id,
            decision_count=len(response.decisions),
            error=response.error,
        )
        return response.decisions[0]  # Best-effort: use first decision
    elif response.text_response:
        # Harness returned a text response (no structured decision)
        # Convert to native text delivery
        return Decision(
            type="text",
            text=response.text_response,
            finished=response.finished,
        )
    else:
        # Nothing salvageable — full fallback
        return None
```

---

## 9. Cold Start & Warm-Up (RES-07)

### 9.1 First-Request Latency Budget

Harnesses may have cold-start latency (model loading, connection pool warm-up). The Shim accommodates this:

| State | First Request Timeout | Subsequent Timeout |
|-------|----------------------|-------------------|
| Cold (harness just registered) | 60s | — |
| Warm (harness has served ≥1 request) | 30s | 30s |

```python
def get_timeout(harness: HarnessState, hop: str) -> float:
    base = TIMEOUTS[hop]
    if harness.request_count == 0:
        return base * 2  # Double timeout for cold start
    return base
```

### 9.2 Warm-Up Protocol

On harness registration, the Shim sends a warm-up probe:

```
POST /v1/health  →  Expect: 200 + capabilities
POST /v1/process  →  Empty messages[], Expect: any valid response
```

If warm-up succeeds → harness is HEALTHY. If warm-up fails → harness is DEGRADED, re-check in 30s.

---

## 10. SDK Middleware Contracts

### 10.1 Go SDK

```go
// sdk-go/pkg/h3/resilience/middleware.go

type ResilienceMiddleware struct {
    circuitBreaker *CircuitBreaker
    timeoutConfig  TimeoutConfig
}

func (m *ResilienceMiddleware) Wrap(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        ctx, cancel := context.WithTimeout(r.Context(), m.timeoutConfig.ProcessTimeout)
        defer cancel()
        
        done := make(chan struct{})
        go func() {
            next.ServeHTTP(w, r)
            close(done)
        }()
        
        select {
        case <-done:
            m.circuitBreaker.RecordSuccess()
        case <-ctx.Done():
            m.circuitBreaker.RecordFailure()
            http.Error(w, `{"error":"HARNESS_TIMEOUT"}`, 504)
        }
    })
}
```

### 10.2 Python SDK

```python
# sdk-python/src/h3_sdk/resilience.py

class ResilienceMiddleware:
    def __init__(self, config: ResilienceConfig):
        self.circuit_breaker = CircuitBreaker(config)
        self.timeout = config.process_timeout_s
    
    async def __call__(self, request: Request, call_next):
        try:
            async with asyncio.timeout(self.timeout):
                response = await call_next(request)
            self.circuit_breaker.record_success()
            return response
        except asyncio.TimeoutError:
            self.circuit_breaker.record_failure()
            return JSONResponse(
                status_code=504,
                content={"error": "HARNESS_TIMEOUT", "timeout_s": self.timeout}
            )
```

### 10.3 TypeScript SDK

```typescript
// sdk-typescript/src/resilience.ts

export class ResilienceMiddleware {
  constructor(private config: ResilienceConfig) {}
  
  middleware(): MiddlewareHandler {
    return async (c, next) => {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), this.config.processTimeoutMs);
      
      try {
        c.req.raw.signal = controller.signal;
        const response = await next();
        clearTimeout(timeoutId);
        this.circuitBreaker.recordSuccess();
        return response;
      } catch (e) {
        clearTimeout(timeoutId);
        this.circuitBreaker.recordFailure();
        return c.json({ error: "HARNESS_TIMEOUT" }, 504);
      }
    };
  }
}
```

---

## 11. CLI Surface

```bash
# View resilience status for all harnesses
hermes h3 resilience show [--json]

# View specific harness
hermes h3 resilience show --harness echo

# Reset circuit breaker (manual override)
hermes h3 resilience reset --harness echo

# Configure thresholds
hermes h3 resilience config --harness echo \
  --process-timeout 45 \
  --failure-threshold 7

# Simulate failover (testing only)
hermes h3 resilience test --harness echo --scenario process-timeout
```

---

## 12. Test Plan

### Unit Tests (RES-01 through RES-15)

| ID | Test | Category |
|----|------|----------|
| RES-01 | Circuit breaker opens after N consecutive failures | Circuit Breaker |
| RES-02 | Circuit breaker transitions OPEN → HALF_OPEN after cooldown | Circuit Breaker |
| RES-03 | HALF_OPEN → CLOSED after M consecutive successes | Circuit Breaker |
| RES-04 | HALF_OPEN → OPEN on probe failure with exponential backoff | Circuit Breaker |
| RES-05 | Process timeout triggers fallback with retry | Timeout |
| RES-06 | Connect timeout triggers immediate FALLBACK (no retry) | Timeout |
| RES-07 | Session state fully preserved during native migration | Fallback |
| RES-08 | User receives one-time notification on fallback | Fallback |
| RES-09 | Backpressure queue drops decisions when full | Backpressure |
| RES-10 | X-H3-Backpressure header sent at 75% queue | Backpressure |
| RES-11 | Partial response extraction: decisions present | Degradation |
| RES-12 | Partial response extraction: text-only response | Degradation |
| RES-13 | Cold start doubles first-request timeout | Cold Start |
| RES-14 | Health re-check loop detects harness recovery | Recovery |
| RES-15 | Bulk session migration migrates all active sessions | Fallback |

### Integration Tests (RES-I-01 through RES-I-08)

| ID | Test | Description |
|----|------|-------------|
| RES-I-01 | Full fallback: harness crash mid-conversation | Kill harness process, verify session continues natively |
| RES-I-02 | Circuit breaker end-to-end | 5 consecutive process timeouts → circuit opens → new sessions route native → health re-check → circuit closes → new sessions route H3 |
| RES-I-03 | Backpressure propagation | Flood harness with decisions, verify queue drops + headers sent |
| RES-I-04 | Session state integrity | Full conversation (10 turns) migrated; verify all messages present |
| RES-I-05 | Recovery notification | Admin alert sent when circuit opens (OBS-06 integration) |
| RES-I-06 | Cold start warm-up probe | Register new harness, verify warm-up probe before routing |
| RES-I-07 | Mid-session re-migration prevention | Harness recovers mid-session; verify existing session stays native |
| RES-I-08 | Config hot-reload | Change timeout at runtime, verify next request uses new value |

### Performance Tests (RES-P-01 through RES-P-03)

| ID | Test | Target |
|----|------|--------|
| RES-P-01 | Fallback latency | < 500ms from timeout detection to native loop start |
| RES-P-02 | Circuit breaker overhead | < 1µs per `allow_request()` call |
| RES-P-03 | Bulk migration throughput | 100 active sessions migrated in < 5s |

---

## 13. Migration Plan

### Phase 1: Shim Core (shim/)

1. Implement `resilience.py`: `CircuitBreaker`, `TimeoutDetector`, `SessionMigrator`
2. Wire into `shim_loop.py`: wrap every harness call with timeout + circuit breaker
3. Unit tests: RES-01 through RES-15
4. Integration: simulate harness crash, verify fallback

### Phase 2: SDK Middleware (sdk-go/ + sdk-python/ + sdk-typescript/)

1. Implement `ResilienceMiddleware` in all 3 SDKs per §10
2. Add `HARNESS_TIMEOUT` error code to protocol spec
3. Integration: harness-side timeout with circuit breaker
4. Unit tests per SDK

### Phase 3: Protocol Update (protocol/)

1. Add resilience error codes: `HARNESS_TIMEOUT`, `HARNESS_UNREACHABLE`, `CIRCUIT_OPEN`, `FALLBACK_ACTIVE`
2. Add backpressure headers to OpenAPI spec
3. Version bump: v1.1 → v1.2

### Phase 4: Production Rollout

1. Enable in staging with echo harness
2. Chaos test: kill harness mid-conversation, verify 30s session survival
3. Monitor fallback rate, circuit breaker trips
4. Gradual rollout to production harnesses

---

## 14. Security Considerations

- **Fallback preserves auth context:** Native loop uses same API key, same session permissions after migration
- **No credential exposure in logs:** Timeout/failure messages log harness_id + session_id only — no tokens
- **Circuit breaker state is local:** No cross-harness information leak (one harness failure doesn't reveal another's state)
- **Admin reset requires authentication:** `hermes h3 resilience reset` validates operator credentials per S12 §5.2

---

## Cross-References

- **S02 (Protocol):** Timeout headers are protocol-level extensions
- **S06 (Hermes Core):** Native loop invocation is Hermes' built-in agent
- **S12 (Security):** Admin reset authentication, token preservation during fallback
- **S15 (Rate Limiting):** Backpressure complements rate limiting
- **S16 (Structured Logging):** All resilience events use canonical 13-field format with `session_id`, `trace_id`, `decision_id`
- **S17 (Metrics):** `h3.fallback.count`, `h3.circuit_breaker.state` metrics
- **S18 (Distributed Tracing):** Same trace_id spans harness → native phases
- **S19 (Health Check v2):** Health re-check uses v2 endpoint for capabilities + component status
- **S20 (Dashboard):** Dashboard shows circuit breaker state per harness + active fallback sessions
- **OBS-06 (Alerting):** Circuit open triggers admin alert via configured notification channel

---

*Spec S21 — v1.0.0. RES-01 through RES-07 collapsed into single architecture spec. Implementation order: Shim → SDKs → Protocol → Production. 15 unit + 8 integration + 3 performance tests.*
