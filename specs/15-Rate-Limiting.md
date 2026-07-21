# S15 — H3 Rate Limiting (SEC-07 Implementation Spec)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S12 (Security & Authentication §4 — Layer 3)  
**Last Updated:** 2026-07-21

---

## 1. Overview

S12 defines rate limiting as Layer 3 of the defense-in-depth architecture:

```
Per-harness: max decisions/sec, burst allowance.
Per-session: max turns, max cost.
Global: Hermes-wide rate cap.
```

This document provides the **implementation-level specification** — exact algorithm, configuration schema, HTTP semantics, CLI surface, SDK middleware contracts, and test scenarios.

**Design principle:** "Fail open under load, fail closed under abuse." Rate limiting protects the platform from runaway harnesses and resource exhaustion, but it must never silently drop legitimate user messages. Every rejection carries diagnostic headers so the caller can adapt.

**Scope:** SEC-07 on the task board. Complements S12 §4; does not replace it.

**Implementation targets:**
- `shim/` — Rate limiter engine (`h3/rate_limiter.py`), CLI commands (`rate-limit show`, `rate-limit set`)
- `protocol/` — New error code `RATE_LIMITED` + response schema
- `sdk-go/`, `sdk-python/`, `sdk-typescript/` — Rate limit header parsing in middleware (advisory, not enforcement — enforcement is Hermes-side)

---

## 2. Rate Limit Architecture

### 2.1 Three Tiers

```
┌─────────────────────────────────────────────────────────────┐
│ TIER 1: Global (Hermes-wide)                                │
│ Protects Hermes from total overload.                        │
│ Hard cap: max total decisions/sec across ALL harnesses.     │
│ When hit: 503 Service Unavailable (Hermes is saturated).    │
├─────────────────────────────────────────────────────────────┤
│ TIER 2: Per-Harness                                         │
│ Isolates harnesses from each other.                         │
│ Token bucket per registered harness.                        │
│ When hit: 429 Too Many Requests + Retry-After.              │
├─────────────────────────────────────────────────────────────┤
│ TIER 3: Per-Session                                         │
│ Prevents runaway sessions.                                  │
│ Max turns (decisions) per session. Max total cost.          │
│ When hit: Session terminated with H3Decision(type=end).     │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Tier Precedence

Tiers are evaluated top-down. Tier 1 is checked first — if the global cap is hit, Tier 2 and 3 are never reached. If Tier 1 passes, Tier 2 is checked per-harness. If Tier 2 passes, Tier 3 is checked per-session.

```
Request arrives
  │
  ├── TIER 1: Global rate check
  │     Within global cap?
  │     No? → 503 + Retry-After
  │
  ├── TIER 2: Harness rate check
  │     Token available in this harness's bucket?
  │     No? → 429 + Retry-After + rate limit headers
  │
  ├── TIER 3: Session rate check
  │     Within session turn limit?
  │     No? → H3Decision(type=end) + error "SESSION_TURN_LIMIT"
  │     Within session cost budget?
  │     No? → H3Decision(type=end) + error "SESSION_COST_LIMIT"
  │
  └── ✓ Passed → dispatch to harness
```

---

## 3. Token Bucket Algorithm (Tier 2 — Per-Harness)

### 3.1 Algorithm

Classic token bucket with configurable rate and burst:

```
State per harness:
  tokens:     float   // current token count (0 to burst)
  last_refill: float  // monotonic timestamp of last refill (time.monotonic())

Parameters:
  rate:       float   // tokens added per second (decisions/sec)
  burst:      float   // maximum token capacity (burst allowance)

On request:
  1. now = time.monotonic()
  2. elapsed = now - last_refill
  3. tokens = min(burst, tokens + elapsed * rate)
  4. last_refill = now
  5. if tokens >= 1.0:
       tokens -= 1.0
       return ALLOW
     else:
       retry_after = (1.0 - tokens) / rate  // seconds until next token
       return DENY(retry_after)
