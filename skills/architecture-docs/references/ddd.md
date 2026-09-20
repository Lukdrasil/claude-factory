# Domain-driven design — modelling rubric

How to decide whether a system's complexity is worth modelling, and what to do once the answer is
yes. `approaches.md` owns the structural choices (hexagonal/clean, CQRS/ES, event-driven); this
file owns the domain thinking those structures exist to serve. Same contract as every rubric here:
options with consequences plus one recommendation, grounded in `02-constraints.md`,
`04-quality-scenarios.md` and the existing ADRs — the human decides.

## The precondition

DDD pays when the competitive difficulty is in the **business rules**, and costs without returning
when the difficulty is in the **plumbing**. A system that is hard because of throughput, latency,
device integration or deployment topology is a hard *technical* problem; modelling ceremony makes
it worse. Ask the driver question before anything else: if the domain experts were replaced by a
short specification, would the system still be hard to get right? If yes, the difficulty is
technical — go to `approaches.md` and stop here.

## Choosing by driver

| Signal in the domain | What it forces |
|---|---|
| Rules that experts argue about, with exceptions and history behind them | model the core domain explicitly; the tactical patterns earn their cost |
| One term means different things to different groups ("customer" in sales, billing, support) | bounded contexts — one per meaning, translation between them |
| A legacy system or third-party model would otherwise dictate your types | anti-corruption layer at that edge, decided and named in an ADR |
| Teams or vendors own different parts and release independently | context boundaries follow ownership; pick a relationship pattern per edge |
| Rules concentrate in a few operations, the rest is forms over data | distil: heavy modelling for the core only, thin everywhere else |
| Invariants that must never be observed broken (money, stock, entitlement) | aggregate boundaries drawn around exactly those invariants |
| The system reacts to facts more than to requests | domain events — then the event-driven axis in `approaches.md` |
| CRUD over a schema someone else defined, or a solved generic problem | do not model — see "When not to reach for DDD" |

## Where the outputs land

| DDD output | Document |
|---|---|
| Ubiquitous language | `CONTEXT.md` — the repo's standing glossary; one entry per domain term, per `templates.md` |
| Bounded contexts | `03-containers.md` — a context is a boundary in the container table, and every crossing is a `Talks to` edge |
| Context relationship (ACL, conformist, published language…) | the `Talks to` edge's description plus an ADR when it constrains future change |
| Core / supporting / generic split | an ADR, tied to the goals in `product/vision.md` |
| Aggregate boundaries | not a document of their own — they are the reviewer's task-cut and transaction-boundary evidence |
| A model change that has not happened yet | `07-risks.md`, not a rewritten model |

## Strategic design

The part practice says matters most and teams skip most often. It is cheap: it costs conversation
and naming, not machinery.

### Ubiquitous language

One language per bounded context, used in speech, in the documents and in the code's type and
method names — the same word for the same thing in all three. The binding rule is that a change in
the language is a change in the code and vice versa; a term that lives only in a glossary is
decoration.

- **Do** put each term in `CONTEXT.md` with its meaning in the domain's own words, and expect to
  find that term as a type, method or module name in the repo.
- **Typical failures** a glossary written once and never enforced; developer-invented synonyms
  (`OrderManager`, `OrderData`, `OrderInfo` for one concept); technical nouns (`Processor`,
  `Handler`, `Item`) standing in for a domain word the experts already have; one language stretched
  across contexts until every term needs a qualifier to be understood.
- **Done when** every term in `CONTEXT.md` matches a name in the code, or a `TODO(question)` names
  where and why they diverge.

### Bounded contexts

Evans' central argument: total unification of a model across a large system is not feasible or
cost-effective. Instead, each model is valid inside a stated boundary, and crossings are
translated. This is what makes the language possible — one meaning per word only holds inside a
boundary.

Find boundaries where something shifts:

- **Language** — the same word carries a different meaning, or one group's distinction is invisible
  to another.
- **Ownership** — a different team, vendor or release cadence governs the rules.
- **Data meaning** — the same record is authoritative here and a cached reference there.

Size judgement: a context is too large when its glossary needs qualifiers to stay unambiguous; too
small when most changes to one rule touch several contexts at once. Prefer fewer, larger contexts
while the boundaries are unproven — merging a split you regret costs more than splitting a context
that grew. A bounded context is a *model* boundary, not automatically a deployment boundary; it may
be a module inside one deployable unit (see the modular monolith in `approaches.md`).

### Context mapping

Every edge between two contexts gets exactly one relationship, chosen deliberately and recorded on
the `Talks to` entry in `03-containers.md`.

