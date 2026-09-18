# h3-pm Field Report — using the PM lane for real

**Date:** 2026-09-18 · **Target:** scheduler project `h3-pm` (namespace `pm`,
workdir `/home/kara/.hermes/stand-in/pm-lane/h3`, cooldown 86400s, enabled) ·
**Run:** `coding-hermes-dogfood` cron, verdict **🟡 PROMISING-BUT-ROUGH**.

This is the first dogfood pass on the **PM lane itself** (previous h3 runs
tested `h3`, `shim`, `sdk-go`, `sdk-python`, `sdk-typescript`). The PM lane is
not a library or a CLI — it is a scheduler lane that runs a *project-management
cycle* over the h3 umbrella. So "real use" here means consuming its product the
way the person it is written for does: **take the rows it filed, and check
whether they are true.**

---

## 1. The promise (null hypothesis)

The lane prompt (`~/.hermes/fleet.toml`, namespace `pm`) plus the skill
`coding-hermes-project-manager` promise:

> The `h3-pm` lane runs a daily PM cycle for the h3 project: read the tracking
> ledger first, spawn parallel read-only gap hunters, gate every candidate
> through G1–G7, write only gated rows with **observable pass criteria**, wake
> the foreman, then next cycle **verify the previous cycle's items with real
> commands** — a fix is only `verified` when the command proves it — escalate
> what is stale, log the cycle to DuckBrain, and regenerate the HTML report.

Its board is the h3 umbrella board at `get-h3/h3/.coding-hermes/board/tasks.jsonl`
(that is where every `H3-PM-*` row lives). Rows it filed on 2026-09-18:
`H3-PM-001` … `H3-PM-009`.

A secondary promise, stated in `get-h3/h3/AGENTS.md`, is that the ecosystem the
lane governs is installable by a fresh user:
`git clone https://github.com/get-h3/shim && pip install … && h3-test --endpoint …`.

## 2. What I actually did (real use, not test-running)

| Step | Action | Result |
|---|---|---|
| a | Read the lane prompt, the PM skill (335 lines), the ledger (1,921 items), the h3 board (188 rows), DuckBrain | Lane is live: last tick 2026-09-18T01:24:47-05:00, 9 `H3-PM-*` rows filed today |
| b | Re-ran the **pass criteria** of the newest rows (`005`–`009`) as commands, from the docs, not from the board | 4/5 hold exactly; 1 criterion is unmeasurable as written |
| c | Resolved `commit_hash` for every row that claims one, in the repo the row names | `59ecfeb 312469b a6b0684 d69409b` → h3 ✓; `507264b6` → protocol ✓ |
| d | Consumed the `H3-PM-003` product (`commit_repo` field) the way a verifier would: resolve all 7 rows carrying it in `get-h3/shim` | **7/7 resolve** — the field does its job |
| e | Ran the PM skill's own **G7 dedupe method** (normalised title+detail fingerprint) over the board the PM repaired | 6 ids still hold rows with *distinct* findings |
| f | Reconciled the **ledger** against every project board, resolving workdirs from `scheduler.db` | 43 of 104 open items are **already complete** on their boards |
| g | Walked the lane's **operational path**: stand-in workdir → target → board | Stand-in `.coding-hermes/` is empty; nothing documents target resolution |
| h | **Ephemeral install leg** on `bunker-las-03` (agent `437f91a0`, destroyed clean) — the documented `shim` quickstart on a bare Debian user | clone → venv → install → scaffold → battery **46/46, exit 0, 24s** |

### 2a. Criterion re-runs, row by row (the L3 check)

| Row | Claimed PASS criterion | Live measurement | Verdict |
|---|---|---|---|
| `H3-PM-005` | `migration.html` sample output has no `11/11`, no `Score: 44/44`, no `43 protocol behaviors` | 0 hits; block categories `7/8/6/7/13/5` sum to **46** = shipped `EXPECTED_TEST_COUNT` | ✅ holds |
| `H3-PM-006` | `grep -rn 'EndResult' /home/kara/get-h3/h3` = **0 hits** | **11 hits** (board row, `events.jsonl` ×2, `.gitreins/history/` ×8); `DEPLOY.md` itself is clean and its Go block defines all five `Harness` methods with `DecisionID` | ⚠️ fix real, **criterion impossible** |
| `H3-PM-007` | every spec-printed `get-h3.github.io` URL returns < 400 **or** carries a `planned` label in the same paragraph | `/h3/`, `/h3/protocol.html`, `/h3/badge/compliant.svg` = 200; `/h3/api/verify`, `/h3/api/compat-badge/h3`, `/h3/badges/v1/*.svg`, `/h3/verify/` = **404 but each is labelled `planned — not implemented` with the live 404 stated**; `pages.yml` `specs/**` trigger removed | ✅ holds |
| `H3-PM-008` | every artifact named in `specs/24 §6.1/§7` either resolves on disk or is marked planned | §4 table lists 7 artifacts as `❌ Not implemented` with the reason each; §6.1/§7 marked planned design intent | ✅ holds |
| `H3-PM-009` | a jq gate copied verbatim from `specs/09` runs against real `h3-test --json` output and fails on a failing battery | `specs/09` now names the 8 emitted keys and states the planned keys are never gate targets | ✅ holds |

