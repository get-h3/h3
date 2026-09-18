# h3-pm Diagnostic Trail — how the PM lane is built, what broke, the right way

Not raw logs. This explains what the `h3-pm` lane *is*, how a tick actually
executes end to end, the errors hit during the 2026-09-18 dogfood run and their
fixes, and the patterns that are proven to work. Written from the consumer side
(someone using the lane), not the builder's.

## 1. How the thing is built

```
~/.hermes/fleet.toml
  [[projects]] name="h3-pm"
      workdir = ~/.hermes/stand-in/pm-lane/h3      ← scheduling home (EMPTY on purpose)
      namespace_id = "pm"                          ← which prompt/tick shape applies
      cooldown_s = 86400, enabled = true
      deliver = telegram:-1003310984808:84802

  [[namespaces]] id="pm"  default_prompt = '''
      target = <row name minus "-pm"> → h3
      load skill coding-hermes-project-manager + pm-injected-board-rows
      run the cycle YOURSELF; the Dagger pm.ts pipeline is RETIRED
  '''

target "h3" → projects.name='h3' → workdir /home/kara/get-h3/h3
                                     └── .coding-hermes/board/tasks.jsonl   ← the real board
```

Two executors exist and only one is live:

| Executor | Status | Where its traces show up |
|---|---|---|
| Skill-driven cycle (the live one) | current | DuckBrain ns `coding-hermes`, keys `/stand-in/<date>/h3`, `/stand-in/<date>/cycle`; rows `H3-PM-*` on the h3 board |
| `~/.hermes/scripts/pm-standin-tick.sh` + `examples/coding-hermes/pm.ts` | **RETIRED** (still on disk) | DuckBrain ns `stand-in-pm`, keys `/pm/<target>/last-run` (h3's last entry: 2026-09-01), ledger writes, `push-scratch-*.jsonl` |

The retired script is worth reading once, because it encodes the *contract* the
agent is now expected to reproduce by hand: derive the target from the row name,
resolve the target's real workdir from `scheduler.db`, refuse to run if the
router has no tool lane, hard-filter proposals to the target, and write
`INSERT row → append event → ledger entry`.

### The PM's data model (four stores, one truth)

| Store | Role | Truth? |
|---|---|---|
| `.coding-hermes/board/tasks.jsonl` | the work list the foreman reads and closes | **canonical** |
| `.coding-hermes/board/events.jsonl` | immutable add/complete/audit trail | append-only record |
| `~/.hermes/stand-in/ledger.json` | the PM's memory across cycles (status/evidence/gates) | the PM's *claim* — verify against the board |
| `~/.hermes/stand-in/digest-input.json` | per-cycle digest bundle built by `ledger_board_reconcile.py` | derived |
| DuckBrain ns `coding-hermes` `/stand-in/<date>/*` | decision trail a human reads later | the cycle report |

The PM skill says it plainly: *"When the ledger and the evidence disagree, the
evidence wins."* This run measured how often they disagree — see §3.2.

## 2. What a healthy tick leaves behind (the pattern to check)

For 2026-09-18 the h3 lane left, verifiably:

- 9 rows `H3-PM-001..009`, all `status=complete`, each with a `commit_hash`
  that resolves, and 5 of them with a literal `PASS:` criterion in
  `review_notes`;
- cycle log `/stand-in/2026-09-18/h3` (06:33Z) + `/stand-in/2026-09-18/cycle`
  (06:34Z, "h3-pm lane, ONE project h3 … 5 gated rows written and committed");
- ledger entries for all 9 with `gates:` recorded (G1 format … G7 dedupe);
- board hygiene product: 13 rows marked `duplicate` with `superseded_by`, and
  the `commit_repo` field (H3-PM-003) that makes a cross-repo hash resolvable.

That is a real, useful product. The rest of this document is the friction.

## 3. Errors and friction hit during the run, and the right way

### 3.1 A criterion that can never pass (H3-PM-006)

**Symptom.** The row is `complete` with `review_notes: "PASS grep: grep -rn
'EndResult' /home/kara/get-h3/h3 == 0 hits"`. Running it gives **11** hits.

**Cause.** The searched string lives in the *artifacts of the search*: the
board row itself (`tasks.jsonl:174`), `events.jsonl` (×2), and the GitReins
judge history (`.gitreins/history/2026-09-18/f791143b/*`, ×8). `DEPLOY.md` is
clean and the Go block was fixed properly (all five `Harness` methods, `EndResult`
replaced by `protocol.End`, `DecisionID` on every `Decision`).

**Right way.** A pass criterion must name the *surface under test*:

```bash
# wrong — matches its own row, the events log and the judge artifacts
grep -rn 'EndResult' /home/kara/get-h3/h3

# right
git -C /home/kara/get-h3/h3 grep -n EndResult -- '*.md' '*.go' '*.html'
grep -rn --exclude-dir=.git --exclude-dir=.coding-hermes --exclude-dir=.gitreins 'EndResult' .
```

**Why it matters beyond one row.** An unmeasurable criterion is worse than no
criterion: it converts a verified fix into an unverifiable one, and the next
auditor either trusts the board (false pass) or reopens a fixed bug (wasted
tick). This is the "externalized stopping criteria" failure the dogfood
research names.

### 3.2 The PM's memory lags the board (43 of 104)

**Symptom.** `ledger.json` lists 104 items as still open (`added` /
`picked_up`). Reconciling each against its project's board — workdirs resolved
from `scheduler.db`, because project names are not paths — **43 of them are
already `complete` on the board** (41%). For h3 specifically, 7 of the 9 rows
filed the same day were closed by the foreman *after* the 06:24Z cycle, so the
ledger still had them `added` at 06:40Z.

**Cause.** Step 5 of the PM cycle updates the ledger for the rows it looks at
that cycle; rows a foreman closes between cycles are only reconciled on the
*next* PM pass (24h later for this lane). Nothing reconciles on read.

**Right way.** Reconcile before you use:

```bash
python3 ~/.hermes/stand-in/ledger_board_reconcile.py    # builds the digest, classifies drift
```

…or read the board row before treating a ledger item as due. Do not quote the
raw open count as outstanding work — it overstates by ~40% fleet-wide.

### 3.3 The lane's own workdir is a trap (H3-PM-004's neighbourhood)

**Symptom.** `~/.hermes/stand-in/pm-lane/h3/.coding-hermes/` exists and is
**empty**. The sibling stand-ins (`stand-in/pm/h3`, `stand-in/dogfood/h3`,
`sync-workdirs/h3-umbrella-sync`) have no `.coding-hermes/` at all. The PM
skill's gate G4 says the board must be at "the path the foreman reads
(`.coding-hermes/board/tasks.jsonl`)", which reads as cwd-relative; a tick that
takes it literally writes into a directory nobody reads and produces theater
rows.

**Cause.** The stand-in path is a *scheduling* home chosen to keep one enabled
project per real workdir (the 409 case-insensitive conflict). Target resolution
used to be code (`pm-standin-tick.sh` lines 52-65: `SELECT workdir FROM
projects WHERE name='<target>'`, then a hard filter on proposals). In the
skill-driven path it is undocumented prose.

**Right way.**

```bash
TARGET="h3"   # row name minus -pm
sqlite3 ~/.hermes/coding-hermes/scheduler.db "SELECT workdir FROM projects WHERE name='$TARGET'"
# → /home/kara/get-h3/h3     ← the board you write to; never the stand-in dir
```

### 3.4 Duplicate markers that cannot be resolved

`superseded_by` is supposed to name the canonical row. On the h3 board four
`duplicate` rows name **themselves** (`DF-H3-1`, `QA-H3-1` ×2, `QA-H3-2`),
and six ids still hold rows with *distinct* findings — including three where a
`pending` row shares an id with duplicate rows of a different finding
(`DF-H3-3` holds the pending "`hermes-h3 install` rejects `--name`" next to two
copies of the docs-count family). Fingerprint by **content** (the PM skill's own
G7 rule), fix the id, then mark the duplicate with the surviving id. A duplicate
row does not stop an id from being reused.

### 3.5 Infrastructure: the ephemeral bunker leg

`bunker spawn --server bunker-las-03 --ttl 2h` failed the first time with
`deadline_exceeded: context deadline exceeded` after ~300s (host healthy,
bunkerd active, `/` at 31% — 13 agent users already present, none created by the
failed attempt, so there was nothing half-spawned to clean up). A second attempt
succeeded (`437f91a0`). Lesson: treat the first spawn deadline as **transient**;
retry once before filing `SKIPPED-install-bunker`, and always verify host-side
that no partial user was left behind. Install and smoke legs must run over
direct `ssh -i ~/.bunker/keys/<id>` (not `bunker exec`, which has stream
deadlines). Destroy afterwards and prove it: `bunker list` → "No agents found",
`ls /home/bunker-<id>` → no such file.

## 4. Verified-good behaviors (trust anchors, 2026-09-18)

- Board parses clean: 188 rows, 0 malformed lines; statuses 106 complete /
  69 pending / 13 duplicate.
- Every `commit_hash` on the newest rows resolves in the repo the row names
  (`59ecfeb`, `312469b`, `a6b0684`, `d69409b` → h3; `507264b6` → protocol).
- `commit_repo` rows (H3-PM-003's product): **7/7** resolve in `get-h3/shim`.
- `docs/migration.html`'s corrected sample output: categories `7/8/6/7/13/5`
  sum to **46**, equal to `EXPECTED_TEST_COUNT` in `shim`'s `test_battery.py:104`.
- `specs/24` states 7 not-implemented artifacts explicitly; `specs/09` names
  the 8 keys the CLI actually emits; live spec URLs that 404 are labelled
  `planned — not implemented` with the 404 stated in the same paragraph.
- `pages.yml` no longer triggers on `specs/**` (and documents why `'*.md'` is
  used instead of `'**.md'`).
- Fresh-machine install of the governed ecosystem (`shim`): clone → venv →
  install → scaffold → `h3-test` **46/46, exit 0, 24s** on agent `437f91a0`
  (bare Debian, python3 3.13.5, non-root), agent destroyed clean.
- Cycle log present for the day: `/stand-in/2026-09-18/h3` +
  `/stand-in/2026-09-18/cycle` in DuckBrain ns `coding-hermes`.

## 5. The right way to consume this lane (short version)

1. Read the **board**, not the ledger, for status.
2. For each row that matters, run the row's own `PASS:` criterion — scoped to a
   surface — and resolve its `commit_hash` in `commit_repo`.
3. Check the **cycle log** exists for the date you are citing; if it does not,
   the cycle did not report.
4. Treat ledger counts as claims; reconcile with `ledger_board_reconcile.py`
   before quoting them.
5. File defects as rows (never fix in place), pointing at the artifact with a
   command the next verifier can re-run.
