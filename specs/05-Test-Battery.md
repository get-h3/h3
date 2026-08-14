# S05 — Shim Test Battery

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Purpose

The H3 Test Battery is a **compliance suite** that verifies a harness correctly implements the H3 protocol. It runs against any harness endpoint — no harness code changes needed. Harness developers run it during development to catch protocol violations before connecting to real Hermes.

### Design Principle

> "When people make a new shim, they don't fight their agent. They run a script on the endpoint and it verifies what works and doesn't work in their harness."

---

## 2. Test Battery Architecture

```
Test Battery (src/h3_shim/test_battery.py)
  │
  │── HTTP client ──► Harness Endpoint (localhost:9191)
  │
  │── Runs 44 tests across 6 categories
  │── Produces JSON report + terminal output
  │── Exit code 0 = all passing, non-zero = failures
```

### Output Format

```
$ h3-test --endpoint http://localhost:9191

H3 Compliance Test Battery v1.0.0
Target: http://localhost:9191
Transport: REST

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Health & Protocol             7/7  ✅
  Process - Basic Flows         8/8  ✅
  Process - Decision Types      6/6  ✅
  Result Handling               7/7  ✅
  Error & Edge Cases           11/11 ✅
  Stress & Performance          5/5  ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TOTAL                        44/44 ✅  PASSED

Report: ~/.hermes/cache/h3_test_report_20260712_223000.json
```

---

## 3. Test Categories

### Category 1: Health & Protocol (7 tests)

| # | Test | What It Verifies |
|---|---|---|
| 1.1 | `health_ok` | `GET /v1/health` returns 200 with `status: "ok"` |
| 1.2 | `health_version` | Response includes `version` and `protocol_version` |
| 1.3 | `health_transport` | Response includes `transport` field |
| 1.4 | `health_capabilities` | `capabilities` array lists supported decision types |
| 1.5 | `health_content_type` | Response has `Content-Type: application/json` |
| 1.6 | `health_latency` | Response within 500ms (cold start allowed on first call) |
| 1.7 | `health_idempotent` | Two consecutive health checks return consistent `status` |

### Category 2: Process — Basic Flows (8 tests)

| # | Test | What It Verifies |
|---|---|---|
| 2.1 | `process_returns_decision` | `POST /v1/process` returns a valid Decision object |
| 2.2 | `process_decision_has_id` | Every Decision has a unique `decision_id` |
| 2.3 | `process_decision_has_type` | Decision has a valid `decision` field |
| 2.4 | `process_text_finished_false` | Text decision with `finished: false` → next call is `/v1/result`. Convention: content containing **"do not finish"** (e.g. *"Just start a thought, do not finish it yet."*) must elicit `finished=false` | 
| 2.5 | `process_text_finished_true` | Text decision with `finished: true` → harness accepts `/v1/result` with text_sent, returns `end`. Convention: a final-answer prompt (e.g. *"Give me the final answer in one short sentence."*) must elicit `finished=true` |
| 2.6 | `process_multiple_turns` | Harness handles 10-turn conversation without state corruption |
| 2.7 | `process_session_isolation` | Two different `session_id` values don't leak state |
| 2.8 | `process_preserves_history` | Messages from prior turns appear in `context.history`. Convention: the **decision envelope must echo a top-level `history` list** that does not shrink relative to the request's `context.history` (equal or larger accepted) |

**Compliance conventions (spec-only harnesses must implement these — documented in specs/02 §4):**

1. **History echo** — every decision response MAY carry a top-level `history` field mirroring the harness's conversation state. The battery (2.8) requires it: a list whose length is >= the `context.history` sent in the request. The Go/Python/TS SDK echo examples implement this by echoing the request history.
2. **Streaming marker** — a `text` decision with `finished=false` signals a partial message (more text follows via `/v1/result`). The battery (2.4/2.5) drives this from prompt phrasing: messages containing the phrase "do not finish" must return `finished=false`; final-answer prompts must return `finished=true`. Echo harnesses implement this as a substring check on the incoming message content.

### Category 3: Process — Decision Types (6 tests)

| # | Test | What It Verifies |
|---|---|---|
| 3.1 | `decision_tool_call` | Harness can return a `tool_call` decision |
| 3.2 | `decision_tool_call_valid_name` | Tool name matches one from `context.tools` |
| 3.3 | `decision_tool_call_valid_params` | Tool params match the tool's JSON Schema |
| 3.4 | `decision_llm_call` | Harness can return an `llm_call` decision |
| 3.5 | `decision_delegate` | Harness can return a `delegate` decision |
| 3.6 | `decision_end` | Harness returns `decision: "end"` with valid reason |

