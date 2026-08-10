# S10 — H3 Website & Developer Docs

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Purpose

The H3 website (`https://get-h3.github.io/h3/`; legacy `h3.sh` domain is dead — NXDOMAIN) is the public face of H3. A developer lands here, understands what H3 is in 10 seconds, picks their language, and has a working harness in under 30 minutes.

---

## 2. Site Structure

```
get-h3.github.io/h3
├── Hero                 ← "BYO harness. Keep the platform." + 3-line code example
├── What Is H3           ← Architecture diagram, Hermes/harness split
├── How It Works         ← Animated sequence: Telegram → Hermes → H3 → Your Harness
├── Quickstart           ← Language picker (Go | Python | TypeScript) → copy-paste code
├── Protocol Reference   ← Full API docs (generated from OpenAPI)
├── Test Battery         ← "Run 44 tests against your harness in 5 seconds"
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
npm install @get-h3/h3-harness-sdk
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

| Page | Content |
|---|---|
| `/` | Landing + Quickstart |
| `/docs/protocol` | Full protocol reference (generated from OpenAPI) |
| `/docs/protocol/decisions` | Deep dive: each decision type with examples |
| `/docs/protocol/errors` | Error catalog |
| `/docs/sdk/go` | Go SDK reference |
| `/docs/sdk/python` | Python SDK reference |
| `/docs/sdk/typescript` | TypeScript SDK reference |
| `/docs/testing` | Test battery guide |
| `/docs/hermes-config` | How to configure Hermes for H3 |
| `/docs/migration` | Native → H3 migration guide |
| `/docs/examples` | Example harnesses: echo, RAG agent, code reviewer |
| `/docs/faq` | FAQ |
| `/compliance` | Compliance badge registry, verify badge endpoint |

---

## 5. Compliance Badge System

### Badge Format

```
[![H3 Compliant](https://get-h3.github.io/h3/badge/compliant.svg)](https://get-h3.github.io/h3/#compliance)
```

Badge URL encodes pass count. Anyone can verify by running `h3-test` against the harness endpoint.

### Verify Endpoint

```
GET https://get-h3.github.io/h3/api/verify?repo=github.com/user/harness
→ {"compliant": true, "protocol_version": "1.0", "tests_passed": 44, "tests_total": 44, "last_verified": "2026-07-12T22:30:00Z"}
```

### Badge Generation

```
GET https://get-h3.github.io/h3/badge/compliant.svg
→ SVG badge: "H3 v1.0 — 44/44 ✅"
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
