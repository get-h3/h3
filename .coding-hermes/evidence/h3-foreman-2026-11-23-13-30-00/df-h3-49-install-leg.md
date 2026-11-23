# DF-H3-49 — ephemeral install leg on bunker-las-03 (tick h3-foreman-2026-11-23-13-30-00)

Row: `[P2] SKIPPED-install-bunker — bunker-las-03 unavailable for the required ephemeral install leg`
Acceptance (PM-UNBLOCK 2026-11-17 criteria): ssh gate rc=0; bunker exec true rc=0; fresh clone
github.com/get-h3/sdk-python + `make install` rc=0; curl `http://127.0.0.1:9191/v1/health` = HTTP 200;
destroy the agent.

## Outcome: PASS on run 2 (agent h3-df49-20261123d), audit-corroborated

| # | Gate | Result | Corroboration |
|---|------|--------|---------------|
| 1 | `timeout 12 ssh -o BatchMode=yes -o ConnectTimeout=8 bunker3 true` | rc=0; host disk 83% (< 94% admission) | session transcript |
| 2 | `bunker exec h3-df49-20261123d --server bunker-las-03 -- true` | rc=0 (raw-d-gate.txt) | audit 14:01:32Z ExecAgent ok |
| 3 | fresh clone + `make install` | rc=0 (raw-d-install.txt; exec TRUE exit, no pipe) — pip ends `Successfully installed ... h3-harness-sdk-0.1.6`, marker LEG2_COMPLETE | audit 14:02:01Z command ok, `script bytes=532 sha256=bd119ddc…` == sha256sum df-h3-49-install2.sh |
| 4 | `curl -sf http://127.0.0.1:9191/v1/health` | HTTP 200 (raw-d-smoke.txt): `{"status":"ok","version":"0.1.6",...,"uptime_seconds":4}` | audit 14:02:13Z command ok, `script bytes=739 sha256=2007652a…` == sha256sum df-h3-49-smoke2.sh |
| 5 | destroy + verified absence | destroy rc=0; `bunker info` → `not_found`; `bunker list --status all` → `No agents found`; zero python/uvicorn processes pre-destroy (raw-d-ps.txt) | audit 14:02:55Z DestroyAgent ok → 14:02:55Z GetAgent not_found → ListAgents |

Installed-version note (feeds DF-H3-52): a fresh main clone imports and serves `0.1.6`
(derivation fix 09b6596 present in source). The remaining DF-H3-52 work is exactly the
owner-gated 0.1.7 release cut.

## Run-1 → judge FAIL → rework (honest trail)

Run 1 (agent h3-df49-20261123b) satisfied every acceptance COMMAND (health body + HTTP 200
streamed live through the foreman terminal; full pip transcript ended Successfully installed),
but both exec scripts exited NONZERO server-side and no raw stdout was preserved:

- install script exited 1: the upload transport mangled the final version-print line's single
  quotes (`print('imported…` → `print('\''imported…` → SyntaxError) and `set -e` aborted AFTER
  the successful `make install` (whose INSTALL_RC=0 marker only prints on success).
- smoke exec recorded exit 255: the body completed (curl + version print) but the in-script
  kill of the nohup'd uvicorn tore down the exec session's process group AFTER CLEANUP_DONE.
- raw stdout existed only in the foreman transcript → preserved post-hoc in
  df-h3-49-run1-raw-stdout.md (labeled, with the exit-code post-mortem).

GitReins tier-2 judge (verdict e6f74c5e, FAIL) correctly refused the run-1 closeout: raw gate
output was not preserved and the audit trail showed nonzero script outcomes. One judge
sub-claim is wrong: `uptime_seconds=4` after `sleep 5` is consistent (the server boots
concurrently, spending ~1s importing before startup completes). The substantive demands —
audit-corroborated evidence + preserved raw output — were met by re-running.

Run 2 fixes: no single quotes in scripts (transport-proof), no fragile trailing lines, teardown
moved to a separate exec, every exec's stdout captured to a repo file, true exit codes taken
from `bunker exec` directly (no pipeline `$?`), script hashes matched against the audit trail.
The cleanup leg's own exec still records exit_255 (runner reaps the session's process group at
exec end — same artifact as run 1); teardown is proven by PORT_CLOSED + zero processes +
destroy ok, not by that exit code.

## Containment incident during spawns (diagnosed; host fix CONSENT-BLOCKED, not applied)

Spawn outcomes on the SAME uid (1002): a FAIL (05:34 PST, first-ever, no drop-in yet at
instantiation), b PASS (05:41, persisted bar-bearing drop-in + loaded unit), c FAIL (05:47,
identical preconditions to b), d PASS (06:0x, retry) — landing convergence is NONDETERMINISTIC
on this host even with the drop-in already on disk.

- Off-by-one lab cache hit: class 3095 `bunker-spawn-slice-limits-memory-swap-max` (answer 4830).
- Host forensics (read-only): `/etc/systemd/system/user-.slice.d/` template ABSENT;
  `user-1000.slice MemorySwapMax=infinity`; running daemon `/opt/bunker/bunkerd`
  (0.2.1, commit bff29c84, built 2026-11-06T14:00Z) contains ZERO `MemorySwapMax` strings while
  the working sibling build (mvp, commit 3f89359d, built 03:20Z) contains THREE — the bff29c84
  file cannot emit the bar into new per-UID drop-ins; the existing
  `user-1002.slice.d/50-bunker.conf` (with `MemorySwapMax=0`) was written by an older daemon.
- Repo context: `internal/agent/df_bunker_67_test.go` documents this exact class for
  bunker-las-03 (systemd 257.13) and pins the raised budget (40 × 50ms = 2s) — both failures
  burned the FULL raised budget.
- The 3095 host remedy (template drop-in `/etc/systemd/system/user-.slice.d/50-bunker-swap.conf`
  + daemon-reload) was prepared but the unattended consent gate BLOCKED the host write — it did
  NOT run. Host mutation needs a foreground session or owner approval.

Residuals for the bunker owner (not this tick):
1. bunker-las-03 runs daemon build bff29c84 lacking the `MemorySwapMax` emission of good build
   3f89359d — first-spawn-of-a-uid fails containment landing; same-uid retries are flaky until
   the daemon emits the knob or a `user-.slice.d` template drop-in lands (3095 remedy;
   prepared content quoted in tick report).
2. Registry orphan: passwd carries `bunker-955b460a` (uid 1001) with no live agent record —
   `bunker destroy bunker-955b460a --purge` is the reclaim path (bunker-server-hygiene).

## Agent lifecycle (run 2)

- spawned `h3-df49-20261123d` (--server bunker-las-03 --ttl 1h) after one failed spawn (c)
- scripts: df-h3-49-install2.sh / df-h3-49-smoke2.sh / df-h3-49-cleanup2.sh (this dir)
- raw outputs: raw-d-gate.txt, raw-d-install.txt, raw-d-smoke.txt, raw-d-cleanup.txt,
  raw-d-ps.txt, raw-d-destroy.txt, raw-d-info.txt, raw-d-audit.txt (this dir)
- destroyed + verified absent (audit DestroyAgent ok → GetAgent not_found → list empty)
