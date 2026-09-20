# Design patterns — the time-proven set

A pattern is a recurring solution with a price attached: one more indirection, one more name to
learn, one more place where the code no longer says what it does in a single hop. The job is
matching a price to a force, not collecting patterns.

This file carries only patterns with decades of evidence behind them — what four decades kept,
transformed, or lost to the platform — so it carries no `written_against` stamp. `approaches.md`
owns the system level (deployment topology, hexagonal/clean, CQRS/ES, event-driven) and
`communication.md` the edges between units; this file is one level down, inside a component.
Stack idioms stay in `stacks/*.md`.

**A pattern earns its place when the force it answers is recorded**: a constraint in
`02-constraints.md`, a measure in `04-quality-scenarios.md`, a risk in `07-risks.md`, or an axis
of change named in an ADR. "We might need to swap it later" is not a force — it is the house
anti-pattern, and the answer to it is the simplest thing that works today.

Where the judgement lands: as **plan-check / cut-check findings** (a seam a recorded axis demands
and the plan omits; a pattern proposed with nothing recorded behind it); as **an ADR** only when
the pattern is load-bearing — it fixes a public contract, the dependency direction or a
consistency boundary; **never as ceremony in task text** — a task says what changes and what
proves it, and names a pattern only when the name *is* the instruction (see the LLM-era note).

## Choosing by driver

| Recorded force | Candidates to put on the table |
|---|---|
| A named axis of change with two or more real variants **today** | Strategy, Abstract Factory, Adapter |
| A contract you do not control (vendor, legacy, protocol) | Adapter, Facade, Gateway |
| Behaviour wrapped around one call and combinable (cache, audit, retry) | Decorator |
| One fact, several independent reactions | Observer → domain event, pub/sub |
| Work deferred, queued, retried or replayed | Command → job/message, Idempotency key |
| Construction itself varies (per tenant, per environment, per provider) | Factory Method, Abstract Factory |
| Many optional or defaulted construction parameters | Builder — or the language's named/optional arguments |
| A part/whole tree treated uniformly | Composite |
| Several writes must commit or fail together | Unit of Work, Aggregate |
| Attributes with rules that keep repeating and keep being got wrong | Value Object |
| A selection rule is domain knowledge used in more than one place | Specification |
| Absence has a defined behaviour repeated at every call site | Null Object |
| A remote dependency can be slow or down | Timeout, Retry, Circuit Breaker, Idempotency key (placement in `operations.md`) |

A force that is not in the recorded documents gets a question to the human, not a pattern.

## Variation behind a seam

The largest surviving group: "this part changes on a different schedule than that part".

- **Strategy** — one step varies along a named axis. Use when two variants exist now, or one
  exists and a constraint names the second (a second payment provider, a second tax regime).
  Cost: the algorithm is no longer readable in one place; the interface freezes the shape of every
  later variant. Misuse: one implementation plus an interface "for testing" — inject the concrete
  type, or use a function type rather than a one-method interface.
- **Template Method** — fixed skeleton, varying steps. Use when the ordering is the invariant
  worth protecting. Cost: inheritance, so the axis is fixed at compile time, only one axis is
  available, and a subclass can break the parent's assumptions. In decline for a reason —
  composition (pass the steps in) gives the same guarantee without the hierarchy; prefer it.
- **Decorator** — behaviour wrapped around an existing contract without changing it. Use when the
  additions are independent and combinable (cache, audit, metrics, retry) and the interface is
  narrow. Cost: longer stack traces, and wrapping order becomes an undocumented correctness
  concern. Misuse: decorating a wide interface, so each decorator forwards twenty members;
  redoing what the platform's own pipeline or middleware already does.
- **Adapter** — a foreign contract made to fit yours. The integration workhorse: how a hexagonal
  port meets a real SDK, and where vendor types stop. Use whenever you consume something you do
  not control. Cost: mapping code and a second vocabulary. Misuse: an adapter re-exporting the
  vendor's types, which adapts nothing.
