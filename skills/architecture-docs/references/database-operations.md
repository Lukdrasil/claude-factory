---
written_against: "web research 2026-08"
---

`written_against` names the product and support state this rubric was checked against — the
Postgres major-version EOL calendar, PgBouncer's prepared-statement support, the managed proxies'
pinning behaviour. A vendor page that contradicts it means this file is stale and needs
re-research, not that the solution drifted.

# Database day 2 — pooling, bloat, slow queries, upgrades

Load this when a relational primary store is in play and the discussion has moved past schema into
deployment: replicas scale, ops is thin, or the engine version has a birthday coming.
`database-products.md` has already settled which engine carries the primary store and whether it is
managed; this file is what happens to it afterwards. `operations.md` owns backups, telemetry
backends and alerting; `machine-topology.md` owns how many machines and what fails over;
`database-tls-operations.md` owns the certificates; `caching-strategy.md` owns the layer people
reach for instead of fixing a query.

Outputs land in `06-deployment.md` (the pooler, the connection budget, the upgrade path), in
`04-quality-scenarios.md` where an upgrade's downtime class becomes a number, and in an ADR per
`templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

Databases do not fail on day 1; they fail on day 400. There are four recurring killers.
**Connection exhaustion**: each Postgres connection is an OS process costing roughly 5–10 MB,
default `max_connections` is 100, and an autoscaled app tier multiplies client pools until the
primary refuses logins. **Bloat**: dead tuples accumulate because autovacuum was left at the 20%
default scale factor, or disabled outright. **Unreviewed slow queries**: `pg_stat_statements`
installed but never read. And **the forced march of major upgrades**: every Postgres major gets
exactly five years — 13 died in November 2025, 14 dies in November 2026.

None of these needs a DBA. They need a pooler, three config values, a recurring 30-minute review,
and one rehearsed runbook. The failure mode for skipping all four is identical in every case: an
incident at the worst possible time, resolved in a panic by someone reading the docs for the first
time.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| App replica count, and whether it autoscales | the connection multiplier nobody computes until `FATAL: too many clients` |
| Managed versus self-hosted | RDS and Cloud SQL buy backups and blue-green switchovers, not query hygiene |
| Write and update rate on hot tables | whether default autovacuum (20% dead rows) is fine or a bloat factory |
| Latency sensitivity and ORM session state | transaction-pooling interplay: PgBouncer 1.21+ handles prepared statements, but session state (`SET`, advisory locks) pins or breaks it |
| Downtime tolerance for upgrades | minutes (`pg_upgrade --link`) versus seconds (logical replication or managed blue-green) |
| Distance to the current major's EOL | a five-year clock, mid-November, every year — rehearse a year out |

## Defaults until it hurts

- **Use when** prototypes, internal tools and single-box deployments with a handful of users — and
  the cliff is being accepted knowingly.
- **Pros** works at one to three replicas and small load.
- **Cons** the cliff is precise: replicas × client pool size crosses `max_connections` (default
  100) and new connections are refused — during a scale-out event, which is to say at peak traffic.
  Bloat accrues invisibly, and the major upgrade happens at EOL under duress.
- **Typical mistakes** never doing the connection math until the outage does it for you.

## Pooler and monitored basics

- **License** PgBouncer is ISC.
- **Use when** this is the sane default for any production relational store with autoscaling or
  more than roughly five app replicas: a server-side pooler (PgBouncer in transaction mode, or the
  RDS Proxy class), autovacuum lowered per-table on hot tables, and `pg_stat_statements` enabled.
- **Pros** removes the connection cliff, multiplexing hundreds of client connections onto tens of
  server connections; bloat and slow queries become at least visible.
- **Cons** transaction pooling forbids session state, so ORMs must be configured accordingly, and
  RDS Proxy silently pins sessions that set state, eating the benefit you paid for.
- **Typical mistakes** raising `max_connections` instead of pooling — each connection is a process,
  so memory pays either way; enabling `pg_stat_statements` and never reading it.

## Full day-2 runbook (pooling, bloat, upgrades rehearsed)

- **Use when** the store is revenue-bearing, or there is dedicated ops: a documented connection
  budget with per-service pool sizes under `max_connections` and headroom, scheduled query review,
  bloat monitoring with `REINDEX CONCURRENTLY` around 20% bloat, minor upgrades on a cadence, and a
  written, staged major-upgrade play executed a year before EOL.
- **Pros** no panic upgrades, no mystery 2× storage growth, and slow queries fixed while they are
  still cheap to fix.
- **Cons** recurring calendar time and a staging clone; overkill for small stores.
- **Typical mistakes** doing the runbook once and letting it rot — the cadence is the whole point.

## Connection math: why ~10 replicas is the cliff

| App replicas | Client pool per replica | Total demanded | Against `max_connections=100` |
|---|---|---|---|
| 3 | 10 | 30 | fine |
| 5 | 20 | 100 | at the wall (superuser slots squeezed) |
| 10 | 20 | 200 | refused — `FATAL: too many clients` |
| 10 + pooler | 20 (into PgBouncer) | ~20–40 server connections | fine, with headroom |
| autoscale burst to 30 | 20 | 600 | only a pooler survives this |

## Postgres major-upgrade paths

| Path | Downtime class | Gotchas |
|---|---|---|
| `pg_upgrade --link` (in-place) | minutes when rehearsed | no rollback once the new cluster starts on linked files; rehearse on a clone |
| logical replication to a new cluster | near-zero — switchover only | DDL is not replicated, sequences need syncing, and the switchover must be drilled |
| managed blue-green (RDS class) | seconds at switchover | the same logical-replication constraints underneath; test the green side first |
| dump/restore | hours or more | only for small databases, or for encoding and hardware changes |

## What holds whatever you pick

- Put a server-side pooler in once app replicas exceed a handful: replicas × pool size must stay
  under `max_connections`, and nobody re-does that math during an autoscale event.
- Default `max_connections` is 100 and each connection is a process at roughly 5–10 MB; past about
  200 direct connections you should be pooling, not raising the limit.
- Transaction pooling forbids session state — `SET`, advisory locks and `LISTEN`/`NOTIFY` pin or
  break it; PgBouncer 1.21+ handles prepared statements in transaction mode.
- Tune autovacuum, never disable it: anti-wraparound vacuum runs anyway, just at the worst possible
  time. Drop `scale_factor` per-table on large hot tables.
- Enable `pg_stat_statements` on day 1 and read it on a cadence, sorting by total time rather than
  by max.
- Monitor index bloat and rebuild online with `REINDEX CONCURRENTLY` around the 20% mark.
- Every Postgres major lives exactly five years — 14 dies in November 2026. Pick the upgrade path
  and rehearse it on a clone at least a year out.
- Apply minor versions routinely and boringly: a team that has never done a minor upgrade will not
  survive a major one calmly.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the pooler and monitored basics: PgBouncer
in transaction mode (or the managed proxy the platform already offers), autovacuum tightened on the
hot tables, `pg_stat_statements` on from day 1, and a diary entry a year ahead of the current
major's EOL. Name the trigger that would push it to the full runbook — the store becoming
revenue-bearing, the first autoscale event, the first `FATAL: too many clients` — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: the pooler and its mode,
   the connection budget per service, the autovacuum overrides, and the chosen major-upgrade path.
2. State the recurring cost of each — the pooler as an operational component, the review cadence in
   someone's calendar, the staging clone an upgrade rehearsal needs — and what skipping it costs at
   EOL.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `06-deployment.md`, which records the pooler, the
   connection budget and the upgrade path.
4. An unpooled autoscaled app tier, an unread `pg_stat_statements`, an unrehearsed upgrade and a
   major version inside a year of EOL are rows in `07-risks.md`, each with an owner. Anything the
   human leaves open is a `TODO(question)` per `templates.md`.
