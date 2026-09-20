---
written_against: "web research 2026-08"
---

`written_against` names the licence and product state this rubric was checked against — Redis's
tri-licence since Redis 8, CockroachDB's retired free Core tier, MongoDB's SSPL, the managed
flavours' feature sets. A vendor page that contradicts it means this file is stale and needs
re-research, not that the solution drifted.

# Database products — which engine carries the primary store, and what running it costs

Load this when the primary datastore product is being chosen or reviewed, when self-hosted versus
managed is still open, or when a licensing or HA question about a database needs an answer.
`data.md` owns every store *beyond* the primary — cache, search index, read replica, OLAP — and
starts once this file has settled what the primary is. `database-operations.md` picks the story up
on day 2, with pooling, vacuum, slow queries and upgrades; `database-tls-operations.md` owns the
certificates the chosen engine has to serve; `machine-topology.md` owns how many machines the
answer implies and which stateful component is the availability ceiling; `licensing.md` owns the
licence-family question once a product's licence turns out to be load-bearing.

Outputs land in `03-containers.md` (the store as a unit, with its writing owner), in
`06-deployment.md` (self-hosted or managed, and where it runs), in `02-constraints.md` when a
licence or a procurement policy narrows the field, and in an ADR per `templates.md`. Every choice
below reaches the human as options with consequences plus your recommendation, per `approaches.md`.

The primary store is the hardest thing in the system to swap later, so pick boring and liquid:
PostgreSQL, or the cloud-managed flavour of whatever the team already runs competently. Postgres
wins on licence (permissive, no vendor), ecosystem, hiring and extension breadth; its real costs
are vacuum and bloat care, connection management via pgbouncer, and the fact that automatic
failover is not built in — you buy that with Patroni or with a managed service. SQL Server is a
fine engine attached to a per-core invoice that dominates infrastructure cost at scale. MongoDB is
SSPL, which is not OSI open source and matters the moment you redistribute it or offer it as a
service.

The 2024–2026 licensing churn is real and recent enough to catch people out: Redis went SSPL and
then added AGPLv3 back in Redis 8 (May 2025) while Valkey stayed BSD-3, and CockroachDB retired its
free Core tier in November 2024 for a single proprietary licence, free under $10M revenue.
Distributed SQL and ClickHouse are answers to specific problems — multi-region survival, OLAP — not
defaults. SQLite is the honest choice for single-host applications, right up until a second machine
needs the data. And if nobody on the team wants to run replication and backups, the decision is
"managed Postgres", not "which database".

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| No strong reason otherwise; general OLTP workload | PostgreSQL — self-hosted only with real ops capacity, else managed |
| Team already operates MySQL or SQL Server well | stay on it; competence beats fashion, and migration is the most expensive move available |
| Single machine, one process, modest write concurrency | SQLite embedded; skip the client-server tax entirely |
| A .NET shop with existing SQL Server licences or an EA, and DBA skills | SQL Server — but price core licensing before autoscaling anything |
| Genuinely document-shaped data plus a need for its ecosystem | MongoDB — after checking that `jsonb` in Postgres does not already cover it |
| Multi-region writes, with surviving the loss of a region as a hard requirement | distributed SQL (CockroachDB / YugabyteDB class); accept the ops and licensing weight |
| Analytics over billions of rows, aggregation-heavy | ClickHouse as a secondary OLAP store, never as the primary |
| Ops capacity none or limited, or availability high without a DBA | the cloud-managed flavour (RDS/Aurora, Azure SQL or Flexible Server, Cloud SQL) |
| Compliance requires OSI-approved licences only | PostgreSQL, MariaDB, SQLite, Valkey, ClickHouse; excludes MongoDB (SSPL) and CockroachDB (proprietary) |
| Sub-millisecond key-value access over rebuildable data | Redis / Valkey — as cache or ephemeral store, never the system of record |

## PostgreSQL

- **License** PostgreSQL License — permissive, OSI-approved; no company owns it.
- **Use when** you need a default primary store for OLTP; relational, `jsonb` document, full-text
  and pgvector workloads on one engine; any team without a specific reason to pick something else.
- **Pros** the deepest ecosystem of the decade — extensions (PostGIS, pgvector, timescaledb), every
  ORM, every hiring pool; one engine covers relational plus `jsonb` plus search plus queues (`SKIP
  LOCKED`), which defers polyglot persistence for years; a serious engine underneath, with MVCC,
  transactional DDL, rich indexing and logical replication for zero-downtime major upgrades; and no
  licence risk ever, with a managed flavour on every cloud, so the exit path is symmetric.