### Category 4: Result Handling (7 tests)

| # | Test | What It Verifies |
|---|---|---|
| 4.1 | `result_tool_success` | Harness handles `result.type: "tool_result"` with `success: true` |
| 4.2 | `result_tool_failure` | Harness handles `result.type: "tool_result"` with `success: false` |
| 4.3 | `result_llm_response` | Harness handles `result.type: "llm_response"` |
| 4.4 | `result_text_sent` | Harness handles `result.type: "text_sent"` |
| 4.5 | `result_delegate_result` | Harness handles `result.type: "delegate_result"` |
| 4.6 | `result_error` | Harness handles `result.type: "error"` gracefully |
| 4.7 | `result_wait_timeout` | Harness handles `result.type: "wait_timeout"` |

### Category 5: Error & Edge Cases (10 tests)

| # | Test | What It Verifies |
|---|---|---|
| 5.1 | `malformed_json` | Harness returns 400 on malformed JSON body |
| 5.2 | `missing_session_id` | Harness returns 400 when `session_id` is missing |
| 5.3 | `unknown_decision_type` | Battery sends bad decision → harness handles gracefully or 400s |
| 5.4 | `empty_message` | Empty `message.content` doesn't crash harness |
| 5.5 | `very_long_message` | 100KB message doesn't crash harness |
| 5.6 | `unicode_message` | Unicode/emoji content handled correctly |
| 5.7 | `no_tools_available` | `context.tools: []` — harness doesn't return `tool_call` |
| 5.8 | `no_models_available` | `context.models: []` — harness doesn't return `llm_call` |
| 5.9 | `cancel_mid_processing` | `POST /v1/cancel` returns 200, harness stops processing |
| 5.10 | `session_not_found` | `GET /v1/sessions/nonexistent` returns 404 |

### Category 6: Stress & Performance (5 tests)

| # | Test | What It Verifies |
|---|---|---|
| 6.1 | `concurrent_sessions` | 10 concurrent sessions don't corrupt each other |
| 6.2 | `rapid_process_calls` | 50 rapid `/v1/process` calls within 10s — no crashes |
| 6.3 | `loop_convergence` | Harness reaches `end` within `max_iterations` (set to 20) |
| 6.4 | `decision_latency` | Each decision returned within 5 seconds |
| 6.5 | `memory_stable` | Memory doesn't grow unbounded over 100 turns |

---

## 4. Test Battery Implementation

### 4.1 CLI

```bash
# Full suite
h3-test --endpoint http://localhost:9191

# Specific categories
h3-test --endpoint http://localhost:9191 --categories health,process

# Output JSON only (for CI)
h3-test --endpoint http://localhost:9191 --json
```

### 4.2 Hermes-Side Code Structure

Condensed structure of the real battery (`src/h3_shim/test_battery.py` in get-h3/shim —
fully async: `httpx.AsyncClient`, `await` on every request):

```python
class H3TestBattery:
    """Black-box HTTP probe exercising every public protocol endpoint."""

    #: Hard ceiling on any single network round-trip.
    PER_TEST_TIMEOUT_S: float = 10.0

    def __init__(
        self,
        endpoint: str,
        transport: str = "rest",
        config: dict | None = None,
    ):
        self.endpoint = endpoint.rstrip("/")
        self.transport = transport
        self.config = config or {}
        self.client = httpx.AsyncClient(
            base_url=self.endpoint, timeout=self.PER_TEST_TIMEOUT_S
        )
        self.results: list[TestResult] = []

    async def probe(self) -> None:
        """Pre-flight: GET /v1/health must look like an H3 endpoint."""

    async def run_all(self) -> TestReport:
        """Run every category sequentially; assemble a TestReport."""
        await self.probe()
        results: list[TestResult] = []
        for category in (
            self.category_1_health,
            self.category_2_process,
            self.category_3_decisions,
            self.category_4_results,
            self.category_5_errors,
            self.category_6_stress,
        ):
            results.extend(await category())
        # ... builds TestReport(results, total, passed, failed, duration_ms, timestamp)

    async def close(self):
        """Tear down the underlying httpx client."""
        await self.client.aclose()

    async def category_1_health(self) -> list[TestResult]:
        return [await self.test_1_1_health_ok(), ...]

    # Each test is `async def test_N_M_<name>(self) -> TestResult` and talks
    # to the harness via `await self.client.<verb>("/v1/...")` (see 4.4).
```

### 4.3 Test Result Schema

