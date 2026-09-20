---
written_against: "web research 2026-08"
---

`written_against` names the specification and tooling state this rubric was checked against — RFC
9745 and RFC 8594's header semantics, the schema-registry compatibility modes, the oasdiff-class
breaking-change checkers. A current spec or tool page that contradicts it means this file is stale
and needs re-research, not that the solution drifted.

# API governance — versioning, deprecation, and the CI gate that enforces both

`communication.md` picks the protocol on an edge and the contract artifact that describes it. This
file starts once that artifact exists and someone else consumes it: how the contract changes
without breaking them, what mechanically stops a breaking change from shipping, and what a
deprecation actually consists of. `api-consumers.md` owns who the consumers are and what a partner
or public relationship adds on top; `testing.md` owns where consumer-driven contract tests sit in
the overall test strategy.

Load it when designing or changing a contract another team or an external party consumes, when the
versioning strategy is open, when something is being deprecated, or when event schema compatibility
is in scope. Outputs land on the edges in `03-containers.md` and in an ADR per `templates.md`.
Every choice below reaches the human as options with consequences plus your recommendation, per
`approaches.md`.

Contracts break silently unless something mechanical stops them. The safe default is an OpenAPI
document — or the event schema — checked into the repo as the source of truth, additive-only
evolution, a schema diff (oasdiff class) failing CI on breaking changes, and an explicit `v2` only
when a break is genuinely unavoidable. Deprecations get RFC 9745 `Deprecation` and RFC 8594
`Sunset` headers and a real removal date. Events are stricter than APIs: a topic's history is read
by future consumers, so schema-registry compatibility — `BACKWARD_TRANSITIVE` or `FULL_TRANSITIVE`
— does the enforcing. There are two failure modes to steer between: a silent breaking change that
takes down every consumer at once, and "we can never touch this field" paralysis because nobody
knows who consumes what.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| One consumer team | a conversation; many consumers is a contract |
| Public versus internal API | public contracts are forever-ish; internal ones can be renegotiated |
| Contract tests or field-usage telemetry already exist | a break is deployable with evidence; without them you must assume everyone uses every field |
| Events on a bus with replay | stricter compatibility than request/response — history is part of the contract |
| A fast-moving internal API | additive-only with a diff gate; ceremony kills iteration speed |
| A missed break costs a partner SLA | consumer-driven contracts (Pact class) with `can-i-deploy` as a release gate |

## Additive-only evolution

- **Use when** the default. No versions: add optional fields, add endpoints, add enum values
  consumers were told to tolerate. Breaking changes are simply not allowed, and a genuinely new
  shape becomes a new endpoint. Enforced by schema diff in CI, not by discipline.
- **Pros** zero version sprawl — one live contract, one docs page; consumers never migrate, and
  oasdiff-class tooling enforces it mechanically on every PR.
- **Cons** design mistakes are permanent unless paired with a real deprecation and sunset process,
  which is exactly where field paralysis comes from; it requires consumers to be tolerant readers
  that ignore unknown fields, since a strict deserializer breaks on additions anyway.
- **Typical mistakes** enforcing by code review alone — reviewers do not diff schemas in their
  heads; accreting `customer_name_v2` fields because the ban has no escape hatch.

## URL versioning (`/v2/`)

- **Use when** a break is unavoidable — not as the routine change mechanism. `v1` and `v2` run side
  by side; `v1` gets `Deprecation` and `Sunset` headers and a removal date.
- **Pros** explicit, cacheable and visible in logs, which is what external consumers actually
  expect; clean side-by-side operation and gradual migration.
- **Cons** every version is a live codepath you maintain, test and secure, which becomes version
  sprawl with many teams; without an enforced sunset, old versions never die.
- **Typical mistakes** versioning the whole API for one endpoint's break; minting `/v3/` within a
  year — at that point the design review is broken, not the versioning scheme.

## Header / media-type versioning

- **Use when** hypermedia-heavy APIs where URLs must be permanent identifiers. Rarely worth it
  elsewhere.
- **Pros** URLs stay stable, and a single representation can be versioned on its own.
- **Cons** invisible in logs, browsers, curl and many caches — a debugging tax on every consumer;
  the same sprawl economics as URL versioning with worse ergonomics.
