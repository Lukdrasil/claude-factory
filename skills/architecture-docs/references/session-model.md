---
written_against: "web research 2026-08"
---

`written_against` names the specification and product state this rubric was checked against — the
IETF OAuth for Browser-Based Apps BCP (`draft-ietf-oauth-browser-based-apps`) and the named
implementations. A spec or vendor page that contradicts it means this file is stale and needs
re-research, not that the solution drifted.

# Session model — how the browser stays logged in

The question: how does the browser app maintain an authenticated session — a server-side session
cookie, a BFF, or tokens in the browser — and how do logout, revocation and CSRF work in that
model? Decide it before writing the first login handler.

`security.md` frames the trade at the level of token shape and trust boundary; this file is the
browser-facing half in detail. `auth-flows.md` owns which grant each client type uses and whether
the chosen IdP supports it. If the answer here is BFF, `gateway-bff.md` takes over: how many BFFs
there are, whether a routing gateway tier belongs in front of them, and how each BFF exchanges the
session for per-downstream tokens — the option below is the entry point to that file, not a
substitute for it. Where the session store runs and how many replicas exist is `machine-topology.md`
and `06-deployment.md`.

The IETF's browser-apps BCP now strongly recommends keeping tokens out of the browser: either a
classic server-side session cookie, or a BFF that holds tokens server-side and gives the browser
only an `HttpOnly` cookie. Tokens in the browser remain workable for pure SPAs but demand
refresh-token rotation with reuse detection, and accept weaker revocation. Every cookie model needs
`SameSite`, `HttpOnly` and `Secure` plus CSRF thinking; every multi-replica deployment needs a
shared session store — in-memory sessions with two replicas is the classic "random logouts" bug.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| More than one machine — replicas or autoscale | a shared session store (Redis, DB-backed); sticky sessions are a fragile crutch that breaks on deploys and scale-in |
| Keycloak or a cloud IdP with a SPA frontend | the BFF pattern: a server-side confidential client, tokens never reaching the browser (IETF BCP strong recommendation) |
| Server-rendered app (Rails, Django, ASP.NET, Blazor) | a plain server-side session cookie — the framework default is the right answer |
| Compliance includes audit or GDPR | a model with real revocation: server-side sessions or BFF, where logout actually kills access immediately |
| Third-party or native API consumers alongside the browser app | tokens for the API clients, but keep the browser app on cookie or BFF — the models can coexist |

## Server-side session cookie (Redis/DB-backed store)

- **Use when** server-rendered or same-origin apps: the boring default that most teams should pick.
- **Pros** instant, authoritative revocation — delete the server record and the session is dead
  everywhere; an `HttpOnly` and `Secure` cookie, so JS never sees the credential and XSS cannot
  exfiltrate it; every framework ships this, giving it the smallest concept count; and session data
  such as roles and flags stays server-side and always fresh.
- **Cons** it needs a shared store — Redis or the app database — once you run more than one replica;
  there is a per-request store lookup, negligible in practice and feared in blog posts; and cookie
  scope makes cross-domain APIs and native clients awkward, which is what tokens are for.
- **Typical mistakes** an in-memory session store with two replicas, where users are randomly logged
  out per request — the classic; `SameSite=None` without a reason, or a missing `HttpOnly` or
  `Secure`; no absolute session lifetime, only an idle timeout; session fixation, from not rotating
  the session ID at login.

## BFF — tokens server-side, cookie to the browser

- **Use when** a SPA against an OIDC IdP (Keycloak, Entra, Auth0); the IETF browser-apps BCP
  strongly recommends this for business and sensitive apps. Once chosen, `gateway-bff.md` decides
  the fleet shape and the token-exchange mechanism.
- **Pros** the BFF is a confidential OAuth client — code flow with a client secret or private key
  JWT, and tokens never enter the browser; the browser holds only an `HttpOnly` session cookie, so
  XSS token theft is off the table and stolen-token blast radius is near zero; revocation works,
  since you can kill the BFF session or revoke the refresh token at the IdP; and there are
  ready-made implementations — Duende BFF for .NET, oauth2-proxy, framework OIDC middlewares.
- **Cons** one more server component to build, deploy and reason about, since the BFF must proxy or
  gateway all API calls; the BFF still needs a shared session and token store across replicas; and
  it adds a latency hop, while SPA purists resent losing the "static hosting only" story.
- **Typical mistakes** a BFF that forwards the access token to the browser "for convenience",
  silently reinventing the token-in-browser model; skipping CSRF defence because "it's OAuth", when
  the browser-facing cookie is still a cookie; storing tokens in an unencrypted server-side session
  that outlives the refresh token.

