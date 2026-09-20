# Data beyond the primary store — cache, search, analytics, read models

The primary store is chosen with the stack (`stacks/dotnet.md` for EF Core vs Dapper) and its
backup, retention and encryption are `operations.md`'s. This file settles what comes *after* it:
every additional store holding a copy of data the primary already owns — which stores exist, who
writes them, how they stay current. The model-level read/write split is `approaches.md`'s CQRS/ES
entry; this file is its infrastructure counterpart.

## The frame

A second store buys exactly one capability and charges three costs, every time:

1. **A consistency model to explain.** Staleness stops being an implementation detail the moment a
   user can see it. The window is a number in `04-quality-scenarios.md`, not a feeling.
2. **An ops surface.** Its own backup or a named rebuild path, its own monitoring, its own upgrade
   and its own failure mode — all of `operations.md` applies to it again.
3. **A synchronisation path that fails independently.** It can lag, drop, reorder or stop, and it
   does so quietly unless someone measured what "in sync" means.

The driver question for every option below: **which recorded quality scenario or constraint does
the primary store fail?** No recorded driver, no second store.

## Choosing by driver

| Recorded driver | Candidates to put on the table |
|---|---|
| A read path misses its `QS-` latency measure and the query is already indexed | HTTP/CDN cache, application cache, materialized view |
| Expensive per-user or per-tenant values, read far more than written, several replicas | shared cache (Redis/Valkey class) |
| Relevance ranking, facet counts or typo tolerance the SQL query cannot express | database full-text first; dedicated index when the shape needs it |
| Report queries contend with the write path for connections, locks and memory | read replica |
| Aggregations over history the row-store cannot serve at the required latency | OLAP store (ClickHouse/DuckDB class) |
| Questions spanning several source systems, or retention far beyond the OLTP's | warehouse |
| A read shape spanning aggregates that must survive the write schema changing | maintained projection |
| Nothing recorded | no second store |

## Caching

Three layers, cheapest first — most systems need only the first — then the invalidation decision
that makes whichever you took safe.

### HTTP and CDN caching

- **Use when** a response is shared between users or repeated by one user, and it can carry a
  validator (`ETag` by default, `Last-Modified` only where the timestamp is trustworthy).
- **Pros** nothing to run and nothing to synchronise; a hit never reaches the application;
  `stale-while-revalidate` keeps tail latency flat across a refresh; CDN cache tags (surrogate keys)
  purge a whole collection in one call, so publish events can drive invalidation.
- **Cons** the copies live in caches you do not control — a browser honours expiry, never a purge,
  so `max-age` on a shared response is a commitment for its full length; `Vary` decides the cache
  key, and getting it wrong serves one user's response to another.
- **Typical mistakes** no `Cache-Control` at all, so every layer applies its own heuristic; a
  header-versioned API without `Vary` (`communication.md`); authenticated responses marked
  `public`; a purge path that exists only as a console click.

### Application-level cache: in-process or shared

| | In-process | Shared (Redis / Valkey class) |
|---|---|---|
| Use when | values fit a bounded memory budget and each replica may legitimately hold a copy of a different age | replicas must observe the same value, the entry must survive a deploy, or a recompute is expensive enough that a per-replica miss storm matters |
| Pros | no hop, no serialisation, no extra container | one copy with one age; coordination primitives for single-flight recompute; usually already earning its keep for rate limits or sessions |
| Cons | N replicas mean N copies with N ages, so the staleness window follows the deployment topology; cold after every deploy; memory competes with the workload's | a hop on the hot path and a failure mode to decide — fail open to the primary or fail the request; another store to size, monitor and upgrade; eviction and persistence are choices, not defaults |
| Typical mistakes | an unbounded dictionary called a cache; tenant-scoped data in a process shared by tenants; assuming an invalidation that reached one replica reached all | treating it as durable when it runs without persistence; no eviction policy, so it fills and refuses writes; running it to hide a query that needed an index |

The Redis/Valkey licence split is a row in `licensing.md`; if the same instance also carries
streams, `message-bus.md` owns that decision.

### Database-side (materialized views)

- **Use when** the expensive part is an aggregation over data the primary already holds and minutes
  of staleness are acceptable. No ops surface, no sync path: the data never leaves its owner.
- **Pros** one store, one backup, one consistency story; the refresh is a statement, testable in
  the same database as everything else.
- **Cons** PostgreSQL's `REFRESH MATERIALIZED VIEW` recomputes the whole view — cost follows the
  source table, not the change; `CONCURRENTLY` avoids the read lock, needs a unique index and still
  recomputes; incremental extensions (`pg_ivm` class) restrict the SQL and are absent on most
  managed services. There is no query-result cache behind it: MySQL removed one in 8.0 and
  PostgreSQL never had one — "the database caches it" means the buffer pool.
