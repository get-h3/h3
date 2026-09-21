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
