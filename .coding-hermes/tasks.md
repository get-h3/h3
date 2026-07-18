# get-h3 — Cross-Repo Task Board

> SPECS FIRST. Code after.

## PHASE -1: Spec Completion ✅

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

**Gate: 11/11 specs written. ~97 pages. ✅**

---

## PHASE 0: Protocol (Single Source of Truth) ✅

| ID | Repo | Task | Status | Commit |
|---|---|---|---|---|
| P0-01 | protocol | Write `h3-protocol.yaml` — OpenAPI 3.1 from S02 + S07 | ✅ Done | 043e5be7 |
| P0-02 | protocol | Write all 14 JSON Schema files under schemas/v1/ | ✅ Done | 9d28e48b |
| P0-03 | protocol | Write 8 example payloads under examples/decisions/ | ✅ Done | 4090dc23 |
| P0-04 | protocol | Validation script + round-trip tests | ✅ Done | 8a0451f3 |
| P0-05 | protocol | CI: validate on PR, release on tag | ✅ Done | a89be0de |
| P0-06 | protocol | Tag v1.0.0 | ✅ Done | v1.0.0 |

**Gate:** `ajv validate` passes all schemas. `redocly lint` passes. Tagged. ✅

---

## PHASE 1: SDKs (Generated from Protocol) ✅

| ID | Repo | Task | Status |
|---|---|---|---|
| P1-01 | sdk-go | Regenerate types from protocol JSON Schema | ✅ Done |
| P1-02 | sdk-go | Harness interface + HTTP handler + middleware | ✅ Done |
| P1-03 | sdk-go | Test bed (MockHermes) + assertions | ✅ Done |
| P1-04 | sdk-go | Examples: minimal, echo | ✅ Done |
| P1-05 | sdk-python | Regenerate Pydantic models from protocol JSON Schema | ✅ Done |
| P1-06 | sdk-python | BaseHarness ABC + FastAPI router | ✅ Done |
| P1-07 | sdk-python | Test bed (MockHermes) + pytest fixtures | ✅ Done |
| P1-08 | sdk-python | Examples: minimal, echo | ✅ Done |
| P1-09 | sdk-typescript | Regenerate Zod schemas from protocol JSON Schema | ✅ Done |
| P1-10 | sdk-typescript | Harness interface + Hono router | ✅ Done |
| P1-11 | sdk-typescript | Test bed (MockHermes) + vitest helpers | ✅ Done |
| P1-12 | sdk-typescript | Examples: minimal, echo | ✅ Done |

**Verification:**
- Go SDK: build ✅, vet ✅, tests ✅ (protocol/harness/testbed)
- Python SDK: 34/34 tests pass ✅
- TypeScript SDK: 91/91 tests pass ✅

**Gate:** All 3 SDK echo examples pass `h3-test`. ✅

---

## PHASE 2: Shim (Hermes Plugin) ✅

| ID | Repo | Task | Status | Lines |
|---|---|---|---|---|
| P2-01 | shim | protocol.py — Pydantic models (regenerated from protocol) | ✅ Done | 281 |
| P2-02 | shim | client.py — REST client for harness communication | ✅ Done | 90 |
| P2-03 | shim | loader.py — discovery, health check, routing | ✅ Done | 202 |
| P2-04 | shim | shim_loop.py — main H3ShimLoop | ✅ Done | 315 |
| P2-05 | shim | Decision executors: tool_call, llm_call, text, wait, delegate | ✅ Done | — |
| P2-06 | shim | native.py — native Hermes loop wrapper | ✅ Done | 49 |
| P2-07 | shim | cli.py — `hermes h3` subcommands | ✅ Done | 491 |

**Verification:** 132/132 tests pass ✅. All 7 components exist + import.

**Gate:** Shim completes 3-turn conversation with echo harness. ✅

---

## PHASE 3: Test Battery (THE GATE) ✅

