# S20 — H3 Operational Dashboard (OBS-05)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S02 (Protocol), S16 (Structured Logging), S17 (Metrics), S18 (Distributed Tracing), S19 (Health Check v2)  
**Last Updated:** 2026-07-21

---

## 1. Overview

S16–S19 define the data collection layer — structured logs, metrics, traces, and health checks flow from the shim and harnesses into a standardized observability pipeline. But data without presentation is raw material without a workshop.

**This spec defines the H3 Operational Dashboard** — a single-pane-of-glass that turns observability data into actionable situational awareness. Operators can see at a glance: which harnesses are healthy, how many sessions are active, where errors cluster, and whether latency is degrading.

**Design principle:** "The dashboard answers the first three questions of any incident — what's broken, how bad is it, and when did it start — without requiring a single grep or jq command."

**Scope:** OBS-05 on the task board. Covers dashboard architecture, data aggregation API, core views (active sessions, harness health, error breakdown, latency heatmap, throughput), UI wireframes, CLI text dashboard variant, backend aggregation layer, and integration with existing metrics/health endpoints. The alerting system (OBS-06) is a separate spec — this spec focuses exclusively on visualization and situational awareness.

**Implementation targets:**
- `h3/` — Dashboard HTML/CSS/JS single-page application
- `shim/` — Dashboard data aggregation API endpoints (`/v1/dashboard`)
- `protocol/` — New optional `/v1/dashboard` endpoint schema

---

## 2. Dashboard Architecture

### 2.1 Data Flow

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Harness 1  │    │   Harness 2  │    │   Harness N  │
│  (echo:9191) │    │ (consensus)  │    │  (custom)    │
│ /v1/health   │    │ /v1/health   │    │ /v1/health   │
│ /v1/metrics  │    │ /v1/metrics  │    │ /v1/metrics  │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       └───────────────────┼───────────────────┘
                           │
                    ┌──────▼───────┐
                    │    Shim      │
                    │  Aggregator  │
                    │ /v1/dashboard│ ← aggregation endpoint
                    │  Dashboard   │ ← static HTML/CSS/JS
                    │  SPA (h3)    │
                    └──────────────┘
