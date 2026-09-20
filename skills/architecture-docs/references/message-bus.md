---
written_against:
  date: 2026-08
  licenses_verified_against_repo: >
    NATS server, Kafka and Pulsar Apache-2.0; RabbitMQ MPL-2.0 (a few OCF files ASL-2.0); Valkey
    BSD-3-Clause; Redis 8 tri-licensed RSALv2/SSPLv1/AGPLv3 (7.2 and earlier stay BSD-3); Redpanda
    BSL-1.1, no "Streaming or Queuing Service", converting to Apache-2.0 after four years; EMQX
    BSL-1.1 since 5.9, one production node granted, same conversion; Mosquitto EPL-2.0 or EDL-1.0;
    pgmq PostgreSQL License; River MPL-2.0; Solid Queue MIT.
  landscape: >
    volatile part: Kafka is KRaft-only since 4.0 (2025) and share groups (KIP-932) reached GA with
    4.2 (Feb 2026); RabbitMQ 4.x removed classic queue mirroring and 4.2 makes Khepri the default
    metadata store; the NATS/Synadia CNCF dispute closed in May 2025 with the core staying
    Apache-2.0 under CNCF stewardship; Valkey (Linux Foundation, BSD) is the default in the major
    managed cache services and Redis 8 added AGPLv3 as its open option.
  note: >
    audit re-checks this stamp against the products and versions actually declared in the repo — a
    mismatch means this file is stale and needs re-research, not that the repo did something wrong.
---

# Message bus and broker products — decision rubric

Load this when the class decision in `communication.md` has landed on a broker and the question is
now *which product, and what does running it actually cost*. `communication.md` owns the class
question and the semantics dimensions — delivery guarantees, ordering, dead-lettering, backpressure;
`approaches.md` owns the event-driven axis itself. Monitoring and backup mechanics belong to
`operations.md`, license family meaning to `licensing.md`. Point, do not restate.

Outputs: the broker is a container in `03-containers.md` with one edge per topic or queue contract;
an ADR names the rejected products and why each lost; the accepted operational weight is a row in
`07-risks.md` with an owner; throughput, lag and retention numbers are rows in
`04-quality-scenarios.md`. Docker Compose on one or a few VMs is the assumed platform, per
`containers.md` — every product is judged at that scale first, and a fleet-scale recommendation
needs a written driver.

## Choosing by driver

| Driver in the recorded scenarios / constraints | Candidates to put on the table |
|---|---|
| A database is already there and enqueue must commit with the business data | PostgreSQL as the queue |
| Per-message routing, priorities, TTL, dead-letter out of the box | RabbitMQ |
| Consumers must re-read past messages; several independent consumer groups on one stream | Kafka, Redpanda, Pulsar, RabbitMQ streams |
| Ops budget is one small container; subjects, request/reply and queue groups in one product | NATS + JetStream |
| Redis or Valkey already deployed and a sub-second loss window on failover is acceptable | Redis/Valkey Streams |
| No ops capacity, spiky load, the app already runs in one cloud | cloud-managed queue |
| Multi-tenancy or geo-replication is a written requirement and someone will operate it | Pulsar |
| Thousands of intermittently connected devices on unreliable links | MQTT broker, bridged inward |
| One process, modules that ship together | in-process dispatch — no broker |

When nothing recorded distinguishes the candidates, recommend the zero-new-component one: the queue
in the database that already exists, consumers idempotent from the first line. Record the trigger
that would change it — a second consumer group, a replay requirement, a rate above one instance — as
a risk in `07-risks.md`.

## PostgreSQL as the queue

`SELECT ... FOR UPDATE SKIP LOCKED` over a jobs table, packaged as pgmq, River, Solid Queue, pg-boss
and similar. The honest floor whenever a database is already in the stack.

- **License** PostgreSQL License for the engine and pgmq, River MPL-2.0, Solid Queue MIT — free
  commercial self-host, no copyleft on your code.
- **Semantics** at-least-once with a visibility timeout per claimed row; ordering only as far as you
  enforce it; dead-lettering is a column and a table you write; no native fan-out.
- **HA and ops at compose scale** whatever the database already has; zero new nodes, nothing new to
  deploy, monitor or back up. The one new duty is bloat.
