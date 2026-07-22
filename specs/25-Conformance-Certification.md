# S25 — Conformance Certification

**Status:** Spec
**Version:** 1.0.0
**Last Updated:** 2026-07-22

---

## 1. Purpose

The H3 Conformance Certification program provides **public, verifiable proof** that a harness implements the H3 protocol correctly. When a developer runs `h3-test` and all 43 tests pass, they earn a badge. That badge is verifiable by anyone — Hermes instances, end users, CI systems — without re-running the test battery.

### Design Principles

> "Run the test battery, get a badge. Anyone can verify the badge without running the tests. No central authority — just math."

| Principle | Rationale |
|-----------|-----------|
| **No central authority** | Badge validity is cryptographic, not permission-based. Anyone can issue a self-signed badge; the registry lists badges others can choose to trust. |
| **Test battery is the gate** | Badges are only issued for 43/43 pass on the exact tagged `h3-test` version. Partial passes or `--smoke` runs don't qualify. |
| **Verifiable offline** | A badge carries enough information (test version, timestamp, harness endpoint, signature) to verify without calling home. |
| **Opt-in registry** | Harness developers can optionally submit their badge to a public registry (`h3.sh/registry`) for discoverability. |
| **Revocable** | If a certified harness is later found non-compliant (via a protocol update), its badge is revoked and the registry is updated. |

---

## 2. Architecture

```
Harness Developer                          Public (h3.sh)
       │                                        │
       │ 1. Run h3-test --endpoint URL           │
       │    43/43 PASS                          │
       │                                        │
       ▼                                        │
  ┌─────────┐    2. Generate badge              │
  │ h3-test ├─────────► JSON + SVG badge        │
  │ --badge │                                   │
  └─────────┘                                   │
       │                                        │
       │ 3. Submit (optional)                   │
       ├────────────────────────────────────────► Registry
       │ HTTPS POST /api/badges                  │ h3.sh/registry
       │                                        │
       │ 4. Verify (anyone)                     │
       │◄────────────────────────────────────────┤
       │ GET /verify?url=https://my-harness.com  │
       │                                        │
       ▼                                        ▼
  Self-hosted badge                         Public dashboard
  (README.md, website)                     (h3.sh/certified)
```

### Components

| Component | Role | Implementation |
|-----------|------|----------------|
| **Badge Generator** | Produces signed JSON badge + SVG image from `h3-test` results | `h3-test --badge` CLI flag |
| **Verification Endpoint** | Validates a badge against stored test results | `h3.sh/verify?url=` |
| **Registry API** | Accepts badge submissions, serves certified list | `h3.sh/api/badges` |
| **Dashboard** | Public directory of all certified harnesses | `h3.sh/certified` |

---

## 3. Badge Format

### 3.1 Signed JSON Badge

The canonical badge is a signed JSON document. The SVG image is derived from it.

```json
{
  "badge_version": "1.0",
  "h3_protocol_version": "1.0",
  "test_version": "hermes-h3-shim==1.2.0",
  "created_at": "2026-07-22T12:00:00Z",
  "expires_at": "2026-10-22T12:00:00Z",
  "harness": {
    "name": "My Echo Harness",
    "endpoint": "https://my-harness.com:9191",
    "language": "go",
    "version": "1.0.0"
  },
  "results": {
    "total": 43,
    "passed": 43,
    "failed": 0,
    "duration_ms": 180,
    "regions": {
      "health_protocol": {"passed": 7, "total": 7},
      "process_flows": {"passed": 8, "total": 8},
      "decision_types": {"passed": 6, "total": 6},
      "result_handling": {"passed": 7, "total": 7},
      "edge_cases": {"passed": 10, "total": 10},
      "stress": {"passed": 5, "total": 5}
    }
  },
  "signature": {
    "algorithm": "Ed25519",
    "signer": "h3_cert_signer_v1",
    "value": "base64url(64-byte-sig)"
  }
}
```

### 3.2 SVG Badge

A shields.io-style badge showing the certification status:

```
┌─────────────────────────────────────┐
│  H3  │  COMPLIANT  │  43/43  180ms │
└─────────────────────────────────────┘
```

Three badge variants:

| Badge | Color | Meaning |
|-------|-------|---------|
| `h3-compliant-brightgreen` | ✅ Green | 43/43 pass, badge valid |
| `h3-compliant-yellow` | 🟡 Yellow | 43/43 pass, badge expired |
| `h3-unverified-lightgrey` | ⚫ Grey | Not tested / no badge |

