# H3 integration field report — 2026-10-20 (dogfood run 16)

**Lane:** `h3-dogfood-2026-10-20-04-07-28` · **Target:** `get-h3/h3` (workdir
`/home/kara/get-h3/h3`) · **Verdict:** 🟡 **PROMISING-BUT-ROUGH** for the
documented CLI transport surface (product itself still SHIPPABLE).

## Promise under test

`docs/integration.md` §5.2 (rewritten by DOC-8 on 2026-10-19) claims an
integrator can manage harnesses end-to-end from the `hermes-h3` CLI — install,
list, verify, use, route, test, uninstall — and §6 claims `hermes-h3 scaffold
--lang <go|py|ts|python|typescript>` produces a complete harness project that
you build, run, and verify with `h3-test`. Nobody had ever consumed that new
table as a user; every verb in it was documentation, not experience.

## What a real user did

Clean venv → `pip install hermes-h3-shim` (**PyPI 0.2.0**) → scaffold → build →
run → `h3-test` → then the whole CLI lifecycle against a scratch config, plus
the loader side of the contract (`H3Loader.resolve`). Same run repeated on a
fresh Ubuntu 24.04 bunker agent with only the documented commands.

**Everything that was promised worked.** `install/list/verify/use/route/test/
test --json/uninstall` all exit 0 and do what the table says; scaffold emits a
harness that serves `/v1/health` and passes **48/48** on the first try; the
`--config` placement fixed by SHIM-GAP-014 works on the subcommand now, and the
`verify NAME` positional fixed by DOGFOOD-11 works. The 7 new DOC-8 rows were
accurate on the first read.

## Findings filed

| Row | Sev | Finding |
|---|---|---|
| DOGFOOD-12 | P2 | `uninstall NAME` removes the harness but leaves every `sessions:` binding pointing at it. `hermes-h3 route` still prints `s1 -> echo`, exit 0; `H3Loader.resolve()` returns the dead name with `harnesses.get(name) is None`, which the loader contract reads as *native* → silent fallback. Reproduces with a non-default harness too. |
| DOGFOOD-13 | P2 | Uninstalling the **default** harness writes `default_harness: null`; unmatched sessions then make `resolve()` return `None`, violating docs/api.md's "never returns `None`". With the key absent (loader default) resolve correctly returns `"native"` — the null state is what the CLI itself produces. |
| DOGFOOD-14 | P3 | Unwritable `--config` path → raw 20-line `PermissionError` traceback (cli.py:140 `save_config` mkdir, :141 open) instead of a clean error naming the path. |
| DOGFOOD-15 | P4 | §5.2 says the scaffold lands in `h3-harness-<lang>/`; `--lang python` actually creates `h3-harness-py/` (canonical name), so the documented `cd h3-harness-python` fails. |

## Exact repro (local, ~90 s)

```bash
python3 -m venv /tmp/v && /tmp/v/bin/pip install hermes-h3-shim   # 0.2.0
C=/tmp/c.yaml
/tmp/v/bin/hermes-h3 --config $C install echo --endpoint http://localhost:9191 --set-default
/tmp/v/bin/hermes-h3 --config $C route --session s1 --set-harness echo
/tmp/v/bin/hermes-h3 --config $C uninstall echo
cat $C                     # -> harnesses: {}  but  sessions: {s1: {harness: echo}}
/tmp/v/bin/hermes-h3 --config $C route          # -> s1 -> echo   (exit 0)
/tmp/v/bin/hermes-h3 --config /etc/nope/c.yaml install x --endpoint http://localhost:9191   # -> traceback
```

Loader side (`docs/api.md` Usage form, `pip install pyyaml` first):

```python
from h3_shim.loader import H3Loader
loader = H3Loader(cfg)                    # cfg from the file above
await loader.resolve("s1", "s1")          # -> "echo"   (client None == native)
await loader.resolve("telegram", "-100")  # -> None     (docs: "never returns None")
```

## Install leg (fresh box, executed — not inherited, not skipped)

Agent `df-h3-261020` on **bunker-mvp**, destroyed + absence re-verified ~90 s
later (`bunker list --status all` → 3 agents, none mine; key removed).

| Stage | Result |
|---|---|
| env | Ubuntu 24.04.4, python 3.12.3, git 2.43, go present, no pipx |
| bare `python3 -m pip install hermes-h3-shim` | rc=1 `externally-managed-environment` (PEP 668) — expected; docs already carry the venv recipe |
| venv + PyPI install | rc=0, **INSTALL_SECONDS=10**, `hermes-h3 0.2.0` |
| `scaffold --lang py` | rc=0, harness generated |
| harness venv + `pip install -e .` | rc=0, `/v1/health` → ok |
| `h3-test --endpoint http://localhost:9191` | **48/48 PASSED, exit 0**, 1.02 s |
| DOC-8 delta verbs (install/list/route/uninstall) | all rc=0; **DOGFOOD-12/13 reproduced on the fresh box** |

## Perf (Step 2b) — nothing a user would feel; **no PERF row filed**

| Operation | Cold | Warm | Command |
|---|---|---|---|
| `h3-test` full battery (48 tests) | 1.08 s wall (0.70 s internal) | 0.76–0.89 s wall / 0.48–0.58 s internal (n=3) | `h3-test --endpoint http://localhost:9191` |
| same on the fresh box | 2 s wall (1.02 s internal) | — | same |
| `hermes-h3 scaffold --lang py` | 0.27 s | — | (see repro) |
| PyPI install (network-bound) | 9 s local / 10 s fresh | — | `pip install hermes-h3-shim` |

Battery latency p50 1.7–4.3 ms, p95 68–131 ms; the two slowest cells are the
battery's own deliberate stress probes (`memory_stable` 292 ms, `rapid_process_calls`
139 ms). Every documented CLI verb returns in well under a second. Nothing here
justifies a profile, and nothing is slow enough for a user to notice.

## Verified-fixed on this run (re-proofs, not new rows)

- SHIM-GAP-014 (`--config` unusable on subcommands) — `hermes-h3 list --config X` → exit 0 ✅
- DOGFOOD-11 (`verify NAME` positional) — `hermes-h3 verify echo` → exit 0 ✅
- DOC-8's new tables — every verb/flag listed exists and behaves as described, except the `<lang>` naming nit (DOGFOOD-15) ✅

## Not findings (recorded so the next run does not chase them)

- `hermes-h3 --version` printing `0.1.0` on the control host is a **stale local
  editable install** (dist-info 0.1.0 built before the 0.2.0 bump, pointing at
  current repo src). A clean PyPI 0.2.0 install prints `0.2.0` on both hosts.
  Environment staleness, not a product defect.
- PEP 668 `externally-managed-environment` on bare pip is the documented,
  already-handled wall (venv recipe is in the scaffold output and README).
