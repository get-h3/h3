# get-h3 — Cross-Repo Task Board

> Discovery sweep: 2026-07-18 17:21 UTC. Verified against all 6 repos.

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

**Gate: 11/11 specs written. ✅ MET.**

---

## PHASE 0: Protocol (Single Source of Truth) ✅

| ID | Repo | Task | Status |
|---|---|---|---|
| P0-01 | protocol | Write `h3-protocol.yaml` — OpenAPI 3.1 from S02 + S07 | ✅ Done |
| P0-02 | protocol | Write all 13 JSON Schema files under schemas/v1/ | ✅ Done |
| P0-03 | protocol | Write 8 example payloads under examples/decisions/ | ✅ Done |
| P0-04 | protocol | Validation script + round-trip tests | ✅ Done |
| P0-05 | protocol | CI: validate on PR, release on tag | ✅ Done |
| P0-06 | protocol | Tag v1.0.0 | ⌛ pending (after P5-01) |

**Gate: Schemas + examples validated. CI green. ✅ MET (P0-06 deferred to first release).**

---

## PHASE 1: SDKs (Generated from Protocol) ✅

| ID | Repo | Task | Status |
|---|---|---|---|
| P1-01 | sdk-go | Regenerate types from protocol JSON Schema | ✅ Done (protocol/types.go, 22 Go types) |
| P1-02 | sdk-go | Harness interface + HTTP handler + middleware | ✅ Done |
| P1-03 | sdk-go | Test bed (MockHermes) + assertions | ✅ Done |
| P1-04 | sdk-go | Examples: minimal, echo | ✅ Done |
| P1-05 | sdk-python | Regenerate Pydantic models from protocol JSON Schema | ✅ Done (protocol.py, 15+ models) |
| P1-06 | sdk-python | BaseHarness ABC + FastAPI router | ✅ Done |
| P1-07 | sdk-python | Test bed (MockHermes) + pytest fixtures | ✅ Done |
| P1-08 | sdk-python | Examples: minimal, echo | ✅ Done |
| P1-09 | sdk-typescript | Regenerate Zod schemas from protocol JSON Schema | ✅ Done (protocol.ts, 30+ exports) |
| P1-10 | sdk-typescript | Harness interface + Hono router | ✅ Done |
| P1-11 | sdk-typescript | Test bed (MockHermes) + vitest helpers | ✅ Done |
| P1-12 | sdk-typescript | Examples: minimal, echo | ✅ Done |

**Gate: All 3 SDKs implement echo harnesses. ✅ MET.**

---

## PHASE 2: Shim (Hermes Plugin) ✅

| ID | Repo | Task | Status |
|---|---|---|---|
| P2-01 | shim | protocol.py — Pydantic models (regenerated from protocol) | ✅ Done |
| P2-02 | shim | client.py — REST client for harness communication | ✅ Done |
| P2-03 | shim | loader.py — discovery, health check, routing | ✅ Done |
| P2-04 | shim | shim_loop.py — main H3ShimLoop | ✅ Done |
| P2-05 | shim | Decision executors: tool_call, llm_call, text, wait, delegate | ✅ Done |
| P2-06 | shim | native.py — native Hermes loop wrapper | ✅ Done |
| P2-07 | shim | cli.py — `hermes h3` subcommands | ✅ Done |

**Gate: Shim 151/151 unit tests pass. CLI fully wired. ✅ MET.**

---

## PHASE 3: Test Battery (THE GATE) ⚠️

| ID | Repo | Task | Status |
|---|---|---|---|
| P3-01 | shim | test_battery.py — TestRunner, H3Client, AssertionEngine, ReportGenerator | ✅ Done |
| P3-02 | shim | Region 1: Health & Protocol (7 tests) | ✅ Done |
| P3-03 | shim | Region 2: Process Flows (8 tests) | ✅ Done |
| P3-04 | shim | Region 3: Decision Types (6 tests) | ✅ Done |
| P3-05 | shim | Region 4: Result Handling (7 tests) | ✅ Done |
| P3-06 | shim | Region 5: Edge Cases (10 tests) | ✅ Done |
| P3-07 | shim | Region 6: Stress (5 tests) | ✅ Done |
| P3-08 | shim | CLI: `h3-test --endpoint URL [--json\|--html\|--smoke]` | ✅ Done |
| P3-09 | shim | CI: GitHub Actions compliance workflow | ✅ Done |
| P3-10 | shim | Publish `hermes-h3-shim` to PyPI | ⌛ pending (after first protocol release) |

