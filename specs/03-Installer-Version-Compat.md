# S03 — Installer & Version Compatibility

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Installation Methods

H3 has two install surfaces:

| Surface | What Gets Installed | Who Installs |
|---|---|---|
| **Hermes-side shim** | Python package inside Hermes Core | Hermes maintainers (CI/CD) |
| **Harness-side SDK** | Language-specific library | Harness developers |

---

## 2. Hermes-Side Installer

### 2.1 `hermes h3 install` CLI

```bash
# Install H3 plugin from PyPI
hermes h3 install

# Install specific version
hermes h3 install --version 1.0.0

# Install from local path (development)
hermes h3 install --path /home/kara/h3/sdks/python

# Install with gRPC support
hermes h3 install --transport grpc

# Verify installation
hermes h3 verify
```

### 2.2 What It Does

1. **Check Hermes version** — H3 shim is version-gated (see §3)
2. **Install Python package** — `pip install hermes-h3-shim==<compatible_version>`
3. **Register plugin** — Add to `~/.hermes/profiles/<active>/config.yaml`:
   ```yaml
   plugins:
     h3:
       enabled: true
       package: hermes-h3-shim
       version: 1.0.0
   ```
4. **Add toolset** — H3 shim tools become available in agent sessions
5. **Run health check** — Verify the shim loads without import errors
6. **Report** — Print compatibility matrix, available harness configs

### 2.3 Uninstall

```bash
hermes h3 uninstall
# Removes plugin registration, uninstalls Python package, cleans config
```

### 2.4 Auto-Update with Hermes

On `hermes update`, the updater:
1. Reads current H3 plugin version
2. Checks compatibility with target Hermes version
3. If compatible: upgrades H3 to latest compatible version
4. If incompatible: **blocks update** with explanation:
   ```
   Hermes 0.19.0 requires H3 >= 2.0.0 (you have 1.0.0).
   Run: hermes h3 install --version 2.0.0
   Then: hermes update
   ```

---

## 3. Version Compatibility Matrix

### 3.1 Contract

H3 protocol version is **semantic**: `MAJOR.MINOR.PATCH`

| Version Change | Impact |
|---|---|
| **MAJOR bump** | Breaking protocol changes. Old harnesses won't work. Hermes blocks incompatible versions. |
| **MINOR bump** | New decision types, optional fields. Backward compatible. Old harnesses work, new features ignored. |
| **PATCH bump** | Bug fixes, docs. No protocol changes. |

### 3.2 Compatibility Table

| Hermes Version | H3 Shim Version | Protocol Version | gRPC Support | Status |
|---|---|---|---|---|
| 0.18.x | 1.0.x | 1.0 | ❌ (REST only) | Current |
| 0.19.x (planned) | 1.1.x | 1.0 | ✅ Beta | Planned |
| 0.20.x (planned) | 2.0.x | 2.0 | ✅ Stable | Planned |

### 3.3 Deprecation Policy

- **MAJOR version N-1** supported for 6 months after N release
- **Deprecation warnings** logged for 3 months before removal
- **Migration guide** published with every MAJOR bump
- **Protocol bridges** provided for 1 MAJOR version gap (e.g., H3 2.0 harness can talk to H3 1.0 shim via adapter)

### 3.4 Compatibility Check Flow

```
Hermes starts
  │
  ├─► Load H3 plugin
  ├─► Read plugin protocol_version (e.g., "1.0")
  ├─► Read Hermes minimum_protocol_version (e.g., "1.0")
  ├─► IF plugin_version < minimum:
  │     Log ERROR "H3 plugin too old. Minimum: 1.0, Have: 0.9"
  │     Disable H3 plugin
  │     Sessions fall back to native
  └─► IF compatible:
        Load harness configs
        Start health check loop
```

---

## 4. Harness-Side SDK Installation

### 4.1 Go

```bash
go get github.com/coding-herms/h3-sdk-go@v1.0.0
```

```go
import "github.com/coding-herms/h3-sdk-go/harness"
```

### 4.2 Python

```bash
pip install h3-harness-sdk
```

```python
from h3_harness import Harness, Decision, DecisionType
```

### 4.3 TypeScript

```bash
npm install @coding-herms/h3-harness-sdk
# or
bun add @coding-herms/h3-harness-sdk
```

