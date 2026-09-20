---
written_against: "web research 2026-08"
---

`written_against` names the research and regulatory state this rubric was checked against — InfoQ's
2026 multi-region trade-off analysis, the cost premium of active-active operation, and the GDPR and
Schrems II treatment of backups, replicas and log pipelines as in-scope data. A source that
contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Global audience — where the users are, and what geography actually costs the architecture

Load this when the profile records user geography, or the design mentions global users,
multi-region, CDN, edge, data residency or worldwide latency. `machine-topology.md` decides host
count and failover inside a region and `edge-proxy.md` owns the proxy and CDN tier in front of it;
this file decides how many regions there are and why. `disaster-recovery.md` owns the
survival reasons for a second region, which are not the same as the latency reasons here — read
both before recommending multi-region to anyone.

Outputs land in `04-quality-scenarios.md` (the latency target with its number and the population it
applies to), in `06-deployment.md` (the regions, the routing, and where data and its backups live),
in `02-constraints.md` when residency rules narrow the choice, and in an ADR per `templates.md`.
Every choice below reaches the human as options with consequences plus your recommendation, per
`approaches.md`.

Geography changes latency budgets, DR shape, residency exposure and on-call. For most dynamic apps a
single well-run region plus a CDN for static assets covers a global audience: CDN and edge fix asset
latency, but dynamic requests still pay the round trip to the origin database, so "multi-region for
latency" only pays off when writes must be close to users. InfoQ's 2026 trade-off analysis found
that latency-based routing plus a CDN recovers roughly 80% of the latency benefit of a new region
for read-heavy workloads, while active-active adds 20–35% operational cost plus replication and
consistency complexity.

Two constraints bound the design. **Multi-region write replication without an explicit conflict
strategy** — region-pinned writes, CRDTs, or a documented last-writer-wins — is a data-loss design,
not an availability one. And **residency cuts against global replication**: regulators treat
backups, replicas, CDN logs and log pipelines the same as the live database, so EU data backed up to
a US region is a violation regardless of encryption (GDPR, Schrems II).

Going global also means picking a DR region deliberately — legal jurisdiction, distance and service
parity, not just the next one in the dropdown — using UTC everywhere with per-user timezone and i18n
rendering, and being honest about on-call, because a global audience has no quiet hours.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Where the p95 user actually is: one metro, one continent, or three continents | a single region plus a CDN as the default; multi-region only with a concrete latency or availability driver |
| A read-heavy mix with tolerance for minutes of staleness | CDN or edge caching of dynamic responses — recovers most latency without replication |
| Writes must be low-latency near users on multiple continents | active-active with an explicit conflict strategy — the only case that justifies it |
| Compliance includes residency | pin data *and* its backups and logs per jurisdiction, or partition stacks per region |
| A global audience with availability expectations | no maintenance window exists; follow-the-sun on-call, or an explicit degraded-off-hours statement |

## Single region plus a CDN for static assets

- **Use when** the default for global audiences of dynamic apps: users everywhere, one write region.
- **Pros** the cheapest and simplest honest global setup; pick the region nearest your densest user
  cluster and be done.
- **Cons** dynamic requests still cross the ocean at 100–250 ms, which is acceptable for most CRUD
  apps and felt in chatty UIs.
- **Typical mistakes** jumping to multi-region compute when the p95 complaint is actually asset load
  time that a CDN would fix.

## Single region plus edge caching of dynamic responses

- **Use when** read-heavy public content — catalogues, articles, search results — where minutes of
  staleness is fine.
- **Pros** the CDN caches API and HTML responses at the edge, recovering most read latency without
  any replication.
- **Cons** cache invalidation discipline is required, and writes and personalised reads still hit
  the origin.
- **Typical mistakes** caching personalised responses at the edge and leaking one user's data to
  another.

## Multi-region read replicas, single write region

- **Use when** dynamic reads must be fast on multiple continents but writes can tolerate one home
  region.
- **Pros** fast local reads with no write conflicts.
- **Cons** replication lag means read-your-writes needs session pinning; and it doubles the
  infrastructure to run and monitor while leaving write latency unchanged.
- **Typical mistakes** serving read-your-writes flows from a lagging replica, then debugging "my
  save disappeared" tickets.

## Multi-region active-active

- **Use when** only when writes genuinely need to be low-latency from multiple continents, or
  availability demands surviving a full region loss with near-zero RTO.
- **Pros** survives full region loss with near-zero RTO, and gives local write latency on every
  continent.
- **Cons** the most expensive pattern, at +20–35% operational cost; it requires an explicit
  write-conflict strategy — region-pinned or home-region writes, CRDTs, or documented
  last-writer-wins — plus regular per-region failover drills; and it often conflicts with residency
  obligations.
- **Typical mistakes** replicating writes globally with no conflict strategy, which is a data-loss
  design rather than an availability one.

## Regional partitioning (separate stacks per jurisdiction)

- **Use when** residency obligations dominate: EU users' data lives and stays in an EU stack,
  including backups and logs.
- **Pros** the cleanest residency answer, with no cross-border replication to explain to a
  regulator.
- **Cons** global features such as cross-region search and cross-region users get hard, and
  per-region ops is multiplied.
- **Typical mistakes** partitioning the live database per region while backups and log pipelines
  still replicate centrally.

## What holds whatever you pick

- A CDN plus latency-based routing recovers roughly 80% of a new region's latency benefit for
  read-heavy workloads, at a fraction of the cost.
- Multi-region writes need an explicit conflict strategy: region-pinned, CRDTs, or documented
  last-writer-wins.
- Regulators treat backups, replicas, CDN logs and log pipelines the same as the live database for
  residency.
- Pick the DR region deliberately — jurisdiction, distance and service parity, not the dropdown
  default.
- A global audience has no maintenance window and no quiet hours. Plan on-call accordingly.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a single region chosen for the densest user
cluster, a CDN in front for static assets, latency-based routing, and no second region at all. Name
the trigger that would change it: a measured p95 latency complaint that a CDN does not fix, a write
path that must be local on a second continent, a residency clause, or a signed availability target
that needs to survive region loss. Each trigger is a row in `07-risks.md` until it becomes a
scenario.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: how many regions, where writes
   happen, and where data and its backups and logs are allowed to live.
2. State each option's ongoing cost — the +20–35% operational premium of active-active, the doubled
   monitoring of read replicas, the multiplied ops of regional partitioning — and the on-call model
   it obliges.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `06-deployment.md`.
4. The latency target becomes a row in `04-quality-scenarios.md` with a number and the population it
   applies to.
5. Multi-region writes with no conflict strategy, backups or log pipelines crossing a residency
   boundary, a DR region picked from the dropdown, and an on-call rota that assumes quiet hours are
   rows in `07-risks.md`, each with an owner. Anything the human leaves open is a `TODO(question)`
   per `templates.md`.
