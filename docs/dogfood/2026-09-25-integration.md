# H3 Control-Plane Integration Report — 2026-09-25

Dogfood run 10 (tick h3-dogfood-2026-09-25-22-57-33). Angle: the harness
**control plane** — the `hermes-h3` lifecycle commands. Runs 1-9 tested
scaffold output, SDKs, the battery, loader internals and `make verify`; no
run had ever registered a harness, routed a session, or run
pre-update-check. This report is the missing chapter of
[2026-09-24b](2026-09-24b-integration.md): you built a harness and it
passes the battery — now what does managing it feel like?

## Environment

- shim: hermes-h3 0.1.0 (source install at /home/kara/get-h3/shim)
- Hermes: v0.21.1 (the real installed agent)
- config: scratch file `/tmp/dogfood-h3-ctl/config.yaml` (via `--config`);
  nothing in `~/.hermes/h3/config.yaml` was touched
- harness: py scaffold output, live on http://localhost:9191

## The lifecycle, as a user

```bash
# 1. config from nothing (0.15s)
hermes-h3 scaffold --config /tmp/dogfood-h3-ctl/config.yaml

# 2. harness from the scaffold, running in its own venv
hermes-h3 scaffold --lang py --output-dir /tmp/dogfood-h3-ctl
cd h3-harness-py && python3 -m venv .venv && .venv/bin/pip install -e .
.venv/bin/python main.py          # listening on :9191, boot->healthy 17ms

# 3. register (0.46s — health-probes the endpoint BEFORE writing config)
hermes-h3 install my-brain --endpoint http://localhost:9191 --set-default

# 4. health, fallback narrative, routing
hermes-h3 verify my-brain            # status/version/caps
hermes-h3 verify my-brain --fallback # contingency narrative + exit 0
hermes-h3 use my-brain               # default_harness
hermes-h3 route --session "telegram:-1004305778724:99" --set-harness my-brain
hermes-h3 route                      # table
hermes-h3 route --session "..." --remove

# 5. pre-flight an upgrade
hermes-h3 pre-update-check 0.21.1    # BLOCK — see DF-H3-36

# 6. tear down
hermes-h3 uninstall my-brain
```

## What held up

- **Fail-closed discipline is real.** Unknown harness in `verify`/`use`/
  `route --set-harness`, unknown session in `route --session`/`--remove`:
  every one exits 1 with a message naming what exists. No silent empties.
- **install probes before it persists.** A wrong endpoint never lands in
  the config (health probe first, ClickException, file untouched).
- **Config survives a dead endpoint.** Killed the harness mid-lifecycle;
  list/route/pre-update-check all behaved (WARN or clean error), file
  uncorrupted, `verify --fallback` correctly prints the ENGAGED narrative
  with the real exception text and exits 0.
- **Uninstall demotes default_harness** instead of leaving a dangling
  default (verified: default went back to null).
- Battery through the CLI's own tooling against the registered harness:
  46/46, 0.42s.

## What didn't (rows filed)

| Row | Finding |
|---|---|
| DF-H3-36 (P1) | pre-update-check BLOCKs on every real Hermes version (matrix stale at 0.20.0; shim 0.1.0 vs planned rows needing 1.1.0/2.0.0) |
| DF-H3-37 (P2) | `verify` prints `HealthStatus.OK` (enum repr) where install and the wire say `ok` |
| DF-H3-38 (P2) | `verify --fallback` hard-codes loader defaults + the "reroutes immediately" wording DF-H3-35 removed from the docs |
| DF-H3-39 (P2) | permanent "config schema v0 will be migrated to v1" WARN — no migration exists anywhere |
| DF-H3-40 (P2) | SKIPPED-install-bunker — las-bunker-03 offline this tick |

## Numbers (Step 2b)

hyperfine --warmup 3 --runs 20, warm, control host, shim 0.1.0 source
install:

| operation | mean ± σ |
|---|---|
| `hermes-h3 list` (no network) | 193.3 ms ± 34.2 |
| `hermes-h3 route` (no network) | 162.7 ms ± 24.4 |
| `hermes-h3 verify` (localhost HTTP) | 291.8 ms ± 17.6 |
| raw /v1/health round-trip (python urllib) | 3.9 ms |
| battery cold (first run after boot) | 0.62 s |
| battery warm | 0.42 s (p50 1.8ms / p95 44.5ms in-battery) |
| harness boot → first healthy response | 17 ms |
| lifecycle install | 0.46 s |

Verdict: **nothing here is slow enough to feel**. The ~250ms delta between
verify and the raw HTTP call is Python/CLI startup, identical for every
subcommand — a user notices nothing below ~300ms on a management command.
No PERF row filed; the number is the finding that there is no finding.
