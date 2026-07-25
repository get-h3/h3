<!--
  ⚠️  BOARD FORMAT — coding-hermes-model-router v1.3 (2026-07-24)
  All tasks MUST use matrix format: | ID | Task | Pri | Cpx | Deps | Tags | Model | Reasoning | Fallback |
  Before editing this file, load the skill: skill_view(name='coding-hermes-model-router')
  Validate: python3 ~/.hermes/scripts/validate-board-format.py .coding-hermes/tasks.md
- [ ] **GITREINS-JUDGE — Configure LLM evaluator for commit quality review**
  | 🔴 Critical | — | — | deepseek-v4-flash @ deepseek-foreman | GITREINS_LLM_API_KEY in ~/.hermes/.env | foreman-direct |

  Run: `python3 ~/.hermes/scripts/check-gitreins-judge.py .` to verify.
  Default limits (adjust per-project based on codebase size and task complexity):
  - Fast/small projects: `max_iterations: 50`, `max_time: 10m`, tokens: `0.2M/0.4M`
  - Large repos (Go monorepos, 100+ files): `max_iterations: 100`, `max_time: 30m`, tokens: `1M/2M`
  - C++/Rust (slow compiles): `max_time: 30m` minimum
  - Scheduler/production infra: `max_time: 30m`, tokens: `1M/2M`
  Supervisor auto-flags projects where limits are too low for codebase size.

| 🔴 Critical | — | — | deepseek-v4-flash @ deepseek-foreman | GITREINS_LLM_API_KEY in ~/.hermes/.env | foreman-direct |

  Run: `python3 ~/.hermes/scripts/check-gitreins-judge.py .` to verify.
  If missing, create/edit .gitreins/config.yaml with evaluator section using deepseek-v4-flash.
  This is CRITICAL for code quality — no automated review of worker output without it.

  NEVER remove the matrix header row or NEVER-DONE / E2E-001 fixtures.
-->

# h3 — Model Router Task Matrix

> **Core purpose:** H3 protocol — standardized interface between Hermes agents and external harnesses. OpenAPI 3.1 protocol, 3 SDKs (Go/Python/TypeScript), shim plugin, test battery, compliance certification.
> **Status:** Phases 0-6 + DEPLOY complete. 43/43 test battery. 19 phases, 150+ tasks.

```
ID | Task | Pri | Cpx | Deps | Tags | Model | Reasoning | Fallback
```

## Active — Quality Verification (QV)

| ID | Task | Pri | Cpx | Deps | Tags | Model | Reasoning | Fallback |
|----|------|-----|-----|------|------|-------|-----------|----------|
| QV-E2E-01 | Go echo: process→text→result→text→result→end — full protocol loop verification | HIGH | 3 | — | e2e,go,testing | GPT-5.6 Luna | Testing/e2e: full protocol loop across Go echo harness | Step 3.7 Flash |
| QV-E2E-02 | Python minimal: process→text→result→text→result→end — full protocol loop | HIGH | 3 | — | e2e,python,testing | GPT-5.6 Luna | Testing/e2e: full protocol loop across Python | Step 3.7 Flash |
| QV-E2E-03 | TypeScript minimal: process→text→result→text→result→end — full protocol loop | HIGH | 3 | — | e2e,typescript,testing | GPT-5.6 Luna | Testing/e2e: full protocol loop across TypeScript | Step 3.7 Flash |
| QV-E2E-04 | Cross-harness: h3-test against all 3 languages simultaneously | MEDIUM | 3 | QV-E2E-01,02,03 | e2e,cross-lang,testing | Step 3.7 Flash | Testing/e2e: cross-language test execution | GPT-5.6 Luna |
| QV-E2E-05 | Harness logs: timestamped METHOD /path STATUS DURATION | LOW | 2 | — | logging,observability | DeepSeek V4 Flash | Simple/boilerplate: structured logging format | — |
| QV-SDK-03 | Python Pydantic validation matches JSON Schema — verify all formats match protocol | MEDIUM | 3 | — | sdk,python,validation | DeepSeek V4 Pro | Architecture/design: schema validation alignment | MiniMax M3 |
| QV-SDK-04 | TS Zod validation matches JSON Schema — verify all formats match protocol | MEDIUM | 3 | — | sdk,typescript,validation | DeepSeek V4 Pro | Architecture/design: schema validation alignment | MiniMax M3 |
| QV-SHIM-01 | h3-test 43/43 against live Go harness — verify with real running harness | HIGH | 2 | — | shim,testing,go | Step 3.7 Flash | Testing/e2e: test battery against live harness | GPT-5.6 Luna |
| QV-SHIM-02 | Test report JSON matches TestReport schema — schema compliance | MEDIUM | 2 | — | shim,testing,schema | DeepSeek V4 Flash | Simple: schema compliance check | — |
| QV-SHIM-03 | Shim handles harness timeout gracefully — resilience testing | MEDIUM | 3 | — | shim,resilience,testing | MiniMax M3 | Bug fix: timeout handling, resilience | DeepSeek V4 Pro |
| QV-SHIM-04 | Health check detects dead harness, falls back to native — resilience | MEDIUM | 3 | — | shim,health,fallback | Kimi K3 | Bug fix: health check, fallback mechanism | MiniMax M3 |