| Relationship | Use when | Cost and failure mode |
|---|---|---|
| Partnership | two teams succeed or fail together and can coordinate releases | needs real, sustained coordination; degrades silently into a distributed monolith when it stops |
| Shared kernel | a genuinely small, stable model subset shared by two contexts under joint change control | practice has largely abandoned it — the shared part attracts growth, and it recouples the teams it was meant to keep separate; prefer duplication or a published language |
| Customer/supplier | the upstream can and will prioritise the downstream's needs; one org, aligned incentives | the downstream's needs must actually reach the upstream backlog, or this is conformist with extra meetings |
| Conformist | the upstream model is adequate and you have no leverage to change it (a platform, a big internal system) | you inherit its model and its churn; correct only while its model does not distort yours |
| Anti-corruption layer | the upstream model would damage yours — a legacy system, a third-party API, an acquisition | the workhorse, and the one with a real price: a translation layer to build and maintain. Mandatory when the foreign model contradicts your invariants or its churn would propagate; ceremony when the foreign model is already close to yours and stable |
| Open host service + published language | several downstreams consume you, and per-consumer integrations do not scale | the published contract is versioned forever from the first consumer onward |
| Separate ways | integration costs more than it returns; the overlap is coincidental | duplicated effort, accepted knowingly — record it so it is not read later as an oversight |

### Distillation

Not all of the domain deserves the same effort. Classify each subdomain, then spend accordingly.

| Subdomain | Definition | Build vs buy | How much rigor |
|---|---|---|---|
| Core | why the business wins; the rules competitors cannot copy | build, with the strongest people | full — explicit model, aggregates, invariants, the supple-design practices below |
| Supporting | necessary, specific to this business, not differentiating | build simply, or buy and adapt | language and boundaries; tactical machinery only where an invariant demands it |
| Generic | a solved problem — auth, notification, payments, billing | buy, or use a library | none; wrap it behind an anti-corruption layer if its model leaks |

The common failure is inversion: the best engineers on the generic subdomain because it is
technically interesting, while the core is subcontracted or left as CRUD. Name the core explicitly,
tie it to a goal in `product/vision.md`, and record the classification in an ADR — it is the
decision that governs where every later effort goes.

## Tactical design

Building blocks for the core subdomain. Each is a rule, not a base class; the rule is what makes it
work. `design-patterns.md` catalogues these as patterns — here they carry their DDD intent.

- **Entity vs value object** — an entity has identity that persists through change; a value object
  is defined wholly by its attributes, equal when its attributes are equal, and immutable. Modern
  practice biases to value objects: prefer one until continuity of identity is genuinely required.
  Every primitive carrying a rule (money, date range, email, quantity with a unit) is a value object
  waiting to be extracted, and extracting it moves validation out of every call site into one place.
- **Aggregate** — a cluster with one root, and the consistency boundary of the model. The rules:
  invariants that must always hold live inside one aggregate; one transaction changes one aggregate;
  other aggregates are referenced by identity, never by object graph; consistency across aggregates
  is eventual, usually carried by a domain event. Keep them small — a large aggregate is a
  contention hotspot and a loading problem. Vernon's deciding question when a change spans two:
  whose job is it to keep them consistent, the user's (same transaction, likely one aggregate) or
  the system's (eventual, via an event). Break these rules only for a stated reason — a UI or
  reporting need, a legacy constraint — and state it.
  - **What this gives the architect**: the aggregate is the natural task cut and the natural locking
    boundary. A task that changes two aggregates transactionally is either mis-cut or is proposing a
    boundary change; the reviewer should say which.
