# S13 — Token Rotation & Revocation (SEC-04 Implementation Spec)

**Status:** Spec  
**Version:** 1.0.0  
**Depends on:** S12 (Security & Authentication)  
**Last Updated:** 2026-07-21

---

## 1. Overview

S12 defines the high-level key lifecycle: generation (§3.2), registration (§3.3), rotation (§3.4), revocation (§3.5), and compromise response (§3.6). This document provides the **implementation-level specification** for rotation and revocation — exact CLI signatures, API endpoint schemas, SDK middleware contracts, grace-period state machines, error paths, and test scenarios.

**Scope:** SEC-04 on the task board. Complements S12; does not replace it.

**Implementation targets:**
- `shim/` — CLI commands (`rotate-key`, `revoke-key`, `rotate-identity`) + `H3Client` rotation methods
- `sdk-go/`, `sdk-python/`, `sdk-typescript/` — auth middleware rotation/revocation handlers
- `protocol/` — new JSON schemas for auth management endpoints

---

## 2. CLI Command Specifications

### 2.1 `hermes h3 rotate-key`

Rotate the API key for a registered harness. Old key remains valid for a 5-minute grace period.

```
hermes h3 rotate-key --harness-url <URL> [--grace-period <seconds>]

Options:
  --harness-url    URL of the harness (required)
  --grace-period   Override default 300s grace period (30–900s)
  --force          Skip confirmation prompt
  --json           Output JSON for scripting

Default grace period: 300 seconds (5 minutes)
```

**Interactive flow (without --force):**
```
$ hermes h3 rotate-key --harness-url http://localhost:9191

  ⚠ You are about to rotate the API key for:
    Harness: echo-harness-01 (http://localhost:9191)
    Current key: h3_kxDRTqP9m2Vj7wNcY4BfL8HsA1Qe3ZpW

    Old key will be valid for 300 seconds after rotation.
    Active sessions will NOT be disrupted.

  Continue? [y/N]: y

  ✓ Rotation initiated
  ✓ Old key valid until: 2026-07-21T03:05:00Z (300s)
  ✓ New API key: h3_Yn8QsW4pL7mKcD2RfA9BxV3JtH6ZwN5X
  ✓ Updated .hermes/h3/harnesses/<id>.yaml
  ✓ Harness acknowledged

  To revert (within grace period):
    hermes h3 rotate-key --harness-url http://localhost:9191 --revert
```

**JSON output (--json):**
```json
{
  "harness_url": "http://localhost:9191",
  "harness_id": "echo-harness-01",
  "old_key": "h3_kxDRTqP9m2Vj7wNcY4BfL8HsA1Qe3ZpW",
  "new_key": "h3_Yn8QsW4pL7mKcD2RfA9BxV3JtH6ZwN5X",
  "grace_period_seconds": 300,
  "old_key_expires_at": "2026-07-21T03:05:00Z",
  "harness_acknowledged": true
}
```

**--revert flag (during grace period only):**
```
hermes h3 rotate-key --harness-url http://localhost:9191 --revert
```
Cancels the rotation, restores old key, tells harness to discard new key. Only valid within grace period.

### 2.2 `hermes h3 revoke-key`

Immediately revoke a harness API key. All active sessions for that harness are terminated.

```
hermes h3 revoke-key --harness-url <URL> [--force] [--json]

Options:
  --harness-url    URL of the harness (required)
  --force          Skip confirmation prompt
  --json           Output JSON for scripting
```

**Interactive flow (without --force):**
```
$ hermes h3 revoke-key --harness-url http://localhost:9191

  ⚠ DANGER: You are about to REVOKE the API key for:
    Harness: echo-harness-01 (http://localhost:9191)
    Key: h3_kxDRTqP9...

  This will IMMEDIATELY:
    - Invalidate the current API key
    - Terminate all active sessions (3 sessions found)
    - Require re-registration to restore access

  This cannot be undone without re-registration.

  Continue? [y/N]: y

  ✓ Key revoked
  ✓ 3 active sessions terminated
  ✓ Harness acknowledged
  ✓ Removed from .hermes/h3/harnesses/<id>.yaml

  To re-register this harness:
    hermes h3 install --harness-url http://localhost:9191 --api-key <new-key>
```

