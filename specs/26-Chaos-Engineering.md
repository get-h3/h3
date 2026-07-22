# S26 — H3 Chaos Engineering (CHAOS-01 through CHAOS-04)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S02 (Protocol), S06 (Hermes Core Integration), S12 (Security & Auth), S16 (Structured Logging), S17 (Metrics), S18 (Distributed Tracing), S21 (Resilience & Fallback)  
**Last Updated:** 2026-07-22

---

## 1. Overview

H3's resilience architecture (S21) defines the safety net: timeouts, fallback, circuit breakers. But a safety net is only as good as the tests that prove it works. Chaos engineering systematically injects faults into the Hermes↔harness communication path and verifies that the system degrades gracefully — never loses data, never panics, never leaves the user stranded.

**This spec defines:** a chaos engineering framework for H3: fault injection primitives, 4 chaos experiment categories (network partition, malformed responses, out-of-sequence decisions, partial responses), a `chaos-proxy` reference implementation, test harnesses that simulate harness-side failures, verification criteria, and CI integration.

**Design principle:** "If it hasn't been broken on purpose, it's not proven to work. Every resilience claim in S21 must survive its corresponding chaos experiment."

**Scope:** CHAOS-01 through CHAOS-04 on the task board. This single S26 spec covers all 4 CHAOS tasks — they share the same fault-injection framework, the same chaos proxy architecture, and the same verification methodology.

**Implementation targets:**
- `shim/` — Chaos test runner, fault injection via `chaos-proxy` subprocess (`h3/chaos/`)
- `sdk-go/` — Malformed-response harness for CHAOS-02, CHAOS-03, CHAOS-04
- `sdk-python/` — Same harness patterns in Python
- `sdk-typescript/` — Same harness patterns in TypeScript
- `protocol/` — New chaos-specific error codes: CHAOS_INJECTED, MALFORMED_DECISION, OUT_OF_SEQUENCE

**Key outcomes:**
- **Every S21 claim has a chaos test:** timeout→CHAOS-01 (network partition), graceful degradation→CHAOS-04 (partial response)
- **Deterministic fault injection:** chaos-proxy intercepts TCP traffic with precise fault timing
- **CI-integrated:** chaos tests run as a separate CI workflow, not on every commit
- **Zero state corruption:** no chaos experiment can leave Hermes in an unrecoverable state

---

## 2. Chaos Architecture

### 2.1 Chaos Proxy

The `chaos-proxy` is a lightweight TCP forward proxy that sits between Hermes (Shim) and the harness. It passes traffic transparently unless a chaos rule matches. Chaos rules are JSON-serializable and can be injected at runtime via a control port.

```
Hermes (Shim) ──► chaos-proxy (:9190) ──► Harness (:9191)
                      ▲
                      │ control port (:9192)
                      │ POST /chaos/rules
                      │ DELETE /chaos/rules
```

**Chaos rule schema:**
```json
{
  "id": "chaos-rule-001",
  "name": "Network partition — 100% packet loss for 5s",
  "type": "latency|packet_loss|corrupt|drop|duplicate|reorder",
  "target": "process|result|health|all",
  "params": {
    "packet_loss_percent": 100,
    "duration_seconds": 5,
    "after_n_requests": 0
  },
  "enabled": true
}
```

**Rule types:**
| Type | Description | CHAOS Task |
|------|-------------|------------|
| `packet_loss` | Drop N% of packets | CHAOS-01 |
| `latency` | Add fixed or variable delay | CHAOS-01 |
| `corrupt` | Flip bits in response body | CHAOS-02 |
| `drop` | Drop entire connections or responses | CHAOS-01, CHAOS-04 |
| `reorder` | Reorder response packets | CHAOS-03 |
| `duplicate` | Send duplicate responses | CHAOS-03 |

**Lifecycle:** Rules are injected before a test scenario, active during the experiment, and cleared after verification. The proxy logs every injected fault with timestamp, rule ID, and matched request.

### 2.2 Chaos Test Runner

The Shim's chaos test runner (`h3/chaos/runner.py`) orchestrates experiments:

