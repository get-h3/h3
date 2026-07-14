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
| P0-01 | protocol | Write `h3-protocol.yaml` — OpenAPI 3.1 from S02 + S07 | ✅ Done (`043e5be`) |
| P0-02 | protocol | Write all 13 JSON Schema files under schemas/v1/ | ✅ Done (`9d28e48`) |
| P0-03 | protocol | Write 8 example payloads under examples/decisions/ | ✅ Done (`4090dc2`) |
| P0-04 | protocol | Validation script + round-trip tests | ✅ Done (`8a0451f`) |
| P0-05 | protocol | CI: validate on PR, release on tag | ✅ Done (`a89be0d`) |
| P0-06 | protocol | Tag v1.0.0 | ✅ Done (`a89be0d` → `v1.0.0`) |

**Gate:** `ajv validate` passes all schemas. `redocly lint` passes. Tagged. ✅ ALL GATES MET — PHASE 0 COMPLETE ✅

## PHASE 0.5: SDK Repo Scaffolding

> BLOCKING Phase 1. All 4 implementation repos are empty shells — need project scaffolding before SDK code.

| ID | Repo | Task | Status |
|---|---|---|---|
| PS-01 | sdk-go | Scaffold Go module: go.mod, Makefile, directory layout (protocol/, harness/, testbed/, examples/) | ✅ Done (`fcffd52`) |
| PS-02 | sdk-python | Scaffold Python package: pyproject.toml, Makefile, directory layout (src/h3_harness/) | pending |
| PS-03 | sdk-typescript | Scaffold TypeScript package: package.json, tsconfig.json, directory layout (src/protocol/, src/harness/) | pending |
| PS-04 | shim | Scaffold Python package: pyproject.toml, directory layout (hermes_cli/agent/shims/h3/) | pending |
| PS-05 | all | Set up foreman crons: sdk-go-foreman, sdk-python-foreman, sdk-typescript-foreman, shim-foreman | pending |

**Gate:** All 4 repos have working module files (`go build ./...` / `pip install -e .` / `npm install`). Each repo has a foreman cron.

## PHASE 1: SDKs (Generated from Protocol)

| ID | Repo | Task | Status |
|---|---|---|---|
| P1-01 | sdk-go | Regenerate types from protocol JSON Schema | pending |
| P1-02 | sdk-go | Harness interface + HTTP handler + middleware | pending |
| P1-03 | sdk-go | Test bed (MockHermes) + assertions | pending |
| P1-04 | sdk-go | Examples: minimal, echo | pending |
| P1-05 | sdk-python | Regenerate Pydantic models from protocol JSON Schema | pending |
| P1-06 | sdk-python | BaseHarness ABC + FastAPI router | pending |
| P1-07 | sdk-python | Test bed (MockHermes) + pytest fixtures | pending |
| P1-08 | sdk-python | Examples: minimal, echo | pending |
| P1-09 | sdk-typescript | Regenerate Zod schemas from protocol JSON Schema | pending |
| P1-10 | sdk-typescript | Harness interface + Hono router | pending |
| P1-11 | sdk-typescript | Test bed (MockHermes) + vitest helpers | pending |
| P1-12 | sdk-typescript | Examples: minimal, echo | pending |

**Gate:** All 3 SDK echo examples pass `h3-test`.

## PHASE 2: Shim (Hermes Plugin)

| ID | Repo | Task | Status |
|---|---|---|---|
| P2-01 | shim | protocol.py — Pydantic models (regenerated from protocol) | pending |
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
| P3-01 | shim | test_battery.py — TestRunner, H3Client, AssertionEngine, ReportGenerator | pending |
| P3-02 | shim | Region 1: Health & Protocol (7 tests) | pending |
| P3-03 | shim | Region 2: Process Flows (8 tests) | pending |
| P3-04 | shim | Region 3: Decision Types (6 tests) | pending |
| P3-05 | shim | Region 4: Result Handling (7 tests) | pending |
| P3-06 | shim | Region 5: Edge Cases (10 tests) | pending |
| P3-07 | shim | Region 6: Stress (5 tests) | pending |
| P3-08 | shim | CLI: `h3-test --endpoint URL [--json|--html|--smoke]` | pending |
| P3-09 | shim | CI: GitHub Actions compliance workflow | pending |
| P3-10 | shim | Publish `hermes-h3-shim` to PyPI | pending |

**Gate:** `h3-test --endpoint http://localhost:9191` passes against all 3 SDK echo examples. Any dev can run it.

## PHASE 4: Installer & Scaffold

| ID | Repo | Task | Status |
|---|---|---|---|
| P4-01 | shim | `hermes h3 install` — plugin registration, version check, pip install | pending |
| P4-02 | shim | `hermes h3 scaffold --lang go/python/ts` — harness template generator | pending |
| P4-03 | shim | `hermes h3 verify` — post-install/post-upgrade verification | pending |
| P4-04 | protocol | `versions.yaml` — Hermes↔H3 compatibility matrix | pending |
| P4-05 | shim | Hermes update pre-flight hook (S11 §3) | pending |

**Gate:** `scaffold --lang go` → `go run .` → `h3-test` passes. Full loop < 5 min.

## PHASE 5: Release Pipeline

| ID | Repo | Task | Status |
|---|---|---|---|
| P5-01 | protocol | Release workflow: validate → tag → dispatch to downstream | pending |
| P5-02 | sdk-go | Sync-protocol workflow: regenerate → test → release | pending |
| P5-03 | sdk-python | Sync-protocol workflow: regenerate → test → release | pending |
| P5-04 | sdk-typescript | Sync-protocol workflow: regenerate → test → release | pending |
| P5-05 | shim | Sync-protocol workflow + PyPI publish | pending |
| P5-06 | h3 | Cross-repo integration test: protocol change → all SDKs update → test battery passes | pending |

**Gate:** One tag on protocol triggers full cascade. All repos release in sync.

## PHASE 6: Docs & Website

| ID | Repo | Task | Status |
|---|---|---|---|
| P6-01 | h3 | h3.sh landing page with Quickstart | pending |
| P6-02 | h3 | Language picker (Go/Python/TS) with copy-paste code | pending |
| P6-03 | h3 | Protocol reference (auto-generated from OpenAPI) | pending |
| P6-04 | h3 | SDK docs (auto-generated) | pending |
| P6-05 | h3 | Compliance badge system + verify endpoint | pending |
| P6-06 | h3 | "Build Your First H3 Harness" guide | pending |
| P6-07 | h3 | Migration guide: native → H3 | pending |

**Gate:** External dev goes zero → working harness < 30 min using docs alone.

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
