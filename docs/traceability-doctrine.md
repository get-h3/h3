# Traceability doctrine — tracing a claim in this repo

**The public trace contract.** Work in this repository is traceable through four
links: a board row id, the commits that landed it, the judge verdict recorded for
it, and a CI run over the resulting tree. This page names the artifacts and gives
the exact commands that walk the chain. It is the public counterpart of the
fleet-internal trace doctrine; nothing here requires fleet access — a clone of
`get-h3/h3`, `jq`, `git` and the `gh` CLI are enough.

Snapshot: **verified 2026-11-25** on `main` at `de4af57`. Every command below was
run on that tree and returns on any clone; re-run them rather than trusting this
page.

## 1. The artifacts

| Link | Artifact | Published |
|------|----------|-----------|
| Row | `.coding-hermes/board/tasks.jsonl` — one JSON object per task row | yes (git-tracked) |
| Lifecycle + verdicts | `.coding-hermes/board/events.jsonl` — `task_created` / `task_dispatched` / `task_completed` events per row | yes (git-tracked) |
| Commits | `git log`; worker commit subjects end `Addresses <row-id>.` | yes |
| Judge verdict | recorded in the row's `task_completed` event (`judge_runs`, `judge`); raw run dirs under `.gitreins/history/<date>/<run-id>/` are judge-workspace-local and gitignored | verdict text yes, run dirs no |
| CI | GitHub Actions runs on `get-h3/h3` (`Deploy to GitHub Pages`, `H3 Cross-Language Round-Trip Verification`) | yes |

The board files are the canonical public record: a completed row's `commit_hash`
names the commit it closed at, and its `task_completed` event carries the judge
verdict for that commit.

## 2. The chain, step by step

### 2.1 Row → commit

```bash
jq 'select(.id=="DOC-31") | {id, status, priority, commit_hash}' \
  .coding-hermes/board/tasks.jsonl
```

A `complete` row carries `commit_hash`: the commit the row closed at (for a wave,
the wave tip). To find the individual commits that name the row:

```bash
git log --oneline --grep='DOC-31' | head -5
```

Worker commits end their subject with `Addresses <row-id>.`; landing merges read
`merge: wt/<row-id> — ...`; board closeouts read `board: ...`.

### 2.2 Commit → what changed

```bash
git show --stat 8384041
```

### 2.3 Verdict

Judge verdicts are recorded in the event log, bound to the row's commit:

```bash
jq -c 'select(.event_type=="task_completed") | .detail | fromjson?
      | select(.commit_hash=="a1bcb71af39bce2421c73bba1985a2d2bbdb056e"
               and .judge_runs!=null and .judge_runs[0]=="c19cb2bf")
      | {worker_commit, judge_runs, judge, tick_number}' \
  .coding-hermes/board/events.jsonl
```

The `judge_runs` ids are run-directory ids: a judge run writes
`verdict.json`, `summary.md` and patch files under
`.gitreins/history/<date>/<run-id>/` **in its own workspace**. That directory is
gitignored runtime residue, not part of the published repo — what ships publicly
is the verdict line quoted in the event. If you operate the judge yourself
(GitReins), the run id matches your local history dir to the recorded verdict.

### 2.4 CI run

```bash
gh run list --commit a1bcb71af39bce2421c73bba1985a2d2bbdb056e --limit 5
# from outside a clone, add -R get-h3/h3
```

A trace ends at the run whatever its outcome — a red run is part of the record,
not a reason to stop. This repo keeps its own CI failures on the board (see
`INT-CI-38` in `tasks.jsonl`).

## 3. Worked example — DOC-31 end to end

Row `DOC-31` (P4): "DEPLOY.md 'Harness API keys' documents only the
`H3_API_KEY` env path; the config `identity:` block ... is documented only in
the sibling shim repo". Walked on 2026-11-25:

1. **Row** — `jq` (2.1) returns `status: complete`,
   `commit_hash: a1bcb71af39bce2421c73bba1985a2d2bbdb056e` (the
   2026-11-25 wave tip).
2. **Commits** — `git log --grep` finds the worker commit `8384041`
   (`DEPLOY.md`, +19/−3, subject ends `Addresses DOC-31.`), its landing merge
   `34f5c1a` (`merge: wt/DOC-31 — ...`), and the board closeout `2207872`.
3. **Verdict** — the row's `task_completed` event carries
   `judge_runs: ["c19cb2bf", "a9bb41b6"]`, `judge: "PASS (both runs)"`,
   `tick_number: 575`, bound to `a1bcb71...`.
4. **CI** — `gh run list --commit a1bcb71...` returns run `45581396930`
   ("Deploy to GitHub Pages", completed **failure** — the Pages deploy failed on
   this commit; tracked as board row `INT-CI-38`).

Every hop resolves on a public clone: the two board files, the commits, and the
Actions run.

## 4. What is deliberately not published

- **Judge run directories** (`.gitreins/history/`) — workspace-local; the
  verdict text is the published record.
- **Fleet host paths, dashboards and credentials** — the board and events name
  rows, commits, run ids and workflow names only.

## 5. Re-running the local gates

The checks that gate docs and board changes here are `make` targets, runnable in
any clone:

```bash
make verify        # composite: docs, specs, counts, tags, json fences, board header
make verify-docs   # docs checks only
```

A row that claims a docs fix closed green should re-verify under these targets
at the commit the row names.
