# Communication — protocol and contract rubric

`approaches.md` picks the communication axis: in-process calls, synchronous request/response, or
event-driven. This file picks what runs on that axis — the protocol per edge, the contract artifact
that describes it, and the evolution policy that keeps it from breaking consumers. Per-stack
implementation (server frameworks, client libraries, generators) stays in `stacks/<stack>.md`.

Ground every option in `04-quality-scenarios.md` (`QS-` ids for latency, throughput, availability)
and `02-constraints.md` (`C-` ids). A protocol that no scenario and no constraint distinguishes from
another is not a real option; ask for the missing scenario instead of guessing.

Where the result lands: each `Talks to` edge in `03-containers.md` gains its protocol and contract;
the contract style, versioning and deprecation numbers become an ADR; a protocol a third party imposes
(a partner's SOAP endpoint, a provider's webhook format) is a `C-` row, not a decision.

## Choosing by driver

| Driver in the recorded scenarios / constraints | Candidates to put on the table |
|---|---|
| Public surface, consumers you cannot recompile, long compatibility window | REST/HTTP+JSON with an OpenAPI contract |
| Internal service-to-service, both ends yours, throughput or polyglot codegen matters | gRPC (Connect where a browser is also a consumer) |
| Many client shapes over one shared graph; frontend and backend teams releasing separately | GraphQL |
| Frontend and backend in one TypeScript repo, internal only | typed-RPC (tRPC class) — see `stacks/react.md` |
| Server pushes to clients that did not ask, one direction only | SSE |
| Client must send on the same connection while the server streams | websockets |
| "Fresh within N seconds" satisfies the scenario, or intermediaries are hostile | polling with cache validators |
| Work must survive restarts, absorb bursts, retry and dead-letter | point-to-point queue |
| Several independent consumers of the same fact; replay is a requirement | log/stream broker |
| A fact must cross an organisation boundary outbound | webhooks |

## Synchronous request/response

### REST / HTTP + JSON

What "REST" honestly means in practice: resource-oriented HTTP with JSON bodies, meaningful methods,
status codes and cache headers. Hypermedia-driven state transfer is not what teams build or what
reviewers check — do not write a doc claiming it.

- **Use when** consumers are unknown, polyglot, or outside your release cycle; a browser is a
  first-class client; the edge must stay debuggable years from now. The default, and the option
  another choice has to beat.
- **Pros** every language, proxy, gateway and CDN already speaks it; `Cache-Control`/`ETag` caching
  costs nothing; OpenAPI tooling for docs, mocks, clients and contract tests; curl reproduces an
  incident from a log line.
- **Cons** chatty when one screen needs five resources — the aggregation lands on the client or on a
  BFF; binary payloads mean base64 (about a third larger) or a second content type; typing is only as
  strong as the generator and the discipline behind it; no streaming beyond SSE or chunked responses.
- **Typical mistakes** RPC verbs in paths plus `200` with an error inside the body, so no intermediary
  can act on failure; collections with no pagination contract; inventing the versioning scheme at the
  first breaking change; treating an interactive UI in `Development` as the contract instead of a spec
  generated at build time and diffed in CI.

### gRPC

- **Use when** both ends are yours, the call is service-to-service, and either throughput or a
  code-generated contract across several languages matters.
- **Pros** compact binary frames and fast codecs; the `.proto` is a machine-checkable contract with
  generated clients; streaming in both directions; deadlines, cancellation and status codes are part
  of the protocol rather than a convention.
- **Cons** HTTP/2 end to end, so every proxy hop becomes a constraint — see `deployment.md`; browsers
  cannot speak it (gRPC-Web needs a translating proxy and drops client and bidirectional streaming,
  while Connect-class servers speak browser-native HTTP, gRPC and gRPC-Web at once and are the answer
  when a browser is a consumer); opaque on the wire, so debugging needs `grpcurl` and reflection; the
  `.proto` becomes a build-time dependency of every consumer.
- **Typical mistakes** choosing it for a browser consumer without checking the proxy chain first; no
  deadline on the call, so one slow dependency pins callers all the way up; exposing it publicly and
  inheriting an SDK per language; using its speed to justify a chatty call graph — a distributed
  monolith at lower latency is still one.

