---
written_against: "web research 2026-08"
---

`written_against` names the practice and platform state this rubric was checked against — the
cell-sizing and blast-radius figures, and the retrofit costs of each tenant operation. Guidance that
contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Tenant operations — quotas, noisy neighbours, and per-tenant data operations

`security.md` picks the isolation model: shared schema with a tenant column, schema per tenant, or
database per tenant. This file starts after that answer and asks the two questions the isolation
diagram does not show. Can one tenant degrade the others? And can you export, restore, migrate, or
meter exactly one tenant without touching the rest? Where the tenant data actually lives and how
many stores hold it is `data.md`; the backup and restore machinery those operations ride on is
`operations.md`; how many hosts and shards the answer implies is `machine-topology.md`.

Operational multi-tenancy is what the isolation diagram omits: shared compute, shared queues and
shared query capacity mean one tenant's batch job is everyone's incident unless per-tenant limits
exist. Limits must be per-tenant and per-tier, keyed on tenant identity at the gateway — a token
bucket in a shared store, a 429 with `Retry-After` — plus per-tenant connection pools, query
timeouts by tier, and fair-share or dedicated queues for background work.

The second half is per-tenant data operations: export one tenant, restore *one* tenant to a point
in time, move a tenant to another shard, and meter what each tenant consumed. Every one of these
requires `tenant_id` on every row and every usage event from day one; none can be bolted on
cheaply. Whole-database PITR restores everyone to yesterday — that is not tenant restore, that is a
second incident. The safe default is per-tenant quotas at the API layer plus tenant-scoped export
and erasure tooling from the first release; cell-based sharding is the earned tier, not the
starting point.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Any tenant can trigger bulk work on shared infrastructure | per-tenant rate limits at the gateway, per-tenant queue fairness, query timeouts by tier |
| Tenants pay different tiers with different SLAs | per-tier quotas and priority lanes: premium gets dedicated workers, free gets hard caps |
| A contract or regulator can demand one tenant's data | tenant-scoped export and erasure tooling; `tenant_id` on every row is the precondition |
| A tenant will someday delete their own data and demand it back | restore-one-tenant design: per-tenant databases, or a rehearsed side-restore-and-copy runbook |
| Usage-based pricing | `tenant_id` stamped on every usage event at emission — reconstruction from logs produces disputed invoices |
| One large tenant outgrowing the shared pool | shard by `tenant_id` so a hot tenant can be isolated to its own shard online |
| Blast radius of a bad deploy must be capped | cell-based architecture: independent cells of 10–50 tenants cap worst case at 1–5%; shuffle-sharded workers as the cheaper mid-step |

## Single-tenant (not applicable)

- **Use when** one customer per deployment: the backup *is* the tenant backup, the meter *is* the
  invoice. Do not build multi-tenant machinery for it.
- **Pros** restore, export, migrate and meter are whole-system operations you already have, and
  there is no noisy neighbour by construction.
- **Cons** per-customer infrastructure cost and fleet burden grow linearly, and turning it
  multi-tenant later is a re-architecture.
- **Typical mistakes** skipping `tenant_id` in the schema "because there is only one" — the
  cheapest column you will ever add is the one you add now.

## Shared everything with per-tenant quotas

- **Use when** the pragmatic floor for real multi-tenant SaaS: shared compute and database, but
  every request carries tenant identity and hits a per-tenant, per-tier limit before compute.
- **Pros** token-bucket quotas in a shared store are days of work; they cap the noisy neighbour at
  the front door, at the cheapest infrastructure cost per tenant.
- **Cons** it protects the API layer only — a heavy query or background job still starves the
  shared database and workers; and restore-one and migrate-one remain unsolved.
- **Typical mistakes** one global rate bucket for all tenants, where the noisy tenant consumes the
  allowance and the limiter punishes the victims; rate-limiting the API but not the background
  queue, which is where the batch damage happens; no per-tenant query timeout, so one analytical
  query holds the pool.

## Quota plus tenant-scoped data operations

- **Use when** the safe default for SaaS with real contracts: everything above, plus export-one,
  erase-one, a rehearsed restore-one path, and per-tenant usage metering.
- **Pros** it meets the contractual reality of B2B — export on offboarding, erasure on demand,
  "restore what we deleted yesterday" — and the `tenant_id`-everywhere discipline is exactly what a
  later shard-by-tenant migration needs.
