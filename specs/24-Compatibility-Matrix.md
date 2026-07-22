# S24 — Compatibility Matrix

**Version:** 1.0.0
**Date:** 2026-07-21
**Status:** Complete
**Phase:** COMPAT (Compatibility Matrix)
**Covers:** COMPAT-01 through COMPAT-05
**Cross-references:** S02 (Protocol Specification), S03 (Installer & Version Compatibility), S08 (Cross-Repo Release Pipeline), S11 (Hermes Upgrade Survival), S14 (TLS Enforcement — TLS version negotiation)

---

## 1. Overview

H3 has multiple moving parts that evolve independently: Hermes gateway versions, H3 shim versions, SDK language versions, and protocol schema versions. Without explicit compatibility guarantees, a Hermes upgrade can silently break running harnesses, or a protocol change can cascade into failures across all SDKs.

This spec defines the compatibility matrix architecture: version negotiation on connect, deprecation policy with N-version backward compatibility, migration tooling, and a regression test suite that verifies every combination of supported versions.

### 1.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ COMPATIBILITY MATRIX                                            │
│                                                                 │
│  Hermes vX.y                                                    │
│    │                                                            │
│    ├── H3 Shim vA.b ── negotiate ──► Protocol vM.N ──► Harness │
│    │                                    │                      │
│    │                           SDK Go vP.Q ────┘               │
│    │                           SDK Py vR.S ────┘               │
│    │                           SDK TS vT.U ────┘               │
│    │                                                            │
│    └── Deprecation policy: N versions, N releases, N months    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ VERSION NEGOTIATION                                   │       │
│  │                                                        │       │
│  │  1. Connect → Send X-H3-Protocol-Version header       │       │
│  │  2. Harness responds with supported_versions[]        │       │
│  │  3. Shim picks highest mutual version                  │       │
│  │  4. Upgrade/downgrade adapter applied                  │       │
│  └──────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Compatibility Domains

| Domain | Components | Version Source |
|--------|-----------|---------------|
| Protocol | h3-protocol.yaml, JSON Schemas | `X-H3-Protocol-Version` header |
| Shim | h3-shim Python package | `pyproject.toml` + `h3 --version` |
| SDK Go | sdk-go Go module | `go.mod` + module path |
| SDK Python | sdk-python Python package | `pyproject.toml` |
| SDK TypeScript | sdk-typescript npm package | `package.json` |
| Harness | User-written code | Self-describes via `/v1/health` |

---

## 2. Versioning Scheme

### 2.1 Semantic Versioning (SemVer 2.0)

All H3 components use strict SemVer: `MAJOR.MINOR.PATCH`.

| Bump | Protocol | Shim | SDK | Implication |
|------|----------|------|-----|-------------|
| MAJOR | New endpoint required | Breaking API change | Breaking type change | Coordinate release across all 6 repos |
| MINOR | New optional field | New feature, backward-compat | New feature | Independent release OK |
| PATCH | Editorial fix | Bug fix | Bug fix | Independent release, no compat concern |

### 2.2 Protocol Version

The protocol version is a single integer (`v1`, `v2`, etc.) tied to the MAJOR version of `h3-protocol.yaml`.

- `v1` — Initial release (current)
- `v2` — Next major (TBD — TLS enforcement, auth headers mandatory)
- `v3` — Future (TBD — streaming gRPC)

The protocol version is NOT the same as the shim version. Multiple shim versions can speak a single protocol version.

### 2.3 Version Matrix (Current)

| Component | Current | Tested Compat | Notes |
|-----------|---------|---------------|-------|
| Protocol | v1 | v1 → v1 | Initial |
| Shim | 0.x | Protocol v1 | Pre-1.0 |
| SDK Go | 0.x | Protocol v1 | Pre-1.0 |
| SDK Python | 0.x | Protocol v1 | Pre-1.0 |
| SDK TypeScript | 0.x | Protocol v1 | Pre-1.0 |

