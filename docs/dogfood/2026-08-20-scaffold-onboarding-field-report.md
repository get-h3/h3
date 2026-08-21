# Dogfood Field Report — Scaffold Onboarding Path (post-fix verification)

**Date:** 2026-08-20
**Tick:** h3-2026-08-20-23-05-23 (umbrella #329)
**Type:** Point-in-time field verification of the scaffold → battery onboarding path
**Status:** ✅ PASS — 44/44, exit 0

## Context

The 2026-08-14 dogfood report (`2026-08-14-integration.md`) recorded the scaffolded
Go harness failing the compliance battery at **43/44 (exit 1)** — the
`cancel_unknown_session` case ("Expected 404, got 200"). Root causes were fixed in
the shim templates between 2026-08-14 and 2026-08-15:

| Fix | Repo/commit | What changed |
|---|---|---|
| DOGFOOD-07 | get-h3/shim `5f665e5` | Go template go.mod: sdk-go v0.1.0 → v0.1.1 (404-on-unknown-cancel fix only in v0.1.1) |
| DOGFOOD-08 | get-h3/shim `ba2b074` | Python template `on_cancel` now raises HTTPException 404 for unknown session_id |
| DOGFOOD-09 | get-h3/shim `6214248` | TS template: unpublished npm dep → `github:get-h3/sdk-typescript`; UUID decision_id fix |
| DOGFOOD-10 | get-h3/shim `8568cb3` | Scaffold-compliance CI job added (fresh scaffold + h3-test must be 44/44) |

This report records a fresh, independent re-run of the exact path that failed on
2026-08-14 (Go scaffold → battery), plus a Python-scaffold re-run, so the evidence
trail contains a post-fix point-in-time record rather than only a retroactive banner.

## Environment

- Host: karaHermes (Linux), America/Bogota (UTC-5)
- CLI: `hermes-h3` 0.1.x (scaffold), `h3-test` 0.1.0 (battery), from board venv
- Go: system toolchain, `go mod tidy` resolved `github.com/get-h3/sdk-go v0.1.1` from the network
- Ports: :9191 free at start and at end (no concurrent harness)

## Run 1 — Go scaffold (the 2026-08-14 failing path)

```bash
$ hermes-h3 scaffold --lang go --output-dir /tmp/h3_20260820_gap059
$ cd /tmp/h3_20260820_gap059/h3-harness-go && go mod tidy && go build .
$ ./h3-harness-go &            # listens on http://localhost:9191
$ curl -s -o /dev/null -w "%{http_code}" http://localhost:9191/v1/health
200
$ h3-test --endpoint http://localhost:9191
```

```
H3 Compliance Test Battery v0.1.0
Target: http://localhost:9191
Transport: REST

  Health & Protocol                   7/7   ✅ PASSED
  Process Basic Flows                 8/8   ✅ PASSED
  Decision Types                      6/6   ✅ PASSED
  Result Handling                     7/7   ✅ PASSED
  Error & Edge Cases                  11/11 ✅ PASSED
  Stress & Performance                5/5   ✅ PASSED
  TOTAL                               44/44 PASSED
  Duration                            0.37s
  Latency p50/p95                     1.46ms / 47.06ms
```

**Exit code: 0** — the `cancel_unknown_session` 404 case now passes
(sdk-go v0.1.1 ships the fix; template go.mod requires v0.1.1).

## Run 2 — Python scaffold

```bash
$ hermes-h3 scaffold --lang py --output-dir /tmp/h3_20260820_gap059_py
$ cd /tmp/h3_20260820_gap059_py/h3-harness-py && python3 -m venv .venv && .venv/bin/pip install -q -e .
$ .venv/bin/python main.py &   # FastAPI harness on :9191 (after Go run ended)
$ h3-test --endpoint http://localhost:9191
```

```
  Health & Protocol                   7/7   ✅ PASSED
  Process Basic Flows                 8/8   ✅ PASSED
  Decision Types                      6/6   ✅ PASSED
  Result Handling                     7/7   ✅ PASSED
  Error & Edge Cases                  11/11 ✅ PASSED
  Stress & Performance                5/5   ✅ PASSED
  TOTAL                               44/44 PASSED
  Duration                            0.80s
  Latency p50/p95                     2.58ms / 107.26ms
```

**Exit code: 0.** Python template `on_cancel` 404s on unknown session
(DOGFOOD-08), battery 44/44.

## Conclusion

- The scaffold → battery onboarding path is **compliant**: fresh scaffold in both
  languages → `h3-test` **44/44, exit 0**, zero manual edits.
- The 2026-08-14 report is left **unchanged** as the historical failure record;
  this file is the post-fix point-in-time record.
- DOGFOOD-10 (scaffold-compliance CI job in shim `.github/workflows/test.yml`)
  now guards this path on every shim push, so a 43/44 regression cannot ship
  undetected again.

**Verifier:** h3 umbrella foreman (tick #329), gitreins task GAP-059.
