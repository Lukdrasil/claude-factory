# Architecture approaches — decision rubric

The catalogue you choose from before proposing an architecture, and the source of the
**options + consequences + recommendation** you put to the human. You never pick silently:
every architectural choice reaches the human as at least two options with what each one costs,
plus your recommendation and the driver it came from.

Ground each option in what is already recorded — `02-constraints.md`, `04-quality-scenarios.md`,
the existing ADRs. An option that no constraint and no quality scenario distinguishes from
another is not a real option; ask for the missing scenario instead of guessing.

## The three independent axes

An architecture is a point on all three, not one label. Do not offer "microservices or clean
architecture" as alternatives — they answer different questions.

| Axis | Question | Choices |
|---|---|---|
| Deployment topology | how many independently deployable units? | monolith · modular monolith · microservices · serverless |
| Internal structure | how is the code inside one unit organised? | layered · hexagonal/clean · CQRS (+ event sourcing) |
| Communication | how do units and modules talk? | in-process calls · synchronous request/response · event-driven |

## Choosing by driver

| Driver in the recorded scenarios / constraints | Candidates to put on the table |
|---|---|
| One team, boundaries not yet known | monolith, modular monolith |
| Two or more areas evolving at different speeds, one deployment | modular monolith |
| Parts with different load, availability or release cadence; teams that must ship without coordinating | microservices |
| One fact triggers many independent reactions; spiky load; integration across availability boundaries | event-driven |
| Business rules must be testable and outlive the framework; several driving channels (HTTP, CLI, queue) | hexagonal/clean |
| Read and write load or shape diverge sharply; complete history is a requirement | CQRS, event sourcing |
| Bursty or low-duty workloads, no ops capacity, cost must follow usage | serverless |
| Team map does not match the proposed boundaries | redraw the boundaries to the team map, or redraw the team to the boundaries (reverse Conway) — leaving the mismatch costs cross-team coordination on every change |
| A cost ceiling or budget constraint | serverless/PaaS for spiky, low-duty load; single-host compose for steady, small load; microservices multiply per-service infrastructure cost |
| A data-residency or right-to-erasure requirement | region-pinned deployment; per-region data stores; event sourcing makes erasure hard — see CQRS and event sourcing |

## Team topology as a driver

Elicit the actual team map before proposing a deployment topology: who owns what today, and any
planned org change. A boundary proposed without it is a guess.

Conway's law runs both ways. Left alone, the architecture will mirror the team structure — service
boundaries settle onto whoever already owns the code. Used deliberately, a topology choice can
instead drive the team split you want (the reverse Conway maneuver): draw the service boundaries
first and let the org grow into them.

Record the team map as an organisational `C-` row in `02-constraints.md` so the reviewer can check
a proposed cut against it.

## Cost as a driver

Ask for the cost ceiling the same way you elicit a quality scenario, and record it as an
organisational `C-` row in `02-constraints.md`. The design-time consequence — which options a
ceiling rules out — belongs in the options you put to the human here; tracking spend once the
system is running is `operations.md`'s territory.

## Monolith

One deployable unit, one database, in-process calls.

- **Use when** one team owns the whole thing, the domain is not yet proven, the load fits one
  process, and nothing needs to be released or scaled on its own.
- **Pros** one build, one deploy, one stack trace; refactoring across boundaries is cheap while
  the boundaries are still wrong; local transactions; no network failure modes.
- **Cons** everything ships on one cadence; scaling is all-or-nothing; nothing stops the
  dependency graph from rotting; build and test times grow with the whole codebase.
- **Typical mistakes** treating "monolith" as permission to skip structure entirely; a shared
  entity model that couples every feature to every other; postponing the split until extracting
  anything means a rewrite; splitting into services to fix what was really a slow test suite.

## Modular monolith

One deployable unit, modules with enforced boundaries, ideally a schema per module.

- **Use when** the domain has two or more areas that evolve separately but nothing yet justifies
  separate deployment. This is the default starting point for a system whose boundaries are
  plausible but unproven, and the cheapest path to microservices later.
- **Pros** boundaries enforced by the build (project references, architecture tests, lint rules);
  in-process calls with no network failure modes; one deploy; a module is extractable as a
  service once it earns it.
- **Cons** boundaries hold only while the enforcement holds; a shared database schema quietly
  defeats the split; still one release cadence and one scaling unit.
- **Typical mistakes** modules cut by technical layer (`api`, `services`, `data`) instead of by
  business capability; a `common` module that everything depends on, which reinstates the
  coupling; cross-module joins in the database; no build-level enforcement, so the boundaries
  exist only in the documentation.

## Microservices

Independently deployable services, each owning its data, communicating over the network.

- **Use when** parts genuinely differ in load, availability or release cadence; several teams
  must release without coordinating; and the operational capability exists — automated delivery,
  centralised logs, distributed tracing, someone on call.
- **Pros** independent release, scaling and technology per service; failures are contained if the
  calls are asynchronous or degrade gracefully; team autonomy matches a real org boundary.