**JSON output (--json):**
```json
{
  "harness_url": "http://localhost:9191",
  "harness_id": "echo-harness-01",
  "revoked_key": "h3_kxDRTqP9m2Vj7wNcY4BfL8HsA1Qe3ZpW",
  "sessions_terminated": 3,
  "harness_acknowledged": true,
  "re_register_required": true
}
```

### 2.3 `hermes h3 rotate-identity`

Rotate the Hermes identity token. This affects ALL registered harnesses.

```
hermes h3 rotate-identity [--grace-period <seconds>] [--force] [--json]

Options:
  --grace-period   Override default 600s grace period (60–3600s)
  --force          Skip confirmation prompt
  --json           Output JSON for scripting

Default grace period: 600 seconds (10 minutes — longer because all harnesses must update)
```

**Interactive flow:**
```
$ hermes h3 rotate-identity

  ⚠ CRITICAL: You are about to rotate the Hermes identity token.
    This affects ALL 3 registered harnesses.

    Old token valid for 600 seconds.
    All harnesses will be notified to accept the new token.

  Continue? [y/N]: y

  ✓ New identity token generated: h3_hx_a1b2c3...
  ✓ Broadcasting to 3 harnesses:
    echo-harness-01 (http://localhost:9191) — acknowledged
    langchain-harness (http://localhost:9192) — acknowledged
    crewai-harness (http://localhost:9193) — acknowledged
  ✓ Old token expires at: 2026-07-21T03:15:00Z
  ✓ Updated .hermes/h3/identity.yaml
```

**If a harness fails to acknowledge:**
```
  ⚠ echo-harness-01: connection refused — will retry
     Harness has 600s to accept new token before old is invalid.
     Run 'hermes h3 rotate-identity --status' to check progress.
```

---

## 3. API Endpoint Specifications

### 3.1 `POST /v1/auth/rotate-key`

Initiate API key rotation on the harness.

**Request:**
```http
POST /v1/auth/rotate-key HTTP/1.1
Authorization: Bearer h3_hx_<hermes-token>
Content-Type: application/json

{
  "new_api_key": "h3_Yn8QsW4pL7mKcD2RfA9BxV3JtH6ZwN5X",
  "grace_period_seconds": 300
}
```

**Request schema (JSON Schema):**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "RotateKeyRequest",
  "type": "object",
  "required": ["new_api_key"],
  "properties": {
    "new_api_key": {
      "type": "string",
      "pattern": "^h3_[A-Za-z0-9_-]{32}$",
      "description": "New API key in h3_<base64url(24B)> format"
    },
    "grace_period_seconds": {
      "type": "integer",
      "minimum": 30,
      "maximum": 900,
      "default": 300,
      "description": "How long the old key remains valid during transition"
    }
  }
}
```

**Response (200 — rotation accepted):**
```json
{
  "rotation_accepted": true,
  "old_key_expires_at": "2026-07-21T03:05:00Z",
  "grace_period_seconds": 300,
  "active_sessions": 5
}
```

**Response schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "RotateKeyResponse",
  "type": "object",
  "required": ["rotation_accepted", "old_key_expires_at", "grace_period_seconds"],
  "properties": {
    "rotation_accepted": {"type": "boolean"},
    "old_key_expires_at": {"type": "string", "format": "date-time"},
    "grace_period_seconds": {"type": "integer"},
    "active_sessions": {"type": "integer"}
  }
}
```

**Error responses:**

| Code | Meaning |
|------|---------|
| `UNAUTHORIZED` | Hermes token invalid or not registered |
| `ROTATION_IN_PROGRESS` | A rotation is already in progress for this harness |
| `INVALID_KEY_FORMAT` | `new_api_key` does not match `h3_` prefix + 32-char pattern |
| `INVALID_GRACE_PERIOD` | `grace_period_seconds` outside 30–900 range |

