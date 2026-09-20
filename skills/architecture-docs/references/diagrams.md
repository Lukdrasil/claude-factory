---
written_against:
  date: 2026-08
  mermaid: >
    v11.17 (docs current at 11.17.2; the dashboard preview bundles 11.17.0). Every keyword named
    below exists in that version: flowchart, sequenceDiagram, classDiagram, stateDiagram-v2,
    erDiagram, C4Context/C4Container/C4Component/C4Deployment, architecture-beta, gantt, timeline.
    The C4 family is still flagged experimental upstream, and GitHub's markdown renderer does not
    bundle its grammar — a C4Context fence is raw text there, while the dashboard bundle renders
    it. No UML component, package, object, use-case, communication or timing diagram exists in
    mermaid at any version.
  likec4: >
    v1.59.2, published 2026-07-22 — pinned in src/worker/Dockerfile and bound to toolset
    `arch-build`. One model with views projected from it, a separate deployment model with its own
    views, dynamic views in diagram and sequence variants; CLI start/build/export/gen/validate/
    format/lsp, with `gen` emitting mermaid, dot, d2 and plantuml.
  note: >
    audit re-checks this stamp against the mermaid the rendering host actually ships and the likec4
    version pinned in the worker image — a mismatch means this file is stale and needs re-research,
    not that the repo did something wrong.
---

# Diagrams — which type, and how it is authored

A diagram is a **view of a model**, not decoration. Each type answers one question for one
audience; write the question down before drawing, and if you cannot, the diagram is maintenance
debt. An unmaintained diagram misleads worse than no diagram, because readers trust it. Two rules
carry the rest: **diagrams-as-code in version control** — text that diffs in the same MR as the
change is the only mechanism that has ever kept a diagram current — and **one diagram, one
question**, because a picture answering three is read for none.

Where the outputs land: the mermaid fences `templates.md` mandates in `01-context.md` and
`03-containers.md`; sequences in `05-runtime.md`; the LikeC4 model in `docs/architecture/*.c4` per
`docs/design/architecture-model.md`; an occasional sketch inside an ADR. `templates.md` owns the
inline mandate — this file does not reopen it. Preview rendering mechanics and ready-made snippets
live in `block-research/references/diagrams.md`.

## What practice actually kept

Petre's ICSE 2013 interviews with 50 professional engineers found 35 using no UML at all and none
using it wholeheartedly; among the 15 selective users, class diagrams appeared 7 times, sequence 6,
activity 6, state 2, use case 1 — and most were thrown away after the discussion they served. The
full UML catalogue lost. Three things survived into daily use: **sequence diagrams**, for one
interaction over time; **boxes and lines for structure**, formalised as C4 rather than as UML
component and package diagrams; and **deployment views**, now usually written as infrastructure
code and described in prose plus a mapping table rather than drawn. Catalogue the rest so you can
recognise it and say why it is not drawn; offer it only against a recorded question.

## Choosing by question

| The question the reader has | Diagram |
|---|---|
| What is inside the system boundary and what does it talk to? | C4 context |
| Which deployable units exist and what flows between them? | C4 container |
| Which parts sit inside one deployable and which way do dependencies point? | C4 component |
| Who sends what to whom, in what order, in this one scenario? | sequence |
| What is decided at which step of this flow? | activity, spelled as a flowchart |
| Which states can this one entity be in, and what moves it? | state machine |
| What are the entities, their attributes and their cardinalities? | ER |
| Which environments exist and where does each artifact run? | a mapping table, plus a deployment view only if the topology is non-obvious |
| What does the domain's vocabulary look like as types? | class — generated from code, not hand-drawn |

## Structural types

### Class diagram — `classDiagram`

- **Shows** classes with attributes and operations; associations, generalisation, composition,
  multiplicities.
- **Answers** what the domain's types are and how they relate.
- **Use when** the domain model itself is the hard part and a small hand-picked subset (five to
  nine types) explains a concept the prose cannot. Aggregate boundaries in a DDD discussion are the
  usual honest case; see `ddd.md`.
- **Misuse** transcribing a namespace. Code generates this view better and always correctly — an
  IDE or doc generator draws every class, so a hand-maintained one is stale on the next merge.
- **Authoring** mermaid `classDiagram`. Not in LikeC4: the model stops at C4 level 3 on purpose.

### Component diagram — UML sense

