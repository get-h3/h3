# QA-lane stand-in row recovery — DF-H3PM-06

- **Tick:** h3 tick #407 (`h3-2026-09-19-07-46-12`), task **DF-H3PM-06**
- **Date:** 2026-09-19 (UTC); recovery writes at 2026-09-19T07:54:43Z (rows) and 2026-09-19T07:55:34Z (stand-in annotation)
- **Scope at #407:** off-by-one leg only. The hermes-canopy leg was **deferred** then (its lanes were live at fire) and was **landed at tick #408** — see §5, which now carries both the landing and the #407 deferral text verbatim (§5.5).
- **Tick #408 (`DF-H3PM-06`, canopy leg):** row `QA-HERMES-CANOPY-QA-1` → `QA-HERMES-CANOPY-12` on the canopy owner board (362 → 363 rows, commit `252cc03`) and the stand-in board dir replaced by a satellite symlink.
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

## 5. LANDED at tick #408 — the hermes-canopy leg

**Status: DONE.** The deferral recorded in §5.5 was lifted and the canopy leg was executed at **h3 tick #408**, same task **DF-H3PM-06**. Nothing here rewrites the #407 record — §5.5 keeps the deferral text exactly as it was written; this section adds the landing.

### 5.1 Why the deferral condition was lifted

At #407 the leg was deferred under the collision rule because `hermes-canopy` and `hermes-canopy-qa` were running. At tick #408 (fire 2026-09-19T08:27Z = 03:27-05:00) **neither lane was running**:

```
$ ps -eo pid,lstart,etime,args | grep -i hermes-canopy | grep -v grep
1895695 Thu Sep 17 01:10:01 2026  2-02:18:21 node /home/kara/hermes-canopy/frontend/node_modules/.bin/vite --port 5173
```

The only match is the long-lived vite dev server (up since Sep 17, unrelated to the lanes) — no `hermes chat` worker. Scheduler state at the same moment:

```
hermes-canopy     last_tick_started=2026-09-19T02:42:31-05:00  last_tick_completed=2026-09-19T03:15:40-05:00
hermes-canopy-qa  last_tick_started=2026-09-19T02:30:18-05:00  last_tick_completed=2026-09-19T03:02:24-05:00
running/spawned tick rows fleet-wide: 8    with a LIVE pid: 0
```

**Correction to the tick-#408 brief, recorded not hidden:** the brief's two timestamps (`02:42:31` and `02:30:18`) are the lanes' `last_tick_started` values, not their completion times; the completions were `03:15:40` (foreman) and `03:02:24` (qa). The conclusion the brief drew from them — the deferral condition was lifted — holds either way: both lanes were between ticks at fire and no worker process was alive.

### 5.2 The recovered row

| old (stand-in) id | new (owner) id | priority | status | ts (carried over) |
|---|---|---|---|---|
| `QA-HERMES-CANOPY-QA-1` | **`QA-HERMES-CANOPY-12`** | P3 | pending | 2026-09-16T21:58:07.553Z |

Owner id proved free **before** the write: `QA-HERMES-CANOPY-QA-1` was absent from the owner board in both spacing styles (0 hits compact, 0 hits spaced), and the `QA-HERMES-CANOPY-<n>` family scanned across **all** statuses tops out at **n = 11**, so 12 is the next free slot (asserted in the appender: family max `== 11`, `12 not in nums`).

Owner board: `/home/kara/hermes-canopy/.coding-hermes/board/tasks.jsonl` — **362 → 363 rows**, append-only. Proven against a sha256-pinned pre-write snapshot (`677576555d9f8fa3…` → `/tmp/canopy_tasks_pre.jsonl`; hash re-verified inside the verifier):

```
(a) parsed rows before=362 after=363
(b) prefix bytes preserved verbatim: True
(c) byte-identical untouched lines=362 / 362
    changed/added line indices: [363]
(d) trailing newline preserved: True
(f) VERBATIM field equality vs stranded row:
      title equal=True   detail equal=True   review_notes equal=True
      reasoning equal=True   ts equal=True
(h) parsed-row count with id QA-HERMES-CANOPY-12: 1
(i) parsed-row count with id QA-HERMES-CANOPY-QA-1: 0   (the old id survives once, as provenance)
(m) pre-existing rows still parse to identical dicts: 362/362
```

`title`, `detail`, `review_notes`, `reasoning` and `ts` were copied verbatim (parsed-value equality asserted, not eyeballed) — including the source's `(bunker call: colect)` typo, which was left alone.

**Field set (15 keys):** the spine mirrors the neighbouring pending QA rows `QA-HERMES-CANOPY-9`/`-10` (`status, id, title, detail, priority, source, reasoning, review_notes, ts, foreman_note, updated_at`), then the provenance block the row requires (`recovered_from`, `recovered_id`, `recovered_at`, `recovered_by`). No field was removed from any existing row anywhere.

**Serialization note:** the row was written with `json.dumps(obj, ensure_ascii=False)` — em-dashes as literal UTF-8, spaces after the separators. That matches the three newest rows on the board (`DF-HERMES-CANOPY-30/31/32` are spaced-style) but **not** the older compact majority: the file was mixed-style **357 compact + 5 spaced** before this write and **357 + 6** after. The id-style greps were therefore run both ways — see (h)/(i) above.

