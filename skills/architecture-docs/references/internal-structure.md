# Internal structure — organising the code inside one deployable unit

`approaches.md` owns this as an axis: whether a unit is layered, hexagonal/clean or CQRS is one of its
three axes, and its hexagonal/clean and CQRS/ES entries stay authoritative for *which axis point*. This
file is one level down — the concrete code-organisation shapes, how they combine, and how to pick. Cutting
modules by domain concept and drawing aggregates as seams is `ddd.md`; the seams inside a component are
`design-patterns.md`; project layout and framework conventions are `stacks/*.md`.

## The frame

Internal structure decides two things:

- **where a change lands** — inside one folder, or as a diagonal across every layer;
- **what a test can grab** — whether the rules run without a database, a broker or an HTTP host.

So the driver question is two-part: **what varies** — the infrastructure, the feature set, or both — and
**what must be testable without infrastructure**. A recorded constraint or quality scenario answers it;
reputation does not. A structure adopted because it is the respectable one costs indirection and buys
nothing, and that is the most common finding on this axis.

Where the judgement lands:

| Output | Where it goes |
|---|---|
| The chosen shape, the options rejected, and the driver | an ADR under `docs/adr/`, referenced from `03-containers.md` |
| One short paragraph per container | `03-containers.md` § Structure inside, per `templates.md` |
| The enforcement mechanism | the same paragraph — a style nothing checks decays to a folder naming convention |
| Consequence for the task cut | the reviewer reads it as cut-check axes 2 and 3 (`architect-review/references/checks.md`) |
| A structural weakness that stands | `07-risks.md`, with the trigger that would reopen it |

**Task-cut consequence.** Under slices or feature modules, one task is one slice or one module: it changes
one folder, and its acceptance runs against one entry point. Under layered or hexagonal, a behaviour change
is inherently a diagonal — it touches the port, the core and the adapter — so the honest task is the
diagonal, and a task cut per layer ("add the repository method", "add the controller") is the mis-cut the
reviewer flags, because no single one of them is verifiable.

## Choosing by driver

| Recorded signal | Candidates to put on the table |
|---|---|
| Forms over data, validation but no rules, one small unit | layered |
| Rules that must outlive the framework; two or more driving actors (HTTP, CLI, queue, scheduler) | hexagonal |
| The above, plus use cases worth naming and testing as objects in their own right | clean/onion |
| Change arrives feature by feature, and features rarely interact | vertical slices |
| Two or more domain areas with different vocabularies inside one deployable unit | feature modules, cut per `ddd.md` |
| Read and write shape diverge inside one feature | CQRS inside that slice — `approaches.md` § CQRS |
| One person or one agent must change a feature without holding the whole unit in view | vertical slices, feature modules |
| A quality scenario demands the rules be provable without infrastructure | hexagonal, or a shared domain core under slices |
| Nothing recorded distinguishes the options | layered, plus a risk row naming what would change it |

## Layered (technical layers)

Controllers, services, repositories: horizontal strata, calls going downward, one project or folder per
stratum. The default that needs no book, and the shape every framework tutorial teaches.

- **Use when** the unit is small, the work is genuinely CRUD-shaped, one team owns all of it, and no
  recorded scenario asks for rules provable without a database. Also the honest answer for a supporting or
  generic subdomain (`ddd.md` § Distillation) sitting next to a richly modelled core.
- **Pros** every developer and every model already knows it; a new endpoint has an obvious home; the
  dependency direction is trivial to state and to check; no mapping between an inner and an outer model.
- **Cons** every feature is smeared across every layer, so a change is always a diagonal and a task is never
  contained; the layers are shared mutable ground where unrelated features collide; the domain depends on
  persistence, so its tests need a database or a large mock setup.
- **Typical mistakes** the service layer as junk drawer — one class per entity accumulating every rule any
  caller ever needed, growing until nobody can say what it guarantees; a shared entity model that couples
  every feature to every other; a `Common`/`Shared` project everything references, which reinstates exactly
  the coupling the layers were drawn to prevent; calling layer folders an architecture while the real
  dependency graph runs in every direction.

## Hexagonal (ports and adapters)

Cockburn's stated intent: let the application be driven equally by users, programs, tests and batch scripts,
and be developed and tested in isolation from its eventual devices and databases. The asymmetry is
inside/outside, not top/bottom — driving adapters trigger the application, driven adapters serve it, and
both sit outside the same boundary. See `approaches.md` § Hexagonal/clean for the axis-level entry.