**Harness-side state machine:**

```
                  ┌──────────────────────┐
                  │   NORMAL             │
                  │   One active key     │
                  └──────┬───────────────┘
                         │ POST /v1/auth/rotate-key
                         ▼
                  ┌──────────────────────┐
                  │   ROTATING           │
                  │   Old key + new key  │
                  │   both valid         │
                  │   Timer: grace_period│
                  └──────┬───────────────┘
                         │
              ┌──────────┼──────────┐
              │ Timer    │ Revert   │
              │ expires  │ called   │
              ▼          ▼          │
    ┌──────────────┐ ┌──────────────┐
    │  POST-ROTATE │ │  NORMAL      │
    │  Old key     │ │  (old key    │
    │  REJECTED    │ │   restored)  │
    │  New key     │ │              │
    │  ACTIVE      │ └──────────────┘
    └──────────────┘
```

### 3.2 `POST /v1/auth/revert-rotation`

Cancel an in-progress rotation. Reverts to the old key.

**Request:**
```http
POST /v1/auth/revert-rotation HTTP/1.1
Authorization: Bearer h3_hx_<hermes-token>
Content-Type: application/json

{}
```

**Response (200):**
```json
{
  "rotation_reverted": true,
  "active_key": "h3_kxDRTqP9m2Vj7wNcY4BfL8HsA1Qe3ZpW",
  "discarded_key": "h3_Yn8QsW4pL7mKcD2RfA9BxV3JtH6ZwN5X"
}
```

**Response (409 — no rotation in progress):**
```json
{
  "error": {
    "code": "NO_ROTATION_IN_PROGRESS",
    "message": "No key rotation is currently active"
  }
}
```

### 3.3 `POST /v1/auth/revoke-key`

Immediately revoke the current API key and terminate all sessions.

**Request:**
```http
POST /v1/auth/revoke-key HTTP/1.1
Authorization: Bearer h3_hx_<hermes-token>
Content-Type: application/json

{}
```

**Response (200):**
```json
{
  "key_revoked": true,
  "sessions_terminated": 3,
  "harness_id": "echo-harness-01",
  "requires_re_registration": true
}
```

**Response schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "RevokeKeyResponse",
  "type": "object",
  "required": ["key_revoked", "sessions_terminated", "harness_id"],
  "properties": {
    "key_revoked": {"type": "boolean"},
    "sessions_terminated": {"type": "integer"},
    "harness_id": {"type": "string"},
    "requires_re_registration": {"type": "boolean"}
  }
}
```

**Post-revocation behavior:**
- All subsequent requests with the revoked key return `TOKEN_REVOKED`
- All active sessions are terminated immediately
- Harness returns to unregistered state
- Hermes client must re-register via `POST /v1/auth/register`

### 3.4 `POST /v1/auth/rotate-identity`

Notify harness of Hermes identity token rotation.

**Request:**
```http
POST /v1/auth/rotate-identity HTTP/1.1
Authorization: Bearer h3_hx_<old-hermes-token>
Content-Type: application/json

{
  "new_hermes_token": "h3_hx_f1e2d3c4b5a6...",
  "old_token_expires_at": "2026-07-21T03:15:00Z",
  "grace_period_seconds": 600
}
```

**Request schema:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "RotateIdentityRequest",
  "type": "object",
  "required": ["new_hermes_token", "old_token_expires_at"],
  "properties": {
    "new_hermes_token": {
      "type": "string",
      "pattern": "^h3_hx_[0-9a-f]{64}$",
      "description": "New Hermes identity token (64 hex chars)"
    },
    "old_token_expires_at": {
      "type": "string",
      "format": "date-time",
      "description": "When the old token stops being accepted"
    },
    "grace_period_seconds": {
      "type": "integer",
      "minimum": 60,
      "maximum": 3600,
      "default": 600
    }
  }
}
```