```

**Why token bucket over sliding window:**
- Token bucket naturally handles bursts — a harness that's idle for 10 seconds builds up 10 × rate tokens
- Sliding window is either too strict (no bursts) or too permissive (counters reset at window boundaries)
- Token bucket is the industry standard (AWS API Gateway, Stripe, GitHub all use it)

### 3.2 Default Values

| Parameter | Default | Rationale |
|---|---|---|
| `rate` | 10 decisions/sec | One human types ~0.3 messages/sec. 10/sec covers 30× burst headroom for tool-call loops |
| `burst` | 30 | Three seconds of burst at default rate. Covers `delegate_task` fan-out (10+ concurrent decisions) |
| `rate` (testing) | 100 | `h3-test` runs 43 decisions in <0.5s. 100/sec ensures no false-positive rate limiting during CI |

### 3.3 Edge Cases

| Scenario | Behavior |
|---|---|
| Harness just registered (zero tokens) | Starts with `burst` tokens (full bucket). No cold-start penalty. |
| Harness idle for hours | Tokens capped at `burst` (not infinite). Prevents burst-of-doom after long idle. |
| Harness consistently above rate | Bucket drains to zero. Every subsequent request gets 429. |
| Token refill between requests (< 1ms) | Floating-point precision handles sub-millisecond refill. No minimum granularity. |
| System clock jumps backward | `time.monotonic()` is immune to clock adjustments. NTP/leap seconds don't affect it. |

---

## 4. Configuration

### 4.1 Hermes Configuration (`.hermes/h3/config.yaml`)

```yaml
rate_limiting:
  # Tier 1: Global Hermes-wide cap
  global:
    enabled: true
    max_decisions_per_second: 100   # 0 = unlimited
    burst: 200                       # Global burst allowance

  # Tier 2: Per-harness defaults (overridable per harness)
  harness_defaults:
    enabled: true
    decisions_per_second: 10        # Token bucket rate
    burst: 30                        # Token bucket capacity

  # Tier 3: Per-session limits
  session:
    enabled: true
    max_turns: 100                  # Max decisions per session
    max_cost_dollars: 5.00          # Max cumulative cost per session
    max_duration_seconds: 3600      # Max session lifetime (1 hour)

  # Per-harness overrides
  harness_overrides:
    consensus:                       # Harness name
      decisions_per_second: 5       # Lower rate for expensive harness
      burst: 10
    echo-harness:
      decisions_per_second: 50      # Higher rate for lightweight echo
      burst: 100
```

### 4.2 Harness Registration Overrides

When registering a harness via `hermes h3 register`, rate limits can be set:

```bash
hermes h3 register --url http://localhost:9191 \
  --rate-limit 20 \
  --rate-burst 50 \
  --max-turns 200
```

These override `harness_defaults` and are stored in `.hermes/h3/harnesses/<id>.yaml`.

### 4.3 Dynamic Reconfiguration

Rate limits can be changed at runtime without restarting Hermes:

```bash
hermes h3 rate-limit set --harness consensus --rate 15 --burst 40
hermes h3 rate-limit set --global --rate 200
hermes h3 rate-limit show --harness consensus
```

Changes take effect immediately on the next request. No session disruption.

---

## 5. HTTP Semantics

### 5.1 Response Headers (on every request)

Hermes adds rate limit headers to every response, whether or not the limit was hit:

```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 10          # Max decisions/sec for this harness
X-RateLimit-Remaining: 7.3     # Tokens remaining (float, 0 to burst)
X-RateLimit-Reset: 0.27        # Seconds until bucket refills to burst
X-RateLimit-Harness: consensus # Which harness this applies to
```

**When rate limited (429):**

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 0.85               # Seconds until next token available
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 0.0
X-RateLimit-Reset: 3.0
X-RateLimit-Harness: consensus
Content-Type: application/json

{
  "error": {
    "code": "RATE_LIMITED",
    "message": "Harness 'consensus' exceeded rate limit (10 decisions/sec). Retry in 0.85s.",
    "details": {
      "harness": "consensus",
      "limit": 10,
      "remaining": 0.0,
      "retry_after_seconds": 0.85,
      "tier": "harness"
    }
  }
}
```

**When globally rate limited (503):**

```http
HTTP/1.1 503 Service Unavailable
Retry-After: 1.5
Content-Type: application/json

{
  "error": {
    "code": "GLOBAL_RATE_LIMITED",
    "message": "Hermes global rate limit reached (100 decisions/sec). Retry in 1.5s.",
    "details": {
      "tier": "global",
      "retry_after_seconds": 1.5
    }
  }
}
```

### 5.2 Rate Limit Headers Specification

| Header | Type | Always Present? | Description |
|---|---|---|---|
| `X-RateLimit-Limit` | integer | Yes | Max decisions/sec for this harness |
| `X-RateLimit-Remaining` | float | Yes | Tokens currently in bucket (0 to burst) |
| `X-RateLimit-Reset` | float | Yes | Seconds until bucket refills to burst at current rate |
| `X-RateLimit-Harness` | string | Yes (Tier 2) | Harness name this limit applies to |
| `Retry-After` | integer/float | Only on 429/503 | Seconds to wait before retrying |

