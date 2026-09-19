# PM ledger ↔ board reconciliation (DF-H3PM-03)

**Scope:** the stand-in PM ledger at `~/.hermes/stand-in/ledger.json` and every project board
(`<workdir>/.coding-hermes/board/tasks.jsonl`) it is compared against.
**Status:** the reconciler exists and has been run for `h3` (tick #397). The PM-cycle behaviour in
the last section is required of the lane, not yet enforced by it.

## Why the ledger overstates open work

The PM lane keeps its own fleet-wide ledger: a JSON object with an `items` list, one item per filed
finding, each carrying its **own** status (`added`, `picked_up`, `verified`, `stale`, `blocked`) plus
`added_at`, `last_checked_at`, `pass_criteria` and `verification_evidence`. The work itself is closed
on the project's board — the ledger was never read back against that board, so the two stores drifted.

Measured before this tick's reconciliation: **154** ledger items were in a non-terminal state
(`added` or `picked_up`) while **60** of them were already `status=complete` on their project's board
and **5** had no matching board row at all.

Two costs, both paid every cycle:

- **The digest overstates outstanding work.** A PM digest built from the raw `added`/`picked_up`
  count reports work as open that the board closed — the reader cannot tell a genuinely open row
  from a ledger row the foreman already finished.
- **The prior-run pass re-checks closed rows.** A cycle that re-reads `pass_criteria` for every
  "open" item spends its budget re-running checks whose answer is already on the board. In the `h3`
  slice, *all ten* open ledger items were already complete on the board — a full cycle's budget for
  that project produced nothing.

The fix is reconcile-on-read: read the board row before treating a ledger item as due, stamp
`completed_at` when the board shows the work is closed, and report the reconciled number.

## Measured at 2026-09-19 (tick #397, before reconciliation)

154 ledger items status added/picked_up — 60 already complete on their boards, 5 with no matching board row (hivemind-work HW-GAP-006..010), 89 genuinely open. h3 slice: 10 of 10 already complete on the board.

Ledger status histogram over all 2141 items at the same moment (`verified` 1983, `added` 129,
`picked_up` 25, `stale` 3, `blocked` 1). The classification was made by the tool below, against the
board resolved through the scheduler db:

```
$ python3 scripts/ledger-board-reconcile.py --all --json | python3 -c "import json,sys;print(json.dumps(json.load(sys.stdin)['before']['totals'],indent=2))"
{
  "projects": 51,
  "unresolved_board": 6,
  "open_items": 154,
  "already_complete": 60,
  "still_open": 89,
  "no_board_row": 5
}
```

The 5 `no_board_row` items are all `hivemind-work` (`HW-GAP-006`..`HW-GAP-010`): that project's board
holds 106 rows and none of them carries those ids. They are named below, not closed.

## Recipe

Dry run (read-only — the default). Prints a per-project table, fleet totals, and the item list behind
`already_complete` and `no_board_row`:

```bash
python3 scripts/ledger-board-reconcile.py --project h3      # one project (--project repeats)
python3 scripts/ledger-board-reconcile.py --all             # every project named in the ledger
```

Machine-readable, one JSON object on stdout — `ledger`, `db`, `applied`, `before.{projects,totals}`
and, with `--apply`, `after` in the same shape:

```bash
python3 scripts/ledger-board-reconcile.py --all --json
```

Write the reconciliation. Additive-only: it touches **only** items classified `ALREADY_COMPLETE`,
setting `status="verified"`, `completed_at`, `last_checked_at` (same UTC timestamp) and a
`verification_evidence` string naming the board row and this tool. Every other key and value is
carried over verbatim and in its original order; `STILL_OPEN` and `NO_BOARD_ROW` items are not
modified at all:

```bash
python3 scripts/ledger-board-reconcile.py --project h3 --apply
python3 scripts/ledger-board-reconcile.py --all --apply
```

**PM-lane lockout.** The ledger is single-writer and the project's PM lane owns it while it runs.
Before mutating anything, `--apply` probes `http://localhost:9090/api/v1/ticks` (10s timeout) and
aborts **without writing** when any *running* tick's `project_name` ends with `-pm`:

```
ABORT: <project> PM lane is running — the ledger is owned by that lane while it runs
```

An unreachable tick API is also a refusal (`exit 3`) — the tool cannot prove the lane is idle — and
proceeds only when `--apply` is combined with an explicit `--force`. When the apply does run it takes
an exclusive `fcntl.flock` on the ledger for the whole read-modify-write, re-reads the file inside the
lock, writes a `ledger.json.bak-<UTC ts>` backup before the first mutation, and `os.replace()`s a
same-directory tmp file into place.

Exit codes: `0` ok, `1` ledger missing/unparseable, `2` usage error, `3` apply refused.
The tool is read-only unless `--apply` is passed; with `--all` or `--project` missing it prints usage
to stderr and exits 2.

## Result

`h3` slice, before (dry run):

```
$ python3 scripts/ledger-board-reconcile.py --project h3
ledger-board-reconcile — DF-H3PM-03 (scripts/ledger-board-reconcile.py, h3 tick #397)
ledger: /home/kara/.hermes/stand-in/ledger.json
db:     /home/kara/.hermes/coding-hermes/scheduler.db
mode:   dry run (read-only; pass --apply to write)

project                              open  compl  still no_row board
h3                                     10     10      0      0 ok
TOTALS (1 swept)                       10     10      0      0 0 unresolved project(s)

ALREADY_COMPLETE — 10 item(s) the board already closed:
  h3 GAP-072 [board=complete] Compliance-test count drift: 45 `def test` in battery vs 44 cla…
  h3 GAP-073 [board=complete] Roundtrip CI still cannot fire on SDK source changes (caller wo…
  h3 H3-PM-002 [board=complete] P1 - row-id reuse: 172 rows / 151 unique ids; distinct findings…
  h3 H3-PM-003 [board=complete] P2 - 6 rows record a cross-repo commit_hash with no repo attrib…
  h3 H3-PM-004 [board=complete] P2 - protocol/ has no board and no lane
  h3 H3-PM-005 [board=complete] Fabricated h3-test output block in docs/migration.html (Edge Ca…
  h3 H3-PM-006 [board=complete] DEPLOY.md Go manual snippet cannot compile (protocol.EndResult …
  h3 H3-PM-007 [board=complete] specs print live get-h3.github.io URLs that 404; pages.yml rede…
  h3 H3-PM-008 [board=complete] specs/24 documents a compat-CI surface (h3-test --compat, scrip…
  h3 H3-PM-009 [board=complete] specs/09 documents a --json summary/regions payload + jq gate t…
```

`--apply`, tail (the table and item list above repeat; only the last lines are shown):

```
$ python3 scripts/ledger-board-reconcile.py --project h3 --apply
items treated: 10
backup:        /home/kara/.hermes/stand-in/ledger.json.bak-20260919T034138Z
before:        {"already_complete": 10, "no_board_row": 0, "open_items": 10, "projects": 1, "still_open": 0, "unresolved_board": 0}
after:         {"already_complete": 0, "no_board_row": 0, "open_items": 0, "projects": 1, "still_open": 0, "unresolved_board": 0}
```

After (the same read command as before, i.e. evidence the items left the open set) — full payload:

```
$ python3 scripts/ledger-board-reconcile.py --project h3 --json
{
  "ledger": "/home/kara/.hermes/stand-in/ledger.json",
  "db": "/home/kara/.hermes/coding-hermes/scheduler.db",
  "applied": false,
  "before": {
    "projects": {
      "h3": {
        "open_items": 0,
        "already_complete": 0,
        "still_open": 0,
        "no_board_row": 0,
        "unresolved_board": false
      }
    },
    "totals": {
      "projects": 1,
      "unresolved_board": 0,
      "open_items": 0,
      "already_complete": 0,
      "still_open": 0,
      "no_board_row": 0
    }
  }
}
```

What the write actually changed, diffed against the backup: **10 items, all `h3`**, and on every one
of them the only changed keys are `status`, `completed_at`, `last_checked_at`,
`verification_evidence` — the item key multiset is unchanged, the relative order of the pre-existing
keys is unchanged, and `completed_at` sits immediately after `status`. A second `--apply` on the same
slice is a no-op: 0 items treated, no new backup, ledger byte-identical (`sha256` unchanged).

Safety branches exercised against a **copy** of the ledger with a local stub ticks endpoint, so no
live ledger was at risk:

| case | ticks endpoint | result |
|---|---|---|
| unreachable, `--apply` | closed port | `WARNING: tick API unreachable … Connection refused` + `ABORT: … --force was not given`, `exit 3`, ledger `sha256` unchanged |
| unreachable, `--apply --force` | closed port | proceeds, 10 items treated, backup written next to the copy |
| PM lane running, `--apply` | stub returning `h3-pm` `running` | `ABORT: h3-pm PM lane is running — the ledger is owned by that lane while it runs`, `exit 3`, no backup, ledger `sha256` unchanged |
| real fleet, `--apply` | live API (9 running ticks, none `-pm`) | no abort, write performed — this is the case above that ran for real |

## Required PM-cycle behaviour

The lane, not this tool, decides what a cycle does with the numbers. A cycle is only reconciled when
it does all four:

1. **Reconcile on read.** Before listing a ledger item as due, read its board row (id → status) and
   classify: board status in `complete`/`closed`/`done`/`cancelled` = closed; any other status = open;
   no row = no board row.
2. **Stamp `completed_at`** on ledger items whose board row is complete — the timestamp of the check
   that observed the closure, plus `verification_evidence` naming the board row and the reconciler.
   Do not re-open, and do not touch items the board still shows as open.
3. **Report the reconciled number**, never the raw `added`/`picked_up` count: `open = still_open`
   (board-open), with `already_complete` and `no_board_row` reported alongside it as separate lines.
4. **Name every residual disagreement** in the cycle report — each `STILL_OPEN` item (board row
   exists, board does not consider it closed: the ledger's real backlog) and each `NO_BOARD_ROW` item
   (no board row: the finding is filed nowhere the board can see). A silent close of either class is
   forbidden: only the board decides closure.

## Scope and residual

- **Related tooling (overlap, stated honestly).** A PM-lane reconciler already existed fleet-side
  before this tick: `~/.hermes/stand-in/ledger_board_reconcile.py` → a symlink to
  `ops/pm-standin/ledger_board_reconcile.py` in the scheduler repo (MYPROJECT-GAP-047/049, commit
  1efacf7, 2026-09-13), dry-run by default, with a wider bucket set (`drift_closable`, `stale_drift`,
  `board_open_work`, `board_missing`, `no_id_match`, `ambiguous`, `age_unknown`) and its own
  pre-write backup. So the drift measured above was **not** caused by a missing tool — it was caused
  by the PM cycle never calling one: the `coding-hermes-project-manager` skill's Step 1 tells the lane
  to eyeball each item's board row, names no tool, and nothing on this host schedules the ops script.
  This repo's `scripts/ledger-board-reconcile.py` is the versioned twin (same verified mapping,
  one command, the same PM-lane lockout rule, `--apply` additive-only). The wiring fix — Step 1 of
  the PM cycle runs a reconciler before listing anything and reports the reconciled number — is
  tracked on this board as **H3-GAP-093**.

- The tool reconciles the **ledger** — fleet data at `~/.hermes/stand-in/ledger.json`, which is not
  committed in this repo. The `h3` slice above was applied to the live ledger; the other 144 open
  items were left alone by this tick, and 50 of those are `ALREADY_COMPLETE` for other projects
  (fleet totals after the `h3` apply: 144 open / 50 already complete / 5 no board row / 89
  still open) — applying the fleet-wide sweep is a separate decision that belongs to the PM lane.
- **The PM lane prompt/skill change is fleet-side and tracked separately.** Nothing in this repo can
  make a cycle call the reconciler; until the lane does, the ledger drifts again on the next filing.
- **The 5 `hivemind-work` rows with no board row are named, not closed**: `HW-GAP-006` (Go version
  drift across README/quickstart), `HW-GAP-007` (`go test ./... -short` not hermetic), `HW-GAP-008`
  (bare `hivemind serve` defaults to `:8080`), `HW-GAP-009` (three competing startup narratives),
  `HW-GAP-010` (fresh-clone quickstart cannot produce the web UI). They need a board row or a
  withdrawal, and either decision belongs to the PM lane and that project's foreman.
- **`STILL_OPEN` is untouched by design.** 89 items fleet-wide have a board row whose status is not
  terminal. The tool never writes them: the board's own answer is "not closed", and inventing a
  ledger status for it would destroy exactly the disagreement this tool exists to surface.
- **6 swept projects have no resolvable board** — `bankai` (db row present, board file absent) and
  `get-h3/shim`, `h3-sdk-go`, `h3-sdk-python`, `h3-sdk-typescript`, `helios-work` (no db row at all).
  They hold 0 reconcilable items today, so they change no number — but they are reported as
  `unresolved_board` rather than skipped, so a project that starts filing items while unresolved is
  visible instead of silently counted as clean.
- **The lockout probe reads the tick API's most recent 50 ticks.** A `-pm` tick older than that
  window would not be seen; running ticks are the newest rows, so this is a narrow gap, but it is a
  gap — `--apply` is not a substitute for the lane's own single-writer discipline.
