# Dogfood Log

Real-use field tests of this project (cron: coding-hermes-dogfood). Each run
answers: "does this project actually work for a real user, and is it worth it?"
— evidence in docs/dogfood/.

## 2026-08-02 — Verdict: 🟡 PROMISING-BUT-ROUGH

- **Promise:** "A developer can build an H3-compliant harness (brain) for
  Hermes in ~30 seconds via `hermes h3 scaffold` + `h3-test` (43 tests), or
  implement their own custom harness from the spec alone."
- **Reality:** The protocol, SDKs and test battery genuinely deliver — Go
  scaffold 43/43, Python SDK echo 43/43, spec-only custom harness 43/43
  (after 2 undocumented conventions), battery runs in ~0.2s. BUT the
  documented onboarding is broken for anyone outside the fleet: nothing is
  published on PyPI (`pip install hermes-h3-shim` → "No matching distribution
  found"), and the scaffolded Go harness does not build (`sdk-go v0.0.0:
  unknown revision` — no tags published, replace commented out).
- **Top 3 findings:** DOGFOOD-01 (nothing on PyPI), DOGFOOD-02 (scaffold
  doesn't build without local fleet checkout), DOGFOOD-03 (2 compliance
  conventions undocumented in specs/02: history echo + "do not finish"
  streaming marker).
- **Time-to-first-success:** BLOCKED on the documented path (install fails);
  ~25 min via source-install workarounds; ~50 min spec-only (incl. reading
  test battery source for the 2 conventions).
- **Friction count:** 8 (PyPI missing, sdk-go untagged, hermes-h3 vs
  `hermes h3` naming, scaffold dir name, history echo undocumented, "do not
  finish" convention undocumented, Python echo hardcoded port 8000, board
  buried in tick log).
- **What passed:** h3-test CLI (human + JSON output, exit 0/1 discipline),
  hermes-h3 install/list/verify/test management flow, error shapes per
  specs/02 §9, spec-only implementability (41/43 from docs alone).
- **Artifacts:** docs/dogfood/2026-08-02-integration.md (integration
  report), docs/dogfood/diagnostics.md (diagnostic trail),
  skills/h3-usage/SKILL.md (agent usage skill). Board: DOGFOOD-01..06.
- **Foreman:** healthy — enabled, 900s cooldown, decay=1, regular completed
  ticks (17:13/17:38/18:13 on run day); no wake/speed-up needed. No
  destructive actions taken; scratch work in /tmp/dogfood-h3.

## 2026-08-14 — Verdict: 🟡 PROMISING-BUT-ROUGH (2nd run)

- **Promise:** "Swap your agent's brain" — a developer can (a) follow the
  README Quick Start and verify an H3-compliant harness in minutes, and (b)
  scaffold a new harness in 30 seconds (`hermes-h3 scaffold --lang go`) whose
  output is H3-compliant (exit 0 = compliant, README L34-45).
- **Reality:** The Quick Start path now works end-to-end (fresh GitHub clones,
  fresh venv: shim source install → Go echo example → **44/44 in 0.22s**,
  exit 0) and all three SDK echo examples pass 44/44 (Go/Python/TS verified
  live). BUT the flagship scaffold path is broken in ALL 3 languages: go
  scaffold 43/44 (template pins sdk-go v0.1.0; 404-on-cancel fix only in
  v0.1.1), py scaffold 43/44 (same test; template on_cancel never 404s), ts
  scaffold cannot install (`npm E404 @get-h3/h3-harness-sdk`). The README's
  "scaffold in 30 seconds" promise produces a NON-compliant harness in every
  language. Regression shipped 2026-08-08 and survived 8 days — no gate runs
  the battery against scaffold output, only against SDK examples.
- **Top 3 findings:** DOGFOOD-07 (go scaffold 43/44, v0.1.0 pin), DOGFOOD-08
  (py scaffold 43/44, no 404 on cancel), DOGFOOD-09 (ts scaffold uninstallable
  — unpublished npm dep in template). Plus DOGFOOD-10 (no scaffold-compliance
  release gate) and DOGFOOD-11 (verify CLI positional-name inconsistency).
- **Time-to-first-success:** ~3 min (README Quick Start path, fresh env).
- **Friction count:** 4 (go scaffold non-compliant, py scaffold
  non-compliant, ts scaffold uninstallable, verify positional-name trap).
- **What passed:** README Quick Start (fixed since 2026-08-02: source install,
  venv step, sdk-go tags), h3-test CLI (help/exit codes/JSON report), SDK echo
  examples ×3 (44/44), hermes-h3 install/list/verify/test management flow,
  error-envelope discipline, battery speed (0.2-0.5s).
- **Artifacts:** docs/dogfood/2026-08-14-integration.md (integration report),
  docs/dogfood/diagnostics.md (E7-E9 appended), skills/h3-usage/SKILL.md
  (scaffold pitfalls + stale 44/44 claim corrected). Board: DOGFOOD-07..11.
- **Foreman:** healthy — enabled, 21600s cooldown (deliberate GAP-003 pin),
  decay=1, last tick completed 2026-08-14 17:16. Woken via PUT CooldownS=900
  after board write (dogfood tasks added); auto-heal restores 21600.
2026-09-01 | SHIPPABLE | 37s t2fs | friction 6 | 5 findings
2026-09-04 | SHIPPABLE | 40s t2fs | friction 8 | 5 findings
2026-09-07 | SHIPPABLE | 20s t2fs | friction 6 | 5 findings
2026-09-08 | SHIPPABLE | ~35s t2fs | friction 6 | 5 findings
- Promise: user scaffolds/runs an H3 harness; h3-test gates compliance (exit 0).
- Reality: HELD. 46/46 on five distinct endpoints: Go echo, Go scaffold,
  PyPI h3-harness-sdk 0.1.5 echo (:9192), TS SDK custom consumer (:9292),
  py scaffold in bunker. Battery 0.27-0.63s, exit codes honest.
- New findings: DF-H3-6 (decision_id UUID vs free-form: TS rejects what Go
  ships and docs show), DF-H3-7 (battery hidden trigger phrases
  'do not finish'/... → a correct-by-docs harness fails 15/46),
  DF-H3-8 (bunker fresh install: python3-venv/ensurepip missing, no-sudo
  bootstrap workaround, 13s), DF-H3-9 (Go echo+scaffold ignore PORT env),
  SKIPPED-install-bunker (bunker-las-03 offline ~1d; leg ran on las-04,
  agent be304d58 destroyed clean).
- Prior DF-H3-1..5 all re-verified as real (HERMES_H3_CONFIG grep=0 refs;
  battery live count 46 vs docs 44; scaffold :9191 hardcode; two install
  forms; no curl round-trip doc — friction trail reproduced 1:1).
- Artifacts: docs/dogfood/2026-09-08-integration.md; diagnostics.md E12-E14
  + trust anchors; skills/h3-usage/SKILL.md 4 new pitfalls + 46-count fix.
- Foreman: h3 enabled, 43200s cooldown; woken via PUT CooldownS=900 after
  5 new board rows (self-restores per cooldown-policy pin).

## 2026-09-18 — dogfood tick h3-dogfood-2026-09-18-06-16-03
- Verdict: SHIPPABLE (re-run of documented paths; prior 09-08 verdict holds).
- Promise: fresh user can install shim from source, run an H3 harness, and pass the compliance battery per README quick start — HELD.
- Real use: echo harness battery 46/46 exit 0 (p50 1.12ms); h3-test exit codes verified (0 compliant / 2 not-an-endpoint); scaffold --lang go + battery 46/46 with holder-attribution proof; scaffold --lang py on bunker 46/46 exit 0.
- Bunker install: clone 4.0s, pip -e 17.4s, smoke 46/46 exit 0 (agent 7520803b, destroyed clean).
- Friction (3): :9191 EADDRINUSE first-run on shared host (DF-H3-15); doc count drift 44/45/46 re-offense (DF-H3-16); first go mod tidy proxy fetch minutes (DF-H3-17 note).
- New rows: DF-H3-15, DF-H3-16, DF-H3-17.

## 2026-09-18 — dogfood tick h3-pm-2026-09-18 (PM lane itself; first pass)
2026-09-18 | PROMISING-BUT-ROUGH | install_seconds=24 | bunker=las-bunker-03 agent=437f91a0 | smoke=ok (46/46 exit 0)
- **Target:** the `h3-pm` scheduler lane (namespace pm, stand-in workdir), not a
  repo — real use = consuming its product. Promise: a daily PM cycle audits the
  h3 umbrella board with ledger-first tracking, G1-G7 gating, and re-verification
  of the previous cycle's fixes with real commands.
- **Real use:** re-ran the PASS criteria of the newest rows (H3-PM-005..009) as
  commands; 4/5 reproduce exactly, 1 is unmeasurable as written (repo-wide grep
  matches the row + judge artifacts quoting it: 11 live hits, 0 outside them).
  Resolved every commit_hash in the repo the row names; consumed H3-PM-003's
  commit_repo product (7/7 resolve in get-h3/shim).
- **Measured:** 43 of 104 open ledger items are already complete on their boards
  (41%) → the Step-5 prior-run list is mostly closed work. 6 board ids still hold
  rows with distinct findings (PM skill's own fingerprint method); 4 duplicate
  rows are superseded_by themselves.
- **Lane ops:** stand-in workdirs carry an EMPTY .coding-hermes/ (some have none)
  and the target→real-board resolution is undocumented (the retired
  pm-standin-tick.sh had it in code). Cycle log for the day is present in
  DuckBrain (/stand-in/2026-09-18/h3 + /cycle).
- **Install leg:** first `bunker spawn` hit deadline_exceeded (transient, no
  half-user left); retry succeeded. Documented shim quickstart on a bare Debian
  user: clone → venv → install → scaffold py → battery 46/46 exit 0 in 24s;
  agent destroyed clean.
- **Artifacts:** docs/dogfood/2026-09-18-h3-pm-integration.md,
  docs/dogfood/h3-pm-diagnostics.md, skills/h3-pm-usage/SKILL.md.
- **Rows:** DF-H3PM-01..05 filed on the h3 board (no cooldown change, foreman not woken).

## 2026-09-21 — dogfood tick h3-dogfood-2026-09-21-10-03-07
- Verdict: SHIPPABLE with one P1 gate break — first run against the h3 repo's OWN
  documented paths (runs 1-7 all tested the shim/SDK/battery products).
- Angle (new surface): `make verify`, `make verify-roundtrip`, README
  "Make your first call" hand-curl, session GET/DELETE workflow.
- Real use: Go echo battery 46/46 exit 0 (p50 0.69ms); README curl payload works
  verbatim (echo + history preserved); /v1/sessions/{id} GET 200 → DELETE 200 →
  GET 404 SESSION_NOT_FOUND envelope; DELETE with empty/{} body also 200 (undocumented
  laxness, non-blocking); round-trip suite 6/6 PASS rc=0.
- FOUND (DF-H3-23, P1): `make verify` RED at HEAD f22cf9f — verify-tick-chain
  "1 hole(s): 464". Tree has drifted /project/h3/tick/464 while bare /tick/464 is
  absent; 3rd occurrence of this drift shape (452/453 precedent). Writer bug, gate
  correctly catching it. HEAD commit message claims tick #465 ran green — false at
  merge time.
- Bunker install leg: fresh clone f22cf9f on las-bunker-03 agent a1d6544c →
  `make verify` ALL PASS rc=0 in 2s (tick-chain cell honestly UNVERIFIED with no
  DuckBrain token, per documented convention). Destroyed clean, absence verified.
  t2fs for the repo-as-product: ~7s (clone+verify).
- Friction (2): DF-H3-23 gate break above; minor — DELETE session body requirement
  undocumented (works without, but OpenAPI says required).
- Foreman: h3 enabled 43200s cooldown; NOT woken (h3 foreman cadence is deliberate
  GAP-003 pin; one open P1 row will surface on next tick).
- Artifacts: docs/dogfood/diagnostics.md E15 (tick-chain drift: writer vs census
  lesson); this log entry; board row DF-H3-23.
## 2026-09-23 — dogfood tick h3-dogfood-2026-09-23-01-11-49
- Verdict: SHIPPABLE — docs-following consumer reaches 46/46 and the full chained-tool loop works; rough edges are docs/naming, not product.
- Angle (NEW surface): from-scratch consumer written from README+integration.md only, PyPI/git SDK (0.1.6), full agentic loop with chained tool_calls + session lifecycle + cancel; h3 repo's own `make verify` from a fresh PUBLIC clone in the bunker (prior runs always tested shim/SDK products, never the hub's own gate).
- Real use: process→tool_call→result→tool_call→result→end(task_complete,"Deployed and verified") over live HTTP; GET session completed → DELETE → 404; cancel 200. Battery 45/46 first run (real catch: "do not finish" convention) → 46/46 exit 0 after fix. Server log clean throughout.
- Measured (Step 2b): cold boot-to-ready 239ms, first /v1/process 1.2ms; warm /v1/process 6.2ms±0.5 (hyperfine n=20); full battery 0.32s warm (p50 1.79ms/p95 35.6ms). Nothing a user would feel — no PERF row filed, deliberately.
- Bunker install leg (las-bunker-03 agent efc4d4ce): clone 4.0s; `make verify` FAILED rc=2 in 1s at public HEAD 8b3cbc5 (header 4 commits/2 ticks stale — DF-H3-25 P1, DF-H3-24 guard correctly catching); shim source install 10s → h3-test OK; PyPI SDK install + echo 46/46 on :9527 — first attempt on :9191 was a FALSE PASS against a co-tenant's 2.6-day-old leftover harness (DF-H3-26 P1; caught via health uptime_seconds=228122 check). Agent destroyed, absence verified (0 passwd, 0 containers).
- Friction (3): README "tool_use" vs wire enum tool_call, masked as 200 end(error) (DF-H3-27); integration.md documents neither ResultRequest fields nor on_result; req.result is a dict — attribute access silently False (DF-H3-28).
- New rows: DF-H3-25..29 (2×P1, 2×P2, 1×P3) — committed e0ef6e9, PUSHED to origin/main and verified (origin/main..HEAD=0).
- Foreman: h3 mid-tick #482 during this run; NOT woken (GAP-003 43200s pin is deliberate; fresh rows surface next evaluation).
- Artifacts: docs/dogfood/2026-09-23-integration.md; diagnostics.md E16; skills/h3-usage/SKILL.md refreshed (3 new pitfalls); this log entry.
2026-09-23 | SHIPPABLE | install_seconds=4(clone)+10(shim) | bunker=las-bunker-03 agent=efc4d4ce destroyed | smoke=ok(46/46 on :9527) + make-verify=FAIL(header, DF-H3-25)

## 2026-09-24 — dogfood tick h3-dogfood-2026-09-24-00-17-44
- Verdict: SHIPPABLE (5th consecutive) — both SDK surfaces deliver a battery-passing harness from docs alone; defects are docs-precision only.
- Angle (NEW surface): harness-author through sdk-go and sdk-typescript (never consumed by any prior run), documented entry paths only, gated by the 46-test battery; first fresh-machine PUBLISHED-route proof for both (module proxy / npm GitHub).
- Real use: Go quickstart verbatim -> build first-try -> 46/46 first try (p50 0.78ms). TS consumer via npm GitHub route -> 46/46 after README's serve + partial-turn steps (AGENTS.md quickstart serves nothing — DF-H3-30). Spec-conformance cross-check: hand-rolled payload missing identity.platform correctly rejected (common.json:55; validator error named the field — E17).
- Measured (Step 2b): battery 0.21s (Go) / 0.24s (TS); boot-to-ready cold 13ms (Go) / 135ms (TS); npm GitHub install 5.2s local / 16s agent; go get v0.1.8 via proxy 11s + build 19s (agent). Nothing a user would feel — no PERF row filed, deliberately.
- Bunker install leg (las-bunker-03 agent 21419eff, bare Debian 13, no sudo, go MISSING): clone 2.7s (HEAD 071a08f = local); TS npm route 16s + serve + health 200; Go: toolchain extracted to ~/go-toolchain (go1.26.6 via dl.google.com), go get 11s, build 19s, spec-shaped /v1/process smoke -> correct echo decision. Battery itself not installable on agent (shim is source-only + venv needs sudo = DF-H3-8 class, known). Agent destroyed, absence verified (0 passwd, 0 containers).
- Friction (2): TS AGENTS.md quickstart gap (serve + partial turns buried in README — DF-H3-30 P2); Go README 1.22+ floor vs go.mod reality + no fresh-machine go-precheck (DF-H3-31 P3).
- New rows: DF-H3-30..31 (1×P2, 1×P3) — committed a38d988 (rows only; releng's uncommitted RELEASE-H3-006 row left byte-exact as found). NOT pushed (see Foreman).
- Foreman: h3 idle since #499 (cooldown 43200s pin deliberate); 2 fresh pending rows will surface at next evaluation. NOT woken.
- Artifacts: docs/dogfood/2026-09-24-integration.md; diagnostics.md E17; skills/h3-usage/SKILL.md (44/44->46/46 sweep + new published-routes section); this log entry.
2026-09-24 | SHIPPABLE | install_seconds=16(ts)+11(goget)+19(gobuild) | bunker=las-bunker-03 agent=21419eff destroyed | smoke=ok(46/46 go local; 46/46 ts local; health+process smoke on agent)

## 2026-09-24 — dogfood tick h3-dogfood-2026-09-24-22-15-26 (run 9)
- Verdict: PROMISING-BUT-ROUGH — first run of the H3Loader resilience surface (the
  Hermes-side half of the brain-swap promise); happy-path failover works, recovery
  is structurally broken (P0).
- Angle (NEW surface): H3Loader (shim loader.py) — discovery, session routing,
  background health loop, circuit breaker, reroute; kill-the-harness scenario.
  No battery test does this; runs 1-8 never drove the loader.
- Real use: resolve precedence (thread>chat>platform>default) ✓; route_session/
  get_session_harness ✓; kill harness → reroute to native at 85s local / 90s bunker
  (3 × 30s health interval); new sessions during outage → native ✓.
- FOUND (DF-H3-34, P0): circuit breaker can NEVER leave OPEN — health loop skips
  OPEN harnesses and is the ONLY feeder of record_outcome/allow_request
  (allow_request has ZERO call sites in src/), so the half-open probe never fires.
  Measured OPEN 300s straight (documented knobs window=2/threshold=0.5/cooldown=3s)
  with harness restarted and healthy at +180s. One transient outage = harness
  disabled for the life of the host process.
- FOUND (DF-H3-33, P1): reroute not durable — resolve() reads static config while
  reroute rewrites _session_routes; fresh host mid-outage (and any host restart)
  resolves pinned sessions to the DEAD harness. Healthy flag also boots False for
  live harnesses (up to 30s).
- FOUND (DF-H3-35, P2): docs overpromise — integration.md:175 "reroutes
  immediately" (measured 85-90s); no recovery contract documented at all.
- Measured (Step 2b): reroute latency is the finding (85-90s vs "immediately");
  boot→first-healthy ~0.5s; battery on bunker 0.59s. No PERF row — nothing slow
  beyond the documented failover gap, which is a correctness/latency-contract row
  (DF-H3-35), not an optimization target.
- Bunker install leg (las-bunker-03 agent f914cf7d, bare Debian 13): clone 5.3s
  (HEAD 9af6d50), install 15s (venv --without-pip + get-pip + pip install -e .),
  scaffold py, full resilience scenario REPRODUCED on the fresh box (reroute 90s,
  resolve-at-boot→dead name), battery 46/46 exit 0 in 0.59s. Agent destroyed,
  absence verified (0 passwd entries; only pre-existing co-tenant containers).
- Friction (3): the three rows above.
- Foreman: h3 enabled 43200s deliberate pin; NOT woken (rows surface next
  evaluation). Board committed surgically (3 rows only).
- Artifacts: docs/dogfood/2026-09-24b-integration.md; diagnostics.md E18;
  skills/h3-usage/SKILL.md (loader-resilience section + repro config); this entry.
2026-09-24 | PROMISING-BUT-ROUGH | install_seconds=15 | bunker=las-bunker-03 agent=f914cf7d destroyed | smoke=ok(46/46, 0.59s; resilience scenario reproduced)

## 2026-09-25 — dogfood tick h3-dogfood-2026-09-25-22-57-33 (run 10)

- Verdict: SHIPPABLE (6th consecutive verdict run) — the control-plane CLI
  (hermes-h3) delivers the full harness lifecycle honestly; defects are
  staleness/cosmetic, none break real use.
- Angle (NEW surface): the harness CONTROL PLANE — install / list / use /
  route (set/remove/show) / verify (+ --fallback) / pre-update-check /
  uninstall against a live scaffolded harness. Runs 1-9 never exercised the
  lifecycle commands (they tested scaffold output, SDKs, battery, loader
  internals, make verify).
- Promise: "A harness author can register a running harness, pin a session
  to it, verify its health, pre-flight a Hermes upgrade against the compat
  matrix, and remove it — all from the CLI, config-backed and fail-closed."
- Reality: lifecycle works end-to-end from empty config (0.15s scaffold) —
  install (0.46s, health-probes on register), verify, use, route
  set/show/table/remove, uninstall, all exit-code disciplined, fail-closed
  on unknown harness/session, config survives a dead endpoint without
  corruption. Battery 46/46 in 0.42s against the registered harness.
- Found (DF-H3-36, P1): pre-update-check BLOCKs on EVERY real Hermes
  version — bundled matrix tops at 0.20.0 (installed Hermes: 0.21.1), and
  even 'planned' rows block on shim 0.1.0 vs required 1.1.0/2.0.0. The
  safety check can never say "safe" on a current system.
- Found (DF-H3-37..39, P2): verify prints enum repr 'HealthStatus.OK'
  instead of the wire value 'ok'; verify --fallback hard-codes the
  resilience narrative in cli.py (re-creating the DF-H3-35 docs drift,
  incl. 'reroutes immediately'); pre-update-check permanently warns about
  a config-schema v0->v1 migration that exists nowhere in the codebase.
- Measured (Step 2b, all warm, hyperfine --warmup 3 --runs 20):
  list 193ms ±34, route 163ms ±24, verify 292ms ±18 (raw HTTP round-trip
  3.9ms — ~288ms is CLI/Python startup); cold battery 0.62s vs 0.42s warm;
  harness boot->healthy 17ms; install 0.46s. Nothing a user would feel —
  no PERF row filed.
- Bunker install leg: SKIPPED-install-bunker (DF-H3-40) — bunker-las-03
  offline (tailscale 'last seen 5h ago', ssh connect timeout, bunker list
  deadline_exceeded). Latest installability proof remains 2026-09-24b
  (15s install, 46/46). Not a silent pass.
- Friction (4): the four rows above.
- Foreman: h3 enabled, 43200s deliberate pin; NOT woken (rows surface next
  evaluation). Board committed surgically (5 rows only).
- Artifacts: docs/dogfood/2026-09-25-integration.md; diagnostics.md E19;
  skills/h3-usage/SKILL.md (control-plane section); this entry.