```python
class ChaosExperiment:
    id: str                    # e.g., "chaos-01-network-partition"
    description: str           # what fault is being injected
    rules: list[ChaosRule]     # fault injection rules
    setup: callable            # pre-experiment setup (start harness, proxy)
    scenario: callable         # the test scenario (send messages, verify behavior)
    assertions: list[callable] # post-experiment assertions
    timeout: int               # max experiment duration in seconds
```

**Execution flow:**
1. Start harness + chaos proxy (proxy between shim and harness)
2. Apply chaos rules via proxy control port
3. Run scenario (send messages through H3 protocol)
4. Verify assertions (harness state, Hermes state, logs, metrics, traces)
5. Clear rules, stop proxy, cleanup

### 2.3 Chaos Harnesses

Each CHAOS task needs a harness that generates specific malformed behavior:

| Chaos Task | Harness Type | What It Does |
|------------|-------------|--------------|
| CHAOS-01 | Normal echo | Real harness behind proxy. Proxy injects faults. |
| CHAOS-02 | Malformed responder | Returns JSON that violates protocol schema (missing fields, wrong types, extra fields) |
| CHAOS-03 | Out-of-sequence responder | Returns decisions in wrong order, duplicates decision_ids, returns type=result before type=process |
| CHAOS-04 | Partial responder | Sends incomplete HTTP response, hangs mid-response, sends truncated JSON |

All chaos harnesses are variants of the echo harness with configurable fault modes.

---

## 3. CHAOS-01: Network Partition

### 3.1 Objective
Verify that Hermes detects harness unreachability, falls back to native loop, preserves session state, and auto-recovers when the harness returns.

### 3.2 Fault Injection — `packet_loss` + `latency`

**Experiment 1: Transient partition (100% loss, 5s)**
- Start normal session through echo harness
- Inject 100% packet loss on all traffic for 5 seconds
- Expect: Shim times out on next request → falls back to native loop
- Verify: Session continues without data loss, user receives response (via native loop)
- Verify: Logs show `event=harness_timeout → event=fallback_to_native`

**Experiment 2: Prolonged partition (100% loss, 60s)**
- Start session, inject 100% packet loss for 60s
- Expect: Circuit breaker opens after N consecutive timeouts (per S21 §5)
- Verify: Health checks fail, harness marked `DEGRADED`
- After 60s: clear fault, wait for health re-check
- Expect: Health check passes → harness re-enabled

**Experiment 3: Variable latency (100ms, 500ms, 2s, 10s delay)**
- Start session, inject increasing latency on process endpoint
- Verify: Each delay <harness_timeout_ms → response received (slow but functional)
- Verify: Delay >harness_timeout_ms → timeout → fallback
- Verify: Latency metrics (S17) capture the spike

**Experiment 4: Partial partition (50% packet loss)**
- Start session, inject 50% packet loss
- Expect: Some requests succeed, some time out. Retries recover.
- Verify: No circuit breaker trips (error rate <50% threshold per S21 §5)
- Verify: Session completes successfully using retries

### 3.3 Assertions
- Session state (messages, context) preserved across fallback
- No duplicate messages delivered to user
- S16 structured logs show complete trace across hops
- S17 metrics capture: `harness_timeout_count`, `fallback_count`, `circuit_breaker_open`
- S18 traces show the faulted hop with `error=true` on the span
- Native loop picks up immediately — no user-perceived gap >2s

### 3.4 Test Scenarios (CHAOS-01-01 through CHAOS-01-08)

| ID | Scenario | Fault | Expected Behavior |
|----|----------|-------|-------------------|
| CHAOS-01-01 | Mid-conversation 5s blackout | packet_loss=100%, 5s | Fallback, session continues, no data loss |
| CHAOS-01-02 | Session start with dead harness | packet_loss=100%, startup | Immediate native loop, no session created on harness |
| CHAOS-01-03 | 60s partition → circuit breaker | packet_loss=100%, 60s | Breaker opens, auto-recovery after health check passes |
| CHAOS-01-04 | Variable latency within budget | latency=50ms,100ms,200ms | All requests succeed (latency <harness_timeout) |
| CHAOS-01-05 | Latency spike exceeds budget | latency=5s | Timeout → fallback on that request |
| CHAOS-01-06 | 50% loss — retry survives | packet_loss=50% | Retries succeed, session completes |
| CHAOS-01-07 | Partition during result delivery | packet_loss on POST /result | Shim retries, session not stranded |
| CHAOS-01-08 | Health check during partition | packet_loss on GET /health | Health marks harness DEGRADED, doesn't affect active sessions |

