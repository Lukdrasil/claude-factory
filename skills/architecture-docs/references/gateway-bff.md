---
written_against: "web research 2026-08"
---

`written_against` names the product and specification state this rubric was checked against —
Duende.BFF's version and licence tiers, Keycloak's token-exchange support, Entra's OBO surface. A
vendor page that contradicts it means this file is stale and needs re-research, not that the
solution drifted.

# Gateway and BFF — routing tier, session tier, token exchange

`security.md` decides the session shape — whether a token ever reaches the browser, or a
server-side session behind a backend-for-frontend holds it. This file starts after that answer has
landed on "BFF": how many BFFs there are, whether a gateway tier belongs in front of them, and how
each BFF turns one user session into the audience-scoped tokens its downstream APIs demand.
`auth-flows.md` owns the grant per client type and whether the chosen IdP supports it;
`edge-proxy.md` owns what the routing tier is built from and where TLS terminates.

Outputs land in `03-containers.md` (the BFF and gateway as units, and the edges between them), in
`06-deployment.md` (the cookie topology, the key ring and the session store), and in an ADR per
`templates.md`.

Sam Newman's pattern gives each frontend — web, mobile, partner UI — its own backend, owned by
that frontend's team. The BFF terminates the browser session in an HttpOnly cookie, keeps tokens
server-side, and shapes or aggregates the downstream calls that frontend needs. A gateway tier in
front of the BFFs is justified only when there are several BFFs to route between: the gateway does
host and path routing (`app.example.com` → web-bff, `m.example.com` → mobile-bff), TLS
termination, rate limiting and WAF — and does not do user login. With one frontend, the proxy *is*
the gateway: a single YARP or Duende.BFF host and no extra tier.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Several frontends and teams, each needing tailored aggregation and independent deploys | a BFF-per-frontend fleet; add a routing gateway tier in front only once the fleet exists |
| A single SPA and one team | one BFF host *is* the gateway — no extra tier; Duende.BFF or hand-rolled YARP |
| Downstream APIs with distinct audiences and scopes | per-downstream token exchange in the BFF, never forwarding one broad token |
| The IdP already chosen | Entra → OBO via Microsoft.Identity.Web; Keycloak ≥ 26.2 → standard RFC 8693 exchange; an in-app or hand-rolled IdP has no exchange grant, so the pattern is not viable |
| Autoscaling BFF instances | a shared Data Protection key ring, a server-side session store (Redis `ITicketStore` or Duende server-side sessions) and a distributed token cache |
| Budget or licensing sensitivity | the hand-rolled YARP BFF (free) versus Duende.BFF paid licence trade-off |

## Single shared BFF (Duende.BFF / oauth2-proxy class)

- **Use when** one SPA, or a small set of frontends served by one team, and the BFF host is itself
  the edge — no separate gateway tier.
- **Pros** the simplest secure default: an HttpOnly cookie, tokens server-side, nothing in the
  browser. Duende.BFF supplies token management, refresh, anti-forgery, backchannel logout and
  server-side sessions out of the box, and v4 hosts several logical frontends in one deployable.
  There is no CORS at all while SPA and BFF share an origin.
- **Cons** one BFF serving many frontends re-creates exactly the general-purpose-API coupling the
  pattern was meant to kill — Newman's rule is a BFF per user experience; Duende.BFF is
  source-available but paid in production, and the Starter tier caps at three frontends; a single
  host becomes a deploy bottleneck across teams.
- **Typical mistakes** running Duende.BFF in production without a licence; putting the SPA and the
  BFF on different registrable domains and then fighting third-party-cookie blocking instead of
  hosting them same-site.

## BFF-per-frontend fleet behind a gateway

- **Use when** several frontends and teams exist. The gateway — YARP, nginx, a cloud LB or a
  Kubernetes ingress — does host and path routing, TLS and rate limiting; each BFF does its own
  OIDC login, owns its `__Host-` cookie, and exchanges the session for audience-scoped downstream
  tokens per proxied route.
- **Pros** team autonomy, since each BFF deploys with its frontend — Newman's original driver;
  least-privilege downstream calls, since each API sees a token scoped to its own audience only;
  blast-radius isolation, since one BFF's cookie or session compromise does not cross frontends;
  and an eShop/Aspire-style YARP plus service discovery keeps the routing tier thin and
  config-driven.
- **Cons** the most moving parts of any option here — a fleet, a gateway, IdP exchange grants and
  distributed caches; auth plumbing duplicated per BFF unless it is factored into a shared internal
  library; a hard dependency on an IdP that genuinely supports exchange; and a cookie and CORS
  topology that has to be designed rather than discovered — subdomain-per-BFF with per-host
  cookies, or path-per-BFF under one host.
- **Typical mistakes** a `Domain=.example.com` session cookie shared across all BFFs, which breaks
  the isolation and widens CSRF via sibling subdomains — use the `__Host-` prefix and no `Domain`
  attribute; the gateway also running OIDC login on top of each BFF's login, giving a double cookie,
  a double redirect dance and a logout that never fully logs out; exchanging for one broad-audience
  token and reusing it everywhere, when audience restriction is the whole point of RFC 8693; no
  token cache, so every proxied request makes an exchange or OBO round-trip to the IdP; an
  autoscaled fleet with in-memory sessions and default Data Protection keys, which logs users out
  on every scale event.

## Gateway only, tokens in the browser (no BFF)

- **Use when** the clients are purely machine-to-machine or trusted devices, or a legacy SPA does
  OIDC code-plus-PKCE in the browser and a BFF is genuinely off the table.