- **Facade** — one coarse entrance to a subsystem you own, so callers stop reaching inside. Cost:
  it becomes where every new method lands. Misuse: a facade that grows until it exposes
  everything it hid; a facade over one class.
- **Composite** — leaves and containers treated uniformly. Use when the domain really is a tree
  (folders, org units, nested rules, UI). Cost: operations meaningless on one of the two shapes
  get defined anyway, usually by throwing. Misuse: forcing a tree onto a flat list.

## Construction

- **Factory Method / Abstract Factory** — construction itself varies. Use when *which* concrete
  types get built depends on something the caller must not know (tenant, environment, licence
  tier), and the variants come in matched sets (Abstract Factory). Cost: a type per variant, and
  wiring moves away from the use site. Misuse: a factory for a single product; a factory whose
  body reads a flag the DI container could read at registration.
- **Builder** — the telescoping-constructor cure, and multi-step assembly validated at the end.
  Use when construction has genuinely optional parts, or an invalid intermediate state must never
  escape. Cost: a second type shadowing the first, and a build step failing at runtime for what a
  constructor would have caught at compile time. Largely moot where the language has named and
  optional arguments plus immutable records with copy-and-modify (C#, Python, Kotlin, TypeScript
  object literals) — check that first. Misuse: a fluent builder for three required parameters.

## Decoupling in time and space

- **Observer** — a producer that must not know its consumers. Modern default: publish an event
  instead of hand-registering listeners. Use when the reactions are independent and the producer's
  job is done without them. Cost: control flow invisible at the call site, no ordering guarantee,
  and a slow synchronous handler becomes the producer's latency. Misuse: an "event" exactly one
  handler must process while the caller waits — a command dressed as an event (`approaches.md`).
- **Command** — a request captured as data. This one grew up: it is how work becomes a queued
  job, a message, an audit record or an undo entry. Use when the request must outlive the call —
  persisted, retried, scheduled, replayed or authorised separately. Cost: the request shape is a
  serialised contract needing versioning, and every handler must be idempotent. Misuse: a command
  class per endpoint with one synchronous handler and no queue, retry or audit.
- **Mediator** — colleagues that must not reference each other, routed through a hub. It earns
  its place where the interaction graph is dense and dynamic: a UI of interdependent controls, a
  workflow coordinating steps that must not know the sequence. The modern controversy is the
  in-process request bus — a request type, a handler type and a dispatcher for one call to one
  handler, adopted for the pipeline behaviours (validation, logging, transactions) rather than
  for any mediation. Legitimate only when that pipeline is real and uniform; a decorator or the
  platform's middleware usually buys the same thing in one hop. Two colleagues do not need a
  mediator, and a request bus is not CQRS — `approaches.md` § CQRS and event sourcing.
- **Publish/subscribe across process boundaries** is a communication-level decision, not a
  component pattern: shape in `approaches.md` § Event-driven, transport and contract evolution in
  `communication.md` § Asynchronous messaging as transport, delivery and failure handling in
  `operations.md`, trace propagation in `correlation.md`.

## Data and domain

PoEAA and the DDD tactical building blocks, as patterns: their mechanics, cost and misuse. Whether
to model a domain this way at all, and what each block means to the model, is `ddd.md`.

- **Repository** — a collection-like interface over persistence for one aggregate. The honest
  modern debate: a mature ORM's context already *is* a repository plus a unit of work, so a
  generic repository over it wraps an abstraction in another abstraction, hides the ORM's useful
  features, and never delivers the "swap the database later" promise it was sold on. The seam
  pays when a recorded constraint demands a persistence-ignorant domain; when it speaks
  aggregates and use cases rather than tables and returns whole domain objects; or when one
  logical entity spans more than one store. Cost: every new query is a new method someone owns.
  Misuse: a generic repository that leaks the ORM's query type — decorative at that point.