### 2.4 Pre-1.0 Compatibility

Before any component reaches v1.0.0, the compatibility guarantees are **best-effort**:

- Protocol v1 is stable — no breaking changes without a v2 release
- Shim 0.x tracks protocol v1 — minor/patches may change internal behavior
- SDK 0.x tracks protocol v1 — minor/patches may change internal behavior
- Breaking changes in 0.x: announce in changelog, provide migration path

---

## 3. Version Negotiation Protocol

### 3.1 Connect-Time Negotiation

On every `/v1/process` and `/v1/result` call, the shim sends:

```
X-H3-Protocol-Version: 1
```

The harness MAY respond with:

```
X-H3-Supported-Protocols: 1, 2
```

If the harness does NOT respond with `X-H3-Supported-Protocols`, the shim assumes the harness supports only the version it sent (implicit single-version).

### 3.2 Negotiation Algorithm

```
1. Shim sends X-H3-Protocol-Version: <shim_version>
2. Harness responds with X-H3-Supported-Protocols: <list>
3. Shim selects highest mutual version:
   a. Intersect shim_supported ∩ harness_supported
   b. Select MAX(intersection)
   c. If intersection empty → FAIL with H3_PROTOCOL_MISMATCH (error code 412)
4. Shim records the negotiated version per-session
5. Shim sends X-H3-Negotiated-Protocol: <version> on subsequent calls
```

### 3.3 Adapter Layer

When the shim negotiates a protocol version different from its internal default, an adapter translates between the two versions:

```python
class ProtocolAdapter:
    """Translates between protocol versions."""
    
    def __init__(self, from_version: int, to_version: int):
        self.from_version = from_version
        self.to_version = to_version
    
    def adapt_request(self, request: dict) -> dict:
        """Upgrade or downgrade a ProcessRequest."""
        if self.from_version == 1 and self.to_version == 2:
            return self._upgrade_v1_to_v2(request)
        elif self.from_version == 2 and self.to_version == 1:
            return self._downgrade_v2_to_v1(request)
        return request
    
    def adapt_response(self, response: dict) -> dict:
        """Upgrade or downgrade a Decision response."""
        # Same pattern
        return response
```

### 3.4 Adapter Behaviors

| Direction | Action |
|-----------|--------|
| Upgrade (v1→v2) | Add new required fields with defaults. Set new optional fields to None/null. Log deprecation warning for removed features. |
| Downgrade (v2→v1) | Strip new fields. Convert new enum values to nearest v1 equivalent. Raise error if v2-only feature is used. |

---

## 4. Deprecation Policy

### 4.1 Three-N Rule

A component version is eligible for deprecation removal only when ALL three conditions are met:

| Rule | Condition | Example |
|------|-----------|---------|
| N+1 versions exist | Next major/minor released | v3 exists when deprecating v1 |
| N+1 releases shipped | Next version in production for 1+ release cycle | v2 has been released and deployed |
| N months elapsed | Deprecation notice active ≥ 3 months | v1 announced deprecated on 2026-07-21, removed on 2026-10-21 |