## Tokens in the browser (SPA with access plus refresh token)

- **Use when** there is no backend you control — static hosting against third-party APIs — or
  native and mobile parity forces a pure token model.
- **Pros** no session state on your servers, and it works across domains and API gateways; the same
  auth model serves web, mobile and machine clients; and there is no CSRF for header-borne tokens,
  since `Authorization` headers are not sent ambiently.
- **Cons** every token in the browser is XSS-stealable, which is exactly why the IETF BCP ranks this
  below BFF; revocation is weak, because a stolen access token works until expiry — keep it at 15
  minutes or less — and logout is advisory; and you now own refresh-token rotation, reuse detection
  and secure storage, which is a lot of subtle code.
- **Typical mistakes** a JWT in `localStorage`, the single most-flagged web auth anti-pattern, where
  any XSS is full account takeover; refresh tokens without rotation and reuse detection, when reuse
  of a rotated token must revoke the whole family; access tokens with hours-long lifetimes because
  refresh was annoying to implement; no server-side denylist or session registry, giving a "logout"
  that does not log anyone out.

## Stateless signed-cookie session (JWT-in-cookie, no store)

- **Use when** small apps that want zero session infrastructure and can accept expiry-based logout.
- **Pros** no session store at all, so replicas scale freely with just a shared signing key; an
  `HttpOnly` and `Secure` cookie keeps the token away from JS; and it is simple to deploy — one
  secret in config.
- **Cons** no revocation path, so logout, password change and account disable do not invalidate
  issued cookies until expiry; claims such as roles go stale until re-issue; and it tempts teams
  into long expiries, which converts "no revocation" from theory into incident.
- **Typical mistakes** long-lived (days) stateless cookies with no denylist, where a fired employee
  still has a working session; `alg=none` or weak HMAC secrets on the signed cookie; stuffing PII
  into the merely base64-encoded payload.

## Sticky sessions with an in-memory store

- **Use when** a legacy constraint only — the load balancer pins each user to one replica so
  in-memory sessions "work". Treat it as debt, not a design.
- **Pros** no session-store infrastructure, and it is sometimes the only quick fix for a legacy app;
  zero code change from a single-instance setup.
- **Cons** every deploy, crash or scale-in logs out that replica's users; it defeats load balancing,
  since hot replicas stay hot; and it breaks silently on multi-AZ load balancers and HTTP/2
  connection reuse, masking the real problem.
- **Typical mistakes** choosing stickiness for a new system instead of spending the afternoon adding
  Redis; assuming cookie-based LB affinity survives failover — it does not, and the session is gone
  with the pod.

## What holds whatever you pick

- Default to keeping tokens out of the browser: a server-side session cookie for server-rendered
  apps, a BFF for SPAs, per the IETF OAuth browser-based-apps BCP.
- Never store tokens in `localStorage` or `sessionStorage`. If tokens must live in the browser, keep
  the access token in memory only with a lifetime of 15 minutes or less, and rotate the refresh
  token with reuse detection.
- More than one replica means a shared session store, Redis or database — sticky sessions are an
  incident generator, not an architecture.
- Cookie baseline: `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict` for admin), plus an explicit
  CSRF defence for any state-changing endpoint. `SameSite` alone is not a CSRF strategy.
- Design logout as revocation: deleting the client-side cookie or token without killing the
  server-side session or refresh token is theater.
- Rotate the session identifier on login and on privilege change, to block session fixation.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a server-side session cookie backed by a
shared store for a server-rendered app, and a BFF for a SPA against an external IdP — in both cases
`HttpOnly`, `Secure`, `SameSite=Lax`, an explicit CSRF defence on writes, an absolute lifetime
alongside the idle timeout, and a logout that deletes the server-side record. Name the trigger that
would change it — a native client demanding the same auth model, a frontend that must be hosted
statically with no backend, a second replica appearing — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: how long after an account
   is disabled that user may still act, and whether the deployment is single-instance today and
   will stay so.
2. State the recurring cost of each — the shared session store, the BFF as an extra deployable, the
   rotation-and-reuse-detection code you own in the token model — and what changing it later costs.
3. Write the accepted model as an ADR under `docs/adr/`, the rejected models as alternatives with
   the reason each lost, and reference it from `03-containers.md` beside the browser-to-backend edge
   and from `06-deployment.md` beside the session store.
4. Numbers become `QS-` rows: access-token lifetime, session idle and absolute lifetime, the
   revocation window. A stateless cookie with no denylist, tokens in browser storage and sticky
   sessions carried as debt are `R-` rows in `07-risks.md` with an owner and a mitigation. Anything
   the human leaves open is a `TODO(question)` per `templates.md`.
