# QA-lane stand-in row recovery — DF-H3PM-06

- **Tick:** h3 tick #407 (`h3-2026-09-19-07-46-12`), task **DF-H3PM-06**
- **Date:** 2026-09-19 (UTC); recovery writes at 2026-09-19T07:54:43Z (rows) and 2026-09-19T07:55:34Z (stand-in annotation)
- **Scope this tick:** off-by-one leg only. The hermes-canopy leg is **deferred** (§5) because its lanes were live at fire.
- **Nothing pushed.** Commits land locally; the foreman pushes.

---

## 1. The defect

A QA lane's workdir is a stand-in directory (`/home/kara/.hermes/stand-in/pm/<project>`), not the owner repo. The board path the QA pipeline writes is **cwd-relative** (`.coding-hermes/board/tasks.jsonl`), so every row the QA lane files lands in the **stand-in's own board**:

```
cwd = /home/kara/.hermes/stand-in/pm/<project>
write -> /home/kara/.hermes/stand-in/pm/<project>/.coding-hermes/board/tasks.jsonl
```

The dispatch/read path is the **owner board** (`/home/kara/<project>/.coding-hermes/board/tasks.jsonl`). No foreman, PM cycle, or dispatch loop ever reads a stand-in board. Consequence: those rows are write-once-never-read — they are never dispatched, never counted against the board, and invisible to every audit that reads the owner board. The QA lane keeps producing findings; the findings do not exist from the owner board's point of view.

The fix in service elsewhere is the **satellite link**: a symlink named `board` inside the stand-in's `.coding-hermes/` pointing at the owner repo's board dir, so the stand-in's cwd-relative path *is* the owner board.

## 2. The measured survey

Method: enumerate `/home/kara/.hermes/stand-in/pm`, classify `<dir>/.coding-hermes/board` with `os.path.islink` / `os.path.isdir`, and parse any real board's `tasks.jsonl`. Script: `/tmp/df_h3pm_06_survey.py` (run by path). Result:

| class | dirs | stranded rows |
|---|---|---|
| **satellite-linked** (`board` is a symlink) | **14** | 0 |
| **unlinked** (`board` is a real dir) | **2** | **3** |
| no board path at all | 32 | n/a |
| **total** | **48** | |

The two unlinked dirs and their stranded ids:

| stand-in dir | stranded id | priority | ts | title |
|---|---|---|---|---|
| `off-by-one` | `QA-OFF-BY-ONE-QA-2` | P1 | 2026-09-17T22:14:15.412Z | [P1] QA battery launch phase never executed — collect has no evidence to gather |
| `off-by-one` | `QA-OFF-BY-ONE-QA-1` | P3 | 2026-09-16T21:06:51.518Z | [P3] Missing launce record blocks evidence collection |
| `hermes-canopy` | `QA-HERMES-CANOPY-QA-1` | P3 | 2026-09-16T21:58:07.553Z | [P3] Collect phase failures due to missing launch record |

Both off-by-one rows were confirmed genuinely stranded before recovery: `grep '"id":"QA-OFF-BY-ONE-QA-[12]"'` against the owner board returned **0**.

**Count discrepancy, recorded not hidden:** the tick-#407 foreman survey reports **13** satellite-linked dirs; the measurement this tick is **14**. Evidence: the 13 older links share mtimes `2026-09-17 01:16:38`–`01:17:23` (local), while the 14th —`/home/kara/.hermes/stand-in/pm/h3/.coding-hermes/board` → `/home/kara/get-h3/h3/.coding-hermes/board`— was created `2026-09-19 02:34:02` local (`07:34:02Z`), i.e. after the snapshot the brief's count came from. The difference is one link added between the survey and the brief, not a missing satellite.

**One measurement trap worth recording:** `wc -l` on `hermes-canopy/.coding-hermes/board/tasks.jsonl` reports **0** lines while the file in fact holds **1** row (662 bytes) — the file has no trailing newline. An unlinked-board census that trusts `wc -l` will conclude "empty, nothing stranded" for exactly this class of file.

## 3. What was recovered

| old (stand-in) id | new (owner) id | priority | status | ts (carried over) |
|---|---|---|---|---|
| `QA-OFF-BY-ONE-QA-2` | **`QA-OFF-BY-ONE-16`** | P1 | pending | 2026-09-17T22:14:15.412Z |
| `QA-OFF-BY-ONE-QA-1` | **`QA-OFF-BY-ONE-17`** | P3 | pending | 2026-09-16T21:06:51.518Z |

Owner ids: `QA-OFF-BY-ONE-<n>` was at max **n = 15** across all statuses, so 16 and 17 are the next free slots and are unique (verified: exactly one row each).

