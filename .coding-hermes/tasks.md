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

**Gate: 11/11 specs written. ~97 pages. FOREMAN: proceed to Phase 0.**

---

## PHASE 0: Protocol (Single Source of Truth)

| ID | Repo | Task | Status |
|---|---|---|---|
| P0-01 | protocol | Write `h3-protocol.yaml` — OpenAPI 3.1 from S02 + S07 | ✅ Done — commit: 4090dc23 |
| P0-02 | protocol | Write all 13 JSON Schema files under schemas/v1/ | ✅ Done — 14 schema files present |
| P0-03 | protocol | Write 8 example payloads under examples/decisions/ | ✅ Done — commit: 4090dc23 |
| P0-04 | protocol | Validation script + round-trip tests | ✅ Done — commit: 8a0451f3 |
| P0-05 | protocol | CI: validate on PR, release on tag | ✅ Done — commit: a89be0de |
| P0-06 | protocol | Tag v1.0.0 | ✅ Done — tag exists, pushed |

**Gate:** `ajv validate` passes all schemas. `redocly lint` passes. Tagged.

## PHASE 1: SDKs (Generated from Protocol)

| ID | Repo | Task | Status |
|---|---|---|---|
| P1-01 | sdk-go | Regenerate types from protocol JSON Schema | ✅ Done — 22 Go types, 100% coverage |
| P1-02 | sdk-go | Harness interface + HTTP handler + middleware | ✅ Done — 5 methods, 6 endpoints |
| P1-03 | sdk-go | Test bed (MockHermes) + assertions | ✅ Done — 13 tests |
| P1-04 | sdk-go | Examples: minimal, echo | ✅ Done — commit: 3bd1702 |
| P1-05 | sdk-python | Regenerate Pydantic models from protocol JSON Schema | ✅ Done — 343 lines, 14 schemas |
| P1-06 | sdk-python | BaseHarness ABC + FastAPI router | ✅ Done — 6 endpoints |
| P1-07 | sdk-python | Test bed (MockHermes) + pytest fixtures | ✅ Done — 34 tests |
| P1-08 | sdk-python | Examples: minimal, echo | ✅ Done — commit: 825615c |
| P1-09 | sdk-typescript | Regenerate Zod schemas from protocol JSON Schema | ✅ Done — 310 lines, 30+ exports |
| P1-10 | sdk-typescript | Harness interface + Hono router | ✅ Done — 183 lines, 6 endpoints |
| P1-11 | sdk-typescript | Test bed (MockHermes) + vitest helpers | ✅ Done — 90 tests |
| P1-12 | sdk-typescript | Examples: minimal, echo | ✅ Done — commit: 8048423 |

**Gate:** All 3 SDK echo examples pass `h3-test`.

## PHASE 2: Shim (Hermes Plugin)

| ID | Repo | Task | Status |
|---|---|---|---|
| P2-01 | shim | protocol.py — Pydantic models (regenerated from protocol) | ✅ Done — commit: ec134f1 |
| P2-02 | shim | client.py — REST client for harness communication | ✅ Done — commit: a32ae58 |
| P2-03 | shim | loader.py — discovery, health check, routing | ✅ Done — commit: 8685996 |
| P2-04 | shim | shim_loop.py — main H3ShimLoop | ✅ Done — commit: ab8b574 |
| P2-05 | shim | Decision executors: tool_call, llm_call, text, wait, delegate | ✅ Done — commit: ab8b574 |
| P2-06 | shim | native.py — native Hermes loop wrapper | ✅ Done — commit (foreman-direct) |
| P2-07 | shim | cli.py — `hermes h3` subcommands | ✅ Done — commit: a9bfd23 |

**Gate:** Shim completes 3-turn conversation with echo harness.

## PHASE 3: Test Battery (THE GATE)

| ID | Repo | Task | Status |
|---|---|---|---|
| P3-01 | shim | test_battery.py — TestRunner, H3Client, AssertionEngine, ReportGenerator | ✅ Done — commit: 0b02c55 |
| P3-02 | shim | Region 1: Health & Protocol (7 tests) | ✅ Done — 7/7 pass |
| P3-03 | shim | Region 2: Process Flows (8 tests) | ✅ Done — 8/8 pass |
| P3-04 | shim | Region 3: Decision Types (6 tests) | ✅ Done — 6/6 pass |
| P3-05 | shim | Region 4: Result Handling (7 tests) | ✅ Done — 7/7 pass |
| P3-06 | shim | Region 5: Edge Cases (10 tests) | ✅ Done — 10/10 pass |
| P3-07 | shim | Region 6: Stress (5 tests) | ✅ Done — 5/5 pass |
| P3-08 | shim | CLI: `h3-test --endpoint URL [--json|--html|--smoke]` | ✅ Done — CLI works |
| P3-09 | shim | CI: GitHub Actions compliance workflow | ✅ Done |
| P3-10 | shim | Publish `hermes-h3-shim` to PyPI | pending |