The SVG is self-contained (no external image assets) and fits in a README.md:

```markdown
[![H3 Compliant](https://h3.sh/badges/v1/ {badge-hash} .svg)](https://h3.sh/verify/ {badge-hash})
```

### 3.3 Badge Lifecycle

| Stage | Description | Duration |
|-------|-------------|----------|
| **Issued** | Fresh 43/43 pass | 90 days |
| **Expiring** | 30 days before expiry, badge shows yellow | 60-90 days |
| **Expired** | Past expiry date, badge shows grey | After 90 days |
| **Revoked** | Manual revocation (protocol version mismatch, vulnerability) | Instant |
| **Re-issued** | Fresh test run after expiry or revocation | Immediate |

---

## 4. Badge Generation (`h3-test --badge`)

### 4.1 CLI Interface

```bash
# Generate badge from latest test run
h3-test --endpoint http://localhost:9191 --badge

# Generate badge from saved JSON results
h3-test --badge --from-results results.json

# Generate badge with custom harness metadata
h3-test --badge --harness-name "My Harness" --harness-version 1.0.0 \
  --harness-language go --endpoint https://my-harness.com:9191

# Output formats
h3-test --badge --format json        # Signed JSON (default)
h3-test --badge --format svg         # SVG image only
h3-test --badge --format markdown    # Markdown embed code
h3-test --badge --format all         # JSON + SVG + markdown
```

### 4.2 Output Files

```
.badge/
├── badge.json             ← Signed JSON badge
├── h3-compliant.svg       ← Green badge (43/43)
├── h3-compliant-yellow.svg ← Yellow badge (expiring)
├── verify.json            ← Verification payload (for h3.sh/verify)
└── submit.json            ← Submission payload (for h3.sh/api/badges)
```

### 4.3 Signing

The badge is signed with the `h3 cert` keypair. Generation flow:

1. `h3-test` runs all 43 tests
2. If 43/43 pass, generates badge template
3. Prompts for signing key (or reads from `H3_SIGNING_KEY` env var)
4. Signs `badge.json` with Ed25519
5. Outputs SVG + JSON + verification URL

For self-signed badges (no registry submission):
- Developer generates their own Ed25519 keypair
- Badge includes `signature.signer: "self:<pubkey-hash>"`
- Verification accepts self-signed badges by checking the signature against the embedded public key

### 4.4 Test Version Binding

Every badge contains the exact `hermes-h3-shim` version used. The test battery is versioned — a badge from v1.2.0 is only comparable to other v1.2.0 badges. When the protocol version increases, all existing badges expire and harnesses must re-test.

```bash
# Show which test versions are valid for the current protocol
hermes-h3 badge --valid-versions
# → Protocol v1.0: hermes-h3-shim>=1.2.0,<2.0.0
```

---

## 5. Verification Endpoint (`h3.sh/verify`)

### 5.1 API

```http
GET /verify?url=https://my-harness.com/badge.json
GET /verify/{badge-hash}
```

**Response (200 — Valid):**

```json
{
  "valid": true,
  "badge": { /* signed badge JSON */ },
  "checked_at": "2026-07-22T12:00:00Z",
  "test_version": "hermes-h3-shim==1.2.0",
  "protocol_version": "1.0",
  "status": "compliant",
  "expires_at": "2026-10-22T12:00:00Z"
}
```

**Response (200 — Expired):**

```json
{
  "valid": false,
  "status": "expired",
  "expired_at": "2026-10-22T12:00:00Z",
  "reason": "Badge expired 2026-10-22. Re-run h3-test --badge to re-certify."
}
```

**Response (200 — Revoked):**

```json
{
  "valid": false,
  "status": "revoked",
  "revoked_at": "2026-11-01T12:00:00Z",
  "reason": "Protocol version 1.1 requires re-certification. v1.0 badges no longer valid."
}
```

**Response (400 — Invalid):**

```json
{
  "valid": false,
  "status": "invalid",
  "errors": [
    "Badge signature invalid",
    "Test version mismatch: badge uses hermes-h3-shim==1.0.0, minimum is 1.2.0",
    "harness.endpoint does not match URL origin"
  ]
}
```

### 5.2 Verification Algorithm

The `h3.sh/verify` endpoint performs these checks in order:

| Order | Check | Fails For |
|-------|-------|-----------|
| 1 | Badge JSON parses correctly | Malformed badge |
| 2 | `badge_version` matches current spec | Version mismatch |
| 3 | `h3_protocol_version` is still supported | Outdated protocol |
| 4 | Signature is valid (Ed25519) | Tampered badge |
| 5 | Signer is trusted (registry key or self-signed) | Unknown/untrusted signer |
| 6 | `expires_at` is in the future | Expired badge |
| 7 | Badge is not in revocation list | Revoked badge |
| 8 | `test_version` is compatible with current protocol | Stale test battery |
| 9 | All 6 regions show 100% pass | Partial pass badge |
| 10 | `harness.endpoint` origin matches URL domain (if URL-based) | Domain mismatch |
| 11 | (Optional) Probe harness endpoint for `/v1/health` | Dead harness |

### 5.3 Verification Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| **Offline** | Verify signature + expiry only. No network calls to registry. | README badge, local CI |
| **Online** | Full verification including registry revocation check + optional health probe. | h3.sh/verify endpoint |
| **Deep** | Online + probe harness endpoint for `/v1/health`, verify protocol version in response. | Pre-production validation |

### 5.4 CLI Verification

```bash
# Verify a badge file
hermes-h3 verify badge.json

# Verify a remote badge
hermes-h3 verify https://my-harness.com/badge.json

# Deep verify: badge + health probe
hermes-h3 verify --deep --endpoint https://my-harness.com:9191 badge.json

# Verify and show full report
hermes-h3 verify --verbose badge.json
```

---

## 6. Registry API

### 6.1 Submit Badge

```http
POST /api/badges
Content-Type: application/json
Authorization: Bearer h3_hx_{hex64}

{
  "badge": { /* signed badge JSON */ },
  "submitter": {
    "name": "Harness Developer",
    "email": "dev@example.com",
    "harness_url": "https://github.com/example/harness"
  }
}
```

**Response (201 — Accepted):**

```json
{
  "id": "badge-a1b2c3d4",
  "status": "pending",
  "verify_url": "https://h3.sh/verify/badge-a1b2c3d4",
  "badge_markdown": "[![H3 Compliant](https://h3.sh/badges/v1/a1b2c3d4.svg)]..."
}
```

**Response (422 — Validation Failed):**

```json
{
  "error": "validation_failed",
  "details": ["Badge signature invalid", "Test battery version must be >= 1.2.0"]
}
```

### 6.2 List Certified

```http
GET /api/badges
GET /api/badges?language=go
GET /api/badges?page=2&per_page=20
```

**Response:**

```json
{
  "badges": [
    {
      "id": "badge-a1b2c3d4",
      "harness": {
        "name": "My Echo Harness",
        "language": "go",
        "version": "1.0.0"
      },
      "status": "compliant",
      "test_version": "hermes-h3-shim==1.2.0",
      "created_at": "2026-07-22T12:00:00Z",
      "expires_at": "2026-10-22T12:00:00Z"
    }
  ],
  "total": 42,
  "page": 1,
  "per_page": 20
}
```

### 6.3 Revoke Badge

```http
DELETE /api/badges/{id}
Authorization: Bearer h3_hx_{admin-hex64}

{
  "reason": "Protocol version 1.1 released. v1.0 badges deprecated.",
  "notify": true
}
```

Revocation reasons:

| Reason | Auth Level | Auto-trigger? |
|--------|-----------|---------------|
| Protocol version bump | admin | ✅ Yes, on new protocol release |
| Manual (security vuln) | admin | ❌ Manual |
| Harness developer request | owner | ❌ Manual (email verification) |
| Test battery update (breaking) | admin | ✅ Yes, on major test battery release |

### 6.4 Registration Authentication

| Action | Auth Required | Key Type |
|--------|-------------|----------|
| Submit badge | `h3_hx_{hex64}` (harness owner) | S12 §3 per-harness key |
| List badges | None | Public |
| Verify badge | None | Public |
| Revoke badge | `h3_hx_{admin-hex64}` (admin) | Admin key |
| View dashboard | None | Public |

---

## 7. Dashboard (`h3.sh/certified`)

### 7.1 Page Layout

