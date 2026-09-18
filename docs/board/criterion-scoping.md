# Board criterion scoping — the self-quote class

**Scope:** every PASS/acceptance criterion written into `.coding-hermes/board/tasks.jsonl` rows, plus the gitreins and PM-lane criteria that quote them, across all `get-h3` repos.
**Status:** binding for all board writers — foremen, PM cycles, QA and dogfood lanes, workers.

## The rule

Rule: scope every board PASS criterion so the check cannot match the artifacts that quote it

A criterion is a command a verifier re-runs on the row's own commit in the row's own tree. If the
command's search space contains the stores that hold the criterion, the criterion measures itself
and can never reach zero. The class is not about a wrong command — `grep -rn` over the repo root is
exactly right for a sweep — it is about command and search space being chosen together.

Corollaries:

- **Name the surface under test.** A criterion is scoped by path, by file type, or by a build or
  serve artifact. Never by the repository root.
- **A repo-wide text search is only valid when the searched string cannot appear in bookkeeping.**
  The board row, its closure events, the judge verdict, the dogfood report and the skill doc all
  quote the criterion verbatim; any one of them is enough to make a `== 0 hits` criterion
  unsatisfiable.
- **Prefer the strongest non-textual proof available** (compile, vet, health check). Bookkeeping
  cannot pollute a build.
- **Quote the command that was actually run**, with the scope it was run at. A row whose
  `review_notes` quotes a repo-root search while the fix was verified file-scoped has lost the
  evidence for its own claim.

## Why: the H3-PM-006 case

Row `H3-PM-006` closed a real defect: `DEPLOY.md`'s "Option B: Manual (use SDK directly)" Go snippet
did not compile — it used `protocol.EndResult`, which appears in no Go source in any `get-h3` repo,
implemented 2 of the 5 `harness.Harness` methods, and omitted `decision_id`. The fix is real
(commit `312469b`: real `protocol.End{Reason, Summary}`, all five `Harness` methods, `DecisionID`
on every `Decision`).

The row recorded its PASS criterion as:

```
grep -rn "EndResult" /home/kara/get-h3/h3 == 0 hits
```

That criterion can never pass, because the string it searches for appears in the artifacts that
record the search. Measurement taken at HEAD `19c9f7e`, before this file existed:

```bash
cd /home/kara/get-h3/h3 && grep -rn "EndResult" . 2>/dev/null | awk -F: '{print $1}' | sort | uniq -c | sort -rn
```

```
      5 ./docs/dogfood/h3-pm-diagnostics.md
      5 ./.gitreins/history/2026-09-18/f791143b/verdict.json
      3 ./.coding-hermes/board/events.jsonl
      2 ./skills/h3-pm-usage/SKILL.md
      2 ./.gitreins/history/2026-09-18/f791143b/summary.md
      2 ./.coding-hermes/board/tasks.jsonl
      1 ./docs/dogfood/2026-09-18-h3-pm-integration.md
      1 ./.gitreins/tasks.yaml
```

Total: **21 hits** across four classes.

| class | files | hits |
|---|---|---|
| board rows + closure events (`.coding-hermes/`) | `board/tasks.jsonl` (2), `board/events.jsonl` (3) | 5 |
| judge artifacts (`.gitreins/history` + `.gitreins/tasks.yaml`) | `history/2026-09-18/f791143b/verdict.json` (5), `…/summary.md` (2), `tasks.yaml` (1) | 8 |
| dated dogfood reports (`docs/dogfood/`) | `h3-pm-diagnostics.md` (5), `2026-09-18-h3-pm-integration.md` (1) | 6 |
| agent skill docs (`skills/*/SKILL.md`) | `h3-pm-usage/SKILL.md` (2) | 2 |

**`DEPLOY.md` itself has 0 hits.** The file-scoped check the criterion should have used is clean:

```bash
grep -n "EndResult" DEPLOY.md    # no output, exit 1
```

So the fix is real and only the criterion was broken. The 21 hits are not defects: the board row and
its closure events must quote the criterion they close, the judge verdict must quote what it scored,
and the dogfood report and skill doc exist to teach this exact case. A criterion that forbids them
is a criterion that forbids its own audit trail.

**This document is in the class too.** The criterion is decided by the search space, not by how
carefully the artifacts are written, so the doc that names the class joins it: with this file
present the same command reports **28 hits**, this file contributing **7** of them (the quoted
criterion, the reproduction command, and the examples above) — which is the whole point. Nothing
here is wrong; a tree-scoped count is simply the wrong instrument.

## The rule in practice

Three forms, weakest first.

### 1. Scope by path — the corrected H3-PM-006 criterion

```bash
grep -n "EndResult" DEPLOY.md        # no output; 0 hits (grep exits 1)
```

The criterion binds the surface the defect lived on, so quoting the string anywhere else — the row,
the verdict, this doc — cannot break it. Use this form whenever the defect names a file or a
directory; prefer a directory over a file when the fix spans several.

### 2. Exclude the self-quoting stores

```bash
grep -rn "EndResult" . --exclude-dir=.gitreins --exclude-dir=.coding-hermes
```

With `.gitreins/` and `.coding-hermes/` excluded and this file absent the sweep returned **8 hits**
(`docs/dogfood/` 6, `skills/` 2); adding this doc takes it to 15. The excludes are necessary but not
sufficient here, because the dated reports and the skill docs quote the criterion legitimately. Use
this form for a class-wide sweep on a string that must not appear in bookkeeping at all, and state
the residual hits in the row instead of claiming zero.

### 3. Assert on the artifact instead of the tree

