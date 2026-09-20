# Edge — reverse proxy, load balancer, gateway

Load this when anything is exposed to the public internet, a proxy, ingress or load-balancer
choice is open, the TLS termination point is undecided, or the team is about to put an app server
(Kestrel, uvicorn, gunicorn, node) on port 80 or 443 directly. `deployment.md` decides the hosting
that constrains the answer and records the TLS termination point, the protocol version and the
long-lived-connection settings; `containers.md` owns the proxy-container-and-internal-network
shape once containers are the platform. This file settles which component sits in front, what role
it plays, and what each candidate costs.

Outputs land in `06-deployment.md` (what is published, where the cipher ends, who renews the
certificate), in `02-constraints.md` when the platform imposes its own edge, and in an ADR per
`templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

The safe default is one reverse proxy at the edge terminating TLS, with everything behind it
speaking plain HTTP on a private network — localhost, an internal Docker network, or a VPC subnet.
Never expose an app server directly: Kestrel, uvicorn, gunicorn and node are not hardened for
slowloris, header smuggling or connection floods, and every one of those frameworks' own
documentation says to put a proxy in front. Terminating at the edge and going plain inside is fine
until compliance or a zero-trust mandate demands mTLS — at which point reach for a mesh or an
internal CA deliberately (`mtls-pki.md`), not ad hoc. A CDN and WAF layer (Cloudflare class) in
front of that proxy is a later addition, made when real bot or DDoS traffic arrives or a global
audience makes latency a stated requirement — not on day one.

## Three roles, usually fewer components

"Reverse proxy", "load balancer" and "API gateway" name three jobs, not three products. Most
products can be argued into all three roles, which is why the argument is worth settling on paper:
what is being bought is a capability, and a capability nobody needs is a component nobody owns.

| Capability | Reverse proxy | Load balancer | API gateway |
|---|---|---|---|
| TLS termination | owns it — the default place the cipher ends | owns it when it is the outermost hop, with certificates managed by the cloud | terminates only where it is also the outermost hop |
| Health-checked failover, L4 vs L7 | L7 only, with shallow checks | owns it — active checks, drain on failure, L4 for TCP protocols and high connection counts, L7 for HTTP | inherits whatever is beneath it |
| Per-tenant quotas, consumer identity | cannot — it sees addresses, not tenants | cannot | owns it — quotas keyed on the authenticated consumer |
| Authentication and authorisation | at most coarse and anonymous — basic auth, a forward-auth hop, an IP allowlist | none | owns token validation, scope and audience checks — but user *login* is the BFF's, not the gateway's |
| Request aggregation, protocol translation | none — one request in, one request out | none | owns it: fan-out to several backends, REST↔gRPC, response shaping |
| WAF | a bolt-on module where one exists | a managed add-on on cloud load balancers | frequently bundled, and frequently the reason it was bought |

Two rows carry the decisions people most often get wrong.

**Rate limiting is two different features with one name.** At the proxy it protects the app from
load and costs nothing per request, but it can only see addresses: one tenant fans out across many
IPs, and many tenants share one corporate NAT, so the heavy tenant slips through while the limiter
throttles their neighbours. Per-tenant and per-user quotas need tenant identity at the limiter —
that is the application gateway after authentication, or the application itself, at the cost of a
request that has already spent a process. Login, password reset and anything that sends mail or
money need the per-identity kind. `security.md` records which one was chosen and why.

**The edge answers north-south traffic only.** Timeouts, retries and circuit breaking placed at
the edge gateway cover requests arriving from outside and say nothing about service-to-service
calls; if those need a policy, its home is calling code or a mesh, decided in `operations.md`.

Roles collapse whenever there is only one thing to route to. With a single frontend, the proxy
*is* the gateway — one host doing TLS, routing and whatever coarse limiting exists, with no second
tier to deploy; `gateway-bff.md` starts the moment a second frontend makes routing between BFFs a
real question, and holds the line that the gateway routes while the BFF authenticates, so exactly
one tier performs OIDC login. On Kubernetes the roles routinely split across two hops that both
call themselves the edge: a cloud load balancer holds the public address and the managed
certificate, and the ingress controller or Gateway API implementation does the L7 routing behind
it — expected, and worth naming in `06-deployment.md` so nobody debugs the wrong hop. On PaaS all
three collapse into the platform. In the other direction, a load balancer is only a role worth
having when there is more than one backend to fail over to; whether there is belongs to
`machine-topology.md`, which also insists the load balancer be redundant itself, because one nginx
VM in front of two app hosts has moved the single point of failure rather than removed it.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| App server (Kestrel, uvicorn, node) currently exposed directly on :80/:443 | put any reverse proxy in front today — a fix-now item, not a design debate |
| Single VM or Docker Compose, small team, no dedicated ops | Caddy — automatic HTTPS, one small config file, nothing to babysit |
| Team has years of nginx muscle memory and existing configs | nginx — familiarity beats marginal simplicity gains; do not force a migration |
| Kubernetes deployment | an ingress controller or Gateway API implementation, never a hand-run proxy pod |
| PaaS (App Service, Cloud Run, Fly.io, Heroku class) | the platform edge; the proxy decision reduces to configuring forwarded headers |
| Public-facing with bot traffic, scraping or DDoS exposure | a CDN and WAF layer (Cloudflare / Front Door class) in front of your proxy |
| Very high connection counts, or L4 TCP balancing | HAProxy — still the raw-throughput and connection-handling benchmark |
| Compliance or zero-trust mandate for internal encryption in transit | mTLS via a service mesh or an internal CA — a deliberate project, not a checkbox |
| A .NET shop needing routing logic as code (BFF, gateway, custom transforms) | YARP behind a dumb TLS edge, so proxy decisions become testable C# |

## Caddy

- **License** Apache-2.0.
- **Use when** a single VM or Compose stack, a small team, and you want HTTPS to be a non-event.
- **Pros** automatic HTTPS via ACME by default, so there is no certificate operation to own; the
  Caddyfile is an order of magnitude shorter than the equivalent nginx config; modern defaults —
  HTTP/2, HTTP/3, OCSP stapling — arrive switched on.
- **Cons** a smaller ecosystem and hiring pool than nginx; fewer battle-tested recipes for exotic
  setups such as complex rewrites or embedded Lua-style logic; on-demand TLS left open is abusable.
- **Typical mistakes** running it behind another TLS-terminating proxy and then fighting its
  auto-HTTPS; not persisting the `/data` volume in Docker, so certificates re-issue on every
  restart and hit Let's Encrypt rate limits; using on-demand TLS with no `ask` endpoint
  restriction.

## nginx

- **License** BSD-2-Clause.
- **Use when** the team already knows it, or you need its enormous body of recipes and modules.
- **Pros** ubiquitous, so every problem has a documented answer; very high performance at low
  memory; doubles as a static file server, a cache and a rate limiter.
- **Cons** no built-in ACME — certbot and a reload hook are bolted on; config verbosity invites
  copy-paste errors, from a forgotten `proxy_set_header` to trailing-slash `proxy_pass` surprises;
  the open-source versus Plus split and F5's stewardship have spawned forks (freenginx, angie).
- **Typical mistakes** forgetting `X-Forwarded-For` and `X-Forwarded-Proto`, so the app generates
  `http://` redirect loops; certbot renewing while nobody reloads nginx, leaving an expired
  certificate served from memory; rate limiting by IP behind a CDN, which throttles the CDN's
  egress addresses instead of clients.

