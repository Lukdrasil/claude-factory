# Test strategy — decision rubric

Which kinds of tests a system invests in, and in what proportion — a decision, not a default.
This is strategy, not technique: it says *what to invest in and why*, never *how to write a
test*. For technique, the harness has dedicated skills (`run-tests`, the `code-testing-*`
family, `test-anti-patterns`); this file never restates them.

Same pattern as `approaches.md`: put the human at least two options, each grounded in
`02-constraints.md` / `04-quality-scenarios.md` / existing ADRs, with the consequence of each
and your recommendation. The strategy lands in three places: a policy constraint in
`02-constraints.md`, a measurable regression-catching scenario in `04-quality-scenarios.md`,
and an ADR recording the chosen shape and the driver behind it.

## Choosing by driver

| Driver in the recorded scenarios / constraints | Shape / kinds to put on the table |
|---|---|
| One deployable unit, logic concentrated in an isolable domain | pyramid — unit-heavy |
| Several services, risk is in the wiring between them, not the algorithms | honeycomb / trophy — integration-heavy |
| Independent teams shipping across a service boundary, no shared integration environment | contract tests (Pact-class) at the boundary |
| A handful of paths where nothing short of the full stack proves it works | a thin e2e smoke suite, not a full e2e suite |
| No tests, behaviour must not change while the code does (brownfield) | characterization tests, before touching anything |
| Business rules with a clean invariant over structured input | property-based tests |
| Domain code entangled with time, randomness, or infrastructure calls | fix the architecture first (ports) — see below, before adding more tests |

## Distribution shapes

Architecture decides which shape is even viable — see the coupling section below before
picking one.

### Pyramid (unit-heavy)

- **Use when** one deployable unit, business logic concentrated in an isolable layer, few
  network hops between the code and its answer.
- **Pros** fast, cheap, isolates the root cause precisely; runs on every save.
- **Cons** mocked collaborators hide the very integration bugs that break production; a green
  suite says nothing about whether the parts wire together.
- **Typical mistakes** unit-testing framework glue and mapping code that has no business rule;
  mocking the collaborator whose real behaviour is the risk; forcing a pyramid onto a system
  that is mostly plumbing, where there is little domain logic to unit-test in the first place.

### Honeycomb / trophy (integration-heavy)

- **Use when** microservices, or any system with many small units where the risk is in wiring
  and network behaviour rather than algorithms.
- **Pros** catches what unit tests structurally cannot — serialization, real HTTP/DB/broker
  behaviour, actual wiring; each test buys more confidence per test.
- **Cons** slower, needs real or containerized dependencies; a failure is harder to localize;
  environment flakiness becomes test flakiness.
- **Typical mistakes** integration tests sharing mutable state, so they pass or fail by run
  order; testing through the UI instead of the API/service layer; dropping unit tests
  entirely so the slow suite is the only feedback loop left.

### E2e-heavy

- **Use when** rarely — a handful of critical user journeys (checkout, auth) where the failure
  mode is losing money or trust and nothing less than the full stack proves it.
- **Pros** the only shape that tests deployed reality end to end.
- **Cons** flake compounds with suite size — every added test raises the odds any given run is
  red for an unrelated reason; triage cost grows faster than the coverage it buys.
- **Typical mistakes** treating e2e as the primary regression net instead of a spot-check on a
  few paths; growing the suite toward "cover everything," producing an unmaintainable, flaky
  bottleneck; no smoke-vs-full split, so every CI run pays the full flake tax.

## Test kinds as decisions

### Unit

What "unit" means depends on internal structure (`approaches.md`, internal-structure axis). In
hexagonal/clean, the unit is the domain tested with ports faked — cheap and stable because it
does not change when infrastructure does. Where logic lives in handlers/controllers
(transaction-script style), a "unit" test either mocks the framework until it tests the mock,
or is really an integration test wearing a unit test's name — call it what it is instead of
counting it toward pyramid coverage it does not provide.

### Integration with real dependencies (testcontainers-class)

- **Use when** the risk lives in a real datastore/broker/API's actual behaviour — query
  semantics, transaction isolation, serialization — that an in-memory fake would fake wrong.
- **Pros** catches what a mock papers over; runs identically locally and in CI; no shared
  environment to maintain or drift.
- **Cons** slower than unit tests; needs a container runtime in CI; state leaking between
  tests reintroduces flake.
- **Typical mistakes** a fresh container per test instead of per suite; using it to replace
  unit tests rather than complement them; a pinned image that has drifted from the version
  actually running in production.

### Contract tests (consumer-driven, Pact-class)

- **Use when** two teams or services must evolve independently and standing up a shared
  integration environment for every change would be the bottleneck.
- **Pros** fast — no live dependency; catches breaking changes before deploy; each side runs
  its own suite on its own schedule.