- **Typical mistakes** expecting external developers to get `Accept` headers right — the support
  burden is real.

## Consumer-driven contract testing (Pact class)

- **License** Pact MIT.
- **Use when** multiple independent consumer teams exist. Each consumer publishes a contract of
  what it actually uses, the provider verifies against all of them in CI, and `can-i-deploy` blocks
  a release that breaks a known consumer.
- **Pros** it answers "who uses this field?" with data rather than fear, which is what enables safe
  non-additive cleanup; "will this deploy break anyone" becomes a CI question.
- **Cons** a broker to run, and every consumer team must participate — the value collapses if only
  half do; useless for public APIs with unknown consumers.
- **Typical mistakes** adopting it with one team, which gates deploys against yourself; lazy
  contracts giving false confidence, since they cover what consumers wrote down, not what they do.

## Change type, class, and what to do

| Change | Class | What to do |
|---|---|---|
| Add an optional request field or a new response field | additive | ship; consumers must ignore unknown fields |
| Add a new endpoint or resource | additive | ship |
| Add an enum value | additive-ish | breaking for exhaustive-switch consumers; document "expect unknown values" or treat it as breaking |
| Make an optional field required; tighten validation | breaking | a new version or a new endpoint, never in place |
| Remove or rename a field or endpoint | breaking | `Deprecation` and `Sunset` headers plus a migration path; remove only after the sunset passes and telemetry shows zero use |
| Change a field's type or semantics — same name, new meaning | breaking, the worst kind | never reuse the name; add a new field and deprecate the old one |
| Change the error format or status codes | breaking | version it; consumers parse errors more than you think |

## Event-schema compatibility modes

| Mode | Guarantee | Use when |
|---|---|---|
| `BACKWARD` | new-schema consumers read old data (latest only) | consumers upgrade first; recent-history replay |
| `BACKWARD_TRANSITIVE` | new-schema consumers read all historical data | consumers replay topics from the beginning — the honest requirement for most Kafka topics |
| `FORWARD` | old-schema consumers read new data | producers upgrade first; consumers lag |
| `FULL` / `FULL_TRANSITIVE` | both directions | many independent producer and consumer teams; safest and most restrictive |
| `NONE` | no checks | never for shared topics |

## What holds whatever you pick

- The spec in the repo is the contract; the running code conforms to it, not the other way around.
- A schema diff in CI is non-negotiable once a second team consumes you — one YAML step prevents
  the take-down-every-consumer failure mode.
- Additive-only is the default. A new major version is an admission of defeat: budgeted and rare.
- Deprecate with machinery, not blog posts: RFC 9745 `Deprecation` plus RFC 8594 `Sunset` headers,
  migration docs, and `410` after sunset. No sunset date means it is not deprecated, just insulted.
- Consumers must be tolerant readers — ignoring unknown fields and tolerating unknown enum values.
  Put that in the contract docs on day one.
- Events are stricter: pick `BACKWARD_TRANSITIVE`, or `FULL_TRANSITIVE` across many teams, and let
  the registry reject incompatible schemas at publish time.
- Field-removal paralysis is an information problem. Contracts or field-usage telemetry tell you
  whether anyone reads the field; no data means assuming everyone does.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the spec committed to the repo as the
source of truth, additive-only evolution with an oasdiff-class gate failing CI on a breaking
change, `BACKWARD_TRANSITIVE` compatibility on every shared topic, and no version segment at all
until a break is genuinely unavoidable. Name the trigger that would change it — a second consumer
team, a partner SLA, the first change that cannot be made additively — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: who consumes the contract,
   which versioning scheme applies, and what the registry's compatibility mode will be.
2. State what each costs the consumers — a migration, a header they must send, a contract they must
   publish — and what reversing it later costs.
3. Write the versioning scheme, the deprecation numbers (notice date, dual-run period, sunset date)
   and the compatibility mode as an ADR under `docs/adr/`, with the rejected options and the reason
   each lost.
4. Annotate `03-containers.md`: every consumed edge names its contract artifact and the gate that
   protects it.
5. A contract with no CI diff gate, a deprecation with no sunset date, a shared topic on `NONE`,
   and a field nobody can remove because no telemetry exists are rows in `07-risks.md` with an
   owner. Anything the human leaves open is a `TODO(question)` per `templates.md`.