```

**Data sources and refresh cadence:**

| Source | What it provides | Refresh |
|--------|-----------------|---------|
| `/v1/health` (v2) | Harness status, model availability, component health, active sessions, uptime, version | 5s poll |
| `/v1/metrics` | Latency quantiles, error rate, throughput, harness health gauges, resource usage | 5s poll |
| Shim internal state | Session registry, decision pipeline status, shim health | In-memory, 1s refresh |
| Shim structured logs | Recent errors, slow decisions (S16 format) | Ring buffer, last N entries |
| Trace data (OTLP) | Link to external trace viewer for deep dives | On-demand |

### 2.2 Deployment Model

**Mode A — Embedded SPA (Recommended):** Single HTML file served by the shim at `/v1/dashboard`. Zero external dependencies. Deployed to GitHub Pages from `h3/` repo.

**Mode B — Standalone CLI:** `hermes h3 dashboard [--json|--text|--watch]` — text-based dashboard for terminal operators.

### 2.3 Aggregation API

```
GET /v1/dashboard?harness=all&window=5m&format=json
```

**Response:**
```json
{
  "timestamp": "2026-07-21T18:45:00Z",
  "harnesses": [{
    "name": "echo",
    "url": "http://localhost:9191",
    "health": {
      "status": "ok",
      "uptime_seconds": 84320,
      "version": "2.1.0",
      "protocol_version": "1.1",
      "active_sessions": 7,
      "component_health": {
        "model_backend": {"status": "ok", "latency_ms": 42},
        "session_store": {"status": "ok", "latency_ms": 3},
        "tool_executor": {"status": "ok", "latency_ms": 11}
      }
    },
    "metrics": {
      "latency": {"p50_ms": 18.2, "p95_ms": 87.5, "p99_ms": 234.1},
      "error_rate": {"1min": 0.02, "5min": 0.01},
      "throughput": {"decisions_per_sec_1min": 3.7},
      "total_decisions": 15234,
      "total_errors": 152
    },
    "recent_errors": [{
      "timestamp": "2026-07-21T18:44:52Z",
      "session_id": "S1",
      "decision_id": "D42",
      "error_type": "harness_timeout",
      "message": "Harness did not respond within 30s"
    }]
  }],
  "aggregate": {
    "total_harnesses": 3,
    "healthy_harnesses": 3,
    "total_active_sessions": 23,
    "total_decisions_1min": 187,
    "global_error_rate_5min": 0.008,
    "shim_uptime_seconds": 125400
  }
}
```

---

## 3. Core Dashboard Views

### 3.1 Fleet Status Bar (Top)

| Widget | Data Source | Visual |
|--------|-----------|--------|
| Harness Status | Health endpoint | Green/Amber/Red circles with count badges |
| Active Sessions | Sum of all harness `active_sessions` | Large number with sparkline (last 15m) |
| Global Error Rate | `global_error_rate_5min` | Percentage with trend arrow |
| Shim Uptime | `shim_uptime_seconds` | Days:hours:minutes |
| Throughput | `total_decisions_1min` | Decisions/min with sparkline |

**Color coding:** 🟢 Green = ok/available | 🟡 Amber = degraded | 🔴 Red = critical/error rate >10% | ⚪ Grey = unknown/unreachable

### 3.2 Harness Detail Cards

Each harness gets a card showing: status + version, active sessions, latency (p50/p95/p99), throughput, error rate with trend, component health, model availability, capabilities, and recent errors (last 5).

### 3.3 Error Breakdown Panel

Groups errors by type and harness over the last 15 minutes. Shows count, share percentage, and trend (↑/↓/→).

### 3.4 Latency Heatmap (Time-Series)

60-column visual heatmap — each column = 1 minute. Each row = a latency band (<50ms through >1000ms). Density indicated by character intensity (· █ ██ ███).

### 3.5 Throughput Timeline

Line chart: decisions/sec (instant) + 1-min moving average overlay over 15-minute window.

### 3.6 Active Sessions Table

Sortable, filterable table: Session ID, Harness, Decisions count, Age, Last Activity. Sessions idle >30s highlighted amber, >2min red.

---

## 4. UI Specification — Web Dashboard

### 4.1 Technology Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| HTML | Single file, semantic | Zero build step, GitHub Pages deployable |
| CSS | Dark theme, CSS custom properties, grid/flexbox | Professional appearance, responsive |
| JS | Vanilla ES6, no framework | Zero dependencies, <50KB |
| Charts | Canvas-based (custom) or Chart.js ESM | Lightweight |
| Data | `fetch()` to shim endpoints | Native, no library |
| Refresh | `setInterval` + visibility API | Pauses when tab hidden |

### 4.2 Layout (Responsive)

```
┌──────────────────────────────────────────────────────────────┐
│  H3 Dashboard                    [auto-refresh 5s ▼] [⚙]     │
├──────────────────────────────────────────────────────────────┤
│  🟢 3 healthy | 🟡 0 degraded | 🔴 0 critical               │
│  23 active sessions | 3.7/sec | 0.8% errors | Uptime 34h     │
├──────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  ┌─────────────────────────────────┐│
│  │ Latency Heatmap     │  │ Error Breakdown (by type)       ││
│  └─────────────────────┘  └─────────────────────────────────┘│
│  ┌─────────────────────┐  ┌─────────────────────────────────┐│
│  │ Throughput Timeline │  │ Error Breakdown (by harness)    ││
│  └─────────────────────┘  └─────────────────────────────────┘│
├──────────────────────────────────────────────────────────────┤
│  [🟢 echo card]  [🟢 consensus card]  [🟢 custom card]       │
├──────────────────────────────────────────────────────────────┤
│  Active Sessions Table (sortable, filterable)                 │
└──────────────────────────────────────────────────────────────┘
```

| Breakpoint | Layout |
|-----------|--------|
| >1200px | 3-column grid |
| 768–1200px | 2-column grid |
| <768px | Single column stacked |

### 4.3 Dark Theme Palette

| Token | Value | Usage |
|-------|-------|-------|
| `--bg-primary` | `#0d1117` | Page background |
| `--bg-card` | `#161b22` | Card background |
| `--border` | `#30363d` | Borders, dividers |
| `--text-primary` | `#e6edf3` | Body text |
| `--text-secondary` | `#8b949e` | Labels |
| `--green` | `#3fb950` | Healthy |
| `--amber` | `#d29922` | Degraded |
| `--red` | `#f85149` | Critical |
| `--blue` | `#58a6ff` | Links |