- **Shows** components, their provided and required interfaces, and the wiring between them.
- **Answers** which parts a deployable is built from and what each exposes.
- **Use when** in practice, never as UML: C4's component level answers the same question with fewer
  notation rules and is what readers expect.
- **Authoring** no mermaid equivalent; draw it as `C4Component` or a LikeC4 view of the container's
  children.

### Package diagram

- **Shows** packages/namespaces/modules and their dependencies.
- **Answers** which way dependencies point across module boundaries — the modular monolith's
  central question (`approaches.md`).
- **Use when** the boundaries are enforced and the allowed direction must be shown. Prefer the
  enforcement: an architecture test failing on a wrong-direction reference is worth more than the
  picture, and the picture without the test documents an intention.
- **Authoring** mermaid `flowchart` with subgraphs; LikeC4 component-level view.

### Object, composite structure

Object diagrams (a snapshot of concrete instances) belong in a test fixture or an example payload;
composite structure (parts, ports, connectors inside a classifier) is practice-dead. Neither has
mermaid support. Do not propose them.

### Deployment diagram

- **Shows** nodes (hosts, containers, runtimes), the artifacts deployed onto them, and the
  communication paths between nodes.
- **Answers** where each thing runs and what crosses the network between machines.
- **Use when** the mapping is genuinely not evident from the repo: several environments, an
  appliance at a customer site, a network segmentation a reader must respect.
- **What replaced it** `06-deployment.md`'s environment and mapping tables plus the IaC that
  provisions them — a Compose file, Helm chart or Terraform module is the executable version of
  this diagram and cannot drift. See `deployment.md` and `containers.md`.
- **Authoring** mermaid `C4Deployment` (experimental) or `architecture-beta` for a cloud-service
  topology; LikeC4's deployment model and its views are the better fit once the topology is worth
  modelling at all.

## Behavioural types

### Sequence diagram — the survivor

- **Shows** participants as lifelines and the ordered messages between them, with returns, loops
  and alternatives.
- **Answers** who calls whom, in what order, and what comes back — for exactly one scenario.
- **Use when** a flow crosses at least two containers and the order or the failure handling is not
  obvious from `03-containers.md`. One scenario per diagram, named for the scenario.
- **Misuse** one diagram covering every branch of every flow; participants that are classes rather
  than containers or external systems; a happy path with the failure paths left to prose
  (`templates.md` requires them stated).
- **Authoring** mermaid `sequenceDiagram`, the format `05-runtime.md` uses. LikeC4 dynamic views
  carry the same content in a sequence variant with parallel/loop/alternative blocks.

### Activity diagram

- **Shows** actions, decisions, forks and joins, optionally in swimlanes per actor.
- **Answers** what happens in what order and what is decided where, when the steps matter more than
  the actors.
- **Use when** a business process or approval flow branches enough that prose becomes unreadable.
- **Misuse** flowcharting code — a function's control flow is read from the function.
- **Authoring** mermaid `flowchart` is the modern spelling; no UML activity notation is needed.

### State machine diagram

- **Shows** states, the events causing transitions, guards, entry and exit points.
- **Answers** which states one entity can occupy and what moves it between them.
- **Use when** the entity is genuinely stateful: transitions are restricted, illegal ones rejected,
  and something in the code enforces them. A task's status lifecycle is the canonical case.
- **Misuse** drawing an enum. With no forbidden transitions the enum in the code documents it
  better, and the diagram adds a second thing to keep in sync.
- **Authoring** mermaid `stateDiagram-v2`.

### Use case, communication, timing, interaction overview

All practice-dead. Use case diagrams answer "who can do what", which stories with acceptance
criteria answer better (`docs/product/stories/` per `templates.md`); communication diagrams restate
a sequence without the time axis; timing diagrams belong to embedded work with a recorded latency
scenario; interaction overview diagrams index other diagrams. No mermaid support. Do not propose
them.

## Non-UML types the architect actually uses

### C4 — context, container, component

- **Shows** three zoom levels over one structure: the system and its neighbours; the deployable
  units inside it; the parts inside one unit. Level 4 (code) is deliberately excluded — a
  hand-maintained code level dies of churn and takes the rest of the model with it.
- **Answers** the structure question UML component and package diagrams answered badly, in a
  notation a newcomer reads without a legend.
