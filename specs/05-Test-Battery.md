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
Test Battery (hermes_cli/agent/shims/h3/test_battery.py)
  │
  │── HTTP client ──► Harness Endpoint (localhost:9191)
  │
  │── Runs 50+ tests across 6 categories
  │── Produces JSON report + terminal output
  │── Exit code 0 = all passing, non-zero = failures
```

### Output Format

```
$ hermes h3 test --endpoint http://localhost:9191

H3 Compliance Test Battery v1.0.0
Target: http://localhost:9191
Transport: REST

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Health & Protocol             7/7  ✅
  Process - Basic Flows         8/8  ✅
  Process - Decision Types      6/6  ✅
  Result Handling               7/7  ✅
  Error & Edge Cases           10/10 ✅
  Stress & Performance          5/5  ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TOTAL                        43/43 ✅  PASSED

Report: /home/kara/.hermes/cache/h3_test_report_20260712_223000.json
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
| 2.4 | `process_text_finished_false` | Text decision with `finished: false` → next call is `/v1/result` |
| 2.5 | `process_text_finished_true` | Text decision with `finished: true` → harness accepts `/v1/result` with text_sent, returns `end` |
| 2.6 | `process_multiple_turns` | Harness handles 10-turn conversation without state corruption |
| 2.7 | `process_session_isolation` | Two different `session_id` values don't leak state |
| 2.8 | `process_preserves_history` | Messages from prior turns appear in `context.history` |

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
hermes h3 test --endpoint http://localhost:9191

# Specific categories
hermes h3 test --endpoint http://localhost:9191 --categories health,process

# Quick smoke test (categories 1-2 only)
hermes h3 test --endpoint http://localhost:9191 --smoke

# Output JSON only (for CI)
hermes h3 test --endpoint http://localhost:9191 --json

# With custom config
hermes h3 test --endpoint http://localhost:9191 --max-iterations 10 --timeout 30
```

### 4.2 Hermes-Side Code Structure

```python
# hermes_cli/agent/shims/h3/test_battery.py

class H3TestBattery:
    def __init__(self, endpoint: str, transport: str = "rest", config: TestConfig = None):
        self.client = H3Client(endpoint, transport)
        self.config = config or TestConfig()
        self.results: list[TestResult] = []

    def run_all(self) -> TestReport:
        self._run_category("Health & Protocol", self.category_health())
        self._run_category("Process - Basic Flows", self.category_process_basic())
        self._run_category("Process - Decision Types", self.category_decision_types())
        self._run_category("Result Handling", self.category_result_handling())
        self._run_category("Error & Edge Cases", self.category_edge_cases())
        self._run_category("Stress & Performance", self.category_stress())
        return TestReport(results=self.results)

    # Each test returns TestResult(passed: bool, name: str, detail: str, duration_ms: float)
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
    results: list[TestResult]
    total: int
    passed: int
    failed: int
    duration_ms: float
    timestamp: str

    @property
    def all_passing(self) -> bool:
        return self.failed == 0
```

### 4.4 Sample Test Implementation

```python
def test_health_ok(self) -> TestResult:
    """GET /v1/health returns 200 with status 'ok'"""
    start = time.time()
    try:
        resp = self.client.get("/v1/health")
        if resp.status_code != 200:
            return TestResult("health_ok", False,
                f"Expected 200, got {resp.status_code}", time.time() - start, "Health & Protocol")
        body = resp.json()
        if body.get("status") != "ok":
            return TestResult("health_ok", False,
                f"Expected status 'ok', got '{body.get('status')}'", time.time() - start, "Health & Protocol")
        return TestResult("health_ok", True,
            f"200 OK, status={body['status']}", time.time() - start, "Health & Protocol")
    except Exception as e:
        return TestResult("health_ok", False,
            f"Exception: {e}", time.time() - start, "Health & Protocol")
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
          pip install hermes-h3-test-battery
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
hermes h3 test --endpoint http://localhost:9191 --smoke
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
4. Open PR to `github.com/coding-herms/h3`

New tests MUST:
- Be deterministic (same input → same expected output)
- Time out after 10 seconds max
- Clean up session state after running
- Work against ANY H3-compliant harness, not just one implementation