### 5.3 SDK Middleware Contract

SDK harnesses SHOULD parse these headers for diagnostics but MUST NOT enforce rate limits. Enforcement is Hermes-side. The harness's responsibility is to return decisions promptly — if Hermes is rate-limiting, the harness won't receive requests until the limit resets.

**Go SDK middleware:**
```go
// RateLimitInfo is parsed from response headers after calling Hermes.
type RateLimitInfo struct {
    Limit     float64 // X-RateLimit-Limit
    Remaining float64 // X-RateLimit-Remaining
    Reset     float64 // X-RateLimit-Reset
    Harness   string  // X-RateLimit-Harness
}

// ParseRateLimitHeaders extracts rate limit info from HTTP response headers.
func ParseRateLimitHeaders(h http.Header) RateLimitInfo
```

**Python SDK middleware:**
```python
@dataclass
class RateLimitInfo:
    limit: float       # X-RateLimit-Limit
    remaining: float   # X-RateLimit-Remaining
    reset: float       # X-RateLimit-Reset
    harness: str       # X-RateLimit-Harness

def parse_rate_limit_headers(headers: dict[str, str]) -> RateLimitInfo:
    ...
```

**TypeScript SDK middleware:**
```typescript
interface RateLimitInfo {
  limit: number;      // X-RateLimit-Limit
  remaining: number;  // X-RateLimit-Remaining
  reset: number;      // X-RateLimit-Reset
  harness: string;    // X-RateLimit-Harness
}

function parseRateLimitHeaders(headers: Headers): RateLimitInfo;
```

---

## 6. CLI Commands

### 6.1 `hermes h3 rate-limit show`

Display current rate limit configuration.

```bash
hermes h3 rate-limit show [--harness <name>] [--json]
```

**Without `--harness`:** Shows global + defaults + all harness overrides.

```
$ hermes h3 rate-limit show

  Global Rate Limit
    Max decisions/sec: 100 (burst: 200)
    Status: enabled

  Harness Defaults
    Decisions/sec: 10 (burst: 30)
    Max turns/session: 100
    Max cost/session: $5.00
    Max session duration: 3600s

  Harness Overrides
    consensus: 5/sec (burst: 10)
    echo-harness: 50/sec (burst: 100)
```

**With `--harness <name>`:** Shows current bucket state for that harness.

```
$ hermes h3 rate-limit show --harness consensus

  Harness: consensus
    Rate: 5.0 decisions/sec
    Burst: 10.0
    Current tokens: 8.3
    Requests today: 1,247
    429s today: 0
```

### 6.2 `hermes h3 rate-limit set`

Change rate limits at runtime.

```bash
hermes h3 rate-limit set --harness <name> [--rate <n>] [--burst <n>]
hermes h3 rate-limit set --global [--rate <n>] [--burst <n>]
hermes h3 rate-limit set --defaults [--rate <n>] [--burst <n>] [--max-turns <n>]
```

**Examples:**
```bash
# Slow down an expensive harness
hermes h3 rate-limit set --harness consensus --rate 3 --burst 8

# Raise global cap during load test
hermes h3 rate-limit set --global --rate 500

# Change session defaults
hermes h3 rate-limit set --defaults --max-turns 200 --max-cost 10.00
```

### 6.3 `hermes h3 rate-limit reset`

Reset token bucket counters for a harness (useful after a burst of 429s during debugging).

```bash
hermes h3 rate-limit reset --harness <name>
hermes h3 rate-limit reset --all   # Reset ALL harness buckets
```

```
$ hermes h3 rate-limit reset --harness consensus
  ✓ Reset token bucket for 'consensus' (refilled to burst: 10.0)
```

---

## 7. Session Limits (Tier 3)

### 7.1 Turn Limit

Each session has a maximum number of decisions. When reached:

1. Hermes sends a final `POST /v1/process` with `session_state.finished=true`
2. The harness receives `finished=true` as a signal to clean up
3. No further turns are dispatched for this session
4. Session is marked `completed` in Hermes

**Error for in-session messages:** If more messages arrive for a session that hit its turn limit, Hermes processes them natively (bypassing H3) with a diagnostic note.

### 7.2 Cost Budget

Each session has a maximum cumulative cost. Cost is calculated per-decision based on the model used:

```
decision_cost = model_cost_per_token × (input_tokens + output_tokens)
session_cost += decision_cost
```

When the cost budget is exceeded mid-session:
1. Current decision completes normally
2. Next request triggers `H3Decision(type=end)` with `error="SESSION_COST_LIMIT"`
3. Session terminates

**Model cost table** (loaded from `~/.hermes/costs.yaml` or provider metadata):

| Model | Cost per 1K input tokens | Cost per 1K output tokens |
|---|---|---|
| deepseek-v4-flash | $0.00014 | $0.00028 |
| deepseek-v4-pro | $0.00055 | $0.00110 |
| gpt-5.6-sol | $0.00300 | $0.01200 |

### 7.3 Duration Limit

Sessions have a maximum wall-clock lifetime. When exceeded:
1. Hermes sends `POST /v1/process` with `session_state.finished=true` and `error="SESSION_DURATION_LIMIT"`
2. No further turns
3. Harness receives the signal and cleans up

---

## 8. Implementation: Rate Limiter Engine

### 8.1 Python Implementation (`shim/h3/rate_limiter.py`)

```python
import time
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class TokenBucket:
    """Per-harness token bucket for rate limiting."""
    rate: float        # tokens/second
    burst: float       # max tokens
    tokens: float = 0.0
    last_refill: float = 0.0

    def __post_init__(self):
        self.tokens = self.burst  # start full
        self.last_refill = time.monotonic()

    def consume(self, n: float = 1.0) -> tuple[bool, float]:
        """Try to consume n tokens. Returns (allowed, retry_after_seconds)."""
        now = time.monotonic()
        elapsed = now - self.last_refill
        self.tokens = min(self.burst, self.tokens + elapsed * self.rate)
        self.last_refill = now

        if self.tokens >= n:
            self.tokens -= n
            return True, 0.0
        else:
            retry_after = (n - self.tokens) / self.rate
            return False, retry_after

    def reset(self):
        """Refill bucket to burst."""
        self.tokens = self.burst
        self.last_refill = time.monotonic()


@dataclass
class RateLimiter:
    """Three-tier rate limiter for H3."""

    # Tier 1: Global
    global_enabled: bool = True
    global_rate: float = 100.0
    global_burst: float = 200.0
    global_bucket: TokenBucket = field(init=False)

    # Tier 2: Per-harness
    harness_defaults: TokenBucket = field(init=False)
    harness_buckets: dict[str, TokenBucket] = field(default_factory=dict)

    # Tier 3: Per-session
    session_enabled: bool = True
    max_turns: int = 100
    max_cost_dollars: float = 5.00
    max_duration_seconds: int = 3600

    def __post_init__(self):
        self.global_bucket = TokenBucket(rate=self.global_rate, burst=self.global_burst)
        self.harness_defaults = TokenBucket(rate=10.0, burst=30.0)

    def check(self, harness_name: str, session_id: str,
              turn_count: int, session_start: float,
              cumulative_cost: float) -> dict:
        """
        Check all three tiers. Returns:
          {"allowed": True} or
          {"allowed": False, "tier": "global|harness|session",
           "retry_after": float, "error_code": str, "message": str}
        """
        # Tier 1: Global
        if self.global_enabled:
            ok, retry = self.global_bucket.consume()
            if not ok:
                return {
                    "allowed": False, "tier": "global",
                    "retry_after": retry,
                    "error_code": "GLOBAL_RATE_LIMITED",
                    "message": f"Global rate limit reached ({self.global_rate}/sec)"
                }

        # Tier 2: Harness
        bucket = self.harness_buckets.get(harness_name)
        if bucket is None:
            bucket = TokenBucket(
                rate=self.harness_defaults.rate,
                burst=self.harness_defaults.burst
            )
            self.harness_buckets[harness_name] = bucket
        ok, retry = bucket.consume()
        if not ok:
            return {
                "allowed": False, "tier": "harness",
                "retry_after": retry,
                "error_code": "RATE_LIMITED",
                "message": f"Harness '{harness_name}' rate limited ({bucket.rate}/sec)"
            }

        # Tier 3: Session
        if self.session_enabled:
            if turn_count >= self.max_turns:
                return {
                    "allowed": False, "tier": "session",
                    "error_code": "SESSION_TURN_LIMIT",
                    "message": f"Session turn limit reached ({self.max_turns})"
                }
            if cumulative_cost >= self.max_cost_dollars:
                return {
                    "allowed": False, "tier": "session",
                    "error_code": "SESSION_COST_LIMIT",
                    "message": f"Session cost limit reached (${self.max_cost_dollars:.2f})"
                }
            elapsed = time.monotonic() - session_start
            if elapsed >= self.max_duration_seconds:
                return {
                    "allowed": False, "tier": "session",
                    "error_code": "SESSION_DURATION_LIMIT",
                    "message": f"Session duration limit reached ({self.max_duration_seconds}s)"
                }

        return {"allowed": True}
```

