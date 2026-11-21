# Evidence receipt — H3-OBS-05 re-close (arm A handoff + arms B/C re-proof)

- Tick: `h3-foreman-2026-11-21-12-58-06`
- Workdir: `/home/kara/get-h3/h3`
- HEAD during verification: `21ad736c885709843c092dc7b59ea44d71cd88da` (unchanged this tick — verification-only close; no code was modified)
- Row: `H3-OBS-05` — verify guard telemetry recorder (P1, lane monitoring), reopened at 12:29 on the premise that the arm-A handoff row did not exist

## Arm A — cross-repo half (the re-close condition)

The reopen premise was that `LORE-EXPORT-H3-GATE` was named but never filed. The handoff
**does** exist on the lore board under a different id:

```
$ cd /home/kara/get-h3/lore && grep -F '"LORE-EXPORT-1"' .coding-hermes/board/tasks.jsonl | jq -r '{id,status,created_by}'
{"id":"LORE-EXPORT-1","status":"complete","created_by":"h3-pm-2026-11-21-09-07-34"}
```

Implementation landed in the sibling checkout: `get-h3/lore` `eda0c96` (feat(gate): export gate
runs as Prometheus textfile), judged PASS in run `d46cce23`
(`.gitreins/history/2026-11-21/d46cce23/summary.md`).

Live host proof taken this tick (the artifact was absent before, because no gate run had
executed on this box since the exporter landed):

```
$ cd /home/kara/get-h3/lore && .venv/bin/python -m lore gate --decision no-new-lesson --reason "h3-foreman tick h3-foreman-2026-11-21-12-58-06 arm-A cross-check"
GATE: ALLOW (no-new-lesson)          # exit 0
$ cat /var/lib/node_exporter/textfile/h3_lore.prom
lore_gate_runs_total 1
lore_gate_last_success 1
$ .venv/bin/python -m lore gate --decision no-new-lesson --reason "h3-foreman arm-A counter increment probe"   # exit 0
lore_gate_runs_total 2
lore_gate_last_success 1
```

Counter increments (1 → 2), verdict series present, atomic textfile in the node_exporter
directory — arm A is live, and its tracker row is closed with a judge on the lore board.

## Arm B — telemetry file carries the nine guards

```
$ grep -c '^h3_verify_guard_result' /var/lib/node_exporter/textfile/h3_verify.prom
9
$ grep '^h3_verify_guard_result' /var/lib/node_exporter/textfile/h3_verify.prom
h3_verify_guard_result{guard="verify-docs"} 1
h3_verify_guard_result{guard="verify-specs"} 1
h3_verify_guard_result{guard="verify-count"} 1
h3_verify_guard_result{guard="verify-tags"} 1
h3_verify_guard_result{guard="verify-json-fences"} 1
h3_verify_guard_result{guard="verify-qa-target"} 1
h3_verify_guard_result{guard="verify-tick-chain"} 1
h3_verify_guard_result{guard="verify-board-header"} 1
h3_verify_guard_result{guard="verify-commit-msg"} 1
h3_verify_runs_total{target="verify"} 25
```

## Arm C — gauge follows the verdict (break → restore, re-executed this tick)

Scratch copy of HEAD, so the working tree of the real checkout was never touched:

```
$ cd /home/kara/get-h3/h3 && git worktree add -q --detach /home/kara/.hermes/cache/scratch/h3-armc-081645 HEAD
$ cd /home/kara/.hermes/cache/scratch/h3-armc-081645 && printf '47\n' > scripts/test-count.txt
$ make verify                     # declared 47 vs authoritative 48
FAIL: specs/05 category list sums to 48, but the canonical compliance-test count is 47.
make[1]: *** [Makefile:409: verify-count] Error 1
EXIT=2
$ grep '^h3_verify_guard_result{guard="verify-count"}' /var/lib/node_exporter/textfile/h3_verify.prom
h3_verify_guard_result{guard="verify-count"} 0
$ h3_verify_runs_total{target="verify"} 24
```

Restore in the same scratch copy:

```
$ git checkout -- scripts/test-count.txt && cat scripts/test-count.txt
48
$ make verify
make verify: verdict census PASS
make verify: ALL PASS — umbrella repo is self-consistent
EXIT=0
$ grep '^h3_verify_guard_result{guard="verify-count"}' /var/lib/node_exporter/textfile/h3_verify.prom
h3_verify_guard_result{guard="verify-count"} 1
$ h3_verify_runs_total{target="verify"} 25
```

So a failing guard is observable as `0` plus a non-zero exit, and the passing state returns
the same gauge to `1` — the recorder never reports a verdict the run did not make.
(The same break/restore proof was first recorded by the 09:02 tick, judge run `71e09b6a`
item `record-follows-verdict`; this tick re-executed it against the current HEAD.)

## Scope / non-claims

- No source file changed in this tick; the scratch worktree is detached at HEAD under
  `~/.hermes/cache/scratch/h3-armc-081645`.
- Arm A's producer code lives in `get-h3/lore`, not here; this receipt claims only that the
  handoff row exists, is closed with judge `d46cce23`, and that the artifact is live on this host.