- **Use when** the rules are the valuable part, more than one kind of actor enters the same use cases, or a
  quality scenario requires the rules to be exercised without infrastructure. The ceremony pays when both
  halves are true: real rules *and* several driving or driven actors.
- **Pros** the whole application is drivable headless, so the test suite is a first-class adapter rather than
  an afterthought; infrastructure choices stay deferrable and replaceable; the dependency direction is one
  sentence and one architecture test.
- **Cons** a second model at every edge plus the mapping to and from it; pure overhead on a unit whose job is
  one query per endpoint; the rule holds only while something enforces it, and adapters leak inward one
  convenient import at a time.
- **Typical mistakes** the interface-per-class cargo cult — a port is a *conversation with a kind of actor*
  ("notify a customer", "persist an order"), and Cockburn expects two to four of them in a typical
  application, not one per class; a port shaped exactly like one ORM's repository, which leaks the database
  it exists to hide; framework, persistence or transport types inside the core; a core that calls
  infrastructure directly through a static helper; applying the full structure to a CRUD unit.

## Clean / onion

Palermo's onion states the rule geometrically: code may depend on rings more central, never on rings further
out; the database, the UI and the tests are all edges. Martin's clean architecture is the same rule plus an
explicit use-case ring between entities and adapters. Treat clean as hexagonal with the dependency rule
promoted from a guideline to a checked invariant, and with use cases named as objects.

- **Use when** the dependency rule needs to be non-negotiable across a team or across agents that will not
  read the reasoning, or when the use cases themselves are worth naming, testing and reviewing individually
  — a workflow-heavy application rather than a rules-heavy one.
- **Pros** one rule that a build-time test enforces without judgement; each use case is an independently
  testable object with an obvious name; the ring diagram survives handover, which is why it spreads.
- **Cons** the indirection tax is real and it lands on the simplest changes — adding one field can mean the
  request DTO, the use case, the entity, the persistence model, the response DTO and every mapper between
  them, with several types representing one concept; ring layout applied uniformly means CRUD paths pay the
  same price as the core; the dogma invites arguing about which ring a type belongs in instead of about the
  domain.
- **Typical mistakes** rings applied to a whole unit rather than to the part with rules; mapper code
  outweighing rule code, which is the signal to drop to plain hexagonal or to layered for those paths;
  an anemic core — entities holding data while every rule lives in a use-case class, which is the layered
  service layer redrawn as circles (`ddd.md` § cargo-cult failure modes).

**Prefer plain hexagonal** when the team already keeps the direction honest, the use cases have no life
outside their entry point, and the DTO layers would be transcription rather than translation.

## Vertical slices

Organise by feature: one folder per use case, owning its path from request to response — endpoint,
validation, data access, response shape. Bogard's rule is the whole design: minimise coupling *between*
slices, maximise coupling *within* one. Rigor is chosen per slice, so a transaction script and a fully
modelled use case coexist without either one paying for the other.

- **Use when** change reliably arrives as one feature at a time, the features are largely independent, and
  the unit is big enough that "where does this change go" is a real question. Strong fit where one worker —
  human or agent — should be able to finish a feature without reading the rest of the unit.
- **Pros** a change lands in one folder and a task cut equals one slice; adding a feature adds files instead
  of editing shared ones, so parallel work rarely collides; each slice picks the simplest thing that works
  for it; deleting a feature deletes a folder.
- **Cons** logic for one domain concept can end up spread across the slices that touch it, and rules
  duplicated across slices drift; without a shared core there is no single place an invariant is guaranteed;
  cross-cutting concerns (transactions, authorisation, audit) need a deliberate mechanism rather than a
  layer that everyone passes through.
- **Typical mistakes** slices reaching into each other's internals, which converts every slice into a public
  API nobody designed; a `Shared`/`Common` folder that grows until the layers are back, unenforced; treating
  slice autonomy as licence to duplicate domain rules, which trades local simplicity for global
  inconsistency; leaving invariants in handlers when `ddd.md` says an aggregate should own them.

The guardrail is the same in every account of it: slices assume the team recognises duplication that matters
and refactors it into a shared core. Where that discipline is absent, slices degrade faster than layers do.

## Feature modules (modular-monolith internals)

Package by feature or by domain area, with each module exposing a deliberate surface — a facade, a set of
events — and everything else invisible outside it. This is the modular monolith of `approaches.md` seen from
inside one unit; when the module boundaries follow bounded contexts, `ddd.md` governs where they fall.

- **Use when** one deployable unit holds two or more areas with their own vocabulary, lifecycle or
  eventual owner, and cross-area coupling is the pain being solved. Also the shape to reach for when slices
  have grown numerous enough to need grouping.