**h3-test results against SDK echo harnesses:**
| Harness | Score | Notes |
|---|---|---|
| sdk-go echo | 43/43 ✅ | Fixed in sdk-go@6f1aaa1 — capabilities, streaming, history echo |
| sdk-python echo | 39/43 | 4 fails: shim-side payload gaps (fixtures need spec-compliant payloads) |
| sdk-typescript echo | 41/43 | 2 fails: streaming (finished=false), history preservation. CROSS-003 filed. |

**Gate: 43/43 against ALL 3 examples. ⚠️ NOT MET — sdk-typescript needs 2 fixes, sdk-python needs 4 (shim-side).**

---

## PHASE 4: Installer & Scaffold

| ID | Repo | Task | Status |
|---|---|---|---|
| P4-01 | shim | `hermes h3 install` — plugin registration, version check, pip install | ✅ Done |
| P4-02 | shim | `hermes h3 scaffold --lang go/python/ts` — harness template generator | ✅ Done |
| P4-03 | shim | `hermes h3 verify` — post-install/post-upgrade verification | ✅ Done |
| P4-04 | protocol | `versions.yaml` — Hermes↔H3 compatibility matrix | ✅ Done |
| P4-05 | shim | Hermes update pre-flight hook (S11 §3) | ⌛ pending |

---

## PHASE 5: Release Pipeline ⚠️

| ID | Repo | Task | Status |
|---|---|---|---|
| P5-01 | protocol | Release workflow: validate → tag → dispatch to downstream | ⚠️ UNBLOCKED (SDK sync workflows exist now) |
| P5-02 | sdk-go | Sync-protocol workflow: regenerate → test → release | ✅ Done |
| P5-03 | sdk-python | Sync-protocol workflow: regenerate → test → release | ✅ Done |
| P5-04 | sdk-typescript | Sync-protocol workflow: regenerate → test → release | ✅ Done |
| P5-05 | shim | Sync-protocol workflow + PyPI publish | ✅ Done |
| P5-06 | h3 | Cross-repo integration test: protocol change → all SDKs update → test battery passes | ⌛ pending (needs P5-01 first) |

**Gate: P5-01 unblocked — all receiver workflows exist. ✅ PROCEED.**

---

## PHASE 6: Docs & Website ⚠️

| ID | Repo | Task | Status |
|---|---|---|---|
| P6-01 | h3 | h3.sh landing page with Quickstart | ✅ Done (docs/index.html, 811 lines, deployed) |
| P6-02 | h3 | Language picker (Go/Python/TS) with copy-paste code | ✅ Done (tab-based picker + copy buttons) |
| P6-03 | h3 | Protocol reference (auto-generated from OpenAPI) | ✅ Done (docs/protocol.html, 879 lines) |
| P6-04 | h3 | SDK docs (auto-generated) | ✅ Done (docs/sdk.html, 950 lines) |
| P6-05 | h3 | Compliance badge system + verify endpoint | ✅ Done (3 badge SVGs, copy-paste code, h3-test section) |
| P6-06 | h3 | "Build Your First H3 Harness" guide | ⚠️ Partial — basic quickstart exists; missing: RAG agent example, code review example, troubleshooting |
| P6-07 | h3 | Migration guide: native → H3 | pending — no migration content in any page |

**Gate: Website deployed, landing page + protocol + SDK refs live. ⚠️ PARTIAL — P6-06 expansion + P6-07 migration guide remain.**

---

## CROSS-REPO BLOCKERS

### [x] CROSS-001 — sdk-go echo harness: fix 3 issues to reach 43/43 h3-test ✅

sdk-go/examples/echo/main.go needed 3 fixes (identified by shim CI sweep):

1. Health(): add `Capabilities: []protocol.DecisionType{protocol.DecisionText}`
2. OnProcess(): detect "do not finish" → `Finished: false`
3. OnProcess(): add `History: req.Context.History` to returned Decision

**Resolved:** sdk-go@6f1aaa1 — "fix: echo harness — 43/43 compliance, add capabilities, streaming, history echo"
**Verified by:** shim@3b48554 — "mark CI compliance task complete — 43/43 PASS"

**Blocks:** PHASE 3 gate, shim CI compliance job (40/43 → 43/43)
**Assignee:** sdk-go-foreman
**Priority:** P1 (gate-blocking)

