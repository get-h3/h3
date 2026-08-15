# H3 Dogfood Integration Report — 2026-08-14 (2nd field test)

Real-use run by the coding-hermes dogfood cron. Everything below was done by
hand in a scratch environment (`/tmp/dogfood-h3-20260814`) as a fresh external
developer: `git clone` from GitHub, fresh venv, network-resolved dependencies,
documented commands only. No internal helpers, no local fleet checkout.

## 1. The promise (null hypothesis)

> "Swap your agent's brain." A developer can (a) follow the README Quick
> Start and verify an H3-compliant harness in minutes (`h3-test` → exit 0),
> and (b) scaffold a new harness in 30 seconds with
> `hermes-h3 scaffold --lang go` and get the same compliance. README: "44
> tests — exit code 0 means your harness is H3-compliant."

## 2. What I did (the actual use)

| Step | Command | Result |
|---|---|---|
| Clone shim (fresh) | `git clone https://github.com/get-h3/shim` | ✅ |
| Clone sdk-go (fresh) | `git clone https://github.com/get-h3/sdk-go` | ✅ |
| Install shim | `python3 -m venv .venv && pip install -e .` | ✅ `h3-test` + `hermes-h3` on PATH |
| Start Go echo example | `cd sdk-go/examples/echo && go run .` | ✅ health OK on :9191 |
| **Run battery** | `h3-test --endpoint http://localhost:9191` | ✅ **44/44, exit 0, 0.22s** |
| Scaffold Go | `hermes-h3 scaffold --lang go` | ✅ generates h3-harness-go |
| Build+run scaffold | `go mod tidy && go run .` | ✅ builds, runs |
| **Battery vs scaffold** | `h3-test --endpoint http://localhost:9191` | ❌ **43/44, exit 1** |
| Scaffold Python | `hermes-h3 scaffold --lang py` | ✅ generates h3-harness-py |
| Install+run scaffold | `pip install -r requirements.txt && python main.py` | ✅ runs |
| **Battery vs py scaffold** | `h3-test --endpoint http://localhost:9191` | ❌ **43/44, exit 1** |
| Scaffold TS | `hermes-h3 scaffold --lang ts` | ✅ generates h3-harness-ts |
| Install TS scaffold | `npm install` | ❌ **E404 `@get-h3/h3-harness-sdk@^0.1.0`** |
| Python SDK echo example | `python src/h3_harness/examples/echo.py` + battery | ✅ **44/44** |
| TS SDK echo example | `npx tsx src/examples/echo.ts` + battery | ✅ **44/44** |
| CLI management | `hermes-h3 install/list/verify` | ✅ works (verify: `-h` flag, not positional) |

Time-to-first-success (README Quick Start): **~3 minutes** from empty /tmp.
Battery runtime: 0.22–0.54s. Latency p50 ~1ms.

## 3. The one failing test (all languages, same root class)

```
FAIL: Error & Edge Cases | cancel_unknown_session | Expected 404, got 200
```

The protocol (specs/02 §6 + OpenAPI) requires `POST /v1/cancel` to return
404 `SESSION_NOT_FOUND` for an unknown session. The scaffolded harnesses
return 200 `{cancelled: true}` for everything.

### Why (root cause per language)

- **Go:** `templates/go/go.mod` pins `github.com/get-h3/sdk-go v0.1.0`. The
  404 fix (`addb017`, "fix: cancel/result 404 SESSION_NOT_FOUND on unknown
  sessions", 2026-08-08) is **only in v0.1.1** (verified with
  `git merge-base --is-ancestor`). The SDK's own `examples/echo` passes 44/44
  because it compiles against sdk-go `main`; a fresh scaffold resolves v0.1.0
  from the module proxy and gets the old behavior. `go.sum` confirms v0.1.0.
- **Python:** `templates/py/main.py` `on_cancel` (L265) unconditionally
  returns `CancelResponse(cancelled=True, ...)`; the `/v1/cancel` route has no
  session lookup. The sdk-python `BaseHarness` (used by the 44/44 example)
  does track sessions and 404s — the template just doesn't use that pattern.