## Traefik

- **License** MIT.
- **Use when** Docker or Compose environments with frequently changing services, and label-driven
  configuration appeals.
- **Pros** auto-discovers containers via Docker labels, so there are no config reloads; built-in
  ACME like Caddy; a good dashboard and a clean middleware-chain model.
- **Cons** label-based configuration becomes hard to audit at scale; documentation split across the
  v2 and v3 majors trips people up; more moving parts than Caddy for the same simple job.
- **Typical mistakes** exposing the dashboard or API publicly with no auth; storing `acme.json`
  without persisting it, so rate limits are hit again; overlapping router rules whose priority
  resolution surprises everyone.

## HAProxy

- **License** GPL-2.0-or-later for the core, with LGPL parts.
- **Use when** serious L4/L7 load balancing is the job: high connection counts, TCP protocols,
  fine-grained health checks.
- **Pros** best-in-class connection handling and visibility into backend health; rock-solid under
  load, and the reference load balancer for two decades; powerful ACLs and stick tables for rate
  limiting.
- **Cons** no static file serving — it is a balancer, not a web server; native ACME support arrived
  only recently (3.2+), so most setups still script it; the config language is a skill of its own.
- **Typical mistakes** choosing it for a single-backend site where Caddy would do; GPL panic, when
  using it is fine because you are not linking against it; no stats socket configured, so backend
  state is invisible.

## YARP (.NET reverse proxy)

- **License** MIT.
- **Use when** a .NET shop needs routing logic as code — a BFF or API gateway with custom
  transforms, auth decisions or session-aware routing — or a Windows/IIS estate wants a modern
  proxy without leaving the stack.
- **Pros** configuration and middleware in C#, in the team's existing language and testable like
  any ASP.NET app; deep ASP.NET Core integration, so auth, rate limiting, health checks and
  OpenTelemetry ride the normal pipeline; a first-party Microsoft project that powers Azure App
  Service front ends; a natural fit as an internal gateway behind a dumb TLS edge.
- **Cons** it is a library, not a product — you build, deploy, patch and monitor a proxy
  application; no built-in ACME, so public TLS needs LettuceEncrypt, a Caddy in front, or platform
  certificates; the Kestrel underneath needs the same hardening care as any exposed app server.
- **Typical mistakes** exposing YARP's Kestrel directly to the internet as if it were a hardened
  edge, instead of putting it behind the real edge or hardening it deliberately; choosing YARP for
  plain TLS-termination-and-forward where Caddy is five lines of config; rebuilding nginx feature
  by feature in C# when no routing decision actually needs code.

