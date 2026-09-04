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
