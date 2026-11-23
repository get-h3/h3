# H3 docs audit — 2026-11-23 (delivery 2 of tick h3-docs-2026-11-23-18-36-23)

Documentation gap audit of the umbrella surface, run by the h3-docs lane.
Delivery 1 of this tick (commit e9703e1) filed DOC-31 + DOC-25-R2 row-only with a
stand-in probe transcript; this delivery re-verifies both live, then files eight
new findings (DOC-32..DOC-39) and re-triages one row's severity. No target docs
were edited — the foreman dispatches the fixes.

Environment: umbrella at e9703e1 (= origin/main at audit time, clean tree);
sibling checkouts shim 162a8a8 (pyproject 0.2.0, matching PyPI latest), sdk-go,
sdk-python, sdk-typescript, protocol at their checked-out HEADs; published shim
0.2.0 installed fresh into a throwaway venv (python 3.14) for CLI probes;
`make verify` run first — ALL PASS (10 guards; docs-link, spec-index, count=48,
tags-table, json-fences, qa-target, tick-chain, board-header, commit-msg,
verdict census 2/0).

## Delivery-1 rows re-verified live (no changes to them)

- DOC-31 (identity block undocumented): still live. Census over README.md,
  DEPLOY.md, CHANGELOG.md, SECURITY.md, CONTRIBUTING.md, docs/integration.md,
  docs/releases.md, docs/observability-spec.md for `hermes_token`: the only hit
  is DEPLOY.md:345 (the argument-priority sentence), no page names the config
  `identity:` block. Finding stands, correctly filed P4.
- DOC-25-R2 (observability-spec live-state rot): still live. `:9191` refused
  connection (curl exit 7, http_code 000 — the doc pins pid 1040050 answering
  200); `ss -ltnp` shows pulse on :9161 at pid 1774955 (doc pins Nov-17 pids
  3002/2992). Finding stands, correctly filed P4.

## New findings filed this delivery (DOC-32..DOC-39)

Method notes: every "zero hits" claim below was re-grepped against the exact
reference set before filing; CLI claims were probed against the PUBLISHED shim
0.2.0 (PyPI install), not the dev checkout; every `spec=` anchor was derived by
GitHub slug rules against the audited blob (all eight resolve; the Setup
heading's em-dash slugifies to `setup-important--read-first` and is cited in
that exact form).

### DOC-32 (P4, rot) — skill port pitfall contradicts the example it points at

- skills/h3-usage/SKILL.md:191-197: "The Python echo example hardcodes `:8000`
  ... looks like a baffling 9/44".
- sdk-python/src/h3_harness/examples/echo.py:14-22: "The port defaults to the
  battery port 9191; pass a number to override (e.g. python echo.py 8000)",
  reads `sys.argv`; grep for `8000` finds it only inside that example comment.
- The skill's own run line (`python src/h3_harness/examples/echo.py &` then
  `h3-test --endpoint http://localhost:9191`) only works because of the new
  default. README.md:82-84 already documents the argv-port contract correctly.
- The "(baffling 9/44)" parenthetical cites the retired count (48 since
  2026-10-02; scripts/test-count.txt).

### DOC-33 (P4, wrong-reference) — DEPLOY.md TypeScript example cannot compile

- DEPLOY.md:157: `import { Harness, Decision, DecisionType, createH3Router }
  from '@get-h3/h3-harness-sdk'`; DEPLOY.md:161: `decision: DecisionType.TEXT`.
- sdk-typescript/src/protocol.ts:20: `export type DecisionType =
  z.infer<typeof DecisionTypeSchema>` — TYPE only; grep for any runtime
  `DecisionType` value export across src/ finds none. index.ts exports
  `Harness` (type) and `createH3Router` (value) but no `Decision`/`DecisionType`
  values.
- The site examples use the working form everywhere (plain literals:
  `decision: 'text'`), e.g. docs/guide.html, docs/index.html, docs/sdk.html TS
  panels.

### DOC-34 (P4, wrong-reference) — Python snippet filename unstated; three docs disagree

- docs/sdk.html:734 and docs/index.html:617: Run `uvicorn harness:app ...`;
  neither page names the file to save the snippet as (grep for `harness.py` /
  `main.py` / "save" in both: no hits in the Python panels).
- DEPLOY.md:150: `uvicorn main:app --port 9191` — filename also unstated there;
  DEPLOY.md:251 (same guide, Docker section) names `harness.py`.
- docs/guide.html:463 names `main.py` in a snippet comment — the only page that
  states a filename. uvicorn resolves `<module>:<attr>`, so the unnamed-file
  Run lines fail for any name the reader picks unaided.

### DOC-35 (P5, polish) — README Loop lists four of six decision types

- README.md:195: "(text, tool_call, end, or wait)".
- protocol/schemas/v1/decision.json enum: six values — text, tool_call,
  llm_call, wait, delegate, end (sdk-go/protocol/types.go:15-22 matches).
- skills/h3-usage/SKILL.md already lists all six; README is the stale subset.

### DOC-36 (P5, polish) — 5.2 --version refusal enumeration incomplete

- docs/integration.md:560 names five refusing subcommands (list, route, use,
  scaffold, verify).
