---
written_against: "web research 2026-08 (Svix docs, Hookdeck guides, Stripe/GitHub webhook practices)"
---

`written_against` names the vendor and provider state this rubric was checked against — Svix's
retry schedule and auto-disable window, Hookdeck's receive-side behaviour, the retry windows Stripe
and GitHub publish. A current vendor page that contradicts a number below means this file is stale
and needs re-research, not that the solution drifted.

# Outbound webhooks — delivering events into infrastructure you do not control

`communication.md` establishes that a fact crosses an organisation boundary outbound and names the
signature, retry and identity obligations that come with it. This file starts after that: how the
deliveries are actually produced, retried, isolated per customer, and surfaced to the customer as a
product. `api-consumers.md` owns the consumer relationship the webhook feeds; `message-bus.md` owns
the broker if one is doing the fan-out; `resilience-patterns.md` owns the retry and idempotency
patterns this file applies to one specific edge.

Load it when communication includes webhooks, or when the system emits events that external
customers consume at their own URLs. Outputs land in `03-containers.md` (the delivery worker and
its store as units), in `06-deployment.md` (the queue or table the deliveries live in), and in an
ADR per `templates.md`.

Outbound webhooks are at-least-once delivery into infrastructure you do not control. The producer
signs every payload with HMAC-SHA256 over `id`, `timestamp` and the raw body, using rotatable keys,
multiple signatures in one header during rotation, and roughly a five-minute timestamp tolerance
against replay. It sends asynchronously from a queue — never in the request path — and retries with
exponential backoff plus jitter over hours to days: Svix runs about eight attempts over roughly a
day, Stripe up to three days.

Every event carries a stable event id that survives retries, so receivers can deduplicate. Delivery
is honestly unordered: a retried old event lands after a newer one, so receivers must key on ids
and timestamps, not arrival order. Failures are dead-lettered per endpoint — never into one shared
DLQ that head-of-line-blocks other customers — and an endpoint failing everything for a sustained
window (Svix uses five days) is auto-disabled with a notification to the customer.

A customer-facing UI is table stakes: add and remove endpoints, view the delivery log, reveal the
signing secret, replay from the DLQ. It is also most of the actual build cost, which is why vendors
like Svix on the send side and Hookdeck or Convoy on the receive side exist at all. Build on your
own queue only if webhooks are core product; otherwise the vendor is cheaper than the six months of
edge cases.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Webhooks sent inline from the API request handler | the customer's slow endpoint sets your API latency and timeouts lose events — move sends behind a queue |
| Many tenants sharing one retry queue | one dead endpoint's retries starve everyone — per-endpoint DLQ plus circuit-breaking and auto-disable |
| No message bus in the architecture | nowhere durable to park retries; either add a queue, even a database-backed one, or buy Svix or Hookdeck |
| Receivers need to trust payloads | an HMAC-SHA256 signature header with a timestamp, a per-endpoint secret, and rotation via multiple concurrent signatures |
| Customers asking "did you send event X?" | a delivery log and replay UI per endpoint — plan it as a product surface, not an afterthought |

## Managed webhook sender (Svix)

- **Use when** webhooks are a product feature rather than your product, and you want the customer
  portal, signing, retries and DLQ replay out of the box.
- **Pros** an embeddable customer portal covering endpoints, logs and replay; a standardized
  signature scheme with built-in key rotation and replay protection; auto-disable after five days
  of total failure, with an operational webhook back to you; per-tenant isolation handled.
- **Cons** a vendor dependency sitting on your event egress path; per-message pricing at high
  volume; payloads transit a third party, so a compliance review is needed.
- **Typical mistakes** wrapping Svix but skipping its portal and rebuilding endpoint management
  badly.

## Own fan-out on the existing bus (RabbitMQ / Kafka / NATS plus delivery workers)

- **Use when** you already run a bus, webhooks are core to the product, or payloads cannot leave
  your infrastructure.
- **Pros** full control over payloads, retention and residency; no per-message vendor cost; it
  reuses existing ops muscle.
- **Cons** you own signing, rotation, backoff, the per-endpoint DLQ, auto-disable and the customer
  UI — months of work. Per-endpoint retry isolation on a shared topic is genuinely hard, needing
  delayed-retry topics or per-endpoint queues.
- **Typical mistakes** retrying forever into a dead endpoint instead of capping and disabling it;
  one global DLQ, so a single customer's outage blocks the pipeline; no jitter, so recovery causes
  a thundering herd.

## Database-backed outbox plus worker (no bus)

- **Use when** small scale, no bus, and few receivers: a `webhook_deliveries` table with a status
  and `next_attempt_at`, polled by a worker.
- **Pros** transactional with the business writes via the outbox pattern, so there is no dual-write
  loss; per-endpoint state is trivial — failure counts, a disabled flag, and a DLQ that is just a
  status; the simplest thing that is still asynchronous and durable.
- **Cons** polling latency and database load at high volume; you still write signing, backoff and
  the endpoint UI yourself.
- **Typical mistakes** sending inside the same transaction or request instead of after commit via
  the worker.

## Ingest-side vendor (Hookdeck) for receiving

- **Use when** the problem is inbound — receiving Stripe or GitHub events reliably — rather than
  sending: queues, retries and unhealthy-endpoint pausing on the receive path.
- **Pros** absorbs bursts and replays into your services; auto-pauses delivery to unhealthy
  internal endpoints and resumes on recovery.
- **Cons** the wrong tool for sending to customers, which is Svix's side of the street; another hop
  in the event path.
- **Typical mistakes** confusing send-side and receive-side products when evaluating vendors.

## Synchronous HTTP POST in the request path

- **Use when** never in production — acceptable only in a prototype demo.
- **Pros** no infrastructure.
- **Cons** the customer endpoint's latency becomes your latency; any receiver error loses the event
  permanently; no retries, no log, no replay.
- **Typical mistakes** shipping this "temporarily" and discovering it under the first customer
  outage.

## What holds whatever you pick

- Sign every payload: HMAC-SHA256 over the id, the timestamp and the raw body, and have the
  receiver reject anything with a timestamp older than about five minutes.
- Support key rotation by sending multiple signatures in one header during the overlap window.
- Every event has one stable event id across all retries; receivers deduplicate on it.
- Exponential backoff with jitter over a capped total window of one to three days, then a
  per-endpoint DLQ.
- Auto-disable endpoints that fail continuously for days and notify the customer. Never retry
  forever.
- Document that ordering is not guaranteed: receivers must tolerate out-of-order and duplicate
  delivery.
- Ship the endpoint management UI — register and test endpoints, reveal the secret, delivery log,
  manual replay.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the database-backed outbox plus a delivery
worker: signed payloads, a stable event id, jittered backoff to a capped window, and per-endpoint
status carrying the DLQ and the disabled flag. Name the trigger that would change it — webhooks
becoming core product, tenant counts where per-endpoint isolation stops being trivial, or a
customer portal nobody has budgeted — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: where deliveries are
   produced, what the retry window and give-up policy are, and who builds the customer-facing
   endpoint UI.
2. State the recurring cost of each — per-message vendor pricing, the months of edge cases a
   self-built sender implies, the compliance review a third-party payload path triggers — and what
   reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. Publish the ordering and duplicate-delivery guarantee in the consumer-facing docs; it is part of
   the contract, not an implementation note.
5. A shared DLQ across tenants, an endpoint with no auto-disable, a signing secret with no rotation
   path, and a delivery log nobody can replay from are rows in `07-risks.md` with an owner.
   Anything the human leaves open is a `TODO(question)` per `templates.md`.