### GraphQL

- **Use when** the aggregation problem is real and measured: several client types needing different
  shapes of one graph, or separate frontend and backend teams that must move independently.
- **Pros** the client asks for exactly the fields it needs; the schema is both the contract and the
  enforcement point; field-level `@deprecated` plus usage telemetry from real queries makes removal a
  decision with data — the strongest evolution story of any option here.
- **Cons** HTTP caching is largely given up (one URL, POST), so caching moves into the server and the
  client library; resolvers produce N+1 queries unless dataloader-style batching is built and kept
  working; authorization is per field, not per endpoint; a public graph needs depth and cost limits or
  one query is an outage; errors arrive as `200` with an `errors` array, so alerting needs custom work.
- **Typical mistakes** one client with one shape — a REST API with extra machinery; federation adopted
  before there are teams to federate; no persisted queries on a public graph; business logic inside
  resolvers, so no team owns a use case end to end.

### Typed RPC (tRPC class)

Deletes the generation step by sharing types directly: the contract lives in one TypeScript codebase
and drift is a compile error. That is the strength and the whole limit — it ends the moment a
non-TypeScript or external consumer needs the same API, and it couples frontend and backend releases.
`stacks/react.md` owns this option and its monorepo consequence.

SOAP and XML-RPC appear as an integration constraint — a bank, an ERP, a government endpoint — never
as a choice. Record the WSDL as a `C-` row and isolate it behind an adapter.

## Server-to-client push

- **SSE** — one direction over ordinary HTTP, with automatic reconnect and `Last-Event-ID` resume in
  the browser's own client. The default for token streams, progress and live status: more
  intermediaries pass it unchanged, and the resume semantics are not yours to build. Pair it with
  HTTP/2, or it consumes one of the browser's six connections per host. The client says nothing on the
  stream — cancelling or approving mid-stream is a separate request.
- **Websockets** — both directions on one connection with low per-message overhead. Use when the
  client genuinely sends during the session (collaborative editing, interactive control). Costs:
  connection state per client, sticky sessions or a backplane beyond one instance, your own
  reconnect-and-resume protocol, and an auth story that does not rely on cookies alone.
- **Polling** — short polling with `ETag`/`If-None-Match` where the scenario tolerates seconds of
  staleness: no long-lived connections, no proxy tuning, no reconnect logic, and it scales on cache
  infrastructure you already have. Long polling only as the fallback where SSE is blocked.
- **Drivers**: does the client send while the stream is open; does the infrastructure tolerate
  long-lived connections (`deployment.md` owns proxy read timeouts, buffering, upgrade headers and the
  sticky-session cost to rolling deploys); what resume looks like after a drop.
- **Typical mistakes** websockets for a one-directional feed; a heartbeat longer than the proxy idle
  timeout; reconnect with no backoff or jitter, so every restart is a thundering herd; treating a push
  channel as durable delivery — an offline client missed everything unless a store can replay it.

## Asynchronous messaging as transport

- **Point-to-point queues (RabbitMQ class)** — a message is a unit of work consumed once. Broker-side
  routing, per-message ack, priorities, TTL and native dead-lettering; quorum queues for durability.
  **Use when** work distribution, retry and DLQ semantics are the requirement. **Cons** an acked
  message is gone, so a new consumer cannot replay history; topology lives in broker configuration,
  not the repo; ordering holds only per queue with a single consumer.
- **Log / stream (Kafka class)** — an append-only retained log. Consumer groups scale by partition,
  ordering is per partition so the partition key is a design decision, and retention makes replay and
  late-joining consumers possible. Kafka 4.2 added share groups (per-message ack without
  partition-bound consumers), narrowing the gap to queues without lowering the operating floor.
  **Use when** several independent consumers read the same facts, or replay and reprocessing are
  recorded requirements. **Cons** partitions, retention, rebalancing and usually a schema registry to
  operate. Résumé check: one consumer, no replay requirement, throughput a queue handles — it is a
  queue.
- **Lightweight (NATS class)** — core NATS is subject-based pub/sub and request-reply with a very
  small operating surface; JetStream adds persistence, replay and durable consumers. **Use when**
  latency and simplicity outrank ecosystem size. **Cons** a smaller connector and tooling ecosystem;
  outside JetStream a message nobody was listening for is simply gone.