### 4.2 Deprecation Lifecycle

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌───────────────┐
│  ACTIVE      │───►│  DEPRECATED  │───►│  SUNSETTING  │───►│  REMOVED      │
│  Full support │    │  Warn only   │    │  Read-only   │    │  Not served   │
│  All features │    │  No new feat │    │  Existing OK │    │  412 on req   │
│  No warnings  │    │  Log warning │    │  No new sess │    │  Error doc    │
└─────────────┘    └──────────────┘    └─────────────┘    └───────────────┘
```

| Phase | Duration | Behavior |
|-------|----------|----------|
| ACTIVE | Until next major/minor | Full support, all features, no warnings |
| DEPRECATED | 3 months after next version released | All features work. Shim logs warning every connect: `WARN — Protocol v1 deprecated, upgrade to v2 by 2026-10-21` |
| SUNSETTING | 1 month before removal | Existing sessions continue. No new sessions allowed on deprecated version. New connections get 412 with `X-H3-Migrate-To: 2` header |
| REMOVED | After sunset period | Connections to deprecated version return 412 `X-H3-Protocol-Mismatch`. Documentation removed, adapters deleted |

### 4.3 Version Support Table (Example)

| Component | v1 | v2 | v3 |
|-----------|----|----|----|
| Protocol | ➖ SUNSETTING APR 2027 | ✅ ACTIVE | ✅ ACTIVE |
| Shim 1.x | ➖ DEPRECATED | ✅ ACTIVE | N/A |
| Shim 2.x | N/A | ✅ ACTIVE | ❄️ IN DEV |
| SDK Go 1.x | ➖ SUNSETTING | ✅ ACTIVE | N/A |

### 4.4 Announcement Channels

Deprecation notices MUST be published on ALL channels simultaneously:

1. **Changelog** — `CHANGELOG.md` entry with deprecation date and removal date
2. **Release notes** — GitHub/GitLab release description
3. **h3.sh** — Version compatibility table on website
4. **Shim startup** — Log warning on first connect with deprecated version
5. **`h3-test`** — `--compat-check` flag that warns on deprecated versions

---

## 5. Backward Compatibility Guarantees

### 5.1 Wire Format Compatibility

| Change Type | Backward Compat? | Example |
|-------------|-----------------|---------|
| Add optional field | ✅ Yes | New field in ProcessRequest, default None |
| Add optional endpoint | ✅ Yes | `/v1/auth/register` — unused by old clients |
| Change field type | ❌ No | `decision_id` UUID→string |
| Remove field | ❌ No | Remove `context` from ProcessRequest |
| Add required field | ❌ No | New mandatory header breaks old clients |
| Add enum variant | ⚠️ Yes (downgrade strips it) | New decision type, adapter converts to UNKNOWN |
| Relax constraint | ✅ Yes | `max_length: 1000` → `max_length: 2000` |
| Tighten constraint | ❌ No | `max_length: 2000` → `max_length: 1000` |

### 5.2 Semantic Compatibility

| Scenario | Guarantee | Example |
|----------|-----------|---------|
| v1 harness → v2 shim | ✅ Full backward compat | Harness returns v1 Decision → shim adapts to v2 internal format |
| v2 shim → v1 harness | ⚠️ Degraded | v2-only features (tracing) not available; v1 features work |
| v1 SDK → v2 protocol | ✅ Full backward compat | SDK types unchanged; adapter on shim side |
| v2 SDK ↔ v1 harness | ❌ Not supported | Both sides must speak v1 or shim must adapt |

### 5.3 Test Matrix

Every release MUST pass the full compatibility test matrix:

```yaml
# compat-matrix.yml — GitHub Actions matrix strategy
compat_matrix:
  protocol_versions: [v1, v2]
  shim_versions: [latest, latest-1]
  sdk_go_versions: [latest, latest-1]
  sdk_python_versions: [latest, latest-1]
  sdk_typescript_versions: [latest, latest-1]
  
  # Critical paths (tested every CI run):
  critical_paths:
    - [shim=latest, protocol=v1, sdk_go=latest]
    - [shim=latest, protocol=v1, sdk_python=latest]
    - [shim=latest, protocol=v1, sdk_typescript=latest]
    - [shim=latest-1, protocol=v1, sdk_go=latest-1]
```

---

## 6. Migration Tooling

### 6.1 `h3-test --compat` Command

Extended `h3-test` with compatibility mode:

```bash
# Test against a specific protocol version
h3-test --endpoint http://localhost:9191 --compat --protocol v1

# Test all compatible combinations
h3-test --endpoint http://localhost:9191 --compat --all-versions