---

### [x] CROSS-002 — sdk-typescript: clean up dirty workdir + reconcile P5-05 ✅

Workdir now clean (`git status --short` empty at 5056ec4). P5-05 generator fidelity resolved (commit 6cc68fb). 

**Resolved:** sdk-typescript@6cc68fb + clean workdir verified 2026-07-18 20:43 UTC.

**Assignee:** sdk-typescript-foreman
**Priority:** P2 (cosmetic, workdir hygiene)

---

### [ ] CROSS-003 — sdk-typescript: history preservation in harness router (QV-GAP-03)

h3-test `process_preserves_history` fails: history entries not echoed in `/v1/result` responses. Fix: store session history in `createH3Router`, include at top-level `history` and `context.history` in result JSON. Same pattern as sdk-go QV-GAP-01.

**h3-test before fix:** 41/43 (history + streaming failures)
**Expected after fix:** 42/43 (streaming failure only, known echo-harness gap)

**Blocks:** PHASE 3 gate (needs 43/43 from all 3 echo harnesses)
**Assignee:** sdk-typescript-foreman
**Priority:** P2 (gate-blocking but streaming gap remains)

---

## Phase Gates Summary

| Phase | Gate | Status |
|---|---|---|
| P-1 | 11/11 specs written | ✅ MET |
| P0 | Protocol schemas + examples validated | ✅ MET |
| P1 | All 3 SDKs pass test battery | ⚠️ Go: 43/43 ✅, TS: 41/43, Py: 39/43 (shim payload gaps) |
| P2 | Shim completes 3-turn conversation | ✅ MET |
| P3 | Test battery passes against all examples | ⚠️ BLOCKED on CROSS-003 (TS history) + shim payload fixes (Py) |
| P4 | Scaffold → test passes end-to-end | ⚠️ P4-05 pending |
| P5 | One tag → full cascade release | ⚠️ P5-01 pending, P5-06 pending |
| P6 | External dev zero→harness < 30 min | ⚠️ P6-01–P6-05 done (website live), P6-06 partial, P6-07 pending |

---

## Discovery Sweep — 2026-07-19 13:18 UTC

**Scope:** h3 umbrella repo — P6 audit (website verification)

| Check | Result |
|---|---|
| Pages | ✅ https://get-h3.github.io/h3/ — HTTP 200, deployed |
| P6-01 Landing | ✅ docs/index.html (811 lines, 44KB) — hero, architecture SVG, quickstart |
| P6-02 Language picker | ✅ Tab-based Go/Python/TS with copy-paste code |
| P6-03 Protocol ref | ✅ docs/protocol.html (879 lines, 40KB) — OpenAPI endpoints, decision types |
| P6-04 SDK docs | ✅ docs/sdk.html (950 lines, 40KB) — Go/Python/TS SDK reference |
| P6-05 Badges | ✅ docs/badge/ (compliant, not-compliant, unknown SVGs) + copy-paste code |
| P6-06 Harness guide | ⚠️ Quickstart exists; missing: RAG example, code review example, troubleshooting |
| P6-07 Migration guide | ❌ No migration content in any page — needs docs/migration.html |
| Cross-repo blockers | CROSS-003 still open (sdk-typescript history preservation, assigned to sdk-typescript-foreman) |
| h3 repo | ✅ Clean except tasks.md (this board update) |

### [x] INFRA-PAGES — Verify GitHub Pages deployment succeeds ✅

Pages workflow created (`.github/workflows/pages.yml`), pushed, and deployed.
- CI run: [29667911668](https://github.com/get-h3/h3/actions/runs/29667911668) — success
- Deployed: https://get-h3.github.io/h3/ — HTTP 200, 44KB landing page

**Assignee:** h3-foreman
**Priority:** P2 (unblocks P6 visibility)

---

## Next Actions

1. **sdk-typescript-foreman**: Fix CROSS-003 (history preservation in `createH3Router`) — gate-blocking PHASE 3 at 41/43
2. **protocol-foreman**: Execute P5-01 (release workflow: validate → tag → dispatch) — unblocked, all receiver workflows exist
3. **h3-foreman**: P6-07 migration guide (native → H3) — next pending task; S11 spec provides full content outline
4. **h3-foreman**: P6-06 expansion (RAG + code review examples, troubleshooting) — after P6-07
5. **shim-foreman**: P4-05 Hermes update pre-flight hook — still pending
