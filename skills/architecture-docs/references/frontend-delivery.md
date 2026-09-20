---
written_against: "web research 2026-08"
---

`written_against` names the product and specification state this rubric was checked against — the
SSR frameworks' current routing and rendering models, the static hosts' fallback mechanisms, and
the framework helpers named below. A vendor page that contradicts it means this file is stale and
needs re-research, not that the solution drifted.

# Frontend delivery — rendering model and asset hosting

Load this when the system has a browser UI and you are deciding its hosting, caching, proxy wiring
or rendering strategy. `edge-proxy.md` decides what the proxy is and where TLS ends;
`deployment.md` owns the build and release path that produces the bundle; `gateway-bff.md` owns the
session tier when the frontend talks to one. This file settles how the HTML and the assets actually
reach the browser, and what that choice costs to run.

Outputs land in `03-containers.md` (the frontend as a unit, or its absence when it is files on a
CDN), in `06-deployment.md` (the cache headers, the fallback route, the deploy-time purge), and in
an ADR per `templates.md`. Options reach the human with consequences plus your recommendation, per
`approaches.md`.

Frontend delivery is two decisions, not one: where HTML is produced — in the browser, in an SSR
runtime, or by the backend itself — and where static assets live: a CDN, a static host, or behind
your own proxy.

The caching contract is universal and does not vary by option. Content-hashed assets get
`Cache-Control: public, max-age=31536000, immutable`; the HTML entry point gets `no-cache` or
`no-store` so that deploys actually reach users. SSR buys SEO, fast first paint and personalised
first responses, at the price of running and scaling a server runtime. A static SPA on a CDN is
operationally the cheapest thing that exists. Server-rendered pages — Razor or Django with htmx —
skip the whole build-and-deploy split for backend-heavy teams. Same-origin serving, where the proxy
routes `/` to assets and `/api` to the backend, eliminates CORS entirely and is the default until
scale forces a CDN.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| SEO or social previews matter (public content, marketing, e-commerce) | SSR or SSG — crawlers and link unfurlers need meaningful HTML, not an empty div |
| The app is behind a login and content is per-user | a static SPA on a CDN or static host — SEO is irrelevant and ops cost is near zero |
| Backend-heavy team (.NET/Python/Java), no dedicated frontend build pipeline | server-rendered pages (Razor Pages, Django templates) plus htmx or Alpine for interactivity |
| Global audience, large asset payloads, or load spikes | a CDN in front of assets (CloudFront, Cloudflare, Fastly) with immutable caching; the origin serves only HTML and API |
| A single proxy already terminates TLS for the API | same-origin serving via that proxy — no CORS, no cookie `SameSite` headaches, one certificate |
| Marketing pages plus a logged-in app | hybrid: SSG/SSR for the public pages, SPA for the app shell — do not force one model on both |

## Static SPA on a CDN or static host (Vite build → CloudFront / Cloudflare Pages / Netlify / S3)

- **Use when** the app is behind auth, SEO is irrelevant, the API is a separate service, and you
  want near-zero frontend ops.
- **Pros** the cheapest ops possible — no server runtime for the UI, and it scales with the CDN;
  deploys are atomic file uploads with trivial rollback by re-pointing; immutable hashed assets
  cache for a year at the edge.
- **Cons** a blank page then hydration on first load, so SEO and link previews are poor without
  extra work; runtime configuration is awkward, since the API URL is baked at build time unless you
  serve a `config.json`; a separate origin from the API means CORS, preflights and cookie
  `SameSite` work.
- **Typical mistakes** caching `index.html` with the same long TTL as the assets, so users run
  week-old builds and hit hash-404s on chunks — `index.html` must be `no-cache`; no SPA fallback,
  so deep links and refreshes return 404 because the host lacks `try_files $uri /index.html`
  (nginx) or a rewrite rule (the S3/CloudFront error-page hack, Netlify `_redirects`); serving the
  SPA from a CDN domain while the API sets cookies on another, which silently breaks auth on
  Safari/ITP.

## SPA served same-origin behind your proxy (nginx/Caddy/YARP serves `dist/`, `/api` → backend)

- **Use when** you already run a proxy for the backend, load is small to medium, and you want zero
  CORS.
- **Pros** no CORS at all — one origin for HTML, assets, API and cookies; one TLS certificate, one
  deploy target, and it works on a single VM or Compose stack; full control of cache headers and
  the fallback route in one config file.
- **Cons** assets ride your origin bandwidth, with no edge caching unless you add a CDN later;
  frontend and backend deploys are coupled to the same box or image unless you split the artifacts.
- **Typical mistakes** a `location /` that proxies everything to the backend, so the backend 404s
  SPA routes — order matters: static plus fallback first, then the `/api` prefix to the backend;
  forgetting `try_files $uri $uri/ /index.html`, so a refresh on `/orders/42` gives nginx's 404;
  gzip or brotli left off for JS bundles, tripling transfer for no reason.

## SSR framework (Next.js / Nuxt / SvelteKit) on a Node runtime or Vercel-class PaaS

- **Use when** public content where SEO and first paint matter, or per-request personalisation in
  the HTML itself, and the team is comfortable operating Node.
