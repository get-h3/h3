# Dogfood Integration — 2026-09-24 (run 2: h3, H3Loader resilience)

**Verdict: PROMISING-BUT-ROUGH.** The harness side of H3 is now proven nine
times over (batteries, scaffolds, SDKs, consumers). This run drove the LAST
untested surface — the Hermes-side loader that the whole "brain-swap" promise
rests on — and found a P0: the circuit breaker freezes OPEN forever, so a
loader that has opened its breaker can never recover without a host restart.

## Angle (pitfall doctrine: change the surface, not the depth)

Nine prior h3 runs (2026-08-02 → 2026-09-24) covered: the battery, py/go/ts
scaffolds, three SDK echoes, from-scratch consumers, `make verify`, the
protocol repo's own gate, and the `hermes h3` plugin. Never touched:

1. **`H3Loader`** (shim `src/h3_shim/loader.py`) — discovery, session
   routing, the background health loop, the circuit breaker, reroute.
2. **The resilience contract** — integration.md §3.2 promises: consecutive
   failures → reroute; breaker "opens on sustained failures and reroutes
   sessions *immediately*"; "When the circuit is OPEN the health check is
   skipped until the cooldown expires (half-open probe)". No battery test
   kills a harness; no dogfood had either.

## Promise under test

"A Hermes host uses H3Loader to route sessions to a harness, health-check it
in the background, and — when the harness dies — automatically reroute its
sessions so conversations keep flowing, recovering when it returns."

## What was run (all live numbers)

| Surface | Result |
|---|---|
| H3Loader boot + config (local, go echo :9731) | works; resolve precedence thread > chat > platform > default ✓ |
| `route_session` / `get_session_harness` | pin → lookup ✓ |
| **Kill harness → reroute (healthy→dead)** | **REROUTE fires at 85s** (3 × 30s health interval), sessions A,B → native ✓ |
| New-session routing during outage | native ✓ (via `_session_routes` reroute) |
| **Fresh host during outage (`resolve` from config)** | **→ dead harness name** (config read is static; reroute lives in a different dict) ✗ DF-H3-33 |
| Harness restart → failback | healthy flag recovers at next pass; **rerouted sessions stay on native forever** (no failback path in code) — half of a documented "keeps flowing" contract |
| **Circuit breaker (window=2, threshold=0.5, cooldown=3s, documented knobs)** | OPEN at 26s (first failed pass after window filled) → **still OPEN at +300s** despite harness restarted and healthy at +180s. Half-open probe never fires: the health loop *skips* OPEN circuits (loader.py:315-323) and is the **only** caller of `record_outcome` (loader.py:333/341/351) and `allow_request` (loader.py:118) — **`allow_request` has zero call sites in `src/`** ✗ DF-H3-34 (P0) |
| Bunker (las-bunker-03, agent f914cf7d, bare Debian 13) | clone 5.3s (HEAD 9af6d50), install 15s (venv--without-pip + get-pip + `pip install -e .`), scaffold py, **full resilience scenario reproduced on the fresh box: reroute 90s, resolve-at-boot → dead name**. Battery 46/46 exit 0, 0.59s (p50 1.99ms). Agent destroyed, absence verified. |

## The P0, stated precisely

`CircuitBreaker` is a correct implementation of a textbook breaker — sliding
window, cooldown, half-open probe — that **can never reach HALF_OPEN through
its only integration point**. The health loop's first branch is
`if cb.state == OPEN: skip + reroute + continue`. Transitioning OPEN →
HALF_OPEN requires either `record_outcome` (only called after a health check,
which is skipped) or time passing *plus someone observing it* (`allow_request`
in `_recalc_state`, never called). Net effect, measured with the documented
config knobs: **a single transient outage that opens the breaker permanently
disables that harness for the life of the host process** — worse than having
no breaker at all, because a plain failure counter recovers on the next
healthy pass (proven: without the breaker, `healthy=True` came back one pass
after restart in run 1).

## Measured (Step 2b — perf)

| Operation | Cold | Warm |
|---|---|---|
| Reroute latency after harness death (documented defaults) | 85s local / 90s bunker | n/a (bounded by 30s health interval × `max_consecutive_failures`) |
| Loader boot → first healthy pass | ~0.5s (next health tick) | — |
| Battery on bunker (py scaffold) | 46/46, 0.59s | — |

The 85-90s reroute latency is a *finding* (docs say "immediately"), not a
performance problem — a user-visible number for what failover actually costs.
Nothing else was slow enough to feel; no PERF row filed.

## Friction inventory

1. **DF-H3-34 (P0)** — breaker freeze, as above.
2. **DF-H3-33 (P1)** — reroute is not durable: `resolve()` reads static
   config while reroute rewrites `_session_routes`; any host restart
   (deploy, crash, supervisor restart — routine for a Hermes gateway)
   re-resolves pinned sessions to the dead harness. Also: the healthy flag
   boots as `False` even for a live harness until the first pass, so
   anything reading health at boot-time sees "unhealthy" for up to 30s.
3. **DF-H3-35 (P2)** — docs overpromise ("reroutes immediately"; no recovery
   contract at all). integration.md:175-176 and loader.py's own docstring
   (299-309) both need a re-write against measured behavior.

## What a new user needs that isn't documented

- That breaker state, healthy flags, and reroutes are all **in-process only**
  — no persistence, no failback, no half-open probe in practice.
- The 30s health interval and `max_consecutive_failures=3` compound:
  worst-case detection ≈ `interval × failures` = 90s. Set both explicitly.
- `resolve()` is a pure config function. If you need outage-aware routing in
  your host, you must consult `loader._harness_healthy` yourself (private).

## Verdict reasoning

The harness ecosystem is genuinely shippable and nine runs of evidence say
so. But the loader is the component that makes the brain-swap *safe* to turn
on in production, and its failure handling has never been exercised. It
works in the happy direction (detect dead harness → move sessions to native)
and fails exactly where resilience matters (recovery). PROMISING-BUT-ROUGH:
use it with the breaker effectively disabled (large window / high threshold)
and accept manual restart-to-recover, until DF-H3-34 lands.
