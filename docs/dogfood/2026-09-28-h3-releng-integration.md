# Dogfood Integration Report — h3-releng release-readiness sweep (2026-09-28)

Lane: `h3-releng` — the release-engineering satellite for `get-h3/h3`. This run
USED the lane for real: one full readiness sweep at origin/main `3864dbb`, plus
the ephemeral-bunker install leg (which yesterday's run skipped — the host was
offline then; today's fresh probe found it back).

## What the lane promises

The lane's own contract (scheduler prompt): "Run the readiness sweep daily:
inventory since the last release artifact, version hygiene, CI truth on HEAD
(cite run ids), deployed-binary staleness, open blockers. You VERIFY — you do
not develop; findings become RELEASE-* rows for the foreman."

Promise under test: *a user (the release operator) can learn, in minutes,
whether get-h3/h3 is cuttable today, with every load-bearing number
re-derivable, and the release driver itself refusing an unfit cut.*

## The sweep, executed end to end (numbers)

1. **Inventory since last artifact** — v0.2.0 cut 2026-09-20 (tag + GitHub
   Release object verified live). HEAD `3864dbb` is 169 commits past v0.2.0
   (3 feat, 8 fix, 0 BREAKING → MINOR, matching pending RELEASE-H3-006's
   v0.3.0 authorization, whose range has since grown).
2. **Re-derive the blockers at HEAD** — scratch worktree at origin/main,
   `make verify`: rc=2 at `verify-tick-chain` (hole `/tick/500`), then
   `verify-board-header` alone: check-A FAIL (last_commit `76abd74` is neither
   HEAD nor parent) + check-B FAIL (ticks_total 502 vs max event tick 503).
   Both pending P1 rows (RELEASE-H3-007/008) re-derive TRUE at the newest HEAD.
   Independent census walker against the raw DuckBrain tree API agrees:
   `/tick/498` present, `/tick/500` absent, `/tick/501` present.
3. **Tick-500 corroboration** — the event log carries tick-500's own close-out
   (event id 650): worker commit pushed, CI success, and the literal words
   "GitReins Tier 2 INCOMPLETE due existing stale header and DuckBrain tick-500
   hole". The hole was known at write time and survived the tick.
4. **Release-driver dry-run** — `bash scripts/release.sh` (720 lines,
   dry-run default): refuses correctly, rc=1, "Nothing was tagged". The driver
   double-checks the gate (exit code AND the literal `make verify: ALL PASS`
   line) and runs under `set -euo pipefail`. Honest refusal is the product
   working — blocked-but-truthful beats green-but-wrong.
5. **CI truth on HEAD** — newest run 36340855717 (pages, success) is on
   `76abd74` = HEAD's parent+1, not HEAD; roundtrip last dispatched 09-23. No
   run on the candidate SHA; the driver's own "--verify-ci" dispatch path is
   the designed remedy (dispatch, assert per-job/per-step, cite ids).
6. **Freshness census** — PyPI `hermes-h3-shim` latest 0.1.0 (single release)
   while the umbrella sits at v0.2.0 → 8+ days stale; umbrella RELEASE-H3-003
   ("no release to push") premise expired.

## The bunker install leg (EXECUTED — supersedes DF-H3-40's skip)

Probe-first found `bunker-las-03` back ONLINE (yesterday: ssh timeout). Then:

- `bunker spawn --ttl 2h` → agent `2b5b2980` (rootless Docker host, bare
  Debian user: python 3.13.5, make 4.4.1, jq 1.7 preinstalled).
- **Clone**: public HTTPS `https://github.com/get-h3/h3.git` inside the agent
  → HEAD `3864dbb`. A fresh user can fetch the repo; no credentials touched,
  no visibility changed (Bane hard rule).
- **Leg A — documented install path from scratch** (`make verify`, the repo's
  own fresh-clone gate): **1 second**, rc=2. Five guards PASS (docs-link,
  spec-index, test-count, json-fences, qa-target); the two DuckBrain guards
  print honest UNVERIFIED (no token on a bare box); `verify-board-header`
  FAILS check-A + check-B with the `PUBLIC-HEAD-VERIFY-FAIL` alert. The
  fresh-clone smoke failure IS the release blocker set — the install leg
  doubles as a clean-machine release-readiness probe.
- **Leg B — armed run**: token staged via /tmp + remote `install -m 600`
  (never in notes/artifacts), DuckBrain reverse-forwarded
  (`ssh -R 3000:localhost:3000`): rc=2 with the `/tick/500` hole verdict
  through the guard's live HTTP path; the independent tree-census walker FAILs
  with the same verdict (two readers, one tree, one answer).
- **Cleanup**: agent destroyed, local key removed, tunnel closed, staged token
  shredded. Sibling agent `04ccef2d` untouched.
- install_seconds=1 (verify) / ~5s (clone). Friction of the leg itself: zero
  beyond the token staging gate dance (surface-imposed, not project-imposed).

## Verdict — per surface

- **Sweep machinery (the lane's own surface): ✅ SHIPPABLE** — every claim in
  the pending RELEASE rows re-derived TRUE at the newest HEAD; the driver
  refuses an unfit cut; the guards' UNVERIFIED-vs-FAIL vocabulary is honest
  at target level; the fresh-clone alert block tells the operator exactly
  what to run (`make board-close`) and why.
- **The release it gates: 🔴 BLOCKED (NO CUT)** — same two defect classes for
  3 consecutive sweeps: the tick-key write path (recurrence #4) and the
  skipped board-close in the board-writing closeout (2 consecutive commits).

## Time-to-first-success and friction

TTFS 6 min (scratch worktree + `make verify` reproduced both P1 blockers).
Friction count 4 (the four filed rows; the strongest is the composite-gate
UNVERIFIED leak — an operator on a substrate-unreachable host gets a green
gate over an unchecked chain).

## What we left behind

Board rows DF-H3-41..43 (this repo's board) + cross-evidence notes on
RELEASE-H3-007/008, `skills/h3-usage/SKILL.md`
release-sweep section, `docs/dogfood/diagnostics.md` E20, this report, and
the dogfood-log run-11 entry.