---

## 4. CHAOS-02: Malformed Decisions

### 4.1 Objective
Verify that Hermes handles protocol violations gracefully — malformed JSON, missing required fields, wrong types, invalid decision types. Hermes must never crash, never pass malformed data to the user, and produce actionable error traces.

### 4.2 Fault Injection — `corrupt` + Malformed Harness

The CHAOS-02 harness is a configurable test harness that returns intentionally malformed responses:

```python
class MalformedHarness(EchoHarness):
    fault_mode: str  # "missing_field" | "wrong_type" | "extra_field" | "invalid_json" | "empty_response"

    def process(self, request: ProcessRequest) -> Decision:
        if self.fault_mode == "missing_field":
            return {"type": "text"}  # missing 'text' field
        elif self.fault_mode == "wrong_type":
            return {"type": "text", "text": 42}  # text should be string
        elif self.fault_mode == "extra_field":
            return {"type": "text", "text": "hello", "__malicious": True}
        elif self.fault_mode == "invalid_json":
            # Return non-JSON response body
            return "this is not JSON"
        elif self.fault_mode == "empty_response":
            # Return HTTP 200 with empty body
            return ""
```

**Experiment 1: Missing required field**
- Harness returns `{"type": "text"}` (no `text` field)
- Expect: Shim validation rejects → logs `event=decision_validation_failed, error=missing_field:text`
- Expect: Shim falls back to native loop for this turn
- Verify: User gets a response (via native), not silence

**Experiment 2: Wrong field type**
- Harness returns `{"type": "text", "text": 42}`
- Expect: Pydantic/Zod validation rejects `text` as wrong type
- Expect: Logged with `error=type_mismatch:text:expected_string_got_integer`
- Verify: No crash, session continues

**Experiment 3: Unknown decision type**
- Harness returns `{"type": "launch_nukes", "target": "moon"}`
- Expect: Shim rejects unknown `type` → logged as `error=unknown_decision_type:launch_nukes`
- Expect: Falls back to native for this turn

**Experiment 4: Non-JSON response body**
- Harness returns plain text `"not json"`
- Expect: Shim JSON parser catches → `error=json_parse_error`
- Verify: HTTP 502 returned to Hermes properly, not a raw traceback

**Experiment 5: HTTP 500 with JSON error body**
- Harness returns HTTP 500 with `{"error": "internal", "detail": "database down"}`
- Expect: Shim treats as harness failure → fallback
- Verify: Harness error detail preserved in logs (no data loss)

**Experiment 6: Garbage binary response**
- Harness returns random bytes (0x00-0xFF)
- Expect: Shim handles UTF-8 decode failure
- Verify: No crash, session survives

### 4.3 Assertions
- Shim never crashes on malformed responses (all experiments)
- Every malformation produces a structured error log event (S16)
- Pydantic/Zod validation catches schema violations before they reach decision execution
- Session falls back to native on unrecoverable malformations
- No malformed data leaked to user output

### 4.4 Test Scenarios (CHAOS-02-01 through CHAOS-02-10)

| ID | Scenario | Malformation | Expected Behavior |
|----|----------|-------------|-------------------|
| CHAOS-02-01 | Missing required text field | `{"type": "text"}` | Validation error, fallback |
| CHAOS-02-02 | Wrong type for text field | `{"type": "text", "text": 42}` | Type error, fallback |
| CHAOS-02-03 | Unknown decision type | `{"type": "unknown_type"}` | Unknown type error, fallback |
| CHAOS-02-04 | Non-JSON response | `"plain text"` | JSON parse error, HTTP 502 |
| CHAOS-02-05 | HTTP 500 with JSON body | 500 + `{"error": "..."}` | Harness failure, fallback |
| CHAOS-02-06 | Binary garbage response | random bytes | Decode error, no crash |
| CHAOS-02-07 | Extra/malicious fields | `{"type":"text","text":"ok","__hack":true}` | Extra field stripped, decision accepted |
| CHAOS-02-08 | Null fields | `{"type": null, "text": null}` | Type validation rejects |
| CHAOS-02-09 | Empty JSON object | `{}` | Missing type field, validation error |
| CHAOS-02-10 | Extremely deep nesting | `{"type":{"a":{"b":...}}}` | Pydantic depth guard or graceful truncation |

