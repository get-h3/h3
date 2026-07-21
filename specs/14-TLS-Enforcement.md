# S14 — H3 TLS Enforcement

**Status:** Spec
**Version:** 1.0.0
**Last Updated:** 2026-07-21

---

## 1. Overview

H3 currently runs over plain HTTP. Every `/v1/process` and `/v1/result` call travels unencrypted across the network. An attacker on the same network can:

- Sniff API keys and session data from request bodies
- Inject forged decisions by MITM-ing the Hermes→harness channel
- Replay captured requests to hijack sessions
- Impersonate either side with intercepted credentials

TLS enforcement closes these gaps at the transport layer. This spec defines mandatory mTLS between Hermes and every registered harness, with phased deployment and backward compatibility.

**Relationship to S12 (Security & Authentication):** S12 defines API key auth at the application layer (Layer 1). This spec defines mTLS at the transport layer (Layer 2). They are independent — an attacker who bypasses one still faces the other. Combined with S15 rate limiting (Layer 3), the three layers form defense in depth.

**Design principle:** "Secure by default, permissive by opt-in." Every harness starts in `strict` mode. Relaxation requires explicit configuration.

---

## 2. TLS Architecture

### 2.1 CA Hierarchy

```
Hermes Root CA (self-signed, 10-year validity)
├── Hermes Server Certificate (signed by Root CA, 1-year validity)
├── Harness A Certificate (signed by Root CA, 1-year validity)
├── Harness B Certificate (signed by Root CA, 1-year validity)
└── Harness C Certificate (signed by Root CA, 1-year validity)
```

**Hermes is the CA.** It generates the root CA on first `hermes h3 install`. All harness certificates are signed by this CA. Both sides trust only the Root CA — no external CAs, no Let's Encrypt, no public PKI.

**Why Hermes as CA:** Hermes is the platform owner. The harness author may be a third party — they shouldn't need to run their own CA or buy certificates. Hermes issues certs as part of the pairing flow.

### 2.2 Key Types

| Component | Algorithm | Key Size | Format | Storage |
|---|---|---|---|---|
| Root CA | Ed25519 | 256-bit | PEM | `.hermes/h3/ca/ca.crt` + `.hermes/h3/ca/ca.key` |
| Hermes Server | Ed25519 | 256-bit | PEM | `.hermes/h3/certs/hermes.crt` + `.hermes/h3/certs/hermes.key` |
| Harness | Ed25519 | 256-bit | PEM | `.h3-harness.yaml` (inline), `.hermes/h3/harnesses/<id>.yaml` (Hermes copy) |

**Ed25519 rationale:**
- Faster than RSA (critical for per-request handshake overhead)
- Smaller keys and signatures (less data on the wire)
- No known side-channel vulnerabilities vs ECDSA
- Widely supported: Go 1.13+, Python 3.8+ (cryptography), Node 12+ (crypto)

### 2.3 TLS Configuration

| Parameter | Value |
|---|---|
| Minimum TLS version | TLS 1.3 |
| Cipher suites | TLS 1.3 built-in (TLS_AES_256_GCM_SHA384, TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256) |
| Client authentication | Required (mTLS) |
| Session resumption | Session tickets (rotated every 24h) |
| OCSP stapling | Not required (private CA, no public revocation infrastructure) |
| Certificate compression | Enabled (zlib) |

**TLS 1.3 only.** TLS 1.2 has known vulnerabilities (BEAST, Lucky13, POODLE). No backward compatibility for pre-1.3 — harnesses deployed on old OSes must be upgraded. H3 is a new protocol; there is no installed base to protect.

**No cipher suite negotiation.** TLS 1.3 has exactly 5 cipher suites and all are strong. We accept all 5 — no need to restrict further.

---

## 3. TLS Enforcement Modes

Every harness has a TLS mode. The mode determines what happens when TLS negotiation fails or when a non-TLS request arrives.

### 3.1 Mode Definitions