- **Use when** the rate is in the low thousands per second or below, consumers are a known small set,
  and the enqueue belongs in the same transaction as the business write.
- **Pros** transactional enqueue removes the dual-write problem outright — the outbox pattern's
  payoff without an outbox or a broker; queue state is queryable in dashboards that already exist;
  one backup covers data and work.
- **Cons** dequeue is polling, so latency is a poll interval; a long-running transaction or an idle
  replication slot pins the xmin horizon, autovacuum stops reclaiming, and the table bloats until
  throughput decays — the characteristic failure, and it is silent; no durable pub/sub fan-out, no
  retention log to replay from, and queue load competes with application load.
- **Typical mistakes** no index matching the claim predicate, so every dequeue scans; whole entities
  as payloads until the table is the largest thing in the database; treating `LISTEN/NOTIFY` as
  delivery when it is fire-and-forget and lost on disconnect; no alert on dead-tuple count or
  oldest-pending age; keeping it after a real fan-out requirement arrived.

## Redis Streams / Valkey

- **License** Redis 8 is tri-licensed RSALv2 / SSPLv1 / AGPLv3 — free self-host exists, under network
  copyleft; 7.2 and earlier remain BSD-3. Valkey is BSD-3-Clause under the Linux Foundation, free
  with no copyleft. The history: Redis left BSD in 2024 for RSALv2/SSPL, the community forked Valkey,
  Redis added AGPLv3 back in 8 (2025), and Valkey is now the default in the major managed cache
  services. The lesson: a single-vendor project's license is a dependency like any other, and
  foundation governance is what makes a fork a real fallback.
- **Semantics** an append-only log per key with consumer groups, per-message ack, redelivery via
  `XAUTOCLAIM`, retention by `MAXLEN`/`MINID`. At-least-once, ordered per stream, replayable within
  retention; dead-lettering is the delivery counter plus a policy you write.
- **HA and ops at compose scale** one small container, one config file, a memory budget. Replication
  is asynchronous, so an acknowledged write can be lost on failover; Sentinel needs 3 nodes, Cluster
  3 primaries plus 3 replicas.
- **Use when** it is already deployed, throughput is high, and the work is recomputable or tolerant
  of a sub-second loss window — notifications, cache invalidation, fan-out to a few consumers.
- **Pros** no new component when the cache is already there; very high throughput per core; consumer
  groups and replay for a fraction of Kafka's footprint.
- **Cons** durability is memory-first (`appendfsync everysec` accepts up to a second of loss) and the
  stream lives in RAM, so retention is a memory budget; no transactional link to the database.
- **Typical mistakes** `XADD` with no `MAXLEN`, so the stream grows until the process is OOM-killed;
  one instance serving cache, sessions and the queue, so one restart loses all three; treating
  replica promotion as lossless; using plain pub/sub for messages that must arrive.

## RabbitMQ

- **License** MPL-2.0 for the server and tier-1 plugins. Weak copyleft: running it imposes nothing on
  your code. Free commercial self-host.
- **Semantics** AMQP 0-9-1, and routing is the strength — direct, topic, headers and fanout
  exchanges, per-message TTL and priority, publisher confirms, native dead-letter exchanges.
  At-least-once, ordered per queue with a single consumer.
- **Queue types in 4.x** classic (non-replicated; mirroring was removed in 4.0), quorum
  (Raft-replicated, the data-safety default, 3 nodes), streams (an append-only replayable log, when
  replay is wanted without a second product). 4.2 makes Khepri, the Raft metadata store, the default
  for new deployments; existing clusters keep their store across an upgrade, so switching is a
  planned migration, not a side effect.
- **HA and ops at compose scale** 3 nodes for quorum queues, though one node with classic queues, a
  durable disk and a rehearsed restore is honest when the availability scenario allows it. One
  container, one Erlang runtime, a management UI on day one. Memory and disk alarms block publishers
  broker-wide when they trip — correct, and a first-time surprise.
- **Use when** routing rules carry real meaning, competing consumers plus DLQ is the shape, and
  throughput is thousands to low tens of thousands per second.
- **Pros** the richest per-message semantics of the self-hosted options, working DLQ and retry
  topology without custom code, mature clients everywhere, and a usable UI from the first hour.