---

## 5. CHAOS-03: Out-of-Sequence Decisions

### 5.1 Objective
Verify that Hermes detects and recovers from decision sequencing errors: decisions arriving out of order, duplicate decision_ids, wrong state transitions, and protocol-level sequencing violations.

### 5.2 Fault Injection — Out-of-Sequence Harness

```python
class OutOfSequenceHarness(EchoHarness):
    fault_mode: str  # "early_end" | "duplicate_id" | "skip_process" | "double_result" | "id_mismatch"
    turn_counter: int = 0

    def process(self, request: ProcessRequest) -> Decision:
        self.turn_counter += 1
        if self.fault_mode == "early_end":
            # Return end on turn 1 instead of waiting for finished=true
            if self.turn_counter == 1:
                return {"id": "D001", "type": "end"}
            return super().process(request)
        elif self.fault_mode == "duplicate_id":
            return {"id": "D001", "type": "text", "text": f"turn {self.turn_counter}"}  # same id every turn
        elif self.fault_mode == "skip_process":
            # Return result without a preceding process
            if self.turn_counter == 1:
                return {"id": "D001", "type": "text", "text": "no process step"}
    ...
```

**Experiment 1: Early end (harness sends `type=end` before `finished=true`)**
- Harness returns `{"type": "end"}` on turn 1 without `finished=true` flag
- Expect: Shim checks if `finished=true` was sent by Hermes — it wasn't → treats as protocol violation
- Expect: Logged as `error=premature_end, decision_id=D001`
- Verify: Session does NOT end prematurely. Hermes continues.

**Experiment 2: Duplicate decision_ids**
- Harness returns same `decision_id` for multiple turns
- Expect: Shim detects duplicate → `error=duplicate_decision_id:D001`
- Expect: Shim falls back to native, generates new decision_id
- Verify: Session continues with unique IDs

