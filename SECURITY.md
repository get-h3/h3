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

H3 is a protocol bridge between Hermes Agent and external AI harnesses. Key security boundaries:

- **API keys**: Harness API keys are passed via `Authorization` header. Never log them.
- **Secret handling**: All secrets are managed through Hermes Core's secret infrastructure.
- **TLS**: Transport encryption between Hermes and harnesses via HTTPS.
- **Input validation**: All harness decisions are validated against the H3 OpenAPI 3.1 schema before execution.

## Disclosure Policy

We follow responsible disclosure:
1. Reporter submits vulnerability privately
2. We acknowledge within 72 hours
3. We develop and test a fix
4. We release the fix and publish an advisory
