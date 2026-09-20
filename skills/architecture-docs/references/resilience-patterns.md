---
written_against: "web research 2026-08"
---

`written_against` names the library and mesh defaults this rubric was checked against — the .NET
standard resilience handler's numbers, resilience4j's window sizes, Envoy and Linkerd retry
budgets, Istio's silent retry. A current doc page that contradicts a number below means this file
is stale and needs re-research, not that the solution drifted.

# Resilience patterns — timeouts, retries, breakers, bulkheads, idempotency

`communication.md` decides the protocol on each `Talks to` edge and, where the edge is
asynchronous, its delivery guarantee and dead-letter policy. This file decides what that edge does
when the far end is slow, flapping or gone: the per-attempt timeout, whether a retry is legal at
all, where the breaker sits, what isolates one dependency's pool from another's, and how a
redelivered message avoids a duplicate side effect. `message-bus.md` owns the broker product;
`operations.md` owns the alerting and health probes that make a tripped breaker visible.

Load it for any synchronous outbound dependency or at-least-once message consumer, and always for
microservices or an event-driven design. Outputs land on the edges in `03-containers.md`, in the
availability rows of `04-quality-scenarios.md`, and in an ADR per `templates.md`. Every choice below
reaches the human as options with consequences plus your recommendation, per `approaches.md`.

Every outbound edge needs an explicit fault policy, because the default policy is "wait forever,
then take the caller down with you". The safe default is a standard resilience pipeline per
dependency edge: an aggressive per-attempt timeout — around 2–3s for intra-datacenter calls, tuned
to that dependency's p99 and never left at the library default — a small jittered exponential retry
applied only to idempotent reads, a circuit breaker on each dependency edge, and idempotency keys
on every message consumer and payment-like endpoint.

Retries without a budget are an outage amplifier. At three layers of three retries each, one slow
dependency receives 27× traffic exactly when it is dying, while callers' pools exhaust upward
through the stack — the canonical cascading failure. .NET teams get the whole pipeline from
`Microsoft.Extensions.Http.Resilience`'s `AddStandardResilienceHandler` (Polly v8 underneath), JVM
teams from resilience4j; both retry non-idempotent methods unless you explicitly disable it, which
is the most common real-world misconfiguration of either. A service mesh — Envoy, Istio, Linkerd —
moves retries, timeouts and outlier detection into the sidecar with proper retry budgets, but it
cannot provide idempotency, fallbacks or degradation order: those are always application code.
Decide the graceful-degradation order per feature up front — serve stale cache, drop the panel,
queue the write — instead of discovering it during the incident.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Synchronous call chains two or more services deep | per-edge timeouts with a shrinking deadline down the chain, and retries at one layer only — multiplicative retry amplification is the main outage mechanism |
| At-least-once delivery anywhere: bus, webhooks, outbox | idempotency keys and a dedup store on every consumer — redelivery is a guarantee, not an edge case |
| Payment-like or side-effectful public endpoints | a client-supplied `Idempotency-Key` persisted with the response and replayed on a duplicate; never a bare retry |
| Third-party APIs with unknown or spiky latency | a circuit breaker plus a bulkhead on that edge, so one vendor's brownout cannot drain the shared pool |
| Availability stated as high, or an SLO with an error budget | a recorded per-edge policy with a degradation order per feature; "the framework handles it" is not reviewable |
| Already on Kubernetes with a mesh installed for mTLS or traffic management | mesh-enforced retries, timeouts and outlier detection with retry budgets; keep idempotency and fallbacks in code |
| Small team, monolith, one or two dependency edges | a library pipeline with defaults tuned once; a mesh is pure ceremony here |
| Load is spiky | ratio-based retry budgets (~20%) instead of fixed counts — fixed counts synchronize into retry storms at the traffic peak |

## No explicit policy (framework defaults)

- **Use when** prototypes, internal tools with one user, or batch jobs where the whole run can
  simply fail and be rerun. Never acceptable for microservices, events, or a high-availability
  target.