```typescript
import { Harness, Decision, DecisionType } from '@coding-herms/h3-harness-sdk';
```

---

## 5. SDK Version Compatibility

SDKs version independently from the shim, but follow the same protocol version:

| Protocol Version | Go SDK | Python SDK | TS SDK |
|---|---|---|---|
| 1.0 | 1.0.x | 1.0.x | 1.0.x |
| 2.0 (planned) | 2.0.x | 2.0.x | 2.0.x |

SDK minor versions add helpers/examples but don't break the protocol.

---

## 6. Harness Quickstart Templates

### 6.1 `hermes h3 scaffold`

```bash
# Generate a new harness in any language
hermes h3 scaffold my-harness --lang go
hermes h3 scaffold my-harness --lang python
hermes h3 scaffold my-harness --lang typescript
```

Generates:
```
my-harness/
├── main.go           # or main.py / index.ts
├── harness.go         # Harness struct with Process/Result handlers
├── go.mod             # or requirements.txt / package.json
├── Dockerfile         # Optional containerized harness
├── README.md          # "How to run, test, configure"
└── test_battery.sh    # Runs the compliance suite against localhost:9191
```

### 6.2 Template Harness (Go)

```go
package main

import (
    "encoding/json"
    "net/http"

    "github.com/coding-herms/h3-sdk-go/harness"
)

func main() {
    h := harness.New()

    http.HandleFunc("/v1/health", h.HandleHealth)
    http.HandleFunc("/v1/process", h.HandleProcess)
    http.HandleFunc("/v1/result", h.HandleResult)
    http.HandleFunc("/v1/cancel", h.HandleCancel)

    http.ListenAndServe(":9191", nil)
}
```

---

## 7. Installer Maintenance

### 7.1 Hermes Version Matrix (source of truth)

File: `h3/versions.yaml` in the Hermes repo

```yaml
hermes_versions:
  - hermes: "0.18.0"
    h3_shim: "1.0.0"
    protocol: "1.0"
    min_h3: "1.0.0"
    max_h3: "1.0.x"
    grpc: false
    status: "current"

  - hermes: "0.19.0"
    h3_shim: "1.1.0"
    protocol: "1.0"
    min_h3: "1.0.0"
    max_h3: "1.x.x"
    grpc: true
    status: "planned"
```

### 7.2 CI/CD for Version Matrix

```
PR to h3 repo
  │
  ├─► Run compatibility test: current Hermes + PR H3 version
  ├─► Run compatibility test: all supported Hermes versions + PR H3 version
  ├─► Update versions.yaml on merge
  └─► Publish SDK packages to registries (PyPI, npm, Go modules)
```

### 7.3 Hermes Update Guard

When `hermes update` runs, the pre-update hook:
1. Fetches `h3/versions.yaml` from Hermes repo
2. Checks current H3 version against target Hermes version
3. If incompatible: **refuses update** with actionable instructions
4. If compatible: runs `hermes h3 install` as part of the update

### 7.4 Backward Compatibility Testing

Test harnesses that exercise the full protocol against every Hermes+H3 version pair:

```
test_matrix:
  - hermes: 0.18.0, h3_shim: 1.0.0, harnesses: [consensus, langchain, crewai]
  - hermes: 0.19.0, h3_shim: 1.1.0, harnesses: [consensus, langchain, crewai]
  - hermes: 0.19.0, h3_shim: 1.0.0, harnesses: [consensus, langchain, crewai]  # back-compat
```

---

## 8. Docker-Based Harness Deployment

For harnesses that need isolation or run on separate hosts:

```dockerfile
FROM python:3.11-slim
RUN pip install h3-harness-sdk
COPY harness.py .
EXPOSE 9191
CMD ["python", "harness.py"]
```

```yaml
# Hermes config
harnesses:
  my-harness:
    endpoint: http://h3-harness:9191
    transport: rest
```

---

## 9. Installation Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `hermes h3 install` fails | Python 3.11+ not found | Install Python 3.11 via pyenv |
| Plugin loads but no harness config | Config not migrated | `hermes h3 init` to regenerate config |
| "Protocol version mismatch" | SDK too old/new | Install matching SDK version |
| Health check timeout | Harness not running | `hermes h3 scaffold` → `go run .` |
| gRPC not available | Installed without gRPC | `hermes h3 install --transport grpc` |