| Mode | Hermes Behavior | Use Case |
|---|---|---|
| `strict` | Hermes refuses to connect without valid mTLS. Harness must present a certificate signed by Hermes CA. Both sides validated. | Default. Production. |
| `permissive` | Hermes attempts mTLS. If harness presents a valid cert, use it. If harness doesn't present a cert (plain HTTP), connect anyway with a warning. If harness presents an INVALID cert, reject. | Migration. Testing. |
| `none` | Hermes connects over plain HTTP. No TLS at all. | Local development only. Logs a startup warning: "TLS disabled — not safe for production." |

### 3.2 Mode Selection

```
┌──────────────────────────────────────────────────────┐
│ Mode Resolution Order                                │
├──────────────────────────────────────────────────────┤
│ 1. Per-harness config: hermes h3 install --tls-mode  │
│ 2. Global default: hermes h3 config set tls.mode     │
│ 3. Hard default: strict                              │
└──────────────────────────────────────────────────────┘
```

### 3.3 Mode Transitions

| From | To | Allowed? | Effect |
|---|---|---|---|
| `strict` | `permissive` | ✅ (downgrade, logged) | Hermes accepts plain-HTTP from this harness after explicit admin action |
| `strict` | `none` | ⚠️ (downgrade, requires --force) | Hermes drops TLS entirely for this harness. Requires CLI confirmation. |
| `permissive` | `strict` | ✅ (upgrade, immediate) | Hermes requires valid cert on next request. If harness has no cert, fails. |
| `none` | `permissive` | ✅ (upgrade) | Hermes starts offering mTLS, still accepts plain HTTP. |
| `none` | `strict` | ✅ (upgrade) | Hermes requires valid cert. Harness must be re-paired with a cert. |

---

## 4. Certificate Lifecycle

### 4.1 Generation

Certificates are generated during harness pairing:

```
$ hermes h3 install --harness-url https://my-harness.example.com:9191

  ✓ Generating harness certificate...
  ✓ Signing with Hermes Root CA...
  ✓ Pairing with harness at https://my-harness.example.com:9191
  ✓ Harness registered: h3_abc123def456
  ✓ Certificate issued:
      Serial:  01:AB:CD:...
      Subject: CN=h3-harness-h3_abc123def456
      Issuer:  CN=H3 Hermes Root CA
      Expires: 2027-07-21T00:00:00Z (365 days)

  ┌─────────────────────────────────────────────────┐
  │ ⚠  SHARE WITH HARNESS AUTHOR                    │
  │                                                 │
  │ Hermes CA certificate (public):                 │
  │   .hermes/h3/ca/ca.crt                          │
  │                                                 │
  │ The harness author needs this CA cert           │
  │ to validate Hermes's identity.                  │
  └─────────────────────────────────────────────────┘
```

### 4.2 Certificate Fields

```
Certificate:
    Version: 3 (0x2)
    Serial Number: <unique, incremented>
    Signature Algorithm: Ed25519
    Issuer: CN = H3 Hermes Root CA, O = H3, OU = get-h3
    Validity:
        Not Before: <generation time>
        Not After : <generation time + 365 days>
    Subject: CN = h3-harness-<harness_id>, O = H3, OU = harness
    Subject Public Key Info:
        Public Key Algorithm: Ed25519
    X509v3 extensions:
        X509v3 Basic Constraints: CA:FALSE
        X509v3 Key Usage: Digital Signature, Key Encipherment
        X509v3 Extended Key Usage: TLS Web Client Authentication
        X509v3 Subject Alternative Name:
            DNS: <harness hostname>
        X509v3 Authority Key Identifier: <root CA key ID>
```

### 4.3 Renewal

Certificates expire after 365 days. Renewal is part of the maintenance cycle:

```
$ hermes h3 renew <harness_id>

  ✓ Harness h3_abc123def456 certificate expires in 3 days
  ✓ Generating new certificate (serial: 01:AB:DE)
  ✓ Pushing to harness...
  ✓ Harness accepted new certificate
  ✓ Grace period: dual-key active until 2027-07-24T00:00:00Z

  Old cert expires: 2027-07-24T00:00:00Z
  New cert expires: 2028-07-21T00:00:00Z
```

**Grace period:** During renewal, both old and new certificates are valid for 3 days. This prevents downtime if the harness needs a restart to pick up the new cert.

**Auto-renewal:** Hermes checks certificate expiry weekly (cron). If a harness cert has < 30 days remaining, it auto-renews. Auto-renewal is enabled by default; can be disabled per-harness.

### 4.4 Revocation

When a harness is unregistered, its certificate is added to a local revocation list:

```
$ hermes h3 revoke <harness_id>

  ✓ Harness h3_abc123def456 revoked
  ✓ Certificate 01:AB:CD added to CRL
  ✓ Active sessions (3) will be terminated on next request

  Revocation reason: harness decommissioned
```

**CRL format:** PEM-encoded X.509 CRL, stored at `.hermes/h3/ca/crl.pem`. Hermes checks this CRL during every TLS handshake. Revoked certs are rejected immediately.

**No OCSP.** With a private CA and local CRL, OCSP adds complexity without benefit. CRL check is a local file read — sub-millisecond.

### 4.5 Emergency Rotation

If the Root CA private key is compromised:

```
$ hermes h3 rotate-ca

  ⚠  WARNING: This invalidates ALL harness certificates.
  ⚠  Every harness must be re-paired.

  Are you sure? [y/N]: y

  ✓ New Root CA generated
  ✓ Old CA backed up to .hermes/h3/ca/backup-2026-07-21T12:00:00Z/
  ✓ All 3 harness certificates revoked
  ✓ New CRL issued (old CA + old certs)

  Next steps:
    1. Re-pair every harness: hermes h3 repair <harness_url>
    2. Delete old CA backup after all harnesses are re-paired
```

---

## 5. mTLS Handshake

### 5.1 Connection Flow

```
Hermes (client)                              Harness (server)
    |                                              |
    | 1. TCP connect                               |
    |--------------------------------------------->|
    |                                              |
    | 2. TLS ClientHello (TLS 1.3)                 |
    |    - SNI: my-harness.example.com             |
    |--------------------------------------------->|
    |                                              |
    | 3. TLS ServerHello                           |
    |    - Server certificate                      |
    |    - CertificateRequest (client auth)        |
    |<---------------------------------------------|
    |                                              |
    | 4. Hermes validates server cert:             |
    |    - Signed by Root CA?                      |
    |    - CN matches expected?                    |
    |    - Not expired?                            |
    |    - Not in CRL?                             |
    |                                              |
    | 5. TLS Certificate (client)                  |
    |    - Hermes client certificate               |
    |--------------------------------------------->|
    |                                              |
    | 6. Harness validates client cert:            |
    |    - Signed by Root CA?                      |
    |    - Not expired?                            |
    |    - Not in CRL?                             |
    |                                              |
    | 7. TLS Finished                              |
    |<-------------------------------------------->|
    |                                              |
    | 8. Encrypted application data                |
    |<-------------------------------------------->|
```

### 5.2 Certificate Validation (Both Sides)

```
function validate_cert(cert, ca_cert, crl):
    // 1. Signature check
    if not cert.verify(ca_cert.public_key):
        return ERROR_BAD_SIGNATURE

    // 2. Expiry check
    if now < cert.not_before or now > cert.not_after:
        return ERROR_EXPIRED

    // 3. Revocation check
    if crl.contains(cert.serial_number):
        return ERROR_REVOKED

    // 4. Usage check (server cert: must have serverAuth EKU)
    if is_server_cert and not cert.has_eku("serverAuth"):
        return ERROR_INVALID_USAGE

    // 5. Hostname check (server cert only)
    if is_server_cert and not cert.san_matches(hostname):
        return ERROR_HOSTNAME_MISMATCH

    return OK
```

