---
name: ef-core-persistence
description: EF Core persistence rules for DbContext lifetime, the unit of work, change tracking, keys and queries. Use when writing code that touches a DbContext, a repository, an entity configuration or a read query.
---

# EF Core persistence and the unit of work

One **unit of work** is one DI scope, one `DbContext` and one `SaveChanges`. Everything below keeps tracked
state, transactions and side effects inside that boundary.

## Rules

1. **One scope per unit of work**: a request, a message or one iteration of a job. A singleton or hosted
   service opens it through `IServiceScopeFactory.CreateAsyncScope()`.
2. **Entities stay in their scope.** Across scopes, messages and background work, pass keys and reload.
3. **External side effects run after the commit**: messages, HTTP calls, cache writes, files. An outbox row
   written in the same transaction carries what must not be lost.
4. **A new graph enters through `Add()` on the root.** `Entry(x).State = Added` marks only the root, and a
   child with a client-generated key attached by `Update()` becomes Modified and updates nothing.
5. **Client-generated keys** (Guid v7, typed ids) are configured `ValueGeneratedNever()`.
6. **Required child collections** are initialized, mapped required, and never null.
7. **Every ordered query orders by a unique key** or a tie-breaker before `Skip`, `Take` or `First`.
8. **String comparison follows the column collation.** Set it explicitly where case or accents matter and
   test it on the real provider.
9. **LINQ first.** Raw SQL only parameterized (`FromSql($"...")`, `ExecuteSql`) and with a stated reason.
10. **Reads project, writes track.** A read is a projection to a DTO with `AsNoTracking()` in a query service;
    a write loads the aggregate tracked through the repository. Reuse what is already loaded, batch lookups
    with `Contains` over ids, and keep queries out of loops.
11. **The code that begins a transaction commits and disposes it**, and nothing touches it after that.
12. **Reads that must agree run in one transaction.**
13. **Mapping between row and domain covers every field in both directions**, proven by a round-trip test
    on the real database.

## Steps

1. **List the scope**: every `DbContext` use, scope creation, transaction, query and mapping the change
   touches. Done when none is missing.
2. **Check each row against every rule.** Done when every row passes or is fixed.

## Wrong and right

- A child with a client GUID was tracked as Modified; `Entry().State = Added` skipped the children. Right:
  `Add()` the root.
- A tracked aggregate was carried across scopes. Right: the payload carries natural keys and the handler
  reloads.
- A disposed `_tx` was reused, and the outbox entry was enqueued before the commit.
- `ToDomain` rehydrated `revokedAt = null`. Right: every field mapped, and a round-trip test.