**Gate:** `h3-test --endpoint http://localhost:9191` passes against all 3 SDK echo examples. Any dev can run it.

## PHASE 4: Installer & Scaffold

| ID | Repo | Task | Status |
|---|---|---|---|
| P4-01 | shim | `hermes h3 install` — plugin registration, version check, pip install | pending |
| P4-02 | shim | `hermes h3 scaffold --lang go/python/ts` — harness template generator | pending |
| P4-03 | shim | `hermes h3 verify` — post-install/post-upgrade verification | pending |
| P4-04 | protocol | `versions.yaml` — Hermes↔H3 compatibility matrix | ✅ Done — commit: df1dca6a |
| P4-05 | shim | Hermes update pre-flight hook (S11 §3) | pending |

**Gate:** `scaffold --lang go` → `go run .` → `h3-test` passes. Full loop < 5 min.

## PHASE 5: Release Pipeline

| ID | Repo | Task | Status |
|---|---|---|---|
| P5-01 | protocol | Release workflow: validate → tag → dispatch to downstream | ✅ Done — commit: 2ff3a7c5 |
| P5-02 | sdk-go | Sync-protocol workflow: regenerate → test → release | ✅ Done — commit: f1b0349 |
| P5-03 | sdk-python | Sync-protocol workflow: regenerate → test → release | ✅ Done — commit: da26f48 |
| P5-04 | sdk-typescript | Sync-protocol workflow: regenerate → test → release | ✅ Done |
| P5-05 | shim | Sync-protocol workflow + PyPI publish | ✅ Done — commit: 372b32b |
| P5-06 | h3 | Cross-repo integration test: protocol change → all SDKs update → test battery passes | pending |

**Gate:** One tag on protocol triggers full cascade. All repos release in sync.

## PHASE 6: Docs & Website

| ID | Repo | Task | Status |
|---|---|---|---|
| P6-01 | h3 | h3.sh landing page with Quickstart | ✅ Done — docs/index.html (44KB) |
| P6-02 | h3 | Language picker (Go/Python/TS) with copy-paste code | ✅ Done — docs/sdk.html (40KB) |
| P6-03 | h3 | Protocol reference (auto-generated from OpenAPI) | ✅ Done — docs/protocol.html (40KB) |
| P6-04 | h3 | SDK docs (auto-generated) | ✅ Done — docs/sdk.html (40KB) |
| P6-05 | h3 | Compliance badge system + verify endpoint | ✅ Done — 3 SVGs in docs/badge/ |
| P6-06 | h3 | "Build Your First H3 Harness" guide | ✅ Done — docs/guide.html (34KB) |
| P6-07 | h3 | Migration guide: native → H3 | ✅ Done — docs/migration.html (25KB) |

**Gate:** External dev goes zero → working harness < 30 min using docs alone.

---

## PHASE DEPLOY: Bunker E2E — Swapped Agent Loop In Production

> GOAL: A real Hermes instance running inside a bunker, with its agent loop routed
> through H3 to an echo harness. Session in → H3 shim → harness decides → Hermes executes
> → result back → delivered to user. Proves the shim works beyond unit tests.

| ID | Task | Verifiable Outcome |
|---|---|---|
| DEPLOY-01 | Spawn persistent bunker agent (24h+ TTL, 2 CPU, 4GB) | Agent ID returned, SSH key saved |
| DEPLOY-02 | Push `h3-echo` and `hermes-h3` Docker images to ttl.sh | Both images pullable from inside bunker |
| DEPLOY-03 | Deploy echo harness container in bunker on :9191 | `curl localhost:9191/v1/health` → `{"status":"ok"}` |
| DEPLOY-04 | Deploy Hermes+H3 container in bunker, configured with `harnesses.echo.endpoint=http://localhost:9191` | Hermes gateway starts, plugin loads, health check green |
| DEPLOY-05 | Configure a test Telegram/Discord session route through echo harness | Session config maps platform+chat_id → harness name |
| DEPLOY-06 | Send a test message. Verify: message → H3 shim → echo harness → Decision returned → Hermes delivers response | Full round-trip logged with timestamps at each hop |
| DEPLOY-07 | Verify harness logs show METHOD /path STATUS DURATION for every request | Log output matches expected format |
| DEPLOY-08 | Write deployment doc: `DEPLOY.md` — "Deploying H3 in a Bunker" | Doc covers all steps, copy-paste ready for any harness |
| DEPLOY-09 | Run `h3-test --endpoint http://localhost:9191` from inside bunker against echo harness | 43/43 tests pass (or documented gaps) |