- **Pros** free, until the first brownout.
- **Cons** default timeouts are hostile — 100s on .NET's `HttpClient`, infinite waits on database
  commands. One slow dependency ties up caller threads for the full default timeout; pools exhaust,
  health checks fail, the orchestrator restarts healthy instances, and one degraded edge becomes a
  full outage.
- **Typical mistakes** assuming "no retry configured" means no retries — some SDKs retry internally
  without telling you; shipping the same defaults to an intra-datacenter edge and to a third-party
  API.

## Standard resilience library pipeline (Polly / resilience4j class)

- **License** Polly BSD-3-Clause, resilience4j Apache-2.0.
- **Use when** the safe default for almost everyone: monoliths with external dependencies, modular
  monoliths, and small-to-medium fleets without a mesh. One composed pipeline per named client or
  edge.
- **Pros** a few lines per client give the whole chain in order — rate limiter, total timeout,
  retry, circuit breaker, attempt timeout (.NET's `AddStandardResilienceHandler`) — over
  battle-tested implementations of every pattern.
- **Cons** the tuning pass is not optional: .NET's 10s attempt and 30s total defaults are far too
  slow for intra-datacenter edges. Policy lives in code, so consistency across teams depends on a
  shared package, or copy-paste drift sets in.
- **Typical mistakes** both major libraries retry all HTTP methods by default — you must exclude
  POST and PATCH yourself or you will duplicate writes; leaving the breaker's minimum throughput at
  its default (100 requests per 30s in .NET) so it never trips on a low-traffic edge.

## Per-edge recorded policy

- **Use when** high-availability targets, SLO shops, or payment and compliance domains: the library
  pipeline plus every dependency edge inventoried with its timeout, retry scope, breaker
  thresholds, bulkhead limits, idempotency mechanism and degradation order.
- **Pros** "what happens when X is down" has an answer before the incident; breaker thresholds get
  reviewed when the dependency's traffic profile changes instead of rotting; the best
  effort-to-value ratio above roughly three services.
- **Cons** it costs discipline — a table per service kept honest in review. Cheap in effort,
  expensive in willpower.
- **Typical mistakes** writing the table once at design time and never revisiting thresholds as
  traffic grows; recording the policy but never testing the fallback path — an unexercised fallback
  is a second bug waiting behind the first outage.

## Service mesh enforced (Envoy / Istio class)

- **License** Envoy, Istio and Linkerd Apache-2.0.
- **Use when** many polyglot teams on Kubernetes where per-language library consistency is
  unachievable, or the mesh is already there for mTLS and traffic management (`mtls-pki.md`). Never
  adopt a mesh for resilience alone.
- **Pros** uniform config-driven enforcement per route, with Envoy retry budgets — 20% of active
  requests by default — beating fixed counts under load; outlier detection ejects sick hosts
  automatically.
- **Cons** a platform to operate: upgrade trains, sidecar overhead, and a new debugging dimension.
  It cannot do idempotency keys, fallbacks, degradation order or business-aware bulkheads, so the
  application half of the policy remains yours.
- **Typical mistakes** Istio retries requests twice by default even with zero configuration, so
  mesh and library retries multiply unless someone owns the total-attempt budget; treating "we have
  the mesh" as the reason to skip the application-level half — teams still cascade, with prettier
  telemetry.

## Pattern, what it protects against, and how it is usually misconfigured

| Pattern | Protects against | Typical misconfiguration |
|---|---|---|
| Per-attempt timeout | a slow dependency tying up caller threads and connections | left at the library default (100s .NET `HttpClient`, infinite DB waits); only a total timeout, so one hung attempt eats the whole budget |
| Retry + jitter | transient blips, dropped packets, brief redeploys | retrying POSTs (the default in both major libraries); no jitter, so a thundering herd; retries at every layer, so 27× amplification |
| Retry budget | retry storms under a partial outage | not used — a fixed count of 3 everywhere; without a mesh, cap attempts at one layer only |
| Circuit breaker | hammering a dead dependency; failing fast during a brownout | minimum throughput too high for a low-traffic edge (.NET's default 100 per 30s never trips at 1 rps); no fallback wired, so "open" still throws |
| Bulkhead / pool limit | one edge draining the shared thread or connection pool | one global pool for all dependencies, so vendor X's brownout starves healthy vendor Y |
| Idempotency key + dedup store | duplicate side effects under at-least-once delivery | the key generated server-side per attempt; a dedup TTL shorter than the redelivery horizon; the response not replayed, so a retry returns 409 |
| Graceful degradation order | a full-page failure when one non-critical edge is down | never decided, so every caller improvises during the incident, and the cached-fallback path is untested and broken when exercised |

## Default numbers

| Knob | Safe default (intra-datacenter edge) | Library or mesh shipped default |
|---|---|---|
| Per-attempt timeout | 2–3s, tuned to the dependency's p99 | 10s (.NET standard handler) |
| Total request timeout | the caller's deadline minus a margin, shrinking down the chain | 30s (.NET standard handler) |
| Retry attempts | 2–3, idempotent reads only, exponential with full jitter | 3 (.NET, resilience4j); Istio silently adds 2 with no configuration |
| Retry budget | ~20% of live requests may be retries | Envoy 20%, minimum 3 concurrent; Linkerd `retryRatio` 0.2 plus 10 free per second |
| Circuit breaker | per edge, with ratio and minimum throughput sized to that edge's real rps | 10% ratio / minimum 100 in 30s / 5s break (.NET); 50% ratio over a window of 100 (resilience4j) |
| Consumer idempotency | a key on every message, with a dedup TTL beyond the maximum redelivery window | none — no library and no mesh does this for you |

## What holds whatever you pick

- Every outbound call has an explicit per-attempt timeout tuned to that dependency's p99. A missing
  timeout is a design defect, not a tuning nicety.
- Retry only idempotent operations, with backoff and full jitter, at exactly one layer of the call
  chain. Never retry POST or PATCH without an idempotency key already in place.
- Cap total retry load with a budget (~20%), or by hard-capping attempts at 2–3 on the single
  retrying layer: 3 × 3 × 3 is 27× on the dying dependency.
- A circuit breaker per dependency edge, with thresholds sized to that edge's actual traffic — the
  default never trips on a low-traffic edge.
- Idempotency keys with a persisted-response dedup store on every at-least-once consumer and
  payment-like endpoint; the TTL runs beyond the redelivery horizon, and the stored response is
  replayed rather than rejected.
- Write down the degradation order per feature — stale cache, then feature off, then queue, then
  error — before the first incident, and test the fallback path.
- If a mesh enforces retries, audit for double-retry: Istio retries twice by default on top of
  whatever the application does.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the standard library pipeline with one
composed policy per named client: a 2–3s per-attempt timeout, two or three jittered retries on
idempotent reads only, a breaker sized to that edge's real rps, and an idempotency key on every
consumer. Name the trigger that would change it — a polyglot fleet large enough that per-language
consistency fails, a third-party edge with unknown latency, a first payment endpoint — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which edges exist, what
   each one's timeout and retry scope is, and which layer of the chain is allowed to retry at all.
2. State what each costs — the tuning pass, the discipline of a per-edge table, the platform a mesh
   obliges someone to operate — and what reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md`.
4. Annotate every outbound edge in `03-containers.md` with its policy, and record the degradation
   order per feature alongside the scenario it protects in `04-quality-scenarios.md`.
5. An untested fallback path, a breaker whose thresholds were never resized, an at-least-once
   consumer with no dedup store, and mesh-plus-library retries with no total-attempt owner are rows
   in `07-risks.md`. Anything the human leaves open is a `TODO(question)` per `templates.md`.
