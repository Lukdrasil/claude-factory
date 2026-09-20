---
written_against: "web research 2026-08"
---

`written_against` names the specification and product state this rubric was checked against — RFC
9111 and RFC 5861, .NET HybridCache's single-flight scope, the Redis and Valkey licence split. A
vendor page or a newer RFC that contradicts it means this file is stale and needs re-research, not
that the solution drifted.

# Caching strategy — which layer earns its keep, and in what order

Load this when the design mentions caching, Redis or Valkey, a CDN, `Cache-Control`, TTLs, "the DB
is slow", or a read-heavy endpoint under spiky load. `data.md` owns the wider question of which
additional stores exist at all and how each stays current — a cache is one of its options, and this
file is the depth behind that option: the layer order, the TTL and invalidation policy, and the
stampede protection. `database-operations.md` owns the query and pooling problems a cache is often
reached for instead of fixing; `edge-proxy.md` owns the CDN and WAF tier the first layer here
depends on; `licensing.md` owns the Redis and Valkey licence split once it becomes load-bearing.

Outputs land in `03-containers.md` when a distributed cache becomes a unit with a writing owner, in
`04-quality-scenarios.md` where every observable staleness window becomes a number with a unit, in
`06-deployment.md` for the cache instance itself, and in an ADR per `templates.md`. Every choice
below reaches the human as options with consequences plus your recommendation, per `approaches.md`.

Caching is layered policy, not a product to install. The layers, in order of cheapness: **HTTP
caching** — `Cache-Control`, `ETag`/`If-None-Match` per RFC 9111, CDN rules — where the client and
the edge do the work and you run nothing; **in-process cache-aside** with short explicit TTLs;
**distributed cache-aside** of the Redis/Valkey class, only when replicas must agree or the working
set outgrows one process; and **write-through or read-through**, only when the cache is
deliberately the fronting read path.

Every cached value needs an explicit TTL and a named invalidation trigger. "We'll flush it when
it's wrong" is not a trigger. Hot keys need stampede protection: single-flight coalescing per key
(.NET HybridCache does this in-process), jittered TTLs so cohorts do not expire in sync, and
`stale-while-revalidate` (RFC 5861) to hide refresh latency.

Two failure modes are what this rubric exists to prevent. The first is stale-data bugs nobody can
reproduce, because five layers cache with implicit lifetimes. The second is a Redis that started as
an optimisation becoming a hard availability dependency — if the app falls over when the cache is
down, it is not a cache any more, it is a database with amnesia.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| The read/write ratio, and how hot the hottest keys are | caching pays on repeated reads, and on nothing else |
| Staleness tolerance per data class | reference data tolerates minutes; sessions, permissions and balances tolerate roughly zero |
| Whether responses are HTTP-cacheable at all | `GET` with stable URLs and validators works; POSTed GraphQL and per-user payloads do not |
| Replica topology | whether an in-process cache is coherent enough |
| Invalidation signal availability | is there a write path that can evict, or is TTL expiry the only truth? |
| Stampede exposure under spiky load | synchronised expiry of popular keys turns a miss into a self-inflicted outage |

## HTTP caching (headers plus CDN)

- **Use when** always first, for anything served over HTTP with per-URL identity. Zero
  infrastructure: browsers, proxies and CDNs do the work, and a correct `ETag` turns repeat fetches
  into 304s even at `max-age=0`.
- **Pros** you run nothing, and it scales with the client population; `stale-while-revalidate` at
  the CDN hides refresh latency.
- **Cons** it requires URL-addressable, correctly `Vary`'d responses, and is useless for POSTed
  queries and per-user payloads; invalidation is TTL or a CDN purge, with no fine-grained evict
  from the app.
- **Typical mistakes** wrong headers cached at a CDN — shared, invisible, and they outlive your
  deploy. Never mark per-user responses `public`.

## In-process cache-aside

- **Use when** the second layer is needed for single-node or per-replica-tolerable data —
  reference tables, config, feature flags. Nanosecond reads, no serialisation.
- **Pros** no network hop; trivial to add; falls back to the source transparently.
- **Cons** it is per-replica, so N replicas hold N independent copies expiring on their own clocks;
  and memory competes with the app, with the cache evicted on every deploy.
- **Typical mistakes** sessions or read-your-writes data behind a load balancer — the bug
  reproduces only when the LB routes you to the other replica, which is to say never on your
  machine.

## Distributed cache-aside (Redis / Valkey class)

