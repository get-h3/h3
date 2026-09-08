# H3 Umbrella Dogfood — 2026-09-08 (real-use run + fresh-install leg)

**Runner:** h3-umbrella-sync dogfood cron (coding-hermes-dogfood skill v1.1.0)
**Targets exercised:** shim CLI + battery (source install), sdk-go echo
example, Go scaffold, PyPI `h3-harness-sdk` 0.1.5, TypeScript SDK (GitHub
install) with a from-scratch custom consumer, and a fresh-rootless-Debian
install on an ephemeral bunker agent.

## Promise vs Reality

**Promise:** "Swap your agent's brain. Keep the Hermes platform" — a user
scaffolds a harness in 30 seconds, runs it, and `h3-test` (the compliance
battery) gates it: exit 0 = H3-compliant.

**Reality: HOLDS.** Every leg produced a compliant endpoint and the battery
is a genuinely useful, fast, honest gate (0.3s, 46/46, exit codes 0/1/2).
One docs-level caveat: the scaffold's "30 seconds" is really ~60-90s once
`go mod tidy` and the battery run are counted (still fast).

## What was run (all fresh clones in /tmp, zero prior state)

| # | Leg | Result |
|---|-----|--------|
| 1 | shim `pip install -e .` (uv venv, control host) | ✅ 1s; `h3-test` help/exit codes sane |
| 2 | sdk-go echo example → battery | ✅ 46/46, exit 0, 0.31s |
| 3 | `hermes-h3 scaffold --lang go` → `go mod tidy` → battery | ✅ 46/46, exit 0, 0.27s |
| 4 | Live round-trip (curl, real session) | ✅ process 200 → decision → result 200 |
| 5 | PyPI `pip install h3-harness-sdk` 0.1.5 → echo on :9192 | ✅ 46/46, exit 0 |
| 6 | TS SDK `npm install github:get-h3/sdk-typescript` (8s) + **custom consumer** | ✅ 46/46 after 2 real fixes |
| 7 | Bunker fresh install (rootless Debian, no sudo, no Go) | ✅ smoke 46/46 (see findings) |

Time-to-first-success (fresh clone → first 46/46): **~35s** on the control
host; ~2.5 min in the bunker including venv bootstrap workaround.

## The live round-trip (the thing the docs never show with curl)

Working request (discoverable only by iterating on error messages, or by
reading Go types — this cost 4 attempts):

```bash
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
curl -s -X POST http://localhost:9191/v1/process -H 'Content-Type: application/json' -d '{
  "session_id": "my-session-1",
  "message": {"role": "user", "content": "summarize the fleet report", "timestamp": "'"$TS"'"},
  "identity": {"user_id": "u1", "platform": "telegram", "chat_id": "-100123", "user_name": "me"},
  "context": {}
}'
# → {"decision":"text","decision_id":"echo-001","text":{"content":"Echo: ...","finished":true}}
curl -s -X POST http://localhost:9191/v1/result -H 'Content-Type: application/json' \
  -d '{"session_id":"my-session-1","decision_id":"echo-001","result":{"status":"ok"}}'
```

