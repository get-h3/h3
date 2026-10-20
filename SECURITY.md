# Security Policy

## Reporting a Vulnerability

The H3 project takes security seriously. If you discover a security vulnerability, please do NOT open a public issue.

Email: wojonstech@gmail.com

Please include:
- Description of the vulnerability
- Steps to reproduce
- Affected version(s)
- Any potential mitigations

We aim to respond within 72 hours and release a fix within 7 days of confirmation.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | ✅ Active development |

## Security Model

H3 is a protocol bridge between Hermes Agent and external AI harnesses. The controls described across the spec set are **design targets, not shipped features**. This section states what is actually implemented in the code today, so that an integrator can deploy without trusting a control that does not exist.

> **Current state (as of 2026-10): the H3 protocol ships with zero authentication, zero TLS enforcement, and zero rate limiting. Any process that can reach a `/v1/process` or `/v1/result` endpoint is served. Deploy only behind a trusted network boundary.**

| Control | Status | Defined in |
| ------- | ------ | ---------- |
| Harness API key authentication | **NOT YET IMPLEMENTED** — design only (SEC-02 … SEC-04) | [specs/12](specs/12-Security-Authentication.md) |
| Transport encryption / mTLS | **NOT YET IMPLEMENTED** — design only, phased rollout (SEC-05) | [specs/14](specs/14-TLS-Enforcement.md) |
| Rate limiting | **NOT YET IMPLEMENTED** — design only (SEC-07) | [specs/15](specs/15-Rate-Limiting.md) |
| Decision schema validation | **PARTIAL — not a security boundary** | [specs/07](specs/07-OpenAPI-JSON-Schema.md), [protocol/](https://github.com/get-h3/protocol) |
| Secret handling | **NOT YET IMPLEMENTED as a protocol feature** | [specs/12](specs/12-Security-Authentication.md), [specs/13](specs/13-Token-Rotation-Revocation.md) |

**API keys — planned, not implemented.** No side validates a caller. The Python shim can send an `Authorization: Bearer <token>` header when a token happens to be configured, but no harness and no shim rejects a request that omits it, and no key is issued, rotated, or revoked by any shipped code. specs/12 defines the intended key hierarchy, format, and lifecycle; none of it is enforced at runtime.

**Transport encryption — planned, not implemented.** No certificate authority is created, no certificates are generated or exchanged, and no connection requires TLS. Harness endpoints are addressed over plain HTTP. specs/14 defines the mandatory mTLS design and its phased deployment, which has not shipped.

**Rate limiting — planned, not implemented.** There are no per-harness, per-session, or global limits. A harness or a caller can drive decisions as fast as the host allows. specs/15 defines the three-tier limiter design.

**Decision validation — partial, and not a security control.** The Python shim parses harness decisions into the generated model types, so a badly typed payload fails rather than executing. That is type-checking at the language boundary, not validation against the published OpenAPI 3.1 document (specs/07): nothing validates a decision against `h3-protocol.yaml` or the standalone JSON Schema files at runtime, and the Go and TypeScript SDKs perform their own ad-hoc checks. Do not rely on validation to reject a hostile decision — treat every harness as trusted code.

**Secret handling — planned, not implemented.** The protocol has no secret channel. Tokens placed in harness configuration files are plaintext on disk, and log redaction is not enforced by the shim or the SDKs. specs/12 §3 and specs/13 define the intended lifecycle.

### Deploying safely today

Until SEC-02 through SEC-07 land, the protocol layer provides no protection, so the network boundary must:

- Bind harness endpoints to `localhost` or a private interface, never a public one, and firewall the port.
- Reach remote harnesses through a VPN, an SSH tunnel, or a reverse proxy that terminates TLS and performs its own client authentication.
- Treat every harness endpoint as trusted infrastructure — a harness can return any decision, including tool calls, without being challenged.

This section is maintained with the code. When one of these controls ships, move it out of this table in the same change that lands the enforcement.

## Disclosure Policy

We follow responsible disclosure:
1. Reporter submits vulnerability privately
2. We acknowledge within 72 hours
3. We develop and test a fix
4. We release the fix and publish an advisory
