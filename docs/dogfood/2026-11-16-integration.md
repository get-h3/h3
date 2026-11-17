# H3 dogfood report — 2026-11-16 (SDK-author angle)

ch:trace tick=h3-dogfood-2026-11-16-23-09-49 project=h3 repo-head=2b0eadf

## Promise
This run's angle is the SDK author's, not the integrator's: a harness author
reads the Python quickstart (docs/integration.md, AGENTS.md), writes a
consumer harness against `h3-harness-sdk`, and proves it with `h3-test`.
Promise under test: "an SDK author can write a compliant harness from the
documented quickstart alone."

## Real-use result
Verdict: WORKS-BUT-THE-SIGNALS-LIE (🟡 PROMISING-BUT-ROUGH). The quickstart
shape passes the battery (arm A: 48/48, 0.76s wall), and the harness answers
correctly under documented concurrency (40 turns / 8 sessions, cross_talk=0).
But the signals the author relies on lie in three places, each filed as a row:

1. **DF-H3-52 (P2)** — the published wheel is 0.1.6 but serves itself as
   version 0.1.5 (`_version.py:9` vs `pyproject.toml:7`). A client checking
   version compatibility against `/v1/health` tests the wrong version.
2. **DF-H3-53 (P2)** — `DELETE /v1/sessions` answers `terminated:true` after
   the BaseHarness no-op hook and stamps `status=completed` itself, and
   battery `test_5_14` accepts exactly that router-written status. The green
   light does not prove a terminate tore anything down. Filed from the shipped
   wheel + battery source; live repro is the row's first AC (DELETE is
   consent-gated, so the live arm was not run).
3. **DF-H3-54 (P3)** — a red battery's human report prints per-category
   tallies only (15 lines, TOTAL 47/48 FAILED) and never names the failing
   test; the actionable detail (`process_text_finished_false [Process Basic
   Flows] — Expected finished=false, got True`, a documented convention) exists
   only in `--json`. A correct harness reads as broken to a text-report user.

## Arms (what each proves)
Four consumer harnesses were written from four readings of the docs:
- **A** — docs-quickstart consumer (sessions tracked, `on_result`): 48/48.
- **B** — no session tracking, no `on_result`: refuses to serve until
  `on_result` is added; 43/48 after the change. The SDK does not tolerate the
  naive reader.
- **C** — bare FastAPI from the OpenAPI description (`/health`, bare
  `/v1/process`): wrong-path case, already owned by SHIM-GAP-037.
- **D** — AGENTS.md quickstart shape (no `status` key, no terminate hook):
  47/48 — the one real failure DF-H3-54 documents.

## Install leg
Ephemeral bunker NOT RUN — `ssh bunker` (100.78.165.52:22) timed out twice
(rc=255); the blocked install-bunker row already exists as DF-H3-49, so this
tick did not re-file it. Local substitute: clean venv, `pip install
h3-harness-sdk` → 0.1.6 installed, served version 0.1.5 (= DF-H3-52). The
substitute install is not a silent pass; the bunker leg stays UNVERIFIED.

## Performance
- Cold start (spawn uvicorn → first /v1/health 200): median 299ms, min 283,
  max 320, n=5.
- Warm battery: 0.76s / 48 checks (~7.6ms/check).
- Concurrent turns (40 / 8 sessions, single worker): p50 3.03ms, p90 8.65ms,
  p99 11.57ms, mean 3.98ms, cross_talk=0.

Nothing measured is user-noticeable; no PERF row and no profile run — a win
nobody can feel is not a finding.

## What a harness author needs that the docs don't say
- `on_result` is not optional in practice: arm B would not serve without it,
  which the quickstart does not foreground.
- The `status` key and terminate hook are part of a *compliant* harness, but
  the router papers over their absence with self-stamped state (DF-H3-53) —
  so the battery cannot teach you they were missing.
- A red run tells you nothing unless you already know `--json` exists
  (DF-H3-54).

## Evidence
Probe kit committed at `.coding-hermes/evidence/h3-dogfood-2026-11-16-23-09-49/`
(arm scripts, red/green outputs, `--json` payloads, timing files, perf probes,
board-writer scripts) with its own README index.
