# PROVENANCE — QA-H3-29 (harness fix, product lives OUTSIDE any git repo)

Row: QA-H3-29 on h3 board (.coding-hermes/board/tasks.jsonl).
Tick: h3-foreman-2026-11-26-02-07-14. Worker session: local-01b36e38d5823d7533747885bb6a2fa7a20ebf218053ea9ce599f24cd445eaf8 (seat-proven: model=glm-5.3-flash provider=opencode-go-2 @ https://opencode.ai/zen/go/v1, no 'Fallback activated'/'refused for billing' lines in agent.log under this session id).

## Product
File: /home/kara/.hermes/scripts/bunker-qa.sh (shared fleet QA battery; NOT a git repo — no commit hash exists or is possible for the product itself).
- BEFORE sha256: 7230a96b3433af49f5c5a990593ddf49bf01a46796314d9854270064e6cc250f (backup copy: bunker-qa.sh.bak-QA-H3-29-20261125T211950)
- AFTER  sha256: e341acf4f8edbd064e26d1e7ef8aeb1b1a9b55c3582aa621079fe10760a20e7c
Change: the "FIX 3" node+npm toolchain bootstrap block moved byte-identically from after the native-suite tests cell (old line ~3670) to immediately before it (new line 3426; tests cell `QA_TESTS_CMD=` now at line 3458). No grading-semantics change (native_runner_missing* untouched). Full diff: fix.diff.

## Evidence (this dir)
- fix.diff — unified diff backup-vs-live.
- worker.log — worker session log; contains the control run output.
- proof/ — the extracted OLD-vs-NEW ordering proof (scrubbed PATH, node-free verified up front): OLD order reproduces `npm: command not found (rc=2)`; NEW order resolves node from $HOME/tools/node/bin (rc=0).

## Foreman re-verification numbers
- bash -n /home/kara/.hermes/scripts/bunker-qa.sh → clean.
- Static ordering: FIX 3 block at line 3426 < tests cell QA_TESTS_CMD at line 3458.
- Control (node v22.22.3 on PATH at /home/kara/.local/share/vite-plus/bin): `cd /home/kara/get-h3/h3 && make verify-roundtrip` → "Passed: 6  Failed: 0", "QV-PROTO-04: Cross-language protocol round-trip verification PASSED".
- h3 repo product code untouched: only board-plane files (.coding-hermes/waves manifest, this evidence dir, gitreins tasks.yaml lifecycle state).

## Residual (disclosed, not hidden)
AC1/AC2's fresh-JIT-agent proof shape (cell-timestamp vs ~/tools/node/bin ctime on a NEW agent) is NOT yet produced: no fresh battery was run this tick (JIT provisioning out of a foreman tick's scope; bunker-mvp known disk pressure). The fix is live in ~/.hermes/scripts/bunker-qa.sh as of 2026-11-25 21:20 -05, so the NEXT h3 QA battery tick on a fresh JIT agent exercises the reordered harness — its tests-cell result is the fresh-agent evidence. Filed as follow-up row QA-H3-31 to close that proof on the next battery's evidence.