**Gate:** A message sent to the bunker Hermes flows through H3 → echo harness → back to user. Agent loop successfully swapped.

---

## PHASE QV: Quality Verification — Real Hard Verification

> These run via `gitreins judge <task-id>`. Each verifies behavior, not just code.
> Every QV task MUST: start real processes, hit real endpoints, check real output.

### QV-E2E: Full Protocol Loop

| ID | What It Verifies | Method |
|---|---|---|
| QV-E2E-01 | Go echo harness: process→text→result→text→result→end loop | ✅ Done — 3/3 requests pass, end Decision: task_complete |
| QV-E2E-02 | Python minimal harness: same full loop | pending |
| QV-E2E-03 | TypeScript minimal harness: same full loop | pending |
| QV-E2E-04 | Cross-harness: same test battery passes against all 3 | pending |
| QV-E2E-05 | Harness logs: every request timestamped with duration | ✅ Done — 5 requests logged: METHOD /path STATUS DURATION |

### QV-Protocol: Schema Integrity

| ID | What It Verifies | Method |
|---|---|---|
| QV-PROTO-01 | All 14 JSON schemas validate against their examples | `ajv validate` every schema/example pair |
| QV-PROTO-02 | OpenAPI spec is valid and complete | `redocly lint h3-protocol.yaml` |
| QV-PROTO-03 | Round-trip: Python → JSON → Go unmarshal → re-marshal → match | Cross-language serialization test |
| QV-PROTO-04 | Round-trip: Go → JSON → TS unmarshal → re-marshal → match | Cross-language serialization test |

### QV-SDK: Implementation Correctness

| ID | What It Verifies | Method |
|---|---|---|
| QV-SDK-01 | Go SDK Decision validation rejects missing fields | Send malformed request, verify structured error |
| QV-SDK-02 | Go SDK auto-generates decision_id when empty | OnProcess returns Decision without ID, verify middleware fills it |
| QV-SDK-03 | Python SDK Pydantic validation matches JSON Schema | Same invalid payload → same error across Go + Python |
| QV-SDK-04 | TS SDK Zod validation matches JSON Schema | Same invalid payload → same error across all 3 SDKs |
| QV-SDK-05 | All 3 SDKs produce identical wire format for same Decision | Serialize same Decision in Go/Python/TS → diff JSON |

### QV-Shim: Hermes Integration

| ID | What It Verifies | Method |
|---|---|---|
| QV-SHIM-01 | Test battery runs against live Go harness, 43/43 pass | `h3-test --endpoint http://localhost:9191` |
| QV-SHIM-02 | Test battery output matches expected JSON schema | Verify report.json matches TestReport schema |
| QV-SHIM-03 | Shim loop handles harness timeout gracefully | Start harness that sleeps 30s, verify timeout error |
| QV-SHIM-04 | Shim loader health check detects dead harness, falls back to native | Kill harness, verify loader marks unhealthy, routes to native |

### QV-Cross: End-to-End Integration

| ID | What It Verifies | Method |
|---|---|---|
| QV-CROSS-01 | Scaffold → run → test: full developer flow in < 5 min | `hermes h3 scaffold --lang go` → `go run .` → `h3-test` |
| QV-CROSS-02 | Install → configure → verify: full Hermes flow | `hermes h3 install` → configure harness → `hermes h3 verify` |
| QV-CROSS-03 | Protocol change → SDK regenerate → tests pass cascade | Modify schema, verify all 3 SDKs regenerate and pass |

---

## Phase Gates Summary

| Phase | Gate | Blocks |
|---|---|---|
| P-1 | 11/11 specs written | Everything |
| P0 | Protocol schemas + examples validated | P1–P6 |
| P1 | All 3 SDKs pass test battery | P2, P3 |
| P2 | Shim completes 3-turn conversation | P3, P4 |
| P3 | Test battery passes against all examples | P4, P5 |
| P4 | Scaffold → test passes end-to-end | P6 |
| P5 | One tag → full cascade release | P6 |
| P6 | External dev zero→harness < 30 min | Launch |
