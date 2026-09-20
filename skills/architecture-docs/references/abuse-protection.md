---
written_against: "web research 2026-08"
---

`written_against` names the product and specification state this rubric was checked against — the
framework defaults quoted below (Kestrel's ~30 MB body cap, nginx's 1 MB, ASP.NET Identity's
five-failure lockout), the ASP.NET rate-limiting middleware surface, and the shape of the
commercial bot-management tiers. A vendor page that contradicts it means this file is stale and
needs re-research, not that the solution drifted.

# Abuse protection — rate limits, bots, size caps, lockout

Load this for any internet-facing endpoint, any self-run login or token endpoint, any backend with
a per-call cost (LLM, SMS, email), any multi-tenant API — or whenever nobody in the room can answer
"what happens at 500 rps from a script". The question is who can hammer this system, how hard, and
what stops them: rate limits per client, per tenant and per IP, bot handling, request size caps and
brute-force lockout, each decided explicitly rather than inherited from a default nobody chose.
`edge-proxy.md` decides what the edge is made of and already draws the line between address-based
and identity-based limiting; this file decides the actual budgets and where each is enforced.
`security.md` records the session and tenant-isolation shape those budgets are keyed on, and
`gateway-bff.md` owns which tier holds the authenticated identity a per-tenant quota needs.

Outputs land in `02-constraints.md` (the policy: which endpoint classes carry which budget), in
`04-quality-scenarios.md` (a measurable scenario — the heavy tenant is throttled while its
neighbours are not), in `06-deployment.md` (where enforcement physically sits), and in an ADR per
`templates.md`.

Traffic protection is a layered decision, not a WAF footnote. The safe default is two layers.
App-level per-identity limits — user, API key, tenant — returning `429` with `Retry-After`, because
only the application knows who the caller is. Plus edge-level per-IP limits at the proxy or CDN,
because the edge is the only place that can shed load before it costs compute. Login and token
endpoints get a separate, much tighter budget plus lockout: credential stuffing is the attack you
will actually see, running at a median of roughly 19% of daily authentication attempts at SSO
providers. Bot management of the Cloudflare class is a third layer, bought on evidence of scraping
or distributed attacks rather than on fear.

Request size limits are part of the same decision, not a separate one. Kestrel caps bodies at
around 30 MB and nginx at 1 MB by default — know which of those you are actually relying on.
Without any of this you are one script away from accidental self-DoS, and if you call paid APIs per
request, an unlimited endpoint is a wallet attack; `llm-features.md` owns the per-call spend that
makes that concrete.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| One tenant's retry loop or misconfigured cron degrades everyone | per-identity limits — fairness requires knowing *who*, which only the app layer does |
| Where the request dies matters | a `429` from the edge costs nothing, while an app-level `429` has already paid for TLS and a thread — edge limits shed load, app limits do fairness |
| Credential stuffing runs one attempt per account across thousands of IPs | per-account velocity plus lockout on login and token endpoints — per-IP limits are structurally blind to it |
| A request fans out to an LLM, SMS or metered API | the rate limit *is* the cost control; no limiter means your bill is attacker-controlled |
| Scraping farms and botnets rotating residential IPs | behavioural bot scoring you rent (Cloudflare / Front Door bot tiers), not build |
| In-process limiters behind N instances | the real limit is N× the configured one — hard global limits belong at the edge or in shared state |
| Slow-loris and oversized payloads | body and header size caps and timeout budgets — abuse that rate counters never see |

## None

- **Use when** internal tools behind a VPN with zero anonymous surface, and nothing else.
- **Pros** free until the incident.
- **Cons** one script, one leaked API key or one traffic spike from a popular link and you are
  either down or paying; a self-run login endpoint with no lockout is the credential-stuffing test
  bench.
- **Typical mistakes** assuming the framework has sane limits — Kestrel's and nginx's defaults were
  not chosen for your workload.

## Edge IP limits

- **Use when** you want the cheap floor: per-IP rules at the proxy or CDN — nginx `limit_req`,
  Caddy `rate_limit`, the Traefik `RateLimit` middleware, HAProxy stick tables, or CDN/WAF rate
  rules.
- **Pros** config-only, and it sheds load before it touches the app; near-zero runtime cost.
- **Cons** IP is a weak identity — corporate NAT makes one IP thousands of users (false positives)
  and attackers rotate IPs (false negatives); a good floor and a bad ceiling.
- **Typical mistakes** leaving nginx to return `503` on limit, which is its default rather than
  `429` — override it; rate limiting by IP behind a CDN, which throttles the CDN's egress addresses
  instead of clients.

