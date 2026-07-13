# S11 — Hermes Upgrade Survival & Migration

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. The Problem

Hermes updates. The H3 shim lives inside Hermes Core. When Hermes changes, H3 must survive:

- Plugin API changes
- Tool registry changes (new tools, removed tools, parameter changes)
- Model router changes (new providers, removed providers)
- Config format changes
- Gateway changes (new platforms, deprecated transports)
- Session management changes

Without explicit survival design, every Hermes update becomes a firefight. **We learned this from the v0.17→v0.18 upgrade** — 6 root causes, 4 hours recovery, 56 gateway crashes.

---

## 2. The Patterns That Break

### 2.1 Auto-Stashed Patches

**Problem:** `hermes update` auto-stashes local modifications. If H3 has patches to Hermes internals (like the LSP idle reaper), those get stashed and lost.

**Fix:** H3 must be a **plugin**, not a patch. All code in `hermes_cli/agent/shims/h3/` is version-controlled and shipped via PyPI — never patched in-place.

### 2.2 Config Migration

**Problem:** Hermes config format changes (new fields, renamed sections, moved keys). H3 config (`harnesses:`, `sessions:`) can silently break.

**Fix:** H3 config has a **schema version**:
```yaml
harnesses:
  _schema: 1  # H3 config schema version
  consensus:
    endpoint: http://localhost:9191
```

On Hermes start, H3 loader:
1. Reads `_schema` version
2. Runs migration if needed (v1 → v2, etc.)
3. Validates migrated config
4. Warns if migration produced unexpected results

### 2.3 Tool Registry Changes

**Problem:** Hermes adds, removes, or renames tools. Harnesses that request removed tools crash.

**Fix:** The shim is a compatibility layer:
```python
class ToolRegistryAdapter:
    """Maps harness tool requests to current Hermes tool registry."""
    
    def __init__(self, actual_tools: dict):
        self.actual = actual_tools
        self.aliases = {
            # Legacy tool names → current
            "search": "web_search",
            "browser_open": "browser_navigate",
        }
        self.removed = {
            # Tools removed from Hermes → stub error
            "execute_code": "Removed. Use terminal() instead.",
        }
    
    def resolve(self, tool_name: str):
        if tool_name in self.removed:
            raise ToolRemovedError(self.removed[tool_name])
        return self.actual.get(self.aliases.get(tool_name, tool_name))
```

### 2.4 Model Provider Changes

**Problem:** Providers get renamed, removed, or change API. Harnesses request models that no longer route.

**Fix:** Model router adapter:
```python
class ModelRouterAdapter:
    def __init__(self, actual_models: list):
        self.actual = {m["name"]: m for m in actual_models}
        self.fallbacks = {
            "deepseek-v4-pro": "glm-5.2",  # If v4-pro unavailable, try GLM
        }
    
    def resolve(self, model_name: str):
        if model_name in self.actual:
            return self.actual[model_name]
        fallback = self.fallbacks.get(model_name)
        if fallback and fallback in self.actual:
            logger.warning(f"Model {model_name} unavailable, falling back to {fallback}")
            return self.actual[fallback]
        raise ModelNotFoundError(f"Model {model_name} not available")
```

---

## 3. Upgrade Pre-Flight Hook

Before `hermes update` runs, H3 checks:

```python
# hermes_cli/agent/shims/h3/upgrade_check.py

def pre_update_check(target_hermes_version: str) -> UpgradeCheckResult:
    """Run before hermes update. Returns: OK, WARN, or BLOCK."""
    
    checks = []
    
    # 1. Protocol compatibility
    compat = version_matrix.get(target_hermes_version)
    if not compat:
        return BLOCK("H3 has no compatibility data for Hermes {target_hermes_version}")
    
    # 2. Current H3 version
    current = get_current_h3_version()
    if current < compat.min_h3:
        return BLOCK(f"H3 {current} too old for Hermes {target_hermes_version}. "
                     f"Run: hermes h3 install --version {compat.h3_shim}")
    
    # 3. Active harness health
    for name, harness in active_harnesses():
        try:
            harness.health()
        except:
            checks.append(WARN(f"Harness '{name}' is unreachable. "
                               f"Sessions will fall back to native after update."))
    
    # 4. Config schema version
    config_schema = read_h3_config().get("_schema", 0)
    if config_schema < CURRENT_CONFIG_SCHEMA:
        checks.append(WARN(f"H3 config schema v{config_schema} will be migrated to v{CURRENT_CONFIG_SCHEMA}"))
    
    if any(c.severity == "BLOCK" for c in checks):
        return BLOCK("\n".join(str(c) for c in checks))
    elif checks:
        return WARN("\n".join(str(c) for c in checks))
    return OK
```

---

## 4. Post-Upgrade Verification

After `hermes update`:

```bash
hermes h3 verify
```

Runs:
1. Shim imports without errors
2. Plugin registered in config
3. All harness health checks pass
4. Test battery runs against at least one harness
5. Config schema migration completed cleanly
6. Version matrix confirms compatibility

---

## 5. Rollback Plan

If an upgrade breaks H3:

```bash
# Revert to previous Hermes version
hermes downgrade --version 0.18.0

# Restore H3 config from backup
cp ~/.hermes/backups/h3-config-20260712.yaml ~/.hermes/profiles/default/config.yaml

# Verify
hermes h3 verify
```

H3 configs are backed up to `~/.hermes/backups/` before every `hermes update` and every `hermes h3 install`.

---

## 6. Compatibility Test Matrix

CI must run the test battery against every supported Hermes+H3 version pair:

```yaml
# .github/workflows/compat-matrix.yml
strategy:
  matrix:
    hermes: ["0.18.0", "0.18.1", "0.19.0"]
    h3_shim: ["1.0.0", "1.1.0"]
    harness: ["echo-go", "echo-python", "echo-typescript"]
    exclude:
      - hermes: "0.18.0"
        h3_shim: "1.1.0"  # 1.1 requires 0.19+
```

---

## 7. Hermes Version → H3 Version Map

Maintained in `get-h3/protocol/versions.yaml`:

```yaml
hermes_versions:
  - hermes: "0.18.0"
    h3_shim: "1.0.0"
    protocol: "1.0"
    min_h3: "1.0.0"
    max_h3: "1.0.x"
    grpc: false
    status: "current"
    notes: "First H3 release. REST only."

  - hermes: "0.19.0"
    h3_shim: "1.1.0"
    protocol: "1.0"
    min_h3: "1.0.0"
    max_h3: "1.x.x"
    grpc: true
    status: "planned"
    notes: "gRPC beta. New wait.poll_endpoint field."

  - hermes: "0.20.0"
    h3_shim: "2.0.0"
    protocol: "2.0"
    min_h3: "2.0.0"
    max_h3: "2.x.x"
    grpc: true
    status: "planned"
    notes: "Breaking: streaming results, session persistence API."
```

This file is the **single source of truth** for compatibility. It feeds:
- `hermes h3 install` version resolution
- `hermes update` pre-flight check
- CI compatibility matrix
- h3.sh version picker