- **Domain event** — a fact the domain cares about, named in the past tense, carrying the identifiers
  and the minimal data a consumer needs. It is the bridge to the event-driven axis in
  `approaches.md`, and the mechanism for consistency between aggregates. Do not dress a command as
  an event (see that file's mistakes list).
- **Domain service** — a stateless operation that belongs to the domain but to no single entity or
  value object, expressed in the language (transfer between accounts, price a basket against a rule
  set). Reach for it only after checking that the behaviour truly has no owner; a service used as a
  default home for logic is the anemic model in disguise.
- **Repositories and factories** — collection-like access to aggregate roots, and encapsulated
  creation of complex ones. One repository per aggregate root, not per table. Mechanics live in the
  pattern catalogue; the DDD constraint is only that the repository's interface speaks the domain's
  language and hides the store.
- **Modules** — package by domain concept, not by technical layer. Module names are part of the
  ubiquitous language; `services/`, `models/`, `utils/` say nothing about what the system does.

## Supple design and the modelling loop

Practices from the book that separate a model that keeps paying from one that ossifies. Apply them
to the core subdomain.

- **Intention-revealing interfaces** — name types and operations for effect and purpose, so a caller
  need not read the implementation to use them correctly.
- **Side-effect-free functions** — push rules into operations that return a result and change
  nothing; keep the state-changing operations few, small and separate. This is what makes the core
  testable without infrastructure.
- **Assertions** — state post-conditions and invariants explicitly, in the code or in tests, so the
  contract is knowable without tracing the implementation.
- **Conceptual contours** — decompose along the domain's own seams. When a typical change touches
  one place, the contours match; when it fans out, the model is cut against the domain.
- **Standalone classes** — reduce the concepts a class drags in, so it can be understood alone.
  Treat low coupling as a modelling target, not only as a metric to report.
- **Closure of operations** — where possible, an operation's arguments and result are the same type,
  so operations compose without introducing foreign concepts.
- **Refactoring toward deeper insight** — models improve in leaps, not increments. A breakthrough
  comes when a concept implicit in the code (a hidden constraint, a policy, an unnamed process)
  is made explicit as a type, and a tangle collapses. Treat a rule that keeps needing special cases
  as the signal that a concept is missing, and look for the word the experts already use for it.
- **Knowledge crunching** — the model comes from repeated, structured conversation with the people
  who know the domain, not from a single requirements pass. The `architecture-docs` interview *is*
  knowledge crunching: each option-and-consequence question tests a candidate model against the
  human's reaction, and a term they correct is a model correction, not a wording fix. Record the
  corrected term in `CONTEXT.md` in the same pass.

## When not to reach for DDD

- **CRUD-shaped systems** — forms over data, validation but no rules. Aggregates, repositories and
  a domain layer add indirection over what a schema already expresses.
- **Generic and supporting subdomains** — buy, or keep it a transaction script. Model the core only.
- **Small teams on a small, well-understood domain** — the coordination cost of the vocabulary
  discipline exceeds the confusion it would prevent.
- **Technically hard, domain-simple systems** — proxies, pipelines, device integrations, schedulers.
  The rubric they need is `approaches.md`.

**DDD-lite is the honest middle**, and the right default when the domain is real but unproven: adopt
the ubiquitous language and the context boundaries, skip the tactical machinery until an invariant
demands it. State it as the choice, so nobody reads the missing aggregates as an oversight.

Cargo-cult failure modes, all of which cost the price without buying anything: an anemic model where
entities hold data and services hold every rule, dressed in DDD names; one aggregate per table; a
repository over every entity including value objects; a `domain/` folder with no bounded contexts
and no domain-expert conversation behind it.

## TDD as design pressure

Test-first is a design feedback loop before it is a verification technique: the test is the first
client of the code, so pain in writing it is information about coupling, not about testing. `testing.md`
owns which kinds of tests a system invests in; the loop's mechanics belong to the harness's
`block-feature` and `block-bugfix` skills. This section covers only what the loop does to a model.

- **Read the friction.** Needing a database, a clock or a network to assert a rule means the rule
  lives in the wrong place; needing elaborate setup means the object depends on too much; needing to
  assert on internals means the behaviour has no public expression yet. The fix is in the design.
- **Schools.** Classic (Detroit) tests behaviour across a cluster of real collaborators, with test
  doubles only at true infrastructure edges — it leaves the model free to be restructured and suits
  an aggregate, which is a cluster by definition. Mockist (London) tests one object against mocked
  collaborators and drives interface discovery outside-in — it produces finer interfaces and tests
  that fail on structural change, so it fits protocol and orchestration code better than a rules
  core. Choose per layer, not per project.
- **Where DDD and TDD meet.** Aggregates and value objects are the naturally unit-testable part of a
  system: pure rules, no infrastructure, invariants that state their own assertions. That is only
  reachable when ports keep infrastructure out of the domain (`approaches.md`, hexagonal/clean).
  A codebase where domain rules cannot be tested without a database has an architecture finding, not
  a testing finding.
- **Where the pressure misleads.** The test-induced design damage critique is real: pursuing
  isolation for its own sake produces layers of indirection that serve the tests and nobody else,
  and mocks that assert the implementation you already wrote. Treat difficulty as a signal to
  investigate, not an instruction to add an abstraction. Self-testing code is the goal; TDD is one
  route to it.

## Recording the choice

1. Put the modelling depth to the human as options — full DDD on a named core, DDD-lite, or no
   modelling beyond the glossary — each with what it costs, what it buys, and which recorded
   constraint or quality scenario distinguishes them. Give one recommendation with its driver.
2. Write the accepted answer down: bounded contexts and their relationships into `03-containers.md`,
   the terms into `CONTEXT.md`, the core/supporting/generic split and each anti-corruption layer
   into an ADR referenced from `03-containers.md`.
3. Anything the human leaves open becomes a `TODO(question)`, per `templates.md`. You do not decide
   it.

**Done when** every bounded context is visible as a boundary in `03-containers.md` with a named
relationship on each crossing; every term in `CONTEXT.md` matches a name in the code or carries a
`TODO(question)` saying where they diverge; the core subdomain is named in an ADR and tied to a goal
in `product/vision.md`; and any known model weakness is a row in `07-risks.md` with an owner.