### 5.3 SNI (Server Name Indication)

Hermes sends the harness hostname as SNI. This allows a single IP to serve multiple harnesses with different certificates. Harnesses behind a reverse proxy (nginx, Caddy) use SNI to route to the correct backend.

---

## 6. Hermes-side Implementation

### 6.1 H3Client TLS Configuration

```python
# shim/src/h3_shim/client.py

class H3Client:
    def __init__(self, harness_config):
        self.base_url = harness_config.url
        self.tls_mode = harness_config.get("tls_mode", "strict")

        if self.tls_mode == "none":
            self._transport = httpx.AsyncClient(verify=False)
            return

        # Load Hermes client cert + key
        self._client_cert = (
            str(HERMES_CERT_DIR / "hermes.crt"),
            str(HERMES_CERT_DIR / "hermes.key"),
        )

        # Load Root CA (to validate harness)
        self._ca_cert = str(CA_DIR / "ca.crt")

        # Load CRL
        self._crl = load_crl(CA_DIR / "crl.pem")

        if self.tls_mode == "strict":
            self._transport = httpx.AsyncClient(
                cert=self._client_cert,
                verify=self._ca_cert,
                http2=True,
            )
        elif self.tls_mode == "permissive":
            self._transport = httpx.AsyncClient(
                cert=self._client_cert,
                verify=self._ca_cert,
                http2=True,
                # Accept plain HTTP redirects
                follow_redirects=True,
            )
```

### 6.2 TLS Error Handling

```python
# Hermes-side error mapping
TLS_ERROR_MAP = {
    "CERTIFICATE_VERIFY_FAILED": {
        "hermes_code": "TLS_CERT_INVALID",
        "message": "Harness certificate failed validation",
        "retry": False,
    },
    "SSLV3_ALERT_CERTIFICATE_EXPIRED": {
        "hermes_code": "TLS_CERT_EXPIRED",
        "message": "Harness certificate has expired",
        "retry": False,
    },
    "SSLV3_ALERT_CERTIFICATE_REVOKED": {
        "hermes_code": "TLS_CERT_REVOKED",
        "message": "Harness certificate has been revoked",
        "retry": False,
    },
    "SSLV3_ALERT_HANDSHAKE_FAILURE": {
        "hermes_code": "TLS_HANDSHAKE_FAILED",
        "message": "mTLS handshake failed — may be TLS version or cipher mismatch",
        "retry": True,
    },
    "TLSV1_ALERT_UNKNOWN_CA": {
        "hermes_code": "TLS_UNKNOWN_CA",
        "message": "Harness presented a certificate from an unknown CA",
        "retry": False,
    },
}
```

### 6.3 Health Check with TLS

The `GET /v1/health` endpoint runs over the same mTLS connection. If TLS fails, health is reported as `TLSError`:

```json
{
    "status": "unhealthy",
    "reason": "TLS handshake failed: CERTIFICATE_VERIFY_FAILED",
    "harness_id": "h3_abc123def456",
    "last_success": "2026-07-21T10:00:00Z",
    "tls_mode": "strict"
}
```

---

## 7. Harness-side Implementation

### 7.1 Go SDK — TLS Middleware

