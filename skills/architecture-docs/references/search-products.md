---
written_against: "web research 2026-08 (Elastic licensing FAQ, OpenSearch Foundation, Meilisearch/Typesense comparisons)"
---

`written_against` names the licence and governance state this rubric was checked against — Elastic's
triple licence, the OpenSearch Software Foundation, and where Meilisearch and Typesense sit. A
vendor page that contradicts it means this file is stale and needs re-research, not that the
solution drifted.

# Search products — which engine, and how the index stays in sync

`data.md` decides whether a dedicated search index is warranted at all, and its rule holds: the
driver is a query shape the primary store cannot serve — relevance ranking, facet counts, typo
tolerance — never "we have a search box". Load this file after that answer has landed on "something
beyond database full-text": which product fits the team's ops capacity, licence constraints and
scale, and how the index stays in sync with the primary DB. `licensing.md` owns the licence-family
question once a copyleft or source-available engine is on the table.

Outputs land in `03-containers.md` (the index as a unit, with its writing owner and sync source),
in `04-quality-scenarios.md` (the staleness window as a number), in `06-deployment.md` (the cluster
or binary and its operator), and in an ADR per `templates.md`.

Postgres FTS — `tsvector` plus GIN — with `pg_trgm` for fuzzy matching covers more products than
teams admit: up to low millions of rows with simple relevance needs, zero new infrastructure, and
transactional index consistency for free. Beyond that the field splits by ops weight.

Elasticsearch is the JVM heavyweight: unmatched aggregations, hybrid vector-plus-lexical search,
and scale past hundreds of millions of documents, but it demands cluster management — shards, heap,
rebalancing — and a dedicated pair of hands. Its licensing settled in August 2024 when Elastic added
AGPLv3 alongside ELv2 and SSPL, making it open source again; AWS's 2021 fork OpenSearch
(Apache-2.0, governed since September 2024 by the OpenSearch Software Foundation under the Linux
Foundation) remains the default on AWS and the safe-licence choice, with the same operational
weight.

Meilisearch (MIT, Rust) and Typesense (GPLv3, C++) are the ops-light single-binary camp: sub-50 ms
queries, typo tolerance by default, an afternoon to integrate. Meilisearch is single-node with HA
only via its cloud offering; Typesense clusters but keeps its index in RAM. Both hit walls at
tens-of-GB indexes and heavy aggregation needs.

Algolia and Elastic Cloud trade money for ops. Algolia is the fastest path to excellent
instant-search UX, with per-record and per-search pricing that stings at scale and real lock-in;
Elastic Cloud removes cluster babysitting but not data-modelling complexity.

Whatever the engine, sync from the primary DB is the actual long-term cost. Dual-writes from
application code silently diverge on partial failure. Prefer CDC (Debezium, WAL) or a transactional
outbox feeding the indexer, with a periodic full reindex as the self-healing backstop.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Ops capacity is none but relevance needs are real | Meilisearch or Typesense as a single binary, or managed (Algolia, Elastic Cloud) — never self-run a JVM cluster |
| Dataset under a few million rows, search is a feature not the product | stay on Postgres FTS + `pg_trgm`; revisit when relevance complaints or query latency force the move |
| Log analytics, heavy aggregations, or 100M+ documents | Elasticsearch or OpenSearch — the lightweight engines are not built for this |
| Corporate allergy to copyleft | Typesense (GPLv3) and Elastic SSPL need legal review; OpenSearch (Apache-2.0) and Meilisearch (MIT) do not |
| The index is drifting from the source of truth | replace dual-writes with CDC or outbox-driven indexing plus a scheduled full reindex |
| The index must fit budget, not RAM | Typesense holds the index in memory — price the RAM at your document count before committing |

## Postgres FTS + pg_trgm

- **License** PostgreSQL License.
- **Use when** you already run Postgres, the corpus is small-to-medium, and "good enough" relevance
  with zero new services wins.
- **Pros** no new infrastructure and no sync pipeline, because the index updates in the same
  transaction; a GIN-indexed `tsvector` plus trigram fuzzy matching covers most CRUD-app search; free.
- **Cons** relevance tuning is crude next to BM25-class engines; no typo tolerance or faceting out of
  the box; heavy search load competes with OLTP on the same box.
- **Typical mistakes** standing up an Elasticsearch cluster for 200k rows that a `tsvector` column
  handles.

## Meilisearch

- **License** MIT.
- **Use when** app-facing instant search, an ops-light team, and a corpus that fits one node —
  e-commerce and docs search are the sweet spot.
- **Pros** a single Rust binary with sensible defaults, typo tolerance and facets out of the box; MIT,
  so no licence conversation is needed; integrated in days with near-zero tuning.
- **Cons** the OSS build is single-node, so HA and replication mean Meilisearch Cloud; not for log
  analytics or heavy aggregations; corpora of 100 GB and up are outside the design centre.
- **Typical mistakes** expecting Elasticsearch-style aggregation pipelines from it.

## Typesense

- **License** GPL-3.0.
- **Use when** lowest-latency instant search, the dataset fits in RAM, and you may need the OSS Raft
  clustering for HA that Meilisearch lacks.