- **Cons** tests the shape of the interaction, not the business logic behind it; needs a
  broker and a versioning discipline; does not work when the provider is a public API outside
  your control.
- **Typical mistakes** writing the contract from captured traffic instead of the consumer's
  actual need; skipping provider verification, so the contract silently drifts from reality;
  using contract tests to replace the one or two integration tests that prove the real
  behaviour still exists.

### E2e (flake economics)

Covered by the e2e-heavy shape above; the decision here is narrower — per flow, not per
system. Add an e2e test only for a flow whose failure mode justifies the flake and
maintenance cost; everything else is covered lower down the stack.

### Characterization tests (brownfield)

- **Use when** changing code that has no tests and no time to first understand or fix its
  behaviour — capture what it does now, then change it safely.
- **Pros** unblocks refactor or rewrite without requiring the correct behaviour to be known
  first; cheap to write (record the actual output, assert it).
- **Cons** encodes existing bugs as if they were spec; gives false confidence if mistaken for
  a statement of *desired* behaviour.
- **Typical mistakes** leaving them in place forever instead of replacing them once real
  tests exist; writing them for code that is about to be deleted anyway.

### Property-based (where it pays)

- **Use when** a business rule has a clear invariant over structured input — pricing,
  scheduling, eligibility, parsers — easier to state as a rule than to enumerate as examples.
- **Pros** finds edge cases example-based tests never think to write; the properties double as
  executable documentation of the rule.
- **Cons** needs the invariant stated precisely, which is real work; a weak generator either
  never reaches the bug or is too slow; a failure needs shrinking to be readable.
- **Typical mistakes** reaching for it on plumbing with no real invariant; a property so loose
  it cannot fail, which is a false sense of coverage.

## Environments

| Environment | Use when | Typical mistakes |
|---|---|---|
| Shared staging | small team, low PR volume, a single mutable environment is not yet a bottleneck | the staging that diverged years ago — config, data shape and even architecture drift until a green staging run stops predicting production; changes queue behind whoever holds the environment |
| Ephemeral per-PR | enough PR volume that a shared environment serialises the team; the stack (app, DB, queues) can be stood up on demand | six isolation problems treated as one — frontend, backend, database, queue, cache and external-service isolation each need a real answer, or the "isolated" environment shares hidden state anyway; cost grows with PR lifetime left unmanaged |
| Production with flags | the team can gate blast radius (flags, segments, fast rollback) and needs real user behaviour no staging replicates | shipping a flag with no removal plan, so flags accumulate as permanent, untested branches; treating "behind a flag" as license to skip lower-level tests |

## The architecture coupling

Testability is mostly decided before the first test is written — see `approaches.md` for the
full rubric; this is the pointer back.

- **Ports/adapters vs static coupling** — a domain behind ports is cheap to unit-test: fake the
  port, no infrastructure needed. Static coupling (statics, singletons, `DateTime.Now`, direct
  file/network calls in domain code) forces integration-style tests onto logic that should be a
  fast unit test. The fix is architectural — inject the dependency — not a slower test.
- **Event-driven** — no single request/response to assert on, so tests split into a publish
  assertion (the right event, with the right shape, on the right condition) and an idempotent
  consumer test per subscriber. A full trace across every hop is not a viable common-path test;
  an integration test per hop plus the event contract stands in for it.
- **CQRS / event sourcing** — the event log makes replay a first-class testing tool: given this
  event stream, does the projection come out correct. Time travel (rebuild from a past point)
  is a test technique that only exists once there is a log to replay.

## LLM-era note

When most code is machine-written, the test suite is the contract the agent is held to, not
documentation for a later human reader. Write acceptance criteria as executable tests, or as
Given/When/Then scenarios that convert to tests 1:1, before generation — the agent's loop is
attempt → run tests → fix → repeat, and that loop only terminates correctly if green actually
means done. This changes *when* tests are written and how strictly "done" is checked; it adds
no new shape or kind to the ones above.

## Recording the choice

1. Put shape and kinds to the human as options: for each, which risk it catches and which risk
   it misses, grounded in the recorded constraints and quality scenarios. Give one
   recommendation with the driver behind it.
2. Write the decision in three places:
   - a policy constraint in `02-constraints.md` (kind: organisational) — e.g. "every service
     boundary ships a contract test before merge";
   - a measurable regression-catching scenario in `04-quality-scenarios.md` — e.g. "a breaking
     change to the pricing API fails CI before merge, not after deploy";
   - an ADR under `docs/adr/` recording the chosen shape and kinds, with the rejected options
     as its alternatives, referenced from `03-containers.md` ("Structure inside").
3. Anything the human leaves open becomes a `TODO(question)`, per `templates.md`. You do not
   decide it.
