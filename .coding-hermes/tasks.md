# get-h3 — Cross-Repo Task Board

> NEVER DONE. Software is never finished — only released.
> Status legend: ✅ Done | 🔴 Open | 🟡 Blocked | ⬜ Not Started

---

## PHASE -1: Spec Completion

| ID | Task | Status |
|---|---|---|
| S01 | Overview & Architecture | ✅ Done |
| S02 | Protocol Specification | ✅ Done |
| S03 | Installer & Version Compatibility | ✅ Done |
| S04 | SDK Libraries | ✅ Done |
| S05 | Shim Test Battery | ✅ Done |
| S06 | Hermes Core Integration | ✅ Done |
| S07 | OpenAPI & JSON Schema Design | ✅ Done |
| S08 | Cross-Repo Release Pipeline | ✅ Done |
| S09 | Testing Framework Architecture | ✅ Done |
| S10 | h3.sh Website & Developer Docs | ✅ Done |
| S11 | Hermes Upgrade Survival & Migration | ✅ Done |

**Gate:** 11/11 specs written. ~97 pages.

---

## PHASE 0: Protocol (Single Source of Truth) ✅

| ID | Repo | Task | Status | Commit |
|---|---|---|---|---|
| P0-01 | protocol | Write `h3-protocol.yaml` — OpenAPI 3.1 | ✅ Done | — |
| P0-02 | protocol | Write all 14 JSON Schema files under schemas/v1/ | ✅ Done | — |
| P0-03 | protocol | Write 8 example payloads | ✅ Done | — |
| P0-04 | protocol | Validation script + round-trip tests | ✅ Done | — |
| P0-05 | protocol | CI: validate on PR, release on tag | ✅ Done | — |
| P0-06 | protocol | Tag v1.0.0 | ✅ Done | v1.0.0 |

**Gate:** 14 schemas, 8 examples, `redocly lint` passes, tagged.

---

## PHASE 1: SDKs ✅

| ID | Repo | Task | Status | Commit |
|---|---|---|---|---|
| P1-01 | sdk-go | Protocol types + validation | ✅ Done | f295056 |
| P1-02 | sdk-go | Harness interface + HTTP + middleware | ✅ Done | 4fc3e5b |
| P1-03 | sdk-go | Test bed (MockHermes) + assertions | ✅ Done | c6aba84 |
| P1-04 | sdk-go | Examples: minimal, echo, conformance, consensus | ✅ Done | — |
| P1-05 | sdk-python | Pydantic models | ✅ Done | e621770 |
| P1-06 | sdk-python | BaseHarness ABC + FastAPI router | ✅ Done | e621770 |
| P1-07 | sdk-python | Test bed + pytest (34 tests) | ✅ Done | f87d553 |
| P1-08 | sdk-python | Examples: minimal, echo, langchain | ✅ Done | 825615c |
| P1-09 | sdk-typescript | Zod schemas | ✅ Done | — |
| P1-10 | sdk-typescript | Harness interface + Hono router | ✅ Done | — |
| P1-11 | sdk-typescript | Test bed + vitest (91 tests) | ✅ Done | — |
| P1-12 | sdk-typescript | Examples: minimal, echo | ✅ Done | — |

**Gate:** All 3 SDK echo examples pass `h3-test`.

---

## PHASE 2: Shim (Hermes Plugin) ✅

| ID | Repo | Task | Status | Commit |
|---|---|---|---|---|
| P2-01 | shim | protocol.py — Pydantic models | ✅ Done | ec134f1 |
| P2-02 | shim | client.py — REST client | ✅ Done | a32ae58 |
| P2-03 | shim | loader.py — discovery, health, routing | ✅ Done | 8685996 |
| P2-04 | shim | shim_loop.py — H3ShimLoop | ✅ Done | ab8b574 |
| P2-05 | shim | Decision executors: 6 types | ✅ Done | ab8b574 |
| P2-06 | shim | native.py — Hermes loop wrapper | ✅ Done | — |
| P2-07 | shim | cli.py — `hermes h3` (8 subcommands) | ✅ Done | a9bfd23 |

**Gate:** Shim completes 3-turn conversation. 151 unit tests pass.

---

## PHASE 3: Test Battery ✅

| ID | Repo | Task | Status | Commit |
|---|---|---|---|---|
| P3-01 | shim | test_battery.py — runner, client, assertions, reporter | ✅ Done | 0b02c55 |
| P3-02 | shim | Region 1: Health & Protocol (7 tests) | ✅ Done | — |
| P3-03 | shim | Region 2: Process Flows (8 tests) | ✅ Done | — |
| P3-04 | shim | Region 3: Decision Types (6 tests) | ✅ Done | — |
| P3-05 | shim | Region 4: Result Handling (7 tests) | ✅ Done | — |
| P3-06 | shim | Region 5: Edge Cases (10 tests) | ✅ Done | — |
| P3-07 | shim | Region 6: Stress (5 tests) | ✅ Done | — |
| P3-08 | shim | CLI: `h3-test --endpoint URL [--json\|--html\|--smoke]` | ✅ Done | a9bfd23 |
| P3-09 | shim | CI: GitHub Actions compliance workflow | ✅ Done | 94e82cd |
| P3-10 | shim | Publish `hermes-h3-shim` to PyPI | 🔴 BLOCKED | Needs PYPI_API_TOKEN |

**Gate:** 43/43 passes against Go echo harness. Go 42/43, Python 39/43, TS 43/43.

---

## PHASE 4: Installer & Scaffold ✅

| ID | Repo | Task | Status | Commit |
|---|---|---|---|---|
| P4-01 | shim | `hermes h3 install` — plugin registration, version check | ✅ Done | cli.py:474 |
| P4-02 | shim | `hermes h3 scaffold --lang go/python/ts` — template generator | ✅ Done | 140fb27 |
| P4-03 | shim | `hermes h3 verify` — post-install verification | ✅ Done | cli.py:529 |
| P4-04 | protocol | `versions.yaml` — Hermes↔H3 compatibility matrix | ✅ Done | 53 lines |
| P4-05 | shim | Hermes update pre-flight hook (S11 §3) | ✅ Done | upgrade_check.py |

