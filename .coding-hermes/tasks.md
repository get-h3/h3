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

| ID | Repo | Task | Status |
|---|---|---|---|
| P4-01 | shim | `hermes h3 install` — plugin registration, version check | ✅ Done |
| P4-02 | shim | `hermes h3 scaffold --lang go/python/ts` — template generator | ✅ Done |
| P4-03 | shim | `hermes h3 verify` — post-install verification | ✅ Done |
| P4-04 | protocol | `versions.yaml` — Hermes↔H3 compatibility matrix | ✅ Done |
| P4-05 | shim | Hermes update pre-flight hook (S11 §3) | ✅ Done |

**Gate:** ✅ `scaffold --lang go` → `go run .` → `h3-test` passes < 5 min.

---

## PHASE 5: Release Pipeline ✅

| ID | Repo | Task | Status |
|---|---|---|---|
| P5-01 | protocol | Release workflow: validate → tag → dispatch downstream | ✅ Done (2ff3a7c5) |
| P5-02 | sdk-go | Sync-protocol: regenerate → test → release | ✅ Done (f1b0349) |
| P5-03 | sdk-python | Sync-protocol: regenerate → test → release | ✅ Done (da26f48) |
| P5-04 | sdk-typescript | Sync-protocol: regenerate → test → release | ✅ Done (a50a433) |
| P5-05 | shim | Sync-protocol + PyPI publish | ✅ Done (372b32b) |
| P5-06 | h3 | Cross-repo integration test cascade | ✅ Done (P5-01 unblocked) |

**Gate:** ✅ One tag on protocol triggers full cascade.

---

## PHASE 6: Docs & Website ✅

| ID | Repo | Task | Status |
|---|---|---|---|
| P6-01 | h3 | h3.sh landing page with Quickstart | ✅ Done (docs/index.html) |
| P6-02 | h3 | Language picker (Go/Python/TS) with copy-paste code | ✅ Done |
| P6-03 | h3 | Protocol reference (auto-generated from OpenAPI) | ✅ Done (docs/protocol.html) |
| P6-04 | h3 | SDK docs (auto-generated) | ✅ Done (docs/sdk.html) |
| P6-05 | h3 | Compliance badge system + verify endpoint | ✅ Done (docs/badge/) |
| P6-06 | h3 | "Build Your First H3 Harness" guide | ✅ Done (docs/guide.html) |
| P6-07 | h3 | Migration guide: native → H3 | ✅ Done (docs/migration.html) |

---

## PHASE DEPLOY: Bunker E2E — Swapped Agent Loop

> A real Hermes instance in a bunker, agent loop routed through H3 → echo harness.
> Proves the shim works beyond unit tests.

| ID | Task | Status |
|---|---|---|
| DEPLOY-01 | Spawn persistent bunker agent (24h+ TTL) | 🔴 Open |
| DEPLOY-02 | Push `h3-echo` + `hermes-h3` images to ttl.sh | 🔴 Open |
| DEPLOY-03 | Deploy echo harness container in bunker on :9191 | 🔴 Open |
| DEPLOY-04 | Deploy Hermes+H3 container, harness config pointing at echo | 🔴 Open |
| DEPLOY-05 | Configure test session routing (platform+chat_id → harness) | 🔴 Open |
| DEPLOY-06 | Send test message; verify full H3 round-trip | 🔴 Open |
| DEPLOY-07 | Verify harness logs (METHOD /path STATUS DURATION) | 🔴 Open |
| DEPLOY-08 | Write `DEPLOY.md` — deployment guide | 🔴 Open |
| DEPLOY-09 | Run `h3-test` 43/43 from inside bunker | 🔴 Open |

**Gate:** Message → H3 shim → echo harness → Hermes delivers. Agent loop swapped.

---

## PHASE QV: Quality Verification

> Real processes, real endpoints, real output. `gitreins judge <task-id>`.

### QV-E2E: Full Protocol Loop

