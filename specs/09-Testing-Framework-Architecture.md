# S09 — Testing Framework Architecture

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Purpose

The H3 Test Battery isn't a unit test suite — it's an **E2E region-style compliance verifier**. It treats the harness as a black box. It sends requests, checks responses, and produces a pass/fail report. Any harness implementing the H3 protocol can be tested.

### Design Principle

> "When someone builds a harness, they run `h3-test --endpoint http://localhost:9191` and get a full compliance report. They don't write tests. They don't configure anything. The battery tests every decision type, every edge case, every error path."

---

## 2. Architecture

```
h3-test CLI
  │
  ├── TestRunner          ← Orchestrates 6 test regions
  │     │
  │     ├── Region: Health & Protocol (7 tests)
  │     ├── Region: Process Flows (8 tests)
  │     ├── Region: Decision Types (6 tests)
  │     ├── Region: Result Handling (7 tests)
  │     ├── Region: Edge Cases (10 tests)
  │     └── Region: Stress (5 tests)
  │
  ├── H3Client            ← HTTP client → harness endpoint
  │     GET  /v1/health
  │     POST /v1/process
  │     POST /v1/result
  │     POST /v1/cancel
  │     GET  /v1/sessions/:id
  │
  ├── AssertionEngine     ← Validates responses against JSON Schema
  │     Schema validation (Decision, ToolCall, etc.)
  │     Semantic validation (decision_id unique, tool name exists, etc.)
  │     Latency checks
  │
  └── ReportGenerator     ← Produces output
        Terminal (colorized, progress bars)
        JSON (machine-readable, CI-friendly)
        HTML (shareable report)
```

---

## 3. Test Regions (E2E Style)

Each region tests a complete functional area end-to-end:

### Region 1: Health & Protocol (7 tests)
Tests the health endpoint and protocol handshake. No session state.

```
health_ok              → GET /v1/health → 200, status="ok"
health_version         → Response includes version + protocol_version
health_transport       → Response includes transport field
health_capabilities    → capabilities array lists supported types
health_content_type    → Content-Type: application/json
health_latency         → Response within 500ms
health_idempotent      → Two calls return consistent status
```

### Region 2: Process Flows (8 tests)
Tests the /v1/process → /v1/result → loop lifecycle.

```
process_returns_decision       → POST /v1/process returns valid Decision
process_decision_has_id        → Decision has unique decision_id
process_decision_has_type      → Decision has valid decision field
process_text_finished_false    → Text(finished=false) → harness expects /v1/result
process_text_finished_true     → Text(finished=true) → /v1/result returns END
process_multiple_turns         → 10-turn conversation, no state corruption
process_session_isolation      → Two session_ids, no state leak
process_preserves_history      → context.history accumulates across turns
```

### Region 3: Decision Types (6 tests)
Tests each of the 6 decision types.

```
decision_tool_call             → Harness returns tool_call
decision_tool_call_valid_name  → Tool name matches context.tools
decision_tool_call_valid_params → Tool params match tool's JSON Schema
decision_llm_call              → Harness returns llm_call
decision_delegate              → Harness returns delegate
decision_end                   → Harness returns end with valid reason
```

### Region 4: Result Handling (7 tests)
Tests harness response to each result type.

```
result_tool_success    → Handles result.type="tool_result" success=true
result_tool_failure    → Handles result.type="tool_result" success=false
result_llm_response    → Handles result.type="llm_response"
result_text_sent       → Handles result.type="text_sent"
result_delegate_result → Handles result.type="delegate_result"
result_error           → Handles result.type="error" gracefully
result_wait_timeout    → Handles result.type="wait_timeout"
```

### Region 5: Edge Cases (10 tests)
Tests error handling and boundary conditions.

```
malformed_json         → 400 on bad JSON
missing_session_id     → 400 when session_id missing
unknown_decision_type  → Handles bad decision gracefully
empty_message          → Empty content doesn't crash
very_long_message      → 100KB message doesn't crash
unicode_message        → Emoji/Unicode handled
no_tools_available     → context.tools=[] → no tool_call returned
no_models_available    → context.models=[] → no llm_call returned
cancel_mid_processing  → POST /v1/cancel returns 200
session_not_found      → GET nonexistent session → 404
```

