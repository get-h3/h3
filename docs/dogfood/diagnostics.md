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

## 8. 2026-09-08 dogfood additions (E12-E14)

### E12. Why the same harness passes in Go and 500s in TypeScript
**What happened:** a from-scratch TS consumer (text-stats harness, no example
copied) returned `decision_id: "stats-<sid>-<ts>"` and got
`500 INVALID_DECISION: Invalid UUID` from `createH3Router`'s Zod validation.
The Go echo example ships `"echo-001"` and passes 46/46. **Why:** the TS SDK
routes every Decision through generated Zod schemas where `decision_id` is a
UUID string; the Go SDK's server-side validation is hand-rolled and lenient.
Both are "correct" per their own code, so nothing in CI catches the drift —
the protocol spec doesn't pin the decision_id format. **Right way:** pick one
contract (UUID everywhere, or free-form everywhere), write it into
`specs/02-Protocol-Specification.md`, and add a cross-SDK conformance test
(`integration/roundtrip` is the natural home). Until then, TS consumers must
`crypto.randomUUID()` — file DF-H3-6.

### E13. The battery is a contract tester, not a courtesy checker — its
### hidden trigger phrases are part of the protocol
**What happened:** a logically-correct TS harness (always `finished:true` on
complete answers, `end.reason:"completed"`) scored 37/46. Failures read
`Expected finished=false, got True`, `result_tool_success … status=500`.
**Why:** `test_battery.py` simulates how Hermes actually drives a harness:
it sends messages containing "do not finish" / "start a thought" /
trailing "..." / "incomplete" / "partial" and expects `finished:false`
(streaming continuation), then drives multi-turn result loops and every
`ResultPayload` type through `onResult`. A harness that is "obviously right"
per the integration doc fails 15 tests, because the doc never states the
convention — the echo examples embody it. **Right way:** read
`examples/echo` in your SDK *as part of the spec* before writing onProcess;
or grep `test_battery.py` for the trigger literals. Long-term fix is
documentation + an explicit conformance mode (DF-H3-7). Note this bit a
maintainer-grade consumer, not a typo — it is the sharpest L3 (works-for-a-
user) gap found this cycle.

### E14. Fresh-machine install fails at venv on stock Debian (no sudo)
**What happened:** the bunker fresh-user agent (Debian 13, Python 3.13.5,
rootless) died on the README's literal first command: `python3 -m venv`
→ `ensurepip is not available … apt install python3.13-venv` (needs sudo).
**Why:** Debian splits venv/ensurepip out of python3-minimal; docker and
cloud images routinely ship without it. **Right way (survived, 13s total):**
`python3 -m venv --without-pip .venv && curl -sS
https://bootstrap.pypa.io/get-pip.py -o /tmp/g.py && .venv/bin/python /tmp/g.py`
then `pip install -e .`. Quickstart should carry this fallback (DF-H3-8).

### Trust anchors update (2026-09-08)

- Battery: **46/46** is the live count (46 since GAP-045/DOGFOOD-002 wave;
  any "44" in docs is stale — DF-H3-2 still open).
- Verified compliant on 2026-09-08: Go echo, Go scaffold, PyPI
  h3-harness-sdk 0.1.5 echo, TS SDK custom consumer, py scaffold in bunker
  — five distinct endpoints, all exit 0, 0.27-0.63s per run.
- Install: works from source on clean machines AFTER the venv bootstrap
  workaround (E14); bunker-las-03 (default dogfood host) offline ~1d —
  install leg ran on bunker-las-04.

