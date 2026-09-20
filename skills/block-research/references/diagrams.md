# Diagram catalogue (mermaid)

A diagram belongs inline in `## Findings`, right next to the passage it illustrates — not in a separate section
at the end. Pick by the question the diagram answers; when in doubt, take a flowchart.
Write a mermaid fence (```mermaid) directly in the markdown — no images, no external tools.

## Flowchart / data flow — `flowchart`

When: data flow, decision logic, a pipeline; "what flows where and what is decided at which point".

```mermaid
flowchart LR
    A[input] --> B{valid?}
    B -- yes --> C[processing]
    B -- no --> D[rejected]
    C --> E[(store)]
```

## Sequence — `sequenceDiagram`

When: component interaction over time, protocols, API calls; "who sends what to whom and in what order".

```mermaid
sequenceDiagram
    participant U as User
    participant D as Dashboard
    participant S as State repo
    U->>D: approve task
    D->>S: commit + push
    S-->>D: ok
```

## C4 context — `C4Context`

When: architecture, system boundaries, external dependencies; "what the system is made of and what it talks to".

```mermaid
C4Context
    Person(dev, "Developer")
    System(sys, "claude-os", "task orchestration")
    System_Ext(forge, "Forge", "GitHub/GitLab")
    Rel(dev, sys, "files tasks")
    Rel(sys, forge, "MRs, issues")
```

## State machine — `stateDiagram-v2`

When: a lifecycle and its transitions (e.g. task statuses); "which states a thing lives in and what flips it".

```mermaid
stateDiagram-v2
    [*] --> draft
    draft --> ready: approve
    ready --> in_progress: dispatch
    in_progress --> review
    review --> [*]
```

## ER — `erDiagram`

When: a data model, relationships between entities; "what is an entity, what is an attribute and what the cardinality is".

```mermaid
erDiagram
    REPO ||--o{ TASK : has
    TASK ||--o| PROGRESS : reports
    TASK {
        string id
        string status
    }
```

## Class — `classDiagram`

When: the structure of types and dependencies; "who depends on whom and what they carry".

```mermaid
classDiagram
    class Orchestrator {
        +TickAsync()
    }
    class OrchestrationTask {
        +Id
        +Status
    }
    Orchestrator ..> OrchestrationTask
```

## Gantt and timeline — `gantt`, `timeline`

When: phases, a plan, history over time; gantt for durations and overlaps, timeline for a sequence of events.

```mermaid
gantt
    dateFormat YYYY-MM-DD
    section Phases
    analysis       :a, 2026-08-20, 2d
    implementation :after a, 3d
```

```mermaid
timeline
    2026-08-18 : ADR-0025 state repo structure
    2026-08-20 : research diagrams plan
```

## Quantitative — `pie`, `xychart-beta`

When: ratios and simple metrics; anything beyond a few numbers belongs in a table, not a chart.

```mermaid
pie title Tasks by tier
    "green" : 12
    "yellow" : 5
    "red" : 2
```

```mermaid
xychart-beta
    title "Tasks per week"
    x-axis [mon, tue, wed]
    y-axis "count" 0 --> 10
    bar [3, 7, 5]
```