- **License** Valkey is BSD-3; Redis 8+ is a tri-licence including AGPLv3.
- **Use when** there is a measured need: replicas must see the same cached value, the working set
  exceeds one process, or warm state must survive deploys. Sessions, rate counters, cross-replica
  memoisation.
- **Pros** coherent across replicas and survives deploys; .NET HybridCache fronts it with an L1
  layer plus per-key single-flight, though that single-flight is per-machine, not cluster-wide.
- **Cons** a network hop plus serialisation per read, orders of magnitude slower than in-process;
  and another stateful service, with every consumer holding its availability in the critical path
  unless you explicitly degrade to the source.
- **Typical mistakes** the classic drift — added as an optimisation, then code paths start assuming
  it exists, then a cache outage is a site outage.

## Write-through / read-through

- **Use when** rarely, and last: staleness tolerance is near zero for a hot dataset and you own the
  single write path, so the cache is by design always fresh after a write.
- **Pros** the cache and the store move in lockstep.
- **Cons** write latency now includes the cache, and every write path must go through it or the
  coherence is fiction; it caches data that is never read, and it couples the cache library into
  the domain's write path.
- **Typical mistakes** one bulk import or ops script writing around the cache, silently breaking
  the freshness guarantee the pattern was chosen for.

## Symptom → wrong reflex → right layer

| Symptom | Wrong reflex | Right layer |
|---|---|---|
| The same anonymous `GET` hammered by many clients | add Redis | HTTP: `Cache-Control` plus `s-maxage`, and let the CDN absorb it |
| Clients re-download unchanged large responses | an application cache | `ETag` plus `If-None-Match` — 304s cost a header |
| A reference table read on every request | a distributed cache | in-process cache-aside, TTL of minutes, jittered |
| Replicas show different data after a write | longer TTLs to smooth it out | distributed cache-aside, or evict-on-write via the write path |
| The DB spikes when a popular key expires | more cache nodes | stampede protection: single-flight, jittered TTL, `stale-while-revalidate` |
| A session is lost when a pod recycles | sticky sessions | a distributed cache — this is the measured need, not a reflex |
| "The API is slow", with no profile | add Redis | measure first; the missing index is not a caching problem |

## Staleness budget → mechanism

| Data class | Tolerable staleness | Mechanism |
|---|---|---|
| Static assets, versioned URLs | effectively infinite | `Cache-Control` `immutable`, `max-age=1y`; change the URL to change the content |
| Catalogue / reference data | minutes | cache-aside, TTL 1–5 min, jittered |
| User-visible aggregates | seconds to a minute | short TTL plus `stale-while-revalidate` |
| Sessions, permissions, balances | roughly zero | don't cache, or evict-on-write with the write path as the only writer |

## What holds whatever you pick

- The order is fixed: HTTP headers → in-process cache-aside → distributed cache → write-through.
  Skipping a layer requires a measurement, not a preference.
- Every cache entry gets an explicit TTL and a named invalidation trigger, decided at design time.
- A cache must be droppable: the system serves, degraded, with the cache empty or down. Otherwise
  the design has a hidden database.
- Cacheable responses carry an `ETag`; per-user responses are `private` or correctly `Vary`'d — a
  `public` header on personalised data is a data leak.
- Protect hot keys before launch: single-flight per key, jittered TTLs for cohorts, and
  `stale-while-revalidate` for expensive refreshes.
- Invalidation by event beats invalidation by guesswork: where the write path exists, evict there.
  TTL is the backstop, not the strategy.
- Do not cache what you have not profiled. A cache added to unmeasured slowness hides the missing
  index and adds a staleness bug on top.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the first layer only: correct
`Cache-Control` and an `ETag` on the shared, URL-addressable responses, with nothing new to run and
no staleness the client cannot revalidate away. Recommend no distributed cache until a measurement
names the read it is meant to serve. Name the trigger that would change it — a profiled hot read
that indexing does not fix, replicas visibly disagreeing after a write, sessions that must survive
a pod recycle — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which layers exist, the
   TTL per data class, the invalidation trigger for each, and the stampede protection on the hot
   keys.
2. State the recurring cost of each — the CDN's purge path and who can call it, a Redis instance to
   size, monitor and upgrade, the write latency a write-through adds — and what removing it later
   costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md` where a distributed cache becomes
   a unit with a writing owner.
4. Every observable staleness window becomes a `QS-` row with a number and a unit. A cache with no
   named invalidation trigger, a hot key with no single-flight, and a cache the system cannot run
   without are rows in `07-risks.md`, each with an owner. Anything the human leaves open is a
   `TODO(question)` per `templates.md`.