- **Unit of Work** — several changes commit or roll back as one. Use when a use case writes to
  more than one aggregate or table and partial success is unacceptable. Cost: an ambient
  transaction someone must scope and must not hold open across a network call. Mostly supplied by
  the ORM already; hand-rolling it is a finding. It does not cross service boundaries — that is a
  saga, owned by `approaches.md` § Microservices.
- **Gateway** — one object encapsulating access to an external system or protocol. Use for every
  outbound integration: the single place where retries, timeouts, auth and the vendor's error
  vocabulary translate into yours. Cost: little — one of the cheapest patterns here. Misuse:
  gateway logic spread across call sites, so the timeout policy differs per caller.
- **Value Object** — an immutable type identified by its values, carrying its own rules (money,
  date range, e-mail, quantity with a unit). The highest return per line in tactical DDD: it
  removes a class of bug (mixed-up primitives, validation done four different ways) rather than
  moving it. Use as soon as an attribute has a rule. Cost: mapping to and from the store, and a
  constructor that can reject input. Misuse: a wrapper with no behaviour and no invariant.
- **Aggregate** — a consistency boundary: one root, one transaction, invariants that hold at
  commit. The boundary rules and the judgement behind them are `ddd.md` § Tactical design; the
  architectural consequence is here — it shapes the cut of tasks and of services. Cost:
  everything outside the boundary is eventually consistent and the UI must show that; the root is
  a contention point under load. Misuse: an aggregate drawn around a whole subsystem because it
  "belongs together", so every write locks it.
- **Domain Event** — a fact the domain records, published after it commits. Use when other parts
  react to something the domain decided and the reaction must not join the deciding transaction.
  Cost: publish-after-commit needs an outbox to be reliable (`logging-and-audit.md`,
  `correlation.md`); the event is a versioned contract at its first external consumer. Misuse:
  raising an event and then depending on its handler's result in the same use case.
- **Specification** — a selection rule as a first-class composable object, usable in memory and in
  a query. Niche but real: use when the same non-trivial rule ("eligible customer", "overdue")
  must hold in validation, in a query and in a report, and drift between those copies is a live
  bug. Cost: composability pushes rules toward what the query translator supports, ending in a
  DSL nobody can debug. Misuse: one specification per query.

## Robustness

- **Null Object** — absence given a defined, do-nothing behaviour. Use where the null check is
  repeated at every call site and the neutral behaviour is genuinely correct (a no-op notifier, a
  guest with no permissions, an empty collection). Cost: a bug reads as silence rather than an
  exception. Misuse: a null object where absence *is* an error the caller must handle; an option
  type where the language has one.
- **Timeout, Retry, Circuit Breaker** — the three failure policies every remote call needs. Where
  the policy lives (library, sidecar, gateway) and what each home costs is owned by
  `operations.md` § Timeouts, retries, circuit breaking; record it there and in
  `03-containers.md`, once, not per call site.
- **Idempotency by design** — a de-duplication key carried by the request or message, and a
  handler that can safely see the same key twice. Use on every retryable operation, which under
  at-least-once delivery is all of them. Cost: a key to generate, propagate and store, with its
  own retention. Misuse: assuming exactly-once delivery from an at-least-once broker.

## Patterns absorbed into infrastructure

Check what the language, runtime and framework already provide before writing any of these by
hand. A hand-rolled version of a row below is a `suggestion` finding at minimum, and `blocking`
when it defeats something recorded (testability, lifetime management, a constraint).

| Pattern | What absorbed it | Consequence |
|---|---|---|
| Singleton | DI container lifetimes | A hand-rolled static instance is untestable, hides its dependencies, and dodges the container's lifetime rules. Register a singleton; do not write one. |
| Iterator | Language iterators, generators, lazy sequences | A custom iterator class where the language has `yield`-style generation is noise. |
| Prototype | Serialization, records with copy-and-modify | Hand-written deep-clone code is a maintenance bug waiting for the next field. |
| Visitor | Pattern matching over closed type hierarchies | Exhaustiveness is checked by the compiler; the double-dispatch scaffolding is not needed. |
| Strategy (single-method) | First-class functions and delegates | An interface with one method and one implementation is a function with extra files. |
| Proxy | Generated clients, interceptors, service meshes | Hand-written pass-through proxies drift from the contract they proxy. |
| Command dispatch | Job queues and message brokers | The queue supplies persistence, retry and dead-lettering that the pattern alone never had. |