- **Pros** real HTML on the first byte, giving SEO, link unfurls and fast LCP on slow devices;
  streaming and RSC reduce hydration cost, with data fetching co-located with routes; a static
  export escape hatch (`next export`) if you later decide SSR was not needed.
- **Cons** you now operate a server runtime for the UI, with memory leaks, cold starts, autoscaling
  and patching; a render cost per request, which makes scalability and infrastructure cost strictly
  worse than serving static files; framework lock-in and a fast-moving upgrade treadmill (App
  Router, RSC churn).
- **Typical mistakes** choosing SSR for an authenticated dashboard nobody Googles, paying the ops
  tax for zero SEO benefit; no CDN or cache layer in front of SSR output, so every crawler hit
  renders — use ISR, stale-while-revalidate, or `Cache-Control: s-maxage`; secrets in
  `NEXT_PUBLIC_` environment variables shipped to the client bundle.

## SSG / prerender (Astro, Next static export, Hugo) plus CDN

- **Use when** content changes at build time rather than per request: marketing, docs, blogs.
- **Pros** the fastest possible delivery — pure files at the edge, SSR-grade SEO with SPA-grade
  ops; no runtime to attack or patch, and near-free hosting.
- **Cons** content freshness is bound to the build cadence, and big sites get slow builds; anything
  per-user still needs a client-side fetch or an API.
- **Typical mistakes** rebuilding the whole site for one CMS edit instead of using ISR or partial
  rebuilds; treating an SSG site like an app and bolting on auth-gated content client-side only,
  which leaves the "protected" content sitting in the public HTML.

## Server-rendered pages (ASP.NET Razor Pages/MVC, Django/Rails templates) plus htmx or Alpine

- **Use when** a backend-heavy team is building CRUD, admin or line-of-business apps where
  interactivity is forms and partial updates rather than a client-side state machine.
- **Pros** one codebase, one deploy, one language, with no JS build pipeline and no
  API-for-the-frontend layer; auth, validation and rendering share the same session and context, so
  whole classes of CORS and token bugs do not exist; htmx gives partial-page updates without
  adopting a SPA framework.
- **Cons** rich client-side interactions — drag-and-drop editors, offline, heavy local state — get
  painful; the full-page mindset can feel dated to frontend hires, and it is hard to peel off a
  mobile API later if everything renders HTML.
- **Typical mistakes** serving static files without content-hash versioning, when .NET's
  `asp-append-version` and Django's `ManifestStaticFilesStorage` exist and should be used;
  rendering everything dynamically with no output caching, then blaming the framework for load
  problems.

## Hybrid: SSG/SSR marketing plus static SPA app, split at the proxy or edge

- **Use when** the public site and the logged-in product have genuinely different needs and the
  team can own two delivery paths.
- **Pros** each surface gets the right model — SEO where it counts, a cheap static app where it does
  not; independent deploy cadences for marketing and product.
- **Cons** two toolchains and two deploy pipelines, with a shared design system that needs
  discipline; the routing seams (`/`, `/app`, `/blog`) must be owned by one proxy or edge config,
  or drift causes outages.
- **Typical mistakes** sharing a session cookie across surfaces on different subdomains without
  planning the `Domain` and `SameSite` attributes up front; letting the marketing framework
  "absorb" the app until you are running the whole product as SSR by accident.

## What holds whatever you pick

- Hashed assets get `Cache-Control: public, max-age=31536000, immutable`; the HTML entry point gets
  `no-cache` (or `no-store`). Never the other way around — this pair is the entire cache-busting
  contract.
- Every SPA host needs an explicit fallback route to `index.html` — nginx `try_files`, Netlify
  `_redirects`, a CloudFront custom error response, ASP.NET `MapFallbackToFile`. Deep-link 404s in
  production mean it is missing.
- Default to same-origin: the proxy serves assets and routes `/api` to the backend. Introduce a
  separate asset or CDN origin only when load or geography demands it, and then budget for CORS on
  fonts and XHR plus `crossorigin` attributes.
- SSR is a product decision — SEO, first paint, personalisation — not a default. If the app is
  behind a login, static SPA plus CDN wins on ops almost every time.
- Keep old hashed assets available for at least one deploy generation; users with a cached
  `index.html` will still request the previous bundle chunks.
- A deploy-time cache purge should only ever need to touch the HTML entry point. If you find
  yourself purging hashed assets, your hashing is broken.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the static SPA served same-origin behind
the proxy that already terminates TLS: one origin, one certificate, the fallback route and the
cache-header pair configured explicitly, and no CDN or SSR runtime until load, geography or a real
SEO requirement asks for one. Name the trigger that would change it — a public marketing surface
that must rank, a global audience with a latency target, an asset bill the origin should not be
paying — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: where HTML is produced, where
   assets are served from, and whether the frontend shares an origin with the API.
2. State for each what it costs to run per month and in whose hours — an SSR runtime to patch and
   scale, a CDN bill, a second toolchain — and what moving off it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md` and `06-deployment.md`, which
   records the cache headers and the fallback route.
4. A missing SPA fallback, an `index.html` cached like an asset, a purge that has to touch hashed
   assets, and a cross-origin cookie topology nobody designed are rows in `07-risks.md`. Anything
   the human leaves open is a `TODO(question)` per `templates.md`.