```bash
# build proof — the documented snippet must compile against the SDK
cd /home/kara/get-h3/sdk-go && go build ./... && go vet ./...

# or a live artifact proof — the harness the snippet produces must answer health
curl -fsS http://localhost:9191/v1/health
```

A build or serve proof cannot be polluted by its own bookkeeping: the board row, its closure events,
the judge verdict, the dogfood report and the skill doc can quote `protocol.End` as often as they
like, and none of them is an input to the compiler or to the health handler. The gate's input set is
the source tree under the module (or the running process), not the search space of a text query, so
its verdict is independent of how many times the criterion is quoted. Reach for this form when the
finding is "this documented artifact is broken" — the artifact is what the criterion is about.

## Verification

```bash
grep -c "^Rule: scope every board PASS criterion so the check cannot match the artifacts that quote it$" docs/board/criterion-scoping.md
# -> 1

grep -n "EndResult" DEPLOY.md
# -> no output; grep exits 1 when there are no matches — that is the expected result

make verify
# -> make verify: ALL PASS — umbrella repo is self-consistent (exit 0)

git show --stat HEAD
# -> exactly 1 file changed: docs/board/criterion-scoping.md
```

## Board id-reuse repair (tick #374, DF-H3PM-02)

Rule: a board id holds exactly ONE finding. An id with more than one row may have at most one row
whose `status` is not `duplicate`; every archived duplicate of a *different* finding gets a fresh id
in its own family (`<PREFIX>-H3-<next free>`) and keeps `superseded_by` pointing at the surviving
canonical row. `superseded_by` must never equal the row's own id.

Detection: fingerprint each row by normalised `title` + `detail` — hex shas and digits stripped,
whitespace collapsed, lowercased — and never by the bare id, which is exactly what collides. Two
rows under one id with different fingerprints are two findings wearing one id.

Re-id map applied (old -> new): DF-H3-1 -> DF-H3-18; DF-H3-2 -> DF-H3-19, DF-H3-20;
DF-H3-3 -> DF-H3-21, DF-H3-22; QA-H3-1 -> QA-H3-10, QA-H3-11; QA-H3-2 -> QA-H3-12, QA-H3-13.

## The json-fence "not valid JSON" class

Rule: when a verifier says a documented JSON block "is not valid JSON", treat the payload as a
hypothesis and the extractor as the suspect. Extract the block BY LINE NUMBERS — the opening
`json` fence line through its closing fence — and run `json.loads` over the payload lines
(open+1 .. close-1). If that parses, the payload is valid, and the defect is in the extraction
or in the fence, never in the payload. Rewriting a payload that already parsed deletes real
specification content to satisfy a broken tool.

Why the class exists: row `H3-GAP-083` claimed the `llm_call` example in `specs/02` section 4.2
"is not valid JSON". Extracting `specs/02-Protocol-Specification.md` lines 222-234 and running
`json.loads` returns `["decision","decision_id","llm_call"]` — the payload was valid JSON, both
before and after the fix. What was true: the block embedded a Go snippet whose opening fence
sequence sat MID-LINE inside the `content` string value, so a naive non-greedy extractor — one
that consumes text up to the NEXT fence sequence anywhere in the file (a `re` non-greedy match, a
`sed -n` range extract, any "find the next fence" helper) — truncated the block at that sequence,
and the truncated text then failed with `Unterminated string starting at: line 8 column 35`. The
example is the canonical `llm_call` payload a harness author copies, so the FENCE was made
extractor-safe (the embedded snippet is now described in words:
`[Go snippet: func AuthMiddleware...]`) and no payload member was touched.

(a) **Measure by line numbers before believing a validity claim.** A block's payload is the text
between its fences, taken at known file lines; that is the only reading that matches what a
reader sees. An extractor that scans for the next fence sequence instead of the next FENCE LINE
reports the payload as broken when it only broke its own reading.

(b) **A fence sequence inside a JSON string value is not a markdown fence.** CommonMark closes a
block only on a line whose first non-space run is >= the opening fence char count, with no info
string; a triple-backtick sequence that sits mid-line — e.g. inside a `content` string value that
embeds a Go sample — is content and the block renders whole. It is nevertheless extractor-hostile,
so do not write one: describe an embedded snippet in words, or keep the marker off line-initial
positions.

(c) **The abbreviated blocks are allowed and must not be rewritten.** Four `json` blocks fail
`json.loads` on purpose, each because it abbreviates the payload instead of spelling out every
member, and each says so ON ITS FAILING LINE:

- `specs/15-Rate-Limiting.md` 9.1 — `...existing codes...,` inside the `error_codes` array
- `specs/15-Rate-Limiting.md` 9.2 — a bare `...` member line in the health response
- `specs/19-Health-Check-v2.md` — `"models": [...]`, `"dependencies": {...}`, `"resources": {...}`
- `specs/25-Conformance-Certification.md` — `"badge": { /* signed badge JSON */ }`

Abbreviation is a legitimate documentation form: it shows the shape without implying completeness.
A failing line carrying one of the placeholder tokens (`...`, `{...}`, `[...]`, `/*`, `*/`) is
reported `ALLOWED (abbreviated)`; "fixing" one of these by inventing members is a defect.

(d) **`scripts/check-json-fences.sh` is the guard for this class and runs from `make verify`.**
It extracts every `json` fence from the tracked markdown (`README.md`, `specs/*.md`, `docs/**/*.md`)
with `git ls-files`, feeds each payload to `python3 -c 'import json,sys;json.load(sys.stdin)'`
(structural fallback when python3 is absent), applies the (c) allowlist, and reports
`file:line` for anything else — including an unclosed fence. `sh scripts/check-json-fences.sh
--self-test` asserts its own exit codes against fixtures. It is a fence/payload guard only: it is
not a markdown renderer and not a schema validator.

