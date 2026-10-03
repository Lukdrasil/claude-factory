---
name: outbound-http
description: Outbound HTTP client rules for client lifetime, resilience, retries and request shape. Use when code calls another service over HTTP or configures an HTTP client.
---

# Outbound HTTP and resilience

## Rules

1. **Clients come from the platform's pooled factory** with a bounded connection lifetime, so DNS changes
   reach the client.
2. **Retries only for idempotent requests.** A one-time token, an assertion or a creating POST is sent once,
   including when a global default adds a retry handler.
3. **Know the inherited handlers.** Check which handlers the client gets from global defaults before adding
   your own.
4. **A PUT sends every field the server owns**, unchanged ones included: read, modify, write. A partial
   update uses PATCH.
5. **Hosts come from configuration or service discovery.**
6. **Every call has a timeout for its purpose** and takes the caller's cancellation token.
7. **Responses map per `fail-closed`**: only an explicit 404 means not-found.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List every client registration and outbound call** the change touches. Done when none is missing.
3. **Check each against every rule.** Done when every row passes or is fixed.

## Wrong and right

- A one-time assertion was replayed by an inherited resilience handler and rejected by the server.
- A singleton client never saw a DNS change. Right: the factory with a pooled connection lifetime.
- A PUT nulled fields the server owned. Right: echo them back.
