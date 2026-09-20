---
written_against:
  react: "19.2"
  meta_frameworks: "Next.js 16 (App Router, RSC default, Turbopack stable), React Router v7 framework mode, TanStack Start, Astro 5"
  ecosystem: "TanStack Query + Zustand/signals as the default server/client state split; tRPC growing inside TS-only stacks, GraphQL share falling; Vite 8 (Rolldown/Oxc) default SPA bundler, Rspack for webpack migrations, Turbopack only inside Next.js"
  note: >
    audit diffs a repo against this stamp before judging drift — a mismatch here means the
    profile is stale and needs re-research, not that the product repo did something wrong.
---

# React / frontend stack profile

Loaded when the product repo is a React app. Same contract as `approaches.md`: every option below
is use-when / pros / cons / typical mistakes, grounded in `02-constraints.md` and
`04-quality-scenarios.md`, offered to the human as options with consequences plus a recommendation
— never picked silently.

## App shape

The first axis: how the app is rendered and shipped. Pick one primary shape per app; a solution can
mix shapes across apps (marketing site on one shape, product app on another) but mixing inside one
app is a specific, justified choice, not a default.

### SPA (Vite class)

Client-rendered, one JS bundle, hits an API over the network.

- **Use when** the app sits behind auth (no SEO requirement), the team owns a separate backend
  already, or the product is an internal tool / dashboard / admin panel.
- **Pros** simplest mental model — one runtime (the browser), any static host or CDN, no server
  render step to operate or debug, backend can be any language.
- **Cons** blank-page-until-JS load, weak SEO without extra work, all data fetching happens after
  hydration so time-to-interactive dominates time-to-first-byte.
- **Typical mistakes** building a marketing/SEO surface as an SPA and bolting on a prerender
  service later; no route-level code splitting, so the whole app ships on first load; treating
  client-side auth checks as a security boundary instead of UX.
- **Hosting**: static bucket + CDN. **Auth**: token in memory/storage, checked client-side, real
  enforcement on the API. **SEO**: weak unless prerendered. **TTFB vs interactivity**: fast TTFB
  (static shell), slow interactivity (wait for JS + data fetch).

### SSR/RSC framework (Next.js class)

Server renders (and increasingly, server-*executes*) the component tree; the framework owns
routing, data fetching and the client/server split.

- **Use when** SEO or fast first paint matters, the team wants data fetching co-located with
  components instead of a separate API layer, or the product needs both public and authenticated
  surfaces from one app.
- **Pros** real HTML on first response, streaming, per-route code splitting by default, server
  components cut client JS for read-heavy screens, one framework owns caching and revalidation.
- **Cons** needs a long-running node/edge runtime, not a static host; server/client boundary is a
  real architectural seam that leaks if ignored; framework version upgrades are load-bearing
  (RSC's Flight protocol has had critical CVEs — treat framework patches as a security dependency,
  not a style update); vendor-shaped conventions (file-system routing, cache directives) couple the
  app to the framework.
- **Typical mistakes** marking everything `"use client"` out of habit, which throws away the RSC
  bundle win; fetching in a client component when the parent server component already had the
  data; treating server actions as an internal RPC with no input validation, because "it's just
  our own frontend calling it."
- **Hosting**: node/edge runtime (Vercel-style or self-hosted node server), not a static bucket.
  **Auth**: session/cookie checked on the server for every render; server components can read
  secrets safely, client components cannot. **SEO**: strong, real HTML. **TTFB vs interactivity**:
  slower TTFB than static (server work per request, mitigated by caching), fast to useful content;
  interactivity still waits on hydration for client islands.

### SSR framework, non-RSC (React Router v7 framework mode class)

Server-rendered via loaders/actions per route; the server/client split is coarser than RSC —
components are client components, data loading is server-side.

- **Use when** the team wants SSR, nested routing, and server-side data loading without adopting
  RSC's finer-grained server/client component split, or is migrating off Remix / CRA.
- **Pros** simpler mental model than RSC (one component model, data loading is the only server
  concern), HTML forms and progressive enhancement are first-class, framework-agnostic enough to
  deploy on more runtimes than the RSC frameworks.
- **Cons** no per-component server/client split, so client bundle size is closer to an SPA's than
  to an RSC app's; ecosystem and tooling around it are smaller than Next.js's.