- **Cloud-managed (SQS, Service Bus, Pub/Sub class)** — no broker to operate, IAM-integrated, retry
  and DLQ as configuration. **Use when** the cloud is already a constraint and volume is moderate.
  **Cons** per-message pricing at high volume, lock-in, and provider semantics that leak into the code
  (visibility timeouts, FIFO throughput limits).

Every option forces the same four answers. Record them in the ADR — silence here is the defect.

| Question | The honest position |
|---|---|
| Delivery guarantee | at-least-once is what you actually get; at-most-once only where loss is acceptable and stated; "exactly-once" holds inside one broker's transaction scope and never across your own side effects |
| Ordering scope | per partition, key or queue — never global. Name the key, and name what happens when a key is hot |
| Poison messages | retry count, backoff, where a failed message lands, who reads that dead-letter queue and within what time |
| Backpressure | what happens when consumers fall behind: the lag threshold that alerts, the prefetch limit, and whether producers are slowed or the backlog grows |

Consumer idempotency and the transactional outbox are what make at-least-once survivable, and
`approaches.md` already names them — record the dedup key and the outbox decision, do not re-derive
them. Propagating trace context across the hop is `correlation.md`.

## Webhooks

Outbound events across an organisation boundary, where the receiver cannot poll you or hold a
connection open. The contract is larger than the payload, and all of it is recorded:

- **Signature** — HMAC-SHA256 over the raw request bytes plus a timestamp, compared in constant time,
  with overlapping keys during rotation. The Standard Webhooks shape is the de-facto default; matching
  an existing provider's scheme is the other legitimate answer.
- **Retry policy** — attempts, exponential backoff with jitter, the give-up window, and whether a
  replay endpoint exists for a receiver down longer than that window.
- **Identity** — a delivery id on every attempt for the receiver to deduplicate on; the event type and
  payload schema are versioned exactly like a public API.
- **Receiver discipline** — verify on the raw bytes before parsing, enqueue, return 2xx immediately,
  do the work off the request, and stay idempotent per delivery id: redelivery is normal traffic.
- **Typical mistakes** signing re-serialized JSON instead of the received bytes; no timestamp in the
  signed string, so a captured call replays forever; processing inline, so the sender times out and
  retries work that already succeeded; shipping whole entities, which couples the receiver to your
  model. Inbound webhooks mirror these rules and start a new trace (`correlation.md`).

## Contract and evolution

### Contract-first or code-first

| | Contract-first (OpenAPI / AsyncAPI / `.proto` is the source) | Code-first (annotations generate the spec) |
|---|---|---|
| Use when | several consumers, independent teams, polyglot clients, or the interface needs review before implementation exists | one team owns both ends and consumers ship with the provider |
| Cost | a generation step in CI, and drift between spec and handlers unless the server side is generated or validated against the spec | the contract is whatever the code happened to do, so a refactor changes it silently and review sees code, not interface |

Either way the spec is generated at build time, committed, and diffed in CI; a spec that exists only
at runtime in a development environment is documentation, not a contract. AsyncAPI plays the OpenAPI
role for message and event channels — an event schema gets the same treatment as an HTTP one.

### Versioning

| Strategy | Buys | Costs |
|---|---|---|
| Additive-only, no version | no migration, one implementation, one test matrix | every change must stay backward compatible; removing anything needs per-field deprecation and usage telemetry |
| URI path (`/v2/`) | visible in logs, routing and CDN cache keys; easiest for a consumer to reason about | each version is a separate route set to run and test; clients edit URLs to migrate |
| Header (`Accept` or `X-API-Version`) | URLs stay stable | needs `Vary` or a CDN serves the wrong version; invisible in logs and traces unless recorded explicitly; the default for a missing header is a compatibility trap forever |
| Date pin (Stripe class) | consumers are never forced to migrate | a chain of compatibility transforms and the test matrix proving them, maintained indefinitely |

Default: additive-only within a version, URI path when a break is unavoidable and consumers are
public, date pinning only for a platform with many external integrators.

### What "breaking" means, per protocol

