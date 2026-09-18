# Cross-repo commit provenance — H3-PM-003

The umbrella board (`.coding-hermes/board/tasks.jsonl`) records work that landed in the
six sibling `get-h3` repos, but a row only carried `commit_hash` — no field saying *which*
repo. A verifier holding a row therefore had to sweep all six repos to resolve the sha, and
a hash that does not resolve in the repo it looks like it belongs to is indistinguishable
from a fabricated one.

`commit_repo` closes that gap: the hash now names its repo.

## The field

```sql
    commit_hash       VARCHAR,
    commit_repo       VARCHAR,
```

- Location: `.coding-hermes/board/schema.sql`, `tasks` table, declared directly after
  `commit_hash` (same `VARCHAR` / nullable convention as its neighbours — no default, no
  constraint, no migration).
- Value: the umbrella directory name of the repo that contains the commit —
  `shim`, `protocol`, `sdk-go`, `sdk-python`, `sdk-typescript` (the `h3` umbrella itself is
  the implicit home repo).
- `NULL` (or absent) means *unattributed*: either the commit is in this repo or the row was
  never given a repo. Nullable on purpose — 53 of the 59 rows that carry a `commit_hash`
  predate this field and are **not** backfilled by this change.
- Read path only: the JSONL store is additive, so rows without the key are unaffected and
  `boardctl` passes the value through (`boardctl show DOGFOOD-07` prints `"commit_repo": "shim"`).
  No writer/validator vocabulary change; no row was reserialized.

## Backfilled rows (6 of 6)

Every row below records a commit that landed in `get-h3/shim` (the shim plugin repo: scaffold
templates, CLI, CI). All six hashes were resolved with
`git -C ../shim cat-file -e <hash>^{commit}` at the time of the change:

| id | commit_hash | commit_repo | commit subject |
|---|---|---|---|
| DOGFOOD-07 | `5f665e5` | `shim` | `fix(templates): bump go scaffold sdk-go dep to v0.1.1 …` |
| DOGFOOD-08 | `ba2b074` | `shim` | `fix(templates): py scaffold cancel 404s on unknown session …` |
| DOGFOOD-09 | `6214248` | `shim` | `fix(templates): ts scaffold dep -> github:get-h3/sdk-typescript …` |
| DOGFOOD-10 | `8568cb3` | `shim` | `ci: add scaffold-compliance gate …` |
| DOGFOOD-11 | `4bac7d2` | `shim` | `fix(cli): verify accepts optional positional NAME …` |
| GAP-064 | `141f140` | `shim` | `fix: bump scaffold Go template sdk-go pin v0.1.1 -> v0.1.4 …` |

Resolving a board row's evidence is now two commands, no sweep:

```sh
grep '"id":"DOGFOOD-07"' .coding-hermes/board/tasks.jsonl   # -> commit_hash, commit_repo
git -C ../shim cat-file -e '5f665e5^{commit}' && echo OK
```

## How this was applied and verified

The six rows had to be selected by `(id, commit_hash)`, not by line order or by `id` alone:
the board carries duplicate cycle-slot ids (`QA-H3-*`, `DF-H3-*`, `H3-GAP-022/023/024`) and
untouched lines must stay byte-identical, so `boardctl update` (which rewrites a row from a
parsed dict) was not used. Each target line received one 21-byte token
`,"commit_repo":"shim"` immediately after its `"commit_hash":"<sha>"`, leaving the rest of
the line — key order, escaping, spacing — exactly as serialized.

Script-based verification (this repo declares `tests: false` in `.gitreins/config.yaml`; the
change is DDL + board data, so there is no test harness to extend):

```sh
# snapshot raw lines before editing
python3 /tmp/h3pm003-snapshot.py    # -> /tmp/h3pm003-before.jsonl + sha256 + target line map
python3 /tmp/h3pm003-apply.py       # surgical insert, asserts one needle per target line
python3 /tmp/h3pm003-verify.py      # before/after line-level assertions
```

`verify` asserts: the change set is exactly lines 65, 66, 67, 68, 69 (DOGFOOD-07..11) and 81
(GAP-064); the other 182 lines are byte-identical to the snapshot; each changed line is the
old line plus a single insertion placed adjacent to its `commit_hash`; the parsed row gained
only `commit_repo` and kept every other key/value (including `status`); and exactly six rows
in the 188-row board carry `commit_repo="shim"` — no duplicate-id sibling picked one up.

Gates run before the commit: `make verify` (docs-link, spec-index, test-count, commit-message
skip-directive guard) — all pass; `git -C ../shim cat-file -e <hash>^{commit}` for all six
hashes — all resolve; `boardctl validate` — unchanged baseline (23 errors / 11 warnings, all
inherited duplicate-id / `status=duplicate` / free-form legacy-field / id-less-event debt that
this task deliberately does not touch).