- **Cons** restore-one in a shared schema is still surgery: restore PITR to a side database, then
  copy one tenant's rows in foreign-key order. Build and rehearse the runbook before the incident.
- **Typical mistakes** believing whole-database PITR covers tenant restore; metering from access
  logs after the fact instead of stamping events at emission; export tooling that misses blob
  storage, search indexes and queues.

## Cell-based / sharded tenants

- **Use when** scale or blast-radius requirements justify it: tenants partitioned across independent
  cells or shards keyed by `tenant_id`, with a routing layer.
- **Pros** blast radius becomes an explicit parameter — 10–50-tenant cells cap impact at 1–5% — and
  tenant restore and migration become first-class, with deploys rolling cell by cell.
- **Cons** the highest operational cost of the four: a fleet of cells, a routing layer, a cross-cell
  control plane; and cross-tenant features such as global search and analytics now span cells.
- **Typical mistakes** building cells before per-tenant quotas, when cells cap blast radius
  *between* cells and quotas cap it *within* one; a tenant-to-cell routing table that is itself a
  shared single point of failure; no migration tooling between cells, so imbalance becomes
  permanent.

## Tenant operations: data-model requirements and the retrofit bill

| Operation | What it requires in the data model | Cost of retrofitting |
|---|---|---|
| Export one tenant | `tenant_id` on every row, plus tagging on blobs, indexes, queue messages; a manifest of which stores hold tenant data | Medium: weeks of ownership-chain archaeology; untagged blobs may be unattributable |
| Restore one tenant | Per-tenant databases (PITR restores exactly one), or shared schema plus a rehearsed side-restore-and-copy runbook with FK-ordered scripts | High: without `tenant_id` discipline, selective restore is manual forensics under incident pressure |
| Migrate a tenant between shards | All tables distributed by `tenant_id`; no cross-tenant FKs; routing indirection the app actually consults | Very high: re-keying a shared schema is a re-architecture — months, not sprints |
| Meter per-tenant usage | `tenant_id` stamped on every usage event at emission; per-tenant per-period aggregation | Medium and lossy: reconstructing history from logs produces disputed invoices |

## What holds whatever you pick

- One global rate limit is not multi-tenant rate limiting: limits are per-tenant and per-tier, keyed
  on tenant identity at the gateway.
- The gateway quota protects the front door only — queues, connection pools and long queries need
  their own per-tenant fairness, or the batch job walks around the limiter.
- Whole-database restore is not tenant restore: PITR that drags every tenant back to fix one is a
  second incident.
- `tenant_id` on every row and every usage event from day one is the cheapest decision in this
  rubric.
- Meter usage in the platform, price it elsewhere: stamp events at emission.
- Export and erasure must cover every store that holds tenant data — or the export is incomplete and
  the erasure is a lie.
- Cell-based architecture is the earned tier; cells without per-tenant quotas just shrink the room
  the noisy neighbour wrecks.
- A hot tenant needs an exit path designed in: if migration was never designed, the biggest customer
  and the platform degrade together.

## When the evidence is thin

If nothing recorded distinguishes the tiers, recommend quotas plus tenant-scoped data operations:
`tenant_id` on every row and every usage event, a per-tenant per-tier token bucket at the gateway
returning 429 with `Retry-After`, per-tenant query timeouts and queue fairness, and export, erasure
and a rehearsed restore-one runbook before the first contract. Name the trigger that would earn
cells — a tenant outgrowing the shared pool, a blast-radius number in a contract, a deploy incident
that took every tenant down — as a row in `07-risks.md`.

## Recording the choice

1. Put the tiers to the human against the affected `QS-` and `C-` ids: which per-tenant operations
   a contract or regulator can actually demand, and which of them the current data model can serve
   today.
2. State the recurring cost of each — the shared quota store, the metering pipeline, the cell fleet
   and its routing layer — and what changing it later costs, which for shard-by-tenant means
   re-keying a shared schema.
3. Write the accepted tier as an ADR under `docs/adr/`, the rejected tiers as alternatives with the
   reason each lost, and reference it from `03-containers.md` beside the store and from
   `06-deployment.md` beside the quota and queue topology.
4. Numbers become `QS-` rows: the per-tier request quota, the per-tenant query timeout, the time to
   export one tenant, the time to restore one tenant, cell size and the blast-radius percentage it
   implies. An unrehearsed restore-one path, an export that skips a store and a routing table with
   no failover are `R-` rows in `07-risks.md` with an owner. Anything the human leaves open is a
   `TODO(question)` per `templates.md`.
