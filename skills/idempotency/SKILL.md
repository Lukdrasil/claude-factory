---
name: idempotency
description: Idempotency rules for at-least-once delivery, retries and create requests. Use when writing a message or event handler, a workflow step, a retry policy, or a create endpoint.
---

# Idempotency and at-least-once delivery

Every message arrives at least once and every request may be retried. An **idempotent** operation run twice
with the same input has the effect of running it once.

## Rules

1. **Every handler and workflow step is safe to run twice**: check-then-act on a durable key, an upsert or a
   unique constraint, never a blind increment or insert.
2. **Create endpoints accept an idempotency key** or a client-chosen id and return the original result on
   replay.
3. **Only idempotent operations are retried.** That includes retries inherited from a global default policy.
4. **Retry counters and backoff state reset on success.**
5. **Outgoing messages go through an outbox** written in the unit of work's transaction and published after
   the commit.
6. **A test delivers the same message twice** and asserts one effect.

## Steps

1. **List every handler, step, retry and create endpoint** the change touches. Done when none is missing.
2. **Check each against every rule.** Done when every row passes or is fixed.

## Wrong and right

- A handler created a second record under redelivery. Right: it checks the natural key first.
- A retry counter was never reset, so a later transient failure went straight to the dead-letter queue.