## Identity-aware application limits

- **Use when** you want the workhorse layer: built-in middleware — the ASP.NET `RateLimiter` with
  token bucket, sliding window and concurrency policies — partitioned by user, API key or tenant,
  returning `429` with `Retry-After`, plus a separate tight policy and lockout on login and token
  endpoints.
- **Pros** the only layer that can do fairness, per-tenant quotas and per-plan tiers; token bucket
  absorbs legitimate bursts while sliding window guards security-sensitive paths; days of work, and
  the highest-leverage days in this rubric.
- **Cons** in-process state multiplies by instance count, which is fine for cost control but not
  for hard guarantees.
- **Typical mistakes** one global bucket for all tenants, so the noisy tenant spends everyone's
  allowance and the limiter punishes the victims; rate-limiting the API but not the background
  queue, which is where the batch damage happens; no per-account lockout on auth endpoints — ASP.NET
  Identity defaults to five failures and a five-minute lockout, so turn it on.

## Edge plus app plus bot management (Cloudflare class)

- **License** proprietary; Enterprise bot tiers are quote-priced.
- **Use when** there is evidence of scraping, distributed credential stuffing or inventory bots in
  your logs — rented bot scoring handles what IP limits structurally cannot see.
- **Pros** per-request bot scores and custom rules; absorbs distributed attacks; low engineering
  effort.
- **Cons** often the biggest line on the contract, plus ongoing tuning; below real bot pressure it
  is paying for an army nobody is fielding against you.
- **Typical mistakes** buying Enterprise bot management before app-level identity limits exist;
  assuming the platform edge implies a WAF, which it usually does not.

## Limit strategy by endpoint class

| Endpoint class | Limit strategy | Enforcement point |
|---|---|---|
| Anonymous read (public pages, search) | per-IP token or leaky bucket with a generous burst; cache hard; bot rules if scraped | edge — the cheapest place to say no |
| Authenticated API | per-identity sliding window or token bucket; `429` plus `Retry-After`; per-plan tiers | app middleware, with edge per-IP as a backstop |
| Login / token / password-reset | strict per-IP *and* per-account velocity; lockout after N failures; CAPTCHA or MFA escalation; alert on failure spikes | app or IdP (only it knows the account), plus an edge IP rule on the path |
| Webhooks (inbound) | signature check first, then a per-sender cap and a strict body limit; queue, do not process inline | app (signature) plus edge (size, IP) |

## What holds whatever you pick

- Return `429` with `Retry-After`, never a bare `503` or a reset — it is the contract client SDKs
  back off on, and without it polite retry logic becomes a thundering herd.
- Login and token endpoints get their own budget, always tighter, plus per-account lockout; per-IP
  limits are blind to credential stuffing.
- Enforce at two layers minimum: edge per-IP to shed load and app per-identity for fairness. Each
  covers the other's blind spot.
- If a request triggers per-call spend, the rate limiter is a financial control, not a performance
  one.
- Know your body-size defaults and set them on purpose — Kestrel around 30 MB, nginx 1 MB. The
  mismatch either breaks uploads or lets oversized payloads through.
- In-process limiters multiply by instance count, so treat app numbers as per-node soft limits;
  hard global limits live at the edge or in shared state.
- Buy bot management on evidence, not fear.
- Token bucket for general traffic, because it absorbs bursts; sliding window for security-sensitive
  paths.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the two-layer default: a per-IP rule at
whatever edge already exists, per-identity limits in the application returning `429` with
`Retry-After`, a deliberately set body-size cap, and a tighter budget with per-account lockout on
the auth endpoints — and no bot-management contract. Name the trigger that would add one — scraping
or distributed credential stuffing visible in the logs, a metered downstream whose bill an attacker
could drive, a tenant whose quota has to be contractual — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which endpoint classes
   exist, what budget each carries, and at which layer each is enforced.
2. State for each what it costs — the bot-management contract, the shared state a hard global limit
   needs, the engineering days for identity-aware limits — and what an unlimited endpoint would cost
   if a metered downstream sits behind it.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, reference it from `06-deployment.md`, and record the policy as a
   constraint in `02-constraints.md` with a measurable scenario in `04-quality-scenarios.md`.
4. An auth endpoint with no lockout, a limiter claimed as a per-tenant quota that only sees IPs, an
   unset body-size cap and an unlimited path in front of metered spend are rows in `07-risks.md`.
   Anything the human leaves open is a `TODO(question)` per `templates.md`.
