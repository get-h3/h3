# GAP-075: load hygiene — process spawns in the umbrella gate battery

Status: verified. One file changed: `scripts/check-json-fences.sh`.

## Class and directive

Fleet load-hygiene directive (Bane, criterion 7 of the 2026-09-19 retirement loop): one or two
projects must not be able to consume the whole box's CPU / L3. GAP-075 is the in-repo arm of that
directive: bound the number of processes this repo's own verification ladder spawns.

The offender is not a test suite — this repo has none of its own. It is `make verify`'s
`json-fences` stage. Its per-block form started one interpreter **per ```` ```json ```` fenced
block**: 65 blocks, 65 `python3` processes. It was the only member of the gate battery that fired a
subprocess per artifact, and it dominated the ladder's wall clock.

Sibling repos are out of scope here; their suites are measured by their own foremen.

## Method

Process count, by tracing every `execve` and classifying by binary:

```sh
strace -f -e trace=execve -o /tmp/gap075_after.txt sh scripts/check-json-fences.sh
grep -c 'execve(' /tmp/gap075_after.txt                       # total execve lines
grep -c 'execve(".*python3' /tmp/gap075_after.txt             # python3 starts
grep -o 'execve("[^"]*"' /tmp/gap075_after.txt \
  | sed 's|execve("||;s|"$||' | xargs -n1 basename | sort | uniq -c | sort -rn
```

Wall clock and peak RSS, via `/usr/bin/time -f "wall %e s maxrss %M KB"`, run three times.

Both figures were taken on the same host in the same session, at `af8affa` (before) and at the
GAP-075 commit (after). Absolute wall times move with box load; the process counts do not.

## BEFORE

`strace` totals: **104 execve lines, 65 of them `python3`** — one interpreter per ```` ```json ````
block. The remainder was the extraction/plumbing set:

```text
65 python3     16 sed     4 tail     4 head     4 grep     2 rm     2 git
 2 cat          1 sort     1 sh       1 mkdir    1 dirname  1 awk
```

Wall clock, three runs: **2.90 s / 2.82 s / 2.90 s** (`maxrss` ~16.0 MB).
`make verify` (all six checks as the gate stood at this measurement — it carries seven
since H3-GAP-098 added `verify-tick-chain`): **2.23 s**, `maxrss` 16.0 MB.

For reference, the foreman's audit of this same command on this same host earlier in the tick
measured 1.49 s / 1.53 s / 1.49 s with the identical 104 / 65 spawn counts. The spawn counts agree
exactly; the wall-clock gap is box load at measurement time, which is why both numbers are recorded
rather than one.

The other guards in the ladder are already cheap and were not touched: `check-qa-target` 0.00 s,
`check-ci-skip-tokens` 0.01 s, `check-test-count` 0.10 s, `check-qa-target-selftest` 0.12 s.

## AFTER

`strace` totals: **23 execve lines, 1 of them `python3`** — one interpreter for the whole run.

```text
4 sed     4 grep     3 cat     2 rm     2 git     1 wc     1 tr
1 sort    1 sh       1 python3 1 mkdir  1 dirname 1 awk
```

Wall clock, three runs: **0.08 s / 0.09 s / 0.09 s** (`maxrss` ~17.0 MB).

So: **65 python3 starts -> 1** (-64), **104 execve lines -> 23** (-81). The residual `sed`/`grep`
spawns are the per-failure placeholder-token lookups, which only run for the handful of blocks that
actually fail; the `cat`/`mkdir`/`rm`/`dirname`/`git`/`sort`/`awk` lines are the existing
extraction plumbing, unchanged in count.

`maxrss` is ~1 MB higher because the single interpreter holds the job list and each payload in
turn, where the per-block form paid the same per process. That is a flat cost, not a per-block one,
and it is well inside the previous per-process figure.

How the batch works: the manifest is walked once to count blocks and write a job list (one payload
path per block, in manifest order); then ONE `python3 "$TMP/validate.py" "$TMP/jobs.txt"` runs the
canonical `json.load` over every payload in that list. The engine echoes each job's own fields back
on its result line, so per-block attribution — file, absolute line, inner line — is preserved by
construction. The shell keeps its existing reporting and its existing absolute-line arithmetic
(`FAILLINE = open_line + inner_line`).

## What did NOT change

* **Blocks scanned: 65.** Same discovery (`git ls-files` over `README.md`, `specs/*.md`,
  `docs/*.md`, `docs/**/*.md`), same extraction, same block count.
* **Allowed count: 4** (the deliberately abbreviated payloads), and the same four
  `ALLOWED (abbreviated) <file>:<line>` lines.
* **Zero failures**, and the guard's full stdout+stderr is **byte-identical** to the pre-change
  guard's (`diff` of the two runs is empty).
* **Engine semantics: unchanged.** `json.load` over the same payload text, and the same failure
  derivation (last non-blank traceback line, `line N` pulled out of it, exception-class prefix
  stripped). Nothing is cached, time-boxed or skipped.
* **`--self-test`: PASS** — clean PASS, abbreviated ALLOWED, unterminated string FAIL.
* **Exit-code contract: unchanged** — 0 pass (or a loud skip), 1 at least one block failed,
  2 guard misconfigured.
* **The structural awk fallback: correct, and now also batched** (one `awk` for the whole run).
  A python3-less `PATH` was used to drive it over the real repo and over fixtures: the block counts,
  failure counts, file:line attribution and all three message classes (`unterminated string`,
  `unexpected closing bracket '}'`, `unbalanced braces/brackets (depth N)`) are identical to the
  pre-change guard's, `structural: ` prefix included.
* **The structural awk fallback's limitation is unchanged** — it cannot see the four abbreviated
  blocks that `json.load` rejects, so on a python3-less host it reports `65 scanned, 0 allowed,
  0 failures`, exactly as it did before. That is the documented floor, not a regression.

One new behaviour, deliberate: the batch is all-or-nothing. If the engine exits non-zero, or returns
a result count that disagrees with the block count, the guard exits **2** with a loud line rather
than reporting a short run as a pass. The per-block form had no equivalent check.

## Limits

* No CPU or load-average claim is made here. The measurement is process count plus wall clock on
  one shared host; wall clock is load-sensitive and the two before/after wall figures were taken
  under different background load.
* The 65 -> 1 reduction bounds *this* guard's spawns. It says nothing about the SDK repos, the
  round-trip suite (`make verify-roundtrip`, different target, needs sibling checkouts), or any
  other project on the box.
* `maxrss` is per-process peak, not aggregate; it is reported because `/usr/bin/time` gives it, not
  because it is a load-hygiene metric.
* `--self-test` on a host with **no python3** still reports FAIL: the structural fallback cannot
  detect the deliberately abbreviated fixture, so the self-test's "abbreviated block was reported
  ALLOWED" assertion cannot hold there. This is pre-existing and unchanged — the pre-change guard
  fails the same assertion on the same python3-less `PATH`.
* The batch is one process, so a crash inside the engine ends the whole run instead of one block.
  That failure mode is caught loudly by the result-count check (exit 2), not silently degraded.