## Where patterns go to die

The misuse catalogue — finding language, not commentary.

- **Pattern-itis** — an interface per class, a factory producing one product, a mediator standing
  between two collaborators, a repository per table over an ORM. The tell: removing the pattern
  changes nothing but line count.
- **The abstraction that never varied** — a seam built for a second implementation that never
  arrived. Speculative generality is the smell; the rule of three is the antidote — first case
  concrete, second duplicated deliberately, third earns the abstraction. The exception is a
  recorded force: a constraint or quality scenario naming the second variant is evidence, and
  then the seam is built on the first case.
- **The wrapper that erases semantics** — a generic message-bus, cache or storage interface over
  a concrete technology, hiding exactly what makes it work: acknowledgement and redelivery,
  ordering and partition keys, dead-lettering, eviction, consistency mode. It looks swappable and
  is not, and the hidden semantics resurface as incidents. Wrap *your use case* ("enqueue an
  invoice for issue"), never the technology's whole surface — `message-bus.md` § Typical mistakes
  works this through for brokers.
- **The pattern applied at the wrong level** — a component pattern answering a system question (a
  mediator standing in for a service boundary, an in-process bus called an architecture). Route
  it to `approaches.md` in the finding.
- **Resume-driven patterning** — a pattern chosen because it is the interesting one. The question
  that settles it is which recorded force it answers; a hypothetical is a finding.
- **The pattern that was never removed** — the force is gone (the second provider was dropped,
  the queue became a call) and the indirection stayed. Removal is a legitimate finding; record
  the dead seam in `07-risks.md` if it is not removed now.

Severity, in the vocabulary of `architect-review/references/checks.md`:

- A pattern with **no recorded force** behind it is a **suggestion** — name it, name its cost,
  propose the simpler shape.
- A **missing seam on a recorded axis of change** is **blocking**: cite the constraint, ADR or
  `QS-NN` naming the variant, and say which cut has to move.
- A pattern that **contradicts something recorded** — it breaks a documented dependency
  direction, hides a delivery semantic a quality scenario depends on, or collides with an
  accepted ADR — is **blocking**, with that evidence attached.

## LLM-era note

Patterns are the compression format shared by humans and agents. A named pattern in a task or an
ADR ("put the tax rules behind a strategy selected per jurisdiction") transfers intent an agent
can execute without further explanation; the same intent written as unnamed clever indirection is
what both agents and humans misread later. Use the names where they carry the instruction.

The pressure runs the other way too: generated code trends toward pattern-heavy boilerplate,
because that is what the corpus rewards. Interfaces for one implementation, factories for one
product, repositories over an ORM and layers of wrappers appear by default, quickly, and in
volume. Every rule above applies at least as hard to machine-written code, through the same lens.

## Recording the choice

1. Name the force first, with its evidence — a constraint id, a `QS-NN`, an ADR, a risk row. No
   force, no pattern.
2. Put at least two options to the human: the pattern, and the simplest thing that works without
   it. For each, what it costs now and what it costs to reverse. Give one recommendation with the
   driver behind it. The human decides.
3. Record it at the level it belongs to:
   - **load-bearing** (fixes a public contract, the dependency direction, or a consistency
     boundary) → an ADR under `docs/adr/`, rejected options as its alternatives, referenced from
     `03-containers.md`;
   - **structural but internal** → one line in the affected container's "Structure inside" in
     `03-containers.md`;
   - **local** → nothing written. Most patterns are here; documenting them is its own ceremony.
4. A pattern the human declines while the force stands becomes a risk row in `07-risks.md` with
   the trigger that would reopen it, per `templates.md`.