- **Cons** autovacuum, bloat and transaction-ID wraparound need monitoring on write-heavy
  workloads; process-per-connection means you will run pgbouncer sooner than expected; there is no
  built-in automatic failover, so promotion needs Patroni, repmgr or a managed service; and
  major-version upgrades are an operation, not a `yum update`.
- **Typical mistakes** self-hosting with zero ops capacity "because Postgres is easy", then
  discovering failover is DIY; choosing MongoDB for JSON without testing `jsonb` first; leaving
  autovacuum defaults on a high-churn table and meeting wraparound in production; one instance with
  dumps as the "HA story" while promising high availability.

## MySQL / MariaDB

- **License** MySQL: GPLv2 plus an Oracle proprietary dual licence. MariaDB: GPLv2,
  foundation-governed.
- **Use when** the team already runs it well; LAMP-heritage stacks; ecosystems built around MySQL
  replication (Vitess class); read-heavy web workloads.
- **Pros** battle-hardened replication with decades of operational folklore, and GTID failover that
  is well understood; an enormous hosting, tooling and hiring ecosystem, with a managed flavour on
  every cloud; and Vitess as a proven horizontal-sharding path that Postgres lacks natively.
- **Cons** weaker than Postgres on advanced SQL, DDL transactionality, extensibility and JSON
  ergonomics; Oracle ownership steers investment toward the enterprise edition while the community
  edition moves slower; and the MySQL/MariaDB divergence is real — they are not drop-in compatible
  any more, so pick one deliberately.
- **Typical mistakes** migrating a working MySQL estate to Postgres for fashion, spending a year on
  migration for marginal gain; treating MariaDB and MySQL as interchangeable in drivers,
  replication and JSON functions; running async replication and calling it HA without ever testing
  promotion under load.

## SQL Server

- **License** proprietary (Microsoft). Per-core licensing in 2-core packs with a 4-core minimum, or
  Server plus CAL; a Standard versus Enterprise feature gate; Express capped; Developer free for
  non-production only.
- **Use when** the team has SQL Server DBAs and existing licensing, deep .NET/SSRS/SSIS integration
  is load-bearing, or the enterprise has already standardised on it.
- **Pros** an excellent engine and tooling — query store, columnstore, Always On availability
  groups; automatic failover that is genuinely built in via Always On AGs with quorum, unlike
  Postgres; and an enterprise support contract, meaning there is someone to call.
- **Cons** per-core licensing scales with your hardware, so every core added for load adds licence
  cost, with Enterprise list price running to five figures per core pair; features teams assume are
  standard turn out to gate on Enterprise edition; and Linux and container support exist without
  the licensing getting any cheaper there.
- **Typical mistakes** choosing it on a tight budget because Developer edition was free, then
  meeting production licensing as a five- to six-figure surprise; autoscaling or over-provisioning
  cores without recounting licences; running it in Kubernetes or Compose without reading the
  per-core virtualization rules; picking it under an OSI-only compliance constraint.

## SQLite

- **License** public domain.
- **Use when** single-host applications, embedded, edge or desktop deployments, read-heavy sites
  and internal tools — anywhere the app and the data live on the same machine and the design is
  honest about staying that way.
- **Pros** zero operations: no server, no users, no network, no TLS to rotate — the database is a
  file; in WAL mode it handles surprisingly serious read-heavy production traffic; backups are file
  copies or Litestream streaming to object storage; and it gives the fastest possible local latency
  while letting tests run against the real engine.
- **Cons** one writer at a time, so write-heavy concurrent workloads hit the wall; no network
  access, so the model breaks the moment a second machine needs the data; and HA is bolt-on —
  Litestream restores, not failover — with no story for an autoscaling app tier.
- **Typical mistakes** deploying on multi-instance infrastructure where each node gets its own
  divergent database file; putting it on network storage (NFS) and corrupting it; skipping WAL mode
  and blaming SQLite for lock contention; not planning the exit to Postgres before write
  concurrency demands it.

## MongoDB

- **License** SSPL v1 — not OSI-approved, source-available. Drivers are Apache-2.0; Atlas is a
  commercial contract.
- **Use when** the data is genuinely document-shaped with a variable schema per record, the team
  commits to schema discipline in code, and Postgres `jsonb` has been evaluated and found
  insufficient.
- **Pros** best-in-class document ergonomics — nested documents, the aggregation pipeline, change
  streams; replica sets with automatic failover built in and mature, giving better out-of-box HA
  than vanilla Postgres; and a native sharding path, with Atlas as a polished managed service.
- **Cons** SSPL fails OSI-only procurement policies, making legal review a recurring tax; the
  schema lives in application code, so without discipline you get silently inconsistent documents;
  and multi-document transactions are bolted on and slower, so relational workloads fit badly.