### Region 6: Stress (5 tests)
Tests performance and stability under load.

```
concurrent_sessions    → 10 concurrent sessions, no corruption
rapid_process_calls    → 50 rapid /v1/process in 10s, no crashes
loop_convergence       → Harness reaches END within max_iterations (20)
decision_latency       → Each decision < 5 seconds
memory_stable          → Memory doesn't grow over 100 turns
```

---

## 4. Runner Implementation

```python
class TestRunner:
    def __init__(self, endpoint: str, config: TestConfig):
        self.client = H3Client(endpoint)
        self.config = config
        self.results: list[RegionResult] = []

    def run_all(self) -> TestReport:
        regions = [
            ("Health & Protocol", HealthRegion(self.client)),
            ("Process Flows", ProcessRegion(self.client, self.config)),
            ("Decision Types", DecisionRegion(self.client, self.config)),
            ("Result Handling", ResultRegion(self.client, self.config)),
            ("Edge Cases", EdgeRegion(self.client, self.config)),
            ("Stress", StressRegion(self.client, self.config)),
        ]

        for name, region in regions:
            print(f"\n━━━ {name} ━━━")
            result = region.run()
            self.results.append(result)
            self._print_region_result(result)

        return TestReport(
            regions=self.results,
            total=sum(r.total for r in self.results),
            passed=sum(r.passed for r in self.results),
            failed=sum(r.failed for r in self.results),
        )
```

---

## 5. Output Formats

### Terminal (default)

```
H3 Compliance Test Battery v1.0.0
Target: http://localhost:9191
Protocol: v1.0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Health & Protocol             7/7  ✅
  Process Flows                 8/8  ✅
  Decision Types                6/6  ✅
  Result Handling               7/7  ✅
  Edge Cases                  10/10 ✅
  Stress                        5/5  ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TOTAL                        43/43 ✅  PASSED

Report saved: h3-report-20260712-223000.json
```

### JSON (--json flag)

```json
{
  "protocol_version": "1.0",
  "harness_endpoint": "http://localhost:9191",
  "timestamp": "2026-07-12T22:30:00Z",
  "summary": {
    "total": 43,
    "passed": 43,
    "failed": 0,
    "pass_rate": 1.0,
    "duration_ms": 2843
  },
  "regions": [
    {
      "name": "Health & Protocol",
      "total": 7,
      "passed": 7,
      "failed": 0,
      "tests": [
        {"name": "health_ok", "passed": true, "duration_ms": 12, "detail": "200 OK, status=ok"},
        ...
      ]
    },
    ...
  ]
}
```

### HTML (--html flag)

Dark-themed, mobile-first report page. Shows per-region pass/fail with expandable test details. Suitable for sharing.

---

## 6. CI Integration

```yaml
# .github/workflows/h3-compliance.yml
name: H3 Compliance
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start harness
        run: go run . & sleep 3
      - name: Run compliance
        run: |
          pip install hermes-h3-shim
          h3-test --endpoint http://localhost:9191 --json > report.json
      - name: Verify
        run: |
          if [ "$(jq '.summary.failed' report.json)" != "0" ]; then
            echo "❌ Compliance failed"
            jq '.regions[] | select(.failed > 0)' report.json
            exit 1
          fi
          echo "✅ All tests passed"
      - name: Upload report
        uses: actions/upload-artifact@v4
        with:
          name: h3-compliance-report
          path: report.json
```

---

## 7. Extending

New tests must:
1. Be deterministic (same input → same output expected)
2. Timeout after 10s max
3. Clean up session state
4. Work against ANY H3-compliant harness

```python
def test_my_new_case(self) -> TestResult:
    """Docstring becomes the test description in reports."""
    start = time.time()
    try:
        # test logic
        return TestResult("my_new_case", True, "detail", time.time() - start, self.name)
    except AssertionError as e:
        return TestResult("my_new_case", False, str(e), time.time() - start, self.name)
```