- **TypeScript:** worse — `templates/ts/package.json` depends on
  `@get-h3/h3-harness-sdk@^0.1.0`, which has **never been published to npm**
  (live E404, 2026-08-14). The sdk-typescript AGENTS.md documents the working
  fallback `npm install github:get-h3/sdk-typescript`; the scaffold template
  was never updated to match. (GAP-005/007/008 fixed this dead ref in the
  *docs*; the template itself still ships it.)

### Why it survived 8 days (process gap)

sdk-go v0.1.1 was tagged 2026-08-08. Every E2E tick since then
(#280/#285/#290/#295/#300/#305) ran the battery against `sdk-go/examples/echo`
— which compiles against sdk-go `main` and passes — never against a fresh
scaffold. The one time the scaffold path was "verified" (tick #254,
2026-08-04) the check stopped at `go mod tidy` + `go build` and never ran
`h3-test`. Classic L2 (it runs) vs L3 (it works for a user) gap: "builds"
was mistaken for "compliant".

## 4. What held up vs. what fell apart

**Held up:**
- README Quick Start (fixed since the 2026-08-02 run): source install with
  venv step, sdk-go tags exist (v0.1.0/v0.1.1 verified via ls-remote), echo
  example runs, battery 44/44, exit 0. The 2026-08-02 blockers (PyPI missing,
  untagged sdk-go) are genuinely resolved — GAP-001/004/047 fixes are real.
- `h3-test` CLI: clean `--help` with documented exit codes 0/1/2, full JSON
  report with per-test `passed/detail/duration_ms/category`, `--categories`
  filter, 0.2-0.5s runtime, clear failure messages ("Expected 404, got 200").
- SDK examples all 44/44 (Go, Python, TypeScript) — the compliance table's
  claims hold for the examples.
- `hermes-h3` management flow: `install` (positional NAME + --endpoint),
  `list` (star marks default), `verify -h NAME` (health/caps/version),
  `test`, `scaffold --lang go|py|ts`, `--config` override.
- Error-envelope discipline: 400/404 shapes with `SESSION_NOT_FOUND` codes
  behave per specs/02 §9 in the SDK examples.

**Fell apart:**
- The "scaffold a new harness in 30 seconds" headline promise — in all 3
  languages (43/44, 43/44, uninstallable). This is the README's second
  quick-start block, so it is the second thing a new user tries.
- `skills/h3-usage/SKILL.md` L61-67 claims the Go scaffold is "44/44" — stale
  since 2026-08-08 (same docs-vs-reality drift class as H3-GAP-00x, but in
  the skill that teaches agents how to use the system).
- `hermes-h3 verify` positional-name trap (minor).

## 5. The integration recipe that WORKS (verified 2026-08-14)

```bash
# 1. Shim (source install — hermes-h3-shim still not on PyPI)
git clone https://github.com/get-h3/shim && cd shim
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

# 2. A compliant harness — use an SDK example (NOT the scaffold, until
#    DOGFOOD-07/08/09 land)
git clone https://github.com/get-h3/sdk-go
cd sdk-go/examples/echo && go run .        # :9191

# 3. Verify
h3-test --endpoint http://localhost:9191    # 44/44, exit 0
```

Python equivalent: `cd sdk-python && . .venv/bin/activate && python
src/h3_harness/examples/echo.py` (44/44). TS equivalent: `cd sdk-typescript
&& npx tsx src/examples/echo.ts` (44/44).

## 6. What I'd tell the maintainer to fix FIRST (1 hour)

1. Bump `templates/go/go.mod` sdk-go v0.1.0 → v0.1.1 (one line — fixes
   DOGFOOD-07).
2. Add a session check + 404 to `templates/py/main.py` cancel route (fixes
   DOGFOOD-08).
3. Swap `templates/ts/package.json` dep to `github:get-h3/sdk-typescript`
   (fixes DOGFOOD-09).
4. Add one CI/release gate: scaffold each language in a temp dir, run
   `h3-test`, require exit 0 (fixes DOGFOOD-10 — the reason 1-3 shipped and
   survived).
5. Update skills/h3-usage/SKILL.md's stale "44/44 scaffold" claim.

All five are on the board as DOGFOOD-07..11 (P0/P0/P0/P1/P2).

## 7. Environment

Go 1.26.5, Python 3.13.13, Node 22.22.3, network-resolved deps, dates
2026-08-14. Scratch dir: /tmp/dogfood-h3-20260814 (throwaway). No credentials,
no real user data, no destructive actions; all harnesses killed after use.