```
┌──────────────────────────────────────────────────┐
│ H3 Conformance Registry                          │
│ ──────────────────────────────────────────────── │
│ [Filter: All Languages ▼] [Search...] [Sort: ▼] │
├──────────────────────────────────────────────────┤
│                                                  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────┐ │
│  │ Go Echo 1.0  │ │ Py Echo 1.0  │ │ TS Echo  │ │
│  │ H3 Compliant │ │ H3 Compliant │ │ v1.0     │ │
│  │ Green Badge  │ │ Green Badge  │ │ Compliant│ │
│  │ 180ms 43/43  │ │ 210ms 43/43  │ │ 195ms    │ │
│  └──────────────┘ └──────────────┘ └──────────┘ │
│                                                  │
│  Stats bar: 42 certified | 3 revoked | 12 expired│
│  Languages: Go(18) Python(14) TypeScript(10)     │
│                                                  │
└──────────────────────────────────────────────────┘
```

### 7.2 Stats

The dashboard displays aggregate statistics:

- **Total certified:** Number of currently valid badges
- **Revoked:** Badges revoked for protocol/safety reasons
- **Expired:** Badges past their 90-day expiry
- **By language:** Breakdown of certified harnesses by SDK language
- **By version:** Active protocol versions in the field
- **Trend:** New certifications per week

### 7.3 Badge Details Page

Clicking a badge entry shows:

```
Badge Details
┌─────────────────────────────────────────┐
│ Status:    ✅ H3 Compliant              │
│ Harness:   My Echo Harness v1.0.0       │
│ Language:  Go                           │
│ Endpoint:  https://my-harness.com:9191  │
│ Tests:     43/43 in 180ms               │
│ Issued:    2026-07-22                   │
│ Expires:   2026-10-22                   │
│                                           │
│ Regions:                                  │
│   Health & Protocol     ✅ 7/7           │
│   Process Flows         ✅ 8/8           │
│   Decision Types        ✅ 6/6           │
│   Result Handling       ✅ 7/7           │
│   Edge Cases           ✅ 10/10          │
│   Stress                ✅ 5/5           │
│                                           │
│ Verification URL:                         │
│ https://h3.sh/verify/badge-a1b2c3d4       │
│                                           │
│ Markdown: [![H3 Compliant](...)](...)      │
│ SVG:      https://h3.sh/badges/v1/...svg  │
└─────────────────────────────────────────┘
```

---

## 8. CI Integration

### 8.1 GitHub Actions

```yaml
# .github/workflows/h3-certification.yml
name: H3 Certification
on:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # Weekly re-certification

jobs:
  certify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start harness
        run: go run . & sleep 2
      - name: Install test battery
        run: pip install hermes-h3-shim
      - name: Run certification
        run: |
          h3-test --endpoint http://localhost:9191 --badge --format all
      - name: Submit badge
        env:
          H3_BADGE_TOKEN: ${{ secrets.H3_BADGE_TOKEN }}
        run: |
          hermes-h3 badge submit .badge/submit.json
      - name: Upload badge artifacts
        uses: actions/upload-artifact@v4
        with:
          name: h3-badge
          path: .badge/
```

### 8.2 CI Badge Gate

CI pipelines can enforce certification as a gate:

```yaml
- name: Verify badge before deploy
  run: |
    hermes-h3 verify .badge/badge.json --strict
    # Fails unless: 43/43, valid signature, not expired, 
    # compatible protocol version, all regions 100%
```

### 8.3 Badge in README

```markdown
<!-- Auto-updated by h3-test --badge --format markdown -->
[![H3 Compliant](https://h3.sh/badges/v1/badge-a1b2c3d4.svg)](https://h3.sh/verify/badge-a1b2c3d4)
```

---

## 9. CLI Surface

```bash
# Badge generation
hermes-h3 badge [generate|verify|submit|revoke|list]

# Generate a new badge from test results
hermes-h3 badge generate \
  --endpoint http://localhost:9191 \
  --name "My Harness" \
  --version 1.0.0 \
  --language go \
  --format all

# Verify a badge
hermes-h3 badge verify badge.json
hermes-h3 badge verify https://h3.sh/verify/badge-a1b2c3d4
hermes-h3 badge verify --deep --endpoint http://localhost:9191 badge.json

# Submit badge to registry
hermes-h3 badge submit .badge/submit.json

# Revoke a badge (admin only)
hermes-h3 badge revoke badge-a1b2c3d4 --reason "Protocol 1.1 release"

# List all badges
hermes-h3 badge list [--language go] [--status compliant] [--json]

# Self-sign a badge (no registry)
hermes-h3 badge sign .badge/badge.json --key-file ~/.h3/signing-key.pem
```

---

## 10. Test Scenarios

### 10.1 Unit Tests (12 tests)

