# S08 — Cross-Repo Release Pipeline

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. The Problem

6 repos, one protocol. When `get-h3/protocol` changes, 5 repos need regeneration and testing. Without automation, releases drift. A harness built against SDK v1.0 won't work with Shim v1.1.

## 2. Release Topology

```
get-h3/protocol (tag: v1.0.0)
    │
    │  schema change → new tag (v1.0.1)
    │
    ├──► get-h3/shim         detect new tag → regenerate → test → release
    ├──► get-h3/sdk-go       detect new tag → regenerate → test → release
    ├──► get-h3/sdk-python   detect new tag → regenerate → test → release
    └──► get-h3/sdk-typescript detect new tag → regenerate → test → release
    
get-h3/h3 (docs) — updated manually on release
```

---

## 3. Protocol Release (Source of Truth)

### Trigger: Tag push on `get-h3/protocol`

```yaml
# .github/workflows/release.yml
name: Protocol Release
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate schemas
        run: |
          npm install -g ajv-cli
          ./tests/validate-schemas.sh
      - name: Validate OpenAPI
        run: |
          npm install -g @redocly/cli
          redocly lint h3-protocol.yaml
      - name: Round-trip tests
        run: ./tests/round-trip/run-all.sh

  publish:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          generate_release_notes: true
      - name: Dispatch to downstream repos
        run: |
          for repo in shim sdk-go sdk-python sdk-typescript; do
            gh api repos/get-h3/$repo/dispatches \
              -f event_type=protocol-update \
              -f client_payload='{"protocol_version":"${{ github.ref_name }}"}'
          done
```

---

## 4. Downstream Repo Release (SDKs + Shim)

### Trigger: `protocol-update` repository dispatch OR manual workflow

```yaml
# .github/workflows/sync-protocol.yml (in each SDK/shim repo)
name: Sync Protocol
on:
  repository_dispatch:
    types: [protocol-update]
  workflow_dispatch:
    inputs:
      protocol_version:
        description: 'Protocol tag (e.g., v1.0.1)'
        required: true

jobs:
  regenerate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Fetch protocol schemas
        run: |
          VERSION="${{ github.event.client_payload.protocol_version || inputs.protocol_version }}"
          curl -sL "https://github.com/get-h3/protocol/archive/refs/tags/${VERSION}.tar.gz" | tar xz
      - name: Regenerate types
        run: make generate
      - name: Run compliance tests
        run: |
          make run-example &
          sleep 3
          pip install hermes-h3-shim
          h3-test --endpoint http://localhost:9191
      - name: Commit generated code
        run: |
          git add -A
          git commit -m "sync: regenerate from protocol $VERSION" || true
      - name: Tag and release
        run: |
          VERSION="${{ github.event.client_payload.protocol_version || inputs.protocol_version }}"
          git tag "$VERSION"
          git push --tags
```

---

## 5. Version Alignment

All repos in a release wave share the same version tag:

```
Protocol v1.0.0
├── Shim v1.0.0
├── SDK Go v1.0.0
├── SDK Python v1.0.0
└── SDK TypeScript v1.0.0
```

**Exception:** A repo can release PATCH versions independently for bug fixes that don't involve schema changes:

```
Protocol v1.0.0
├── Shim v1.0.1  ← bug fix in shim logic, no schema change
├── SDK Go v1.0.0
```

---

## 6. Release Checklist (Manual Override)

For major/minor releases, a human must:

1. [ ] Protocol: tag pushed, schemas validated, GitHub Release created
2. [ ] Each SDK: regenerated types committed, compliance tests pass
3. [ ] Shim: regenerated protocol.py, test battery passes against all SDK examples
4. [ ] h3.sh docs: updated version matrix, examples, changelog
5. [ ] DuckBrain: `/spec/h3/` entries updated with new version info
6. [ ] Announcement: Discord, X, Hermes changelog

---

## 7. Package Registries

| Repo | Registry | Package Name | Push Trigger |
|---|---|---|---|
| shim | PyPI | `hermes-h3-shim` | Tag push + compliance pass |
| sdk-go | Go Module Proxy | `github.com/get-h3/sdk-go` | Tag push (auto) |
| sdk-python | PyPI | `h3-harness-sdk` | Tag push + compliance pass |
| sdk-typescript | npm | `@get-h3/h3-harness-sdk` | Tag push + compliance pass |

### PyPI Trusted Publisher (shim + sdk-python)

```yaml
- name: Publish to PyPI
  uses: pypa/gh-action-pypi-publish@release/v1
  with:
    packages-dir: dist/
```

### npm Provenance (sdk-typescript)

```yaml
- name: Publish to npm
  run: npm publish --provenance --access public
  env:
    NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

---

## 8. Compliance Badge System

Every SDK repo displays a badge showing protocol version and compliance status:

```
[![H3 Protocol v1.0](https://img.shields.io/badge/H3-v1.0-8b5cf6)](https://github.com/get-h3/protocol)
[![Compliance](https://img.shields.io/badge/compliance-43%2F43-brightgreen)](https://github.com/get-h3/shim)
```

Badges update automatically via the release pipeline.

---

## 9. Breaking Change Policy

| Change | Protocol Version | Downstream Impact |
|---|---|---|
| New optional field | MINOR bump | Regenerate, no code changes needed |
| New decision type | MINOR bump | Regenerate, add case to decision handler |
| Remove decision type | MAJOR bump | Migration required, 6-month deprecation |
| Rename field | MAJOR bump | Migration required |
| Change field type | MAJOR bump | Migration required |

**Deprecation:** Old versions supported for 6 months. Warning logged for 3 months before removal. Protocol bridges provided for 1 major version gap.