```go
// sdk-go/middleware/tls.go

type TLSConfig struct {
    Mode       TLSMode // strict, permissive, none
    CertFile   string  // path to harness cert PEM
    KeyFile    string  // path to harness key PEM
    CAFile     string  // path to Hermes Root CA PEM
    CRLFile    string  // path to CRL PEM
}

func NewTLSServer(cfg TLSConfig) (*http.Server, error) {
    if cfg.Mode == TLSModeNone {
        return &http.Server{Addr: ":9191"}, nil
    }

    // Load harness certificate
    cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
    if err != nil {
        return nil, fmt.Errorf("failed to load harness cert: %w", err)
    }

    // Load Hermes CA
    caCert, err := os.ReadFile(cfg.CAFile)
    if err != nil {
        return nil, fmt.Errorf("failed to load CA cert: %w", err)
    }
    caCertPool := x509.NewCertPool()
    caCertPool.AppendCertsFromPEM(caCert)

    // Load CRL
    crl, err := loadCRL(cfg.CRLFile)
    if err != nil {
        return nil, fmt.Errorf("failed to load CRL: %w", err)
    }

    tlsCfg := &tls.Config{
        Certificates: []tls.Certificate{cert},
        ClientAuth:   tls.RequireAndVerifyClientCert,
        ClientCAs:    caCertPool,
        MinVersion:   tls.VersionTLS13,
        VerifyPeerCertificate: func(rawCerts [][]byte, _ [][]*x509.Certificate) error {
            return verifyClientCert(rawCerts, caCertPool, crl)
        },
    }

    if cfg.Mode == TLSModePermissive {
        tlsCfg.ClientAuth = tls.VerifyClientCertIfGiven
    }

    return &http.Server{
        Addr:      ":9191",
        TLSConfig: tlsCfg,
    }, nil
}
```

### 7.2 Python SDK — TLS Middleware

```python
# sdk-python/h3_harness/middleware/tls.py

import ssl
import uvicorn
from pathlib import Path

class TLSConfig(BaseModel):
    mode: Literal["strict", "permissive", "none"] = "strict"
    cert_file: Path
    key_file: Path
    ca_file: Path
    crl_file: Path | None = None

def create_ssl_context(cfg: TLSConfig) -> ssl.SSLContext | None:
    if cfg.mode == "none":
        return None

    ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(cfg.cert_file, cfg.key_file)
    ctx.load_verify_locations(cafile=cfg.ca_file)

    if cfg.mode == "strict":
        ctx.verify_mode = ssl.CERT_REQUIRED
    elif cfg.mode == "permissive":
        ctx.verify_mode = ssl.CERT_OPTIONAL

    return ctx

# Usage with uvicorn
ssl_context = create_ssl_context(tls_config)
uvicorn.run(
    app,
    host="0.0.0.0",
    port=9191,
    ssl_certfile=str(tls_config.cert_file),
    ssl_keyfile=str(tls_config.key_file),
    ssl_ca_certs=str(tls_config.ca_file),
)
```

### 7.3 TypeScript SDK — TLS Middleware

```typescript
// sdk-typescript/src/middleware/tls.ts

import { readFileSync } from "fs";
import { createServer, SecureServerOptions } from "https";
import { TLSMode } from "../types";

interface TLSConfig {
  mode: TLSMode;
  certFile: string;
  keyFile: string;
  caFile: string;
  crlFile?: string;
}

export function createTLSServerOptions(cfg: TLSConfig): SecureServerOptions {
  if (cfg.mode === "none") {
    return {}; // HTTP, not HTTPS
  }

  return {
    cert: readFileSync(cfg.certFile),
    key: readFileSync(cfg.keyFile),
    ca: readFileSync(cfg.caFile),
    requestCert: cfg.mode === "strict",
    rejectUnauthorized: cfg.mode === "strict",
    minVersion: "TLSv1.3",
  };
}
```

---

## 8. Deployment Models

### 8.1 Local Development (localhost)

```
Hermes ──── plain HTTP ──── Harness
          mode: none
```

Use case: Developing a harness on the same machine. TLS adds friction without security benefit when traffic never leaves localhost.

**Configuration:**
```yaml
# .hermes/h3/harnesses/dev-harness.yaml
url: http://localhost:9191
tls_mode: none
```

Hermes logs: `WARN TLS disabled for harness dev-harness — not safe for production`

### 8.2 Same-Network (Docker, bare metal)

```
Hermes ──── mTLS ──── Harness
 10.0.1.2    |      10.0.1.3
      strict mode
```

