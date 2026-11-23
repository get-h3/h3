# Evidence — h3 dogfood tick h3-dogfood-2026-11-23-14-28-25 (run 19, observability-operator angle)

Angle: a user wires the NEW verify guard telemetry (feat 64edea3, 11-21) per its only
mentions (scripts/verify-telemetry.sh + Makefile:366), runs `make verify` twice, and
reads the resulting `h3_verify.prom`.

| Artifact | What it is | sha256 (first 12) |
|---|---|---|
| cold.out | stdout of first `make verify` (cold): ALL PASS, verdict census 2 verified / 0 unverified | a9c4da5acf8d |
| cold.err | stderr of cold run: the first-run WARN `missing or corrupt prior counter; starting at 1` + WALL_COLD=1.31 EXIT_COLD=0 | 297fbd4a434e |
| warm.out | stdout of second run — byte-identical to cold.out (verify stdout carries no timestamps; prom state lives in DEST, not stdout) | a9c4da5acf8d |
| warm.err | stderr of warm run: WALL_WARM=1.44 EXIT_WARM=0, no WARN (counter read OK on second run) | 5e41dce8b20b |
| prom-sample.prom | h3_verify.prom after run 2: counter=2, 9 h3_verify_guard_result gauges (all 1), 9 h3_verify_duration_seconds samples (two are 0 — DF-H3-057) | 2167c5ab143f |

Additional live observations not captured as files (commands re-runnable from repo root):

- `sh scripts/verify-telemetry.sh --selftest` → `verify-telemetry: PASS — nine guards and
  durations, FAIL, SKIP/degrade, counter, unwritable directory`, rc=0.
- `H3_VERIFY_TEXTFILE_DIR=/proc/nope make verify` → exactly 1
  `WARN — textfile directory unavailable or unwritable` line; verify still ends ALL PASS rc=0.
- `sh scripts/verify-telemetry.sh --bogus` → `WARN — unknown mode`, exit 0 (silent no-op).
- `hyperfine -w 1 -m 5 'make verify'` → mean 1.432 s ± 0.142 s (1.249–1.553 s). Warm-only
  environment note: single-worker laptop, DuckBrain census at localhost:3000 reachable.

Rows filed this tick: DF-H3-056 (P2 docs/spec staleness), DF-H3-057 (P3 duration gauge
whole-second zeros), DF-H3-058 (P3 first-run WARN conflates healthy install with corrupt state).
Install leg: closed-as-owned — DF-H3-49 (complete 11-23, bunker-las-03 run-2 audit-corroborated;
evidence artifact `.coding-hermes/evidence/h3-foreman-2026-11-23-13-30-00/df-h3-49-install-leg.md`
present on disk and read before this claim).
Perf: headline op `make verify` 1.432 s mean — not user-feelable, no PERF row, no profile (keisoku law).