- **Cons** replay exists only in the streams type — on classic and quorum queues an acked message is
  gone; quorum queues hold their index in memory, so depth has a memory cost; the Erlang debugging
  vocabulary is unfamiliar to most teams; clustering across a WAN is unsupported.
- **Typical mistakes** copying a pre-4.0 design that mirrors classic queues, a feature that no longer
  exists; queues with no max-length and no DLQ, so one dead consumer fills the disk and then blocks
  every publisher on the broker; a queue per consumer instance until there are tens of thousands;
  three nodes on one Docker host described as HA.

## Apache Kafka

- **License** Apache-2.0, free commercial self-host. Caveat: vendor distributions and ecosystem
  components carry their own terms — check any "Kafka" image or connector that is not Apache's.
- **Semantics** a partitioned, replicated, retention-based log; consumer groups track offsets, so
  replay is the differentiator — a new consumer reads history, a fixed one reprocesses it.
  At-least-once by default; exactly-once *within Kafka* via the idempotent producer and transactions,
  which does not extend to your database. Ordering is per partition only, and there is no DLQ
  concept — you build one from a topic and the consumer's error path.
- **Version reality** ZooKeeper is gone: 4.0 (2025) is KRaft-only and a 3.x cluster must migrate
  before it can upgrade. Share groups (KIP-932) reached GA with 4.2 (Feb 2026), so "Kafka cannot do
  queues" is stale — but that is a young subsystem, not the mature path.
- **HA and ops at compose scale** replication factor 3 with `min.insync.replicas=2`, so 3 brokers
  (controllers may be co-located at small scale); one broker runs and guarantees nothing. The
  heaviest mainstream option to operate: JVM heap plus page cache, per-partition file handles,
  retention sizing, rebalance behaviour, consumer-lag monitoring as a standing duty, and a schema
  registry once a second team writes to a topic. A one-broker compose Kafka is a development
  fixture, not a deployment.
- **Use when** replay is a stated requirement, several independent consumer groups read the same
  stream, sustained throughput exceeds one node, or the log is the integration contract.
- **Pros** retention decouples consumers from producers in time, not just in space; consumers are
  added and reset without touching the producer; the ecosystem (connectors, stream processing,
  schema registries) is the largest of any option here.
- **Cons** the minimum footprint dominates a small stack's whole ops budget; partition count is both
  the ordering and the parallelism unit, decided early and awkward to change; no per-message routing,
  so filtering is every consumer's job.
- **Typical mistakes** adopted for a job queue at ten messages a second, where the footprint buys
  nothing a database table did not; partition count chosen for a throughput nobody measured; lag
  unmonitored until a consumer has been down a day; infinite retention on a finite disk.
- **Redpanda** is the Kafka-API-compatible lighter option: one C++ binary, no JVM, no ZooKeeper,
  materially cheaper at compose scale. BSL-1.1, with an Additional Use Grant forbidding use to offer
  a "Streaming or Queuing Service"; each release converts to Apache-2.0 four years on. Not open
  source today — fine for your own product, a lawyer's question if you resell messaging.

## NATS + JetStream

- **License** Apache-2.0. The 2025 scare, resolved: Synadia moved to withdraw the project from the
  CNCF and relicense the server under BUSL; it closed in May 2025 with stewardship and the trademark
  going to the CNCF and the core staying Apache-2.0.
- **Semantics** core NATS is at-most-once fire-and-forget pub/sub over hierarchical subjects with
  wildcards, plus request/reply and queue groups. JetStream adds persistent streams with durable
  consumers, acks, redelivery, retention policies (limits, interest, work-queue) and publish-id
  deduplication — fan-out and competing consumers over the same subject space.
- **HA and ops at compose scale** 3 nodes for an R3 stream (Raft, quorum 2 of 3; R5 is the ceiling),
  and the lightest credible broker to run — one small static binary, no JVM, no external metadata
  store, one config file.
- **Use when** the system needs request/reply, work queues and durable streams from one dependency,
  and the ops budget is a single container.
- **Pros** subject wildcards make routing a naming decision rather than a topology one; the same
  cluster serves RPC and messaging; latency is low and the resource floor is tiny.