### 8.2 Integration Point in Shim Loop

The rate limiter is checked in `shim_loop.py` BEFORE dispatching to the harness:

```python
# In H3ShimLoop._dispatch_to_harness():
def _dispatch_to_harness(self, session_id: str, message: dict) -> Decision:
    # Check rate limits before calling harness
    result = self.rate_limiter.check(
        harness_name=self.current_harness.name,
        session_id=session_id,
        turn_count=self._session_turns.get(session_id, 0),
        session_start=self._session_starts.get(session_id, time.monotonic()),
        cumulative_cost=self._session_costs.get(session_id, 0.0),
    )

    if not result["allowed"]:
        if result["tier"] == "session":
            # Session limit hit — end the session cleanly
            return H3Decision(type="end", error=result["error_code"])
        else:
            # Rate limited — retry, then fall back to native
            time.sleep(min(result["retry_after"], 1.0))
            return self._fallback_to_native(session_id, message, result["error_code"])

    # Proceed to harness
    return self._call_harness(session_id, message)
```

---

## 9. Protocol Schema Updates

### 9.1 New Error Code

Add to `protocol/schemas/v1/error.json`:

```json
{
  "error_codes": [
    ...existing codes...,
    "RATE_LIMITED",
    "GLOBAL_RATE_LIMITED",
    "SESSION_TURN_LIMIT",
    "SESSION_COST_LIMIT",
    "SESSION_DURATION_LIMIT"
  ]
}
```

### 9.2 Health Endpoint Extension

`GET /v1/health` response gains optional rate limit fields:

```json
{
  "status": "ok",
  "version": "1.0.0",
  ...
  "rate_limits": {
    "global": {"rate": 100, "burst": 200, "current_tokens": 87.3},
    "harness": {"rate": 10, "burst": 30, "current_tokens": 24.1}
  }
}
```

---

## 10. Test Scenarios

### 10.1 Unit Tests (`shim/tests/test_rate_limiter.py`)

| ID | Test | Expected |
|---|---|---|
| RL-01 | Token bucket starts full | `tokens == burst` |
| RL-02 | Single consume at rate | Returns ALLOW, tokens decremented |
| RL-03 | Exhaust bucket with rapid consumes | Returns DENY with retry_after > 0 |
| RL-04 | Refill after idle | Wait > 1/rate seconds, bucket refills proportional to elapsed time |
| RL-05 | Never exceeds burst | After long idle, tokens capped at burst |
| RL-06 | Zero rate | All consumes return DENY |
| RL-07 | Very high rate | All consumes return ALLOW |
| RL-08 | Global limit checked first | When global exhausted, harness bucket not touched |
| RL-09 | Session turn limit | Turn 100 → DENY with SESSION_TURN_LIMIT |
| RL-10 | Session cost limit | Cost $5.01 → DENY with SESSION_COST_LIMIT |
| RL-11 | Session duration limit | Elapsed 3601s → DENY with SESSION_DURATION_LIMIT |
| RL-12 | Harness-specific buckets isolated | Exhaust harness A, harness B still ALLOW |
| RL-13 | `reset()` refills bucket | tokens == burst after reset |
| RL-14 | Sub-millisecond refill | Two consumes in <1ms, second sees correct refill |
| RL-15 | `time.monotonic()` immune to clock jump | Bucket state consistent after system time change |

### 10.2 Integration Tests (`shim/tests/test_rate_limiter_integration.py`)

| ID | Test | Expected |
|---|---|---|
| RL-I-01 | 429 returned with correct headers | `X-RateLimit-Remaining: 0`, `Retry-After: N` |
| RL-I-02 | 503 returned on global exhaustion | 503 + `GLOBAL_RATE_LIMITED` error |
| RL-I-03 | Harness receives 429, Hermes retries | After Retry-After, request succeeds |
| RL-I-04 | CLI `rate-limit show` reflects current state | Output matches internal bucket state |
| RL-I-05 | CLI `rate-limit set` takes effect immediately | Next request uses new rate |
| RL-I-06 | Session termination on turn limit | Harness receives `finished=true` + `error=SESSION_TURN_LIMIT` |
| RL-I-07 | Session termination on cost limit | Harness receives `finished=true` + `error=SESSION_COST_LIMIT` |
| RL-I-08 | `h3-test` runs at elevated rate (100/sec) | All 43 tests pass without 429 |
| RL-I-09 | Rate limit disabled → no enforcement | `enabled: false` → all requests pass |