- **Pros** the boundary is checkable by the compiler or by an architecture test, so it survives contributors
  who never read the ADR; a module is the natural extraction unit if it later earns its own deployment;
  module names are domain words, which makes the repo layout say what the system does.
- **Cons** cross-module use cases need an explicit mechanism (a published interface, in-process events), and
  that mechanism is a contract with a cost; boundaries drawn before the domain is understood are expensive
  to move; enforcement must exist from the start, because retrofitting it means paying down every violation
  at once.
- **Typical mistakes** modules named for technical layers (`api`, `services`, `data`) rather than
  capabilities; a shared database schema or cross-module joins that quietly defeat the split; a `common`
  module every other module depends on; documented boundaries with nothing enforcing them.

**Enforcement, per language.** Visibility keywords (`internal` with one assembly or project per module,
package-private, Go's `internal/`) stop violations at compile time; architecture tests (NetArchTest,
ArchUnit, import-linter and equivalents) fail the build on a forbidden dependency and also cover rules the
type system cannot express, such as "nothing in the core imports the persistence namespace". Name the chosen
mechanism in the container's Structure inside paragraph.

## Combinations

Almost every honest answer is a hybrid. Pick the combination, not the label.

| Combination | When it is the honest pick | The risk |
|---|---|---|
| Slices over a shared domain core | features vary independently, but a few invariants must hold everywhere | the core becomes a junk drawer unless entry is restricted to aggregates and value objects |
| Hexagonal core, sliced application layer | rules must be infrastructure-free, and use cases still want to own their own path | two vocabularies in one unit; state plainly which side a new type belongs on |
| Feature modules, layered inside each | modules are the real boundary and each one is small and CRUD-shaped | layer folders multiply across modules; accept the repetition rather than hoisting a shared layer |
| Feature modules, sliced inside each | a large unit with several areas, each evolving feature by feature | two levels of boundary to enforce; only worth it above a size the module count makes obvious |
| CQRS inside one slice | that feature's read and write shapes diverge; the rest of the unit does not care | CQRS spreading to slices with no divergence — `approaches.md` § CQRS |
| Layered core, one hexagonal edge | one integration must be swappable or fakeable; nothing else needs isolating | a port justified for one edge is not a mandate to port everything |

## LLM-era note

Slices and feature modules minimise the context needed to change one feature: the folder is the unit of
work, so an agent loads one path instead of a diagonal across four projects, and two agents working on two
features rarely touch the same file. That is a genuine driver in a repo where agents do the implementing,
and it deserves to be named as one when the options are put to the human — alongside its price, which is
that the duplication slices produce is exactly what a generator reproduces most willingly. Where slices are
chosen for this reason, pair them with a shared domain core for the invariants and say so in the ADR.

## Migration paths

- **Layered to slices** — strangler by feature: new features arrive as slices; an existing feature moves only
  when it is being changed anyway, taking its data access with it; the old service class shrinks as callers
  leave and is deleted when empty. No big-bang pass, and no half-migrated feature left across both shapes.
- **Layered to hexagonal** — carve the core out: start from a rule that is painful to test, move it and its
  value objects into an infrastructure-free project, define a port for each actor the rule needs, and add
  the architecture test that fixes the direction before adding the second rule.
- **Do not migrate** working code with no recorded pain. Restructuring pays only against a named symptom —
  a scenario that cannot be tested, a change that keeps touching everything, collisions between parallel
  workers. Absent one, the honest answer is that the current shape stays and the next new area is built in
  the target shape.

## Recording the choice

1. Put at least two shapes to the human, each with what it costs on the affected quality scenarios and
   constraints by id, what it costs to reverse, and what it does to the task cut. Give one recommendation
   with the driver behind it. The human decides.
2. Write the accepted shape as an ADR, rejected shapes as its alternatives with the reason each lost, and
   reference the ADR from the container's `## Structure inside` paragraph in `03-containers.md`.
3. State the enforcement mechanism in the same paragraph. A structure with no enforcement is recorded as a
   risk row in `07-risks.md`, not as a decision.
4. Different containers may hold different shapes; record each one on its own container, and never as a
   repo-wide rule.
5. Anything the human leaves open becomes a `TODO(question)`, per `templates.md`. You do not decide it.

**Done when** every container in `03-containers.md` with more than trivial code has a Structure inside
paragraph naming its shape, its enforcement and the ADR that decided it, or a `TODO(question)` saying why
not.