- **Cons — where the simplicity trades off** Jepsen's 2025 analysis of 2.12.1 left issues open:
  corruption of block or snapshot files on a minority of nodes causing large-scale message loss and
  even stream deletion, and persistent replica divergence after one node's OS crash. The default
  fsync is lazy — writes are acknowledged long before they reach disk — so a correlated power failure
  loses data unless sync is set explicitly. A full work-queue stream rejects publishes: correct
  backpressure, and still a surprise.
- **Typical mistakes** assuming core subjects are durable when no consumer is connected; one node
  with JetStream enabled treated as durable storage; the default fsync left in place on the machine
  holding the only copy; three replicas in one failure domain; a stream with no max-age or max-bytes.

## Apache Pulsar

**License** Apache-2.0. **Semantics** queue and stream in one product — exclusive, failover, shared
and key-shared subscriptions, per-message ack, a real DLQ, retention and replay; multi-tenancy and
geo-replication are built in, and tiered storage offloads cold segments to object storage so
retention is not a disk budget. **HA and ops** 3 brokers, 3 bookies, 3 metadata nodes; compute and
storage are separate tiers, the architectural strength and exactly why it is a poor compose fit —
three tiers to size, monitor and upgrade where Kafka has one and NATS has none. **Use when**
multi-tenancy or geo-replication is written down and someone is funded to operate it; otherwise
those requirements are met more cheaply above.

## Cloud-managed (Azure Service Bus, AWS SQS/SNS, Google Pub/Sub)

- **License** proprietary services billed per operation or hour. Free self-host: no — that absence is
  the trade being made.
- **Semantics** SQS standard is at-least-once and unordered at effectively unlimited rate, SQS FIFO
  ordered and deduplicated per message group at a much lower rate; both have native DLQs driven by a
  receive count and a visibility timeout. Azure Service Bus is a full broker — sessions for ordering,
  topics with SQL filters, scheduled messages, transactions inside a namespace, a DLQ per entity.
  Google Pub/Sub is at-least-once fan-out with per-key ordering and replay by seek within retention.
- **HA** not yours: zero nodes, zero patching, zero backup — and zero access when it misbehaves.
- **Use when** the app already runs in that cloud, load is spiky, and ops capacity is the binding
  constraint. For a two- or three-person team this is usually the honest answer over a self-run
  broker, for the reasons `containers.md` gives about single-host stacks.
- **Pros** no node, no upgrade, no backup and no 3 a.m. restart; scaling and durability are the
  provider's problem; IAM, encryption and audit come from the platform already in use.
- **Cons** lock-in in the SDK, the semantics and the infrastructure code; cost follows message count,
  so a chatty design is expensive in a way a VM is not; quotas and payload ceilings (256 KB is the
  common one) shape the message; per-message features do not port between the three.
- **Compose-scale pain: local development.** Azure Service Bus has an official emulator container —
  AMQP over TCP only, no partitioned entities, and it loses data and entities on restart. Google
  Pub/Sub ships an emulator in the gcloud CLI. AWS offers no first-party SQS/SNS emulator, so local
  runs mean a third-party stand-in (LocalStack, ElasticMQ) whose fidelity is its own risk, or a real
  queue per developer. Settle this before adopting.
- **Typical mistakes** no DLQ, so a poison message redelivers forever and shows up on the bill; a
  visibility timeout shorter than the processing time, producing duplicates nobody designed for;
  FIFO chosen for safety and then hitting the per-group rate ceiling; emulator gaps discovered only
  after the test suite depends on them.

## MQTT brokers

Mosquitto (EPL-2.0 or EDL-1.0) is a tiny single-binary broker; EMQX moved to BSL-1.1 at 5.9, whose
Additional Use Grant covers a single production node — clustering needs a paid key, and each version
converts to Apache-2.0 after four years. MQTT is a device-edge protocol: QoS 0/1/2, retained
messages, last-will, tiny frames over unreliable links, thousands of intermittently connected
publishers. It is right at the sensor boundary and wrong as the application bus — no consumer groups,
no replay, no real dead-letter story. Terminate it at the edge, bridge into a product above, and
design the application flow on that.

## In-process and embedded