- **Use when** always, for `01-context.md` and `03-containers.md`; component level only where a
  container's internals are themselves a question.
- **Authoring** mermaid `C4Context`, `C4Container`, `C4Component` — still experimental upstream and
  not rendered by GitHub's markdown, so when a repo's diagrams must be readable on GitHub, a
  `flowchart` with subgraphs carries the same content in a notation everything renders. LikeC4
  models all three levels natively as views over one model.

### ER diagram

- **Shows** entities, attributes, and relationships with cardinality.
- **Answers** what the data shape is and how records relate.
- **Use when** the data shape is the hard part of the design. The schema migration already
  documents the columns; the diagram earns its place only by making relationships visible.
- **Authoring** mermaid `erDiagram`.

### Flowcharts, gantt, timeline

`flowchart` is the general-purpose fallback and the spelling for activity flows. `gantt` and
`timeline` are project artifacts — schedules and history — and never belong in
`docs/architecture/`.

## Authoring: mermaid or LikeC4

| | mermaid | LikeC4 |
|---|---|---|
| Unit | one fence = one diagram | one model, many views projected from it |
| Elements | restated in every diagram that mentions them | declared once, referenced by name |
| Views | written by hand | `include`/`exclude` predicates over the model |
| Rendering | inline in GitHub, GitLab and our previews | a build step producing a static site with click-through drill-down |
| Cost | none | a node toolchain, a build in CI, and a DSL to learn |
| In this repo | the format `templates.md` mandates inside the documents | `docs/architecture/*.c4`, validated by toolset `arch-build` |

**mermaid** costs nothing and renders where people already read. Its limit is that no model sits
behind the fences: the same container appears in three diagrams as three unrelated strings, so a
rename is three edits and drift is invisible until a reader notices. Its C4 support is experimental
and unevenly rendered (see the stamp).

**LikeC4** is a model first. Elements are declared once with kind, technology and description,
nested to form the hierarchy; relationships are declared between them; each view says which parts
of the model to include, so context, container and component views cannot contradict each other.
A separate deployment model carries its own views, and dynamic views carry scenarios. The cost is
npm, a build, and rendering that lives outside the markdown — a cost this repo already pays:
`likec4` is pinned in the worker image (Graphviz alongside it since #418; `arch-build` uses the
bundled WASM engine via `--no-use-dot`, so the contract has no native dependency), `arch-build`
validates the model, and the `solution-c4-map`
skill renders the interactive map from the same DSL.

**The decision rule.** mermaid for every view a document carries inline — the C4 fences
`templates.md` mandates, one-off sequences in `05-runtime.md` or an ADR. LikeC4 once restating
elements across diagrams starts to drift; the threshold signal is concrete — more than about eight
containers, the same element in three or more diagrams, or a component level per container, at
which point a rename stops being reliably applied by hand. Not exclusive, and past the threshold not optional either:
`likec4 gen mermaid` emits fences from the model, so a repo with a `.c4` model keeps its inline C4
fences generated from it rather than hand-written. A hand-written C4 fence in such a repo is a
second source of truth that drifts silently from the first; `architect-review` records it as a
`suggestion`.

**The neighbours.** PlantUML covers the whole UML catalogue but needs a render step — GitHub does
not render it at all, GitLab only when an administrator wires up a PlantUML server — so the diagram
stops being readable where the code is reviewed. Structurizr is C4's own tooling with the same
model-and-views idea and a mature DSL, but its rendering runs as a service the team operates. This
repo standardises on the two above because one renders with zero setup everywhere we read markdown
and the other is already installed, pinned and bound to a toolset command.

## The minimal set

For a typical repo this is the whole justified inventory:

- **C4 context and C4 container**, inline, per `templates.md`. Always.
- **Two or three sequences** in `05-runtime.md`, once there is more than one container — the flows
  that cross containers and whose failure handling is not obvious.
- **An ER diagram** only when the data shape is the hard part of the design.
- **A state machine** only for an entity with genuinely restricted transitions.
- **A deployment view** only when `06-deployment.md`'s tables leave the topology unclear.

Everything beyond that list needs a recorded question it answers — a quality scenario, a
constraint, a reader who asked. Put the question in the document next to the diagram. A diagram
with no such question is a `suggestion`-class finding under `architect-review/references/checks.md`
when the reviewer meets it: name it, name what maintaining it costs, and propose deleting it or
recording the question.
