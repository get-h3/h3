# H3 Diagnostic Trail — how the system is built, errors hit, the right way

Not raw logs — an explanation of how the get-h3 fleet is put together, what
broke during a real use run (2026-08-02), and the correct patterns. Written
from the perspective of someone who used the system, not built it.

## 1. How the thing is built

```
protocol/  (OpenAPI 3.1 h3-protocol.yaml — single source of truth)
    │   generates Pydantic/Zod/Go types into the SDKs
    ├──► shim/          Python: client, loader, shim_loop, test_battery (44 tests)
    │        │          exposes: h3-test, hermes-h3 (CLI)
    │        └── templates/ (go/py/ts scaffold generators)
    ├──► sdk-go/        Go harness SDK (protocol/ + harness/ packages)
    ├──► sdk-python/    Python SDK (Pydantic models + FastAPI router)
    └──► sdk-typescript/ TS SDK (Zod models + Hono router)
```

**The loop** (from specs/02 §10): Hermes → `POST /v1/process` (message +
context) → harness returns a Decision (`tool_call` / `llm_call` / `text` /
`wait` / `delegate` / `end`) → Hermes executes → `POST /v1/result` →
harness returns the next Decision → ... → `end`.

**The gate:** `h3-test --endpoint URL` runs 44 tests in 6 categories
(health, process flows, decision types, result handling, errors, stress).
Exit 0 = compliant. The battery is transport-agnostic (REST today; gRPC is
PERF-04).

**Fleet topology:** 6 repos, each with its own coding-hermes foreman cron;
the umbrella `h3` repo holds the specs, the cross-repo board
(`.coding-hermes/board/`), and cross-language roundtrip fixtures
(`integration/roundtrip/`). GitReins quality gate on every repo.

## 2. How the harness protocol works (the parts that matter)

- **Health:** `GET /v1/health` → `{status, version, transport,
  protocol_version, uptime_seconds, active_sessions, capabilities[]}`.
  Capabilities is a list of supported decision types; an echo harness that
  only emits `text` may advertise just `["text"]` (the Go scaffold does) —
  the battery treats decision-type tests as "skipped/optional" for such
  harnesses.
- **Process:** request carries `session_id`, `message`, `identity`, and
  `context` (history, tools, models, memory, skills, config, session_state).
  Response = exactly one Decision envelope.
- **Decision envelope:** `{decision: "<type>", decision_id, "<type>": {...}}`
  plus two OPTIONAL extras that the battery checks:
  - `history`: echo of `context.history` (list of `{role, content}`) —
    required by test `process_preserves_history`.
  - Streaming marker: if the user content contains the substring
    `"do not finish"`, a `text` decision must be `finished: false`; otherwise
    `finished: true`. This is the battery's convention for testing the
    streaming path (test `process_text_finished_false` sends "do not
    finish"; `process_text_finished_true` sends a "final answer" prompt and
    expects `finished: true`).
- **Result:** `{session_id, decision_id, result: {type, data, ...}}` where
  result.type ∈ `tool_result | llm_response | text_sent | delegate_result |
  wait_timeout | error`.
- **Errors:** `{"error": {code, message, details}}` with codes
  `INVALID_REQUEST` (400), `INVALID_DECISION` (400), `SESSION_NOT_FOUND`
  (404), etc. (specs/02 §9). Malformed JSON → 400; the battery requires the
  exact error-envelope shape.

## 3. Errors hit during the run, and the right way

### E1. Installing the shim package → "No matching distribution found"
**Why:** the package was never published to PyPI (P3-10 blocked on
credentials). Same for the Python SDK's PyPI name (`h3-harness-sdk`).
**Right way:** install from source — shim: `git clone
https://github.com/get-h3/shim && cd shim && pip install -e .`; SDKs:
`pip install git+https://github.com/get-h3/sdk-python` /
`npm install github:get-h3/sdk-typescript`. Or wait for the publish (P3-10).


### E2. `go mod tidy` → `unknown revision v0.0.0`
**Why:** the scaffold template pins `github.com/get-h3/sdk-go v0.0.0`, a
version that cannot exist (no tags), and the `replace` directive that would
fix it ships commented out.
**Right way:** uncomment `replace github.com/get-h3/sdk-go => <local path>`
(relative to the scaffold, `../../sdk-go` works when the fleet is checked
out as siblings), then `go mod tidy && go build`. Long-term fix: tag a
release.

### E3. Battery tests fail: `process_text_finished_true`, `process_preserves_history`
**Why:** two conventions live only in SDK example code, not the spec (see
§2). A spec-only implementer can't know them.
**Right way:** include `history` in the decision envelope and set
`finished = "do not finish" not in content` for text decisions.

### E4. `h3-test` against :8000 → 9/43, health returns `{"detail":"Not Found"}`
**Why:** the port was owned by an unrelated FastAPI service. The Python
echo example hardcodes `port=8000`, fails to bind (exit 3), and the battery
silently tests whatever IS on the port. Same trap as the fleet's own tick
#35.
**Right way:** before testing, confirm the port with
`curl <endpoint>/v1/health` and check `ss -tlnp`; use a free port for
examples (`port=8001`).

### E5. `hermes-h3 scaffold` vs the plugin's space-form subcommand
**Why:** the README documents the in-Hermes plugin form (the `hermes h3`
command group); standalone the binary is `hermes-h3`. The space form
exists only once WIRING-01/02 land (plugin wired into a live Hermes).
**Right way:** use `hermes-h3` for CLI work today; the commands are
identical.