# Generate compatibility report
h3-test --compat --report compat-report.json
```

### 6.2 Migration CLI (`h3 migrate`)

```
h3 migrate check           # Check current version compatibility status
h3 migrate plan v1→v2      # Generate migration plan
h3 migrate apply plan      # Apply migration plan
h3 migrate rollback        # Rollback to previous version
h3 migrate status          # Show migration state
```

### 6.3 Migration Plan Format

```json
{
  "from_version": 1,
  "to_version": 2,
  "components_affected": {
    "protocol": {"from": "1.0.0", "to": "2.0.0"},
    "shim": {"from": "0.5.0", "to": "1.0.0"},
    "sdk_go": {"from": "0.3.0", "to": "1.0.0"},
    "sdk_python": {"from": "0.4.0", "to": "1.0.0"},
    "sdk_typescript": {"from": "0.4.0", "to": "1.0.0"}
  },
  "breaking_changes": [
    "S12: auth headers required (was optional)",
    "S16: trace_id required in ProcessRequest",
    "S14: TLS verification default: strict"
  ],
  "migration_steps": [
    "1. Upgrade protocol to v2 (redocly lint, tag release)",
    "2. Upgrade SDKs (regenerate, pass tests)",
    "3. Upgrade shim (implement adapters, pass test battery)"
  ],
  "rollback_steps": [
    "1. Revert shim to previous version",
    "2. Revert SDKs to previous version",
    "3. Revert protocol to previous tag"
  ],
  "estimated_duration": "4 hours"
}
```

### 6.4 Auto-Downgrade During Rollback

When a migration is rolled back, the shim must gracefully downgrade active sessions:

1. Stop sending v2-only features (tracing headers, auth enforcement)
2. Strip v2-only fields from outbound requests
3. Set `X-H3-Negotiated-Protocol: 1` header
4. Log each downgraded session: `INFO — Session S1 downgraded to protocol v1 (rollback)`

---

## 7. CI Integration

### 7.1 Compatibility CI Workflow

A dedicated GitHub Actions workflow runs the full compatibility matrix on every protocol release:

```yaml
name: H3 Compatibility Matrix
on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  compat-matrix:
    strategy:
      matrix:
        protocol: [v1, v2]
        shim: [latest, latest-1]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build compatible versions
        run: ./scripts/build-compat.sh ${{ matrix.protocol }} ${{ matrix.shim }}
      - name: Run compatibility tests
        run: h3-test --endpoint http://localhost:9191 --compat --protocol ${{ matrix.protocol }}
      - name: Generate report
        run: h3-test --compat --report compat-report-${{ matrix.protocol }}.json
      - uses: actions/upload-artifact@v4
        with:
          name: compat-report-${{ matrix.protocol }}-${{ matrix.shim }}
          path: compat-report-*.json