Use case: Hermes and harness on different machines in the same VPC/datacenter. mTLS prevents lateral movement if one machine is compromised.

**Configuration:**
```yaml
# .hermes/h3/harnesses/production-harness.yaml
url: https://10.0.1.3:9191
tls_mode: strict
```

### 8.3 Cross-Network (Internet)

```
Hermes ──── mTLS ──── Internet ──── mTLS ──── Harness
         strict                      strict
         (reverse proxy              (reverse proxy
          terminates TLS             terminates TLS
          at edge)                   at edge)
```

Use case: Harness hosted by a third party, accessed over the internet. Both sides use a reverse proxy that terminates TLS at the edge, then proxies over an internal network. The edge proxy validates the client cert and passes the validated identity as a header.

**Hermes side (nginx):**
```nginx
server {
    listen 443 ssl;
    ssl_certificate /etc/nginx/certs/hermes.crt;
    ssl_certificate_key /etc/nginx/certs/hermes.key;
    ssl_client_certificate /etc/nginx/certs/ca.crt;
    ssl_verify_client on;
    ssl_protocols TLSv1.3;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header X-H3-Client-DN $ssl_client_s_dn;
    }
}
```

### 8.4 Bunker Deployment

Bunker containers communicate over Docker's internal network. TLS mode: `strict` by default, with certificates generated during `bunker connect` and injected via Docker secrets.

---

## 9. Error Handling

### 9.1 Error Codes

| Code | HTTP Status | Meaning | Retry? | User-Visible Message |
|---|---|---|---|---|
| `TLS_REQUIRED` | 426 Upgrade Required | Harness requires mTLS but Hermes connected without it | Yes (with TLS) | "Harness requires TLS. Enable TLS in harness config." |
| `TLS_CERT_INVALID` | 495 | Certificate failed validation (bad signature, wrong CA) | No | "Harness certificate is invalid. Re-pair the harness." |
| `TLS_CERT_EXPIRED` | 495 | Certificate is past its NotAfter date | No | "Harness certificate expired. Run: hermes h3 renew <id>" |
| `TLS_CERT_REVOKED` | 495 | Certificate is in the CRL | No | "Harness certificate revoked. Harness was decommissioned." |
| `TLS_HANDSHAKE_FAILED` | 525 | TLS handshake could not complete | Yes | "TLS handshake failed. Check TLS version (need 1.3+)." |
| `TLS_UNKNOWN_CA` | 495 | Certificate signed by an untrusted CA | No | "Harness certificate from unknown CA. Re-pair with Hermes CA." |
| `TLS_HOSTNAME_MISMATCH` | 495 | Certificate SAN doesn't match connected hostname | No | "TLS hostname mismatch. Check harness URL." |

### 9.2 User-Facing Error Flow

When a TLS error occurs during an agent session:

```
[harness-h3_abc123 connection]
  Status: TLS Error

  Harness certificate expired (2026-07-20).
  Session paused. Hermes will retry in 30s.

  To fix:
    $ hermes h3 renew h3_abc123
    $ hermes h3 restart h3_abc123

  Falling back to native agent loop in the meantime.
```

### 9.3 Logging

All TLS errors log at ERROR level with structured fields:

```json
{
    "level": "ERROR",
    "component": "h3.tls",
    "harness_id": "h3_abc123def456",
    "tls_error": "CERTIFICATE_EXPIRED",
    "cert_serial": "01:AB:CD:EF",
    "cert_expiry": "2026-07-20T00:00:00Z",
    "session_id": "sess_xyz789",
    "retry": false
}
```

---

## 10. Test Scenarios

### 10.1 Unit Tests (per SDK)