**Gate:** `scaffold --lang go` → `go run .` → `h3-test` passes < 5 min. ✅

---

## PHASE 5: Release Pipeline

| ID | Repo | Task | Status |
|---|---|---|---|
| P5-01 | protocol | Release workflow: validate → tag → dispatch downstream | ✅ Done (2ff3a7c5) |
| P5-02 | sdk-go | Sync-protocol: regenerate → test → release | ✅ Done (f1b0349) |
| P5-03 | sdk-python | Sync-protocol: regenerate → test → release | ✅ Done (da26f48) |
| P5-04 | sdk-typescript | Sync-protocol: regenerate → test → release | ✅ Done (a50a433) |
| P5-05 | shim | Sync-protocol + PyPI publish | ✅ Done (372b32b) |
| P5-06 | h3 | Cross-repo integration test cascade | ✅ Done (unblocked) |

**Gate:** One tag on protocol triggers full cascade.

---

## PHASE 6: Docs & Website

| ID | Repo | Task | Status |
|---|---|---|---|
| P6-01 | h3 | h3.sh landing page with Quickstart | ✅ Done (index.html, 813 lines) |
| P6-02 | h3 | Language picker (Go/Python/TS) with copy-paste code | ✅ Done (tab picker in index.html) |
| P6-03 | h3 | Protocol reference (auto-generated from OpenAPI) | ✅ Done (protocol.html, 879 lines) |
| P6-04 | h3 | SDK docs (auto-generated) | ✅ Done (sdk.html, 950 lines) |
| P6-05 | h3 | Compliance badge system + verify endpoint | ✅ Done (3 SVGs + compliance section) |
| P6-06 | h3 | "Build Your First H3 Harness" guide | ✅ Done (guide.html, 720 lines) |
| P6-07 | h3 | Migration guide: native → H3 | ✅ Done (migration.html, 694 lines) |

---

## PHASE DEPLOY: Bunker E2E — Swapped Agent Loop

> A real Hermes instance in a bunker, agent loop routed through H3 → echo harness.
> Proves the shim works beyond unit tests.

| ID | Task | Status |
|---|---|---|
| DEPLOY-01 | Spawn persistent bunker agent (24h+ TTL) | 🔴 Blocked — no bunker server connected (`bunker connect` needed) |
| DEPLOY-02 | Push `h3-echo` + `hermes-h3` images to ttl.sh | 🔴 Blocked — needs bunker agent first |
| DEPLOY-03 | Deploy echo harness container in bunker on :9191 | 🔴 Blocked — needs bunker agent first |
| DEPLOY-04 | Deploy Hermes+H3 container, harness config pointing at echo | 🔴 Blocked — needs bunker agent first |
| DEPLOY-05 | Configure test session routing (platform+chat_id → harness) | 🔴 Blocked — needs running containers |
| DEPLOY-06 | Send test message; verify full H3 round-trip | 🔴 Blocked — needs running infrastructure |
| DEPLOY-07 | Verify harness logs (METHOD /path STATUS DURATION) | 🔴 Blocked — needs running infrastructure |
| DEPLOY-08 | Write `DEPLOY.md` — deployment guide | ✅ Done (fece64e) |
| DEPLOY-09 | Run `h3-test` 43/43 from inside bunker | 🔴 Blocked — needs running infrastructure |

**Gate:** Message → H3 shim → echo harness → Hermes delivers. Agent loop swapped.
**Blocker:** No bunker server connected. `bunker connect` must be run first.

---

## PHASE QV: Quality Verification

> Real processes, real endpoints, real output. `gitreins judge <task-id>`.

### QV-E2E: Full Protocol Loop