- **Typical mistakes** choosing it because the data "is JSON" when it is actually relational with
  joins everywhere; embedding unbounded arrays that grow past the 16 MB document limit; skipping
  schema validation and discovering five shapes of the same document in production.

## Redis / Valkey (as a data store)

- **License** Redis 8+: a tri-licence of AGPLv3, SSPLv1 and RSALv2, where AGPLv3 restored OSI
  status. Valkey, the Linux Foundation fork: BSD-3-Clause.
- **Use when** it is the primary store only for data that is ephemeral, rebuildable, or tolerates
  loss windows — sessions, queues, leaderboards, rate limits. As a cache it is nearly always fine
  (`caching-strategy.md`).
- **Pros** sub-millisecond operations and data structures no SQL engine matches; Valkey offers the
  same protocol under a clean BSD licence with major-cloud backing; and Sentinel or Cluster provide
  failover.
- **Cons** persistence (RDB/AOF) is a durability compromise, not a guarantee; the economics are
  memory-bound, since the dataset must fit in RAM and is priced accordingly; and the 2024 licence
  saga split the ecosystem, so managed services and clients are fork-aware now.
- **Typical mistakes** using it as the system of record for data you cannot regenerate; pinning to
  Redis-only modules, then discovering they are not in Valkey; a single instance with no AOF
  described as durable.

## Distributed SQL (CockroachDB / YugabyteDB class)

- **License** CockroachDB: a proprietary single licence since November 2024 — free under $10M
  revenue, per-CPU above it. YugabyteDB: core is Apache-2.0.
- **Use when** there are hard requirements for multi-region writes, for surviving region loss
  without manual failover, or for horizontal write scaling beyond one primary — and the team can
  afford the operational and consistency-model learning curve.
- **Pros** consensus replication gives real automatic failover and no single-primary write
  bottleneck; online rolling upgrades and rebalancing are native; and Postgres-compatible wire
  protocols lower the porting cost.
- **Cons** a latency floor, because every write pays consensus round-trips, making single-region
  OLTP strictly slower than Postgres; an operational surface — multi-node planning, clock skew —
  far above one Postgres primary; and CockroachDB licensing is now proprietary, so procurement must
  model per-CPU cost and the Apache-era assumption is dead.
- **Typical mistakes** adopting it for a small single-region app "for future scale", running a
  3+ node distributed system to serve load one Postgres box handles; assuming CockroachDB is still
  open source in a 2026 procurement review; not benchmarking write latency against plain Postgres
  before committing.

## ClickHouse (OLAP, secondary store)

- **License** Apache-2.0 for the server; ClickHouse Cloud is commercial.
- **Use when** columnar analytics is the requirement — event streams, logs, metrics, product
  analytics at billions of rows — always alongside an OLTP primary, fed by CDC or batch.
- **Pros** orders-of-magnitude faster aggregation over wide event tables than any row store; and
  Apache-2.0 with a healthy self-host community, where compression makes long retention
  economically sane.
- **Cons** it is not an OLTP database — mutations are asynchronous rewrites and there are no real
  transactions; and self-hosted cluster ops (keeper, replication, parts management) is a specialist
  job.
- **Typical mistakes** using it as the primary store because analytics queries were slow, when it
  cannot serve point-lookup OLTP; frequent `UPDATE`/`DELETE` workloads on a MergeTree table;
  hand-rolling dual writes instead of designing the CDC pipeline. `data.md` owns the sync path that
  feeds it.

## Cloud-managed flavour (RDS/Aurora, Azure SQL or Flexible Server, Cloud SQL class)

- **License** the underlying engine's licence plus provider terms. Aurora and Hyperscale are
  proprietary forks — engine-compatible, not the engine.
- **Use when** ops capacity is none or limited, availability must be high without a DBA on call, or
  simply as the default deployment mode for most teams: "managed Postgres" is a complete answer.
- **Pros** automated backups, PITR, patching, multi-AZ failover and monitoring bought with a
  checkbox; the worst-case scenarios — a failed failover, lost WAL, a botched upgrade — become the
  provider's problem; and compliance artefacts such as encryption at rest and certifications come
  with the platform.
- **Cons** two to five times the raw compute cost of self-hosting, with IOPS and cross-AZ bills
  that surprise people; a lock-in gradient, where RDS Postgres is portable but Aurora-specific
  features and IAM auth are not, and egress fees tax the exit; and you inherit the provider's
  schedule — forced maintenance windows, version deprecations, CA rotations, with the rds-ca-2019
  expiry breaking clients whose trust stores were never updated (`database-tls-operations.md`).