**Commit:** **`252cc03`** (short sha) — `1 file changed, 1 insertion(+)`, exactly one `Co-authored-by:` trailer (appended by the repo's `prepare-commit-msg` hook; none supplied in `-m`). **Not pushed** (1 commit ahead of `origin/master`); the untracked `namespaces/` (foreign DuckBrain store) and `.gitreins/logs/` did not ride in.

**Guard on the canopy commit:** `gitreins guard; echo EXIT=$?` against the staged state exited **0** (`Tier 1 Guards: PASS (test mode: full)`, 0.338s) — but this is the vacuous-PASS class §7 already recorded: the guard log shows `No Go files staged` for `go_build`/`go_lint`/`go_tests`, and the console prints `No supported source files found. Supported extensions: …` (`jsonl` is not in that list), so **no test or build ran**. Only the `secrets` guard genuinely executed (gitleaks clean). Backstop for the suite claim: `grep -rn "tasks\.jsonl" --include=*.go --include=*.ts --include=*.tsx --include=Makefile` across the repo returns **0 hits**, i.e. no Go/TS source or Make target reads the board file, so a data-only append to it cannot change the suite's result. A normal commit was made; `--no-verify` was **not** needed.

### 5.3 The satellite link (rename-never-delete)

Applied to `/home/kara/.hermes/stand-in/pm/hermes-canopy/.coding-hermes/`, in this order — rename, then annotate the **preserved** copy, then link, so no write could pass through the link into the owner board:

```bash
cd /home/kara/.hermes/stand-in/pm/hermes-canopy/.coding-hermes
mv board board.pre-satellite-20260919                  # PRESERVE — nothing deleted
#   annotate the preserved row in place (add keys only, original bytes kept as a prefix)
ln -s /home/kara/hermes-canopy/.coding-hermes/board board
```

Verification (actual output):

```
$ ls -la /home/kara/.hermes/stand-in/pm/hermes-canopy/.coding-hermes/
lrwxrwxrwx 1 kara kara   45 Sep 19 03:28 board -> /home/kara/hermes-canopy/.coding-hermes/board
drwxrwxr-x 2 kara kara 4096 Sep 16 16:58 board.pre-satellite-20260919

$ readlink -f .../.coding-hermes/board
/home/kara/hermes-canopy/.coding-hermes/board
$ readlink -f /home/kara/hermes-canopy/.coding-hermes/board
/home/kara/hermes-canopy/.coding-hermes/board                     # MATCH: YES

$ parsed row count read THROUGH the link
363                                                               # owner board, incl. QA-HERMES-CANOPY-12

$ preserved row, read back from the preserved file
moved_to   = ["QA-HERMES-CANOPY-12"]
moved_at   = 2026-09-19T08:28:27Z
moved_note = recovered into the hermes-canopy owner board by h3 umbrella tick #408 (DF-H3PM-06)
keys: status, id, title, detail, priority, source, reasoning, review_notes, ts, moved_to, moved_at, moved_note
```

The preserved file keeps its original 9 keys with identical values and no trailing newline (829 bytes, still one parsed row — `wc -l` undercounts it to 0 exactly as §2 warns). The annotator asserts every original key/value survives and that the original bytes remain a strict prefix: the three new keys are inserted before the closing brace, so not one original byte moved.

Effect: the hermes-canopy QA lane's cwd-relative board writes now land on the owner board and are dispatchable. Definition of done for this class of fix is per-directory — the link exists only where it was created.

### 5.4 Strand census after the fix — one honest exception

Same method as §2 (`os.path.islink` on `<dir>/.coding-hermes/board`, parse `tasks.jsonl` in real dirs), run **after** the swap:

| root | dirs | satellite-linked | unlinked **with rows** |
|---|---|---|---|
| `/home/kara/.hermes/stand-in/pm` | 48 | **16** (was 15) | **0** (was 1) |
| `/home/kara/.hermes/stand-in/pm-lane` | 16 | 5 | 0 |
| `/home/kara/.hermes/stand-in/dogfood` | 43 | 13 | 0 |
| `/home/kara/.hermes/sync-workdirs` | 51 | 12 | **1 — `heading-sync`, 4 rows** |

**Residual, stated plainly: zero stranded rows remain in the QA-lane class.** Every surveyed `stand-in` root (`pm`, `pm-lane`, `dogfood`) now has 0 unlinked boards holding rows — the QA-lane strand count is 0. The one remaining strand is **not** a QA lane and **not** in the surveyed stand-in roots: `/home/kara/.hermes/sync-workdirs/heading-sync/.coding-hermes/board/tasks.jsonl` holds **4 pending rows** (`HSYNC-DF-001` P0, `HSYNC-DF-002` P1, `HSYNC-DF-003` P1, `HSYNC-DF-004` P2), all **0 hits** on the heading owner board (`/home/kara/heading/.coding-hermes/board/tasks.jsonl`), with the stand-in `board` still a real directory. **Not touched by this tick** — different project and a different lane class (sync), outside the DF-H3PM-06 canopy scope. It is the same defect class and deserves its own board row.

### 5.5 The #407 deferral record (RESOLVED — kept verbatim for history)

Everything from here to the end of this section is the §5 text as written at tick #407, extracted from this file and embedded byte-for-byte. It is retained unedited; the sections above supersede its **status**, not its history. Its original heading was:

`## 5. DEFERRED — the hermes-canopy leg`


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

**Resolution at tick #408:** steps (a) and (b) landed as planned, and (c) landed with the key set `moved_to`/`moved_at`/`moved_note` — the plan's `moved_ids` was NOT written; the single recovered id lives in `moved_to` (value `["QA-HERMES-CANOPY-12"]`), which is the recovered-row id shape used for the off-by-one leg as well. Acceptance for the canopy leg is now met.

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
