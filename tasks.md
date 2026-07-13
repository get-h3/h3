# get-h3 — Cross-Repo Task Board

> This board tracks work ACROSS all 6 repos. Each repo also has its own `.coding-hermes/tasks.md`.

## PHASE 0: Protocol (Single Source of Truth)

| ID | Repo | Task | Status |
|---|---|---|---|
| P0-01 | protocol | Write `h3-protocol.yaml` — OpenAPI 3.1 spec from S02 | pending |
| P0-02 | protocol | Write JSON Schema for all types (ProcessRequest, Decision, ResultRequest, etc.) | pending |
| P0-03 | protocol | Add validation tests: schema validates example payloads | pending |
| P0-04 | protocol | Add GitReins config | pending |
| P0-05 | protocol | Publish first version tag (v1.0.0) | pending |

**Gate:** OpenAPI spec + JSON Schema pass validation. Tagged v1.0.0.

## PHASE 1: SDKs (Generated from Protocol)

| ID | Repo | Task | Status |
|---|---|---|---|
| P1-01 | sdk-go | Go types generated from protocol JSON Schema | pending |
| P1-02 | sdk-go | Harness interface + HTTP handler + middleware | pending |
| P1-03 | sdk-go | Test bed (MockHermes) + assertions | pending |
| P1-04 | sdk-go | Examples: minimal, echo | pending |
| P1-05 | sdk-python | Pydantic models + BaseHarness ABC + FastAPI router | pending |
| P1-06 | sdk-python | Test bed (MockHermes) + pytest fixtures | pending |
| P1-07 | sdk-python | Examples: minimal, echo | pending |
| P1-08 | sdk-typescript | Zod schemas + Harness interface + Hono router | pending |
| P1-09 | sdk-typescript | Test bed (MockHermes) + vitest helpers | pending |
| P1-10 | sdk-typescript | Examples: minimal, echo | pending |

**Gate:** All 3 SDK examples pass the test battery.

## PHASE 2: Shim (Hermes Plugin)

| ID | Repo | Task | Status |
|---|---|---|---|
| P2-01 | shim | protocol.py — Pydantic models (generated from protocol) | pending |
| P2-02 | shim | client.py — REST client for harness communication | pending |
| P2-03 | shim | loader.py — discovery, health check, routing | pending |
| P2-04 | shim | shim_loop.py — main H3ShimLoop | pending |
| P2-05 | shim | Decision executors: tool_call, llm_call, text, wait, delegate | pending |
| P2-06 | shim | native.py — native Hermes loop wrapper | pending |
| P2-07 | shim | cli.py — `hermes h3` subcommands | pending |

**Gate:** Shim completes 3-turn conversation with echo harness.

## PHASE 3: Test Battery (THE GATE)

| ID | Repo | Task | Status |
|---|---|---|---|
| P3-01 | shim | test_battery.py — full 43-test compliance suite | pending |
| P3-02 | shim | Category 1: Health & Protocol (7 tests) | pending |
| P3-03 | shim | Category 2: Process Basic Flows (8 tests) | pending |
| P3-04 | shim | Category 3: Process Decision Types (6 tests) | pending |
| P3-05 | shim | Category 4: Result Handling (7 tests) | pending |
| P3-06 | shim | Category 5: Error & Edge Cases (10 tests) | pending |
| P3-07 | shim | Category 6: Stress & Performance (5 tests) | pending |
| P3-08 | shim | E2E region-style runner: `h3-test --endpoint URL` | pending |
| P3-09 | shim | CI integration — GitHub Actions workflow | pending |

**Gate:** Test battery passes against all 3 SDK echo examples. Any developer can run `h3-test --endpoint http://localhost:9191` and get a full compliance report.

## PHASE 4: Installer & Scaffold

| ID | Repo | Task | Status |
|---|---|---|---|
| P4-01 | shim | `hermes h3 install` — full flow | pending |
| P4-02 | shim | `hermes h3 scaffold --lang go/python/ts` — harness template generator | pending |
| P4-03 | shim | Version compatibility matrix (versions.yaml) | pending |
| P4-04 | shim | Hermes update pre-flight hook | pending |

**Gate:** `hermes h3 scaffold --lang go` → `h3-test` passes on generated harness.

## PHASE 5: Docs & Release

| ID | Repo | Task | Status |
|---|---|---|---|
| P5-01 | h3 | h3.sh landing page + Quickstart | pending |
| P5-02 | h3 | "Build Your First H3 Harness" guide | pending |
| P5-03 | h3 | Migration guide: native → H3 harness | pending |
| P5-04 | h3 | Compliance badge system | pending |

**Gate:** External dev goes zero → working harness in < 30 min.
