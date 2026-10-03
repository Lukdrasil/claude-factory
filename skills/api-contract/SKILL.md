---
name: api-contract
description: HTTP API contract rules for request validation, status mapping, error responses and wire DTO stability. Use when adding or changing an endpoint, a request or response DTO, or an error-to-status mapping.
---

# API request validation and contract stability

The wire contract is what callers depend on. The request is checked before any handler code runs, every
failure has one status and one code, and the contract changes only on purpose.

## Rules

1. **Bind, validate, authorize, handle**, in that order. A malformed route value, a non-JSON body or `{}`
   missing a required member is 400 before the handler runs.
2. **Required members are required on the wire**: an absent member fails deserialization. Unknown enum values
   are rejected, and enums travel as names.
3. **One table maps domain errors to statuses.** An unmapped domain error fails a test instead of becoming 500.
4. **Every error response is a ProblemDetails with a stable code** and a fixed message.
5. **Null collections become empty at the boundary**, inbound and outbound.
6. **Response DTOs carry no secrets.** A record prints every member in its generated `ToString`.
7. **Before refactoring an endpoint or DTO**, pin it with characterization tests and diff the OpenAPI
   document. Before deleting public API, search every consumer.
8. **Every route has the standard tests**: the happy path, malformed input (400), no identity (401), another
   tenant (403 or 404 per `trust-boundary`), and each mapped domain error.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List every endpoint and DTO** the change adds or edits. Done when none is missing.
3. **Check each against every rule.** Done when every row passes or is fixed.

## Wrong and right

- A `{}` body threw a null reference (500); a malformed route value gave 500; an unmapped domain exception gave
  500. Right: 400, 400, and a mapping row with a test.
- A non-JSON body threw before validation. Right: 400.
- `MapInboundClaims = false` renamed the claims and broke 26 routes. Right: search every claim read first.
- Enums were sent as integers. Right: names.
