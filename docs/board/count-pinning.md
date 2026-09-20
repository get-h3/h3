# Count pinning in closure notes and PM ledger entries (DF-H3PM-05)

**Class:** a note, closure summary, or ledger title quotes a COUNT (`six of 188 rows`, `172 rows / 151
unique ids`) that was true when the note was written, and nothing says at which commit/date it was
measured. The number then ages on its own as later work lands — the product is fine, the note lies.
Filed by the dogfood cycle 2026-09-18 (h3-pm lane) as `DF-H3PM-05`; closed at h3 tick #412.

## The rule

**Pin every quoted count to its measurement commit or date, or recompute it at close.**

| Form | Verdict |
|---|---|
| `six of 188 rows carry it` | AGES — unverifiable next week |
| `at 838fd8c: six of 188 rows carry it` | PINNED — a verifier can check the commit out and count |
| `six of 188 rows at 838fd8c, 20 at the 2026-09-19 re-measure` | BEST — states the growth as growth, not drift |

Recompute-at-close is the alternative when the number is the point of the note (a repair count, a
row total). When the number is provenance (how many rows the repair touched), PIN the measurement
commit and name the current value separately — never silently swap one for the other.

## Why this bites harder on the h3 umbrella board

Umbrella rows routinely record work that landed in a SIBLING repo (`commit_repo`, H3-PM-003) and
sibling lanes keep landing more of it. So a count measured at repair time drifts monotonically while
every individual claim in the row stays true. The `H3-PM-003` repair measured **6 of 188** rows
carrying `commit_repo` at `838fd8c`; at tick #412 the board held **20** such rows — each from a
later, legitimate cross-repo closure. Nothing regressed; the note just aged.

## Applied at tick #412

| Store | Row | Before | After |
|---|---|---|---|
| `tasks.jsonl` | `H3-PM-003` | `six of 188 rows carry it` (worker_summary) | `at 838fd8c: six of 188 rows ... (re-measured 2026-09-19: 20 rows — later cross-repo closures, not drift of this repair)` |
| `tasks.jsonl` | `H3-PM-003` | — | `foreman_note` append: count-pin rationale |
| ledger `items` | `H3-PM-002` | `172 rows / 151 unique ids` (pre-repair figure) | `pre-repair 172 rows / 151 unique ids (2026-09-18 audit filing); post-repair 177 rows / 167 unique ids at d69409b (tick #354, verified)` |
| ledger `items` | `H3-PM-003` | `6 rows record a cross-repo commit_hash with no repo attribution` | same figure WITH the measurement commit + the 20-row re-measure |

## Verification

- `tasks.jsonl`: per-line edit, `git diff --numstat` = `1 1`; 208 of 209 lines byte-identical; the
  edited row re-parses with both the pin and the pinned figure present.
- ledger: `indent=1, ensure_ascii=True` is byte-exact for the file (proven on the pre-edit blob);
  after the edit `diff` shows exactly 2 changed lines (the two titles) and the item count is
  unchanged at 2236.
- Reviewer PASS form (from the row): *a verifier can tell from the row alone when the number was
  true, and the ledger entry matches the row's final numbers.*