A modular monolith whose modules ship in one process needs no broker: an in-memory channel, a
background worker over a database table, or an in-process dispatcher gives the decoupling with none
of the operations. Reach for a broker when producer and consumer must survive each other's restarts
or scale apart — and see `approaches.md`, which notes that in-process dispatch is not an
event-driven architecture.

## The payoff table

| Product | Free self-host? | Semantics | Replay | Fan-out | HA min | Compose fit | Ops weight | Wins when |
|---|---|---|---|---|---|---|---|---|
| PostgreSQL queue | yes (PostgreSQL Lic.) | queue | no | no | 0 new nodes | native | none new | the DB is there and enqueue is transactional |
| Redis/Valkey Streams | yes (Valkey BSD; Redis AGPL option) | both | within retention | yes | 3 (Sentinel) | easy | low | already deployed, loss windows tolerable |
| RabbitMQ | yes (MPL-2.0) | queue (+ streams) | streams only | yes | 3 (quorum) | easy | moderate | routing, TTL, priorities, DLQ out of the box |
| Kafka | yes (Apache-2.0) | stream | yes | yes | 3 brokers | poor | high | replay and several consumer groups on one log |
| Redpanda | source-available (BSL-1.1) | stream | yes | yes | 3 | workable | moderate | Kafka semantics without the JVM footprint |
| NATS + JetStream | yes (Apache-2.0) | both | within retention | yes | 3 (R3) | native | low | one binary covers RPC, queues and streams |
| Pulsar | yes (Apache-2.0) | both | yes | yes | 3+3+3 | poor | high | multi-tenancy or geo-replication, with an operator |
| Cloud-managed | no (service) | queue or both | Pub/Sub yes, others limited | yes | n/a | dev-only emulators | near zero | no ops capacity, spiky load, one cloud |
| MQTT (Mosquitto/EMQX) | Mosquitto yes; EMQX BSL single node | pub/sub | retained only | yes | 3 (EMQX, licensed) | easy | low | the device edge, bridged inward |
| In-process | n/a | in-memory | no | in-process | 0 | native | none | one deployable unit |

## Typical mistakes

- **Kafka for a ten-message-per-second job queue.** Three nodes, JVM tuning, lag monitoring and a
  schema registry, bought for work one database table does with a `SKIP LOCKED` claim. Decide on the
  requirement — replay, independent consumer groups, sustained throughput — never on message shape.
- **The unmonitored broker as a single point of failure.** It is load-bearing by day two and nobody
  alerts on it. Queue depth, consumer lag, oldest un-acked message age and the broker's own disk and
  memory alarms are the four signals; alerting mechanics belong to `operations.md`, the requirement
  to have them to `04-quality-scenarios.md`.
- **Unbounded queues masking a dead consumer.** With no max length and no age alert, a stopped
  consumer becomes a full disk hours later — on RabbitMQ, a broker that has blocked every publisher.
  Bound every queue and stream and alert on the oldest un-acked message: depth alone lags.
- **Choosing by résumé, and its twin, choosing by what is already installed.** Redis is not a durable
  queue because Redis happens to be up. Write down the driver that survives both arguments.
- **Migrating brokers instead of abstracting the seam.** Publish and consume calls spread through the
  code turn a product swap into weeks of work; keep them in one thin transport boundary.
- **The counter-truth: an abstraction that erases the product's semantics is worse than none.** A
  generic bus interface hiding partitions, ack modes, visibility timeouts, redelivery and ordering
  produces code correct on neither product. Abstract connection, serialization and retry policy; keep
  semantics visible at the call site; write consumer idempotency by hand either way.

## Recording the choice

1. Put the products to the human as options, each with its license status, HA minimum node count and
   ops weight stated against constraint and scenario ids, plus what leaving it costs later.
2. Give one recommendation with the driver behind it. The human decides.
3. Write the accepted product as an ADR under `docs/adr/`, the rejected ones as its alternatives with
   the reason each lost, and add the broker to `03-containers.md` as a container with one edge per
   topic or queue contract.
4. Turn every number that was argued about — throughput, consumer lag, retention window, tolerated
   loss on failover — into a row in `04-quality-scenarios.md` with a unit.
5. Record the accepted operational weight in `07-risks.md` with an owner: the node count nobody yet
   operates, the restore nobody has exercised, the source-available license that could move. Anything
   left open is a `TODO(question)` per `templates.md`.