**Response (200):**
```json
{
  "identity_rotation_accepted": true,
  "old_token_expires_at": "2026-07-21T03:15:00Z",
  "grace_period_seconds": 600
}
```

---

## 4. Grace Period Mechanics

### 4.1 Dual-Key Acceptance Window

During rotation, the harness maintains TWO valid keys:

```
t=0: POST /v1/auth/rotate-key
     ├── old_key: ACTIVE (expires at t+grace_period)
     └── new_key: ACTIVE (permanent)

t=0 to t=grace_period:
     Both old_key AND new_key authenticate successfully.
     No session disruption — existing sessions continue with old key.
     New sessions use whichever key Hermes provides.

t=grace_period:
     old_key: EXPIRED → returns KEY_EXPIRED error
     new_key: ACTIVE only
```

### 4.2 Hermes-Side Key Management

The shim's `H3Client` must handle dual-key transitions transparently:

```python
class H3Client:
    def __init__(self, harness_url: str, api_key: str, _auth_state: AuthState = None):
        self._auth_state = _auth_state or AuthState(
            active_key=api_key,
            pending_key=None,
            pending_key_expires_at=None,
        )
    
    def _get_auth_header(self) -> str:
        """Return the appropriate auth header for the current state."""
        return f"Bearer h3_hx_{self.hermes_token}"
    
    def rotate_key(self, new_key: str, grace_period: int = 300) -> RotateKeyResult:
        """Initiate rotation. Client tracks both keys during grace period."""
        # 1. Send rotation request to harness (using current auth)
        resp = self._post("/v1/auth/rotate-key", {
            "new_api_key": new_key,
            "grace_period_seconds": grace_period,
        })
        # 2. Update local state — both keys valid
        self._auth_state.pending_key = new_key
        self._auth_state.pending_key_expires_at = time.time() + grace_period
        # 3. Update config file
        self._update_config(new_key)
        return RotateKeyResult(...)
    
    def _is_pending_key_valid(self) -> bool:
        """Check if pending key is still in grace period."""
        if self._auth_state.pending_key is None:
            return False
        return time.time() < self._auth_state.pending_key_expires_at
    
    def _handle_401(self, response) -> bool:
        """Handle auth failure. Try pending key if available."""
        error_code = response.json().get("error", {}).get("code")
        if error_code == "KEY_EXPIRED":
            # Old key expired — switch to pending
            if self._auth_state.pending_key:
                self._auth_state.active_key = self._auth_state.pending_key
                self._auth_state.pending_key = None
                return True  # retry with new key
        return False
```

### 4.3 SDK Middleware Interface

Every SDK must expose these methods on its auth middleware:

| Method | Signature | Description |
|--------|-----------|-------------|
| `HandleRotateKey` | `(newKey string, gracePeriod time.Duration) error` | Accept rotation with grace period |
| `HandleRevertRotation` | `() error` | Cancel in-progress rotation |
| `HandleRevokeKey` | `() (int, error)` | Revoke key, return terminated session count |
| `HandleRotateIdentity` | `(newToken string, expiresAt time.Time) error` | Accept Hermes identity rotation |
| `ValidateRequest` | `(r *http.Request) error` | Check auth on every request (unchanged) |

**Go interface:**
```go
type KeyRotationManager interface {
    HandleRotateKey(newKey string, gracePeriod time.Duration) error
    HandleRevertRotation() error
    HandleRevokeKey() (sessionsTerminated int, err error)
    HandleRotateIdentity(newToken string, expiresAt time.Time) error
}

// TrustStore manages trusted Hermes identities and API keys
type TrustStore interface {
    AddHermesIdentity(identity, token string) error
    RemoveHermesIdentity(identity string) error
    ValidateToken(token string) (identity string, valid bool)
    IsRevoked(token string) bool
    
    // Rotation state
    AddPendingKey(newKey string, oldKeyExpiresAt time.Time)
    RevertRotation() (activeKey string)
    IsInRotation() bool
}
```