| ID | Test | Verifies |
|----|------|----------|
| CERT-01-01 | Generate badge from 43/43 results | Badge JSON has correct structure, all fields populated |
| CERT-01-02 | Generate badge from partial results (40/43) | `h3-test --badge` rejects with error for <43/43 |
| CERT-01-03 | Sign badge with Ed25519 | Signature is valid and verifiable |
| CERT-01-04 | Verify self-signed badge | Self-signed badge validates with embedded pubkey |
| CERT-01-05 | Reject tampered badge | Test fails after modifying a single field |
| CERT-01-06 | Reject expired badge | `expires_at` in past → invalid |
| CERT-01-07 | SVG badge generation | SVG file matches expected shields.io style |
| CERT-01-08 | Badge expiry calculation | 90 days from creation, yellow at 60d |
| CERT-01-09 | Multiple badge format output | `--format all` produces json+svg+markdown |
| CERT-01-10 | Badge version compatibility | `badge_version: "0.9"` rejected by current verifier |
| CERT-01-11 | Self-signing key generation | `hermes-h3 badge keygen` produces Ed25519 pair |
| CERT-01-12 | Badge hash is deterministic | Same inputs → same badge hash |

### 10.2 Integration Tests (8 tests)

| ID | Test | Verifies |
|----|------|----------|
| CERT-I-01 | End-to-end: test→badge→verify loop | Full pipeline produces valid badge |
| CERT-I-02 | Registry submit then list | Submitted badge appears in list response |
| CERT-I-03 | Registry submit then verify | `h3.sh/verify/{id}` returns valid |
| CERT-I-04 | Revoke badge then verify | `h3.sh/verify/{id}` returns revoked=true |
| CERT-I-05 | Expired badge auto-detection | Badge with past expires_at handled correctly |
| CERT-I-06 | Multi-language certification | Go/Python/TS harnesses all produce valid badges |
| CERT-I-07 | CI badge gate enforcement | CI step fails when badge is expired/revoked |
| CERT-I-08 | Submit badge with invalid signature rejected | Registry returns 422 |

### 10.3 Dashboard Tests (4 tests)

| ID | Test | Verifies |
|----|------|----------|
| CERT-D-01 | Dashboard renders badge list | At least one badge row present |
| CERT-D-02 | Dashboard filters by language | Filter shows only matching entries |
| CERT-D-03 | Dashboard stats match badge count | Stats bar totals match actual badge count |
| CERT-D-04 | Badge detail page shows full data | All regions, verification URL, markdown rendered |

---

## 11. Security Considerations

| Threat | Mitigation |
|--------|-----------|
| Badge forgery | Ed25519 signatures. Registry only accepts admin-signed badges for auto-submission. Self-signed badges are identifiable by `signer: "self:..."` and clearly marked. |
| Badge reuse on different harness | Badge binds `harness.endpoint` + `harness.name` + signature. Domain mismatch in online verification blocks URL-reuse. |
| Registry spam | Rate limit badge submissions: 5/hour per API key. Human review for first badge from new submitter. |
| Revocation bypass | Revocation list is signed by admin key. Clients verify revocation list signature during online verification. |
| Stale badge from old protocol | Badge includes `h3_protocol_version` and `test_version`. Verifier checks these against current minimum. |
| Harvesting harness endpoints from registry | Registry lists are public by design — endpoints are already discoverable from badges in READMEs. No additional risk. |
| Private harness certification | `--local-only` flag generates badge that is never submitted to registry. Badge still verifiable offline (self-signed). |

---

## 12. Migration & Deployment

### Phase 1: Badge Generator (Shim)

| Step | Description | Acceptance |
|------|-------------|------------|
| 1.1 | Add `--badge` flag to `h3-test` CLI | `h3-test --badge` produces badge.json |
| 1.2 | Implement Ed25519 signing in badge generator | Badge signature verifies correctly |
| 1.3 | Add SVG badge output | SVG matches shields.io style |
| 1.4 | Add `--format all` output | JSON + SVG + markdown in `.badge/` |
| 1.5 | Add `hermes-h3 badge` CLI commands | generate, verify, list, sign, submit, revoke |
| **Gate** | `h3-test --badge --format all` produces all 3 files | Self-signed badge passes offline verify |

### Phase 2: Badge Verification (Shim)

| Step | Description | Acceptance |
|------|-------------|------------|
| 2.1 | Implement offline verifier | `hermes-h3 verify badge.json` passes for valid badge |
| 2.2 | Implement verification algorithm (all 11 checks) | Each check returns correct pass/fail |
| 2.3 | Add `--deep` verification mode | Deep verify probes harness endpoint |
| 2.4 | Add expiration detection + yellow SVG variant | Expiring badges correctly flagged |
| **Gate** | Full verification loop: generate → sign → verify | End-to-end pass with 43/43 test battery |