## Active — Security & Auth (SEC)

| ID | Task | Pri | Cpx | Deps | Tags | Model | Reasoning | Fallback |
|----|------|-----|-----|------|------|-------|-----------|----------|
| SEC-01 | Design: harness API key / token auth model | HIGH | 3 | — | security,auth,design | DeepSeek V4 Pro | Architecture/design: security model design | GPT-5.6 Sol |
| SEC-02 | Implement: Hermes validates harness API key on connect | HIGH | 3 | SEC-01 | security,auth,implementation | DeepSeek V4 Pro | Architecture/design: auth implementation | Kimi K3 |
| SEC-03 | Implement: harness validates Hermes caller identity | HIGH | 3 | SEC-01 | security,auth,implementation | DeepSeek V4 Pro | Architecture/design: mutual auth | Kimi K3 |
| SEC-04 | Token rotation + revocation support | MEDIUM | 3 | SEC-02 | security,token,rotation | MiniMax M3 | Feature: token lifecycle management | DeepSeek V4 Pro |
| SEC-05 | TLS enforcement between Hermes ↔ harness | MEDIUM | 3 | — | security,tls,encryption | DeepSeek V4 Pro | Architecture/design: TLS configuration | MiniMax M3 |
| SEC-06 | Secret handling audit: no credentials leak in logs/errors | MEDIUM | 2 | — | security,audit,secrets | DeepSeek V4 Flash | Simple: security audit | — |
| SEC-07 | Rate limiting spec: max decisions/sec, burst allowance | LOW | 2 | — | security,rate-limit,spec | GPT-5.6 Terra | Spec/doc writing: rate limiting design doc | — |

## Active — Phase 4: Installer & Scaffold

| ID | Task | Pri | Cpx | Deps | Tags | Model | Reasoning | Fallback |
|----|------|-----|-----|------|------|-------|-----------|----------|
| P4-01 | `hermes h3 install` — plugin registration, version check | HIGH | 3 | — | shim,cli,installer | DeepSeek V4 Pro | Architecture/design: plugin installation system | MiniMax M3 |
| P4-02 | `hermes h3 scaffold --lang go/python/ts` — template generator | HIGH | 3 | — | shim,cli,scaffold | DeepSeek V4 Pro | Architecture/design: code generation, templates | MiniMax M3 |
| P4-03 | `hermes h3 verify` — post-install verification | MEDIUM | 2 | P4-01,P4-02 | shim,cli,verification | MiniMax M3 | Feature: verification tool | DeepSeek V4 Pro |
| P4-04 | `versions.yaml` — Hermes↔H3 compatibility matrix | MEDIUM | 2 | — | protocol,compatibility,spec | GPT-5.6 Terra | Spec/doc writing: compatibility matrix | — |
| P4-05 | Hermes update pre-flight hook (S11 §3) | MEDIUM | 3 | — | shim,upgrade,hook | MiniMax M3 | Feature: upgrade pre-flight check | DeepSeek V4 Pro |
| P3-10 | Publish `hermes-h3-shim` to PyPI — BLOCKED: Needs PYPI_API_TOKEN | MEDIUM | 1 | — | shim,pypi,blocked | DeepSeek V4 Flash | Simple: blocked, waiting on credentials | — |

## Active — Cross-Cutting (OBS, RES, PERF, MULTI, COMPAT, CERT, CHAOS)