- **Typical mistakes** refreshing so often that the refresh is the load; a refresh with no owner and
  no alert, so failure looks like data that is merely old; a view standing in for a missing index.

### Invalidation

The decision that determines whether a cache helps or lies.

| Strategy | Buys | Costs |
|---|---|---|
| TTL only | one setting; a staleness window you can state; self-healing after any bug | stale for the whole window; shortening it trades staleness back for load |
| Event-driven | freshness within the write path's own latency | a delivery path that can drop or reorder — pair it with a TTL so a missed event still heals; the invalidation path needs its own test |
| Versioned keys | invalidation is one counter bump: no delete storm, no partial purge across layers | superseded entries occupy memory until eviction; the version must appear in every key |

- **The honest rule**: staleness a user may observe is a `QS-` row with a number and a unit ("the
  catalogue page may be up to 60 s behind a price change"), agreed with the human before it ships.
- **Typical mistakes** the cache as source of truth — a value written to it and only later, or never,
  to the store; a hot key expiring into a stampede with no single-flight, jitter or early refresh; a
  cache hiding a missing index; invalidation paths no test exercises, so they are discovered broken
  in production; a deletion that clears the row and leaves the copy.

## Search

The driver is a query shape the primary store cannot serve — relevance ranking, facet counts, typo
tolerance, one query across several entities. "We have a search box" is not a driver: a filtered
`LIKE` over an indexed column is a query.

### Database full-text (PostgreSQL FTS, `pg_trgm`)

- **Use when** the searchable rows live in one database and results must obey the same filters,
  joins and permissions as everything else, with no visible lag after a write.
- **Pros** the index updates inside the writing transaction, so drift is impossible; ranking and SQL
  filtering compose in one query; no new container, backup or sync path; `pg_trgm` covers fuzzy
  matching on names and identifiers.
- **Cons** relevance control stops at weights and ranking functions; facet counts over large sets
  get expensive; it scales with the one primary; analysis is limited to bundled dictionaries.
- **Typical mistakes** computing the `tsvector` per query instead of storing a generated column
  with a GIN index; reaching for an engine before the FTS query has been indexed and measured.

### Dedicated index, heavy tier (Elasticsearch / OpenSearch class)

- **Use when** relevance is itself the feature (synonyms, boosting, tuning), facet counts and
  aggregations over large document sets are required, or corpus and query volume exceed one node.
- **Pros** relevance and aggregation controls SQL has no equivalent for; horizontal scale; an
  explicit, versioned analysis pipeline.
- **Cons** a cluster with its own memory sizing, snapshot repository, monitoring and version-bound
  upgrade path; a derived copy that can drift; permissions re-expressed in the index or applied as a
  post-filter. The licence history of this family is a row in `licensing.md`.
- **Typical mistakes** a cluster for a corpus a single node would hold in memory; searching the index
  then loading every hit from the primary, reinstating the load; filtering by permission after paging.

### Dedicated index, light tier (Meilisearch / Typesense class)

- **Use when** instant search, prefix matching and typo tolerance over a bounded corpus is the whole
  requirement and the ops budget is one container.
- **Pros** a single binary with defaults that work without a query DSL; ops weight close to a cache.
- **Cons** a lower ceiling on aggregation and relevance tuning; clustering and HA differ per product
  and edition; moving to the heavy tier later rewrites the query layer.
- **Typical mistakes** using it for log analytics; assuming an HA story the edition does not have.

### Sync path

The index is a projection; how it is fed is a separate decision with its own failure modes.
Typical mistakes: no measured reindex-from-scratch runway, so the first full rebuild takes an
unbudgeted number of hours; fields that exist only in the index, making it an unacknowledged source
of truth; rebuilding in place instead of into a new index behind an alias.

| Path | Use when | Costs |
|---|---|---|
| Dual write from the application | the corpus is small and a rebuild is cheap | not transactional — any failure between the two writes is permanent drift, so it needs a reconciliation job to be honest |
| Outbox drained by a worker | the write and its event must commit together over ordinary transport | an outbox table, a worker to drain it, per-key ordering (`communication.md`, `message-bus.md`) |
| CDC (Debezium class) | the writing application cannot be changed, or several consumers want one stream | a replication slot that fills the primary's disk if nobody drains it, a connector to operate and monitor, and a stated answer for source schema changes |

## Analytics and reporting

The floor is a read replica and better SQL. Recommend an engine only once that floor is measured
and found insufficient. CDC (Debezium class) is the modern backbone feeding whatever comes next.

### Read replica

- **Use when** report queries contend with the write path for connections, locks or memory, and the
  report shapes are ones the OLTP schema can still answer.
- **Pros** no new engine, schema, dialect or backup story; replication lag is the one new number.
- **Cons** lag is visible in reports; long analytical queries conflict with replay, so they are
  cancelled or they delay replication; a wide aggregation is still slow on a row store.
- **Typical mistakes** a BI tool pointed at the production primary "for now"; a replica with no lag
  alert; expecting a replica to reduce write load.

### OLAP store (ClickHouse / DuckDB class)

- **Use when** aggregations over tens of millions of rows or over long history must return in
  seconds and no indexing of the row store gets there. DuckDB class suits single-node analysis over
  files or an extract; ClickHouse class suits continuous ingest with real query concurrency.
- **Pros** columnar storage changes the cost class of a wide scan; a schema shaped for reports
  without deforming the OLTP one.
- **Cons** a second engine with a full ops surface plus the sync path feeding it; updates and
  deletes are awkward, so an erasure obligation needs an explicit answer; it cannot join to OLTP
  tables — everything a report touches must be loaded first.
- **Typical mistakes** adopting it before a replica and an index were tried; a nightly load
  described to users as real-time; no owner for the pipeline, so report freshness is a guess.

### Warehouse or lakehouse

- **Use when** questions span several source systems, analysts outside the product team own the
  modelling, or data must be retained well past the OLTP's retention.
- **Pros** one place for cross-system questions, with its own modelling layer and access control.
- **Cons** a data-platform discipline — ingestion, modelling, tests, lineage, cost control — rarely
  a product team's side job; another copy of personal data with its own obligations (`operations.md`).
- **Typical mistakes** a warehouse for one product's own reports; the nightly ETL nobody owns;
  analytics reading OLTP tables directly, which freezes the OLTP schema — publish a contract (a
  view, an outbox event, a CDC stream with a stated shape) and let the tables move behind it.

## Read models and projections

A materialised copy maintained outside the writing store, kept current from events or CDC. Whether
the application splits its read and write models is `approaches.md`'s CQRS entry; this is the store
that split needs when the read cannot be a query.

- **Use when** the read shape spans several aggregates or containers and must keep serving while the
  source is busy. While all the data lives in one store a SQL view or materialized view is the
  cheaper answer; a projection earns its place when the source is elsewhere, or when the read must
  survive the write schema changing underneath it.
- **Pros** the read is shaped exactly for its consumer; the source schema stays free to change; a
  bug in the read path is fixed by correcting the projector and rebuilding.
- **Cons** eventual consistency the UI has to represent; a projector is code that runs forever and
  can lag, crash or re-deliver, so handlers are idempotent; the events it consumes are a versioned
  contract (`communication.md` owns schema evolution).
- **Rebuildability is the design property.** Record what it rebuilds from, how long a rebuild takes,
  and who has done one. A projection that cannot be rebuilt is a second source of truth and needs a
  primary's backup and restore treatment (`operations.md`).
- **Typical mistakes** the API writing to the projection alongside the projector; source events
  pruned away; repairing a wrong row by hand instead of fixing the projector and replaying.

## Data ownership

- **Exactly one container writes each store.** Everything else reads it through that owner's
  contract, a replica or a projection. Two writers to one store is a **blocking** finding in the
  review rubric (`architect-review/references/checks.md`): coupling with no contract and no owner.
- Every store in `03-containers.md` names its writing owner; a derived store also names its source
  and sync path. A derived store with no named source is an unacknowledged primary.
- A cache, index or projection holding personal data inherits the retention and deletion obligations
  of the rows it copied (`operations.md`).
- On one Compose host each added store is another container inside the same failure domain,
  competing for the same memory — `containers.md` is the measuring stick for whether it fits.

## When the evidence is thin

Recommend no second store: one primary with the right indexes, HTTP caching with a validator on the
shared responses, a read replica once the report load is real. Record the trigger that would change
it — a `QS-` measure missed after indexing, a relevance requirement — in `07-risks.md`.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected quality scenarios and
   constraints by id, the staleness introduced, the recurring operational cost, and removal cost.
2. Give one recommendation with its driver. The human decides.
3. Write the accepted store as a container row in `03-containers.md` with its writing owner and sync
   source; its staleness as a `QS-` row with a number; its backup or rebuild path and monitoring per
   `operations.md`; the rejected option and why it lost in an ADR.
4. Anything the human leaves open becomes a `TODO(question)` line in the affected document.

**Done when** every store in `03-containers.md` beyond the primary has a named writing owner, a
named sync path, and either a `QS-` staleness row or a recorded not-applicable; every cache has a
written invalidation strategy; and no store is written by two containers.