**Python protocol:**
```python
class KeyRotationHandler(ABC):
    @abstractmethod
    async def handle_rotate_key(self, new_key: str, grace_period_seconds: int) -> RotateKeyResponse:
        ...
    
    @abstractmethod
    async def handle_revert_rotation(self) -> RevertRotationResponse:
        ...
    
    @abstractmethod
    async def handle_revoke_key(self) -> RevokeKeyResponse:
        ...
    
    @abstractmethod
    async def handle_rotate_identity(self, new_token: str, expires_at: datetime) -> RotateIdentityResponse:
        ...
```

**TypeScript interface:**
```typescript
interface KeyRotationManager {
  handleRotateKey(newKey: string, gracePeriodSeconds: number): Promise<RotateKeyResponse>;
  handleRevertRotation(): Promise<RevertRotationResponse>;
  handleRevokeKey(): Promise<RevokeKeyResponse>;
  handleRotateIdentity(newToken: string, expiresAt: Date): Promise<RotateIdentityResponse>;
}
```

---

## 5. Config File Changes

### 5.1 `.hermes/h3/harnesses/<id>.yaml` (Hermes Side)

```yaml
harness_url: http://localhost:9191
harness_id: echo-harness-01
api_key: h3_Yn8QsW4pL7mKcD2RfA9BxV3JtH6ZwN5X
protocol_version: "1.1"
tls_mode: permissive
rotation_state:
  in_progress: false
  old_key: null
  old_key_expires_at: null
last_rotated_at: "2026-07-21T03:00:00Z"
```

### 5.2 `.h3-harness.yaml` (Harness Side)

```yaml
api_key: h3_Yn8QsW4pL7mKcD2RfA9BxV3JtH6ZwN5X
harness_id: echo-harness-01
protocol_version: "1.1"
tls_mode: permissive
trust_store:
  - identity: hermes-main
    token: h3_hx_f1e2d3c4b5a6...
    registered_at: "2026-07-20T00:00:00Z"
rotation:
  in_progress: false
  old_key: null
  old_key_expires_at: null
sessions:
  max_concurrent: 50
  active_count: 3
```

---

## 6. Protocol Schema Additions

### 6.1 New Schemas to Add to `schemas/v1/`

| File | Schema | Purpose |
|------|--------|---------|
| `auth-rotate-key-request.json` | `RotateKeyRequest` | Rotation initiation |
| `auth-rotate-key-response.json` | `RotateKeyResponse` | Rotation acknowledgment |
| `auth-revert-rotation-response.json` | `RevertRotationResponse` | Revert acknowledgment |
| `auth-revoke-key-response.json` | `RevokeKeyResponse` | Revocation result |
| `auth-rotate-identity-request.json` | `RotateIdentityRequest` | Identity rotation |
| `auth-rotate-identity-response.json` | `RotateIdentityResponse` | Identity rotation ack |

### 6.2 Updated `h3-protocol.yaml`

New paths under `/v1/auth/`:

```yaml
/v1/auth/rotate-key:
  post:
    summary: Rotate harness API key
    security:
      - HermesBearerAuth: []
    requestBody:
      content:
        application/json:
          schema:
            $ref: 'schemas/v1/auth-rotate-key-request.json'
    responses:
      '200':
        description: Rotation accepted
        content:
          application/json:
            schema:
              $ref: 'schemas/v1/auth-rotate-key-response.json'
      '401':
        $ref: '#/components/responses/Unauthorized'
      '409':
        description: Rotation already in progress

/v1/auth/revert-rotation:
  post:
    summary: Revert in-progress key rotation
    security:
      - HermesBearerAuth: []
    responses:
      '200':
        content:
          application/json:
            schema:
              $ref: 'schemas/v1/auth-revert-rotation-response.json'

/v1/auth/revoke-key:
  post:
    summary: Immediately revoke API key
    security:
      - HermesBearerAuth: []
    responses:
      '200':
        content:
          application/json:
            schema:
              $ref: 'schemas/v1/auth-revoke-key-response.json'

/v1/auth/rotate-identity:
  post:
    summary: Rotate Hermes identity token
    security:
      - HermesBearerAuth: []
    requestBody:
      content:
        application/json:
          schema:
            $ref: 'schemas/v1/auth-rotate-identity-request.json'
    responses:
      '200':
        content:
          application/json:
            schema:
              $ref: 'schemas/v1/auth-rotate-identity-response.json'
```

