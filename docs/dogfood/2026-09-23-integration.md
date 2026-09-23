# H3 Umbrella Dogfood — 2026-09-23 (docs-following consumer + chained-tool loop + bunker install leg)

**Runner:** dogfood tick h3-dogfood-2026-09-23-01-11-49 (coding-hermes-dogfood skill v1.2.0, Step 2b per coding-hermes-perf)
**New surface (prior runs tested OTHER people's harnesses: echo examples, scaffolds, PyPI echo on :9191):** a fresh developer writing a from-scratch consumer against the DOCS ONLY with the published SDK, driving the full agentic loop (process → tool_call → result → chained tool_call → result → end), session lifecycle (GET/DELETE/404, cancel), plus the h3 repo's own `make verify` from a fresh public clone.

## Promise vs Reality

**Promise:** "Swap your agent's brain" — a developer installs a harness SDK, implements the Loop (Hermes sends ProcessRequest, harness returns Decisions, Hermes executes and reports ResultRequests, until Decision.end), and `h3-test` gates compliance.

**Reality: HOLDS — SHIPPABLE.** The full chained-tool workflow works end-to-end over the wire, the battery is honest (caught my real non-compliance), and the SDK's failure masking, while surprising, is documented once found. Four docs/naming traps cost a real developer ~3 debug cycles; every one is now written down.

## What was run

| # | Leg | Result |
|---|-----|--------|
| 1 | `uv pip install git+https://github.com/get-h3/sdk-python` → h3-harness-sdk 0.1.6 (2.6s) | ✅ |
| 2 | From-scratch `DeployBotHarness` written from README+integration.md only (scratch /tmp/dogfood-h3-20260923) | ✅ after 3 docs-driven fixes (below) |
| 3 | Full loop: process→tool_call→result→tool_call→result→end(task_complete, "Deployed and verified") + GET session(completed)→DELETE→GET 404 + cancel | ✅ server log clean |
| 4 | h3-test battery vs my harness | 45/46 first (real catch), 46/46 after implementing the documented "do not finish" convention. exit 0 |
| 5 | Perf: cold boot-to-ready 239ms, first /v1/process 1.2ms; warm process 6.2ms±0.5 (n=20); battery 0.32s warm / 727ms±324ms incl. python startup | ✅ nothing a user would feel — no PERF row filed |
| 6 | Bunker install leg (las-bunker-03, agent efc4d4ce, rootless Debian): clone h3 (4s) → `make verify` → **FAILED rc=2** (DF-H3-25) | ❌ gate RED at public HEAD 8b3cbc5 |
| 7 | Bunker: clone shim + `pip install -e .` (10s) + h3-test --version | ✅ |
| 8 | Bunker: `pip install h3-harness-sdk` (PyPI) → echo harness → battery 46/46 | ✅ after catching a false PASS on a co-tenant's leftover server (DF-H3-26) |
| 9 | Agent destroyed, absence verified (0 passwd entries, 0 containers) | ✅ |

## The three traps a docs-following developer hits (all filed)

1. **README says `tool_use`, wire enum is `tool_call`** (DF-H3-27). `DecisionType.TOOL_USE` → AttributeError → the router masks it as HTTP 200 `{decision:"end", end:{reason:"error", summary:"<exception>"}}`. Silent loop death that looks compliant. `grep end.summary server.log` finds it; `create_router(..., debug_errors=True)` raises instead.
2. **`on_result` has no context; `req.result` is a plain dict** (DF-H3-28). `ResultRequest` = `decision_id, result, session_id` only. `req.result.success` (attribute) silently returns `False` → my harness reported "Deploy had failures" with zero errors. integration.md documents neither the result schema nor `on_result` at all (grep = 0 hits).
3. **"do not finish" convention** (DF-H3-29) — only in specs/02, specs/05, integration.md:293; README quickstart never mentions it → first battery run fails test 2.4.

## The false PASS that matters (DF-H3-26)

Bunker leg 8 first ran the documented `:9191`: my echo's output redirect hit an unwritable path → uvicorn bind failed silently → `h3-test` returned **46/46 PASSED rc=0 against a stranger's 2.6-day-old leftover harness** (health: uptime_seconds=228122, active_sessions=288, capabilities=["text"] only — no tool_call). Caught because the health-check habit (this skill, DF-H3-15 lesson) demanded reading uptime before trusting the result. Battery fix direction filed: print target uptime/identity, `--expect-fresh` flag.

## Board rows

DF-H3-25 (P1, make verify RED at fresh clone — header sync skipped on ticks #480/#481; the DF-H3-24 guard correctly catches it), DF-H3-26 (P1, false PASS), DF-H3-27/28 (P2, docs/SDK contract), DF-H3-29 (P3, onboarding). Committed e0ef6e9, pushed to origin/main.

## Foreman

h3 was mid-tick #482 while this run filed rows (rows pushed first; tick rebases). Not woken — 43200s cadence is the deliberate GAP-003 pin; 5 fresh rows (2×P1) will surface on its next evaluation.
