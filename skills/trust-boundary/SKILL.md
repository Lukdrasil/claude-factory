---
name: trust-boundary
description: Trust-boundary rules for input from callers, tokens and upstream systems. Use when external input reaches a storage path, key, URL, query, authorization decision or response text.
---

# Untrusted input at trust boundaries

Everything that crosses a **trust boundary** (a request, a token claim, an upstream response, a file) is
hostile until proven otherwise. Proof is a check against the domain grammar or the caller's identity.

## Rules

1. **Validate every external id against its domain grammar** (characters, length, format) before it reaches
   a path, key, URL or query. Invalid input is rejected, never cleaned up and used.
2. **Responses carry your own codes and messages.** Caller text, upstream text, internal paths and exception
   messages stay inside the service.
3. **Authorize by the authenticated identity**, never by an id or role in the body or route. Every route
   parameter that names a resource, alternate keys included, passes the same membership check.
4. **A missing or malformed claim is unauthenticated**, never a default value.
5. **Not found and forbidden look the same** to a caller who may not know the resource exists.
6. **Every write route has a cross-tenant test**: a caller from another tenant or organization is refused.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List every external input** the change reads and where each one flows. Done when every input has its
   sink named.
3. **Check each input against every rule.** Done when every input passes or is fixed.

## Wrong and right

- A raw `clientId` went into a Vault path (path traversal). Right: validated against the client id grammar.
- The Vault path appeared in the ProblemDetails `detail`. Right: a fixed message for the code.
- The provider came from the request body and DELETE had no authorization. Right: from the caller's claims.
- An RBAC route keyed by `{shortName}` skipped the membership check that the id route had.