| ID | Task | Pri | Cpx | Deps | Tags | Model | Reasoning | Fallback |
|----|------|-----|-----|------|------|-------|-----------|----------|
| OBS-01 | Structured logging spec: decision_id, session_id, trace_id on every log line | MEDIUM | 2 | — | observability,logging,spec | GPT-5.6 Terra | Spec/doc writing: observability spec | — |
| OBS-02 | Metrics: decision latency (p50/p95/p99), error rate, throughput | MEDIUM | 3 | — | observability,metrics | DeepSeek V4 Pro | Architecture/design: metrics collection | MiniMax M3 |
| OBS-03 | Distributed tracing: trace_id propagates Hermes → H3 → harness → back | MEDIUM | 4 | — | observability,tracing | DeepSeek V4 Pro | Architecture/design: distributed tracing | MiniMax M3 |
| OBS-04 | Health check v2: capabilities, model list, version, uptime | LOW | 2 | — | observability,health | DeepSeek V4 Flash | Simple: health check enhancement | — |
| OBS-05 | Dashboard: active sessions, harness health, error breakdown | LOW | 3 | — | observability,dashboard | DeepSeek V4 Pro | Architecture/design: dashboard design | DeepSeek V4 Flash |
| OBS-06 | Alerting: harness down, latency spike, error rate threshold | LOW | 2 | — | observability,alerting | MiniMax M3 | Feature: alerting rules | DeepSeek V4 Flash |
| RES-01 | Harness timeout → fallback to native loop | HIGH | 3 | — | resilience,fallback | Kimi K3 | Bug fix / resilience: timeout fallback | MiniMax M3 |
| RES-02 | Mid-session harness death → session migration to native | HIGH | 4 | — | resilience,migration | DeepSeek V4 Pro | Architecture/design: session migration | Kimi K3 |
| RES-03 | Circuit breaker: N consecutive failures → auto-disable harness | MEDIUM | 3 | — | resilience,circuit-breaker | MiniMax M3 | Feature: circuit breaker pattern | DeepSeek V4 Pro |
| RES-04 | Backpressure: harness sends decisions faster than Hermes can execute | LOW | 3 | — | resilience,backpressure | DeepSeek V4 Pro | Architecture/design: backpressure mechanism | MiniMax M3 |
| RES-05 | Session replay: reconstruct full session from logs | LOW | 3 | — | resilience,replay | MiniMax M3 | Feature: session replay | DeepSeek V4 Pro |
| RES-06 | Graceful degradation: harness partial failure → best-effort response | LOW | 3 | — | resilience,degradation | MiniMax M3 | Feature: graceful degradation | DeepSeek V4 Pro |
| RES-07 | Cold start: first-request latency budget, warm-up protocol | LOW | 2 | — | resilience,cold-start | DeepSeek V4 Pro | Architecture/design: cold start optimization | MiniMax M3 |
| PERF-01 | Latency budget: process < 50ms, result < 100ms p95 | MEDIUM | 2 | — | performance,latency | DeepSeek V4 Flash | Simple: latency measurement + optimization | — |
| PERF-02 | Load test: 100 concurrent sessions, 10 decisions/sec each | MEDIUM | 3 | — | performance,load-test | Step 3.7 Flash | Testing/e2e: load testing | DeepSeek V4 Pro |
| PERF-03 | Memory profile: shim loop over 500 decisions | LOW | 2 | — | performance,memory | DeepSeek V4 Flash | Simple: memory profiling | — |
| PERF-04 | gRPC transport implementation + benchmark vs REST | LOW | 4 | — | performance,grpc,transport | DeepSeek V4 Pro | Architecture/design: gRPC transport | MiniMax M3 |
| PERF-05 | Connection pooling: HTTP keep-alive, multiplexing | LOW | 2 | — | performance,connection-pool | DeepSeek V4 Flash | Simple: connection pooling | — |
| MULTI-01 | Multiple harnesses simultaneously (per-session routing) | LOW | 3 | — | multi-tenant,routing | DeepSeek V4 Pro | Architecture/design: multi-tenant routing | MiniMax M3 |
| MULTI-02 | Harness isolation: one harness crash doesn't affect others | LOW | 3 | — | multi-tenant,isolation | MiniMax M3 | Feature: process isolation | DeepSeek V4 Pro |
| MULTI-03 | A/B testing: route X% of sessions to harness, rest to native | LOW | 3 | — | multi-tenant,ab-testing | MiniMax M3 | Feature: A/B testing | DeepSeek V4 Pro |
| MULTI-04 | Hot-reload: add/remove harnesses without restarting Hermes | LOW | 3 | — | multi-tenant,hot-reload | DeepSeek V4 Pro | Architecture/design: hot-reload mechanism | MiniMax M3 |
| COMPAT-01 | Cross-version test: Hermes vX with H3 protocol vY | LOW | 3 | — | compatibility,testing | Step 3.7 Flash | Testing/e2e: compatibility matrix testing | DeepSeek V4 Pro |
| COMPAT-02 | Protocol version negotiation on connect | LOW | 3 | — | compatibility,protocol | DeepSeek V4 Pro | Architecture/design: version negotiation | MiniMax M3 |
| COMPAT-03 | Deprecation policy: N versions before breaking change | LOW | 2 | — | compatibility,policy,spec | GPT-5.6 Terra | Spec/doc writing: deprecation policy | — |
| COMPAT-04 | Backward compat: v1 harness works with v2 protocol | LOW | 3 | — | compatibility,backward | MiniMax M3 | Feature: backward compatibility | DeepSeek V4 Pro |
| COMPAT-05 | Migration tool: upgrade harness from v1 to v2 protocol | LOW | 3 | — | compatibility,migration | MiniMax M3 | Feature: migration tool | DeepSeek V4 Pro |
| CERT-01 | Official "H3 Compliant" badge spec | LOW | 2 | — | certification,badge,spec | GPT-5.6 Terra | Spec/doc writing: certification spec | — |
| CERT-02 | Badge generation from h3-test output | LOW | 2 | — | certification,badge | DeepSeek V4 Flash | Simple: badge generation | — |
| CERT-03 | Verification endpoint: `h3.sh/verify?url=https://my-harness.com` | LOW | 3 | — | certification,verification | MiniMax M3 | Feature: verification endpoint | DeepSeek V4 Flash |
| CERT-04 | Conformance results registry: public dashboard of certified harnesses | LOW | 3 | — | certification,registry | MiniMax M3 | Feature: public registry | DeepSeek V4 Pro |
| CHAOS-01 | Network partition: Hermes ↔ harness latency injection | LOW | 2 | — | chaos,network | DeepSeek V4 Flash | Simple: chaos test scenario | — |
| CHAOS-02 | Harness returns malformed Decision → Hermes handles gracefully | LOW | 2 | — | chaos,validation | MiniMax M3 | Bug fix: malformed input handling | DeepSeek V4 Flash |
| CHAOS-03 | Harness returns decisions out of expected sequence | LOW | 2 | — | chaos,sequence | MiniMax M3 | Bug fix: out-of-sequence handling | DeepSeek V4 Flash |
| CHAOS-04 | Partial response: harness hangs mid-decision | LOW | 2 | — | chaos,timeout | MiniMax M3 | Bug fix: partial response handling | DeepSeek V4 Flash |