Friction trail (each = one 400 the docs don't prevent):
1. `{"text":"..."}` → `message.role must be user`
2. missing `message.timestamp` shape → role first, then platform required
3. `identity.platform` → `identity.chat_id is required`
4. `/v1/sessions/{id}/result` (the intuitive path) → **404**; the real route
   is flat `POST /v1/result` with `session_id` in the body.
5. Bare `text` field (as the OpenAPI securitySchemes example suggests) →
   `INVALID_REQUEST`. The envelope `{"message": {...}}` is required.

## The custom TS consumer (Step-2 "write a real consumer" leg)

Built `/tmp/dogfood-h3-umbrella/ts-consumer/stats-harness.mjs` — a
text-stats harness (word/char counts) that ships in no example:

```js
import { createH3Router } from "@get-h3/h3-harness-sdk";
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { randomUUID } from "node:crypto";

class StatsHarness {
  async onProcess(req) {
    const text = req.message?.content ?? "";
    const words = text.split(/\s+/).filter(Boolean).length;
    const lower = text.toLowerCase();
    const isPartial = lower.includes("do not finish") ||
      lower.includes("start a thought") || text.endsWith("...") ||
      lower.includes("incomplete") || lower.includes("partial");
    return {
      decision: "text",
      decision_id: randomUUID(),          // TS router REJECTS non-UUID ids
      text: { content: `stats: ${words} words`, finished: !isPartial },
    };
  }
  async onResult(_req) {
    return { decision: "end", decision_id: randomUUID(),
             end: { reason: "task_complete" } };  // enum value, not "completed"
  }
  health() { return { status: "ok", version: "0.1.0", transport: "rest",
    protocol_version: "1.0", capabilities: ["text"] }; }
}
const app = new Hono();
app.route("/", createH3Router(new StatsHarness()));
serve({ fetch: app.fetch, port: Number(process.env.PORT || 9292) }, () => {});
```

**Two real failures on the way to 46/46** (this is the integration report):

1. `decision_id: "stats-<sid>-<ts>"` → **500 `INVALID_DECISION: Invalid
   UUID`** from the TS router's Zod validation. The Go echo example ships
   `"echo-001"` and passes — the SDKs disagree on the id contract, and
   docs/integration.md:96 shows `"d_9e4f"` which the TS SDK would reject.
   → filed **DF-H3-6**.
2. `finished: true` always + `end.reason: "completed"` → **15/46 failed**
   (Process 7/8, Result 0/7, Error 11/13) with failures like
   `Expected finished=false, got True` and `result_tool_success … status=500`.
   Cause: the battery has an **undocumented trigger convention** — messages
   containing "do not finish"/"start a thought"/"..."/"incomplete"/"partial"
   must yield `finished:false` — and `end.reason` must be one of the schema
   enum values (`task_complete`, not "completed"). Both discoverable only by
   reading example/distro source. → filed **DF-H3-7**.

After those two fixes: 46/46, exit 0, 0.33s.

## Fresh-install leg (bunker; las-03 offline → sibling las-04)

- `bunker-las-03` (the skill's default host) was **offline** (ssh timeout to
  100.69.3.13; tailscale "last seen 1d ago"). Ran the leg on registered
  sibling **bunker-las-04** (bunkerd active, Docker 26.1.5) — infra gap
  filed as `SKIPPED-install-bunker` on the board.
- Agent `be304d58` (ttl 2h), rootless, **no sudo, no Go, Python 3.13.5**:
  cloned get-h3/shim + sdk-go from GitHub (public, no credentials needed).
- **Documented install path FAILED at the first step**: `python3 -m venv
  .venv` → "ensurepip is not available … apt install python3.13-venv" and
  the agent cannot sudo. Real-user workaround:
  `python3 -m venv --without-pip .venv && curl -sS
  https://bootstrap.pypa.io/get-pip.py | venv python` then
  `pip install -e .` → **13s total**. → filed **DF-H3-8**.
- Smoke: `hermes-h3 scaffold --lang py` (agent had no Go, so py path) →
  `pip install -r requirements.txt` → run → `h3-test` → **46/46, exit 0**
  on the fresh scaffold. Agent destroyed cleanly (`bunker destroy` OK).

## Verdict

**✅ SHIPPABLE** — third consecutive SHIPPABLE verdict (09-01, 09-04,
09-07, now 09-08). The protocol works, the battery is an excellent honest
gate, and four language/runtime paths + one custom consumer all reached
compliance. The remaining work is documentation honesty: the decision_id
contract, the battery's trigger conventions, and the venv bootstrap
fallback — all filed as DF-H3-6/7/8 (plus DF-H3-9: Go PORT env ignored).

## Friction count: 6

1. round-trip shape discovery (4× 400s + intuitive route 404) — DF-H3-5 (existing)
2. TS UUID decision_id rejection — DF-H3-6 (new)
3. battery hidden trigger conventions — DF-H3-7 (new)
4. bunker venv/ensurepip failure — DF-H3-8 (new)
5. Go echo/scaffold ignore PORT — DF-H3-9 (new)
6. las-03 offline forced sibling host — SKIPPED-install-bunker (new)
