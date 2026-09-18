# S10 — H3 Website & Developer Docs

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Purpose

The H3 website (`https://get-h3.github.io/h3/`; legacy `h3.sh` domain is dead — NXDOMAIN) is the public face of H3. A developer lands here, understands what H3 is in 10 seconds, picks their language, and has a working harness in under 30 minutes.

**Implementation status (2026-09-18):** the site ships as a static GitHub Pages deploy of this repo's `docs/` tree. Live today: `/` (`docs/index.html`), `/guide.html`, `/protocol.html`, `/sdk.html`, `/migration.html`, `/integration.md` and the three static conformance SVGs under `/badge/`. Everything else this spec names — the `/docs/...` route set in §4, the verify endpoint in §5, and the registry/dashboard of S25 — is **planned — not implemented**: the published tree has no `api/`, `verify/`, `certified/` or `specs/` path, and each of those 404s.

---

## 2. Site Structure

```
get-h3.github.io/h3
├── Hero                 ← "BYO harness. Keep the platform." + 3-line code example
├── What Is H3           ← Architecture diagram, Hermes/harness split
├── How It Works         ← Animated sequence: Telegram → Hermes → H3 → Your Harness
├── Quickstart           ← Language picker (Go | Python | TypeScript) → copy-paste code
├── Protocol Reference   ← Full API docs (generated from OpenAPI)
├── Test Battery         ← "Run 46 tests against your harness in 5 seconds"
├── SDKs                 ← Links to each SDK repo + npm/PyPI/Go badges
├── Compliance Badges    ← "Put this in your README to show you're H3-compliant"
└── Community            ← Discord, GitHub discussions, X
```

---

## 3. Quickstart Flow (The Critical Path)

The goal: zero → working harness in < 30 minutes.

### Step 1: Pick language
```
[Go] [Python] [TypeScript]
```

### Step 2: Install SDK
```bash
# Go
go get github.com/get-h3/sdk-go

# Python
pip install h3-harness-sdk

# TypeScript
npm install github:get-h3/sdk-typescript
```

### Step 3: Copy-paste the echo harness
(Full working code — same examples from S04 SDK quickstarts)

### Step 4: Run it
```bash
go run .
# or: python harness.py
# or: npx tsx harness.ts
```

### Step 5: Test it
```bash
# Gated on P3-10 (PyPI publish); source install until then:
git clone https://github.com/get-h3/shim && cd shim && pip install -e .
h3-test --endpoint http://localhost:9191
```

### Step 6: Configure Hermes
```yaml
# ~/.hermes/profiles/default/config.yaml
harnesses:
  my-harness:
    endpoint: http://localhost:9191
    transport: rest

sessions:
  "telegram:YOUR_USER_ID":
    harness: my-harness
```

### Step 7: Message yourself on Telegram
Your harness responds.

---

## 4. Docs Pages

**Status (2026-09-18):** nothing under `/docs/` is published — GitHub Pages serves the `docs/`
tree at the site root, so the routes below are design intent and the live equivalent is named
where one exists. `✅ published` = served today; `⚠️ planned` = no such path exists in the
published tree (HTTP 404), i.e. **planned — not implemented**.