### Phase 3: Registry Server (h3.sh)

| Step | Description | Acceptance |
|------|-------------|------------|
| 3.1 | Deploy `POST /api/badges` submission endpoint | Badge accepted with valid signature |
| 3.2 | Deploy `GET /api/badges` list endpoint | Listed badges match submitted counts |
| 3.3 | Deploy `GET /verify` verification endpoint | Badge verified against registry data |
| 3.4 | Deploy `DELETE /api/badges/{id}` revocation | Revoked badge returns `status: revoked` |
| 3.5 | Add authentication for submission + revocation | h3_hx token required |
| **Gate** | Full registry CRUD cycle works | Submit → list → verify → revoke → verify |

### Phase 4: Dashboard (h3.sh)

| Step | Description | Acceptance |
|------|-------------|------------|
| 4.1 | Build `h3.sh/certified` dashboard page | Renders badge cards from registry API |
| 4.2 | Add filter (language, status) + search | Filtered results match selection |
| 4.3 | Add badge detail page | Full badge info, verification URL, SVG embed |
| 4.4 | Add stats bar + trend chart | Stats match registry aggregate counts |
| **Gate** | Dashboard shows at least 1 certified harness | Full read-only registry interface working |

### Phase 5: CI Integration

| Step | Description | Acceptance |
|------|-------------|------------|
| 5.1 | Write CI workflow template (GitHub Actions) | Workflow runs in <5 min |
| 5.2 | Add badge submit step to CI template | Badge auto-submitted to registry |
| 5.3 | Add badge gate to CI template | Deploy blocked if badge invalid |
| 5.4 | Document CI setup in h3.sh | External developers can set up CI certification |

---

## 13. Cross-References

| Spec | Section | Relationship |
|------|---------|-------------|
| S02 — Protocol Specification | §3 (Endpoints) | Registry API extends protocol |
| S05 — Shim Test Battery | §2 (Test Runner) | `h3-test` is badge generator runtime |
| S10 — Website & Developer Docs | all | Dashboard + verify endpoint are h3.sh features |
| S12 — Security & Authentication | §3 (API Key Format) | Badge auth uses h3_hx tokens |
| S13 — Token Rotation & Revocation | §4 (Revocation) | Badge revocation follows same pattern |
| S14 — TLS Enforcement | all | Registry and verify endpoint must use TLS |
| S24 — Compatibility Matrix | §3 (Version Negotiation) | Badge version checking follows compat matrix |
| S20 — Operational Dashboard | §2 (Dashboard Architecture) | Registry dashboard shares S20 design patterns |

---

## 14. Design Decisions

| Decision | Rationale |
|----------|-----------|
| Ed25519 over RSA/ECDSA | Ed25519 is fast (~100K sig/s on modern CPUs), produces small signatures (64 bytes), and doesn't need a random hardware source. All H3 SDKs already support Ed25519 from S12. |
| 90-day badge expiry | Balances freshness with practicality. Quarterly re-certification is cheap (h3-test takes <1s). Developers get a ~weekly reminder before expiry. |
| Self-signed badges allowed | Not everyone wants or needs a registry. Self-signed badges let private harnesses (internal tools, CI-only) prove compliance without publishing their endpoint. |
| Badge binds endpoint URL | Prevents a certified badge from being copied to a different harness. Online verification checks domain match; offline verification shows a warning. |
| Protocol version in badge | A v1.0 badge is meaningless after v1.1 release. Binding the badge to the protocol version lets the verifier reject stale certifications. |
| Registry is opt-in | No one should be forced to publish their harness. The badge itself (SVG + JSON) is verifiable locally. The registry is a discovery tool, not an authority. |

---

## 15. Future Work

| Item | Description | Priority |
|------|-------------|----------|
| Badge auto-renewal | CI cron job auto-submits new badge before expiry | Medium |
| Private registry | Self-hosted registry for enterprise | Low |
| Audit log | Full history of badge submissions + revocations | Low |
| Badge tiers | Bronze (partial), Silver (full), Gold (stress+perf) | Low |
| WebAuthn for admin revocation | Stronger auth for admin operations | Medium |
| Badge API SDK | Go/Python/TS clients for registry API | Low |

---

*End of S25 — Conformance Certification*
