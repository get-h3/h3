# H3 Fresh-User PyPI Path — 2026-09-28

Dogfood run (tick h3-dogfood-2026-09-28-23-20-50). Angle: the **PyPI
fresh-user path** — the README's actual quick start, never the source
checkout every prior run used. Runs 1-12 installed `shim` from
`pip install -e .`; a real new user hits `pip install hermes-h3-shim`
from PyPI and follows the README verbatim.

## What was done (as a user)

1. `python3 -m venv .venv && pip install hermes-h3-shim` — 5.7s from
   PyPI, zero errors, both console scripts (`h3-test`, `hermes-h3`)
   present. venv 5.3s.
2. `hermes-h3 scaffold --lang py` → harness dir, 1s.
3. `pip install -e .` the scaffold harness, run `main.py` — healthy.
4. `h3-test --endpoint http://127.0.0.1:9191` — 46/46, all_passing,
   p50 2.2ms / p95 75ms / p99 236ms.

## Ephemeral bunker install leg (bunker-las-03, agent 9f45f0c3, destroyed)

- Fresh clone from `https://github.com/get-h3/shim`: 5.2s (public repo,
  no credential needed).
- Fresh install: venv `--without-pip` + get-pip + `pip install -e .`
  = 14s, rc=0. (Bunker Debian has no ensurepip → the README's own
  `--without-pip` fallback box is exactly right; it worked verbatim.)
- Scaffold + harness install + serve + battery: 46/46 PASSED, 0.59-0.65s
  across 6 runs.
- Agent destroyed and confirmed gone.

## Perf (Step 2b)

Headline operation = the battery run: 0.62s warm (6-run median ~0.64s;
first local PyPI-venv run 0.62s, bunker cold-start 0.59s). The warm/cold
delta is noise; the p99 tail (236ms) is the battery's own stress tests,
not a defect. Nothing here is slow enough that a user would notice —
no PERF row filed.

## Verdict

✅ SHIPPABLE on the PyPI fresh-user surface. No new gaps found; the
install leg was EXECUTED (not skipped). The only near-finding: the
health endpoint is `/v1/health`, not `/health` — the battery probes the
correct path, so this is a non-issue; noting it only because a curl of
`/health` 404s and could mislead a hand-testing user.
