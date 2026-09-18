# S09 — Testing Framework Architecture

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-09-18

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
        Terminal (per-category pass/fail + duration + latency)
        JSON (machine-readable, CI-friendly)   ← the only machine format shipped
        HTML (shareable report)                ← planned, not implemented (no --html flag)
```

---

## 3. Test Regions (E2E Style)

Each region tests a complete functional area end-to-end. The regions are a
*view* over one flat results list: every test in the shipped report carries its
own `category` (see §5), and the CLI uses the canonical labels
`Health & Protocol`, `Process Basic Flows`, `Decision Types`, `Result Handling`,
`Error & Edge Cases`, `Stress & Performance`. The headings below are prose names
for the same regions.

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

Shipped class: `H3TestBattery` in `shim/src/h3_shim/test_battery.py`, wrapped by the
`h3-test` CLI. The sketch below shows the intended runner shape; the part that matters
to consumers is the report it returns — the flat `TestReport` documented in §5.

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

        # Flat report: one entry per test, each carrying its own `category`.
        # `TestReport` takes no `regions=` argument (see §5).
        results = [t for r in self.results for t in r.tests]
        passed = sum(1 for t in results if t.passed)
        return TestReport(
            results=results,
            total=len(results),
            passed=passed,
            failed=len(results) - passed,
            duration_ms=sum(r.duration_ms for r in self.results),
            timestamp=datetime.now(timezone.utc).isoformat(),
        )
```

---

## 5. Output Formats

### Terminal (default)

Verbatim output of `h3-test --endpoint http://localhost:9191` against the Go echo
example — a plain per-category table, no color and no progress bars. `v0.1.0` is the
installed `hermes-h3-shim` package version. A region with failing tests prints
`❌ FAILED` on its row, and the `TOTAL` row prints `PASSED`/`FAILED` without an icon.

```

H3 Compliance Test Battery v0.1.0
Target: http://localhost:9191
Transport: REST

  Health & Protocol                   7/7  ✅ PASSED
  Process Basic Flows                 8/8  ✅ PASSED
  Decision Types                      6/6  ✅ PASSED
  Result Handling                     7/7  ✅ PASSED
  Error & Edge Cases                  13/13  ✅ PASSED
  Stress & Performance                5/5  ✅ PASSED
  TOTAL                               46/46  PASSED
  Duration                            0.38s
  Latency p50/p95                     0.97ms / 57.84ms
```

Nothing is written to disk by default — the report goes to stdout. Redirect it
(`h3-test ... > report.txt`) or use `--json` and keep the JSON.

### JSON (--json flag)

The whole payload is `dataclasses.asdict(TestReport)` plus two fields the CLI adds
(`all_passing`, `latency`). Captured verbatim from a live run against the Go echo
example (46/46, exit code 0), trimmed in the middle:

```json
{
  "timestamp": "2026-09-18T09:58:16.120158+00:00",
  "total": 46,
  "passed": 46,
  "failed": 0,
  "duration_ms": 319.6196659700945,
  "all_passing": true,
  "results": [
    {
      "name": "health_ok",
      "passed": true,
      "detail": "200 OK, status=ok",
      "duration_ms": 0.9074170375242829,
      "category": "Health & Protocol"
    },
    {
      "name": "health_version",
      "passed": true,
      "detail": "version='1.0.0', protocol_version='1.0'",
      "duration_ms": 0.9577800519764423,
      "category": "Health & Protocol"
    },
    ...
  ],
  "latency": {
    "min_ms": 0.74,
    "p50_ms": 1.42,
    "p90_ms": 8.49,
    "p95_ms": 39.0,
    "p99_ms": 113.46,
    "max_ms": 113.46,
    "mean_ms": 6.73
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `timestamp` | string | ISO-8601 UTC, stamped when the run finishes |
| `total` / `passed` / `failed` | int | `total == passed + failed` |
| `duration_ms` | float | wall time for the whole run |
| `all_passing` | bool | `true` iff `failed == 0` |
| `results[]` | array | one object per test: `name`, `passed`, `detail`, `duration_ms`, `category` |
| `latency` | object | `min_ms`, `p50_ms`, `p90_ms`, `p95_ms`, `p99_ms`, `max_ms`, `mean_ms` over `results[].duration_ms` |

**⚠️ Keys documented by earlier revisions that the CLI does NOT emit.** A previous
version of this spec showed a top-level `summary: {total, passed, failed, pass_rate,
duration_ms}` object, a top-level `regions: [...]` array, and top-level
`protocol_version` / `harness_endpoint` fields. The shipped CLI emits **none of
them**. The grouped per-region roll-up, `pass_rate` and `harness_endpoint` are
**planned** (design intent, no implementation artifact yet) — as is the `--html`
format below. Never gate on the planned keys: `jq '.summary.failed'` returns
`null`, `[ "null" != "0" ]` is TRUE, so a gate copied from the old text reports
failure on a clean 46/46 run. The endpoint is not in the payload either — it is
passed to `--endpoint` and echoed only in the terminal form.

For a grouped, human-readable region view, fold the flat list yourself:

```bash
jq -r '.results | group_by(.category)[]
       | "\(.[0].category)\t\(map(select(.passed)) | length)/\(length)"' report.json
```

That is a display helper only. Gate on `.failed` (see §6).

### HTML (`--html` flag)

**Planned — not implemented.** No `--html` flag exists: `h3-test --help` lists only
`--endpoint`, `--json`, `--categories` and `--version`. The intended artifact is a
dark-themed, mobile-first page with per-region pass/fail and expandable test details.
Until it ships, build shareable output from the `--json` report.

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
          # Gated on P3-10 (PyPI publish); source install until then:
          git clone https://github.com/get-h3/shim && cd shim && pip install -e .
          h3-test --endpoint http://localhost:9191 --json > report.json
      - name: Verify
        run: |
          # The report is FLAT: `.failed` is a top-level integer and every test is
          # an entry in `.results[]` with its own `.passed` boolean. There is no
          # `.summary` object and no `.regions` array — see "JSON (--json flag)".
          if [ "$(jq -r '.failed' report.json)" != "0" ]; then
            echo "❌ Compliance failed"
            jq '.results[] | select(.passed == false)' report.json
            exit 1
          fi
          echo "✅ All tests passed"
      - name: Upload report
        uses: actions/upload-artifact@v4
        with:
          name: h3-compliance-report
          path: report.json
```

`h3-test` itself already exits `1` on a compliance failure and `2` when the target is
not an H3 endpoint (which fails the "Run compliance" step under GitHub's default
`bash -e`), so the `Verify` step is a second pair of eyes that also *names* the failed
tests. For a target-independent belt, assert `jq -e '.all_passing == true' report.json`
as well: a non-H3 target prints `"failed": 0` alongside `"all_passing": false`, so a
`.failed`-only gate reads green on a report that carries no test results at all.

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