---

## 7. New Error Codes

| Code | HTTP | Meaning |
|------|------|---------|
| `ROTATION_IN_PROGRESS` | 409 | A key rotation is already in progress for this harness |
| `NO_ROTATION_IN_PROGRESS` | 409 | Attempted to revert when no rotation is active |
| `INVALID_KEY_FORMAT` | 400 | `new_api_key` does not match `h3_` prefix + 32-char base64url pattern |
| `INVALID_GRACE_PERIOD` | 400 | `grace_period_seconds` outside 30–900 range |
| `KEY_EXPIRED` | 401 | API key past its grace period (already defined in S12 §11) |
| `TOKEN_EXPIRED` | 401 | Hermes identity token past expiry (new for identity rotation) |
| `ALREADY_REGISTERED` | 409 | Attempted to register an already-registered Hermes identity |

---

## 8. Test Scenarios

### 8.1 Rotation Success Path

```
TS-ROT-01: Basic rotation
  Given: Harness registered with key h3_AAAA
  When: POST /v1/auth/rotate-key {new_api_key: "h3_BBBB", grace_period: 300}
  Then: 200, old key valid until t+300s
  And: Both h3_AAAA and h3_BBBB authenticate during grace period
  And: After 300s, h3_AAAA returns KEY_EXPIRED
  And: h3_BBBB continues to work

TS-ROT-02: Rotation revert
  Given: Rotation in progress (h3_AAAA → h3_BBBB)
  When: POST /v1/auth/revert-rotation
  Then: 200, h3_BBBB discarded, h3_AAAA active
  And: No sessions disrupted

TS-ROT-03: Rotation idempotency
  Given: Rotation already in progress
  When: POST /v1/auth/rotate-key again
  Then: 409 ROTATION_IN_PROGRESS

TS-ROT-04: Revert with no rotation
  Given: No rotation in progress
  When: POST /v1/auth/revert-rotation
  Then: 409 NO_ROTATION_IN_PROGRESS
```

### 8.2 Revocation Success Path

```
TS-REV-01: Basic revocation
  Given: Harness registered, 3 active sessions
  When: POST /v1/auth/revoke-key
  Then: 200, sessions_terminated=3
  And: Subsequent requests return TOKEN_REVOKED
  And: Hermes removes config from .hermes/h3/harnesses/

TS-REV-02: Double revocation
  Given: Key already revoked
  When: POST /v1/auth/revoke-key again
  Then: 401 UNAUTHORIZED (no valid auth to revoke)

TS-REV-03: Re-registration after revocation
  Given: Key revoked
  When: POST /v1/auth/register with new key
  Then: 200, harness re-registered
```

### 8.3 Identity Rotation

```
TS-ID-01: Identity rotation across harnesses
  Given: 3 harnesses registered with token h3_hx_AAAA
  When: hermes h3 rotate-identity (new token h3_hx_BBBB)
  Then: All 3 harnesses acknowledge
  And: Both tokens valid during 600s grace period
  And: After 600s, h3_hx_AAAA returns TOKEN_EXPIRED

TS-ID-02: Partial identity rotation failure
  Given: 3 harnesses, 1 unreachable
  When: hermes h3 rotate-identity
  Then: 2 harnesses acknowledge, 1 reports failure
  And: CLI warns about unreachable harness
  And: Unreachable harness has 600s to accept new token

TS-ID-03: Identity rotation before expiration
  Given: Identity rotation in progress (AAAA → BBBB)
  When: Request arrives with old token AAAA during grace period
  Then: 200 OK — old token still accepted
  When: Request arrives with new token BBBB during grace period
  Then: 200 OK — new token also accepted
```