**Experiment 3: Decision_id mismatch (harness returns id that doesn't match any pending request)**
- Harness returns a decision_id that Shim never sent
- Expect: Shim logs `error=unknown_decision_id:X999`
- Verify: Decision is discarded, session continues

**Experiment 4: Double result (harness sends two results for one process)**
- Harness sends two `type=result` decisions after one `process` request
- Expect: Second result is unexpected → `error=unexpected_result` logged
- Verify: First result is processed normally, second is discarded

**Experiment 5: Missing process step (harness sends result without process)**
- Harness sends `type=text` without a preceding `process` call
- Expect: Unclear — may indicate a bug in harness. Shim logs warning.
- Verify: No crash, decision processed as a standalone response

### 5.3 Assertions
- duplicate decision_ids detected and rejected
- premature end (before finished=true) caught and session preserved
- decision_id mismatch caught, no phantom decisions executed
- Session state machine never enters invalid state
- All sequencing errors produce structured logs with decision_id for traceability

### 5.4 Test Scenarios (CHAOS-03-01 through CHAOS-03-08)

| ID | Scenario | Sequence Error | Expected Behavior |
|----|----------|---------------|-------------------|
| CHAOS-03-01 | Premature end on turn 1 | type=end before finished=true | Premature end rejected, session continues |
| CHAOS-03-02 | Duplicate decision_ids | Same id across turns | Duplicate detected, fallback with new id |
| CHAOS-03-03 | Unknown decision_id | Harness returns unsent id | Decision discarded, warning logged |
| CHAOS-03-04 | Double result | Two results for one process | Second result discarded |
| CHAOS-03-05 | Missing process step | Result without process | Warning logged, decision processed |
| CHAOS-03-06 | Reversed order | result before process | Shim detects out-of-order, re-syncs |
| CHAOS-03-07 | Very large decision_id | id length > 256 chars | Accepted (protocol doesn't limit length) or truncated with warning |
| CHAOS-03-08 | Zero-length decision_id | `id: ""` | Validation rejects empty id |

---

## 6. CHAOS-04: Partial Response & Harness Hang

### 6.1 Objective
Verify that Hermes handles incomplete responses: truncated JSON, harness that hangs mid-response, slow streaming, and responses that arrive in fragments.

### 6.2 Fault Injection — Partial Responder Harness

```python
class PartialHarness(EchoHarness):
    fault_mode: str  # "hang_forever" | "hang_timeout" | "truncated_json" | "chunked_slow" | "close_mid_response"

    def process(self, request: ProcessRequest) -> Decision:
        if self.fault_mode == "hang_forever":
            import time
            time.sleep(999999)  # never returns
        elif self.fault_mode == "hang_timeout":
            time.sleep(self.harness_timeout_ms / 1000 + 1)  # just past timeout
        elif self.fault_mode == "truncated_json":
            # Send partial JSON then close connection
            return '{"type": "text", "text": "hel'  # truncated mid-string
        elif self.fault_mode == "close_mid_response":
            # Close TCP connection mid-response
            raise ConnectionAbortedError()
```

**Experiment 1: Harness hangs forever**
- Harness `sleep(999999)` on process request
- Expect: Shim hits `harness_timeout_ms` → falls back to native
- Verify: No goroutine/thread leak — timeout handler cleans up connection
- Verify: Subsequent requests to same harness use a new connection

**Experiment 2: Truncated JSON response**
- Harness sends `'{"type": "text", "text": "hel'` then closes
- Expect: Shim JSON parser detects truncated input → `error=json_truncated`
- Verify: Falls back to native, no partial response delivered to user

**Experiment 3: TCP connection close mid-response**
- Harness sends partial HTTP response then closes TCP
- Expect: Shim HTTP client catches connection error → `error=connection_reset`
- Verify: Session survives, fallback occurs

**Experiment 4: Chunked transfer encoding with slow chunks**
- Harness sends `Transfer-Encoding: chunked` with 100ms delay between chunks
- Each chunk is a fragment of valid JSON
- Expect: Shim assembles full response body across chunks
- Verify: Response is valid and complete after assembly

**Experiment 5: Harness returns HTTP 200 with Content-Length: 1000 but body is 10 bytes**
- Content-Length header lies about body size
- Expect: Shim HTTP client times out waiting for missing bytes or detects EOF
- Verify: `error=content_length_mismatch` logged, fallback

### 6.3 Assertions
- No goroutine/thread/memory leaks from abandoned connections (verify with soak test)
- All partial responses caught before reaching decision executor
- Connection pool (S22 §5) handles dead connections gracefully — removes from pool
- Timeout handler reliably fires — no "stuck forever" sessions
- S17 metrics capture: `harness_hang_count`, `partial_response_count`

### 6.4 Test Scenarios (CHAOS-04-01 through CHAOS-04-08)

| ID | Scenario | Partial Response | Expected Behavior |
|----|----------|-----------------|-------------------|
| CHAOS-04-01 | Harness hangs forever | sleep(∞) | Timeout → fallback, no resource leak |
| CHAOS-04-02 | Harness hangs past timeout | sleep(timeout+1s) | Timeout fires, session continues |
| CHAOS-04-03 | Truncated JSON | `{"type":"text","te` | JSON parse error, fallback |
| CHAOS-04-04 | TCP close mid-response | TCP RST after partial send | Connection error, fallback |
| CHAOS-04-05 | Slow chunked transfer | 100ms between chunks | Full response assembled, functional |
| CHAOS-04-06 | Content-Length mismatch | CL=1000, body=10 bytes | Timeout/EOF, error logged |
| CHAOS-04-07 | Harness hangs on /health | sleep(30s) on health endpoint | Health marks harness DEGRADED |
| CHAOS-04-08 | Rapid connect/disconnect cycle | 100 connections in 1s | Connection pool handles, no exhaustion |

---

## 7. SDK Harness Patterns

### 7.1 Go SDK — Chaos Harness Interface

```go
// ChaosMode configures the harness's fault injection behavior.
type ChaosMode string

const (
    ChaosModeNormal          ChaosMode = "normal"
    ChaosModeMissingField    ChaosMode = "missing_field"
    ChaosModeWrongType       ChaosMode = "wrong_type"
    ChaosModeUnknownType     ChaosMode = "unknown_type"
    ChaosModeNonJSON         ChaosMode = "non_json"
    ChaosModeTruncatedJSON   ChaosMode = "truncated_json"
    ChaosModeHang            ChaosMode = "hang"
    ChaosModeCloseMidResp    ChaosMode = "close_mid_response"
    ChaosModeEarlyEnd        ChaosMode = "early_end"
    ChaosModeDuplicateID     ChaosMode = "duplicate_id"
    ChaosModeUnknownID       ChaosMode = "unknown_id"
)

// ChaosConfig controls fault injection on the harness.
type ChaosConfig struct {
    Mode       ChaosMode        `json:"mode"`
    HangDuration time.Duration  `json:"hang_duration,omitempty"`
}
```

### 7.2 Python SDK — Chaos Harness Interface

```python
from enum import Enum

class ChaosMode(str, Enum):
    NORMAL = "normal"
    MISSING_FIELD = "missing_field"
    WRONG_TYPE = "wrong_type"
    UNKNOWN_TYPE = "unknown_type"
    NON_JSON = "non_json"
    TRUNCATED_JSON = "truncated_json"
    HANG = "hang"
    CLOSE_MID_RESPONSE = "close_mid_response"
    EARLY_END = "early_end"
    DUPLICATE_ID = "duplicate_id"
    UNKNOWN_ID = "unknown_id"

@dataclass
class ChaosConfig:
    mode: ChaosMode = ChaosMode.NORMAL
    hang_duration_seconds: float = 0.0
```

### 7.3 TypeScript SDK — Chaos Harness Interface

```typescript
export enum ChaosMode {
  Normal = "normal",
  MissingField = "missing_field",
  WrongType = "wrong_type",
  UnknownType = "unknown_type",
  NonJson = "non_json",
  TruncatedJson = "truncated_json",
  Hang = "hang",
  CloseMidResponse = "close_mid_response",
  EarlyEnd = "early_end",
  DuplicateId = "duplicate_id",
  UnknownId = "unknown_id",
}

export interface ChaosConfig {
  mode: ChaosMode;
  hangDurationMs?: number;
}
```

---

## 8. CLI Surface

### 8.1 Shim Commands

```bash
# Run all chaos experiments
hermes h3 chaos run --endpoint http://localhost:9191

# Run specific experiment category
hermes h3 chaos run --endpoint http://localhost:9191 --category network
hermes h3 chaos run --endpoint http://localhost:9191 --category malformed

# Run individual experiment
hermes h3 chaos run --endpoint http://localhost:9191 --experiment CHAOS-01-03

# Dry run — validate chaos rules without executing
hermes h3 chaos run --endpoint http://localhost:9191 --dry-run

# List available experiments
hermes h3 chaos list

# Output formats
hermes h3 chaos run --endpoint http://localhost:9191 --json   # JSON report
hermes h3 chaos run --endpoint http://localhost:9191 --html   # HTML report
```

### 8.2 Harness-Side Control

The chaos harnesses expose a control endpoint for runtime fault mode switching (useful for manual testing and CI):

```bash
# Set fault mode
curl -X POST http://localhost:9191/_chaos/mode -d '{"mode": "truncated_json"}'

# Get current fault mode
curl http://localhost:9191/_chaos/mode

# Clear fault mode (back to normal)
curl -X DELETE http://localhost:9191/_chaos/mode
```

The `/_chaos/*` endpoints are ONLY available when the harness is started with `--chaos-enabled`. They are not available in production mode.

---

## 9. CI Integration

Chaos experiments are resource-intensive (proxy processes, timing-dependent) and should NOT run on every commit. They run as a separate CI workflow:

```yaml
# .github/workflows/chaos.yml (in shim repo)
name: H3 Chaos Engineering
on:
  schedule:
    - cron: '0 6 * * *'   # Daily at 6 AM UTC
  workflow_dispatch:        # Manual trigger
  push:
    branches: [main]
    paths:
      - 'src/h3_shim/chaos/**'
      - 'specs/26-Chaos-Engineering.md'

jobs:
  chaos-network:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Run network partition experiments
        run: |
          pip install hermes-h3-shim
          hermes h3 chaos run --category network --json > chaos-network.json
      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: chaos-network-results
          path: chaos-network.json

  chaos-malformed:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Run malformed response experiments
        run: |
          pip install hermes-h3-shim
          hermes h3 chaos run --category malformed --json > chaos-malformed.json

  chaos-sequence:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Run out-of-sequence experiments
        run: |
          pip install hermes-h3-shim
          hermes h3 chaos run --category sequence --json > chaos-sequence.json

  chaos-partial:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Run partial response experiments
        run: |
          pip install hermes-h3-shim
          hermes h3 chaos run --category partial --json > chaos-partial.json

  chaos-report:
    needs: [chaos-network, chaos-malformed, chaos-sequence, chaos-partial]
    runs-on: ubuntu-latest
    steps:
      - name: Aggregate results
        run: |
          # Combine all JSON reports into one
          echo "Chaos experiments complete. See artifacts for per-category results."
```

**Gate:** Chaos CI is informational only (never blocks deploy). A failing chaos experiment creates a `CHAOS-REGRESSION` issue with the experiment ID and failure details.

---

## 10. Test Plan

### 10.1 Unit Tests (CHAOS-U-01 through CHAOS-U-12)

| ID | Test | Scope |
|----|------|-------|
| CHAOS-U-01 | ChaosRule JSON serialization/deserialization | Shim |
| CHAOS-U-02 | ChaosRule validation (invalid types, missing params) | Shim |
| CHAOS-U-03 | ChaosProxy starts on configurable port | Shim |
| CHAOS-U-04 | ChaosProxy passes traffic when no rules active | Shim |
| CHAOS-U-05 | ChaosProxy applies packet_loss rule correctly | Shim |
| CHAOS-U-06 | ChaosProxy applies latency rule correctly | Shim |
| CHAOS-U-07 | ChaosProxy applies corrupt rule (bit flip) correctly | Shim |
| CHAOS-U-08 | ChaosProxy control API: POST/DELETE /chaos/rules | Shim |
| CHAOS-U-09 | MalformedHarness returns correct fault mode | SDK-Go |
| CHAOS-U-10 | OutOfSequenceHarness returns duplicate IDs | SDK-Go |
| CHAOS-U-11 | PartialHarness truncates JSON correctly | SDK-Go |
| CHAOS-U-12 | Chaos mode disabled in production (no /_chaos endpoint) | SDK-Go |

### 10.2 Integration Tests (CHAOS-I-01 through CHAOS-I-12)

| ID | Test | Category | Scope |
|----|------|----------|-------|
| CHAOS-I-01 | 5s partition → fallback → session survives | Network | E2E |
| CHAOS-I-02 | 60s partition → circuit breaker → auto-recovery | Network | E2E |
| CHAOS-I-03 | Variable latency within budget → all succeed | Network | E2E |
| CHAOS-I-04 | Missing required field → validation error → fallback | Malformed | E2E |
| CHAOS-I-05 | Non-JSON response → parse error → fallback | Malformed | E2E |
| CHAOS-I-06 | Binary garbage → no crash, session survives | Malformed | E2E |
| CHAOS-I-07 | Duplicate decision_ids → detected, fallback | Sequence | E2E |
| CHAOS-I-08 | Premature end → rejected, session continues | Sequence | E2E |
| CHAOS-I-09 | Harness hang → timeout → fallback | Partial | E2E |
| CHAOS-I-10 | Truncated JSON → parse error → fallback | Partial | E2E |
| CHAOS-I-11 | TCP close mid-response → connection error → fallback | Partial | E2E |
| CHAOS-I-12 | Content-Length mismatch → timeout → error logged | Partial | E2E |

### 10.3 Performance Tests (CHAOS-P-01 through CHAOS-P-03)

| ID | Test | What It Measures |
|----|------|-----------------|
| CHAOS-P-01 | 1000-request soak under 10% packet loss | Memory stability, no goroutine/thread leak |
| CHAOS-P-02 | 100 harness hang/timeout cycles | Connection pool health, file descriptor count |
| CHAOS-P-03 | Chaos proxy throughput: 1000 req/s baseline | Proxy overhead <5% latency increase |

---

## 11. Error Codes

New protocol error codes for chaos-specific scenarios:

| Code | HTTP | Name | Meaning |
|------|------|------|---------|
| CHAOS_INJECTED | — | Chaos fault injected | Internal marker — never exposed to user. Used in logs/traces to identify chaos experiments. |
| MALFORMED_DECISION | 502 | Malformed decision from harness | Harness returned a decision that failed protocol validation (schema, type, sequencing). |
| OUT_OF_SEQUENCE | 502 | Decision out of expected sequence | Harness returned decisions in wrong order or with duplicate/unknown IDs. |
| DECISION_TRUNCATED | 502 | Decision response truncated | Harness response was incomplete — truncated JSON, closed connection, or Content-Length mismatch. |

These codes extend the error registry from S12 (§9) and S21 (§11).

---

## 12. Metrics & Observability

### 12.1 Chaos-Specific Metrics (S17 Extension)

| Metric | Type | Description |
|--------|------|-------------|
| `chaos_experiment_count` | Counter | Total chaos experiments executed |
| `chaos_experiment_duration_seconds` | Histogram | Experiment wall-clock time |
| `chaos_fault_injected_count` | Counter | Number of faults injected by chaos proxy |
| `chaos_assertion_pass_count` | Counter | Assertions that passed |
| `chaos_assertion_fail_count` | Counter | Assertions that failed |

### 12.2 Structured Logging (S16 Extension)

Every chaos experiment produces a log event with:
- `event=chaos_experiment_start` / `event=chaos_experiment_end`
- `experiment_id`, `category`, `fault_type`, `duration_ms`
- `assertions_total`, `assertions_passed`, `assertions_failed`
- `decision_id` — links chaos experiment to specific session turns

### 12.3 Distributed Tracing (S18 Extension)

Chaos proxy creates a span for each injected fault with `span.kind=CHAOS_INJECTION`. The fault span is a child of the HTTP request span, allowing correlation between injected faults and downstream behavior.

---

## 13. Security Considerations

| Threat | Mitigation |
|--------|-----------|
| Chaos proxy as attack vector | Only listens on localhost (127.0.0.1). Never exposed to network. |
| Chaos mode in production | `/_chaos/*` endpoints only available with `--chaos-enabled` flag. Production harnesses start without it. |
| Fault injection data leakage | Chaos rules are never persisted to disk. In-memory only. |
| CI token exposure | Chaos CI workflow uses repository secrets, same as other CI workflows. |

---

## 14. Migration Plan

### Phase 1: Chaos Framework (Shim)
- Implement `h3/chaos/proxy.py` — TCP forward proxy with rule engine
- Implement `h3/chaos/runner.py` — experiment orchestrator
- Implement `h3/chaos/rules.py` — rule types (packet_loss, latency, corrupt, drop)
- CLI: `hermes h3 chaos run/list`
- Unit tests: CHAOS-U-01 through CHAOS-U-08

### Phase 2: Chaos Harnesses (SDKs)
- Go SDK: `ChaosHarness` with all fault modes
- Python SDK: `ChaosHarness` with all fault modes
- TypeScript SDK: `ChaosHarness` with all fault modes
- `/_chaos/mode` control endpoint with `--chaos-enabled` gate
- Unit tests: CHAOS-U-09 through CHAOS-U-12

### Phase 3: Integration Tests
- CHAOS-I-01 through CHAOS-I-12 — full E2E experiments
- Each experiment: inject fault → run scenario → verify expected behavior
- CI workflow: `.github/workflows/chaos.yml`

### Phase 4: Performance & Production Readiness
- CHAOS-P-01 through CHAOS-P-03 — performance benchmarks
- Soak test: 1000 requests under 10% packet loss over 10 minutes
- Document chaos experiment results in project README
- Publish chaos score (passed/total experiments) as part of conformance badge (S25)

---

## 15. Cross-References

| Spec | Relationship |
|------|-------------|
| S02 (Protocol) | CHAOS-02 validates protocol schema enforcement |
| S12 (Security) | Chaos mode disabled in production; localhost-only proxy |
| S16 (Logging) | Chaos experiments produce structured log events |
| S17 (Metrics) | Chaos-specific metrics extend the metrics spec |
| S18 (Tracing) | Chaos proxy creates trace spans for injected faults |
| S21 (Resilience) | CHAOS-01 validates every S21 timeout/fallback/circuit-breaker claim |
| S25 (Conformance) | Chaos score becomes part of conformance badge |

---

*Spec complete. 15 sections, 34 chaos test scenarios, 3 SDK harness interfaces, full CI integration, 4-phase migration plan. This is the LAST spec — all 19 H3 phases now have complete specifications.*
