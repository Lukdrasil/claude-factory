---
written_against: "web research 2026-08"
---

`written_against` names the product and specification state this rubric was checked against —
Sentry's and GlitchTip's deployment footprints, Grafana Faro v2 and Web Vitals v5, the W3C trace
context headers, and the ePrivacy and GDPR articles cited. A vendor page that contradicts it means
this file is stale and needs re-research, not that the solution drifted.

# Frontend observability — errors, web vitals, sessions, and browser-to-backend traces

Load this when the frontend is a real app — SPA, SSR or hybrid — serving external or
business-critical users, or when error tracking, RUM, session replay or browser-to-backend trace
correlation is being decided. `operations.md` owns the backend the beacons land in;
`observability-conventions.md` owns the field and metric names they should use; `correlation.md`
owns the trace context this file propagates across the browser boundary; `stacks/react.md` owns the
frontend project shape the SDK plugs into.

Outputs land in `03-containers.md` (the browser app as a telemetry producer, and the collector or
tunnel it reaches), in `06-deployment.md` (the CI source-map upload and release tagging) and in an
ADR per `templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

Server uptime is not user experience. A SPA can be fully broken — a JS error on boot, a failed chunk
load, a CORS regression — while every backend dashboard is green; a public SPA with no browser
telemetry has invisible outages. The stack has four layers.

**Error tracking.** Sentry SaaS is the default. Sentry self-hosted is heavy — around 40 containers
(Kafka, ClickHouse, Snuba, Relay, Symbolicator, Postgres, Redis) with 16 GB RAM recommended — while
GlitchTip speaks the same Sentry DSN and SDK protocol and runs in roughly 512 MB to 2 GB, making it
the sane light self-host. Errors are useless without source maps: upload them in CI (modern Sentry
SDKs inject Debug IDs via `@sentry/vite-plugin` or `webpack-plugin`) and tag releases so regressions
map to deploys.

**RUM and web vitals.** Measure field LCP, INP and CLS; lab Lighthouse scores are not field data,
and FID is retired. Options are vendor RUM (Datadog, New Relic, priced per session) or Grafana Faro
and the OTel browser SDK feeding Loki, Tempo and Prometheus. Faro v2 auto-collects Web Vitals v5
with attribution.

**Trace correlation browser to backend.** W3C `traceparent` is injected on fetch and XHR. The
backend CORS config *must* list `traceparent` in `Access-Control-Allow-Headers` or the browser
silently drops it, and `propagateTraceHeaderCorsUrls` should be restricted to your own APIs. Sample
hard: 100% browser tracing is cost suicide, so head-sample 1-10% at the browser, since the browser's
sampling decision propagates downstream.

**Session replay.** Replay is personal data under GDPR — ePrivacy 5(3) plus Art. 6(1)(a) consent.
Keep the mask-all-text and block-all-media defaults, test every unmask so password and PII fields
never leak, and gate replay behind consent.

Operations sit across all four: alert on the error-rate spike per release and use it as a deploy
gate; cap ingestion, because one bug in a render loop can burn a month's event quota in minutes, so
configure spike protection and rate limits per project. Expect roughly 15-30% beacon loss to ad
blockers on third-party endpoints; a first-party proxy or tunnel — Sentry's tunnel option, a reverse
proxy for the collector — recovers most of it.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Public exposure with a SPA | error tracking at minimum — public SPAs fail invisibly server-side, while internal tools can tolerate blindness longer |
| Ops capacity none or limited, but self-hosting wanted | GlitchTip (same Sentry SDKs, ~2 GB) — self-hosted Sentry is a distributed system of its own |
| Compliance includes GDPR | replay and IP-bearing beacons are consent-gated personal data — masking defaults plus consent-banner integration |
| Correlation on the backend is OTel or both | browser `traceparent` pays off end to end — add `traceparent` to the CORS allowlist and sample 1-10% |
| Per-event or per-session pricing | spike protection and per-project rate limits, so one release bug loop does not eat the bill |
| CI/CD exists | source-map upload and release tagging as CI jobs, never manual steps |

## None (server-side only)

- **Use when** static sites, server-rendered pages with trivial JS, or internal tools with forgiving
  users.
- **Pros** zero cost, zero privacy surface.
- **Cons** client-side failures are invisible — you learn about outages from support tickets.
- **Typical mistakes** keeping this posture after the frontend becomes a real SPA serving external
  users.

## Error tracking SaaS (Sentry class)

- **Use when** the default for most teams: a Sentry, Bugsnag or Rollbar-style SaaS with source maps
  uploaded in CI, release tagging, and an alert on the new-issue spike per release.
- **Pros** minutes to integrate, and release-tagged errors map regressions to deploys; alerting on
  new-issue spikes doubles as a deploy gate.
- **Cons** per-event pricing punishes error loops, so configure spike protection and per-project rate
  limits; and a third-party endpoint loses roughly 15-30% of beacons to ad blockers unless you add a
  first-party tunnel.
- **Typical mistakes** skipping source-map upload, so production stack traces are minified noise; no
  ingestion cap, so a render-loop bug burns the month's quota in minutes.

## Error tracking self-hosted (Sentry self-host / GlitchTip)

- **Use when** data residency or cost drives it. GlitchTip speaks the same Sentry SDK and DSN and
  runs on around 2 GB of RAM; full self-hosted Sentry only with dedicated ops.
- **Pros** data stays on your infrastructure, so no DPA is needed for error beacons; and GlitchTip is
  right-sized for limited ops — errors plus alerts in roughly 512 MB to 2 GB.
- **Cons** full Sentry self-host is around 40 containers (Kafka, ClickHouse, Snuba, Relay, Postgres,
  Redis) with 16 GB RAM recommended, a distributed system of its own; and you own upgrades, retention
  and storage growth.
- **Typical mistakes** deploying full Sentry self-host with no ops capacity when GlitchTip covers the
  need.

## Full RUM plus tracing (vendor or Faro/OTel)

- **Use when** you want errors plus field web vitals (LCP, INP, CLS) plus browser-to-backend traces,
  optionally with replay. Either a vendor (Datadog or New Relic RUM) or Grafana Faro with the OTel
  browser SDK feeding your own stack.
- **Pros** field web vitals instead of lab guesses, and traces that connect a slow click to the
  backend span that caused it; Faro and OTel keep the pipeline on your own Grafana and Tempo stack.
- **Cons** per-session vendor pricing, and a Faro pipeline is real infrastructure; it requires
  `traceparent` in the API's CORS allowlist and aggressive sampling at 1-10%; and replay needs
  consent and masking under GDPR.
- **Typical mistakes** 100% browser trace sampling, which is cost suicide that also floods the
  backend; session replay recording password or PII fields after an untested unmask.

## What holds whatever you pick

- Source-map upload and release tagging run in CI — errors without them are minified noise.
- `traceparent` (and `tracestate`/`baggage`) must be in the API's `Access-Control-Allow-Headers`, or
  browser trace context silently drops.
- Head-sample browser traces at 1-10% — the browser's sampling decision propagates downstream.
- Session replay is GDPR personal data: consent-gated, with mask-all-text and block-all-media
  defaults, and every unmask tested.
- Cap ingestion per project via spike protection — one release bug loop can burn a month's quota in
  minutes.
- Expect roughly 15-30% beacon loss to ad blockers; a first-party tunnel or proxy recovers most of
  it.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend error tracking SaaS with source maps and
release tags uploaded from CI, spike protection on, and no replay and no browser tracing yet. Name
the trigger that would add them — a latency complaint that lab scores cannot explain, an end-to-end
trace requirement, a support case that needs a replay — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which layers exist,
   self-hosted or SaaS, whether replay is on, and the browser sampling rate.
2. State the recurring cost of each — per-event or per-session pricing at expected volume, the RAM
   and ops a self-host obliges, the consent-banner work replay adds — and what reversing it later
   costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. The measurable outcomes become rows in `04-quality-scenarios.md` with a number and a unit: the
   browser trace sampling rate, the per-project ingestion cap, the field LCP/INP/CLS targets, and the
   error-rate threshold that gates a deploy.
5. Replay running without a tested unmask list, a CORS allowlist missing `traceparent`, and manual
   source-map uploads are rows in `07-risks.md`. Anything the human leaves open is a
   `TODO(question)` per `templates.md`.