- **Cons** no cross-service transactions — consistency becomes eventual and visible in the UI;
  partial failure, retries and idempotency everywhere; debugging needs tracing that must be built
  first; per-service infrastructure cost; a change across service contracts touches many repos.
- **Typical mistakes** services cut per entity (`user-service`, `order-service`) so every use case
  needs three of them; a shared database, which removes the only real benefit; synchronous call
  chains that reproduce a monolith with added latency and failure modes (the distributed
  monolith); starting here before the boundaries are known; no contract tests and no versioning
  policy, so any deploy can break a consumer.

## Event-driven

Producers publish facts; consumers subscribe. Applies within a monolith as much as across services.

- **Use when** a producer must not know its consumers, one fact triggers several independent
  reactions, load is spiky and needs buffering, or the sequence of facts is itself valuable.
- **Pros** temporal decoupling — the consumer may be down; new consumers are added without
  touching the producer; the broker absorbs bursts; the log of facts is an audit trail.
- **Cons** eventual consistency is visible to users; ordering and exactly-once delivery are not
  free; consumers must be idempotent; no single place in the code shows the end-to-end flow;
  the event schema is a public contract from the first consumer onwards.
- **Typical mistakes** commands dressed as events (`OrderCreatedEvent` that exactly one consumer
  must handle, and the caller waits for the result) — use a call; fat events carrying whole
  entities, which recouples consumers to the producer's model; no dedup key and no idempotent
  handler; no versioning plan for the event schema; choosing events where the caller needs an
  immediate answer.

## Hexagonal / clean (ports and adapters)

Domain in the centre, infrastructure behind ports, dependencies pointing inwards only.

- **Use when** the business rules are the valuable part and will outlive the framework around
  them, several driving channels enter the same use cases, or the domain must be testable without
  a database.
- **Pros** domain tests run in memory and stay fast; infrastructure decisions can be deferred and
  replaced; the dependency direction is explicit and checkable by a test.
- **Cons** indirection and mapping code between layers; pure overhead on a CRUD service that has
  no rules to protect; the dependency rule must be enforced, or adapters leak inward one import
  at a time.
- **Typical mistakes** ports shaped exactly like one ORM's repository, so the abstraction leaks
  the database it was meant to hide; framework and persistence types inside the domain; a "core"
  that calls infrastructure directly; applying the full structure to a service whose entire job
  is one query per endpoint.

## CQRS and event sourcing

CQRS: separate write and read models. Event sourcing: the event log is the source of truth, state
is a fold over it. They are separable — CQRS without ES is common and much cheaper.

- **Use when** read and write differ sharply in load or in shape, several read projections serve
  different consumers, or complete history and replay are a stated requirement rather than a
  preference. Apply per aggregate, not per system.
- **Pros** reads scale and are shaped independently of the write model; the write model stays
  small and rule-focused; with ES, a complete audit trail, rebuildable projections and read
  models that can be introduced retroactively over past events.
- **Cons** the read model lags, and the UI has to handle it; with ES, events are versioned
  forever and need upcasting, deletion for privacy requests is hard, and replay and snapshots are
  infrastructure someone must build and operate; the learning curve is real and it is the pattern
  most often applied where it is not needed.
- **Typical mistakes** calling a mediator pipeline with a command class and a query class per
  endpoint "CQRS" while both hit the same model — that is naming, not architecture; event
  sourcing the whole system instead of the one aggregate that needs history; querying the event
  store instead of building a projection; no versioning strategy from the first event onwards;
  presenting the write model's consistency guarantees to the user as if the read side had them.

## Serverless

Functions and managed services; no server the team operates.

- **Use when** the workload is event or HTTP driven with low duty cycle or unpredictable bursts,
  the team has no ops capacity, cost should follow usage, and the latency budget survives a cold
  start.
- **Pros** no servers to patch or size; scale to zero; per-function scaling; managed integration
  with the cloud's own events and queues.
- **Cons** cold-start latency, and it lands on the tail of the latency scenario; hard limits on
  execution time, memory and payload size; strong provider lock-in; local testing and debugging
  are weaker; at steady high load it costs more than a VM; all state lives elsewhere.
- **Typical mistakes** a function per route sharing one database and no boundaries — a
  distributed system with no architecture; long-running or CPU-heavy jobs squeezed under the
  timeout; synchronous function-to-function chains multiplying cold starts; a latency scenario
  written for the warm path only; deploying by console, so production has no reproducible source.

## When the evidence is thin

If no recorded constraint or quality scenario distinguishes the options, say so and recommend the
reversible choice: one deployable unit, modules cut by business capability with build-level
enforcement, synchronous in-process calls, and the domain isolated behind ports only where rules
justify it. Note the trigger that would change the recommendation ("a second team owning
billing", "the report load starves the write path") as a risk in `07-risks.md`.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected quality scenarios and
   constraints by id, and what it costs to reverse later.
2. Give one recommendation with the driver behind it. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected options as its
   alternatives with the reason each lost, and reference the ADR from `03-containers.md`.
4. Anything the human leaves open becomes a TODO question in the affected document, per
   `templates.md`. You do not decide it.
