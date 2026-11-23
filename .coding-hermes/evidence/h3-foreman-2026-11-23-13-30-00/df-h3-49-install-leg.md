# DF-H3-49 — ephemeral install leg on bunker-las-03 (tick h3-foreman-2026-11-23-13-30-00)

Row: `[P2] SKIPPED-install-bunker — bunker-las-03 unavailable for the required ephemeral install leg`
Acceptance (PM-UNBLOCK 2026-11-17 criteria): ssh gate rc=0; bunker exec true rc=0; fresh clone
github.com/get-h3/sdk-python + `make install` rc=0; curl `http://127.0.0.1:9191/v1/health` = HTTP 200;
destroy the agent.

## Gate results (all PASS)

| # | Gate | Result |
|---|------|--------|
| 1 | `timeout 12 ssh -o BatchMode=yes -o ConnectTimeout=8 bunker3 true` | rc=0 |
| 1b | Host probe | SSH_OK, bunker-las-03, `/dev/nvme0n1p2 221G 174G 37G 83% /` (below 94% admission) |
| 2 | `bunker exec h3-df49-20261123b --server bunker-las-03 -- true` | rc=0 (exec binds an AGENT, not the server alias — the acceptance's `bunker exec bunker3 "true"` shape has no target binding in bunker 0.2.x CLI; the agent-scoped form preserves the criterion's intent) |
| 3 | `git clone --depth 1 https://github.com/get-h3/sdk-python.git && cd sdk-python && make install` | rc=0 — h3-harness-sdk 0.1.6 editable wheel built + installed, full dev deps |
| 4 | `curl -sf http://127.0.0.1:9191/v1/health` | HTTP 200 — `{"status":"ok","version":"0.1.6","active_sessions":0,...,"protocol_version":"1.0","transport":"rest","uptime_seconds":4}` |
| 5 | `bunker destroy h3-df49-20261123b --server bunker-las-03` | rc=0 (home 371.0 MB archived+deleted, local key removed); `bunker info` → `not_found`; `bunker list --status all` → `No agents found` |

Installed-version note (feeds DF-H3-52): a fresh main clone imports and serves `0.1.6` (derivation fix
09b6596 present in source). The remaining DF-H3-52 work is exactly the owner-gated 0.1.7 release cut.

## Containment incident during spawn (diagnosed, not fixed host-side)

First spawn `h3-df49-20261123` FAILED at stage slice-limits:
`containment landing did not converge within 40 reads: memory.swap.max = "max", want "0" (bar swap)`.

- Off-by-one lab cache hit: class 3095 `bunker-spawn-slice-limits-memory-swap-max` (answer 4830).
- Host forensics (read-only): `/etc/systemd/system/user-.slice.d/` template dir ABSENT;
  `user-1000.slice MemorySwapMax=infinity`; the running daemon `/opt/bunker/bunkerd`
  (0.2.1, commit bff29c84, built 2026-11-06T14:00Z) contains **zero** `MemorySwapMax` strings
  while the working sibling build (mvp, commit 3f89359d, built 03:20Z) contains **three** —
  the bff29c84 file physically cannot emit the bar into a NEW per-UID drop-in.
  The existing `/etc/systemd/system/user-1002.slice.d/50-bunker.conf` (written by an older daemon)
  DOES carry `MemorySwapMax=0` and its mtime updated at the failed spawn (05:34 PST).
- After the failed attempt, `systemctl show user-1002.slice -p MemorySwapMax` → `0` (unit DB picked
  up the persisted drop-in) while the live cgroup still read `max` at spawn time.
- Repo context: `internal/agent/df_bunker_67_test.go` documents this exact class for
  bunker-las-03 (systemd 257.13) and pins the RAISED convergence budget (40 × 50ms = 2s) —
  my failure consumed the full raised budget, so the budget raise alone is insufficient when the
  bar-bearing drop-in is not yet on disk at slice instantiation.
- Working mechanism (proven live): the SECOND spawn (`h3-df49-20261123b`) re-drew uid 1002 whose
  drop-in (with `MemorySwapMax=0`) now persists on disk BEFORE slice instantiation → landed
  immediately → spawn succeeded. No host files were modified by this tick.

Residual (for the bunker owner, not this tick):
1. `/opt/bunker/bunkerd` on bunker-las-03 (bff29c84) lacks the `MemorySwapMax` emission of the
   good 3f89359d build — first-spawn-of-a-uid will fail containment landing until the daemon
   emits the knob or the host gains a `user-.slice.d` template drop-in (off-by-one 3095 remedy).
2. Registry orphan: passwd carries `bunker-955b460a` (uid 1001) with no live agent record
   (bunker list empty) — `bunker destroy bunker-955b460a --purge` is the reclaim path per
   bunker-server-hygiene.

## Agent lifecycle

- spawned `h3-df49-20261123b` (--server bunker-las-03 --ttl 2h) after the first-spawn failure above
- install leg script: df-h3-49-install.sh (this dir)
- smoke script: df-h3-49-smoke.sh (this dir); server killed before destroy
- destroyed + verified absent (info not_found, list empty)