- **Pros** no BFF tier to build or scale — the gateway validates JWTs and routes; stateless, with
  no session store and no Data Protection coordination.
- **Cons** access and refresh tokens sit in browser storage and are exfiltrable by XSS, which is
  why the IETF BCPs and the Duende and Curity guidance have converged on BFF-with-cookies for
  browser apps; no per-downstream audience narrowing at the edge, so the SPA tends to hold one
  over-scoped token; and a CORS configuration surface for every API.
- **Typical mistakes** refresh tokens in `localStorage`; treating the gateway's JWT validation as
  equivalent to session management, which leaves no revocation story.

## Hand-rolled YARP BFF

- **Use when** a .NET shop wants full control or no licence cost: YARP plus the ASP.NET cookie and
  OIDC middleware, an `ITransformProvider` attaching the right token per route, and a custom RFC
  8693 or OBO exchange service over an `IDistributedCache` keyed on (`sub`, audience).
- **Pros** free and fully open — YARP is MIT, with no per-frontend licence maths;
  `ITransformProvider` and per-cluster transforms map cleanly onto per-downstream token exchange;
  and on Entra, Microsoft.Identity.Web's `IDownstreamApi` with a distributed token cache does most
  of the OBO plumbing already.
- **Cons** you own token refresh, expiry skew, anti-CSRF, backchannel logout and session revocation
  — the exact hard parts Duende.BFF productises. There is a known YARP wrinkle where
  `MapForwarder`/direct forwarding bypasses `ITransformProvider` registration (dotnet/yarp #2626),
  so transforms must be attached where the pipeline actually runs them. And it is easy to
  under-build: many hand-rolled BFFs skip logout and cache invalidation entirely.
- **Typical mistakes** forwarding the IdP's user access token to every downstream instead of
  exchanging per audience; storing exchanged tokens in the auth cookie itself, which blows the
  cookie past 4 KB and churns re-encryption — keep tokens server-side and the session id in the
  cookie.

## Per-downstream token exchange

The BFF never forwards the IdP's original user token. For each target API it exchanges the
session's token for one scoped to that API's audience, by one of two mechanisms:

- **RFC 8693 token exchange.** Keycloak supports it as a standard, non-preview feature from 26.2,
  internal-to-internal within one realm; identity chaining and the JWT authorization grant landed
  in 26.5.
- **Microsoft Entra On-Behalf-Of**, via MSAL and Microsoft.Identity.Web — `ITokenAcquisition` or
  `IDownstreamApi`.

Exchanged tokens must be cached per (user, audience); Microsoft strongly recommends a distributed
cache such as Redis, partitioned per user, for OBO. Without a cache, every proxied request hammers
the IdP's token endpoint. Verify the IdP's support before committing to the pattern — a hand-rolled
or in-app IdP has no exchange grant, and there is no way to retrofit one.

## The BFF host on .NET

The canonical host is YARP inside ASP.NET Core: cookie authentication and the OIDC middleware
handle login, and an `ITransformProvider` — or Duende's YARP extensions and `IAccessTokenRetriever`
— attaches an access token to each proxied request, per route or per cluster. Microsoft's eShop
reference uses YARP as the gateway/BFF tier in .NET Aspire with service discovery
(`Microsoft.Extensions.ServiceDiscovery.Yarp`).

Duende.BFF v4 (December 2025) adds multi-frontend hosting — several logical frontends inside one
physical BFF host — alongside server-side sessions, backchannel logout and OpenTelemetry. It is a
paid per-year licence: the Starter tier runs around $3.9k per year for up to three frontends, with
Enterprise beyond that. The hand-rolled YARP BFF is free and re-implements token management,
refresh, anti-CSRF and logout by hand. Record which side of that trade was taken and why; the
licence family question itself belongs to `licensing.md`.

## What autoscaling adds

A BFF fleet stops working at instance number two unless both of these exist:

- **A shared Data Protection key ring** — blob storage, Key Vault or Redis — so any instance can
  decrypt any cookie. The default per-instance key ring means users are logged out whenever the
  platform scales or redeploys.
- **A server-side session or ticket store** — `ITicketStore`, or Duende server-side sessions backed
  by Redis or EF — so tokens live server-side, cookies stay small, and sticky sessions are not
  required.

Both are `06-deployment.md` entries: where the key ring lives, where the session store lives, and
who operates them. The Redis instance itself is an operational dependency with the backup,
availability and access questions of `operations.md`.

## What holds whatever you pick

- The gateway routes and the BFF authenticates: exactly one tier performs OIDC login.
- One cookie per BFF, `__Host-` prefixed, never `Domain`-scoped across the fleet.
- One exchanged token per downstream audience, cached per (user, audience) in a distributed cache.
- Autoscaled BFFs need shared Data Protection keys and a server-side session store before instance
  number two.
- Token exchange requires IdP support — RFC 8693 (Keycloak ≥ 26.2) or Entra OBO. Verify it before
  committing to the pattern.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend one BFF host acting as its own gateway,
same-origin with its frontend, holding an `__Host-` cookie with the tokens server-side, and no
separate routing tier. Name the trigger that would add one — a second frontend with its own team,
a downstream API demanding its own audience, the first autoscale event — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: how many BFFs, whether a
   gateway tier exists, and which exchange mechanism the chosen IdP actually supports.
2. State the recurring cost of each — the Duende licence, the Redis instance, the IdP round-trips
   a missing cache would cause — and what reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. A cookie topology nobody has written down, a token cache with no eviction owner, and an
   unverified IdP exchange capability are rows in `07-risks.md`. Anything the human leaves open is
   a `TODO(question)` per `templates.md`.
