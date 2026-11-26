# H3 — Observability Specification

**Audience:** the coding-hermes foreman/worker who will instrument this org.
**Product:** `h3` (`get-h3` GitHub org) — hub repo `/home/kara/get-h3/h3` plus the runnable
repos under `/home/kara/get-h3/` (`shim`, `sdk-go`, `sdk-python`, `sdk-typescript`,
`protocol`) and the four sibling *tools* repos (`logsey`, `pulse`, `lore`, `digest`).
**Audited:** 2026-11-03, on this host (`kara`), by a read-only filesystem audit.
**Out of scope:** modifying service code, and the monitoring stack itself
(`/home/kara/fleet-monitoring`, host `fleet-monitor`).

---

## 0. Verdict in one paragraph

**Update 2026-11-25 (DF-H3-056):** the verdict paragraph below was true when audited on
2026-11-03 and is now **partially stale**: the `h3` hub's `make verify` control plane *does*
emit a scrapeable metric surface. `scripts/verify-telemetry.sh` — wired into the `verify`
target at `Makefile:365-366` — writes `h3_verify.prom` into `H3_VERIFY_TEXTFILE_DIR`
(default `/var/lib/node_exporter/textfile`) with the three `h3_verify_*` families catalogued
in §5.4. §0.1 is the user-facing how-to. The `pulse`/`logsey`/`digest`/`lore` blind spots
described below are unchanged.

