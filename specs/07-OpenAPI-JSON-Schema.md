# S07 — OpenAPI & JSON Schema Design

**Status:** Spec  
**Version:** 1.0.0  
**Last Updated:** 2026-07-12

---

## 1. Purpose

The `get-h3/protocol` repo is the single source of truth. Every SDK and the Hermes shim generate types FROM this repo. The spec lives as an OpenAPI 3.1 document + standalone JSON Schema files.

---

## 2. File Layout

```
protocol/
├── h3-protocol.yaml          # OpenAPI 3.1 — all endpoints, schemas, examples
├── schemas/
│   ├── process-request.json   # ProcessRequest schema
│   ├── decision.json          # Decision schema (all 6 types via oneOf)
│   ├── result-request.json    # ResultRequest schema
│   ├── tool-call.json         # ToolCall sub-schema
│   ├── llm-call.json          # LLMCall sub-schema
│   ├── text-response.json     # TextResponse sub-schema
│   ├── wait.json              # Wait sub-schema
│   ├── delegate.json          # Delegate sub-schema
│   ├── end.json               # End sub-schema
│   ├── health-response.json   # HealthResponse schema
│   ├── error-response.json    # ErrorResponse schema
│   └── common.json            # Shared types (Message, Identity, Context, SessionState)
├── examples/
│   ├── process-request.json   # Full example payload
│   ├── decisions/
│   │   ├── tool-call.json
│   │   ├── llm-call.json
│   │   ├── text.json
│   │   ├── text-finished.json
│   │   ├── wait.json
│   │   ├── delegate.json
│   │   └── end.json
│   └── result-request.json
├── tests/
│   ├── validate-schemas.sh    # ajv validate against all examples
│   └── round-trip/
│       ├── go/                # Go deserializes examples, re-serializes, checks match
│       ├── python/            # Python deserializes examples
│       └── typescript/        # TS deserializes examples
└── README.md
```

---

## 3. Schema Design Rules

### 3.1 One schema per file
Each JSON Schema file is self-contained. The OpenAPI spec references them. This lets SDK code generators consume individual schemas.

### 3.2 Decision uses `oneOf`
```json
{
  "Decision": {
    "type": "object",
    "required": ["decision", "decision_id"],
    "properties": {
      "decision": {
        "type": "string",
        "enum": ["tool_call", "llm_call", "text", "wait", "delegate", "end"]
      },
      "decision_id": { "type": "string", "format": "uuid" }
    },
    "oneOf": [
      { "required": ["tool_call"] },
      { "required": ["llm_call"] },
      { "required": ["text"] },
      { "required": ["wait"] },
      { "required": ["delegate"] },
      { "required": ["end"] }
    ]
  }
}
```

### 3.3 Discriminated by `decision` field
The `decision` field IS the discriminator. Validators use it to know which sub-schema to validate:

- `"tool_call"` → `tool_call` field must be present and valid
- `"llm_call"` → `llm_call` field must be present and valid
- etc.

### 3.4 Versioning

Schema files include `$id` with version:

```json
{
  "$id": "https://github.com/get-h3/protocol/schemas/v1/decision.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema"
}
```

Directory structure per protocol version:
```
schemas/v1/   ← protocol version 1.0
schemas/v2/   ← protocol version 2.0 (when it exists)
```

---

## 4. Validation Pipeline

```bash
# 1. Validate JSON Schema files themselves are valid
ajv compile -s schemas/v1/decision.json

# 2. Validate all examples against their schemas
ajv validate -s schemas/v1/process-request.json -d examples/process-request.json
ajv validate -s schemas/v1/decision.json -d examples/decisions/tool-call.json
ajv validate -s schemas/v1/decision.json -d examples/decisions/llm-call.json
# ... all 8 decision examples

# 3. Validate the full OpenAPI spec
redocly lint h3-protocol.yaml

# 4. Cross-language round-trip
# Go: unmarshal example → marshal → diff against original
# Python: pydantic parse → model_dump → diff
# TypeScript: Zod parse → JSON.stringify → diff
```

---

## 5. Code Generation Targets

From the JSON schemas, each repo generates:

| Schema | Go | Python | TypeScript |
|---|---|---|---|
| `process-request.json` | `ProcessRequest` struct | `ProcessRequest(BaseModel)` | `ProcessRequest` type + Zod |
| `decision.json` | `Decision` struct | `Decision(BaseModel)` | `Decision` type + Zod |
| `result-request.json` | `ResultRequest` struct | `ResultRequest(BaseModel)` | `ResultRequest` type + Zod |
| `tool-call.json` | `ToolCall` struct | `ToolCall(BaseModel)` | `ToolCall` type |
| `llm-call.json` | `LLMCall` struct | `LLMCall(BaseModel)` | `LLMCall` type |
| (etc.) | | | |

### Generation Commands

```bash
# Go
go-jsonschema --input schemas/v1/ --output ../sdk-go/protocol/

# Python
datamodel-codegen --input schemas/v1/ --output ../shim/protocol.py

# TypeScript
json2ts --input schemas/v1/ --output ../sdk-typescript/src/protocol.ts
```

---

## 6. Schema Change Process

1. **PR to `get-h3/protocol`** — modify schema + add new example + update existing examples
2. **Validation gate** — all examples must validate, round-trip tests pass
3. **Version bump** — PATCH for bug fixes, MINOR for new optional fields, MAJOR for breaking changes
4. **Tag release** — `git tag v1.0.1`
5. **Regenerate** — SDK repos run codegen, update their types
6. **Test battery re-run** — all SDK examples must pass `h3-test`

---

## 7. OpenAPI Spec Structure

```yaml
openapi: 3.1.0
info:
  title: H3 Protocol
  version: 1.0.0
  description: >
    Hermes Harness Hooks — two-endpoint protocol for connecting
    external agent harnesses to Hermes Core.

servers:
  - url: http://localhost:9191
    description: Local harness

paths:
  /v1/health:
    get:
      summary: Health check
      responses:
        '200':
          content:
            application/json:
              schema:
                $ref: './schemas/v1/health-response.json'

  /v1/process:
    post:
      summary: New message → Decision
      requestBody:
        content:
          application/json:
            schema:
              $ref: './schemas/v1/process-request.json'
      responses:
        '200':
          content:
            application/json:
              schema:
                $ref: './schemas/v1/decision.json'

  /v1/result:
    post:
      summary: Execution result → Decision
      requestBody:
        content:
          application/json:
            schema:
              $ref: './schemas/v1/result-request.json'
      responses:
        '200':
          content:
            application/json:
              schema:
                $ref: './schemas/v1/decision.json'

  /v1/cancel:
    post:
      summary: Cancel in-flight operation

  /v1/sessions/{session_id}:
    get:
      summary: Session metadata
    delete:
      summary: Terminate session
```