### 4.4 Accessibility

- All colors paired with icons (not color-only)
- ARIA labels: `aria-label="echo harness — healthy"`
- Keyboard navigation: Tab between cards, Enter to expand
- `aria-live="polite"` region for status change announcements

---

## 5. CLI Dashboard — Text Mode

```
$ hermes h3 dashboard --watch

╔══════════════════════════════════════════════════════════════╗
║  H3 Dashboard — 2026-07-21 18:45 UTC  (refresh: 5s)        ║
╠══════════════════════════════════════════════════════════════╣
║  Fleet: 🟢 3/3 healthy | 23 sessions | 3.7/sec | 0.8% err  ║
╠══════════════════════════════════════════════════════════════╣
║  🟢 echo (v2.1.0)  p50:18ms p95:88ms p99:234ms  1.5% err   ║
║    Sessions: 7  Throughput: 3.7/s  Uptime: 23h 12m          ║
║    Components: model🟢42ms session🟢3ms tools🟢11ms          ║
║  🟢 consensus (v2.0.1)  p50:45ms p95:120ms  0.3% err        ║
║    Sessions: 12  Throughput: 5.2/s  Uptime: 4d 6h           ║
╠══════════════════════════════════════════════════════════════╣
║  Recent Errors (last 15 min):                                ║
║  18:44:52  echo/S1/D42  harness_timeout  30s no response    ║
║  18:42:11  consensus/S3/D18  model_unavailable  503          ║
╠══════════════════════════════════════════════════════════════╣
║  Press q to quit, r to refresh, h for help                  ║
╚══════════════════════════════════════════════════════════════╝
```

**Controls:** q=quit, r=refresh, 1-9=harness detail, e=toggle errors, s=cycle sort, h=help

---

## 6. Backend Aggregation Layer

### 6.1 Aggregation Engine

Shim-based `DashboardAggregator` class: concurrently fetches `/v1/health` + `/v1/metrics` from all registered harnesses, caches results for 5s TTL, computes fleet-level aggregates.

### 6.2 Performance Budget

| Operation | Budget |
|-----------|--------|
| Aggregation (5 harnesses) | <500ms |
| Aggregation (50 harnesses) | <2s |
| JSON serialization | <10ms |
| Memory per harness | <2KB |
| Total memory (100 harnesses) | <200KB |

### 6.3 Caching

5-second TTL cache keyed by `harness_filter:window`. Concurrent clients share cached response — shim fetches once per poll interval.

---

## 7. Integration with Existing Specs

| Spec | Dashboard Consumption |
|------|----------------------|
| S16 (Logging) | Recent errors view, slow decision detection, session replay links |
| S17 (Metrics) | Latency panels, error rate, throughput, harness health gauges |
| S18 (Tracing) | Deep-link to Jaeger/Tempo per trace_id, slowest traces top-10 |
| S19 (Health v2) | Harness status, component health, model availability, capabilities, feature flags |

---

## 8. Error Handling & Degraded States

- **Harness unreachable:** ⚪ Grey status, "Last seen: Ns ago", collapses to red bar after 60s
- **Partial data:** Health shown, metrics shown as "—" with tooltip
- **Shim degraded:** Top banner: "⚠ Shim degraded — session creation throttled"

---

## 9. Security

