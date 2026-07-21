# S20 — H3 Dashboard & Alerting (OBS-05, OBS-06)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S16 (Structured Logging), S17 (Metrics), S18 (Tracing), S19 (Health Check v2)  
**Last Updated:** 2026-07-21

---

## 1. Overview

With structured logging (S16), metrics (S17), distributed tracing (S18), and health check v2 (S19), every component in the H3 pipeline emits diagnostic data. But data alone isn't observability — operators need a unified view to answer "is the system healthy right now?" and "what broke, and when?"

**This spec defines the H3 Dashboard** — a real-time operational view that pulls data from all 4 observability pillars (logs, metrics, traces, health) into one screen. It also defines the Alerting Rules Engine that watches these data sources and notifies operators when thresholds are breached.

**Design principle:** "Observability without visibility is invisible reliability. The dashboard is the window; alerting is the alarm."

**Scope:** OBS-05 (Dashboard) + OBS-06 (Alerting) on the task board. Covers dashboard architecture, data sources, UI layout, alerting rules engine, notification channels, SDK instrumentation points, CLI surface, and a phased rollout plan.

---

## 2. Dashboard Architecture

### 2.1 Data Flow

```
GET /v1/health ──► Shim ──► GET /v1/dashboard (aggregate) ──► Dashboard HTML (static)
GET /v1/metrics ──►     ◄── Alerting Engine (background eval)
```

The dashboard is a **static HTML page** served from `h3/docs/dashboard.html`. No backend, no framework — just HTML + CSS + vanilla JavaScript that polls the shim's aggregate endpoint.

### 2.2 Aggregate Endpoint: `GET /v1/dashboard`

```json
{
  "status": "ok",
  "timestamp": "2026-07-21T18:44:58Z",
  "shim": {
    "version": "0.1.0", "uptime_seconds": 86400,
    "active_sessions": 12, "total_decisions_processed": 45231,
    "error_rate_1m": 0.02, "error_rate_5m": 0.015,
    "p50_latency_ms": 12.3, "p95_latency_ms": 45.7, "p99_latency_ms": 89.2,
    "throughput_decisions_per_sec": 5.2
  },
  "harnesses": [{
    "id": "echo-go", "endpoint": "http://localhost:9191",
    "status": "healthy", "protocol_version": "1.0",
    "uptime_seconds": 36000, "active_sessions": 3,
    "error_rate_1m": 0.01, "p95_latency_ms": 22.1,
    "throughput_decisions_per_sec": 1.8,
    "capabilities": ["text", "streaming", "auth", "metrics"],
    "models": [{"id": "deepseek-v4-flash", "provider": "deepseek", "status": "available"}]
  }],
  "alerts": {
    "active": 2,
    "firing": [{"id": "alert-001", "severity": "warning", "rule": "harness_latency_p95", "harness": "echo-go", "message": "p95 latency 22.1ms > threshold 20ms", "since": "2026-07-21T18:40:00Z"}]
  }
}
```

### 2.3 Polling: dashboard polls every 15s, alerts evaluated every 15s.

---

## 3. Dashboard UI Layout (5 Panels)

1. **Top Bar** — System overview: shim version, uptime, active sessions, error rate, status indicator.
2. **Active Sessions** — Table: session_id, harness, started_at, decision_count, duration, status (active/idle/ending). Auto-refresh 15s.
3. **Harness Health Grid** — Per-harness: status (🟢/🟡/🔴), uptime, active sessions, error rate, p95 latency, throughput. Color-coded.
4. **Error Breakdown** — Last 1h: error type, count, %, trend sparklines (7 data points, 5-min buckets).
5. **Latency Distribution** — ASCII bar chart: p50/p95/p99/max + distribution buckets + per-harness breakdown.
6. **Active Alerts** — Currently firing alerts: severity, rule name, message, duration.

---

## 4. Alerting Rules Engine

6 default rules in `h3_alerts.yaml`:

| Rule | Severity | Condition | For |
|------|----------|-----------|-----|
| harness_down | critical | harness.status == 'unavailable' | 60s |
| harness_latency_p95 | warning | p95 > 50ms | 120s |
| error_rate_spike | critical | error_rate_5m > 0.05 | 60s |
| shim_high_error_rate | warning | shim.error_rate_5m > 0.03 | 120s |
| session_spike | info | active_sessions > 2x 5-min avg | 30s |
| throughput_drop | warning | throughput < 0.5/sec | 180s |

### Evaluation loop (every 15s):
1. Collect: shim metrics + all harness health/metrics
2. Evaluate each rule → if true: start timer → if timer >= "for": fire + notify
3. If false and was firing: resolve + notify
4. Duplicate suppression: already-firing alerts don't re-notify

### Notification channels: Telegram Bot API, SMTP email, HTTP webhook. Log notifier always on.

---

## 5. SDK Middleware Contracts

All 3 SDKs expose:

```
DashboardCollector interface:
  - SessionSnapshots() → []SessionSnapshot
  - ActiveAlertCount() → int
  - RegisterAlertCallback(func(AlertStateChange))
```

---

## 6. Test Plan

- 12 unit tests (DASH-01 through DASH-12): endpoint, alert evaluation, suppression, resolution, notification
- 6 integration tests (DASH-I-01 through DASH-I-06): full flow, multi-harness, latency/error alerts, silence
- 3 HTML tests (DASH-HTML-01 through DASH-HTML-03): rendering, color coding, responsive

---

## 7. Performance Budget

| Metric | Target |
|--------|--------|
| Dashboard endpoint | <50ms p95 |
| Page load | <500ms |
| Polling overhead | <1% CPU |
| Alert evaluation | <10ms |
| Dashboard memory | <10MB browser |

---

## 8. Security

- Dashboard endpoint auth-protected (S12). Unauthenticated → `{"status":"ok"}` only.
- No session content, no user data, no tokens in dashboard or alert messages.
- Static HTML — no server-side rendering, no injection surface.

---

## 9. Migration Plan (4 Phases)

1. Dashboard endpoint (shim: `h3/dashboard.py`, `GET /v1/dashboard`)
2. Dashboard HTML (`h3/docs/dashboard.html`, static SPA)
3. Alerting engine (shim: `h3/alerts.py`, `h3_alerts.yaml`, notifiers)
4. SDK middleware + integration tests

---

## 10. CLI Surface

```bash
hermes h3 dashboard [--port 8080] [--open]
hermes h3 alerts show [--all|--harness] [--json]
hermes h3 alerts history [--limit 50] [--json]
hermes h3 alerts silence <rule-id> --for <duration>
hermes h3 alerts test-notify --channel <telegram|email|webhook>
hermes h3 dashboard data [--json]
```

---

## 11. File Inventory

```
h3/specs/20-Dashboard-Alerting.md
h3/docs/dashboard.html
shim/src/h3_shim/dashboard.py, alerts.py, alerts_config.yaml
shim/src/h3_shim/notifiers/{__init__,base,telegram,email,webhook,log}.py
shim/tests/test_dashboard_endpoint.py, test_alerts_engine.py, test_dashboard_integration.py
sdk-go/dashboard/collector.go
sdk-python/h3_sdk/dashboard.py
sdk-typescript/src/dashboard.ts
```

---

## 12. Acceptance Criteria

**OBS-05 (Dashboard):** GET /v1/dashboard returns correct schema. HTML renders 5 panels. Polls every 15s. Harness status color-coded. Responsive at 768px+.

**OBS-06 (Alerting):** Rules evaluate every 15s. Fire after "for" duration. Resolve + notify on clear. Duplicate suppression. CLI test-notify works. CLI silence works.

---

*Spec 20 of the H3 specification suite. Covers OBS-05 (Dashboard) and OBS-06 (Alerting).*
