# H3 Umbrella Dogfood — 2026-09-24 (harness-author through sdk-go + sdk-typescript, published routes + fresh-machine proof)

**Runner:** dogfood tick h3-dogfood-2026-09-24-00-17-44 (coding-hermes-dogfood skill v1.2.0, Step 2b per coding-hermes-perf)
**New surface (prior runs tested: CLI/board, make verify, python-SDK consumer + PyPI, live HTTP loop):** the TWO SDK surfaces no run ever consumed — **sdk-go** and **sdk-typescript** — from the documented entry paths only, as a harness author with no prior h3 knowledge, gated by the 46-test battery. Plus the first fresh-machine **published-route** proof for both (public module proxy / npm GitHub route) on an ephemeral bunker.

## Promise vs Reality

**Promise:** "Go SDK / TypeScript SDK for building H3-compliant agent harnesses" — install per README/AGENTS.md, implement the Harness interface, serve, pass `h3-test`.

**Reality: HOLDS — SHIPPABLE, 5th consecutive dogfood verdict (08-23, 09-01, 09-04, 09-19, 09-23).** Both SDKs delivered a battery-passing harness from docs alone. Go: quickstart compiled first try, 46/46 first try. TypeScript: 46/46 after two documented-but-buried steps (serve + partial turns), both present in the README, neither in AGENTS.md. No protocol drift, no silent failures, no false passes this run.

## What was run

| # | Leg | Result |
|---|-----|--------|
| 1 | Go consumer: scratch module, README quickstart main.go verbatim, local fs-replace | ✅ `go build` 0.33s, first try |
| 2 | Go harness on :9291 + h3-test | ✅ 46/46, exit 0, 0.21s (p50 0.78ms / p95 33.1ms) |
| 3 | TS consumer: `npm install github:get-h3/sdk-typescript` (5.2s, prepare builds dist) | ✅ |
| 4 | TS harness per README (serve + partial turns) on :9292 + h3-test | ✅ 46/46, exit 0, 0.24s (p50 1.21ms / p95 30.2ms) |
| 5 | Boot-to-ready (cold): Go 13ms; TS (tsx-less, plain node) 135ms | ✅ nothing a user would feel — no PERF row filed |
| 6 | Bunker fresh machine (las-bunker-03 agent 21419eff, bare Debian 13, no sudo): clone sdk-go (2.7s, HEAD 071a08f = local) | ✅ |
| 7 | Bunker TS: npm GitHub route 16s + consumer serve + health 200 | ✅ (battery not installable there: h3-shim is source-only, venv needs sudo — DF-H3-8 class, known) |
| 8 | Bunker Go: go1.26.6 toolchain extracted (no sudo), `go get github.com/get-h3/sdk-go` via public proxy → **v0.1.8 in 11s**, build 19s, serve + spec-shaped /v1/process smoke → correct echo decision | ✅ |
| 9 | Agent destroyed, absence verified (0 passwd entries, 0 containers) | ✅ |

## What a harness author experiences (the integration report)

**Go (the good one).** AGENTS.md quickstart is the README quickstart, and both compile and comply first try: implement 5 methods, `harness.ListenAddr()` + `harness.NewHTTPServer` + `harness.Serve`, `PORT` env override honored. One near-miss worth teaching: my hand-rolled curl payload omitted `identity.platform` and the server rejected it with `INVALID_REQUEST: identity.platform is required` — that is the SPEC being enforced (protocol/schemas/v1/common.json:55 requires platform/chat_id/user_name/user_id), not a bug. The error message walked me straight to the fix. v0.1.8 types match the spec exactly (checked `Platform` json tag + `Validate()` tests).

**TypeScript (works, but you must read past AGENTS.md).** Three gaps between AGENTS.md-quickstart and a serving, compliant harness — all closed by the README:
1. The quickstart `export default app` serves NOTHING on `node file.ts`; the serve step (`@hono/node-server`) is README §"Serving your harness" (~:142).
2. The always-`finished:true` quickstart fails battery test 2.4 (`process_text_finished_false`); the partial-turn convention is README §"Partial turns", and `src/examples/echo.ts` is the battery-passing reference.
3. `tsc` consumers need a tsconfig with `"types": ["node"]` — bare `tsc file.ts` fails TS2591 even with @types/node installed (README documents the @types/node requirement; the tsconfig detail cost one iteration).
Time-to-first-success ≈ 15 min (would be ~5 if AGENTS.md matched the README). Filed as DF-H3-30.

**Fresh-machine reality (bunker, bare Debian 13).** Toolchains: node/npm/python3 present; **go missing, no sudo** — the README's "install Go first" is the real first step; the actual artifact comes from dl.google.com (go1.26.6) since go.dev/dl is a docs page, not a version API. Even so, the published-route journey worked end to end: `go get` through the public module proxy resolved v0.1.8 in 11s. npm GitHub route: 16s on the agent. Filed docs-precision items as DF-H3-31.

## Numbers (Step 2b)

- Battery vs Go harness: 0.21s, p50 0.78ms, p95 33.11ms (46/46, exit 0)
- Battery vs TS harness: 0.24s, p50 1.21ms, p95 30.23ms (46/46, exit 0)
- Boot-to-ready cold: Go 13ms, TS 135ms
- `go build` of quickstart: 0.33s (local) / 19s (agent, cold module cache)
- `npm install github:get-h3/sdk-typescript`: 5.2s (local) / 16s (agent)
- `go get github.com/get-h3/sdk-go` via proxy: 11s (agent)
- Nothing here makes a user wait — **no PERF row filed, deliberately** (a win nobody can feel is not a finding).

## Board rows

- **DF-H3-30 (P2):** sdk-typescript AGENTS.md quickstart serves nothing and hides the battery-deciding partial-turn convention; README has both — make AGENTS.md match.
- **DF-H3-31 (P3):** sdk-go README 1.22+ floor vs go.mod/generics reality + fresh-machine precheck/toolchain-version hint; published route verified working (v0.1.8, spec-conformant).

Committed a38d988 (rows only; releng satellite's uncommitted RELEASE-H3-006 row deliberately left exactly as found, byte-exact, uncommitted).

## Verdict

✅ **SHIPPABLE** — both SDK surfaces deliver on their promise from docs alone; the only defects found are docs-precision (AGENTS.md drift on the TS side, version-floor/precheck precision on the Go side).