- `/v1/dashboard` requires Bearer token (S12 auth enforced)
- No message content, no API keys, no stack traces in dashboard responses
- Role-based: Operator sees all views, unauthenticated gets 401

---

## 10. CLI Commands

```
hermes h3 dashboard                # Open text dashboard (--watch mode)
hermes h3 dashboard --json         # Single JSON snapshot, exit
hermes h3 dashboard --watch        # Live-refreshing text dashboard
hermes h3 dashboard --interval 10  # 10-second refresh
hermes h3 dashboard --harness echo # Show only echo harness
hermes h3 dashboard --web          # Start local server, open browser
hermes h3 dashboard --web --port 9090  # Custom port
```

---

## 11. Implementation Plan

| Phase | What | Timeline |
|-------|------|----------|
| Phase 1 | Aggregation API (`h3_shim/dashboard.py`, `/v1/dashboard` endpoint) | Day 1 |
| Phase 2 | Web Dashboard (single-file SPA, dark theme, all views) | Day 1–2 |
| Phase 3 | CLI Dashboard (`hermes h3 dashboard` subcommand) | Day 2 |
| Phase 4 | Production hardening (auth, perf testing, accessibility) | Day 3+ |

---

## 12. Test Scenarios

### Unit Tests (DASH-01 through DASH-12)

| ID | Test |
|----|------|
| DASH-01 | Aggregator collects from 3 mock harnesses |
| DASH-02 | Aggregator with filter `harness=echo` |
| DASH-03 | Aggregator with unreachable harness |
| DASH-04 | Aggregator cache hit within TTL |
| DASH-05 | Aggregator cache expiry after TTL |
| DASH-06 | Error ring buffer overflow |
| DASH-07 | `/v1/dashboard` returns valid JSON |
| DASH-08 | `/v1/dashboard?format=prometheus` |
| DASH-09 | `/v1/dashboard?window=15m` |
| DASH-10 | Dashboard HTML validates (no JS errors) |
| DASH-11 | Dashboard HTML — harness missing metrics shows "—" |
| DASH-12 | CLI `--json` output valid, exits 0 |

### Integration Tests (DASH-I-01 through DASH-I-06)

| ID | Test |
|----|------|
| DASH-I-01 | Dashboard with Go echo harness |
| DASH-I-02 | Dashboard with Python echo harness |
| DASH-I-03 | Dashboard with TS echo harness |
| DASH-I-04 | Dashboard with 2 harnesses simultaneously |
| DASH-I-05 | Harness goes down → dashboard updates within 10s |
| DASH-I-06 | Harness comes back → dashboard recovers |

### Performance Tests (DASH-P-01 through DASH-P-03)

| ID | Test | Expected |
|----|------|----------|
| DASH-P-01 | Aggregation latency (5 harnesses) | <500ms |
| DASH-P-02 | Aggregation latency (50 harnesses) | <2s |
| DASH-P-03 | Dashboard HTML load time | <500ms |

### Security Tests (DASH-S-01 through DASH-S-02)

| ID | Test | Expected |
|----|------|----------|
| DASH-S-01 | Unauthenticated `/v1/dashboard` | 401 |
| DASH-S-02 | Dashboard response has no secrets | Grep clean |

---

## 13. Migration Plan

| Phase | What | Rollback |
|-------|------|----------|
| Phase 1 | Add `/v1/dashboard` endpoint | Remove endpoint |
| Phase 2 | Deploy dashboard HTML to GH Pages | Revert Pages deploy |
| Phase 3 | Add CLI command | Remove subcommand registration |
| Phase 4 | Auth enforcement on dashboard | Remove auth middleware |

No breaking changes — all additions are net-new endpoints and UI.

---

## 14. Future Extensions (Out of Scope)

- Historical time-series database for trend analysis
- Alert correlation (link OBS-06 alerts to dashboard context)
- Custom dashboards (operator-defined widget layouts)
- Multi-shim fleet-level view
- Export/share (PDF snapshot, shareable URL)
- Dark/light theme toggle

---

*End of S20 — H3 Operational Dashboard (OBS-05)*