## Cloud load balancer (ALB / Front Door / Cloud LB class)

- **License** proprietary managed service.
- **Use when** already on that cloud with autoscaling groups or managed containers, and managed
  TLS and health checks are wanted.
- **Pros** no servers to patch; certificates managed and auto-rotated by the cloud; native
  integration with autoscaling and health checks; WAF and DDoS protection attach as managed add-ons.
- **Cons** a per-hour plus per-request cost that never sleeps; deep lock-in, since listener rules,
  WAF rules and the certificate store are all provider-specific; a feature ceiling, so complex
  rewrites may still need a proxy behind it.
- **Typical mistakes** terminating TLS at the load balancer and then forgetting that the app trusts
  `X-Forwarded-*` from anywhere; recreating the load balancer via IaC and silently dropping
  manually added WAF rules; paying for an ALB in front of a single small VM that a $5 Caddy box
  would serve.

## Kubernetes ingress / Gateway API

- **License** varies by controller — ingress-nginx Apache-2.0, Traefik MIT, Envoy Gateway
  Apache-2.0.
- **Use when** you are on Kubernetes. This is not optional there; it is how edge is done.
- **Pros** declarative routing that lives with the app manifests; Gateway API is the standardised
  successor with role-separated configuration; pairs naturally with cert-manager for TLS.
- **Cons** controller choice is its own decision, under ingress-nginx retirement pressure and with
  Envoy-based gateways ascendant; debugging adds a layer, since the path is load balancer →
  ingress → service → pod; annotations remain controller-specific despite the "standard" resource.
- **Typical mistakes** running a hand-managed nginx pod instead of a controller; staying on
  unmaintained ingress-nginx annotations instead of planning the Gateway API move; one ingress
  controller per team, a proliferation nobody owns.

## PaaS-provided edge (none to run)

- **License** not applicable — a platform service.
- **Use when** hosting is App Service, Cloud Run, Fly.io, Railway or Heroku class, and the platform
  terminates TLS and routes.
- **Pros** no edge operations at all; TLS, HTTP/2 and often a CDN are included; certificates are
  issued and rotated by the platform; one less component to misconfigure.
- **Cons** the platform's limits become yours — timeouts, body size, WebSocket quirks; lock-in at
  the routing and edge layer; custom WAF or rate-limit logic may be paywalled or impossible.
- **Typical mistakes** deploying your own nginx container on PaaS out of habit, which breaks client
  IPs and health checks; not configuring forwarded-headers middleware, so the app thinks it is on
  `http`; assuming a platform edge implies a WAF, which it usually does not.

## Edge choice by deployment platform

| Platform | Safe default edge | TLS terminates at | When to deviate |
|---|---|---|---|
| Single VM | Caddy | Caddy on the VM | nginx if the team knows it cold; HAProxy for multi-backend L4 |
| Docker Compose | Caddy container, or Traefik if labels appeal | the proxy container; apps on the internal network with no published ports | nginx if configs already exist |
| Kubernetes | ingress controller / Gateway API plus cert-manager | the ingress, or a cloud LB in front with TLS passthrough | a cloud LB terminating TLS when the org mandates managed certificates |
| Cloud VMs with autoscaling | cloud LB (ALB / Front Door class) | the cloud LB | a self-managed HAProxy pair only with dedicated ops and a cost case |
| PaaS | the platform edge — run nothing | the platform | add a CDN/WAF in front under bot or DDoS pressure |
| IIS / Windows VM | IIS as reverse proxy (ARR), or YARP | IIS | put Caddy or nginx in front if leaving IIS is on the roadmap |

## What holds whatever you pick

- Never expose an app server — Kestrel, uvicorn, node — directly to the internet. One proxy in
  front, always.
- Terminate TLS once at the edge; plain HTTP inside a private network is fine until a compliance
  driver says otherwise.
- On PaaS the platform is your proxy: configure forwarded headers and stop there.
- On Kubernetes, edge means ingress or Gateway API, never a hand-run proxy pod.
- A CDN and WAF are a response to real traffic pressure, not a day-one requirement.
- If the proxy config is longer than the app's `Program.cs`, the wrong proxy was probably picked.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the one with the least to operate and the
cheapest exit: whatever edge the hosting platform already provides, TLS terminated there with
automatic renewal, plain HTTP on a private network behind it, and no gateway tier until a second
frontend or a per-tenant quota needs one. Name the trigger that would change it — a second
frontend, a signed availability target, a bot-traffic incident, an internal-encryption mandate — as
a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the edge component, the TLS
   termination point, and whether a gateway role exists at all separate from the proxy.
2. State for each what it costs per month and in whose hours, what it locks in, and what moving off
   it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `06-deployment.md`, which records what is published,
   where the cipher ends and who renews the certificate.
4. Unautomated certificate renewal, an edge nobody owns, and a rate limit claimed as a per-tenant
   quota are rows in `07-risks.md`, not sentences in the deployment document. Anything the human
   leaves open is a `TODO(question)` per `templates.md`.