Owner board: `/home/kara/off-by-one/.coding-hermes/board/tasks.jsonl` — **123 → 125 rows**, appended only (never re-serialized; the first 123 lines are byte-identical to `HEAD`).

`detail` and `review_notes` were copied **verbatim** from the stranded rows (byte-equality asserted in the appender, not by eye) — including the original typos in `review_notes` ("launch phas never ran") and the original `ts`. Title for the P3 row uses the corrected spelling "launch" per the task brief; the copied `detail`/`review_notes` keep the original wording.

Provenance field set written into each recovered row (**37 keys**, insertion order, compact separators — matching the owner file's newest row):

- recovery identity: `source` (`qa-dagger`), `reasoning` (`{"note": "<stranded QA foreman cycle note> — original reasoning preserved; row recovered into the owner board at h3 tick #407 (DF-H3PM-06) because it was written by the QA lane into the stand-in workdir and was never dispatchable."}`), `related_rows` (`["QA-OFF-BY-ONE-1"]`)
- chain of custody: `recovered_from`, `recovered_id`, `recovered_at`, `recovered_by` (`h3 tick #407 DF-H3PM-06`), `foreman_note`
- dispatchable field set mirrored from the neighbouring pending QA row `QA-OFF-BY-ONE-15` (owner board line 109, read at write time): `worker_status` (`pending`), `attempts`, `dispatched_at`, `completed_at`, `exit_code`, `commit_hash`, `files_changed`, `lines_added`, `lines_removed`, `guard_result`, `ci_result`, `worker_summary`, `blocked_reason`, `blocked_since`, `depends_on`, `blocks`, `capability_tags`, `complexity`, `primary_model`, `primary_provider`, `fallback_model`, `fallback_provider` (all `null` in that neighbour).

No field was removed from any existing row anywhere.

## 4. The fix (rename-never-delete)

Applied to `/home/kara/.hermes/stand-in/pm/off-by-one/.coding-hermes/`:

```bash
cd /home/kara/.hermes/stand-in/pm/off-by-one/.coding-hermes
mv board board.pre-satellite-20260919        # PRESERVE the original rows — never delete
ln -s /home/kara/off-by-one/.coding-hermes/board board
```

The preserved copy keeps all original rows, with the two stranded rows annotated in place (`moved_to`, `moved_ids`, `moved_at`) by a per-line edit that adds keys to the row dict without touching the original content — every pre-existing key survives with an identical value, and the serializer round-trip for each original line is asserted byte-for-byte inside the annotator before the write (`/tmp/df_h3pm_06_annotate.py`).

Verification (actual output):

```
$ readlink -f /home/kara/.hermes/stand-in/pm/off-by-one/.coding-hermes/board
/home/kara/off-by-one/.coding-hermes/board          # MATCH: YES
$ ls -l .../.coding-hermes/
lrwxrwxrwx board -> /home/kara/off-by-one/.coding-hermes/board
drwxrwxr-x board.pre-satellite-20260919             # preserved, still present
$ wc -l < .../.coding-hermes/board/tasks.jsonl
125                                                 # resolves through the link
$ wc -l < .../.coding-hermes/board.pre-satellite-20260919/tasks.jsonl
2                                                   # original rows preserved
$ grep -c moved_to .../board.pre-satellite-20260919/tasks.jsonl
2                                                   # annotation present on both rows
```

Effect: the off-by-one QA lane's cwd-relative board writes now land on the owner board and are dispatchable. Definition of done for this class of fix is per-directory — the link exists only where it was created.

## 5. DEFERRED — the hermes-canopy leg

**Not touched this tick.** Nothing under `/home/kara/hermes-canopy`, its git tree, or `/home/kara/.hermes/stand-in/pm/hermes-canopy` was modified (the stand-in dir still holds its own real `board` dir; the owner board was read only).

Collision evidence — hermes-canopy and hermes-canopy-qa lanes were **running** when tick #407 fired (spawned 2026-09-19T02:30:18-05:00):

```
$ ps -eo pid,lstart,etime,args | grep -i hermes-canopy | grep -v grep
3013999 Sat Sep 19 02:45:04 2026  bash -lic set +m; cd /home/kara/hermes-canopy && ... hermes chat -q \
    "$(cat /tmp/hermes-canopy-t516-pl03-client-brief.md)" -m gpt-5.6-luna --provider openai-codex \
    -s coding-hermes-worker --ignore-rules -Q >> /tmp/hermes-canopy-t516-worker.log 2>&1 ...
1895695 Thu Sep 17 01:10:01 2026  node /home/kara/hermes-canopy/frontend/node_modules/.bin/vite --port 5173
```

A live worker writing in that repo while a board row is recovered into it is a write/commit race on a shared tree; the leg is next-tick work.

Still stranded in that stand-in: **1 row** — `QA-HERMES-CANOPY-QA-1` [P3] "Collect phase failures due to missing launch record", ts `2026-09-16T21:58:07.553Z`.

Related owner-board context (read-only): the canopy owner board already carries the open row **`QA-HERMES-CANOPY-10`** whose text is *"hermes-canopy-qa is re-picked every cycle against an empty stand-in workdir"* (both the id and the phrase match once each). Canopy QA ids top out at **11**, so `QA-HERMES-CANOPY-12` is the next free owner id for the deferred recovery.

Deferred plan: when the canopy lanes are idle — (a) append `QA-HERMES-CANOPY-QA-1` to `/home/kara/hermes-canopy/.coding-hermes/board/tasks.jsonl` as `QA-HERMES-CANOPY-12` with the same provenance field set, (b) rename-and-link `/home/kara/.hermes/stand-in/pm/hermes-canopy/.coding-hermes/board` → `board.pre-satellite-20260919` + symlink to the canopy owner board, (c) annotate the preserved row with `moved_to`/`moved_ids`/`moved_at`. Acceptance is not met for the canopy leg until that lands.

## 6. Verification commands and actual results

**off-by-one owner board (CHANGE 1)** — script `/tmp/df_h3pm_06_verify.py`:

```
(a) lines=125  json.loads OK=125  parse failures=NONE
(b) row count == 125 ? True (actual 125)
(c) QA-OFF-BY-ONE-16 occurrences=1 exactly-one? True
(c) QA-OFF-BY-ONE-17 occurrences=1 exactly-one? True
(d) HEAD lines=123  compared=123  byte-identical=123  (must be 123) True
    first mismatching line indices: NONE
VERDICT: PASS
row QA-OFF-BY-ONE-16 | priority=P1 | status=pending | ts=2026-09-17T22:14:15.412Z | recovered_id=QA-OFF-BY-ONE-QA-2 | keys=37
row QA-OFF-BY-ONE-17 | priority=P3 | status=pending | ts=2026-09-16T21:06:51.518Z | recovered_id=QA-OFF-BY-ONE-QA-1 | keys=37
```

The stranded ids no longer exist as row ids on the owner board (`grep -c '"id":"QA-OFF-BY-ONE-QA-[12]"'` → **0**) and appear only as provenance: `grep -c '"recovered_id":"QA-OFF-BY-ONE-QA-[12]"'` → **2**.

**Commit (off-by-one):** `git rev-parse HEAD` → `c5fb7108d2da0f3534c097352ee462d917f1433a`

```
$ git show --stat HEAD
 .coding-hermes/board/tasks.jsonl | 2 ++
 1 file changed, 2 insertions(+)
```

Commit body carries **exactly one** `Co-authored-by:` line (appended by the repo's `prepare-commit-msg` hook; none supplied in `-m`). Not pushed.

**Stand-in (CHANGE 2)** — results in §4 (readlink match YES, 125 rows through the link, preserved dir present with 2 annotated rows).

**h3 (CHANGE 3)** — this document; commit hash and `make verify` exit code are recorded in the tick report.

## 7. Residual observation — UNVERIFIED CAUSE

Recorded as observed, with no causal claim:

- **Observation as reported to this tick:** a `gitreins guard` run on a staged JSONL-only diff in `/home/kara/off-by-one` did not complete within 180s under loadavg ~16 at 2026-09-19T07:48Z and wrote **no** guard log, while clean-tree runs complete in seconds.
- **What this tick measured instead:** a guard log **does** exist at `/home/kara/off-by-one/.gitreins/logs/guard-20260919T074806.425736Z.log` (1332 bytes, `run_utc: 2026-09-19T07:48:06Z`, `overall: PASS`, `guards: 4 (0 failed, 0 skipped)`), and this tick's own commit at `07:54:58Z` completed in **0s** with its own log (`guard-20260919T075458.622501Z.log`). Both staged-diff runs report the short-circuit path — `No Go files staged` for `go_build`/`go_lint`/`go_tests` and `No supported source files found` on the console — i.e. the guard's Tier-1 battery does not execute tests for a diff containing no file extension it treats as source.
- **Not claimed:** whether the reported 180s stall was a different run than the one that logged at `07:48:06Z`, a guard-process contention effect under load, or something else. The two readings have not been reconciled. Note loadavg fell from 23.87 (07:53Z) to 6.90 (07:55Z) across the recovery, so this tick's 0s run and the reported stall did not occur under comparable load. Cause: **UNVERIFIED**.
