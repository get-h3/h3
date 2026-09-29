# H3 Docs Surface (Published Site + Release Pins) — 2026-09-29

Dogfood run 14, lane `h3-docs` (tick target: the h3 repo's docs lane). Angle:
**the lane's own product** — the published docs site
(https://get-h3.github.io/h3/, deployed by `.github/workflows/pages.yml` from
`docs/`) and the release-pin contract it publishes (`docs/releases.md`). No
prior run consumed the site as a reader or verified the published pin flow;
runs 1–13 tested the shim/SDK/battery products, the CLI, the loader, and the
release sweep.

## Promise under test

"A reader can consume the published H3 docs site, follow its release guide to
pin the newest tag, and verify an umbrella release from a fresh clone with
`make verify`."

## What a real reader session looked like

1. **Site consumption.** All five pages serve 200 with byte-identical content
   to HEAD (`index.html`, `protocol.html`, `sdk.html`, `guide.html`,
   `migration.html`) plus `integration.md` / `releases.md` — live == HEAD
   verified by diff after the v0.3.0 push. TTFB ~235 ms. The compliance badge
   SVGs serve; the `46/46` count on the site is guarded by
   `scripts/test-count.txt` + CI (GAP-072), and a probe for retired counts
   (43/44/45) found only false positives (CSS pixel values, hashes) — the
   count guard holds on the published surface too.
2. **Release pin+verify, verbatim from the published guide.** Fresh public
   clone → `git checkout v0.3.0` → `make verify`: **ALL PASS, rc=0, 3.1 s**
   (12 PASS lines). The guide's flow works on the newest tag; what does not
   work is the guide's tag table (DF-H3-44 below).
3. **Link integrity probe of the published pages** (27 unique links across
   all pages + GitHub API existence for the six referenced repos): all six
   `get-h3/*` repos exist; **two live 404s** — `integration.md` links
   `../specs/02-Protocol-Specification.md` and `../specs/05-Test-Battery.md`,
   which Pages never publishes (specs are deliberately unpublished per the
   pages.yml H3-PM-007 note) → DF-H3-45.
4. **Fresh-machine install leg** (las-bunker-03, agent 1027e20b, bare
   Debian): documented path = clone public repo → checkout tag → `make verify`.
   Clone 5 s, verify 1 s, rc=0. No venv, no pip, no toolchain needed — the
   repo-as-product installs with git + coreutils alone (jq/curl/python3 were
   prepresent and the DuckBrain guards degraded to honest UNVERIFIED without
   the token). Agent destroyed, absence verified.
5. **Step 2b measurements:** `make verify` 0.98 s ±0.21 warm (hyperfine
   n=10), count guard 101 ms, full journey clone→tag→verify 3.6 s cold,
   site TTFB 235 ms. Nothing a user would feel — no PERF row, deliberately.

## Findings (rows on the h3 board)

- **DF-H3-44 (P2)** — published `releases.md` Tags table lists only v0.1.0
  while v0.2.0 (09-20) and v0.3.0 (09-29) are cut and pushed; a consumer
  following the published release guide pins a 2-releases-old commit.
- **DF-H3-45 (P2)** — published `integration.md` spec links 404 on Pages;
  the repo link guard covers README + specs/_index only, so links inside
  `docs/*.md` are never validated anywhere.
- **DF-H3-46 (P3)** — cross-evidence for DF-H3-41: the UNVERIFIED→exit-0
  composition reproduced on a real fresh box (6 UNVERIFIED lines, final
  `ALL PASS` rc=0), no synthetic probe needed; every public consumer gets
  this. Also refreshed DF-H3-43 (PyPI shim still 0.1.0 under umbrella
  v0.3.0) and DF-H3-41 notes.

## Verdict

**SHIPPABLE** for the docs surface: live == HEAD, the headline pin+verify
flow works verbatim on the newest tag in ~3 s, install needs nothing but
git, and the flagship number (46) is genuinely single-sourced. The two P2s
are staleness/link-routing in the published contract, not runtime defects.