- **JSON over HTTP** — additive change is safe only if consumers ignore unknown fields; state that
  expectation in the contract. Removing or renaming a field, narrowing a type, tightening validation,
  adding a required request field, changing a status code, or adding an enum value a consumer switches
  on exhaustively all break.
- **protobuf** — field numbers are permanent: reserve, never reuse. Adding an optional field is wire
  safe; renaming breaks generated code but not the wire; changing a type breaks both. Enforce with a
  breaking-change checker in CI and choose its category deliberately (wire compatibility versus
  generated-source compatibility).
- **GraphQL** — adding fields and types is safe; removing a field or enum value, adding a required
  input argument, or changing a type is not. `@deprecated` plus per-field usage telemetry is the
  removal path, and the reason removal is more tractable here than anywhere else.
- **Messages and events** — the schema is public from the first consumer. Record the registry's
  compatibility mode (backward, forward or full): that choice decides whether producers or consumers
  upgrade first, and it is an architectural decision, not a registry setting someone picks later.

### Public and internal are different disciplines

- **Internal**, every consumer deploying with you: break deliberately with a coordinated deploy, using
  expand/contract over two releases — add the new shape, run both, remove the old. Enforcement is a
  build-time check, not a version number.
- **Public, or any consumer you cannot recompile** — mobile apps most of all, where an installed
  version lives for years, so a server-side break is an outage for users who never upgraded. Contracts
  here are additive-only.
- **Deprecation is numbers, not intent**: notice date, dual-run period, sunset date, all in the ADR.
  Emit `Deprecation` (RFC 9745) and `Sunset` (RFC 8594) with a `Link` to the replacement, and measure
  per-consumer usage so removal can be decided from data. A window with no telemetry never closes.
- **Enforcement** at the boundary is consumer-driven contract tests — `testing.md` owns that choice.

## Serialization

| Format | Size and speed | Evolution rules | Debuggability | Use when |
|---|---|---|---|---|
| JSON | largest, slowest to parse; irrelevant below a few thousand requests per second | convention only — ignore unknown fields, never repurpose a name; JSON Schema optional | readable in curl and logs | anything crossing a team or organisation boundary, anything a browser touches |
| protobuf | small and fast, codegen for every language | strongest and machine-checkable; field numbers permanent | opaque without the `.proto` | internal RPC and event payloads where both ends are yours |
| Avro | compact, no per-field tags; the schema travels as a registry id | registry-enforced compatibility mode | opaque, needs a registry lookup | log/stream pipelines with a schema registry, especially analytics consumers |
| MessagePack | JSON's data model, smaller and faster | none beyond JSON's conventions | opaque, with no gain in rules | a JSON-shaped payload where bytes matter and adding a schema system does not pay |

The wire format is part of the contract decision — it fixes what counts as a compatible change, who
needs a generation step, and whether an incident is diagnosable from a log line. Choose it with the
protocol.

## When the evidence is thin

Recommend REST over HTTP/JSON with an OpenAPI document generated at build time and diffed in CI,
additive-only evolution, SSE for anything the server pushes, and a queue only where work must survive
a restart. Name the trigger that would change it ("a polyglot second consumer", "a replay
requirement") as a `07-risks.md` row.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected `QS-` and `C-` ids, what
   the consumers must do, and what changing it later costs them.
2. Give one recommendation with the driver behind it. The human decides.
3. Write an ADR for the contract style, versioning strategy and deprecation numbers, with the rejected
   options and why each lost; on an asynchronous edge it also carries delivery guarantee, ordering
   scope and DLQ policy.
4. Annotate `03-containers.md`: every edge names its protocol, whether it is synchronous or
   asynchronous, and the contract artifact that describes it (spec path, `.proto`, schema id).
5. An externally imposed protocol becomes a `C-` row in `02-constraints.md`. An unversioned public
   contract, an unread dead-letter queue and a deprecation window with no telemetry are `07-risks.md`
   rows with an owner.
6. Anything the human leaves open is a `TODO(question)` in the affected document, per `templates.md`.

**Done when** every `Talks to` edge in `03-containers.md` names a protocol and the contract that
describes it, or carries a `TODO(question)` saying which is still undecided.
