# Diagram catalogue (mermaid)

A diagram belongs inline in `## Findings`, right next to the passage it illustrates, not in a separate section
at the end. Pick by the question the diagram answers; when in doubt, take a flowchart.
Write a mermaid fence (```mermaid) directly in the markdown, no images, no external tools.

## Flowchart / data flow, `flowchart`

When: data flow, decision logic, a pipeline; "what flows where and what is decided at which point".

```mermaid
flowchart LR
    A[input] --> B{valid?}
    B -- yes --> C[processing]
    B -- no --> D[rejected]
    C --> E[(store)]
```

## Sequence, `sequenceDiagram`

When: component interaction over time, protocols, API calls; "who sends what to whom and in what order".

```mermaid
sequenceDiagram
    participant C as Client
    participant A as Orders.Api
    participant P as PostgreSQL
    C->>A: POST /orders
    A->>P: insert order
    P-->>A: ok
```

## C4 context, `C4Context`

When: architecture, system boundaries, external dependencies; "what the system is made of and what it talks to".

```mermaid
C4Context
    Person(cust, "Customer")
    System(sys, "Orders API", "order intake and fulfilment")
    System_Ext(pay, "Payment provider", "card payments")
    Rel(cust, sys, "places orders")
    Rel(sys, pay, "charges, refunds")
```

## State machine, `stateDiagram-v2`

When: a lifecycle and its transitions (e.g. order statuses); "which states a thing lives in and what flips it".

```mermaid
stateDiagram-v2
    [*] --> Placed
    Placed --> Paid: payment captured
    Placed --> Cancelled: cancel
    Paid --> Shipped: dispatch
    Shipped --> [*]
```

## ER, `erDiagram`

When: a data model, relationships between entities; "what is an entity, what is an attribute and what the cardinality is".

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ ORDER_LINE : contains
    ORDER {
        string id
        string status
    }
```

## Class, `classDiagram`

When: the structure of types and dependencies; "who depends on whom and what they carry".

```mermaid
classDiagram
    class OrderService {
        +PlaceAsync()
    }
    class Order {
        +Id
        +Status
    }
    OrderService ..> Order
```

## Gantt and timeline, `gantt`, `timeline`

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
    2026-08-18 : ADR-0007 order status lifecycle
    2026-08-20 : Orders.Worker split out
```

## Quantitative, `pie`, `xychart-beta`

When: ratios and simple metrics; anything beyond a few numbers belongs in a table, not a chart.

```mermaid
pie title Orders by status
    "Shipped" : 12
    "Paid" : 5
    "Cancelled" : 2
```

```mermaid
xychart-beta
    title "Orders per day"
    x-axis [mon, tue, wed]
    y-axis "count" 0 --> 10
    bar [3, 7, 5]
```