### 2b. Install leg (ephemeral bunker, fresh user)

```
agent 437f91a0 @ 100.69.3.13 (bunker-las-03), TTL 2h, destroyed clean afterwards
whoami=bunker-437f91a0 · python3 3.13.5 · non-root (sudo needs a password)
git clone https://github.com/get-h3/shim   →  OK
python3 -m venv .venv && pip install .     →  OK  (h3_shim imports; h3-test + hermes-h3 on PATH)
hermes-h3 scaffold --lang py && pip install -e . && python main.py   →  harness on :9191
h3-test --endpoint http://localhost:9191
  Health & Protocol 7/7 · Process Basic Flows 8/8 · Decision Types 6/6
  Result Handling 7/7 · Error & Edge Cases 13/13 · Stress & Performance 5/5
  TOTAL 46/46 PASSED · 0.61s · EXIT 0
INSTALL_SECONDS=24
```

Nothing had to be guessed: the README's PEP-668 venv warning was accurate and
sufficient on this image (`python3-venv` was already installed). Prior runs hit
`ensurepip` missing — that is an image difference, not a docs regression.

## 3. Verdict — 🟡 PROMISING-BUT-ROUGH

**Does it work?** Yes. The lane really runs, and its rows are *real* findings
with real fixes: 4 of 5 newest criteria reproduce exactly as written, and the
one that fails does so because the *criterion* is broken, not the fix. The
`commit_repo` product (`H3-PM-003`) resolves 7/7 — that is a genuine workflow
improvement a verifier feels immediately.

**Is it useful?** Yes, and measurably so. `H3-PM-005..009` are the class of
defect that only an outside reader finds: a **fabricated sample output block**
in `docs/migration.html`, a **Go snippet in `DEPLOY.md` that cannot compile**,
**spec URLs that 404**, a **compat-CI surface documented as implemented but
absent**, and a **jq gate that reads `null`**. Every one of those is a user
hitting a wall while the repo's own tests stay green.

**Is it usable?** The *cycle* is well specified; the *lane* is not. Two traps
cost real time (findings 3 and 4): the ledger you are told to read first
disagrees with reality 41% of the time, and the lane's own workdir contains an
**empty `.coding-hermes/`** with nothing saying which board you are actually
supposed to write to.

**Is it trustworthy?** Mostly — with one named weakness: **its stopping
criteria are not always measurable**. A criterion that greps the whole repo for
a string the row itself contains can never be satisfied (that is `H3-PM-006`),
and a "complete" hygiene row (`H3-PM-002`) that leaves the same defect class
partly open is exactly the premature-completion pattern the PM skill exists to
catch. Both are cheap to fix and both are filed below.

**Time to first success:** ~12 min (read prompt + skill + ledger + board, then
reproduce the first criterion as a command).
**Friction count:** 5 (2 real traps, 2 stale-bookkeeping, 1 unmeasurable criterion).

## 4. Findings filed on the board

| ID | Prio | Finding |
|---|---|---|
| `DF-H3PM-01` | P1 | `H3-PM-006`'s criterion is unsatisfiable as written (11 live hits, all in the board/judge artifacts the criterion greps) — scope criteria to the surface under test |
| `DF-H3PM-02` | P2 | `H3-PM-002` did not close the id-reuse class: 6 ids still hold rows with distinct findings, 3 of them a **pending** row sharing an id with duplicate rows of another finding; 4 duplicate rows are `superseded_by` **themselves** |
| `DF-H3PM-03` | P2 | Ledger drift: **43 of 104** open ledger items are complete on their boards (41%), including 7 of today's 9 `H3-PM` rows → the Step-5 prior-run list is mostly closed work |
| `DF-H3PM-04` | P2 | Stand-in workdir trap: lane workdirs carry an **empty `.coding-hermes/`** (some lanes have none at all) and nothing documents target → real-workdir resolution; the retired `pm-standin-tick.sh` had it |
| `DF-H3PM-05` | P3 | Stale self-reported metrics inside closure notes (`H3-PM-003` says "six of 188 rows", live is 7; the ledger's `H3-PM-002` title still carries the pre-repair 172/151 counts vs the row's 177/167) |

## 5. What was left behind

- `docs/dogfood/2026-09-18-h3-pm-integration.md` — this report
- `skills/h3-pm-usage/SKILL.md` — how another agent consumes / re-runs the PM lane
- `docs/dogfood/h3-pm-diagnostics.md` — how the lane is built, the errors hit, the right way
- `.coding-hermes/dogfood-log.md` — run line
- Board rows `DF-H3PM-01..05` — the fixes, for the foreman