| ID | Test | Expected |
|---|---|---|
| TLS-UNIT-01 | `strict` mode: valid mTLS connection succeeds | 200 OK |
| TLS-UNIT-02 | `strict` mode: no client cert → rejected | TLS error, connection closed |
| TLS-UNIT-03 | `strict` mode: wrong CA client cert → rejected | CERTIFICATE_VERIFY_FAILED |
| TLS-UNIT-04 | `strict` mode: expired client cert → rejected | CERTIFICATE_EXPIRED |
| TLS-UNIT-05 | `permissive` mode: no client cert → accepted | 200 OK, WARN log |
| TLS-UNIT-06 | `permissive` mode: valid client cert → accepted | 200 OK |
| TLS-UNIT-07 | `permissive` mode: invalid client cert → rejected | CERTIFICATE_VERIFY_FAILED |
| TLS-UNIT-08 | `none` mode: plain HTTP → accepted | 200 OK, WARN log |
| TLS-UNIT-09 | TLS 1.2 handshake → rejected | PROTOCOL_VERSION |
| TLS-UNIT-10 | Revoked cert (in CRL) → rejected | CERTIFICATE_REVOKED |
| TLS-UNIT-11 | SAN mismatch → rejected | HOSTNAME_MISMATCH |

### 10.2 Integration Tests (cross-language)

| ID | Test | Expected |
|---|---|---|
| TLS-INT-01 | Go harness `strict` vs Hermes shim → mTLS handshake succeeds | ProcessRequest round-trips |
| TLS-INT-02 | Python harness `strict` vs Hermes shim → mTLS handshake succeeds | ProcessRequest round-trips |
| TLS-INT-03 | TS harness `strict` vs Hermes shim → mTLS handshake succeeds | ProcessRequest round-trips |
| TLS-INT-04 | Harness cert rotation: old cert → new cert → old cert rejected | Grace period respected |
| TLS-INT-05 | CRL update: revoke cert → next request rejected | 495 TLS_CERT_REVOKED |
| TLS-INT-06 | Health check over mTLS reports TLS status | `healthy` with TLS info |

### 10.3 End-to-End Tests

| ID | Test | Expected |
|---|---|---|
| TLS-E2E-01 | Full agent loop over mTLS (3 turns) | All turns succeed |
| TLS-E2E-02 | Agent session during cert rotation (grace period) | No interruption |
| TLS-E2E-03 | Agent session after cert expiry → fallback to native | Native loop takes over |
| TLS-E2E-04 | `hermes h3 renew` during active sessions | Sessions unaffected |

---

## 11. Security Considerations

### 11.1 Threat Model

| Threat | Mitigation | Layer |
|---|---|---|
| Eavesdropping (passive sniffing) | TLS 1.3 encryption | Transport |
| MITM (active interception) | mTLS — both sides must present valid certs | Transport |
| Certificate forgery | Ed25519 signatures, Hermes as sole CA | Transport |
| Replay attacks | TLS 1.3 0-RTT disabled by default | Transport |
| Key exfiltration (harness cert stolen) | Revoke + CRL, replace cert | Transport + App |
| Key exfiltration (Root CA stolen) | Emergency CA rotation, re-pair all harnesses | Transport |
| Downgrade to plain HTTP | Mode enforcement in H3Client, no auto-downgrade | Transport |
| Expired cert silent acceptance | Strict expiry validation, no grace beyond NotAfter | Transport |

### 11.2 Private Key Protection

- **Root CA key:** 0600 permissions, readable only by Hermes process
- **Harness keys:** 0600 permissions on harness host
- **Never in environment variables** — always file-based
- **Never in version control** — `.h3-harness.yaml` is in `.gitignore`
- **Key generation uses `os.urandom` / `crypto/rand`** — not `math/random`

### 11.3 Forward Secrecy

TLS 1.3 enforces forward secrecy via ephemeral Diffie-Hellman key exchange (all 5 cipher suites use ECDHE). Compromising the Root CA private key does not decrypt previously captured traffic.

### 11.4 Downgrade Attack Prevention

