# Evidence repair — H3-PM-001

Forensic pass over the 12 board rows that the PM audit (`1cb4887`) flagged as `status=complete`
with an id that appears in no commit message in any of the six `get-h3` repos.

The audit's finding was a **false negative in 12/12 cases**: the work landed, but the commits name
ids in grouped/lowercase forms (`Addresses H3-GAP-017/018/019/020`, `Addresses dogfood-02/03/04`,
`closes H3-GAP-025/027/028`) or the row was never given a `commit_hash`. Every row below now
carries a pointer to a sha that resolves in a `get-h3` repo and that contains the artifact the row
claims.

- Board: `.coding-hermes/board/tasks.jsonl` — 171 rows before and after, 12 lines modified
  (`git diff --numstat` = `12 12`).
- Only `foreman_note` (appended, prefixed `evidence repair 2026-09-18:`), `commit_hash`, and
  `updated_at` changed on the 12 target rows. `status`, `priority`, `title`, `id` untouched.
- No row was reopened: nothing had to fall back to `pending`.

## Verdicts

| id | old status | verdict | evidence pointer / remaining work |
|---|---|---|---|
| DOGFOOD-02 | complete | **EVIDENCED** | `h3@674c54b` (Tick #180) — README quickstart + install repaired (source install, `hermes-h3`); `sdk-go` tag `v0.1.0` = `1cb84d0` (2026-08-02), present on origin (`refs/tags/v0.1.0`); `.gitreins/tasks.yaml` dogfood-02 flipped complete in the same commit |
| DOGFOOD-03 | complete | **EVIDENCED** | `h3@674c54b` — `specs/02-Protocol-Specification.md:186` (decision envelope / top-level `history`) + `specs/05-Test-Battery.md:69` (`Category 2: Process — Basic Flows (8 tests)`) |
| DOGFOOD-04 | complete | **EVIDENCED** | `h3@674c54b` — `README.md` quick-start drift fixed: `hermes-h3` binary, `h3-harness-go` dir, source install replacing dead `pip install hermes-h3-shim` / `hermes h3` |
| DOGFOOD-06 | complete | **EVIDENCED** | `h3@ff95ee9` (JSONL-NORM-001) — `.coding-hermes/board/tasks.jsonl` introduced as the canonical store (with `board.jsonl`/`events.jsonl`/`fixtures.jsonl`/`schema.sql`, 17 rows bootstrapped from legacy `tasks.md`) |
| H3-GAP-018 | complete | **EVIDENCED** | `h3@4caeaf8` — `README.md` + `CONTRIBUTING.md` `h3.sh` refs 3 → 0 (parent: README 1, CONTRIBUTING 2); `docs/{index,guide,protocol,sdk}.html` at 0 |
| H3-GAP-019 | complete | **EVIDENCED** | `h3@4caeaf8` — `CHANGELOG.md` gained the 2026-08 section (`git grep -c '2026-08' CHANGELOG.md` = 2 at that commit) |
| H3-GAP-020 | complete | **EVIDENCED** | `h3@4caeaf8` — `specs/08+09+10+26` code blocks: 0 bare `pip install hermes-h3-shim` lines (e.g. `specs/10-Website-Docs.md:65` → `git clone https://github.com/get-h3/shim && cd shim && pip install -e .`) |
| H3-GAP-022 *(null row)* | complete | **EVIDENCED** | `h3@bfa7766` (Tick #280) — `README.md:42` `cd h3-harness-go && go mod tidy && go run .` |
| H3-GAP-023 *(null row)* | complete | **EVIDENCED** | `h3@bfa7766` (Tick #280) — `specs/` hardcoded `/home/kara` refs 7 → 0 (parent: specs/02 ×3, specs/03 ×1, specs/05 ×1, specs/12 ×2) → portable `$HOME`/`~` |
| H3-GAP-024 *(null row)* | complete | **EVIDENCED** (negative-fact form) | `h3@bfa7766` (Tick #280) commit body records the orphan `h3-harness-scaffold/` removal; the dir was never git-tracked (0 scaffold paths in `git ls-tree -r bfa7766` and in HEAD) and is absent from the workspace root today — a filesystem-only deletion leaves no tracked delta, so absence is the evidence |
| H3-GAP-027 | complete | **EVIDENCED** | `h3@798c69a` (Tick #285, `6e63101`) — `skills/h3-usage/SKILL.md:97-99` reworded: `There are no published sdk-go tags` → `sdk-go v0.1.0+ is published, so go mod tidy fetches it — add a replace directive only for local SDK dev`; grep at HEAD = 0 |
| H3-GAP-028 | complete | **EVIDENCED** | `h3@798c69a` (Tick #285, `6e63101`) — `skills/h3-usage/SKILL.md` 43/43 → 44/44 in heading + prose, plus 41/43 → 41/44 and the 9/43 → 9/44 wrong-server example; `grep '43/43'` at HEAD = 0 |

### Duplicate-id handling

`H3-GAP-022`, `H3-GAP-023`, `H3-GAP-024` each appear **twice**. Only the row with
`commit_hash: null` (the legacy #280 rows, different titles) was edited; the `24bdbc9` rows
(closed at #304) were selected *by `commit_hash`, not by line order*, and are byte-identical to
their pre-edit state — verified by comparing pre/post parses and asserting the `24bdbc9` value is
still present 4× in the file.

## Method

Search by **content change**, not only by id:

```bash
# content-level archaeology
git -C /home/kara/get-h3/h3 log --oneline -S'<literal text>' -- <path>
git -C /home/kara/get-h3/h3 log --oneline --diff-filter=A -- .coding-hermes/board/tasks.jsonl
git -C /home/kara/get-h3/h3 show <sha> --stat
git -C /home/kara/get-h3/h3 grep -n -c '<literal>' <sha> -- <paths>
git -C /home/kara/get-h3/h3 cat-file -e <sha>^{commit}
```

- The 12 ids were **not** grepped as commit-message substrings beyond using the PM audit's own
  lead list; each lead was re-verified against the tree at the named sha (artifact present /
  artifact absent) rather than trusted.
- Every sha written into a row was confirmed with `git cat-file -e <sha>^{commit}`:
  `4caeaf8`, `bfa7766`, `674c54b`, `ff95ee9`, `798c69a` all resolve in `h3`. The one sibling-repo
  object cited (`sdk-go` `v0.1.0` → `1cb84d0`) resolves with `git cat-file -e 'v0.1.0^{commit}'`
  in `/home/kara/get-h3/sdk-go` and matches `refs/tags/v0.1.0` on `origin`.
- Board edit: a `/tmp` script (`json.loads`/`json.dumps` **per line**, separator style detected
  from each raw line and proven by a byte-for-byte roundtrip assertion before any mutation).
  Non-target lines were written back verbatim.
- Post-edit verification script: row count 171 → 171, every line parses, changed lines = 12, and
  for each changed line the parsed key-set difference is a subset of
  `{foreman_note, commit_hash, updated_at}`.

## Limits

- **H3-GAP-018 is only partially satisfied if the row's literal PASS criterion is read
  strictly.** The row's PASS was `grep -r 'h3\.sh' --include='*.md' --include='*.html' . | wc -l`
  = 0. That is **not** true: repo-wide matches went 24 files (parent) → 20 (at `4caeaf8`) → **8 at
  HEAD**, and the survivors are design text and historical artifacts
  (`specs/10-Website-Docs.md`, `specs/16-Observability-Structured-Logging.md`,
  `specs/18-Distributed-Tracing.md`, `CHANGELOG.md`, `prd.html`, plus the legacy board logs
  `.coding-hermes/tasks.md` and `board/{tasks,events}.jsonl`).
  The finding's named user-facing surface (`README.md`, `CONTRIBUTING.md`, the live `docs/*.html`)
  is fully clean, and the foreman note records the #258 review-class scope decision to keep spec
  design prose — so the row is evidenced for the defect it names, but a strict repo-wide zero was
  never achieved. Recorded in the row's `foreman_note`, not silently dropped.
- **H3-GAP-024's evidence is a negative fact.** The deleted directory lived at the *umbrella root*
  (`/home/kara/get-h3/h3-harness-scaffold`), outside the `h3` repo, and was untracked, so there is
  no tree delta to point at in any repo. The pointer is the commit body of `bfa7766` plus the
  absence checks (untracked at that commit and at HEAD; absent on disk today).
- **Commit-message id forms are ungreppable by exact id.** The grouped forms
  (`H3-GAP-017/018/019/020`, `dogfood-02/03/04`, `H3-GAP-025/027/028`) are why the original audit
  produced false negatives; a future audit should search content, or normalize ids before grepping.
- No row required reopening, so no `pending` rewrites and no `completed_at`/`worker_status`
  resets appear in this commit.