```

### 7.2 Compatibility Badge

A GitHub badge in every repo README shows the current compatibility status:

```
[![Compatibility](https://img.shields.io/endpoint?url=https://h3.sh/api/compat-badge/h3)](https://h3.sh/compat)
```

The badge is generated from the latest CI compat-matrix run.

### 7.3 Pre-Release Gate

No protocol release may proceed with a RED compatibility status. The release workflow checks the latest compat CI run before publishing:

```bash
./scripts/check-compat.sh --block-on-failure
```

---

## 8. SDK Contracts

### 8.1 Go — Compatibility Check

```go
// CheckCompatibility verifies the harness supports the required protocol version.
// Returns (negotiated_version, error).
func CheckCompatibility(ctx context.Context, client *H3Client, requiredVersion int) (int, error) {
    resp, err := client.Health(ctx)
    if err != nil {
        return 0, fmt.Errorf("health check failed: %w", err)
    }
    
    supported := resp.SupportedProtocolVersions
    if len(supported) == 0 {
        supported = []int{1} // default if not advertised
    }
    
    negotiated := highestMutual(requiredVersion, supported)
    if negotiated == 0 {
        return 0, fmt.Errorf("incompatible: shim requires v%d, harness supports %v",
            requiredVersion, supported)
    }
    return negotiated, nil
}
```

### 8.2 Python — Compatibility Check

```python
def check_compatibility(client: H3Client, required_version: int = 1) -> int:
    """Verify harness supports the required protocol version."""
    health = client.health()
    supported = health.get("supported_versions", [1])
    
    mutual = set([required_version]) & set(supported)
    if not mutual:
        raise IncompatibleVersionError(
            f"Shim requires v{required_version}, harness supports {supported}"
        )
    return max(mutual)
```

### 8.3 TypeScript — Compatibility Check

```typescript
async function checkCompatibility(
  client: H3Client, 
  requiredVersion: number = 1
): Promise<number> {
  const health = await client.health();
  const supported = health.supportedVersions ?? [1];
  
  const mutual = supported.filter(v => v === requiredVersion);
  if (mutual.length === 0) {
    throw new IncompatibleVersionError(
      `Shim requires v${requiredVersion}, harness supports ${supported}`
    );
  }
  return Math.max(...mutual);
}
```

---

## 9. CLI Surface

### 9.1 `h3 compatibility` Command

```
h3 compatibility check [--endpoint URL]     # Check harness protocol version
h3 compatibility matrix                     # Show full version support table
h3 compatibility policy                     # Show deprecation policy
h3 compatibility report                     # Generate compatibility report
```

### 9.2 `h3 migrate` Command (detailed)

```
h3 migrate check                            # Show current+latest versions
h3 migrate plan [--from v1] [--to v2]       # Generate migration plan
h3 migrate apply <plan-file>                # Execute migration plan
h3 migrate rollback                         # Rollback to previous version
h3 migrate status                           # Show migration state
h3 migrate dry-run                          # Validate plan without executing
```

---

## 10. Error Codes

| Code | Name | HTTP | Description |
|------|------|------|-------------|
| COMPAT-01 | PROTOCOL_MISMATCH | 412 | No mutually supported protocol version |
| COMPAT-02 | VERSION_DEPRECATED | 412 | Requested version is deprecated, upgrade available |
| COMPAT-03 | VERSION_SUNSET | 412 | Requested version is sunset, must upgrade |
| COMPAT-04 | MIGRATION_IN_PROGRESS | 409 | Migration is in progress, retry later |
| COMPAT-05 | MIGRATION_FAILED | 500 | Migration could not complete |
| COMPAT-06 | COMPAT_CHECK_FAILED | 500 | Compatibility self-check failed |

---

## 11. Test Plan

### 11.1 Unit Tests

| ID | Test | Description |
|----|------|-------------|
| COMPAT-U-01 | negotiate_highest_mutual | Both sides share version → pick highest mutual |
| COMPAT-U-02 | negotiate_no_mutual | No shared version → return error |
| COMPAT-U-03 | negotiate_harness_implicit | Harness doesn't advertise → assume v1 |
| COMPAT-U-04 | adapt_upgrade_v1_to_v2 | v1 request fields → v2 format with defaults |
| COMPAT-U-05 | adapt_downgrade_v2_to_v1 | v2 fields stripped for v1 harness |
| COMPAT-U-06 | adapt_v2_feature_not_in_v1 | v2-only feature → nearest equivalent |
| COMPAT-U-07 | deprecation_lifecycle | ACTIVE→DEPRECATED→SUNSETTING→REMOVED |
| COMPAT-U-08 | deprecation_three_n_rule | All 3 conditions must be met |
| COMPAT-U-09 | deprecation_warning_logged | DEPRECATED phase logs warning on connect |
| COMPAT-U-10 | migration_plan_generation | Plan includes all breaking changes |

### 11.2 Integration Tests

| ID | Test | Description |
|----|------|-------------|
| COMPAT-I-01 | shim_latest_harness_v1 | Latest shim connects to v1 harness |
| COMPAT-I-02 | shim_latest_harness_v2 | Latest shim connects to v2 harness |
| COMPAT-I-03 | shim_previous_harness_latest | Previous shim connects to latest harness |
| COMPAT-I-04 | full_roundtrip_v1 | Complete process→result cycle with v1 |
| COMPAT-I-05 | full_roundtrip_v2 | Complete process→result cycle with v2 |
| COMPAT-I-06 | migration_apply_rollback | Apply migration, rollback, verify v1 works |
| COMPAT-I-07 | deprecated_harness_connect | HAR with deprecated version → warning logged |
| COMPAT-I-08 | sunset_harness_connect | HAR with sunset version → 412 |

### 11.3 E2E Tests

| ID | Test | Description |
|----|------|-------------|
| COMPAT-E2E-01 | compat_matrix_all_green | Full CI matrix passes for all supported combos |
| COMPAT-E2E-02 | cross_version_test_battery | h3-test 43/43 on v1 AND v2 harnesses |
| COMPAT-E2E-03 | migration_blue_green | Blue v1, Green v2, migrate, rollback, verify |

---

## 12. Migration Guide

### 12.1 v1 → v2 Migration Steps

```
Phase 1: Audit
  └── h3 migrate check → verify current version
  └── h3 migrate plan v1→v2 → review breaking changes

Phase 2: Protocol
  └── Update h3-protocol.yaml to v2
  └── Run redocly lint
  └── Tag release → triggers SDK regeneration

Phase 3: SDKs
  └── SDKs auto-regenerate from protocol
  └── Run full test suites
  └── Publish new SDK versions

Phase 4: Shim
  └── Implement protocol v2 adapter
  └── Version negotiation logic
  └── Deprecation warnings for v1

Phase 5: Rollout
  └── Deploy shim with dual-protocol support
  └── Gradually migrate harnesses
  └── Monitor session health during migration

Phase 6: Cleanup (after sunset)
  └── Remove v1 adapters
  └── Remove v1 test matrix entries
  └── Update documentation
```

### 12.2 Rollback Procedure (v2 → v1)

```
1. h3 migrate rollback
2. Verify: h3-test --endpoint http://localhost:9191 --protocol v1
3. Verify: h3 compatibility check --endpoint http://localhost:9191
4. Active sessions are downgraded gracefully (see §6.4)
5. Shutdown v2-only infrastructure
```

---

## 13. Security Considerations

| Threat | Mitigation |
|--------|------------|
| Downgrade attack (attacker forces v1 negotiation) | Shim rejects v1 if auth is required (S12 §3.1). Negotiation is server-authoritative — harness declares what it supports, shim picks. |
| Version spoofing | `X-H3-Protocol-Version` is advisory on the wire; the negotiated version is stored per-session in a signed context object (S18 distributed tracing — session trace ID integrity). |
| Migration data corruption | Migration is read-only until validated. Blue/green deployment ensures zero data loss on rollback. |
| Stale version lingering | Deprecation policy enforces removal: 3N rule ensures the ecosystem has migrated before removal. |

---

## 14. Performance Budget

| Operation | Budget | Measurement |
|-----------|--------|-------------|
| Version negotiation | <5ms | Time from connect to negotiated version selected |
| Adapter (upgrade) | <1ms | v1→v2 field transformation |
| Adapter (downgrade) | <1ms | v2→v1 field stripping |
| Compat CI matrix (full) | <30m | All supported combinations |
| Migration plan generation | <10s | Scanning all components |

---

## 15. Open Questions / Future Work

1. **Protocol version discovery from h3.sh:** Should h3.sh serve a `/versions.json` endpoint that lists all supported protocol versions and their release dates?
2. **API key version binding:** When a harness registers an API key (SEC-02), should the key be bound to a specific protocol version?
3. **Automatic SDK downgrade on incompatible harness:** Should the shim auto-detect that the harness only supports v1 and downgrade SDK calls transparently?
4. **Performance test baseline:** The CI compat matrix will need a baseline run time. First pass with all-empty adapters should measure <5s per combination.
5. **UniFFI bindings:** If an SDK adds UniFFI-based bindings (Rust→Python), the compat matrix grows. Consider adding a `compat-tier` label to SDK releases.