TLS 1.3 includes downgrade protection in the ServerHello.Random field. If a MITM strips the TLS 1.3 support and forces TLS 1.2, the client detects the tampering and aborts the handshake. No configuration needed — this is built into TLS 1.3.

---

## 12. Implementation Phasing

### Phase 1: Hermes-side TLS Client (shim only)

- H3Client gains TLS config (cert, key, CA, CRL)
- `hermes h3 install` generates Root CA on first run
- `hermes h3 install --harness-url` generates harness cert during pairing
- CRL file management (create on first revoke)
- TLS modes: `strict`, `permissive`, `none`
- Health check reports TLS status
- **No harness-side changes needed yet** — harnesses can stay on plain HTTP in `permissive` mode

### Phase 2: Go SDK TLS Server

- Go TLS middleware (as specified in §7.1)
- Cert loading from `.h3-harness.yaml`
- mTLS enforcement in `strict` mode
- CRL checking
- Tests: TLS-UNIT-01 through TLS-UNIT-11

### Phase 3: Python + TypeScript SDK TLS Servers

- Python TLS middleware (§7.2)
- TypeScript TLS middleware (§7.3)
- Full cross-language integration tests (TLS-INT-01 through TLS-INT-06)

### Phase 4: End-to-End Validation

- Full agent loop over mTLS (TLS-E2E-01)
- Cert rotation during active sessions (TLS-E2E-02)
- Expiry → fallback handling (TLS-E2E-03)
- Renewal with no downtime (TLS-E2E-04)

### Phase 5: Production Hardening

- Auto-renewal cron job
- Emergency CA rotation procedure
- Bunker deployment with Docker secrets
- Edge proxy configuration docs (nginx, Caddy)

---

## 13. Protocol Changes

TLS enforcement requires no protocol changes. The H3 protocol (POST /v1/process, POST /v1/result, GET /v1/health) is unchanged. TLS is transparent to the application layer — once the handshake completes, the HTTP exchange is identical.

However, the harness config and pairing flow change:

**harness_config.yaml (new fields):**
```yaml
harness_id: h3_abc123def456
url: https://my-harness.example.com:9191
tls_mode: strict
tls:
  cert_file: /etc/h3/certs/harness.crt
  key_file: /etc/h3/certs/harness.key
  ca_file: /etc/h3/certs/ca.crt
  crl_file: /etc/h3/certs/crl.pem
```

**Hermes config (new section):**
```yaml
# .hermes/h3/config.yaml
tls:
  mode: strict  # global default
  ca_dir: .hermes/h3/ca/
  cert_dir: .hermes/h3/certs/
  auto_renew: true
  renew_before_days: 30
  crl_check: true
```

---

## 14. Backward Compatibility

| Hermes Version | Harness Version | TLS Behavior |
|---|---|---|
| v1.1 (TLS-capable) | v1.0 (no TLS) | Hermes in `permissive` mode → works with warning |
| v1.1 (TLS-capable) | v1.1 (TLS-capable) | Full mTLS in `strict` mode |
| v1.0 (no TLS) | v1.1 (TLS-capable) | Plain HTTP only. Harness `strict` mode rejects unencrypted connections. |

**Migration path for existing v1.0 harnesses:**
1. Hermes upgrades to v1.1, Root CA generated
2. Per-harness TLS mode set to `permissive` (accepts plain HTTP)
3. Each harness upgraded to v1.1 SDK, cert issued via `hermes h3 renew`
4. Per-harness TLS mode switched to `strict`
5. Global default remains `strict` for all new harnesses

---

## Summary

TLS enforcement adds mandatory mTLS between Hermes and every harness. Hermes acts as the Root CA, issuing and managing all certificates. Three modes (strict, permissive, none) support the full lifecycle from development to production. Implementation is phased: Hermes-side first (shim only, no harness changes needed), then SDK-by-SDK, then end-to-end validation.

**Combined with S12 (API key auth) and S13 (rate limiting), TLS enforcement completes the three-layer defense-in-depth security model for H3.**