- **Typical mistakes** fetching in `useEffect` after the loader already ran, duplicating the
  request; putting secrets in a loader that also runs during client-side transitions without
  checking `request` context.
- **Hosting**: node runtime (adapter-based — node, Cloudflare Workers, Deno). **Auth**: session
  cookie read in loaders/actions. **SEO**: strong. **TTFB vs interactivity**: similar profile to
  RSC frameworks, coarser optimization ceiling.

### Static/SSG

Every page pre-rendered at build time into plain HTML.

- **Use when** content changes at deploy-time cadence, not per-request (marketing sites, docs,
  blogs, changelogs).
- **Pros** cheapest possible hosting (CDN only), fastest possible TTFB, no server to operate or
  patch, trivially cacheable.
- **Cons** rebuild-and-redeploy for any content change unless paired with ISR/on-demand
  revalidation; not viable for per-user or frequently-changing content.
- **Typical mistakes** SSG'ing a page that actually needs per-request personalization, then
  smuggling that personalization in client-side and losing the SEO benefit that justified SSG.
- **Hosting**: static bucket + CDN. **Auth**: none at render time; authenticated bits are
  client-side islands or a separate app. **SEO**: strongest option. **TTFB vs interactivity**:
  fastest TTFB of all shapes; interactivity only where JS is added.

### Islands (Astro class)

Static HTML by default; JS hydrates only the specific components marked interactive.

- **Use when** the page is mostly static content with a few interactive widgets (marketing site
  with a signup form, docs site with a search box, content site with a comment widget).
- **Pros** ships the least JS of any shape with interactivity, keeps the content-authoring story
  simple, framework-agnostic islands (can mix React, Vue, Svelte components on one page).
- **Cons** falls apart when interactive parts need to share state across the page or a route
  change should update more than one island — that is an SPA's job, not an island's.
- **Typical mistakes** reaching for islands on a page that is fundamentally one interactive
  surface (a dashboard, an editor) instead of a few widgets on static content; sharing state
  between islands via ad hoc globals because the architecture has no story for it.
- **Hosting**: static bucket + CDN, same as SSG. **Auth**: same constraint as SSG — islands can
  call an authenticated API client-side, the shell itself is not gated. **SEO**: strongest.
  **TTFB vs interactivity**: fastest TTFB; interactivity scoped per-island, not page-wide.

## Server components / server functions (RSC)

RSC is not "SSR but newer" — it changes *where code runs by default* and adds a network boundary
inside the component tree, not just at the API edge. A server component's code (and its imports)
never reaches the browser; a client component's code always does; the boundary between them is a
serialization boundary (props crossing it must be serializable — no functions, no class instances,
no closures over server-only state).

- **What it actually couples the frontend to**: a server runtime that can execute React during the
  request (not a static host), a bundler that understands the RSC convention (`"use client"` /
  `"use server"` boundaries), and — because server components can call databases and internal
  services directly — a blurring of the line between "frontend" and "backend for this app" that a
  separate API layer used to enforce.
- **When the complexity pays**: read-heavy screens where most of the tree never needs to be
  interactive (product pages, dashboards with mostly-display data) — those components ship zero
  JS. It does not pay on a screen that is mostly interactive already; the RSC boundary there adds
  ceremony without cutting meaningful bundle weight.
- **Server functions** (`"use server"`) are RPC endpoints defined inline in a component file. Treat
  every one as a public HTTP endpoint for validation and authz purposes — "it's just called from
  our own form" is not a security boundary, the same way a REST controller isn't trusted just
  because only the SPA calls it today.
- **Typical mistake**: treating the server/client split as a performance-only concern and skipping
  the input validation and authz that would be obviously required if the same function were a REST
  route.

## State management scale points

Escalate only when the current tool demonstrably can't do the job — the classic mistake is
reaching for the heaviest option (a global store, or Redux specifically) before local state or
context have been tried and found wanting.