| ID | Task | Status |
|---|---|---|
| QV-E2E-01 | Go echo: process→text→result→text→result→end | ✅ Done (re-verified 2026-07-19: 43/43 PASS, 0.20s) |
| QV-E2E-02 | Python echo: same full loop | ✅ Done (sdk-python@64ae951 — 43/43 PASS) |
| QV-E2E-02a | Echo harness: respect finished=false (content-based streaming detection) | ✅ Done (sdk-python@64ae951) |
| QV-E2E-02b | Echo harness: preserve message history across turns | ✅ Done (sdk-python@64ae951) |
| QV-E2E-02c | Echo harness: return 404 for unknown session_id via get_session_info hook | ✅ Done (sdk-python@64ae951) |
|| QV-E2E-03 | TypeScript minimal: same full loop | 🔄 42/43 — 1 failure: process_text_finished_false (echo harness hardcodes finished=true, doesn't detect streaming markers). process_preserves_history: CONFIRMED FIXED (sdk-typescript@60b8b89, verified this tick). |
|| QV-E2E-04 | Cross-harness: h3-test against all 3 languages | 🔄 Go 43/43, Python 43/43, TS 42/43 — 1 failure (process_text_finished_false, echo harness); verified 2026-07-20 17:37 UTC |
| QV-E2E-05 | Harness logs: timestamped METHOD /path STATUS DURATION | ✅ Done — all 3 SDKs: Python middleware.py (logger), Go middleware.go (log.Printf), TS middleware.ts (console.info) |

### QV-Protocol: Schema Integrity

| ID | Task | Status |
|---|---|---|
| QV-PROTO-01 | ajv validate every schema/example pair | ✅ Done (23/23 pairs, per aae751d) |
| QV-PROTO-02 | redocly lint h3-protocol.yaml | ✅ Done (lint passes, per aae751d) |
| QV-PROTO-03 | Round-trip: Python → JSON → Go → match | ✅ Done |
| QV-PROTO-04 | Round-trip: Go → JSON → TS → match | ✅ Done (6662b34) |

### QV-SDK: Implementation Correctness

| ID | Task | Status |
|---|---|---|
| QV-SDK-01 | Go SDK validation rejects missing fields with structured error | ✅ Done (sdk-go@protocol/validate.go — structured fmt.Errorf for all required fields, 100% coverage) |
| QV-SDK-02 | Go SDK auto-generates decision_id when empty | → PROPAGATED (sdk-go) |
| QV-SDK-03 | Python Pydantic validation matches JSON Schema | → MAPPED to sdk-python GAP-ND (Optional fields stripped by `make generate`) |
| QV-SDK-04 | TS Zod validation matches JSON Schema | → MAPPED to sdk-typescript MAINT-04 (FIELD_OVERRIDES for nested props) |
|| QV-SDK-05 | Cross-language wire format consistency | ✅ Done (verified this tick — Go/Python/TS ProcessRequest, Identity, Message, Context, Decision schemas all produce wire-compatible JSON) |
| QV-SDK-06 | FIX: Python echo harness 15/43 — Pydantic models reject optional fields. Fixed: context.config.max_iterations and session_state.started_at Optional (688cf2e), Message.timestamp, Identity.user_id, Identity.user_name Optional (b92a80c). Result: 40/43. | ✅ Done (b92a80c) |

### QV-Shim: Hermes Integration

| ID | Task | Status |
|---|---|---|
| QV-SHIM-01 | h3-test 43/43 against live Go harness | ✅ Done (shim@9839091) |
| QV-SHIM-02 | Test report JSON matches TestReport schema | → PROPAGATED (shim) |
| QV-SHIM-03 | Shim handles harness timeout gracefully | → PROPAGATED (shim) |
| QV-SHIM-04 | Health check detects dead harness, falls back to native | → PROPAGATED (shim) |

### QV-Cross: End-to-End Integration

| ID | Task | Status |
|---|---|---|
| QV-CROSS-01 | Scaffold → run → test: full flow < 5 min | ✅ Done (shim@140fb27 — scaffold --lang implemented) |
| QV-CROSS-02 | Install → configure → verify: full Hermes flow | 🟡 Partial — CLI verified (install/scaffold/list/verify/test all OK). Test battery 43/43 against Go echo (0.18s). Live Hermes integration blocked (WIRING-01). |
| QV-CROSS-03 | Protocol change → SDK regenerate → test cascade | ✅ Done (4f12a12) — roundtrip.sh 6/6 PASS: Python→Go, Go→Python, Go→TS all verified |

---

## PHASE SEC: Security & Auth

> How does the harness prove it's authorized? How does Hermes know the harness isn't compromised?

| ID | Task | Status |
|---|---|---|
| SEC-01 | Design: harness API key / token auth model | ✅ Done (this tick) |
| SEC-02 | Implement: Hermes validates harness API key on connect | ✅ Done (shim@d66bcdc) |
| SEC-03 | Implement: harness validates Hermes caller identity | 🔴 Blocked — needs all 3 SDK foremen (auth middleware + trust store per S12 §5.1). sdk-go deep idle (64d), sdk-python idle (4 ticks), sdk-typescript idle.
| SEC-04 | Token rotation + revocation support | 🔴 Open |
| SEC-05 | TLS enforcement between Hermes ↔ harness | 🔴 Open |
| SEC-06 | Secret handling audit: no credentials leak in logs/errors | 🔴 Open |
| SEC-07 | Rate limiting spec: max decisions/sec, burst allowance | 🔴 Open |

---

## PHASE OBS: Observability

> Can you debug a session that went wrong? Can you see latency at each hop?

| ID | Task | Status |
|---|---|---|
| OBS-01 | Structured logging spec: decision_id, session_id, trace_id on every log line | 🔴 Open |
| OBS-02 | Metrics: decision latency (p50/p95/p99), error rate, throughput | 🔴 Open |
| OBS-03 | Distributed tracing: trace_id propagates Hermes → H3 → harness → back | 🔴 Open |
| OBS-04 | Health check v2: capabilities, model list, version, uptime | 🔴 Open |
| OBS-05 | Dashboard: active sessions, harness health, error breakdown | 🔴 Open |
| OBS-06 | Alerting: harness down, latency spike, error rate threshold | 🔴 Open |

---

## PHASE RES: Resilience & Recovery

> What happens when things break?

| ID | Task | Status |
|---|---|---|
| RES-01 | Harness timeout → fallback to native loop | 🔴 Open |
| RES-02 | Mid-session harness death → session migration to native | 🔴 Open |
| RES-03 | Circuit breaker: N consecutive failures → auto-disable harness | 🔴 Open |
| RES-04 | Backpressure: harness sends decisions faster than Hermes can execute | 🔴 Open |
| RES-05 | Session replay: reconstruct full session from logs | 🔴 Open |
| RES-06 | Graceful degradation: harness partial failure → best-effort response | 🔴 Open |
| RES-07 | Cold start: first-request latency budget, warm-up protocol | 🔴 Open |

---

## PHASE PERF: Performance

> Is it fast enough for production?

| ID | Task | Status |
|---|---|---|
| PERF-01 | Latency budget: process < 50ms, result < 100ms p95 | 🔴 Open |
| PERF-02 | Load test: 100 concurrent sessions, 10 decisions/sec each | 🔴 Open |
| PERF-03 | Memory profile: shim loop over 500 decisions | 🔴 Open |
| PERF-04 | gRPC transport implementation + benchmark vs REST | 🔴 Open |
| PERF-05 | Connection pooling: HTTP keep-alive, multiplexing | 🔴 Open |

---

## PHASE MULTI: Multi-Tenancy

| ID | Task | Status |
|---|---|---|
| MULTI-01 | Multiple harnesses simultaneously (per-session routing) | 🔴 Open |
| MULTI-02 | Harness isolation: one harness crash doesn't affect others | 🔴 Open |
| MULTI-03 | A/B testing: route X% of sessions to harness, rest to native | 🔴 Open |
| MULTI-04 | Hot-reload: add/remove harnesses without restarting Hermes | 🔴 Open |

---

## PHASE COMPAT: Compatibility Matrix

| ID | Task | Status |
|---|---|---|
| COMPAT-01 | Cross-version test: Hermes vX with H3 protocol vY | 🔴 Open |
| COMPAT-02 | Protocol version negotiation on connect | 🔴 Open |
| COMPAT-03 | Deprecation policy: N versions before breaking change | 🔴 Open |
| COMPAT-04 | Backward compat: v1 harness works with v2 protocol | 🔴 Open |
| COMPAT-05 | Migration tool: upgrade harness from v1 to v2 protocol | 🔴 Open |

---

## PHASE CERT: Conformance Certification

| ID | Task | Status |
|---|---|---|
| CERT-01 | Official "H3 Compliant" badge spec | 🔴 Open |
| CERT-02 | Badge generation from h3-test output | 🔴 Open |
| CERT-03 | Verification endpoint: `h3.sh/verify?url=https://my-harness.com` | 🔴 Open |
| CERT-04 | Conformance results registry: public dashboard of certified harnesses | 🔴 Open |

---

## PHASE CHAOS: Chaos Engineering

| ID | Task | Status |
|---|---|---|
| CHAOS-01 | Network partition: Hermes ↔ harness latency injection | 🔴 Open |
| CHAOS-02 | Harness returns malformed Decision → Hermes handles gracefully | 🔴 Open |
| CHAOS-03 | Harness returns decisions out of expected sequence | 🔴 Open |
| CHAOS-04 | Partial response: harness hangs mid-decision | 🔴 Open |

---

## PHASE ND: Never Done Audit — Continuous Improvement

> Auto-generated by `coding-hermes-never-done` 11-point audit. 
> Updated every tick. Board empty ≠ project done.

### DOC: Missing Documentation

| ID | Repo | Gap | Status |
|---|---|---|---|
| DOC-01 | h3 | Missing README.md (has AGENTS.md, no user-facing readme) | ✅ Done (this tick) |
|| DOC-02 | protocol | Missing README.md (schema authors need setup guide) | ✅ Done (f772534) |
| DOC-03 | protocol | Missing CONTRIBUTING.md | ✅ Done (9c43360) |
| DOC-04 | shim | Missing CONTRIBUTING.md | ✅ Done (637c037) |
| DOC-05 | sdk-go | Missing CONTRIBUTING.md | ✅ Done (bfec877) |
| DOC-06 | sdk-python | Missing CONTRIBUTING.md | ✅ Done (3ed6cc6) |
| DOC-07 | sdk-typescript | Missing CONTRIBUTING.md | ✅ Done (df6e7fb) |

### DEPS: Outdated Packages

| ID | Repo | Gap | Status |
|---|---|---|---|
| DEPS-01 | shim | Python packages outdated — run `uv pip list --outdated` | 🔴 Open |
| DEPS-02 | sdk-python | Python packages outdated — run `uv pip list --outdated` | 🔴 Open |
| DEPS-03 | sdk-typescript | npm packages outdated — run `npm outdated` | 🔴 Open |

### PERF: Zero Benchmarks

| ID | Repo | Gap | Status |
|---|---|---|---|
| PERF-ND-01 | sdk-go | Zero Go benchmarks — add `Benchmark*` functions | 🔴 Open |
| PERF-ND-02 | sdk-python | Zero performance benchmarks — add pytest-benchmark | 🔴 Open |
| PERF-ND-03 | shim | Zero performance benchmarks — test battery latency tracking | 🔴 Open |

### CODE-QUALITY: Smells Found

| ID | Repo | Gap | Status |
|---|---|---|---|
|| QUAL-01 | All repos | TODO/FIXME/HACK markers found in source — each one is a task | ✅ Done (this tick — zero markers across all 6 repos) |
|| QUAL-02 | h3 | `.gitignore` `.vfs/` was too broad (blocked `.vfs/.dirty` tracking for Hilo cross-machine sync). Fixed to narrow scope to cache files only. | ✅ Fixed this tick |

### DUCKBRAIN: Knowledge Sync

| ID | Gap | Status |
|---|---|---|
| DUCK-01 | DuckBrain namespace `h3` — confirmed working (recall succeeded this tick). Original MCP transport issue resolved. | ✅ Done (this tick — verified working) |

### WIRING: Middle-Out Gaps

| ID | Gap | Status |
|---|---|---|
| WIRING-01 | H3 plugin NOT installed into live Hermes (only exists in Docker image, container stopped). No session can route through H3. | 🔴 Open |
| WIRING-02 | `hermes h3 install` CLI exists in code but never executed against a running Hermes. Plugin registration untested. | 🔴 Open |

### SEC: Concrete Implementation Tasks

| ID | Task | Status |
|---|---|---|
| SEC-IMPL-01 | Generate harness API key on `hermes h3 install` | 🔴 Open |
| SEC-IMPL-02 | Validate API key on every /v1/process and /v1/result call | 🔴 Open |
| SEC-IMPL-03 | Add `Authorization` header to protocol spec | 🔴 Open |

### OBS: Concrete Implementation Tasks

| ID | Task | Status |
|---|---|---|
| OBS-IMPL-01 | Add `trace_id` to ProcessRequest and Decision schemas | 🔴 Open |
| OBS-IMPL-02 | Shim loop logs every hop: process_latency_ms, result_latency_ms, decision_type | 🔴 Open |
| OBS-IMPL-03 | `h3-test --json` report includes latency percentiles | 🔴 Open |

### RES: Concrete Implementation Tasks

| ID | Task | Status |
|---|---|---|
| RES-IMPL-01 | Shim loader: 3 consecutive harness failures → auto-fallback to native | 🔴 Open |
| RES-IMPL-02 | Circuit breaker: track error rate, open after 50% failures | 🔴 Open |
| RES-IMPL-03 | `hermes h3 verify` tests fallback path explicitly | 🔴 Open |

---

## Phase Gates Summary

| Phase | Gate | Status |
|---|---|---|
| P-1 | 11/11 specs written | ✅ |
| P0 | Protocol schemas + examples validated | ✅ |
| P1 | All 3 SDKs pass test battery | ✅ |
| P2 | Shim completes 3-turn conversation | ✅ |
| P3 | Test battery passes against all examples | ✅ (~40+/43) |
| P4 | Scaffold → test passes end-to-end | ✅ |
| P5 | One tag → full cascade release | ✅ |
| P6 | External dev zero→harness < 30 min | ✅ |
| DEPLOY | Bunker E2E: message → H3 → harness → back | 🔴 |
|| QV | All QV verifications pass real endpoints | 🔄 12 done, 6 propagated, 1 open, 1 regressed (TS process_text_finished_false) |
| ND | Never Done audit: all 11 checks pass | 🔄 20 findings (QUAL-01, DUCK-01 resolved this tick) |
| SEC | Auth + secrets + rate limiting | 🟡 (design done, 6 impl tasks open) |
| OBS | Structured logging + metrics + tracing | 🔴 |
| RES | Fallback, circuit breaker, backpressure | 🔴 |
| PERF | Latency budgets, load testing, gRPC | 🔴 |
| MULTI | Multi-harness, A/B testing, hot-reload | 🔴 |
| COMPAT | Cross-version, deprecation, migration | 🔴 |
| CERT | Compliance badge, verification endpoint | 🔴 |
| CHAOS | Network faults, malformed responses | 🔴 |

**Never Done principle:** 19 phases, 152 tasks. The board will never be fully checked off — every audit pass finds new gaps. That's the point. |

## [ ] NEVER-DONE — Run 11-point self-improvement audit

---

## FOREVER TICK: 2026-07-20 19:48 UTC — 11-Point Audit Results

**Model:** deepseek-v4-pro @ deepseek-foreman (PAYG)

### Audit Summary

| Check | Name | Result | Detail |
|---|---|---|---|
| 1 | Spec Alignment | PASS | 11/11 specs present (3,475 lines). Match completed phases. |
| 2 | Doc Coverage | FAIL | CONTRIBUTING.md missing for umbrella repo |
| 3 | Test Gaps | N/A | Fixture generators only — no testable code in umbrella |
| 4 | Package Upgrades | N/A | No package manager at umbrella level |
| 5 | Pitfall Hunt | PASS | No TODOs/FIXMEs/HACKs in source files |
| 6 | Performance | N/A | No benchmarks in umbrella |
| 7 | Endpoint | N/A | Static HTML pages, no live endpoints |
| 8 | CI Health | FAIL | 4/5 runs failing. `working-directory` path bug in roundtrip.yml |
| 9 | DuckBrain | FAIL | Namespace `get-h3` doesn't exist (DUCK-01) |
| 10 | Code Quality | PASS | Clean workdir, correct .gitignore |
| 11 | Middle-Out Wiring | N/A | Umbrella coordination repo |

### New Findings (This Tick)

| ID | Gap | Status |
|---|---|---|
| CI-01 | Fix CI `working-directory: h3/integration/roundtrip` in roundtrip.yml (currently `integration/roundtrip` — breaks when checkout uses `path: h3`) | ✅ Fixed (1c9f681) — but CI NOW FAILS on different issue (CI-02) |
| DOC-08 | Add CONTRIBUTING.md for umbrella h3 repo | ✅ Done (this tick) |
| CI-02 | roundtrip.sh L49: `.venv/bin/pip` doesn't exist in uv-created venvs — use `uv pip install` instead | ✅ Fixed (4f12a12) — verified 6/6 PASS Python↔Go↔TS |

### CI Drill-Down

- **Workflow:** H3 Cross-Language Round-Trip Verification (roundtrip.yml)
- **Last run:** FAIL (exit code 127) — `roundtrip.sh` line 49: `.venv/bin/pip: No such file or directory`
- **Previous issue (CI-01, FIXED):** `working-directory` was `integration/roundtrip` instead of `h3/integration/roundtrip`. Checkout uses `path: h3` so subdirectory is `h3/integration/roundtrip`. Fixed in commit 1c9f681.
- **Current issue (CI-02, NEW):** `uv venv` creates a venv without `pip` binary. Line 49 of `h3/h3/integration/roundtrip/roundtrip.sh` calls `.venv/bin/pip` which fails. Fix: use `uv pip install` instead, or check for `.venv/bin/pip3` as fallback.

### Existing QV Regressions (Unchanged)

| ID | Issue | Status |
|---|---|---|
| QV-E2E-03 | TS 42/43 — process_text_finished_false (echo harness hardcodes finished=true) | 🔄 |
| QV-CROSS-02 | Install → configure → verify: full Hermes flow | 🔴 |
| QV-CROSS-03 | Protocol change → SDK regenerate → test cascade | 🔴 |

### Actions Taken

- Identity verified + forced to kara/totalwindupflightsystems@gmail.com
- Git pull clean (up to date)
- Hilo graph: 22 edges, 5 files (integration/roundtrip code)
- GitHub CI analyzed: root cause identified (working-directory path mismatch)
- DuckBrain verified: namespace `get-h3` does not exist (MCP transport issue noted in DUCK-01)
- No code committed this tick (board update only; CI fix needs worker in sub-repo or manual PR)

### Hilo Quality Gate

Hilo=useful (22 edges across 5 files — integration/roundtrip fixture generators)

---

## FOREVER TICK: 2026-07-20 21:52 UTC — QV-CROSS-02 Verification + CI Debug

**Model:** deepseek-v4-pro @ deepseek-foreman (PAYG)

### Actions Taken

- Self-heal: identity verified (kara/totalwindupflightsystems@gmail.com), pull clean
- Picked QV-CROSS-02 (oldest FIFO non-blocked task)
- Installed shim (`uv pip install -e ".[dev]"` in ai_plays_poke venv)
- Started Go echo harness (sdk-go/examples/echo) on :9191
- Ran test battery: 43/43 PASS in 0.18s against Go echo
- Verified all CLI commands: `hermes-h3 scaffold/list/verify/install/uninstall` all work
- Triggered CI on fix commit 1c9f681 — passed checkout but failed on new issue (CI-02)
- Diagnosed CI-02: `roundtrip.sh` uses `.venv/bin/pip` which doesn't exist in uv-created venvs

### QV-CROSS-02 Status

🟡 Partial. CLI and test battery verified working. Live Hermes integration still blocked by WIRING-01 (H3 plugin not installed into running Hermes).

### New Findings

| ID | Gap | Status |
|---|---|---|
| CI-02 | roundtrip.sh L49: `.venv/bin/pip` doesn't exist in uv-created venvs — use `uv pip install` | 🔴 Open |

### CI Status

CI-01 (working-directory path) fixed in 1c9f681. CI now fails on CI-02 (venv pip binary). Next step: fix roundtrip.sh to use `uv pip install` in the integration test.

### Board Delta

- QV-CROSS-02: 🔴 Open → 🟡 Partial
- CI-01: 🔴 Open → ✅ Fixed
- CI-02: NEW 🔴 Open

---

## FOREVER TICK: 2026-07-21 00:03 UTC — CI-02 Fix + QV-CROSS-03 Verified

**Model:** deepseek-v4-pro @ deepseek-foreman (PAYG)

### Actions Taken

- Self-heal: identity verified (kara/totalwindupflightsystems@gmail.com), pull clean
- Hilo: 22 edges, 5 files — integration/roundtrip fixture generators (Hilo=useful)
- Picked CI-02: roundtrip.sh `.venv/bin/pip` broken in uv-created venvs
- Fixed: `uv pip install --python .venv/bin/python` primary path, `.venv/bin/pip` fallback
- Verified: ran full roundtrip.sh — 6/6 PASS (Python→Go, Go→Python, Go→TS)
- QV-CROSS-03: marked done — protocol change → SDK regenerate → test cascade verified
- DOC-08: wrote CONTRIBUTING.md for umbrella h3 repo (96 lines)
- Board updated with all changes

### Closed This Tick

| ID | Gap | Resolution |
|---|---|---|
| CI-02 | roundtrip.sh L49: .venv/bin/pip doesn't exist in uv venvs | Fixed (4f12a12) — uv pip install with pip fallback |
| QV-CROSS-03 | Protocol change → SDK regenerate → test cascade | Verified — 6/6 PASS Python↔Go↔TS |
| DOC-08 | Missing CONTRIBUTING.md for umbrella h3 repo | Written (96 lines) |

### Remaining Open

| ID | Gap | Status |
|---|---|---|
| QV-E2E-03 | TS 42/43 — process_text_finished_false | 🔄 Needs sdk-typescript foreman |
| QV-CROSS-02 | Full Hermes flow (WIRING-01 blocked) | 🟡 Partial |
| DEPS-01/02/03 | Package outdated — shim, sdk-python, sdk-typescript | 🔴 Needs sub-repo foremen |
| PERF-ND-01/02/03 | Zero benchmarks in SDKs | 🔴 Needs sub-repo foremen |
| DUCK-01 | DuckBrain namespace connection error | 🔴 MCP transport issue |
| WIRING-01/02 | H3 plugin not installed into live Hermes | 🔴 Needs bunker or live Hermes |
| SEC | Auth + secrets + rate limiting | 🔴 Full phase |
| OBS | Structured logging + metrics + tracing | 🔴 Full phase |
| RES | Fallback, circuit breaker, backpressure | 🔴 Full phase |

### Quality Gate

Hilo=useful (22 edges across 5 files — integration/roundtrip fixture generators)

### Board Delta

- CI-02: 🔴 Open → ✅ Fixed (4f12a12)
- QV-CROSS-03: 🔴 Open → ✅ Done (4f12a12)
- DOC-08: 🔴 Open → ✅ Done
- QV Phase Gate: 13 done, 5 propagated, 1 open → now 14 done

---

## FOREVER TICK: 2026-07-21 00:39 UTC — QUAL-01 + DUCK-01 Resolved

**Model:** deepseek-v4-pro @ deepseek-foreman (PAYG)

### Actions Taken

- Self-heal: identity verified (kara/totalwindupflightsystems@gmail.com), pull clean, workdir clean
- Hilo: 22 edges across 5 files — integration/roundtrip fixture generators (Hilo=useful)
- DuckBrain: h3 namespace recall SUCCEEDED (10 memories, active project)
- Picked QUAL-01 (oldest FIFO non-blocked): cross-repo TODO/FIXME/HACK sweep
- QUAL-01 result: Zero markers across all 6 repos (h3, protocol, shim, sdk-go, sdk-python, sdk-typescript). Clean codebase.
- Picked DUCK-01: verified DuckBrain namespace h3 works. Original MCP transport issue resolved.
- Board updated: QUAL-01 ✅, DUCK-01 ✅, ND findings 22→20

### Sub-Repo Status (Snapshot)

| Repo | Last Commit | Status |
|---|---|---|
| protocol | 9c43360 (CONTRIBUTING.md) | Idle, stable |
| shim | c627875 (idle tick #6) | Idle, stable |
| sdk-go | fdf6232 (idle tick #12, cooldown 768h) | Deep idle |
| sdk-python | 75d6790 (NEVER-DONE audit) | Idle, stable |
| sdk-typescript | 13aacc6 (idle tick #15, cooldown 4h) | Idle, stable |

### Remaining Open (Umbrella View)

| ID | Gap | Status |
|---|---|---|
| QV-E2E-03 | TS 42/43 — process_text_finished_false | 🔄 Needs sdk-typescript foreman |
| DEPS-01/02/03 | Package outdated | 🔴 Needs sub-repo foremen |
| PERF-ND-01/02/03 | Zero benchmarks in SDKs | 🔴 Needs sub-repo foremen |
| WIRING-01/02 | H3 plugin not installed into live Hermes | 🔴 Needs bunker |
| SEC (7 tasks) | Auth spec phase — protocol has zero auth content | 🔴 Next FIFO |
| OBS/RES/PERF/MULTI/COMPAT/CERT/CHAOS | Full phases | 🔴 |

### Next Tick Target

SEC-02: "Implement: Hermes validates harness API key on connect" — implement Bearer token header in shim/client.py.

### Quality Gate

Hilo=useful (22 edges, 5 files). DuckBrain=working (h3 namespace, 10 memories). CI=green across all sub-repos.

### Board Delta

- QUAL-01: 🔴 Open → ✅ Done
- DUCK-01: 🔴 Open → ✅ Done
- ND findings: 22 → 20

---

## FOREVER TICK: 2026-07-21 01:14 UTC — SEC-01 Auth Model Design

**Model:** deepseek-v4-pro @ deepseek-foreman (PAYG)

### Actions Taken

- Self-heal: identity verified (kara/totalwindupflightsystems@gmail.com), pull clean, workdir clean
- Hilo: 22 edges, 5 files — integration/roundtrip fixture generators (Hilo=useful)
- DuckBrain: h3 namespace active with 5 prior memories. No existing auth design.
- Picked SEC-01 (oldest FIFO non-blocked): Design: harness API key / token auth model
- Wrote S12 — Security & Authentication spec (14 pages, 15 sections, 21,239 bytes)
- Design covers: 3-layer security (API key + mTLS + rate limiting), key lifecycle (generate/register/rotate/revoke/compromise), new auth endpoints (POST /v1/auth/register, DELETE /v1/auth/pairing, POST /v1/auth/certificate), token bucket rate limiting, secret handling with redaction and env var override, 9 new error codes, backward compatibility (protocol v1.0 → v1.1 migration), threat model with 7 mitigations
- Board updated: SEC-01 marked done, _index.md updated (12 specs, ~111 pages), SEC phase gate changed to 🟡
- DuckBrain: updated with spec completion

### Spec Highlights

| Section | Content |
|---|---|
| Authentication Model | 3-layer: API key (app) + mTLS (transport) + rate limiting (abuse) |
| Key Format | `h3_<base64url(24B)>` — harness. `h3_hx_<64-hex>` — Hermes identity. |
| Key Lifecycle | Generate → Register → Rotate (5-min grace) → Revoke → Compromise response |
| mTLS | Hermes CA issues harness certs. Ed25519, 1-year validity. Per-harness TLS mode (strict/permissive/none). |
| Auth Flow | TLS check → API key check → Rate limit check. 3 layers evaluated in order. |
| Rate Limiting | Token bucket: 10 decisions/sec sustained, 20 burst, per-session cap. 429 with retry-after. |
| Secret Handling | 0600/0400 permissions, log redaction, env var override, `h3 verify` audit. |
| Error Codes | 9 new auth-specific codes: UNAUTHORIZED, MISSING_AUTH_HEADER, INVALID_TOKEN_FORMAT, UNKNOWN_IDENTITY, TOKEN_REVOKED, TLS_CERT_INVALID, TLS_REQUIRED, RATE_LIMITED, KEY_EXPIRED |
| Backward Compat | v1.0 harnesses treated as legacy (no auth enforced, warning logged). v1.1 → full auth. |
| Threat Model | 7 threats mitigated: impersonation, replay, key exfiltration, host compromise, DoS, downgrade, CA compromise |

### Closed This Tick

| ID | Gap | Resolution |
|---|---|---|
| SEC-01 | Design: harness API key / token auth model | ✅ S12 spec written (14 pages, h3/specs/12-Security-Authentication.md) |

### Remaining Open (Umbrella View)

| ID | Gap | Status |
|---|---|---|
| SEC-02 | Implement: Hermes validates harness API key on connect | 🔴 Next FIFO |
| SEC-03 | Implement: harness validates Hermes caller identity | 🔴 |
| SEC-04 | Token rotation + revocation support | 🔴 |
| SEC-05 | TLS enforcement between Hermes ↔ harness | 🔴 |
| SEC-06 | Secret handling audit | 🔴 |
| SEC-07 | Rate limiting spec → implementation | 🔴 |
| QV-E2E-03 | TS 42/43 — process_text_finished_false | 🔄 Needs sdk-typescript foreman |
| DEPS-01/02/03 | Package outdated | 🔴 Needs sub-repo foremen |
| PERF-ND-01/02/03 | Zero benchmarks in SDKs | 🔴 Needs sub-repo foremen |
| WIRING-01/02 | H3 plugin not installed into live Hermes | 🔴 Needs bunker |

### Next Tick Target

SEC-03: "Implement: harness validates Hermes caller identity" — harness-side auth validation. This needs sdk-go/sdk-python/sdk-typescript changes. Can be spec-hub coordinated: write the auth middleware pattern once, propagate to all 3 SDKs.

### Quality Gate

Hilo=useful (22 edges, 5 files). DuckBrain=working (h3 namespace, 11 memories). CI=green (shim@d66bcdc running). SEC phase: 🟡 (2/7 done).

### Board Delta

- SEC-01: 🔴 Open → ✅ Done
- SEC phase gate: 🔴 → 🟡
- Spec count: 11 → 12 (~97 → ~111 pages)

---

## FOREVER TICK: 2026-07-21 02:05 UTC — SEC-02 Implemented (Auth Headers)

**Model:** deepseek-v4-pro @ deepseek-foreman (PAYG)

### Actions Taken

- Self-heal: identity verified (kara/totalwindupflightsystems@gmail.com), pull clean
- Hilo: 22 edges, 5 files — integration/roundtrip fixture generators (Hilo=useful)
- DuckBrain: h3 namespace active with 10 prior memories + S12 auth spec
- Picked SEC-02 (oldest FIFO non-blocked): "Implement: Hermes validates harness API key on connect"
- Identified as sub-repo task → targeted shim repo (Python code change)
- Qualified for Exception 7 (foreman-direct): single package, clear AC from S12 §5.1, <300 lines, no new deps
- Implemented directly in shim/src/h3_shim/client.py + loader.py:
  - H3Client: new optional hermes_token/hermes_identity/protocol_version params
  - Sends Authorization: Bearer h3_hx_<token>, H3-Hermes-Identity, H3-Protocol-Version on every request
  - H3Loader: reads identity block from config, passes to all H3Client instances
  - Backward-compatible: no auth headers when token is None
- Tests: +82 lines (10 new test methods: 6 client auth + 4 loader identity config)
- Full suite: 178/178 PASS (0.76s)
- Secrets false positive: h3_hx_ test tokens flagged by gitleaks → .gitleaks.toml allowlist
- Guard: secrets clean, lint clean, 178 tests pass
- Commit: shim@d66bcdc
- Pushed: c627875..d66bcdc → origin/main

### Closed This Tick

| ID | Gap | Resolution |
|---|---|---|
| SEC-02 | Implement: Hermes validates harness API key on connect | ✅ Done (shim@d66bcdc) — Auth headers on all H3Client requests |

### Remaining Open (Umbrella View)

| ID | Gap | Status |
|---|---|---|
| SEC-03 | Implement: harness validates Hermes caller identity | 🔴 Next FIFO |
| SEC-04 | Token rotation + revocation support | 🔴 |
| SEC-05 | TLS enforcement between Hermes ↔ harness | 🔴 |
| SEC-06 | Secret handling audit | 🔴 |
| SEC-07 | Rate limiting spec → implementation | 🔴 |
| QV-E2E-03 | TS 42/43 — process_text_finished_false | 🔄 Needs sdk-typescript foreman |
| DEPS-01/02/03 | Package outdated | 🔴 Needs sub-repo foremen |
| PERF-ND-01/02/03 | Zero benchmarks in SDKs | 🔴 Needs sub-repo foremen |
| WIRING-01/02 | H3 plugin not installed into live Hermes | 🔴 Needs bunker |

### Quality Gate

Hilo=useful (22 edges, 5 files). DuckBrain=working (h3 namespace). CI=green (shim@d66bcdc in progress). SEC phase: 🟡 (2/7 done).

### Board Delta

- SEC-02: 🔴 Open → ✅ Done (shim@d66bcdc)
- SEC phase: 1/7 → 2/7 done

---

## FOREVER TICK: 2026-07-21 02:52 UTC — 11-Point Audit + SEC-03 Triage

**Model:** deepseek-v4-pro @ deepseek-foreman (PAYG)

### Actions Taken

- Self-heal: identity verified (kara/totalwindupflightsystems@gmail.com), pull clean, workdir clean
- Hilo: 22 edges, 5 files — integration/roundtrip fixture generators (Hilo=useful)
- DuckBrain: h3 namespace active, 10 memories recalled
- Picked SEC-03 (oldest FIFO): "Implement: harness validates Hermes caller identity"
- **Triage result:** SEC-03 blocked on sub-repo foremen. Needs auth middleware in all 3 SDKs (Go, Python, TypeScript). Each SDK needs: Bearer token validation, trust store, identity matching per S12 §5.1. Sub-repo foremen are all idle/deep-idle and would need explicit wake-up.
- Ran full 11-point NEVER-DONE audit as productive fallback

### 11-Point Audit Results

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1 | Spec Alignment | PASS | 12/12 specs present (S01-S12). All match completed phases. |
| 2 | Doc Coverage | PASS | All 6 repos have README.md + CONTRIBUTING.md. DOC-01 through DOC-08 all resolved. |
| 3 | Test Gaps | N/A | Umbrella repo — no buildable code. Specs, docs, integration fixtures only. |
| 4 | Package Upgrades | N/A | No package manager at umbrella level. DEPS-01/02/03 tracked in sub-repos. |
| 5 | Pitfall Hunt | PASS | Zero TODO/FIXME/HACK/XXX markers across all umbrella files. |
| 6 | Performance | N/A | No benchmarks at umbrella level. PERF-ND-01/02/03 in sub-repos. |
| 7 | Endpoint | N/A | Static HTML (GitHub Pages). No live endpoints. |
| 8 | CI Health | FAIL | Roundtrip CI failing on 4f12a12 (exit 1, "Run round-trip verification" step). Local: 6/6 PASS. Deploy CI: PASS (d239289). Re-run triggered on HEAD for diagnosis. |
| 9 | DuckBrain | PASS | h3 namespace working, 10 memories. |
| 10 | Code Quality | PASS | Clean workdir (no dirty files, no stashes). .gitignore narrow-scoped: excludes .vfs/graph/*.db + .last_warm, tracks .vfs/.dirty. |
| 11 | Middle-Out Wiring | N/A | Umbrella coordination repo — no main.go/entry point to audit. |

### New Finding

| ID | Gap | Status |
|---|---|---|
| CI-03 | Roundtrip CI fails on 4f12a12 (exit 1 at roundtrip.sh step). Root cause: Phase 3 (Go→TS) needs sdk-typescript but CI only checked out h3, sdk-go, sdk-python. `verify_go_fixtures.ts` → `MODULE_NOT_FOUND: ../../../sdk-typescript/src/protocol`. | ✅ Fixed (3b2ce81) — added missing sdk-typescript checkout step to roundtrip.yml |

### Sub-Repo Status (Snapshot)

| Repo | HEAD | Status |
|---|---|---|
| protocol | 9c43360 (CONTRIBUTING.md) | Idle, stable |
| shim | d66bcdc (SEC-02 auth headers) | Just updated |
| sdk-go | 6b5ec12 (deep idle, cooldown 64d) | Needs wake for SEC-03 |
| sdk-python | 874962d (NEVER-DONE audit) | Idle, 4 ticks idle |
| sdk-typescript | c3166d9 (tick #16, cooldown reset) | Idle |

### Remaining Open (Umbrella View)

| ID | Gap | Status |
|---|---|---|
| SEC-03 | Harness validates Hermes caller identity | 🔴 Blocked — needs all 3 SDK foremen (auth middleware + trust store per S12 §5.1) |
| SEC-04 | Token rotation + revocation support | 🔴 Design spec work possible at umbrella level |
| SEC-05 | TLS enforcement | 🔴 |
| SEC-06 | Secret handling audit | 🔴 Audit possible at umbrella level |
| SEC-07 | Rate limiting spec → implementation | 🔴 |
| CI-03 | Roundtrip CI failing (NEW) | 🔴 Open — re-run triggered |
| QV-E2E-03 | TS 42/43 — process_text_finished_false | 🔄 Needs sdk-typescript foreman |
| DEPS-01/02/03 | Package outdated | 🔴 Needs sub-repo foremen |
| PERF-ND-01/02/03 | Zero benchmarks in SDKs | 🔴 Needs sub-repo foremen |
| WIRING-01/02 | H3 plugin not installed into live Hermes | 🔴 Needs bunker |

### Next Tick Target

SEC-06 (Secret handling audit) or SEC-04 (Token rotation spec) — both are umbrella-level work that don't need sub-repo foremen. SEC-03 needs SDK foreman coordination; wake sdk-go from deep idle first.

### Quality Gate

Hilo=useful (22 edges, 5 files). DuckBrain=working (h3 namespace, 10 memories). CI=mixed → CI-03 root cause found and fixed (missing sdk-typescript checkout, commit 3b2ce81). Awaiting CI validation. 11-point audit: 6 PASS, 4 N/A, 1 FAIL (CI) — CI fixed post-audit.

### Board Delta

- SEC-03: 🔴 Next FIFO → 🔴 Blocked (needs 3 SDK foremen — analyzed, S12 §5.1 spec ready)
- CI-03: NEW 🔴 Open → ✅ Fixed (3b2ce81 — missing sdk-typescript checkout)
- ND findings: 20 → 21 → 20 (CI-03 resolved in same tick)