- Live probe of published 0.2.0: `hermes-h3 <cmd> --version` invoked for all
  nine subcommands; every one answers with the Click usage line (refusal).
  Only the group level accepts --version. The claim "group-level only" is true;
  the five-name enumeration reads as exhaustive and is not.

### DOC-37 (P5, rot-lite) — skill Setup pins stale PyPI versions

- skills/h3-usage/SKILL.md:40-44: sdk "(0.1.2, published 2026-08-08)", shim
  "(0.1.0, published 2026-09-22)".
- Live: pypi.org/pypi/h3-harness-sdk/json → 200, info.version 0.1.6;
  pypi.org/pypi/hermes-h3-shim/json → 200, info.version 0.2.0. The skill's own
  release-sweep section still says "still 0.1.0" (dated run evidence — left as
  history, not filed).

### DOC-38 (P5, polish) — skill describes the pages.yml count guard as "single-sources 46"

- skills/h3-usage/SKILL.md:409; scripts/test-count.txt = 48; pages.yml comments
  speak in terms of 48 ("48 -> 49"). Same file says "46 anywhere = stale"
  fourteen lines earlier.

### DOC-39 (P5, rot) — skill denies the positional form verify now takes

- skills/h3-usage/SKILL.md:217-218: "(it takes `--harness`, not a positional)".
- Live 0.2.0 `hermes-h3 verify --help`: "Usage: hermes-h3 verify [OPTIONS]
  [NAME]" with "-h, --harness TEXT ... Ignored when NAME is given" — both
  forms exist; docs/integration.md 5.2 already documents the positional
  correctly, so the skill contradicts its own reference.

## Re-triage (doc-severity policy, not a new assessment)

- DF-H3-056 (filed today by the dogfood lane at P2): finding class is
  missing-reference (telemetry surface documented nowhere; observability spec
  §0/§4 stale). Demoted P2 → P4, title prefix moved in the same update, note
  added naming the policy (Bane ruling 2026-09-30: a doc row must never
  outrank a functional defect). The finding itself stands as filed.
- No pre-2026-09-30 doc rows at P1-P3 remain open on this board (census of all
  open P0-P3 rows; the only doc-class row at P1-P3 was DF-H3-056, filed
  post-ruling).

## Live witnesses captured this tick

- `make verify` → "make verify: ALL PASS" with verdict census "2 verified /
  0 unverified".
- PyPI: hermes-h3-shim 0.2.0, h3-harness-sdk 0.1.6 (both HTTP 200).
- npm registry: scoped @get-h3/h3-harness-sdk → 404, unscoped h3-harness-sdk →
  404 (the docs' npm-404 claims are true).
- Published shim 0.2.0 CLI surfaces: `h3-test --help`, `hermes-h3 --help`, and
  `--help` on all nine subcommands match docs/integration.md 5.2 (table is
  accurate); `--version` refuses on all nine subcommands.
- sdk-go release tags: v0.1.8 is the latest semver tag (README's dated pin
  "v0.1.8 as of 2026-10-07" remains current); shim tag set {v.0, v0.2.0}; no
  tag contains d95085b, so the skill's "no release carries the uninstall fix
  yet" statement still holds; the 0.2.0 wheel still bundles the 0.1.0-pairing
  versions.yaml (skill's DF-H3-36 pitfall still accurate).
- sdk.html/index.html `harness:app` Python Run commands are the only broken-as-
  written instructions found on the site; guide.html's main.py flow is correct.

## Coverage and what was NOT re-verified

Audited surfaces: README.md (full), DEPLOY.md (full), AGENTS.md, CONTRIBUTING.md
(all named make targets and workflows exist: pages.yml, roundtrip.yml, and the
protocol/shim workflow sets match the README's CI claims), SECURITY.md
(DOC-9 fix intact: zero-auth/TLS disclosure present), docs/integration.md
(endpoints table matches the protocol paths; exit-code table matches the
battery epilog; 5.1/5.2 verified as above; PyPI install guidance present —
DOC-24 fix intact; --version group-level claim present — DOC-23 fix intact),
docs/releases.md (tags-table guard green; historical era labels left as
history), docs/qa-target-contract.md (matches scripts/check-qa-target.sh
behavior; make verify-qa-target PASS), docs/migration.html (battery banner
v0.2.0 carries an explicit not-a-pinned-requirement disclaimer; registry routes
current), docs/protocol.html (route mentions are schema $id fields, not
phantom endpoints), docs/observability-spec.md §1 (owned by the open
DOC-25-R2), skills/h3-usage (audited in full), skills/h3-pm-usage (143 lines,
not diffed field-by-field this tick), specs/_index.md (guard-enforced).

NOT re-verified this tick: field-by-field schema parity of
docs/integration.md §2-§4 request/response envelopes against
protocol/h3-protocol.yaml (battery-enforced in CI; only headline claims
spot-checked); guide.html's TypeScript tsconfig guidance; skills/h3-pm-usage
content; the HTML pages' JS behavior (only served content claims); Go module
proxy resolution live (the README pin was checked against git tags, not the
proxy endpoint).

STATUS: findings filed, all open — nothing closed this delivery.
