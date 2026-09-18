# QA target contract — get-h3 umbrella

**Row:** `QA-H3-1` (P1) — "QA battery target repo does not exist — zero cells
recorded". This page is the repo-owned statement of the contract that row asks
for: *which* directory is the QA/verification target of this umbrella, *how* it
is resolved, and *why an empty result is never a pass*.

Applies to: QA cells, dogfood runs, fresh-install legs, CI jobs and any
script — in this repo or in a lane that drives it — that records a
pass/fail verdict **about the `h3` project**.

## 1. The rule

1. **The target of the `h3` project is this repository** — the `get-h3/h3`
   checkout. It is the umbrella's spec hub, board and integration-test home;
   `protocol`, `shim`, `sdk-go`, `sdk-python` and `sdk-typescript` are separate
   targets with their own boards and their own verdicts.
2. **Project names are not paths.** A row name (`h3`, `h3-qa`, `h3-dogfood`,
   `h3-pm`, `h3-umbrella-sync`) is not a directory. Resolve the checkout:
   * from the checkout itself — `git -C <checkout> rev-parse --show-toplevel`;
   * or from the scheduler row — `SELECT workdir FROM projects WHERE name='<project'>`
     in `~/.hermes/coding-hermes/scheduler.db`;
   * **never** by string-concatenating `/home/<user>/<project-name>`. That
     assumption is what produced this row: it yields `/home/kara/h3`, which
     does not exist, while the real checkout is `/home/kara/get-h3/h3`
     (`get-h3/<repo>` — the umbrella directory is part of the path).
3. **An empty / no-cell result is UNVERIFIED — never a pass.** A run that
   drove zero cells proved nothing about the code. It must be reported as
   UNVERIFIED (or as a finding about the runner), never as OK, CLEAN or green —
   in a report, a ledger, a board row or DuckBrain.
4. **A target that does not resolve fails loudly and non-zero**, before any
   cell is recorded. Silence is the failure mode this contract exists to kill.
5. **Absolute paths only where unavoidable.** Everything above is
   repository-relative or git-root-derived so it survives a rename, a move to
   another host, or a fresh clone. The one absolute path that is genuine on the
   fleet host is the canonical checkout `/home/kara/get-h3/h3` — and the
   retired `/home/kara/h3` is not a repo path at all.

Repo-relative forms preferred everywhere: `scripts/check-qa-target.sh` locates
its own repository from `$0`, so it works from any clone, at any path.

## 2. The pre-flight guard

```bash
sh scripts/check-qa-target.sh            # validate THIS checkout (no argument)
sh scripts/check-qa-target.sh <candidate>  # validate a candidate target directory
make verify-qa-target                    # same, as a make target (runs in `make verify`)
```

Exit codes (same convention as the sibling guards in `scripts/`):

| Code | Meaning |
|---|---|
| `0` | the target exists, is a git work tree, and is this repository |
| `1` | invalid target: missing / not a directory / not a git work tree / another repository (a `get-h3` sibling is called out by name) |
| `2` | the guard was misused (usage error) — nothing was validated |

It answers one question only — *is this a real h3 umbrella checkout?* — and is
meant to be run **before** cells are recorded, so a phantom path fails as a
phantom path instead of degrading into an empty, "clean" result. It does not
run any suite; `make verify`, `make verify-roundtrip` and
`h3-test --endpoint <harness>` are what measure the code.

## 3. Reproducible real-target verification

Run from anywhere; every command is self-contained and states its own expected
result.

```bash
# 1. the real checkout resolves, and the path is derived (not hardcoded)
git -C /home/kara/get-h3/h3 rev-parse --show-toplevel     # → /home/kara/get-h3/h3

# 2. the retired target really does not exist
test -d /home/kara/h3; echo $?                            # → 1

# 3. a phantom target fails loudly instead of reporting nothing
sh /home/kara/get-h3/h3/scripts/check-qa-target.sh /home/kara/h3; echo $?   # → 1

# 4. the real target validates
sh /home/kara/get-h3/h3/scripts/check-qa-target.sh; echo $?                 # → 0

# 5. the guard's own negative proof (fails closed on every invalid shape)
sh /home/kara/get-h3/h3/scripts/check-qa-target-selftest.sh; echo $?        # → 0, 11/11 PASSED

# 6. the repo's own consistency gates, from the resolved checkout
cd /home/kara/get-h3/h3 && make verify; echo $?           # → 0, "make verify: ALL PASS"
```

Step 3 is the whole finding in one command: the incident's target path,
evaluated by a repo-owned script, produces a **non-zero exit with a named
reason** — it can no longer be read as "nothing to report, therefore fine".

## 4. Scope: what this contract does and does not cover

**Covered here (repo-owned, executable):** target existence, target identity
(this repository, not a sibling), and the "empty ≠ green" rule as a
prerequisite any runner can enforce with one command.

**Not covered here — owned by the QA lane / pipeline:** the resolution that
produced the wrong path in the first place (`resolve_targets` in the QA
pipeline deriving `/home/<user>/<project-name>` in env mode) and the
degradation that turned a failed probe into `cells: [], status ok`
(`parse_cells`). Those are pipeline internals outside this repository, tracked
by the board rows for the target finding (`QA-H3-1`, this contract) and for the
silent-no-cells class (`QA-H3-2`). This page does not claim to have changed
them.

**Why there is no stronger repo-owned fix:** a guard that lives inside the
repository cannot be reached by a runner whose target path does not exist —
nothing repo-owned can run at a path that is not there. That is exactly why
rule 1.2 (resolve from the checkout or the scheduler row) is normative for lane
configuration, and why the guard's job is to make a *candidate* target fail
loudly for any runner that does hold one.

## 5. Incident record

| | |
|---|---|
| Filed | 2026-09-01 (`QA-H3-1`), re-filed 2026-09-03 (`QA-H3-10`) and 2026-09-05 (`QA-H3-11`) — same class, same wrong path, three cycles |
| Reported target | `/home/kara/h3` — `cd` failed, "No such file or directory" |
| Real checkout | `/home/kara/get-h3/h3` (`get-h3/h3`, umbrella repo) |
| Reported outcome | zero cells recorded; carried forward as if clean — no failing command could be captured because no cell ran |
| Repo-side evidence | `git grep -n '/home/kara/h3' -- . ':(exclude).coding-hermes'` → **no match.** No tracked script, `Makefile`, spec or doc ever contained that path, so no in-repo path edit could have fixed it; the missing artefact was the contract itself |
| Lane-side note | a QA-lane comment of 2026-09-18 (`events.jsonl` id 206) records that the then-current lane resolved the target correctly and drove cells, i.e. the original premise no longer reproduced; the row stayed open because nothing repo-owned stated the target contract, which is what this page adds |
| Sibling rows (not this one) | `QA-H3-2` — battery silently reports no cells instead of failing loudly; pipeline-side |

## 6. Verifying this page

The contract is only credible if it is re-runnable, so the checks of §3 are the
gate: `make verify` (which now includes `verify-qa-target`),
`make verify-qa-target-selftest` (the negative proof) and the commands of §3
themselves. If any of them stops passing, this page is stale — fix the guard
before trusting the rule.
