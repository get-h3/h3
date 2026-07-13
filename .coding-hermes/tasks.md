# H3 — Task Board

> Foreman: follow this board. FIFO within each phase. Phase gates block downstream work.
> Specs: DuckBrain `/spec/h3/*` and `specs/*.md` in this repo.

---

## PHASE 0: Project Scaffold

| ID | Task | Status | Worker |
|---|---|---|---|
| P0-01 | Initialize Go module, directory structure, Makefile | pending | — |
| P0-02 | Add GitReins config (.gitreins/config.yaml) | pending | — |
| P0-03 | Write AGENTS.md for repo | pending | — |
| P0-04 | Initialize DuckBrain /spec/h3/* seeds from specs | pending | — |

**Gate:** `gitreins guard` passes, repo is pushable.

---

## PHASE 1: Protocol Types (No Logic)

| ID | Task | Status | Worker |
|---|---|---|---|
| P1-01 | Implement `protocol.py` — Pydantic models for all types (S02, S06) | pending | — |
| P1-02 | Implement `protocol.go` — Go structs with JSON tags (S04 §2) | pending | — |
| P1-03 | Implement `protocol.ts` — TypeScript types + Zod schemas (S04 §4) | pending | — |
| P1-04 | Validate round-trip: Python serializes → Go deserializes → TS deserializes | pending | — |

**Gate:** All three protocol libraries pass round-trip serialization tests.

---

## PHASE 2: Hermes-Side Shim

| ID | Task | Status | Worker |
|---|---|---|---|
| P2-01 | Implement `client.py` — REST client for harness communication (S06 §3) | pending | — |
| P2-02 | Implement `loader.py` — harness discovery, health check loop, session routing (S06 §6) | pending | — |
| P2-03 | Implement `shim_loop.py` — main H3ShimLoop: process → execute → result → loop (S06 §4) | pending | — |
| P2-04 | Implement decision executors: tool_call, llm_call, text, wait, delegate (S06 §5) | pending | — |
| P2-05 | Implement `native.py` — native Hermes loop as H3 harness wrapper (S06 §7) | pending | — |
| P2-06 | Implement `cli.py` — `hermes h3` subcommands (S06 §8) | pending | — |
| P2-07 | Implement `hermes h3 install` — plugin registration, version check, pip install (S03 §2) | pending | — |

**Gate:** Shim can call a minimal echo harness and complete a 3-turn conversation.

---

## PHASE 3: SDK Libraries

| ID | Task | Status | Worker |
|---|---|---|---|
| P3-01 | Implement Go SDK: harness interface, HTTP handler, middleware (S04 §2) | pending | — |
| P3-02 | Implement Go SDK: testbed (MockHermes, assertions) (S04 §6) | pending | — |
| P3-03 | Implement Go SDK: examples (minimal, echo, consensus reference) | pending | — |
| P3-04 | Implement Python SDK: BaseHarness ABC, FastAPI router (S04 §3) | pending | — |
| P3-05 | Implement Python SDK: testbed (MockHermes, pytest fixtures) | pending | — |
| P3-06 | Implement TypeScript SDK: Harness interface, Hono router (S04 §4) | pending | — |
| P3-07 | Implement TypeScript SDK: testbed (MockHermes, vitest helpers) | pending | — |
| P3-08 | Publish Go SDK to `github.com/coding-herms/h3-sdk-go` | pending | — |
| P3-09 | Publish Python SDK to PyPI (`h3-harness-sdk`) | pending | — |
| P3-10 | Publish TypeScript SDK to npm (`@coding-herms/h3-harness-sdk`) | pending | — |

**Gate:** All 3 SDK examples pass the test battery.

---

## PHASE 4: Test Battery

| ID | Task | Status | Worker |
|---|---|---|---|
| P4-01 | Implement `test_battery.py` — full compliance suite, 43 tests (S05) | pending | — |
| P4-02 | Implement Category 1: Health & Protocol (7 tests) | pending | — |
| P4-03 | Implement Category 2: Process — Basic Flows (8 tests) | pending | — |
| P4-04 | Implement Category 3: Process — Decision Types (6 tests) | pending | — |
| P4-05 | Implement Category 4: Result Handling (7 tests) | pending | — |
| P4-06 | Implement Category 5: Error & Edge Cases (10 tests) | pending | — |
| P4-07 | Implement Category 6: Stress & Performance (5 tests) | pending | — |
| P4-08 | Add `hermes h3 test` CLI command | pending | — |
| P4-09 | Add GitHub Actions workflow for CI compliance testing (S05 §6) | pending | — |

**Gate:** Test battery passes against all 3 SDK echo examples.

---

## PHASE 5: Installer & Versioning

| ID | Task | Status | Worker |
|---|---|---|---|
| P5-01 | Implement `hermes h3 install` — full flow with version check (S03 §2) | pending | — |
| P5-02 | Implement `hermes h3 scaffold` — harness template generator (S03 §6) | pending | — |
| P5-03 | Create `versions.yaml` — Hermes↔H3 compatibility matrix (S03 §7) | pending | — |
| P5-04 | Implement Hermes update pre-flight hook — blocks incompatible versions (S03 §2.4) | pending | — |
| P5-05 | Implement backward compatibility test matrix (S03 §7.4) | pending | — |

**Gate:** `hermes h3 scaffold --lang go` → `hermes h3 test` passes on generated harness.

---

## PHASE 6: Documentation & Release

| ID | Task | Status | Worker |
|---|---|---|---|
| P6-01 | Write h3.sh landing page with Quickstart | pending | — |
| P6-02 | Write migration guide: native → H3 harness | pending | — |
| P6-03 | Write harness developer guide ("Build Your First H3 Harness") | pending | — |
| P6-04 | Record compliance badge system (passing test battery = badge in README) | pending | — |
| P6-05 | Publish OpenAPI 3.1 spec: `h3-protocol.yaml` | pending | — |

**Gate:** External developer can go from zero → working harness in < 30 min using docs.

---

## Phase Gates

| Phase | Gate | Blocks |
|---|---|---|
| P0 | GitReins guard passes, repo pushable | Everything |
| P1 | Protocol round-trip tests pass | P2, P3 |
| P2 | Shim completes 3-turn conversation with echo harness | P4 |
| P3 | All 3 SDKs pass test battery | P5 |
| P4 | Test battery passes against all examples | P6 |
| P5 | Scaffold → test battery end-to-end | P6 |
| P6 | External dev docs complete | Release |