- **Typical mistakes** comparing only instance price against self-hosting while ignoring the DBA
  time it replaces or the outage it prevents; never testing failover and PITR restore because "the
  cloud handles it"; ignoring provider CA-rotation notices until connections fail; building on
  Aurora-only features while telling yourself you are on vanilla Postgres.

## Product picker

| Driver / workload | Product | Why |
|---|---|---|
| General OLTP, no special constraints | PostgreSQL (managed if ops is thin) | best licence/ecosystem/capability balance; every path stays open |
| Team fluent in MySQL or SQL Server | what they run | operational competence beats engine deltas |
| Single host, embedded, internal tool | SQLite | zero-ops file database; WAL mode carries real read traffic |
| .NET enterprise with EA licensing and DBAs | SQL Server | built-in Always On HA — if the per-core invoice is already sunk |
| Genuinely document-shaped, `jsonb` ruled out | MongoDB (Atlas or replica set) | best document ergonomics and built-in failover; accept SSPL |
| Ephemeral hot data, queues, sessions | Valkey (BSD) or Redis (AGPLv3+) | speed and data structures; never the system of record |
| Multi-region writes, survive region loss | CockroachDB / YugabyteDB | consensus replication; pay the latency, ops and licence cost |
| Billions of events, aggregation-heavy | ClickHouse beside the OLTP store | columnar OLAP; feed via CDC, never primary |
| Ops none or limited, availability high | managed flavour of the chosen engine | failover, backups and patching bought with a checkbox |

## HA and failover per product

| Product | Built-in replication | Automatic failover needs | Managed option |
|---|---|---|---|
| PostgreSQL | streaming + logical replication | not built in — Patroni/repmgr plus a consensus store, or CloudNativePG on Kubernetes | RDS/Aurora, Azure Flexible Server, Cloud SQL/AlloyDB |
| MySQL/MariaDB | async/semi-sync GTID; Group Replication | Orchestrator, or InnoDB Cluster plus Router; Galera for MariaDB | RDS/Aurora MySQL, Azure MySQL, Cloud SQL |
| SQL Server | Always On AGs (Enterprise; basic AG in Standard) | built in via AG plus quorum — a genuine advantage | Azure SQL Database/MI, RDS for SQL Server |
| SQLite | none native; Litestream streams to object storage | n/a — restore-based recovery, not failover | Turso/LiteFS-class hosting (niche) |
| MongoDB | replica sets with elections | built in — no extra tooling | Atlas; DocumentDB and Cosmos are API imitations, not MongoDB |
| Redis/Valkey | async replica; Sentinel or Cluster | Sentinel (quorum) or Cluster mode — built in but must be deployed | ElastiCache, Azure Cache, Memorystore |
| CockroachDB/Yugabyte | Raft consensus per range, synchronous | built in — the whole point; needs 3+ nodes and clock discipline | CockroachDB Cloud, YugabyteDB Aeon |
| ClickHouse | ReplicatedMergeTree via Keeper | built in for data; ops still specialist | ClickHouse Cloud, Altinity |

## What holds whatever you pick

- The default is PostgreSQL — or the managed flavour of whatever the team already operates well.
- The database is the hardest component to swap; optimise for the exit you will never take anyway.
- SQL Server's engine is excellent; its per-core invoice is the architecture decision.
- MongoDB is SSPL and CockroachDB has been proprietary since November 2024 — check the licence
  year, not your memory.
- Redis 8 is AGPLv3 again and Valkey is BSD-3; the fork settled the saga in the user's favour
  either way.
- Vanilla Postgres has replication, not failover — Patroni or a managed service supplies the
  failover.
- SQLite on more than one machine is a bug, not an architecture.
- Distributed SQL for a single-region small app is paying consensus latency for a problem you do
  not have.
- A managed database's price includes the outages you no longer have; compare against that, not
  against the VM bill.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend PostgreSQL in its cloud-managed flavour:
no licence risk, a symmetric exit on every cloud, and failover, backups and patching bought rather
than built. If the team has no appetite for running replication and backups, that is the whole
answer — "managed Postgres", not "which database". Name the trigger that would change it — a
signed multi-region survival requirement, an aggregation workload no index reaches, an existing
SQL Server EA, a genuinely document-shaped domain that `jsonb` was measured against and lost — as a
row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: the engine, self-hosted
   versus managed, and which HA mechanism the choice implies.
2. State the recurring cost of each — per-core licences, managed premiums, IOPS and cross-AZ
   traffic, the DBA hours self-hosting assumes — and what moving off it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md` (the store and its writing owner)
   and `06-deployment.md`.
4. A licence that fails the procurement policy, an HA claim with no failover mechanism behind it,
   and a self-hosted primary with no named ops owner are rows in `07-risks.md`. Anything the human
   leaves open is a `TODO(question)` per `templates.md`.