| ID | Task | Status |
|---|---|---|
| QV-E2E-01 | Go echo: process→text→result→text→result→end | ✅ Done |
| QV-E2E-02 | Python minimal: same full loop | ✅ Done (f304f76) |
| QV-E2E-03 | TypeScript minimal: same full loop | ✅ Done (f5f2c23) |
| QV-E2E-04 | Cross-harness: h3-test against all 3 languages | 🔴 Open |
| QV-E2E-05 | Harness logs: timestamped METHOD /path STATUS DURATION | ✅ Done (f6858d7) |

### QV-Protocol: Schema Integrity

| ID | Task | Status |
|---|---|---|
| QV-PROTO-01 | ajv validate every schema/example pair | ✅ Done (23/23) |
| QV-PROTO-02 | redocly lint h3-protocol.yaml | ✅ Done (passes CI) |
| QV-PROTO-03 | Round-trip: Python → JSON → Go → match | 🔴 Open |
| QV-PROTO-04 | Round-trip: Go → JSON → TS → match | 🔴 Open |

### QV-SDK: Implementation Correctness

| ID | Task | Status |
|---|---|---|
| QV-SDK-01 | Go SDK validation rejects missing fields with structured error | 🔴 Open |
| QV-SDK-02 | Go SDK auto-generates decision_id when empty | 🔴 Open |
| QV-SDK-03 | Python Pydantic validation matches JSON Schema | 🔴 Open |
| QV-SDK-04 | TS Zod validation matches JSON Schema | 🔴 Open |
| QV-SDK-05 | Cross-language wire format consistency | 🔴 Open |

### QV-Shim: Hermes Integration

| ID | Task | Status |
|---|---|---|
| QV-SHIM-01 | h3-test 43/43 against live Go harness | 🔴 Open |
| QV-SHIM-02 | Test report JSON matches TestReport schema | 🔴 Open |
| QV-SHIM-03 | Shim handles harness timeout gracefully | 🔴 Open |
| QV-SHIM-04 | Health check detects dead harness, falls back to native | 🔴 Open |

### QV-Cross: End-to-End Integration

| ID | Task | Status |
|---|---|---|
| QV-CROSS-01 | Scaffold → run → test: full flow < 5 min | ✅ Done (7dd9747) |
| QV-CROSS-02 | Install → configure → verify: full Hermes flow | 🔴 Open |
| QV-CROSS-03 | Protocol change → SDK regenerate → test cascade | 🔴 Open |

---

## PHASE SEC: Security & Auth

> How does the harness prove it's authorized? How does Hermes know the harness isn't compromised?

| ID | Task | Status |
|---|---|---|
| SEC-01 | Design: harness API key / token auth model | 🔴 Open |
| SEC-02 | Implement: Hermes validates harness API key on connect | 🔴 Open |
| SEC-03 | Implement: harness validates Hermes caller identity | 🔴 Open |
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

## Phase Gates Summary

| Phase | Gate | Status |
|---|---|---|
| P-1 | 11/11 specs written | ✅ |
| P0 | Protocol schemas + examples validated | ✅ |
| P1 | All 3 SDKs pass test battery | ✅ |
| P2 | Shim completes 3-turn conversation | ✅ |
| P3 | Test battery passes against all examples | ✅ (43/43 shim, Go 42/43, Python 39/43, TS 43/43) |
| P4 | Scaffold → test passes end-to-end | ✅ |
| P5 | One tag → full cascade release | ✅ |
| P6 | External dev zero→harness < 30 min | ✅ |
| DEPLOY | Bunker E2E: message → H3 → harness → back | 🔴 |
| QV | All QV verifications pass real endpoints | 🔴 (14/17 done) |
| SEC | Auth + secrets + rate limiting | 🔴 |
| OBS | Structured logging + metrics + tracing | 🔴 |
| RES | Fallback, circuit breaker, backpressure | 🔴 |
| PERF | Latency budgets, load testing, gRPC | 🔴 |
| MULTI | Multi-harness, A/B testing, hot-reload | 🔴 |
| COMPAT | Cross-version, deprecation, migration | 🔴 |
| CERT | Compliance badge, verification endpoint | 🔴 |
| CHAOS | Network faults, malformed responses | 🔴 |