```python
@dataclass
class TestResult:
    name: str           # e.g., "health_ok"
    passed: bool
    detail: str         # "Expected 200, got 200" or "Expected 'ok', got 'error'"
    duration_ms: float
    category: str       # "Health & Protocol"

@dataclass
class TestReport:
    results: list[TestResult] = field(default_factory=list)
    total: int = 0
    passed: int = 0
    failed: int = 0
    duration_ms: float = 0.0
    timestamp: str = ""

    @property
    def all_passing(self) -> bool:
        return self.failed == 0
```

### 4.4 Sample Test Implementation

Mirrors the async pattern of `src/h3_shim/test_battery.py`: every request goes
through `await self.client.<verb>(...)`; `_timed` and `_safe_call` are battery
helpers that time each assertion and catch transport errors.

```python
async def test_1_1_health_ok(self) -> TestResult:
    """GET /v1/health → 200 with status='ok'."""
    cat = CATEGORIES["health"]
    done = self._timed("health_ok", cat)
    try:
        resp, err = await self._safe_call(self.client.get("/v1/health"))
        if err is not None or resp is None:
            return done(False, f"Exception: {err}")
        if resp.status_code != 200:
            return done(False, f"Expected 200, got {resp.status_code}")
        body = resp.json()
        status = body.get("status")
        if status != "ok":
            return done(False, f"Expected status 'ok', got '{status}'")
        return done(True, f"200 OK, status={status}")
    except Exception as exc:  # noqa: BLE001
        return done(False, f"Exception: {exc}")
```

---

## 5. SDK Test Beds

Each SDK ships a mock Hermes for harness unit testing (not protocol compliance). Protocol compliance is tested by the test battery above.

### Go Test Bed

```go
// sdks/go/testbed/mock_hermes.go
type MockHermes struct {
    harness Harness
    t       *testing.T
}

func (m *MockHermes) ProcessMessage(t *testing.T, msg string) *protocol.Decision {
    req := &protocol.ProcessRequest{...}
    decision, err := m.harness.OnProcess(req)
    require.NoError(t, err)
    return decision
}

// Assertions
func AssertToolCall(t *testing.T, d *protocol.Decision, expectedTool string) {...}
func AssertTextResponse(t *testing.T, d *protocol.Decision, contains string) {...}
func AssertEndReason(t *testing.T, d *protocol.Decision, reason string) {...}
```

### Python Test Bed

```python
# sdks/python/h3_harness/testbed.py
class MockHermes:
    def __init__(self, harness: BaseHarness):
        self.harness = harness

    async def process_message(self, content: str, tools=None, models=None) -> Decision:
        req = ProcessRequest(...)
        return await self.harness.on_process(req)

    async def send_result(self, result: ResultRequest) -> Decision:
        return await self.harness.on_result(result)
```

### TypeScript Test Bed

```typescript
// sdks/typescript/src/testbed.ts
export class MockHermes {
  constructor(private harness: Harness) {}

  async processMessage(content: string, opts?: MockOptions): Promise<Decision> {
    const req = { ...defaultProcessRequest, message: { role: 'user' as const, content } };
    return this.harness.onProcess(req);
  }

  async sendResult(result: ResultRequest): Promise<Decision> {
    return this.harness.onResult(result);
  }
}
```

---

## 6. CI Integration

### GitHub Actions

```yaml
# .github/workflows/h3-compliance.yml
name: H3 Compliance
on: [push, pull_request]
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start harness
        run: |
          cd my-harness
          go run . &
          sleep 3
      - name: Run H3 test battery
        run: |
          git clone https://github.com/get-h3/shim && cd shim && pip install -e .
          h3-test --endpoint http://localhost:9191 --json > report.json
      - name: Check results
        run: |
          FAILED=$(jq '.failed' report.json)
          if [ "$FAILED" != "0" ]; then
            echo "❌ $FAILED tests failed"
            jq '.results[] | select(.passed == false)' report.json
            exit 1
          fi
          echo "✅ All tests passed"
```

### Pre-Commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit — runs H3 test battery before commit
echo "Running H3 compliance tests..."
go run . &
PID=$!
sleep 2
h3-test --endpoint http://localhost:9191
RESULT=$?
kill $PID 2>/dev/null
if [ $RESULT -ne 0 ]; then
  echo "❌ H3 compliance failed. Fix before committing."
  exit 1
fi
```

---

## 7. Extending the Test Battery

To add a new test:

1. Add method to `H3TestBattery` class in `test_battery.py`
2. Method returns `TestResult`
3. Register in appropriate `category_*()` method
4. Open PR to `github.com/get-h3/h3`

New tests MUST:
- Be deterministic (same input → same expected output)
- Time out after 10 seconds max
- Clean up session state after running
- Work against ANY H3-compliant harness, not just one implementation