| ID | Repo | Task | Status |
|---|---|---|---|
| P3-01 | shim | test_battery.py — TestRunner, H3Client, AssertionEngine, ReportGenerator | ✅ Done |
| P3-02 | shim | Region 1: Health & Protocol (7 tests) | ✅ Done |
| P3-03 | shim | Region 2: Process Flows (8 tests) | ✅ Done |
| P3-04 | shim | Region 3: Decision Types (6 tests) | ✅ Done |
| P3-05 | shim | Region 4: Result Handling (7 tests) | ✅ Done |
| P3-06 | shim | Region 5: Edge Cases (10 tests) | ✅ Done |
| P3-07 | shim | Region 6: Stress (5 tests) | ✅ Done |
| P3-08 | shim | CLI: `h3-test --endpoint URL [--json|--html|--smoke]` | ✅ Done |
| P3-09 | shim | CI: GitHub Actions compliance workflow | ✅ Done | 94e82cd |
| P3-10 | shim | Publish `hermes-h3-shim` to PyPI | ✅ Done |

**Verification:** 43 test functions, 132 tests pass, CLI wired, CI compliance job added. ✅

**Gate:** `h3-test --endpoint http://localhost:9191` passes against all 3 SDK echo examples. ✅

---

## PHASE 4: Installer & Scaffold

| ID | Repo | Task | Status |
|---|---|---|---|
| P4-01 | shim | `hermes h3 install` — plugin registration, version check, pip install | ✅ Done |
| P4-02 | shim | `hermes h3 scaffold --lang go/python/ts` — harness template generator | ✅ Done |
| P4-03 | shim | `hermes h3 verify` — post-install/post-upgrade verification | ✅ Done |
| P4-04 | protocol | `versions.yaml` — Hermes↔H3 compatibility matrix | ✅ Done (df1dca6a) |
| P4-05 | shim | Hermes update pre-flight hook (S11 §3) | ✅ Done | d5c0048 |

**Gate:** `scaffold --lang go` → `go run .` → `h3-test` passes. Full loop < 5 min.

---

## PHASE 5: Release Pipeline

| ID | Repo | Task | Status |
|---|---|---|---|
| P5-01 | protocol | Release workflow: validate → tag → dispatch to downstream | **→ BOARD CREATED** |
| P5-02 | sdk-go | Sync-protocol workflow: regenerate → test → release | **→ PROPAGATED** |
| P5-03 | sdk-python | Sync-protocol workflow: regenerate → test → release | **→ PROPAGATED** |
| P5-04 | sdk-typescript | Sync-protocol workflow: regenerate → test → release | **→ PROPAGATED** |
| P5-05 | shim | Sync-protocol workflow + PyPI publish | **→ PROPAGATED** |
| P5-06 | h3 | Cross-repo integration test: protocol change → all SDKs update → test battery passes | **PENDING** |

**Gate:** One tag on protocol triggers full cascade. All repos release in sync.

---

## PHASE 6: Docs & Website

| ID | Repo | Task | Status |
|---|---|---|---|
| P6-01 | h3 | h3.sh landing page with Quickstart | **PENDING** |
| P6-02 | h3 | Language picker (Go/Python/TS) with copy-paste code | **PENDING** |
| P6-03 | h3 | Protocol reference (auto-generated from OpenAPI) | **PENDING** |
| P6-04 | h3 | SDK docs (auto-generated) | **PENDING** |
| P6-05 | h3 | Compliance badge system + verify endpoint | **PENDING** |
| P6-06 | h3 | "Build Your First H3 Harness" guide | **PENDING** |
| P6-07 | h3 | Migration guide: native → H3 | **PENDING** |

**Gate:** External dev goes zero → working harness < 30 min using docs alone.

---

## PHASE QV: Quality Verification — Real Hard Verification

> These run via `gitreins judge <task-id>`. Each verifies behavior, not just code.
> Every QV task MUST: start real processes, hit real endpoints, check real output.

### QV-E2E: Full Protocol Loop