### 8.4 CLI Integration Tests

```
TS-CLI-01: rotate-key --json output matches schema
  Run: hermes h3 rotate-key --harness-url http://localhost:9191 --force --json
  Assert: stdout JSON validates against RotateKeyResponse schema
  Assert: exit code 0

TS-CLI-02: revoke-key terminates sessions
  Given: 3 active sessions via h3-test --smoke
  Run: hermes h3 revoke-key --harness-url http://localhost:9191 --force --json
  Assert: sessions_terminated >= 3
  Assert: subsequent h3-test returns auth errors

TS-CLI-03: rotate-key --revert restores old key
  Run: hermes h3 rotate-key --harness-url http://localhost:9191 --force
  Run: hermes h3 rotate-key --harness-url http://localhost:9191 --revert
  Assert: old key works, new key rejected
```

### 8.5 Race Condition Tests

```
TS-RACE-01: Grace period edge — request at t=grace_period
  Given: Rotation expires at t=300s
  When: Request sent at t=299.999s with old key
  Then: 200 OK (still valid)
  When: Request sent at t=300.001s with old key
  Then: 401 KEY_EXPIRED

TS-RACE-02: Concurrent rotation requests
  Given: Two Hermes processes (simulated)
  When: Both send POST /v1/auth/rotate-key simultaneously
  Then: One succeeds (200), one fails (409 ROTATION_IN_PROGRESS)

TS-RACE-03: Revoke during rotation
  Given: Rotation in progress
  When: POST /v1/auth/revoke-key
  Then: 200, all keys invalidated, sessions terminated
  And: Rotation state cleared
```

---

## 9. Implementation Order

### Phase A — Protocol (depends on: none)
1. Add 6 new JSON schemas to `protocol/schemas/v1/`
2. Add 4 new paths to `protocol/h3-protocol.yaml`
3. Tag `v1.1.0`

### Phase B — Shim CLI (depends on: Phase A)
1. Implement `H3Client.rotate_key()` + `revert_rotation()` + `revoke_key()` methods
2. Add `hermes h3 rotate-key` CLI subcommand
3. Add `hermes h3 revoke-key` CLI subcommand
4. Add `hermes h3 rotate-identity` CLI subcommand
5. Config file state management for rotation tracking
6. Tests: unit + integration against echo harness

### Phase C — SDK Middleware (depends on: Phase A, parallel across 3 SDKs)
1. Implement `TrustStore` with rotation state tracking (Go)
2. Implement `KeyRotationHandler` abstract class (Python)
3. Implement `KeyRotationManager` interface (TypeScript)
4. Route handlers: `/v1/auth/rotate-key`, `/v1/auth/revert-rotation`, `/v1/auth/revoke-key`, `/v1/auth/rotate-identity`
5. Grace period timer implementation
6. Session termination on revocation
7. Tests: mock Hermes client → harness → verify

### Phase D — Integration (depends on: Phase B + C)
1. End-to-end: `hermes h3 rotate-key` → echo harness → verify dual-key window
2. End-to-end: `hermes h3 revoke-key` → session termination → verify rejected
3. End-to-end: `hermes h3 rotate-identity` → all 3 SDK echo harnesses → verify
4. Race condition tests with parallel clients

---

## 10. Security Considerations

| Concern | Mitigation |
|---------|------------|
| Replay of rotation request | `decision_id` nonce prevents replay (already in protocol) |
| Attacker initiates rotation with known key | Requires valid Hermes token to call rotate-key endpoint |
| Old key leaked during grace period | Grace period is short (5 min). Revoke immediately if compromised. |
| Race between rotate and revoke | Revoke wins — clears rotation state, terminates all |
| Config file contains both keys during rotation | File permissions 0600. Both keys valid only during 5-min window. |
| Hermes crash during rotation | On restart, H3Client reads config, checks `old_key_expires_at`. If expired, promotes new key. If still valid, continues dual-key mode. |

---

*Next: Implementation per §9 order. Phase A (protocol schemas) can begin immediately.*
