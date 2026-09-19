# Pending-row evidence audit — QA-H3-8

Board row `QA-H3-8` (`.coding-hermes/board/tasks.jsonl`, source `qa-dagger`, filed 2026-09-05) claimed:

> P1/P2 board rows stuck with `attempts=0` for 4-8 days; the never-done audit claims 'zero gaps'.
> GAP-069 (P1, escalated 2026-08-29, pending since 08-27 22:35Z, attempts=0), GAP-072/GAP-073
> (P2, 2026-08-31, attempts=0), DF-H3-1..5 (filed 2026-09-01, pending). Board rows marked pending
> never get dispatched — the audit contradicts its own board.

This document records a **re-measurement of that claim's item list** at h3 `HEAD 16c76a8`
(2026-09-19), the evidence method used, and the residuals that are still live. It is the
evidence companion to the row's `review_notes` / `measured_state` fields.

## Method

Content + commit evidence per item, never id-grep alone (cycle-slot id reuse and id re-issue are
both live board conventions here, so an id match proves nothing about a finding):

- resolve every sha with `git show --stat <sha>` **in the repo the row names**, then prove it is
  published with `git branch -r --contains <sha>` (must list `origin/main`);
- re-run each row's **own PASS predicate** as a content check (the predicated grep / count / file
  state), not the row's prose;
- re-measure the board-level instrument the finding rests on (`attempts`, `status`, event history
  per task id in `.coding-hermes/board/events.jsonl`);
- read the current NEVER-DONE audit wording rather than the #319-era wording the row quotes.

## Board snapshot at the audit

```
$ wc -l .coding-hermes/board/tasks.jsonl
205 .coding-hermes/board/tasks.jsonl
$ # status histogram (parser over every line)
complete 140 | pending 52 | duplicate 13          (205 rows, 0 unparseable)
$ # attempts field
attempts=0: 110 rows | attempts absent: 89 rows | attempts=1: 6 rows
```

## Per-item result

| Item (as filed) | State measured 2026-09-19 | Evidence | Class |
|---|---|---|---|
| `GAP-069` — "P1, escalated 2026-08-29, pending since 08-27 22:35Z, attempts=0" | `status: complete`, closed 2026-09-11 05:58:04 | `get-h3/h3` `41e2cc0` (`docs(specs): GAP-069 — drive _index.md Status column …`), listed by `git branch -r --contains 41e2cc0` → `origin/main`. PASS predicate re-run: `grep -n '^| 2[0-6]' specs/_index.md` → rows 20/25/26 read `Spec (planned)`, 21 `Spec`, 22-24 `Complete` (no ✅ on S20/S25/S26). | **complete, real commit + push evidence** |
| `GAP-072` — "P2, 2026-08-31, attempts=0" | `status: complete`, closed 2026-09-18 01:55:38 | `h3` `a14b346` (+ `17e810d`), `shim` `4d6dc64`; all three in their `origin/main`. PASS predicate re-run: the row's own stale-literal grep over its listed paths returns **0 hits**; `shim/src/h3_shim/test_battery.py:104 EXPECTED_TEST_COUNT = 46` == `h3/scripts/test-count.txt` (`46`); `make verify` count guard PASS. | **complete, real commit + push evidence** |
| `GAP-073` — "P2, 2026-08-31, attempts=0" | `status: complete` | cross-repo: `sdk-go` `c115c46`, `sdk-python` `7890683`, `sdk-typescript` `711eac5` — each listed by `git branch -r --contains` in its own repo → `origin/main`. `push:` + `pull_request:` triggers present in all three `.github/workflows/sync-protocol.yml`. Live: push-triggered `Sync Protocol` runs observed 2026-09-19 (sdk-go `35422509313` 04:53Z, `35424193418` 05:31Z, `35427159889` 06:38Z — all `success`). | **complete, real commit + push evidence**, with one named residual below |
| `DF-H3-1..5` — "filed 2026-09-01, pending" | all five `status: complete` (2026-09-18) | `edba372` (DF-H3-1 + DF-H3-2 co-closed, `h3`), `02f8f65` (`shim`, the row currently holding id `DF-H3-3`), `99d2c2b` (DF-H3-4, `h3`), `35e632a` (DF-H3-5, `h3`); every sha in `origin/main`. | **complete, real commit + push evidence** (one id-space caveat below) |

### Id-space caveats (why the id is not the finding)

- `DF-H3-3` at HEAD is the **2026-09-04 cycle slot** (`hermes-h3 install rejects --name`), not the
  09-01 slot; the board marks the archived cycle slots `duplicate` with a `dedupe_note` saying so
  (`QA-H3-12`, `QA-H3-13`, `DF-H3-18`, `DF-H3-19`, `DF-H3-20`, `DF-H3-21`, `DF-H3-22`).
- `GAP-069`'s surviving row is the `specs/_index.md` Status-column finding (same `created_at`
  2026-08-27T22:35:00Z as the claim quotes); its escalation note was replaced by the closure note
  on 2026-09-11. Nothing under that id is open.

## The audit's "zero gaps" wording, re-read

The row quotes a 2026-09-05-era note. Measured now:

- older desk audits (ticks #346-#349, `.coding-hermes/board/events.jsonl` ids 137-140) did read
  `zero gaps found, no new tasks created` with the pending rows named only in the same event's
  "No actionable pending rows" sentence;
- the current text (latest folded 12-point desk audit, tick #392, event id 319) reads
  `all PASS, zero new gaps; known-WARN carry-overs unchanged (DOGFOOD-01 P3-10 PYPI token,
  DOGFOOD-05 sdk-python-owned)` — i.e. the desk audit now names its carry-overs, and closed rows
  (e.g. `GAP-072`) are not silently re-opened.

So the *specific* contradiction the row was filed on — four P1/P2 item groups open for 4-8 days
while an audit reported zero gaps — is **stale**: all four groups are closed with pushed commit
evidence, and the audits now carry named carry-overs. What is **not** stale is the board-process
half, recorded below as named residuals.

## Residuals (live at this audit — owners named, none claimed fixed)

| Residual | Owner | Measured basis |
|---|---|---|
| **`attempts` is not a dispatch counter.** `attempts=0` appears on 110 rows and is absent on 89; only 6 rows reached `1`. `GAP-069` carried **21 tick events** in `.coding-hermes/board/events.jsonl` between 2026-09-01 and 2026-09-10 (dispatch/dry-run/rework cycles, event ids 152-173) plus `task_completed` id 174 — while `attempts` stayed `0` for the whole period. A future finding of the form "`attempts=0` ⇒ never dispatched" is therefore not measurable from this field; dispatch history lives in `events.jsonl`. | h3 board (row writes / schema semantics) | event ids 152-173 + 174 for `task_id=GAP-069`; attempts histogram above |
| **`QA-H3-2` (P3) still pending** — "battery silently reported no cells instead of failing loudly". The repo-owned half is now answered (`scripts/check-qa-target.sh` exits `1` on a bad target and names the contract; `0` on this repo — see below); the fleet-side QA-lane runner that produced the empty cell list has **not** been re-measured. | h3 umbrella tick / QA lane | `sh scripts/check-qa-target.sh /home/kara/h3` → `BAD_TARGET_EXIT=1`; `sh scripts/check-qa-target.sh` → `GOOD_TARGET_EXIT=0` |
| **`sdk-python` `Sync Protocol` is RED** — its two newest runs (`35355874386` 2026-09-18T14:22:59Z, `35387279417` 2026-09-18T19:40:46Z) both fail at the `Install uv` step, before the round-trip runs. The GAP-073 trigger fires (that is the point of the fix); the workflow body then aborts. | sdk-python lane (sibling repo) | `gh run view 35387279417 --repo get-h3/sdk-python --json jobs` → failing step `Install uv`, `Run round-trip verification` skipped |
| **Externally blocked P2 rows** (not dispatchable): `DOGFOOD-01` (`blocked_reason: P3-10 PYPI_API_TOKEN`), `DOGFOOD-05` (sdk-python-owned tracking placeholder), `SKIPPED-install-bunker` (host `bunker-las-03` offline; installability proven on the fallback host). | external credential / sdk-python / infra | rows at HEAD |
| **`LOGSEY-*/PULSE-*/LORE-*/DIGEST-*` (42 rows, P1/P2, filed 2026-09-17)** — pending by design, blocked on the human decision `LOGSEY-001` (repo home for the agent-ops line). | Bane decision (`LOGSEY-001`) | rows at HEAD; tick #392/#394 events |
| **`H3-GAP-084`** (foreign DuckBrain namespace store written into this public workdir), **`H3-GAP-086`** (sdk-go AGENTS.md snippet; write to AGENTS.md needs interactive approval), **`DF-H3PM-04` / `DF-H3PM-05`** (PM-lane board-path resolution; stale self-reported counts). | DuckBrain/SUPRA policy call; interactive approval; h3 PM-process (dispatchable) | rows at HEAD |

None of these is closed by this audit, and this audit makes **no** "zero gaps" claim.

## Reproduction (raw)

```bash
cd /home/kara/get-h3/h3
git log --oneline -1                                   # 16c76a8
python3 - <<'PY'                                       # parser over every line + histogram
import json, collections
rows=[json.loads(l) for l in open('.coding-hermes/board/tasks.jsonl') if l.strip()]
print(len(rows))
print(collections.Counter(r['status'] for r in rows))
print(collections.Counter(str(r.get('attempts','absent')) for r in rows))
PY
git show --stat --format='%H%n%s' 41e2cc0 a14b346 17e810d edba372 99d2c2b 35e632a
git branch -r --contains 41e2cc0                       # -> origin/main
git -C ../shim branch -r --contains 4d6dc64
git -C ../sdk-go branch -r --contains c115c46
git -C ../sdk-python branch -r --contains 7890683
git -C ../sdk-typescript branch -r --contains 711eac5
grep -n '^| 2[0-6]' specs/_index.md                    # GAP-069 predicate
grep -rn -E '44/44|44 tests|44 compliance|44-test|out of 43|43 protocol behaviors' \
  README.md AGENTS.md DEPLOY.md docs/integration.md docs/index.html docs/guide.html \
  docs/migration.html specs/05-Test-Battery.md specs/25-Conformance-Certification.md \
  docs/badge/compliant.svg                             # GAP-072 predicate -> no output
sh scripts/check-qa-target.sh /home/kara/h3; echo $?    # QA-H3-2 class -> 1
make verify                                            # ALL PASS, exit 0
```

Measured outputs at HEAD 16c76a8: parser `205` rows, `0` unparseable; every `git branch -r
--contains` above listed `origin/main`; the GAP-072 predicate printed nothing (exit 1 = no
matches); `check-qa-target.sh` on the phantom path exited `1`; `make verify` printed
`make verify: ALL PASS — umbrella repo is self-consistent`, exit `0`.
