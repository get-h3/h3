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