### 10.3 Performance Benchmarks

| ID | Test | Target |
|---|---|---|
| RL-P-01 | Token bucket check latency | < 1μs per check |
| RL-P-02 | Rate limiter with 1000 harnesses | < 10μs per check |
| RL-P-03 | Memory per harness bucket | < 100 bytes |

---

## 11. Performance Considerations

### 11.1 Lock Contention

The rate limiter is called on every request. Under high concurrency, the token bucket's `consume()` method must be thread-safe.

**Python (single-threaded Hermes):** No lock needed. The shim loop processes one request at a time.

**Go/TypeScript (multi-threaded harnesses):** Use `sync.Mutex` (Go) or `Atomics` (TS). The critical section is ~10 floating-point operations — lock contention is negligible.

### 11.2 Memory

Each registered harness has one `TokenBucket` struct (~64 bytes: 4× float64 + metadata). 10,000 harnesses = 640KB. Negligible.

### 11.3 Floating-Point Precision

Token bucket uses `float64`. At 10 tokens/sec over 30 days:
- Total tokens consumed: 10 × 86400 × 30 = 25,920,000
- Float64 precision: ~15 significant digits
- Error accumulation: < 1 nanosecond of drift over 30 days → effectively zero

---

## 12. Monitoring & Observability

### 12.1 Metrics (OBS Phase)

When OBS-02 (metrics) is implemented, the rate limiter exposes:

| Metric | Type | Labels |
|---|---|---|
| `h3_rate_limit_checks_total` | Counter | `tier`, `harness`, `result` |
| `h3_rate_limit_denials_total` | Counter | `tier`, `harness`, `error_code` |
| `h3_rate_limit_bucket_tokens` | Gauge | `harness` |
| `h3_rate_limit_global_tokens` | Gauge | — |
| `h3_session_turns` | Gauge | `session_id` |
| `h3_session_cost_dollars` | Gauge | `session_id` |

### 12.2 Logging

Rate limit events are logged at WARNING level:

```
[WARN] h3.rate_limiter: harness='consensus' rate limited (5.0/sec), retry_after=0.85s
[WARN] h3.rate_limiter: global rate limit reached (100/sec), 503 returned
[INFO] h3.rate_limiter: session='s_abc123' turn limit reached (100), ending session
```

---

## 13. Security Considerations

### 13.1 Rate Limit Bypass via Harness Name

A malicious user could register multiple harnesses to bypass per-harness limits. **Mitigation:** The global tier (Tier 1) caps total throughput regardless of harness count. Individual harness registration requires Hermes-side authentication.

### 13.2 Slowloris via Long-Running Decisions

A harness returning decisions slowly ties up the rate limiter but doesn't consume tokens. **Mitigation:** The shim loop already has a 30s timeout per harness call (QV-SHIM-03). Slow harnesses are marked degraded.

### 13.3 Token Bucket State After Hermes Restart

Token bucket state is in-memory. After Hermes restart, all buckets refill to `burst`. An attacker could exploit this by timing attacks around restarts. **Mitigation:** The global tier prevents total overload. Session limits (Tier 3) are independent of restart. If needed, persist bucket state to disk in a future version.

---

## 14. Migration & Backward Compatibility

### 14.1 Existing Harnesses

Harnesses registered before this spec are unaffected. Their rate limits default to `harness_defaults` (10/sec, burst 30). No configuration changes needed.

### 14.2 Protocol Version

No protocol version bump required. Rate limit headers are additive — harnesses that don't parse them are unaffected. The 429/503 responses follow standard HTTP semantics.

### 14.3 Disabling Rate Limiting

For development or testing:

```bash
hermes h3 rate-limit set --global --rate 0   # 0 = unlimited
```

Or in config:
```yaml
rate_limiting:
  global:
    enabled: false
  harness_defaults:
    enabled: false
  session:
    enabled: false
```

---

*Spec written 2026-07-21. Token bucket algorithm adapted from AWS API Gateway rate limiting design. Three-tier architecture from S12 §4 Layer 3 definition.*