### E6. (Ops, for completeness) Tick rows with `status='running'` + `session_id NULL`
Observed on several projects during this run; they were **in-flight gateway
spawns**, not zombies — the daemon completed them within minutes
(`session_id='gateway'`). True zombies (per the scheduler-registration-health
playbook) are rows stuck past `--tick-timeout` (7200s here). Don't clear a
fresh `running` row; check its age first.

## 4. Verified-good behaviors (trust anchors)

- Battery exit codes: 0 pass / 1 fail; `--json` report is schema-valid and
  includes per-test `passed/detail/duration_ms/category`.
- Three independent implementations (Go scaffold, Python SDK, stdlib
  spec-only) all reach 44/44 against the same battery — the gate is
  consistent and language-agnostic.
- Spec-only implementability: 41/43 from `specs/02` alone (the 2 missing
  conventions are documented above).
- Management CLI (install/list/verify/test) behaves consistently, respects
  `--config`, and `verify` correctly reports harness health/caps/version.
- The board's claim "fleet green" matches reality for the tested paths.

## 5. The right way to build a harness (short version)

1. `GET /v1/health` → 200 with `status: ok`, version, transport, capabilities.
2. `POST /v1/process` → Decision; echo `history` from context; respect the
   `"do not finish"` streaming marker for `finished`.
3. `POST /v1/result` → next Decision; `end` when done (reason
   `task_complete`).
4. `POST /v1/cancel` → `{cancelled: true}`; `GET|DELETE /v1/sessions/:id`.
5. Errors as `{"error": {code, message, details}}` with the §9 codes.
6. Run `h3-test --endpoint http://localhost:9191` until 44/44.

## 6. 2026-08-14 run — what changed, new errors, the right way

Second dogfood run (fresh clones, fresh venv, network-resolved deps). The
2026-08-02 blockers are GONE: shim installs from source, sdk-go has release
tags (v0.1.0/v0.1.1), README Quick Start works end-to-end (44/44 in 0.22s).
New findings below.

### E7. Scaffolded Go harness → 43/44, `cancel_unknown_session` "Expected 404, got 200"
**Why:** `templates/go/go.mod` pins `sdk-go v0.1.0`. The 404-on-unknown-cancel
fix (`addb017`, GAP-DOG-002) landed 2026-08-08 and is only in **v0.1.1**.
The SDK's own `examples/echo` compiles against sdk-go `main` (fixed), so the
fleet's E2E ticks kept passing 44/44 while every fresh scaffold resolved the
broken v0.1.0 from the module proxy. **Right way:** template must require
v0.1.1+ (one-line bump, DOGFOOD-07); more broadly, verify scaffold output per
release, not just SDK examples (DOGFOOD-10).

### E8. Scaffolded Python harness → 43/44, same test
**Why:** `templates/py/main.py` `on_cancel` (L265) always returns
`CancelResponse(cancelled=True)` — no session lookup, so `/v1/cancel` never
404s. The sdk-python `BaseHarness` (44/44 example) tracks sessions and 404s;
the template doesn't use that pattern. **Right way:** session check + 404
`SESSION_NOT_FOUND` in the template's cancel route (DOGFOOD-08).

### E9. Scaffolded TS harness → `npm install` E404
**Why:** `templates/ts/package.json` depends on `@get-h3/h3-harness-sdk@^0.1.0`
— never published to npm (verified live). The sdk-typescript AGENTS.md
documents the working fallback `github:get-h3/sdk-typescript`; the template
ships the dead ref (same class as GAP-005/007/008, which fixed the docs but
not the template). **Right way:** template dep → `github:get-h3/sdk-typescript`
until published (DOGFOOD-09).

### E10. Why the 43/44 regression survived 8 days (process lesson)
sdk-go v0.1.1 tagged 2026-08-08; E2E ticks #280-#305 all ran the battery
against `examples/echo` (compiles against main) — never a fresh scaffold. The
single "scaffold verified" tick (#254) stopped at `go build`. **Right way:**
the compliance gate must run `h3-test` against a *fresh scaffold*, per
release, in CI (DOGFOOD-10). This is the premature-completion pattern again:
L2 (it runs) was mistaken for L3 (it works for a user).

### E11. (Minor) `hermes-h3 verify` positional-name trap
**Why:** `verify` takes `-h/--harness NAME` while `install`/`list`/`uninstall`
take positional NAME — `hermes-h3 verify ts-echo` → "Got unexpected extra
argument". **Right way:** accept an optional positional (DOGFOOD-11).

## 7. Updated trust anchors (2026-08-14)

- README Quick Start: ✅ works end-to-end from fresh clones (~3 min to 44/44).
- SDK echo examples: ✅ 44/44 in Go, Python, TypeScript (all verified live).
- Scaffold path: ❌ 43/44 / 43/44 / uninstallable (DOGFOOD-07/08/09) — the
  README's "30 seconds" claim does NOT hold as of 2026-08-14.
- Battery speed/exit-code discipline: ✅ unchanged (0.2-0.5s, exit 0/1/2).
- h3-harness-sdk 0.1.2 IS on PyPI (2026-08-08) — `pip install h3-harness-sdk`
  works; `hermes-h3-shim` still not published (P3-10).