| Scale point | Use when | Typical mistake at this point |
|---|---|---|
| Local component state (`useState`/`useReducer`) | State is read and written by one component and its direct children. | Lifting state to a parent/context "just in case" before two components actually need it. |
| Context | A few components deep in the tree need the same read-mostly value (theme, auth session, locale). | Using context for high-frequency updates (form fields, live cursors) — every consumer re-renders on every change; that's a store's job. |
| Dedicated client store (Zustand/signals class) | Client-only state (UI mode, multi-step form, selection) is read/written from unrelated parts of the tree, or updates are frequent enough that context's re-render blast radius matters. | Putting server data (anything fetched from an API) into this store — that's what the next tier is for; doing it here means hand-rolling caching, invalidation and loading states that a server-cache library gives for free. |
| Server-cache library (TanStack Query class) | Any state that originates from the server: lists, detail records, anything with a natural cache key and an invalidation event. | Treating it as a generic store for client-only state; skipping query keys that reflect the actual dependency (stale data from a key that's too coarse), or invalidating too broadly (refetch storms). |

Redux (or Redux Toolkit) is still the right call for large apps that need strict, inspectable
state-transition conventions and time-travel debugging across a big team — not the default
starting point.

## API coupling

| Option | Use when | Consequence for team boundaries / contracts |
|---|---|---|
| REST | Public API, partner integrations, polyglot consumers, long-term backward compatibility is a requirement. | Contract is documentation (OpenAPI) plus discipline; drift is caught by contract tests or not at all. |
| GraphQL | Multiple client types with different data shapes, or separate frontend/backend teams (roughly 15+ engineers) that need to develop in parallel against a stable schema. | The schema *is* the contract and the enforcement point; resolver-level ownership needs its own boundary or every team touches every resolver. |
| tRPC / typed-RPC class | Frontend and backend share one TypeScript codebase (monorepo), internal-only API, team wants compile-time contract checking with no codegen step. | Contract drift becomes a compile error, which is the strength and the limit — breaks down the moment a non-TypeScript or external consumer needs the same API. |
| Backend-for-frontend (BFF) | The product frontend's ideal data shape doesn't match a shared/public backend's, or the frontend team needs to iterate on aggregation without backend releases. | Adds a deployable unit and an owner for it; done well it isolates the frontend from backend churn, done badly it's a second copy of business logic to keep in sync. |

## Build/tooling and runtime

- **Bundler**: Vite (now Rolldown/Oxc under the hood) is the default for a new SPA or non-Next.js
  app — fast enough that raw speed stopped being the deciding factor; pick something else only for
  a specific reason. Rspack is the migration path for an existing webpack app that needs
  webpack-plugin compatibility. Turbopack is not a general-purpose choice — it ships inside Next.js
  only, so choosing it means choosing Next.js.
- **TypeScript**: default assumption for a new React codebase; treat a plain-JS proposal as the
  option needing justification, not the other way around.
- **Monorepo vs polyrepo with the backend**: a monorepo (shared types, tRPC-class coupling, one CI
  pipeline) buys compile-time contract safety at the cost of coupling releases; a polyrepo keeps
  frontend and backend independently releasable at the cost of needing an explicit contract
  (OpenAPI/GraphQL schema) and contract tests to catch drift. The API coupling choice above and this
  one move together — tRPC implies monorepo, REST/GraphQL work either way.

## Networking specifics this stack owns

- **CDN/edge placement**: static and SSG shapes push everything to the CDN edge; SSR/RSC shapes
  place the render step at a node runtime or an edge function (Next.js middleware/edge runtime) —
  edge functions have tighter limits (no arbitrary node APIs, shorter execution budget) than a
  node server, and pushing the whole render there is a real constraint, not a free upgrade.
- **Hydration cost**: every client component's JS, plus React's own hydration work, blocks main
  thread before the page is interactive; this is the cost RSC and islands specifically cut, and the
  cost an SPA pays in full on every load.
- **Websockets/SSE from the browser**: both need a long-lived connection target — a static/SSG/
  islands host doesn't have one, so real-time features need a separate service (or a serverless
  provider's managed realtime product) even when the rest of the app is static.
- **CORS against a separate API**: any shape that calls a backend on a different origin (SPA
  calling a standalone API, islands calling an authenticated API) needs CORS configured on that
  API, and cookies need `SameSite`/`credentials` handled explicitly — this disappears only when
  the frontend framework's own server makes the call (SSR loader, RSC data fetch, server function),
  because that request never crosses the browser's origin boundary.