| ID | What It Verifies | Status |
|---|---|---|
| QV-E2E-01 | Go echo harness: process→text→result→text→result→end loop | **PENDING** |
| QV-E2E-02 | Python minimal harness: same full loop | **PENDING** |
| QV-E2E-03 | TypeScript minimal harness: same full loop | **PENDING** |
| QV-E2E-04 | Cross-harness: same test battery passes against all 3 | **PENDING** |
| QV-E2E-05 | Harness logs: every request timestamped with duration | **PENDING** |

### QV-Protocol: Schema Integrity

| ID | What It Verifies | Status |
|---|---|---|
| QV-PROTO-01 | All 14 JSON schemas validate against their examples | **PENDING** |
| QV-PROTO-02 | OpenAPI spec is valid and complete | **PENDING** |
| QV-PROTO-03 | Round-trip: Python → JSON → Go unmarshal → re-marshal → match | **PENDING** |
| QV-PROTO-04 | Round-trip: Go → JSON → TS unmarshal → re-marshal → match | **PENDING** |

### QV-SDK: Implementation Correctness

| ID | What It Verifies | Status |
|---|---|---|
| QV-SDK-01 | Go SDK Decision validation rejects missing fields | **PENDING** |
| QV-SDK-02 | Go SDK auto-generates decision_id when empty | **PENDING** |
| QV-SDK-03 | Python SDK Pydantic validation matches JSON Schema | **PENDING** |
| QV-SDK-04 | TS SDK Zod validation matches JSON Schema | **PENDING** |
| QV-SDK-05 | All 3 SDKs produce identical wire format for same Decision | **PENDING** |

### QV-Shim: Hermes Integration

| ID | What It Verifies | Status |
|---|---|---|
| QV-SHIM-01 | Test battery runs against live Go harness, 43/43 pass | **PENDING** |
| QV-SHIM-02 | Test battery output matches expected JSON schema | **PENDING** |
| QV-SHIM-03 | Shim loop handles harness timeout gracefully | **PENDING** |
| QV-SHIM-04 | Shim loader health check detects dead harness, falls back to native | **PENDING** |

### QV-Cross: End-to-End Integration

| ID | What It Verifies | Status |
|---|---|---|
| QV-CROSS-01 | Scaffold → run → test: full developer flow in < 5 min | **PENDING** |
| QV-CROSS-02 | Install → configure → verify: full Hermes flow | **PENDING** |
| QV-CROSS-03 | Protocol change → SDK regenerate → tests pass cascade | **PENDING** |

---

## Phase Gates Summary

| Phase | Gate | Blocks | Status |
|---|---|---|---|
| P-1 | 11/11 specs written | Everything | ✅ |
| P0 | Protocol schemas + examples validated | P1–P6 | ✅ |
| P1 | All 3 SDKs pass test battery | P2, P3 | ✅ |
| P2 | Shim completes 3-turn conversation | P3, P4 | ✅ |
| P3 | Test battery passes against all examples | P4, P5 | ✅ |
| P4 | Scaffold → test passes end-to-end | P6 | ⚠️ Partial |
| P5 | One tag → full cascade release | P6 | ❌ |
| P6 | External dev zero→harness < 30 min | Launch | ❌ |

---

## Remaining Work Summary

**Release Pipeline — Phase 5 (5/6 propagated):**
- P5-01: Protocol release workflow (board created in protocol repo)
- P5-02–P5-05: SDK sync-protocol workflows (propagated to sdk-go/sdk-python/sdk-typescript/shim)
- P5-06: Cross-repo integration test (pending in h3)

**Docs & Website — Phase 6:**
- P6-01–P6-07: h3.sh developer portal

**Quality Verification:**
- QV-E2E: End-to-end protocol loop verification
- QV-Protocol: Schema integrity verification
- QV-SDK: Cross-SDK correctness verification
- QV-Shim: Hermes integration testing
- QV-Cross: Full developer flow testing
