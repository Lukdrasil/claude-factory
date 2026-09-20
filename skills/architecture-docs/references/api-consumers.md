---
written_against: "web research 2026-08"
---

`written_against` names the specification state this rubric was checked against — RFC 9745, RFC
8594 and RFC 8288's header semantics, and the IETF httpapi rate-limit-headers draft, which is still
a draft. A current spec page that contradicts it means this file is stale and needs re-research,
not that the solution drifted.

# API consumers — who calls you, and what that obliges

`api-governance.md` decides how a contract evolves and what mechanically stops a break. This file
answers the question that sets the stakes for all of it: who consumes the API — only your own
frontends and services, or external partners and the public? `communication.md` owns the protocol
and the contract artifact; `webhooks-out.md` owns the delivery machinery once events go outbound to
customer-controlled endpoints.

Load it when the profile records external API consumers, or when the design mentions partners,
third-party integrations, a public API, a developer portal, API keys, or webhooks for external
parties. Outputs land in `02-constraints.md` where a partner agreement imposes a window you cannot
choose, in `04-quality-scenarios.md` where an SLA gets a number, and in an ADR per `templates.md`.

The moment a third party you do not employ calls your API, the API stops being an implementation
detail and becomes a product with a contract. Versioning and deprecation become contractual:
enterprise API agreements commonly guarantee a 6–12 month deprecation notice, and the mechanical
side is the `Deprecation` header (RFC 9745), the `Sunset` header with a hard decommission date (RFC
8594), a `Link` header to migration docs (RFC 8288), and `410 Gone` after sunset — never a flag-day
removal.

Rate limiting becomes a documented contract rather than ops firefighting: per-key, per-consumer
quotas so one heavy partner cannot starve another, `429` with `Retry-After` on rejection, and
`RateLimit` and `RateLimit-Policy` response headers (draft-ietf-httpapi-ratelimit-headers) so
clients can self-throttle. Every consumer needs its own credential — an API key, or OAuth2
client-credentials per partner — with rotation support, meaning two active keys accepted during
rollover, and revocation; one shared key means you cannot identify, throttle, bill or cut off
anyone individually. A developer portal with docs, a changelog and key self-service, a status page,
and an SLA all become product surface: partners build businesses on your uptime and will ask for
the number in writing.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| The blast radius of a breaking change is partner codebases you cannot see or fix, not your own repo | contractual deprecation windows with `Deprecation` and `Sunset` headers instead of informal versioning |
| Consumers must be individually identified — for billing, quotas, revocation, abuse attribution | per-consumer credentials with two-key rotation; never one shared key |
| The support model is a contractual SLA, not an internal Slack ping | a status page, a published SLA, and proactive breaking-change communication |
| The API is a product line and anyone can sign up | a self-service developer portal, tiered published limits and versioned docs — a permanent staffing commitment |

## Internal consumers only

- **Use when** only your own frontends and services call the API.
- **Pros** versioning stays additive and informal, and a breaking change is a repo-wide refactor
  rather than a negotiation; no per-consumer identity is needed beyond service auth.
- **Cons** it keeps working only as long as it stays true — the first partner integration changes
  the contract silently.
- **Typical mistakes** letting a partner integrate against the internal API "temporarily" and
  inheriting a contract you never wrote.

## Partner API with a contract

- **Use when** a known, finite set of external partners integrate.
- **Pros** per-partner credentials — an API key or OAuth2 client credentials — with rotation and
  revocation; a documented deprecation window, commonly 6–12 months, enforced via `Deprecation` and
  `Sunset` headers; documented per-key quotas with `429` and `Retry-After`.
- **Cons** docs, a changelog and a named contact become maintained surface, and breaking changes
  now take months of runway.
- **Typical mistakes** one shared API key for all partners, leaving no individual throttling,
  billing or cutoff; internal-style flag-day breaking changes in partner codebases you cannot fix.

## Public developer platform

- **Use when** anyone can sign up and the API is a product line.
- **Pros** a self-service portal for key issuance, dashboards and usage, tiered published rate
  limits and `RateLimit` response headers; a public status page and a published SLA build
  integration trust.
- **Cons** a permanent staffing commitment, not a feature; every endpoint shipped is an endpoint
  someone depends on forever.
- **Typical mistakes** launching the platform before the deprecation policy and migration-guide
  muscle are already in place.

## Outbound webhooks to consumers

- **Use when** third parties receive events from you, in addition to or instead of polling.
- **Pros** event push removes partner polling load and latency.
- **Cons** you now depend on their uptime: retries with exponential backoff, signed payloads
  (HMAC), idempotent delivery and a redelivery or replay tool all become table stakes —
  `webhooks-out.md` owns that build.
- **Typical mistakes** treating event schema changes as internal; they are breaking changes to
  partner code too.

## What holds whatever you pick

- `Deprecation` (RFC 9745), `Sunset` (RFC 8594) and a `Link` to migration docs (RFC 8288), then
  `410 Gone` — never a flag-day removal.
- Per-consumer credentials with two-key rotation. One shared key means no individual throttle, bill
  or cutoff.
- Rate limits are a documented contract: per-key quotas, `429` with `Retry-After`, and
  `RateLimit` / `RateLimit-Policy` response headers per the IETF httpapi draft.
- Partners build businesses on your uptime — write the SLA down before their escalation email
  writes it for you.
- Breaking changes get product-style communication: email, changelog and headers, months ahead.

## Recording the choice

1. Put the consumer classes to the human against the affected `QS-` and `C-` ids: who calls the
   API today, who plausibly calls it next, and which obligations follow from that.
2. State what each class costs on an ongoing basis — the deprecation runway, the portal staffing,
   the SLA number someone signs — and what reversing it later costs the consumers.
3. Write the accepted consumer model as an ADR under `docs/adr/`, with the deprecation window, the
   credential and rotation scheme, and the published rate limits named as numbers.
4. A partner-imposed deprecation window or SLA is a `C-` row in `02-constraints.md`, not a
   decision; the uptime target itself becomes a `04-quality-scenarios.md` row with a number.
5. One shared partner key, a deprecation policy that exists only in prose, and an unpublished rate
   limit partners are already hitting are rows in `07-risks.md` with an owner. Anything the human
   leaves open is a `TODO(question)` per `templates.md`.
