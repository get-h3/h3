# Tick receipt — h3-foreman-2026-11-21-01-05-08

Row: H3-OBS-02 (pulse metric family + node_exporter textfile mirror)
Owner repo: get-h3/pulse (cross-repo work; the fix lives where the code lives)

## Landed
- pulse commit `22834d321527ec4fe6ef6043501335ca22dec6ea` on `main`, pushed (`git rev-list --count origin/main..HEAD` = 0).
- Worker chain: `0db35c9` (pre-tick) -> `3326db8` (worker commit) -> `22834d32` (worker amend, tests only;
  `git diff --stat 3326db8..22834d3` confined to `*_test.go`).
- h3-repo bookkeeping: board header re-pinned `3766b6d` -> `6534776` (`make board-close`) because the previous
  tick skipped closeout and `make verify` was red on a stale header; committed alone and pushed.

## Gates at final pulse HEAD (22834d32)
- `go build ./...` rc=0
- `go test ./...` rc=0
- `gofmt -l` empty
- `go vet ./...` rc=0

## Live acceptance (this host, after `bash scripts/install.sh --source /home/kara/get-h3/pulse`, INSTALL_RC=0)
- `curl -sf -m 5 http://127.0.0.1:9161/metrics` rc=0 — 30 `pulse_` sample lines over 12 families, including
  `pulse_sampler_throttle_total{reason}`, `pulse_budget_over{budget}`, `pulse_cpu_percent`, `pulse_rss_bytes`,
  `pulse_disk_bytes_per_day`, `pulse_silence_total{class}`, `pulse_heartbeat_trim_total`,
  `pulse_heartbeat_age_seconds`.
- `/var/lib/node_exporter/textfile/h3_pulse.prom` present with exactly 3 `pulse_budget_over` lines.
- Kill test: `systemctl --user stop pulse.service` -> textfile survived with 3 lines; `start` -> active.

## Not proven here (named, not claimed)
- A non-zero `increase(pulse_sampler_throttle_total[1h])` needs a real throttle episode. The heartbeat record
  since restart shows `throttle_count: 0`, consistent with the live counter (0), so the two agree but the
  increase leg is not exercised.
- Fleet Prometheus `http://100.122.154.108:9090` is Ready but `api/v1/targets` carries **no pulse job**, so
  `pulse_up` / `pulse_budget_over` cannot be queried monitoring-side yet. That is a monitoring-side follow-up.
- The installed binary was built from `3326db8`, whose non-test tree is identical to `22834d32`.

## Judging
- GitReins run in the owner repo (pulse): run dir `817abc73`, overall PASS (tier1 PASS, tier2 PASS).
  The CLI line `Verdict saved: 9c3e36f5` is a verdict id, not the history run dir.