| Page | Content | Status |
|---|---|---|
| `/` | Landing + Quickstart | ✅ published (`docs/index.html`) |
| `/docs/protocol` | Full protocol reference (generated from OpenAPI) | ⚠️ planned — published today as `/protocol.html` (hand-written; OpenAPI generation is not wired) |
| `/docs/protocol/decisions` | Deep dive: each decision type with examples | ⚠️ planned — covered today by `/protocol.html` (Decisions) |
| `/docs/protocol/errors` | Error catalog | ⚠️ planned — covered today by `/protocol.html` (Error Codes) |
| `/docs/sdk/go` | Go SDK reference | ⚠️ planned — published today as `/sdk.html` (one page, all three languages) |
| `/docs/sdk/python` | Python SDK reference | ⚠️ planned — published today as `/sdk.html` |
| `/docs/sdk/typescript` | TypeScript SDK reference | ⚠️ planned — published today as `/sdk.html` |
| `/docs/testing` | Test battery guide | ⚠️ planned — published today as `/guide.html` (Run the compliance test battery) |
| `/docs/hermes-config` | How to configure Hermes for H3 | ⚠️ planned — not published |
| `/docs/migration` | Native → H3 migration guide | ⚠️ planned — published today as `/migration.html` |
| `/docs/examples` | Example harnesses: echo, RAG agent, code reviewer | ⚠️ planned — not published; `/integration.md` covers wiring an existing agent system and the per-language examples live in the SDK repos |
| `/docs/faq` | FAQ | ⚠️ planned — not published |
| `/compliance` | Compliance badge registry, verify badge endpoint | ⚠️ planned — not published; the registry is specified in S25 §6–§7, while the static badges under `/badge/*.svg` are live |

---

## 5. Compliance Badge System

**Status (2026-09-18):** the three static SVGs under `/badge/` are published and served
(`/badge/compliant.svg` → HTTP 200, reading `H3 | 46/46 ✓ | Compliant v1.0`). The verify
endpoint in §5 below and per-harness badge generation are **planned — not implemented**:
`/api/verify` and `/badges/v1/...` return HTTP 404.

### Badge Format

```
[![H3 Compliant](https://get-h3.github.io/h3/badge/compliant.svg)](https://get-h3.github.io/h3/#compliance)
```

The published badge URL is a static asset (the SVG is rendered in-repo, not per request);
it carries the current battery result rather than a per-harness pass count. Anyone can verify a
harness by running `h3-test` against its endpoint — encoding a per-harness count in a generated
badge URL is **planned — not implemented**.

### Verify Endpoint (planned — not implemented)

The request below is design intent: `/api/verify` is not routed in the published tree and
returns HTTP 404 today, so the JSON is the intended response shape, not a live one.

```
# PLANNED — /api/verify is not routed on get-h3.github.io/h3 yet (HTTP 404 today)
GET https://get-h3.github.io/h3/api/verify?repo=github.com/user/harness
→ {"compliant": true, "protocol_version": "1.0", "tests_passed": 46, "tests_total": 46, "last_verified": "2026-07-12T22:30:00Z"}
```

### Badge Generation

Served today as the static asset `docs/badge/compliant.svg` (HTTP 200); generating a badge
per harness on demand is **planned — not implemented**.

```
GET https://get-h3.github.io/h3/badge/compliant.svg
→ SVG badge: "H3 v1.0 — 46/46 ✅"
```

---

## 6. Tech Stack

- **Static site:** Next.js or Astro (SSG, fast, dark theme)
- **Hosting:** Vercel or Cloudflare Pages
- **API docs:** Redocly or Scalar (generated from `h3-protocol.yaml`)
- **Domain:** `get-h3.github.io/h3` (GitHub Pages; the legacy `h3.sh` domain is dead — NXDOMAIN)
- **Repo:** `get-h3/h3` (served from `get-h3/h3/docs/` via GitHub Pages)

---

## 7. Content Checklist

### Before Launch

- [ ] Hero with 3-line code example
- [ ] Architecture diagram (dark-themed SVG)
- [ ] Quickstart with language picker
- [ ] Each quickstart step verified (5 min end-to-end)
- [ ] Full protocol reference (auto-generated)
- [ ] SDK docs (auto-generated from repos)
- [ ] Test battery guide
- [ ] Hermes config guide
- [ ] Migration guide (native → H3)
- [ ] 3 example harnesses (echo, RAG, code review)
- [ ] Compliance badge system working
- [ ] FAQ
- [ ] Mobile-responsive (dark theme)

### Post-Launch

- [ ] Interactive playground (in-browser harness tester)
- [ ] Video: "Build an H3 harness in 10 minutes"
- [ ] Community showcase (list of H3-compliant harnesses)
- [ ] Changelog page
