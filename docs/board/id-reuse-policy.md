# Board id-reuse policy

**Scope:** `.coding-hermes/board/tasks.jsonl` (JSONL-canonical board) in every `get-h3` repo.
**Status:** binding for all board writers — foremen, PM cycles, QA/dogfood lanes, workers.

## The rule: **one id, one finding**

An id is assigned to exactly one finding, once. After an id has been used — regardless of whether
the row is `pending`, `complete`, `duplicate` or `blocked` — it may **never** be reused to file a
new, different finding. A `complete` id that is reused makes brand-new work read as already closed:
the row count grows while the "open work" view shrinks, and the audit trail is lost.

Corollaries:

- **Never edit a closed row to describe new work.** File a new row with a new id.
- **Never delete or merge rows** to fix a collision. Re-id the offending row and leave both rows in
  place, one finding each.
- A re-id is recorded on the row itself with `foreman_note_append` naming the old id, the tick, and
  the evidence commit, plus `updated_at`.

### New findings: take the next free number in the family

At **write time**, a new finding receives the next free number in its family — `H3-GAP-<n>` for
gaps, `DF-H3-<n>` for dogfood, `QA-H3-<n>` for QA, `H3-PM-<n>` for PM-process rows. "Free" means
*not present anywhere in the file*, computed by parsing the board (a `grep` is not proof: ids also
appear in `title`, `detail` and `reasoning`). If the intended number is taken, take the next one up
and say so in the commit message — never overwrite the existing row, and never append `-b`.

## The exception: QA/DF **cycle-slot** ids

`QA-H3-<n>` and `DF-H3-<n>` are **per-cycle slots**, not finding identifiers. Cycle 1 of the QA
lanes writes `QA-H3-1..5`; cycle 2 writes `QA-H3-1..5` again; a third cycle repeats them once more.
The same is true for the dogfood lane's `DF-H3-<n>`. Two to three rows therefore carry the same id
**by design**, and that is not a violation of "one id, one finding" — the slot identifies the
*position in a cycle*, and the finding is identified by its content.

It is safe because **dedupe is done by content fingerprint, never by id**:

- the fingerprint is the normalized title (severity tag `[P1]` / `[dogfood:P2]` stripped, paths and
  shas dropped, lower-cased, punctuation collapsed to spaces) compared as a token set; a pair with
  ≥ 0.8 similarity is the same finding re-filed in a later cycle;
- a row that duplicates an earlier row of its own slot carries
  `superseded_by: "<canonical id>"` and
  `dedupe_note: "cycle-slot duplicate of the earlier row with this id — kept for cycle provenance"`;
  duplicates are additionally marked `status: "duplicate"` by the PM dedupe pass, with
  `superseded_by` naming the canonical row — which may live in another family (`GAP-072` for the
  battery/test-count drift class) when the canonical finding is the board row, not the slot;
- a row that holds a genuinely different finding in a reused slot carries
  `dedupe_note: "cycle-slot id reuse by design; distinct finding"` and is left otherwise untouched.

Rules for the cycle lanes:

1. **Do not renumber** cycle-slot rows, and do not re-id a distinct finding off a cycle slot just
   because the number repeats — annotate it.
2. A finding that graduates out of the cycle pattern (it becomes standing work) gets a fresh unique
   id (e.g. `QA-H3-8`, `DF-H3-12`) and leaves the cycle slot behind.
3. Any consumer counting "unique ids" as "unique findings" is wrong: dedupe on the fingerprint.

## Worked example — `H3-GAP-021..024` (repaired in H3-PM-002, tick #354)

The legacy rows `H3-GAP-021..024` were closed at tick #280 by `bfa7766`:

| id | finding closed by `bfa7766` |
|---|---|
| H3-GAP-021 | battery-count drift 43 vs 44 (`TOTAL 43/43` → `44/44`) |
| H3-GAP-022 | README quickstart omits `go mod tidy` |
| H3-GAP-023 | specs embed hardcoded `/home/kara` paths |
| H3-GAP-024 | orphan `h3-harness-scaffold/` directory |

A later PM cycle then re-used those four ids for **new** findings, closed by `24bdbc9`
(`fix(h3): GAP-021..024 — sweep coding-herms typo org (specs/01,03,04,05), pin sdk-go @v0.1.1, TS
github: install caveat, PyPI status in h3-usage skill`). Each new finding now has its own id:

| old (reused) id | new id | finding (evidence `24bdbc9`) |
|---|---|---|
| H3-GAP-021 | **H3-GAP-075** | specs 03/04 point installers at a phantom org `coding-herms` |
| H3-GAP-022 | **H3-GAP-076** | `skills/h3-usage/SKILL.md` claims sdk-python "also not on PyPI" — stale |
| H3-GAP-023 | **H3-GAP-077** | specs/03 npm/bun install commands carry no unpublished-package caveat |
| H3-GAP-024 | **H3-GAP-078** | specs/03:131 `go get …@v1.0.0` names a tag that does not exist |

The four original `bfa7766` rows were left in place (one row each), `commit_hash: 24bdbc9` is
retained on all four re-id'd rows, and the `H3-GAP-021` battery-drift row — which had
`commit_hash: null` although `bfa7766`'s message names "battery-count drift 44/44" — was
back-filled with `commit_hash: bfa7766`. Result: 4 id collisions removed, 0 rows deleted.

## Fields

| field | meaning |
|---|---|
| `foreman_note_append` | re-id audit line: old id, tick, why, evidence commit |
| `superseded_by` | canonical id of the finding this row duplicates (same family for cycle slots, any family when the PM dedupe pass folded it into a standing row) |
| `dedupe_note` | `cycle-slot duplicate …` or `cycle-slot id reuse by design; distinct finding` |
| `updated_at` | UTC timestamp of the last write to the row |

Board writers must add keys without removing or reordering existing ones, and must write the file
line by line (parse + re-serialize each line with its own separator style) so untouched rows stay
byte-identical.