**Nothing in the get-h3 org emits a scrapeable metric today.** Zero files under any of the
9 candidate repos import a Prometheus client (`client_golang`, `prometheus_client`,
`prom-client`), register a collector, or serve `/metrics`. The only HTTP listener in the whole
org is `pulse`'s env-gated pprof endpoint — and pprof is not a metric surface. Every product
here is either a **short-lived CLI** (`lore`, `digest`, `h3`'s `make verify` control plane),
a **batch indexer** (`logsey`), or a **library/SDK** (the harness SDKs). The one genuine
long-running daemon, `pulse`, already **writes a machine-readable heartbeat line every few
seconds** to `~/.pulse-data/heartbeat.jsonl` and **nobody ever reads it** — it is the richest
unexported signal in the org, and it is being thrown away 553,374 lines at a time.

The right mechanism for this org is therefore **textfile-collector completion records** for the
CLI/batch lanes and **a small `/metrics` endpoint** for the two HTTP/Long-running surfaces
(`pulse` daemon, `logsey watch`), *not* a scrape of everything on one port. §4 says exactly which.

### 0.1 `make verify` telemetry — how to collect it (live since DF-H3-056)

`make verify` records its own guard results as Prometheus textfile metrics. The writer is
`scripts/verify-telemetry.sh`, invoked by the `verify` target (`Makefile:365-366`); a real
sample of its output is committed at
`.coding-hermes/evidence/h3-dogfood-2026-11-23-14-28-25/prom-sample.prom`.

**Enable it:** the script writes to `H3_VERIFY_TEXTFILE_DIR`
(default `/var/lib/node_exporter/textfile`) and silently skips — a WARN on stderr, verify
still passes — when the directory is absent or unwritable. To collect, point it at a
node_exporter textfile directory:

```sh
sudo mkdir -p /var/lib/node_exporter/textfile
sudo chown node_exporter:node_exporter /var/lib/node_exporter/textfile
export H3_VERIFY_TEXTFILE_DIR=/var/lib/node_exporter/textfile   # default; set only to override
```

**What lands there:** `h3_verify.prom`, rewritten atomically (tmp file + lock directory) on
every `make verify` run. Three metric families:

| Family | Type | Meaning |
|---|---|---|
| `h3_verify_runs_total{target="verify"}` | counter | how many times `make verify` has run |
| `h3_verify_guard_result{guard="..."}` | gauge, 0/1 | 1 = that guard passed clean; 0 = failed, skipped, or degraded. One series per guard: `verify-docs`, `verify-specs`, `verify-count`, `verify-tags`, `verify-json-fences`, `verify-qa-target`, `verify-tick-chain`, `verify-board-header`, `verify-commit-msg` |
| `h3_verify_duration_seconds{guard="..."}` | gauge | wall-clock seconds of that guard's last run |

**Scrape it:** node_exporter's textfile collector (enabled by default) picks the file up
automatically — a normal node_exporter scrape is all that is needed on the host running
`make verify`:

```yaml
# prometheus.yml — on the host that runs make verify
scrape_configs:
  - job_name: node-exporter-h3
    scrape_interval: 15s
    static_configs:
      - targets: ["kara:9100"]
        labels: {product: h3, service: h3-hub, host: kara}
```

Alert on `h3_verify_guard_result == 0` (a red or forever-skipping guard) and on staleness of
`h3_verify_runs_total` (verify stopped running altogether). Guard names and metric families
above are grep-verified against `scripts/verify-telemetry.sh` (the guard list is line 4; the
families are emitted at lines 48-49, 50+69, and 70-71).

---

## 1. What actually runs (ground truth, verified)

| Repo | What it is | Long-running? | HTTP surface | Durable output | Evidence |
|---|---|---|---|---|---|
| `h3` | Spec hub, docs site, board, `make verify` control plane | No — CI/foreman ticks | none served (static site) | `.coding-hermes/board/tasks.jsonl`, `board.jsonl`, `events.jsonl` | `h3/README.md:209-228`, `h3/Makefile:363-377` |
| `shim` | Hermes-side Python plugin: shim loop, 48-test battery, `hermes-h3` CLI | Only when wrapping a Hermes session | **generates** harness servers (FastAPI/Go/Node templates), does not run one itself | pytest/CLI exit codes, SQLite sessions | `shim/src/h3_shim/templates/py/main.py:459,574`, `shim/src/h3_shim/templates/go/main.go:316` |
| `sdk-go` | Harness SDK + echo example | Echo example binds `:9191` when run | `/v1/health`, `/v1/process`, … | none | `h3/README.md:107-116` |
| `sdk-python` | Harness SDK | library | (example only) | none | `h3/README.md:160-167` |
| `sdk-typescript` | Harness SDK (not on npm) | library | (example only) | none | `h3/README.md:167` |
| `protocol` | OpenAPI 3.1 + JSON Schema | no | no | YAML/JSON | `h3/README.md:163` |
| **`logsey`** | Log-corpus indexer: `watch` tails sources into `corpus.jsonl`, `index` builds DuckDB | **Yes — `logsey watch`, every 30 s** (systemd unit shipped) | none | `corpus.jsonl`, `checkpoints.json`, `index.duckdb` | `logsey/systemd/logsey.service:1-8,47`, `logsey/internal/logsey/ingest/checkpoints.go:55-58` |
| **`pulse`** | Metric-log sampler daemon | **Yes — continuous daemon; re-measured running 2026-11-26** | pprof only, env-gated | `~/.pulse-data/pulse-YYYY-MM-DD.jsonl` + `heartbeat.jsonl` | `pulse/cmd/pulse/pprof.go:6-28`; live check: `systemctl --user status pulse.service` (PID and start time are volatile — read them from the live unit, not from this page) |
| **`lore`** | Runbook compiler/validator CLI | No — invoked per command | none | `.lore/validate-history.jsonl` (append-only), stdout JSON | `lore/__main__.py:386-421`, `.lore/validate-history.jsonl` (7 871 lines, 2026-11-18; append-only — a bare number rots) |
| **`digest`** | Daily fleet digest builder; systemd timer **08:00** installed (`../digest/packaging/digest.timer:5` still ships `07:17` — the installed unit is what fires, running `h3-family-digest.sh`) | No — `Type=oneshot` | none | installed unit: `~/.local/share/digest/h3-family-YYYY-MM-DD.md`; packaged script: `../digest/digests/latest.html`, `digest-YYYY-MM-DD.{md,json}` | `../digest/packaging/digest.timer:1-8`, `../digest/packaging/digest.service:36`, installed `h3-digest.timer` |

**What is actually live on this host (a dated snapshot)** — re-measured
2026-11-26T03:33Z (= 2026-11-25 22:33 -05) with read-only probes (`systemctl --user
list-units`, `ps`, `ss`, `curl`, `wc -l`). This page is a snapshot, not a live dashboard:
volatile values (PIDs, start times, line counts, ephemeral listeners) rot between
re-measures — the figures below already replaced a stale 2026-11-17 set, and they will rot
again. Every volatile figure below carries its measurement date inline; when you need a
current value, re-run the named command instead of trusting the page. Prefer the
restart-surviving facts (what each component is and how to check it live) over the
numbers.

- `pulse` — running as a systemd user service: `pulse.service` active since
  Mon 2026-11-23 08:22:40 -05, main PID 1774955 (volatile — re-run
  `systemctl --user status pulse.service` for the current PID/start time). Heartbeat
  file: `wc -l ~/.pulse-data/heartbeat.jsonl` → `466,613` lines at
  `2026-11-25 22:33 -05` — a dated snapshot, not a current figure: the file is
  append-only but the retention trimmer (§3.4) drops old history, so it both grows
  and shrinks (it held `577,372` lines at the 2026-11-18 reading). What does not rot
  is the last line's `ts` (`2026-11-26T03:33:52Z` at that reading): if that
  timestamp is within ~2× the fastest sampling interval of your clock, the daemon
  is alive right now — that check is the durable liveness signal.
- `logsey watch` — running, not absent. `systemctl --user list-units | grep logsey` →
  `logsey-watch.service loaded active running` (ExecStart `/home/kara/.local/bin/logsey watch`,
  `ActiveEnterTimestamp Mon 2026-11-23 08:22:40 -05`, PID 1774939 — PID/start time
  volatile, re-run the status command). `logsey-index.timer loaded active running`
  (`OnCalendar=*:0/30` — every 30 minutes); `logsey-index.service` was mid-rebuild
  (`activating`) at the 2026-11-26T03:33Z reading, which is normal for that timer.
  `~/.local/share/logsey/checkpoints.json` is being written continuously (18,967
  bytes, mtime `2026-11-25 22:34:41 -05`), so the loop's checkpoints are real.
  Corpus: `wc -l ~/.local/share/logsey/corpus.jsonl` → `10,298,773` lines at
  `2026-11-25 22:33 -05` (dated snapshot — append-only, grows by ~1k lines/minute
  while `watch` tails; re-run the command).
- `digest` — the h3-family chain is installed, scheduled, and producing fresh
  artifacts. `systemctl --user list-timers | grep digest` → `h3-digest.timer`
  active waiting (daily 08:00; last fired Wed 2026-11-25 08:00:00 -05, next Thu
  2026-11-26 08:00:00 -05) and `h3-digest.service loaded inactive dead` since
  Wed 2026-11-25 08:00:11 -05 (the normal oneshot state between runs). A second
  timer `h3-digest-liveness.timer` (daily 09:00) exists. The **installed** unit runs
  `ExecStart=/home/kara/.local/bin/h3-family-digest.sh`, whose output dir is
  `/home/kara/.local/share/digest`: `ls -1t ~/.local/share/digest/` →
  `h3-family-2026-11-25.md` (mtime `2026-11-25 08:00 -05`),
  `h3-family-2026-11-24.md`, `h3-family-2026-11-23.md` — a fresh artifact every
  morning, so timer → artifact works. **Honest failure at the same reading:** the
  sibling generic unit `digest.service` (daily 07:17) is `loaded failed` —
  `Result: exit-code`, status 127, since Wed 2026-11-25 07:17:00 -05 — so check
  both units, not just the h3 one, before calling digest healthy. Do **not** judge
  the timers by the repo-local `digests/` dir of the sibling `get-h3/digest`
  checkout (`../digest/digests/`, newest `digest-2026-10-24.md`): that is a
  manually-run output of a different script, not these units'.
- `lore` — scheduled weekly, not "no cadence". `systemctl --user list-timers | grep
  lore` → `lore-validate.timer loaded active waiting` (`OnCalendar=Mon *-*-* 07:30:00`
  — every Monday 07:30; last fired Mon 2026-11-23 07:56:59 -05, next Mon 2026-11-30),
  `lore-validate.service loaded inactive dead` (the oneshot between runs). A second
  timer `lore-dep-drift.timer` (Mon 07:45) exists. `h3`'s `make verify` control
  plane has no unit and runs only on CI/foreman ticks.
- A harness on `:9191` — **nothing is listening** at `2026-11-26T03:33Z`:
  `ss -ltn | grep 9191` → empty, and `curl --max-time 3 http://localhost:9191/health`
  → no response. The 2026-11-18 reading found a `shim`-venv harness (pid 1040050,
  `~/.hermes/stand-in/docs/h3/qs/my-harnesses/h3-harness-py/main.py`) answering 200 —
  that was a manually started example, not a service, and it has since exited. The
  sdk-go echo example binds `:9191` **only while someone runs it**; treat any
  `:9191` answer as a manual session and verify with the two commands above rather
  than trusting this page either way.

The earlier conclusion — "three of five runnable surfaces silent and unmonitored" —
is obsolete. Re-measured 2026-11-26T03:33Z: `pulse` and `logsey watch` are both
running as systemd user services (both up since Mon 2026-11-23 08:22 -05),
`h3-digest` and `lore` have installed timers firing on schedule (with the generic
`digest.service` unit failing — dated above), and nothing listens on `:9191`. Only
`h3`'s `make verify` control plane runs on invocation (CI/foreman ticks) — by
design. What survives is the monitoring gap, and that is the real finding: none of
these surfaces exports a scrapeable `/metrics`, and `pulse`'s heartbeat — hundreds
of thousands of append-only lines (466,613 at `2026-11-25 22:33 -05`, trimmed and
still growing) — is still never read. Running is not the same as monitored.

---

## 2. What "healthy" means, per surface

| Surface | Healthy means | Today's only proof |
|---|---|---|
| `pulse` daemon | sampling at the configured intervals, within the ≤1 % CPU / ≤100 MB-day-disk budget, heartbeat line within ~2× fastest interval, zero silent classes | a human greps `heartbeat.jsonl` by hand |
| `logsey watch` | `last_tick` in `checkpoints.json` < 60 s old, corpus growing, per-source failure counters flat | `logsey status` (human-invoked only) |
| `digest` | one artifact written per day, exit 0, Money/Ops sources present, not stale > 24 h | file mtime in `digests/` |
| `lore` | gate/validate commands exit 0 on the runbook corpus; validate history append succeeds | `.lore/validate-history.jsonl` tail |
| `h3` hub | `make verify` passes on the published tip; board header in sync | CI + foreman narrative |
| harness SDKs | compliance 48/48; end-to-end loop completes | test battery output, per run |

---

## 3. What is NOT emitted today (the blind spots, with the code that holds the state)

Each line names the place where the state *exists* and is never exported.

1. **`pulse` sampler cost and throttling** — `internal/daemon/budget.go:113-190` computes
   `OverCPU/OverRSS/OverDisk`, the *Over* overshoot amounts, and an EMA sustained ratio. The
   daemon then writes it only into a heartbeat JSON line (`internal/daemon/daemon.go:712-741`)
   and throws it away. Throttle events (`throttle_count`, `throttle_reason: ["cpu"]` currently
   at 2268) are the single best signal that the sampler is *itself* the problem — and there is
   no alert on them.
2. **`pulse` per-class sample/error rates** — `heartbeat.jsonl` carries
   `load_samples/load_errors`, `rss_*`, `conns_*`, `disk_*`, `events_*`
   (observed: `load_errors: 2797`, `disk_errors: 280`, `events_errors: 93` on the last line).
   There are 2797 load-sampling failures with **zero** visibility in any dashboard.
3. **`pulse` silence events** — `internal/daemon/watchdog.go:91-250` writes
   `{"kind":"silence","class":…}` lines for classes that stopped producing samples. A class
   going dark is exactly "the thing stopped working"; it is only greppable.
4. **`pulse` heartbeat retention trims** — `internal/daemon/heartbeat_retention.go:16-31`
   writes `{"kind":"heartbeat-trim"}` when it drops history. Silent data loss by design.
5. **`logsey` liveness** — `internal/cli/status_cmd.go:62-77` computes exactly the right
   verdict (`running` / `not running`, `2×watcherInterval` staleness) — **inside a CLI a human
   must type**. The state is `checkpoints.json:last_tick` (`internal/logsey/ingest/checkpoints.go:55`).
6. **`logsey` suspended sources** — `internal/logsey/ingest/checkpoints.go:37-44`
   `FailureState{Runs, Offset, HadData, Path, Size, MtimeNs}` tracks a source parked at a held
   offset after repeated parse failures. A source can be *silently* not ingested forever.
7. **`logsey` ingest yield** — nothing counts lines indexed, bytes read, per-source lag
   (`size - offset`), or index rebuild duration. `logsey status` prints entry counts
   (`status_cmd.go:55-60`) only when a human asks.
8. **`digest` source degradation** — `digest/digest/__main__.py:208-221,291` (sibling
   `get-h3/digest` checkout; the h3 repo has no `digest/` dir) deliberately renders `no data`
   rather than a fabricated zero when a source is absent — an honest artifact, but there is no
   counter for *how many* sections degraded. The installed unit does write a fresh
   `~/.local/share/digest/h3-family-YYYY-MM-DD.md` every morning at 08:00, yet nothing alerts if
   a morning is skipped: no `last_run` metric, no freshness assertion, so a missed firing would
   be noticed only by a human opening the dir.
9. **`lore` gate outcomes** — `.lore/validate-history.jsonl` appends
   `{class_id, drifted_orders, executed_count, outcomes, honesty_label, total_checks}`
   (`lore/__main__.py:407-421`). Failures are recorded and never counted.
10. **`h3` control-plane gates** — `make verify` fans out 9 guards + a verdict census
    (`h3/Makefile:377`); each prints PASS/FAIL/SKIP to stdout and no result summary exists
    outside the CI check. A guard that starts SKIPping forever is invisible.
    **Update 2026-11-25 (DF-H3-056):** partially closed — `scripts/verify-telemetry.sh` now
    records per-guard verdicts and durations to the textfile (§0.1), so a forever-skipping
    guard is visible as `h3_verify_guard_result{guard="..."} 0`.
11. **All four repos ship `gitreins` usage records** (`.gitreins/usage.jsonl`) — per-command
    artefacts that no exporter reads.

---

## 4. Exposure mechanism (decided per surface, not one-size-fits-all)

| Surface | Mechanism | Why |
|---|---|---|
| `pulse` daemon | **`/metrics` on a new loopback HTTP listener in the existing pprof server pattern** (`client_golang` + `promhttp`), plus a **textfile** mirror of the alert-relevant gauges so a dead process still leaves its last value | It is a Go daemon that already owns a private listener (`pprof.go:46-70`); the 1 s sampling loop can update counters with no new goroutine |
| `logsey watch` | **`/metrics` on a loopback listener inside the `watch` loop** (`client_golang` + `promhttp`), *and* a textfile completion record per tick | Long-running, so a scrape is correct; the textfile keeps a record when it is down |
| `digest` | **textfile completion record only** written at end of every build (`--out` sibling `.prom`), plus pushgateway if fleet-monitor has one | `Type=oneshot` (`digest.service:4`); a `/metrics` endpoint would be un-scrapeable 99.9 % of the time — the wrong answer |
| `lore` | **textfile completion record** per `gate`/`validate` invocation | CLI, exited before any scrape |
| `h3` `make verify` | **textfile completion record** written by a single `verify` recipe post-step (Makefile:365-368) (`scripts/`) — one line per guard with its verdict | Control-plane gates are the "is the product still buildable" signal; the record is what the scraper can see |
| `sdk-*`, `protocol` | **not instrumented as a service** — they are libraries; the harness that embeds them owns the metrics. Emit the SDK contract metrics from the scaffold template (§5.4) so every scaffolded harness reports for free | Instrumenting a library without a running process produces nothing |

**Naming:** `<product>_<subsystem>_<thing>_<unit>`. **Labels stay low-cardinality**: `host`,
`product`, `service`, `class`, `source`, `outcome`, `lang`, `guard`. Never a `session_id`,
`decision_id`, `class_id` beyond the ~dozens alive, prompt, path, or timestamp.

**Collection path (fleet-monitor):** agents on this host push via `remote_write`; a scrape-only
surface needs a job in `/root/fleet-monitoring/prometheus/prometheus.yml` plus a host label.
The spec therefore requires **both** a scrape config block (quoted in §6 so the monitoring
owner can paste it) **and** node_exporter's `--collector.textfile.directory`-style pickup, so
the org works on a host whose only path is PUSH. Exact labels: `host="kara"`, `product="h3"`,
`service="<pulse|logsey|digest|lore|h3-hub>"`.

---

## 5. Metric catalogue

### 5.1 `pulse` — the sampler daemon (P0; largest blind spot, already produces all the data)

| Metric | Type | Unit | Labels | Question answered |
|---|---|---|---|---|
| `pulse_sampler_samples_total` | counter | samples | `class` (`load`,`rss`,`conns`,`disk`,`events`) | How much work is the sampler actually doing? |
| `pulse_sampler_errors_total` | counter | errors | `class` | How often does a sample fail, and for which class? |
| `pulse_sampler_throttle_total` | counter | events | `reason` (`cpu`,`rss`,`disk`) | Is the sampler throttling itself, and why? |
| `pulse_budget_ratio` | gauge | ratio (0-1+) | `budget` (`cpu`,`rss`,`disk`) | Are we inside the ≤1 % / ≤100 MB budget at scrape time (sustained EMA)? |
| `pulse_budget_over` | gauge | bool | `budget` | Is a budget breached (drives alerting, mirrors `OverNames`)? |
| `pulse_cpu_percent` | gauge | percent of one core | — | What does the daemon cost? |
| `pulse_rss_bytes` | gauge | bytes | — | Is it leaking? |
| `pulse_disk_bytes_per_day` | gauge | bytes/day | — | Are we about to breach the disk budget? |
| `pulse_heartbeat_age_seconds` | gauge | seconds | — | Is the watchdog still alive? (self-staleness) |
| `pulse_silence_total` | counter | episodes | `class` | Which sensor class went dark? |
| `pulse_heartbeat_trim_total` | counter | trims | — | How much heartbeat history was dropped? |
| `pulse_up` | gauge | bool | — | Process liveness for `up{}`-style alerting |

Source of every value: `internal/daemon/budget.go` (`BudgetReport`), `daemon.go:712-741`
(`liveness{Stats, intervals}`), `watchdog.go` (`silenceLine`), `heartbeat_retention.go`
(`HeartbeatTrimKind`).

### 5.2 `logsey` — the corpus tailer

| Metric | Type | Unit | Labels | Question answered |
|---|---|---|---|---|
| `logsey_watch_up` | gauge | bool | — | Is the tailer running? |
| `logsey_watch_tick_age_seconds` | gauge | seconds | — | When did it last tick (= `now - last_tick`)? |
| `logsey_watch_tick_total` | counter | ticks | — | Is it ticking at 30 s cadence? |
| `logsey_ingest_lines_total` | counter | lines | `source_class` (`journald`,`file`,`jsonl`) | How much data is flowing? |
| `logsey_ingest_parse_errors_total` | counter | lines | `source_class` | Are sources producing unparseable lines? |
| `logsey_ingest_lag_bytes` | gauge | bytes | `source` (registered name, ≤ tens) | Which source is falling behind (`size - offset`)? |
| `logsey_source_suspended` | gauge | bool | `source` | Is a source parked on repeated failures (`FailureState.Runs ≥ N`)? |
| `logsey_source_failure_runs` | gauge | runs | `source` | How close to suspension? |
| `logsey_corpus_bytes` | gauge | bytes | `format` (`jsonl`,`duckdb`) | Is storage growing unbounded (RETENTION)? |
| `logsey_index_rebuild_seconds` | histogram | seconds | — | How long does a rebuild block queries? |
| `logsey_index_stale` | gauge | bool | — | Is the derived index behind the corpus? |

Source: `internal/cli/watch_cmd.go`, `internal/cli/status_cmd.go:55-77`,
`internal/logsey/ingest/checkpoints.go:37-58`, `internal/logsey/duckidx/update.go:367`.

### 5.3 `digest` — the daily artifact builder (oneshot → textfile)

| Metric | Type | Unit | Labels | Question answered |
|---|---|---|---|---|
| `digest_build_success_timestamp_seconds` | gauge | unix seconds | — | When did the last build succeed? (primary staleness alert) |
| `digest_build_duration_seconds` | gauge | seconds | — | Did the build get slower? |
| `digest_build_exit_code` | gauge | code | — | Did it fail? |
| `digest_sections_degraded` | gauge | count | `section` | Which sections rendered `no data` (source down) vs genuinely zero? |
| `digest_rows_ingested_total` | counter | rows | `section` | Is the input volume sane vs yesterday? |
| `digest_delivery_success` | gauge | bool | `channel` (`telegram`,`file`) | Did the artifact reach the operator? |

Source: `digest/digest/__main__.py:208-253`, `digest/render.py:36`, `digest/send.py`.

### 5.4 `lore`, `h3`, and the harness SDKs

| Metric | Type | Unit | Labels | Question answered |
|---|---|---|---|---|
| `lore_gate_runs_total` | counter | runs | `outcome` (`allow`,`deny`,`error`) | How often does the gate block? |
| `lore_validate_checks_total` | counter | checks | `outcome` | Are runbook commands still live? |
| `lore_validate_drift_total` | counter | drifted orders | `class_id` (registry-bounded, ~20) | Which runbooks have rotted? |
| `lore_run_duration_seconds` | histogram | seconds | `command` (`gate`,`validate`,`compile`) | Cost of a lookup |
| `h3_verify_runs_total` | counter | runs | `target` (`verify` — the only value emitted today) | Is the hub's control plane exercised, and how often? |
| `h3_verify_guard_result` | gauge | 0/1 | `guard` (9 fixed names) | Which guard is red (or SKIPping forever)? |
| `h3_verify_duration_seconds` | gauge | seconds | `guard` | Did a guard start hanging? |
| `h3_harness_requests_total` | counter | requests | `endpoint`,`decision`,`lang` | *(SDK contract, emitted by scaffolded harnesses)* is the loop doing work? |
| `h3_harness_request_duration_seconds` | histogram | seconds | `endpoint`,`lang` | p50/p95/p99 decision latency (S17's core metric) |
| `h3_harness_errors_total` | counter | errors | `endpoint`,`status_class` (`4xx`,`5xx`) | Error rate |
| `h3_harness_sessions_active` | gauge | sessions | `lang` | Concurrent sessions (capacity) |

Note: `specs/17-Metrics-Performance-Monitoring.md` and `specs/16-Observability-Structured-Logging.md`
already *specify* these harness metrics (latency p50/p95/p99, error rate, throughput, uptime) and
mark implementation targets on `shim` (`h3/metrics.py`) and all three SDKs. **None of it exists**:
`shim/src/h3_shim/` has no `metrics.py` and no SDK repo has a `metrics.*` file. This spec
catalogs them, but they are **P2 — after the operational blind spots**, because no harness is
deployed here; the ops lanes are what actually break.

Implemented (DF-H3-056, 2026-11-25): the three `h3_verify_*` families above are **live** —
`scripts/verify-telemetry.sh` writes them on every `make verify` run; see §0.1 for collection.
The `h3_harness_*` SDK rows remain unimplemented (P2).

---

## 6. Collection path and exact scrape config

For every surface that serves `/metrics`, bind **loopback only** (the pprof precedent,
`pulse/cmd/pulse/pprof.go:47-60`) and let the co-located collector scrape it. For fleet-monitor
(a separate host), use the remote agent; the job below is the scrape form.

```yaml
# proposed addition to /root/fleet-monitoring/prometheus/prometheus.yml
# (owner applies; this audit does not touch the monitoring stack)
scrape_configs:
  - job_name: h3-pulse
    scrape_interval: 15s
    static_configs:
      - targets: ["kara:9161"]
        labels: {product: h3, service: pulse, host: kara}
  - job_name: h3-logsey
    scrape_interval: 30s
    static_configs:
      - targets: ["kara:9162"]
        labels: {product: h3, service: logsey, host: kara}
```

Textfile lanes (`digest`, `lore`, `h3` verify) write
`/var/lib/node_exporter/textfile/h3_<service>.prom` atomically (`.tmp` + rename, the
`heartbeat_retention.go` writer's own discipline) and are picked up by node_exporter's
textfile collector; on a push-only host the same file is POSTed to the agent's pushgateway
with `job="h3-textfile"` and the three labels above.

---

## 7. Verification — what "done" looks like

Run these in order; a reviewer who gets all of them green may close the rows.

1. **Endpoint exists and carries the family**
   ```bash
   curl -sf http://127.0.0.1:9161/metrics | grep -c '^pulse_'          # expect >= 11
   curl -sf http://127.0.0.1:9162/metrics | grep -c '^logsey_'         # expect >= 11
   curl -sf http://127.0.0.1:9161/metrics | grep -E 'pulse_sampler_(samples|errors)_total\{class="load"'
   ```
2. **Values are real, not zero-filled.** After 60 s:
   ```promql
   rate(pulse_sampler_samples_total[5m]) > 0                          # the loop is running
   increase(pulse_sampler_errors_total[1h])                          # must equal heartbeat error deltas within 2%
   pulse_budget_ratio{budget="cpu"} < 1                              # inside budget, or alert fires
   time() - pulse_heartbeat_age_seconds < 60
   ```
3. **Cross-check against the file it replaces** (this is the anti-fabrication check):
   ```bash
   tail -1 ~/.pulse-data/heartbeat.jsonl | jq '.load_errors,.throttle_count,.cpu_percent'
   curl -s http://127.0.0.1:9161/metrics | grep -E '^pulse_(cpu_percent|sampler_errors_total|sampler_throttle_total)'
   ```
   The scrape's cumulative values must be ≥ the heartbeat's snapshot and grow monotonically.
4. **Unimplemented Alerts genuinely fire** — stop the daemon, wait 2× scrape interval:
   ```promql
   up{job="h3-pulse"} == 0    or    absent(pulse_up)
   ```
5. **Staleness alert on the oneshot lanes** — the alert that would have caught the 10-day
   digest gap:
   ```promql
   time() - digest_build_success_timestamp_seconds > 86400*1.5
   time() - logsey_watch_tick_age_seconds > 120
   ```
6. **Textfile scrape survived a restart**
   ```bash
   ls -l /var/lib/node_exporter/textfile/h3_*.prom   # mtime <= last run, no .tmp leftovers
   ```
7. **Cardinality guard** — the whole org must stay under 200 series:
   ```promql
   count by (__name__)({product="h3"})   # no name with more than ~40 series
   ```

---

## 8. Deliberately NOT instrumented (and why)

- **Per-session / per-decision ids** — `session_id`, `decision_id` are unbounded; they belong in
  the structured logs specified by `specs/16-Observability-Structured-Logging.md`, never in labels.
- **Per-source file paths** in `logsey` — paths are high-cardinality and leak directory layout;
  use the registered source *name* only, and `source_class` for aggregates.
- **Per-runbook / per-incident ids** in `lore` — `class_id` is registry-bounded today (~20) so it is
  allowed, but a free-form id must not become a label.
- **Static-site build / docs size** in `h3` — `make verify` guards already fail the build; a metric
  adds no decision.
- **`protocol` and SDK libraries themselves** — no running process. Their contract metrics are
  emitted by whatever harness embeds them (§5.4).
- **Metric values embedded in log lines** — `logsey`'s corpus is not a monitoring backend; label
  the lines instead of scraping it.

---

## 9. Open questions / unverified

- `logsey`'s `watch` loop is the only *intended* daemon in this org besides `pulse`; **it is
  installed and running here** (`logsey-watch.service`, active since Mon 2026-11-23
  08:22:40 -05 as re-measured 2026-11-26T03:33Z; the PID is volatile —
  `systemctl --user status logsey-watch.service` shows the current one), and its live
  `~/.local/share/logsey/checkpoints.json` exists (18,967 bytes, mtime
  `2026-11-25 22:34:41 -05`, continuously rewritten), so the loop's checkpoints are real,
  not hypothetical. What
  remains unverified is narrower: its metric names above are derived from code, not observed
  traffic — nobody has scraped the emitted counters.
- Whether fleet-monitor already has a pushgateway endpoint reachable from this host was not
  verified (no network/tool access in the audit) — the textfile path is specified as the
  fallback, but the exact URL and token are the monitoring owner's to supply.
- The `h3` repo's owner has not said whether the `verify` textfile writer is in scope for the
  hub repo (it is a `scripts/` addition); board row §10-5 is filed as a proposal with that caveat.
  **Resolved 2026-11-25 (DF-H3-056):** the writer exists in the hub repo
  (`scripts/verify-telemetry.sh`) and is wired into the `verify` target (`Makefile:365-366`) —
  see §0.1.