## Never-Done Audit — Continuous Improvement

| ID | Task | Pri | Cpx | Deps | Tags | Model | Reasoning | Fallback |
|----|------|-----|-----|------|------|-------|-----------|----------|
| DEPS-01 | shim: Python packages outdated — 16 packages (gitreins, pydantic-core blocked by fastapi, +14 more) | LOW | 2 | — | deps,python | DeepSeek V4 Flash | Simple: dep updates | — |
| DEPS-02 | sdk-python: Python packages outdated — 7 packages | LOW | 2 | — | deps,python | DeepSeek V4 Flash | Simple: dep updates | — |
| DEPS-03 | sdk-typescript: npm packages outdated — 4 packages (typescript, hono, prettier, @hono/node-server) | LOW | 2 | — | deps,typescript | DeepSeek V4 Flash | Simple: dep updates | — |
| PERF-ND-01 | sdk-go: Zero Go benchmarks — add `Benchmark*` functions | LOW | 2 | — | performance,benchmark,go | DeepSeek V4 Flash | Simple: benchmark additions | — |
| PERF-ND-02 | sdk-python: Zero performance benchmarks — add pytest-benchmark | LOW | 2 | — | performance,benchmark,python | DeepSeek V4 Flash | Simple: benchmark additions | — |
| PERF-ND-03 | shim: Zero performance benchmarks — test battery latency tracking | LOW | 2 | — | performance,benchmark,shim | DeepSeek V4 Flash | Simple: benchmark additions | — |
| WIRING-01 | H3 plugin NOT installed into live Hermes (only exists in Docker image, container stopped). No session can route through H3. | HIGH | 2 | — | wiring,deployment | DeepSeek V4 Pro | Architecture/design: deployment wiring | DeepSeek V4 Flash |
| WIRING-02 | `hermes h3 install` CLI exists in code but never executed against running Hermes. Plugin registration untested. | HIGH | 2 | — | wiring,cli,testing | Step 3.7 Flash | Testing/e2e: CLI verification | DeepSeek V4 Pro |
| SEC-IMPL-01 | Generate harness API key on `hermes h3 install` | HIGH | 2 | P4-01 | security,implementation | MiniMax M3 | Feature: API key generation | DeepSeek V4 Flash |
| SEC-IMPL-02 | Validate API key on every /v1/process and /v1/result call | HIGH | 2 | SEC-IMPL-01 | security,middleware | MiniMax M3 | Feature: API key validation middleware | DeepSeek V4 Flash |
| SEC-IMPL-03 | Add `Authorization` header to protocol spec | MEDIUM | 1 | — | security,spec,protocol | GPT-5.6 Terra | Spec/doc writing: protocol update | — |
| OBS-IMPL-01 | Add `trace_id` to ProcessRequest and Decision schemas | MEDIUM | 2 | — | observability,schema | GPT-5.6 Terra | Spec/doc writing: schema update | — |
| OBS-IMPL-02 | Shim loop logs every hop: process_latency_ms, result_latency_ms, decision_type | MEDIUM | 2 | — | observability,logging | DeepSeek V4 Flash | Simple: structured logging addition | — |
| OBS-IMPL-03 | `h3-test --json` report includes latency percentiles | LOW | 2 | — | observability,testing | DeepSeek V4 Flash | Simple: report enhancement | — |
| RES-IMPL-01 | Shim loader: 3 consecutive harness failures → auto-fallback to native | HIGH | 2 | — | resilience,fallback | Kimi K3 | Bug fix: failure detection + fallback | MiniMax M3 |
| RES-IMPL-02 | Circuit breaker: track error rate, open after 50% failures | MEDIUM | 2 | — | resilience,circuit-breaker | MiniMax M3 | Feature: circuit breaker | DeepSeek V4 Flash |
| RES-IMPL-03 | `hermes h3 verify` tests fallback path explicitly | LOW | 2 | — | resilience,testing | Step 3.7 Flash | Testing/e2e: fallback path test | DeepSeek V4 Pro |
| INFRA-GR-01 | sdk-typescript: missing GitReins evaluator config — add evaluator section to .gitreins/config.yaml (model: deepseek-v4-flash, api_key_env: GITREINS_LLM_API_KEY) | HIGH | 1 | — | infra,gitreins,typescript | DeepSeek V4 Flash | Simple: config addition | — |
| INFRA-GR-02 | protocol: missing GitReins evaluator config — add evaluator section to .gitreins/config.yaml (model: deepseek-v4-flash, api_key_env: GITREINS_LLM_API_KEY) | HIGH | 1 | — | infra,gitreins,protocol | DeepSeek V4 Flash | Simple: config addition | — |
| INFRA-GR-03 | sdk-go: GitReins evaluator missing api_key_env — add `api_key_env: GITREINS_LLM_API_KEY` to .gitreins/config.yaml | HIGH | 1 | — | infra,gitreins,go | DeepSeek V4 Flash | Simple: config addition | — |
| NEVER-DONE | 11-point audit: spec alignment, doc coverage, test gaps, package upgrades, pitfall hunt, performance audit, endpoint verification, CI/CD health, DuckBrain sync, code quality, middle-out wiring. Run every 3-4 ticks. | LOW | 3 | — | audit,quality | DeepSeek V4 Pro | Architecture-level project audit across all subsystems | GLM-5.2 |

- [ ] **E2E-001 — E2E Testing Tick (self-improving loop)** | Recurring every 5-10 ticks | — | — | Luna (browser/screenshots) or Step 3.7 Flash (CLI/API) | foreman-direct | — | —
