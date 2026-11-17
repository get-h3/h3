# Evidence index — dogfood tick h3-dogfood-2026-11-16-23-09-49 (run 18, SDK-author angle)

Probe kit for the 2026-11-16 real-use run, salvaged from the auto-pruned scratch
tree (`~/.hermes/cache/scratch/h3-dogfood-20261116/`) and committed here so the
numbers in rows DF-H3-52/53/54 and the dogfood-log entry remain re-runnable.
No product source was touched; the tree at commit 2b0eadf is clean.
The 9 Python probe scripts were reformatted with `ruff format` on commit (a
mechanical, semantics-preserving pass the repo's lint guard requires; the
scripts here are semantically identical to what produced the numbers below).

## Findings provenance

- **DF-H3-52** (installed 0.1.6 serves version 0.1.5): proved by the pip install
  leg into scratch `.venv` (scratch-only; venv not copied) + the battery runs
  against the installed SDK. See `a.json` (`armA`) and `d.json` (`armD`) targets.
- **DF-H3-53** (DELETE /v1/sessions: terminated:true + router-stamped
  `completed` accepted by test_5_14): probe scripts `lifecycle_probe.py`,
  `armD_nostatus.py`; filed from the shipped wheel + battery source.
- **DF-H3-54** (human battery report names no failing test): `red.txt` (arm A
  forced red — human report, no failing name), `armD_red.txt` (arm D red),
  `a.json`/`d.json` (the `--json` payloads whose detail the human report lacks),
  `fix_detail.py` + `patch_d54.py` (board-row evidence writers, board-only).

## Arms (four consumer harnesses written from the docs)

| file | arm | shape | result |
|---|---|---|---|
| armA_quickstart.py | A | docs-quickstart consumer, sessions + on_result | 48/48 pass, 0.76s wall (`a.time`) |
| armB_naive.py | B | no session tracking, no on_result | 43/48 — refuses to serve without on_result |
| armC_bare.py | C | bare FastAPI from OpenAPI description, `/health` | wrong-path case, owned by SHIM-GAP-037 |
| armD_nostatus.py | D | AGENTS.md quickstart shape, no `status` key | 47/48 — one real, unnamed failure (`d.json`, `armD_red.txt`) |

## Performance (Step 2b — all below user-noticeable thresholds, no PERF row)

- Cold start (spawn uvicorn → first /v1/health 200): median 299ms, min 283,
  max 320, n=5 (`cold_start.py`).
- Warm battery: 0.76s / 48 checks (`battery_time.txt`, ~7.6ms/check).
- Concurrency (40 turns / 8 sessions, 1 worker): cross_talk=0, p50 3.03ms,
  p90 8.65ms, p99 11.57ms (`concurrency_probe.py`).

## Install leg

Ephemeral bunker NOT RUN — `ssh bunker` (100.78.165.52:22) timed out twice
(rc=255); the blocked install-bunker row already exists as DF-H3-49. Local
substitute: clean venv, `pip install h3-harness-sdk` → 0.1.6 wheel installed,
served version 0.1.5 (= DF-H3-52).