### E15. The census is not the writer: tick-chain drift came back exactly as designed (2026-09-21)
**What happened:** dogfood tick h3-dogfood-2026-09-21 ran `make verify` against the
h3 repo itself for the first time (prior runs tested the shim/SDK/battery products,
never the hub's own guards) and verify-tick-chain went RED: `1 hole(s): 464`.
The DuckBrain tree holds the drifted shape `/project/h3/tick/464` while the bare
canonical `/tick/464` is absent — 458-463 and 465 are all bare. This is the same
drift shape as ticks 452/453, which tick #459 backfilled but whose write path was
never fixed.
**Why it matters:** the checker comment says a future drift "goes red at the gate
that measures it instead of being narrated as contiguous in the next audit" — that
is exactly what happened. The gate works. What is broken is the WRITER: the
foreman's DuckBrain record key intermittently lands under `/project/h3/tick/<N>`
instead of bare `/tick/<N>`. Backfilling 464 alone would repeat the 452/453
pattern — symptom patched, cause alive.
**Right way:** fix the write path (the record key must be bare `/tick/<N>` for the
h3 umbrella ns), then backfill the drifted key, and add a regression check on the
writer (e.g. assert the key the writer just wrote parses as canonical) — not only
on the census, which can only catch the drift one tick late by design. Filed as
DF-H3-23 (P1). Note: the HEAD commit message at the time (f22cf9f, tick #465)
claimed a green verify; it was red at merge time — commit messages that narrate
gate status are claims, the gate re-run at HEAD is the fact.

---

## E16 (2026-09-23) — The detector/writer split is the real architecture: guards age, writers regress

**What happened:** DF-H3-24 shipped the board-header consistency guard (H3-GAP-099) and closed. Two ticks later (#480, #481), a fresh public clone fails `make verify` again: header last_commit=125f473 (4 commits behind), ticks_total=479 vs event log 481 — the post-push header sync didn't run in either closeout. The guard did exactly its job (clean FAIL naming both A and B conditions); the WRITER is what regressed, again (459/463/464, now 480/481).

**Why it matters:** a repo whose own README-documented smoke (`git checkout && make verify`) is red at public HEAD fails the FIRST thing every fresh user runs — the product works, the gate about the gate doesn't. A green detector row ("guard complete") is not a green system when the class it detects keeps recurring; the recurrence rate IS the metric for the writer fix, and it has now fired five times.

**Right way:** treat repeated guard catches of the same class as evidence the WRITER needs an unconditional step (header write-back inside the board-writing closeout, not a best-effort post-push hook), and re-open the writer row each time the guard fires instead of treating the catch itself as closure. Filed DF-H3-25 (P1). Companion lesson from the same run: a compliance battery can green-light the WRONG server on a shared host (h3-test 46/46 vs a 2.6-day-old co-tenant harness while the target never bound — DF-H3-26); a gate must print the identity/uptime of what it tested, or its PASS is only about the port, not the process.

### E17 (2026-09-24) — The validator IS documentation: an error message that proves the contract, and the surgical-commit rule for shared boards

**What happened:** two things, one run. (1) Probing the v0.1.8 Go harness with a
hand-rolled curl payload (session_id + message + context, no identity), the server
answered `INVALID_REQUEST: identity.platform is required` instead of echoing. For a
moment this looked like SDK-vs-spec drift — `grep -r platform` finds NOTHING in
shim/client.py or the YAML surface, so "the published tag demands a field the spec
never mentions" seemed live. It was not: protocol/schemas/v1/common.json:55 requires
platform/chat_id/user_name/user_id on Identity, and sdk-go's `Validate()` tests assert
exactly that. My payload was wrong; the server was the spec. (2) Committing the two
dogfood rows, the board already contained an UNCOMMITTED row from a sibling lane
(releng's RELEASE-H3-006, appended after the foreman's last commit e08ed4d).

**Why it matters:** (1) A terse, field-naming validator error is better onboarding
than prose — it pointed at the one missing concept (Identity) and the fix took one
edit. When a consumer sees a "drift," the sequence that settles it in minutes is:
read the JSON Schema (not the YAML prose) → read the SDK's Validate tests → only then
believe drift. (2) A dogfood/audit lane that commits the whole board file can swallow
or mis-attribute a sibling's in-flight row. The safe shape: stage HEAD + ONLY your
rows (rebuild the file from `git show HEAD:path` + your appends, byte-exact), commit,
then restore the sibling's row byte-identically as the uncommitted state you found.

**Right way:** send the full envelope on first contact (the working curl pair is in
the skill + docs/dogfood/2026-09-08-integration.md); treat validator errors as the
cheapest spec reading available. For shared JSONL boards, commit surgically and prove
it (`git diff --numstat` == your row count) — never `git add` the whole board file
when any other lane can append between your read and your commit.

## E18 (2026-09-24) — A breaker wired only to the health loop cannot heal: "skipped" is not "half-open"

**What happened:** the ninth h3 dogfood run drove H3Loader's resilience path
(loader.py) for the first time — kill the harness, watch reroute, restart,
watch recovery. Reroute works (85-90s via the 30s health loop). Recovery does
not exist when the breaker opens: measured OPEN for 300s straight with the
documented knobs (window=2, threshold=0.5, cooldown=3s) and the harness
healthy again from +180s.

**Why it matters (the mechanism, not the incident):** the CircuitBreaker
class is textbook-correct in isolation. The defect is a **wiring shape**: the
health loop's first branch is `if state == OPEN: skip + continue`, and the
health loop is the ONLY component that feeds the breaker
(`record_outcome` ×3, `allow_request` ×0 in src/). Transitioning OPEN →
HALF_OPEN needs either an outcome (skipped) or someone *observing* the
cooldown expiry via `allow_request` (never called). "Skip while OPEN" and
"probe after cooldown" are mutually exclusive when the skipper is also the
only observer. Lesson: when you add a fast-path guard, audit who else feeds
the state machine — a state machine with one feeder and a guard on that
feeder deadlocks in the failure state. The correct shape is either the skip
branch doing the HALF_OPEN transition itself (loop still runs; check
`allow_request()` instead of `state == OPEN`), or request-path calls
flowing through the breaker so real traffic can close it.

**Second lesson from the same run:** `resolve()` reads static config while
reroute rewrites `_session_routes` — two sources of truth for one question.
Any restart re-resolves to the dead name. Durability of routing decisions
must live in the same structure that answers the query, or be re-derived on
load. This is the same writer/detector split as E15-E16 in a new costume:
the guard (reroute) writes state the reader (resolve) never looks at.

**Right way:** to use H3Loader today, treat the breaker as a
latch-disabled-until-restart device: set `circuit_breaker_window` huge or
write your own probe loop; keep sessions on the default harness during
deploys. To fix it (DF-H3-34/33), make the health loop call
`allow_request()` on every pass and probe when permitted, and make reroute
state the only answer `resolve()` gives.

## E19 (2026-09-25) — The control plane's weak point is a data file nobody owns: versions.yaml

**What happened:** run 10 exercised the CLI lifecycle (install/list/use/
route/verify/pre-update-check/uninstall) for the first time. The lifecycle
itself is clean — fail-closed everywhere, install probes before persisting,
uninstall demotes default_harness, config survives a dead endpoint. The one
surface that lies is `pre-update-check`: it BLOCKed 0.21.1 (newer than
matrix), 0.20.0 and 0.19.0 (shim 0.1.0 vs required 1.1.0/2.0.0) — i.e. the
check cannot return "safe" on any Hermes a current user could run. Only
0.17.0 (WARN-only) passes, and that Hermes predates every fleet machine.

**Why:** `data/versions.yaml` is generated from the S03 spec and its own
header says "version bumps and this matrix move together" — but nothing owns
that cadence. The shim version stayed 0.1.0 across five Hermes releases;
the matrix (and the `min_h3` values of its "planned" rows) drifted into a
state where the tool is always-BLOCK. The failure mode is not a crash, it
is a safety check that cries wolf: a user trained by permanent BLOCKs
skips the check the day it matters.

**Second observation, same class:** the `config_schema v0 → v1` WARN
fires on every config forever — `upgrade_check.py` compares
`cfg.get('_schema', 0)` to `CURRENT_CONFIG_SCHEMA=1`, but nothing in the
codebase ever writes a `_schema` key or migrates anything. A permanent
warning about a migration that does not exist.

**Right way:** a compatibility matrix is a *product surface* with an owner
and a freshness signal (print its last-updated date in BLOCK output). Any
WARN a user cannot clear must be a BUG — either implement the migration or
don't warn. The harness-facing check 4 (`harness:NAME unreachable` WARN)
shows what correct looks like: it is conditional, accurate, and clears.

**Cross-reference:** rows DF-H3-36 (P1), DF-H3-37/38/39 (P2, one class:
string literals duplicating runtime facts — enum repr, breaker narrative,
schema claim — each drifts from its source independently).