- **Pros** a single C++ binary, sub-50 ms, typo tolerance built in; OSS high-availability clustering;
  predictable flat pricing on Typesense Cloud.
- **Cons** the entire index lives in RAM, so cost scales with corpus size; GPLv3 needs a pass from
  legal in some shops; weak for analytics-style queries.
- **Typical mistakes** committing before pricing the RAM footprint at ten times the current document
  count.

## OpenSearch (self-hosted or AWS managed)

- **License** Apache-2.0.
- **Use when** you need Lucene-class power — aggregations, huge corpora, log analytics — with a clean
  licence, especially on AWS.
- **Pros** Apache-2.0 under the Linux Foundation's OpenSearch Software Foundation since 2024, so no
  licence risk; a roughly feature-parity fork of Elasticsearch 7.10 with its own vector and hybrid
  search since; the AWS-managed flavour removes some cluster toil.
- **Cons** the same JVM-cluster ops weight as Elasticsearch — shards, heap, rebalancing — and a
  growing divergence from Elastic, so client libraries and features are no longer interchangeable.
- **Typical mistakes** assuming Elasticsearch tutorials and plugins still apply one-to-one.

## Elasticsearch / Elastic Cloud

- **License** AGPLv3 or ELv2/SSPL — triple-licensed since August 2024.
- **Use when** there is dedicated search or ops capacity and the requirements are hard: massive
  scale, complex aggregations, mature vector-plus-lexical hybrid, the Kibana ecosystem.
- **Pros** the deepest feature set and ecosystem of any engine here; the AGPLv3 option restored
  open-source status in 2024; Elastic Cloud offloads cluster management.
- **Cons** the heaviest ops burden when self-hosted, so plan for a person who owns the cluster; the
  ELv2/SSPL/AGPL matrix still requires legal attention for redistribution and SaaS cases; it is easy
  to overbuy, since most product search needs none of this.
- **Typical mistakes** running a self-hosted cluster with no ops capacity and discovering shard
  rebalancing during an incident.

## Algolia

- **License** proprietary SaaS.
- **Use when** instant-search UX is a revenue lever and you will pay to not build or operate anything.
- **Pros** best-in-class latency and frontend libraries (InstantSearch); zero ops on a global edge
  network; the fastest time to a polished search experience.
- **Cons** per-record plus per-search pricing grows painfully with catalogue and traffic; deep
  lock-in, since proprietary ranking config and APIs do not port; index size limits per record.
- **Typical mistakes** indexing full documents instead of search-relevant fields and tripling the bill.

## Search products at a glance (2026)

| Product | License | Ops weight | Sweet spot |
|---|---|---|---|
| Postgres FTS + `pg_trgm` | PostgreSQL License | none — already running | small/medium corpora, search as a checkbox feature |
| Meilisearch | MIT | light — single Rust binary, single-node OSS | instant search for apps/docs/e-commerce, ops-light teams |
| Typesense | GPL-3.0 | light — single C++ binary, OSS Raft clustering, index in RAM | lowest-latency instant search on RAM-sized datasets |
| OpenSearch | Apache-2.0 (Linux Foundation) | heavy — JVM cluster: shards, heap, rebalancing | big corpora and log analytics with a clean licence, AWS shops |
| Elasticsearch | AGPLv3 / ELv2 / SSPL | heavy — JVM cluster plus deepest tuning surface | massive scale, complex aggregations, dedicated search team |
| Algolia / Elastic Cloud | proprietary SaaS / Elastic terms | none — managed, pay instead | buy-not-build: polished UX fast (Algolia) or managed Lucene power (Elastic Cloud) |

## What holds whatever you pick

- Exhaust Postgres FTS and `pg_trgm` before adding a search service: a new datastore is a new sync
  problem.
- Match the engine to ops capacity. JVM clusters — Elastic, OpenSearch — require dedicated ownership;
  single-binary engines do not.
- Sync via CDC (Debezium, WAL) or a transactional outbox, never bare dual-writes from app code.
- Schedule a periodic full reindex as the drift backstop, whatever the sync mechanism.
- Check the licence against your distribution model: MIT and Apache are clean, GPLv3 and SSPL need
  legal review.
- Treat search results as eventually consistent in the UI; read-your-writes goes to the primary DB.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend staying on Postgres FTS with `pg_trgm`,
indexed and measured, and no separate search service at all. Name the trigger that would change it —
a relevance or typo-tolerance requirement the SQL query cannot express, facet counts that get
expensive, a corpus past a few million rows, or search load contending with OLTP — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which engine, what its ops
   weight assumes about the team, and which sync mechanism feeds it.
2. State the recurring cost of each — per-record and per-search pricing, the RAM the index occupies,
   the person who owns the cluster — and what reversing it later costs once the query layer is
   written against it.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. The staleness a user may observe becomes a `QS-` row with a number and a unit. A dual-write sync
   path, a missing full-reindex schedule, and a copyleft licence with no legal sign-off are rows in
   `07-risks.md`. Anything the human leaves open is a `TODO(question)` per `templates.md`.
