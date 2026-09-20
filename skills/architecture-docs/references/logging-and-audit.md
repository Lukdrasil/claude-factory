# Logging and audit — decision rubric

Two artifacts share the word "log" and almost nothing else. A **diagnostic log** explains why one
request behaved the way it did; it is written for operators, may be sampled, and deleting it costs
nothing anyone notices. An **audit record** is a business fact — who did what to what, when, from
where — kept as evidence for the business, an auditor or the affected person. Everything below hangs
off that split.

`operations.md` settles where telemetry goes and who runs the backend: OTLP through a collector,
self-run against SaaS, alerting, ingest cost. This file settles what is written, in what shape, under
what rules, and whether an audit trail exists as a separate artifact. Do not re-open the wire here.

Results land in the usual places: measurable ones as observability and data-protection rows in
`04-quality-scenarios.md`, an obligation fixing retention as a row in `02-constraints.md`, a separate
audit store as its own container and edge in `03-containers.md`, the decision as an ADR. The rule
from `approaches.md` holds — two options minimum, each with its consequence against scenario and
constraint ids, your recommendation with its driver, the human decides.

## The split

| | Diagnostic log | Audit record |
|---|---|---|
| Written for | whoever is debugging | the business, an auditor, the affected person |
| Losing one | acceptable — sampled, dropped under load | a failed control, not a gap in telemetry |
| Lifetime | days to weeks, driven by cost | years, driven by an obligation |
| Mutability | rotated, deleted, reprocessed freely | append-only; a correction is a new record |
| Personal data | kept out | often the whole point of the record |
| Read access | the engineering team | named roles, few, often audited itself |
| Written | wherever the code needs it | one deliberate place, tied to the change it witnesses |

Mixing them means one column's rules win and ruin the other: audit-grade retention over debug output
grows the bill and the privacy exposure together, and log-grade handling of audit records means the
evidence was sampled away before anyone asked for it.

## Choosing by driver

| Signal in the interview or the repo | What it forces |
|---|---|
| "who changed this?" asked by anyone who is not an engineer | an audit trail as its own artifact, with its own store and retention |
| Regulated data, money moving, one person acting on another's record | a tamper-evidence tier and a retention number taken from the obligation |
| Personal data anywhere in the request path | a redaction decision, and the recognition that logs holding it become subject to erasure |
| More than one process, or any asynchronous hop | structured records and a correlation id that survives the hop |
| Support or admin staff can act as another user | actor and on-behalf-of both recorded; entering impersonation is itself an audited event |
| Log volume or the telemetry bill named as a concern | level policy, sampling rate and retention tiers as a recorded decision |
| One operator, no personal data, no action anyone will dispute | record the not-applicable audit trail and the trigger that would create one |

## Diagnostic logging

### Structure

Structured records are the default: one event, typed fields, a stable field name per fact. The
message string is not the data — free text is paid for at every query, forever, by everyone.
Deviating needs a reason recorded as a constraint.

- Use the OpenTelemetry semantic conventions for anything they name (`service.*`, `http.*`,
  `user.id`, the exception fields); invent names only for domain facts, defined once in `CONTEXT.md`.
- Trace id and span id on every record are the join key between logs, traces and the audit trail. The
  correlation id created at the edge travels in queue message headers and job payloads, not only in
  the HTTP call it started as — a design rule the async edges in `03-containers.md` inherit.
- **Typical mistakes** interpolating values into the message and recovering them later with a regex;
  a field name per team, so no query spans two services; a whole object dumped into one field.

### Levels

A level is a policy about who reacts, not a feeling about how bad something looked.

| Level | Means | Who reads it |
|---|---|---|
| error | work was lost or a user-visible operation failed | on-call; it is counted, so the error rate is a signal only while this stays honest |
| warn | the system recovered or degraded, and someone should know | whoever reviews them; a warning nobody would act on is info |
| info | the few facts that reconstruct what the system did without reproducing it | anyone investigating afterwards |
| debug / trace | developer-time detail | the person debugging, for a bounded window |

Record which level production runs at, and the bounded procedure for raising it: which component, by
whom, for how long, and what turns it back off.

- **Typical mistakes** an exception logged and rethrown at every layer, so one incident is five
  errors; error used for a validation failure the user caused, which makes the rate and every alert
  built on it meaningless; info describing the code path instead of the decision taken.

### Volume and sampling

Volume is a design output, not a surprise: decide what one ordinary request costs in records before
the backend choice in `operations.md` prices it. Sample the high-volume success path if you must,
keep every error, never sample the audit trail, and rate-limit repeated identical records at source
so a hot loop against a downstream outage does not flood exactly the window you need.

- **Typical mistakes** logging inside a per-item loop instead of once per batch with counts; whole
  request and response bodies "for now"; a retry wrapper logging every attempt at error level.

### What never enters a log line

Never: credentials, tokens, keys, session identifiers, card and account numbers, and personal data
beyond a stable opaque id. Reference a person by an internal id and resolve it at query time from the
system that owns the mapping, so the record carries the join key and not the person.

- Redact at the source, in the process, as the design. A collector rule is the safety net for what a
  new code path forgot; as the design it means the plaintext already crossed a process boundary and
  lives in every buffer and file between the two.
- Once personal data is in the logs, **the logs are personal data**: lawful basis, retention limit,
  access control, transfer rules, reachable by an erasure request. A cheap deletable stream becomes a
  regulated store, usually by accident.
- **Typical mistakes** an exception message carrying the record it choked on; a request body dumped
  at the authentication boundary, which is where the credentials are; "we will scrub it later", which
  means scrubbing a store that already holds the data.

### Retention

Decide per stream, not once for the system: a hot searchable window in days, an archive if anything
needs one, then deletion — each with a number and an owner. Storage cost belongs to `operations.md`;
the decision here is how long the evidence must exist to answer a question you can name today.

- **Typical mistakes** the window nobody chose, inherited from whichever tool was installed and found
  during an erasure request or a bill; a window shorter than the time it takes to notice the incident
  those records exist to explain.

## The audit trail

An audit record is domain output. It is written because the action happened, not because someone
might want to debug it — so it has a schema, it is tested, and a missing one is a defect.

Whatever mechanism is chosen, every record carries:

| Field | Note |
|---|---|
| actor | the authenticated identity **and** the identity acted for — impersonation, delegation, a service or agent acting for a person. Two fields, always both |
| action | a closed vocabulary of domain verbs, not free text and not the HTTP method |
| subject | what it happened to, by stable id and type |
| outcome | allowed, denied or failed — denials are the security signal and the most commonly missing field |
| when | one synchronised clock, UTC; correlation across systems is guesswork without it |
| origin | source address, channel or client, session id |
| change | before and after, or a delta, where the record must prove what changed — under the same personal-data rules as any other store |
| correlation id | joins the record to the diagnostic logs and traces of the same request |

Failed authentications and permission denials belong here. Leaving them in the application error log
is the classic finding: the events an auditor asks for first are the ones nobody routed to the trail.

### Application-level audit records in their own store

- **Use when** the record must read as domain language, must carry the actor and authorization
  context the database never sees, or must outlive the data it describes. The default for anything a
  human will be asked to explain.
- **Pros** captures intent rather than row diffs; its own store means its own retention, grants and
  access rules; the emitting path is testable like any other behaviour.
- **Cons** only what the code writes exists, so a path that forgets to emit is silently unaudited; a
  manual SQL fix or a bulk job bypasses it; a second store is a second consistency problem.
- **Typical mistakes** emitting from controllers, so the second entry point into the same use case is
  unaudited — emit where the change is committed; a fire-and-forget publish after the commit, so a
  crash loses the record and nothing reports the loss; keeping the record in the schema it witnesses,
  so the migration, tenant purge or restore that damages the data destroys the evidence with it.
  Write it transactionally with the change, then ship it out (an outbox) to a store the application
  cannot update.

### Database-level history — temporal tables, CDC, triggers

- **Use when** the question is "what did this row look like at time T", or writes reach the database
  from more than one application, so application-level capture cannot be complete.
- **Pros** nothing bypasses it, including hand-run SQL; complete by construction; system-versioned
  tables give point-in-time queries for free; cheap to switch on.
- **Cons** it records rows, not intentions — a customer cancelling and a batch job cancelling look
  identical; the actor is the connection pool's identity unless the application stamps the session;
  the history's shape changes with the schema, and it lives inside the store it audits, so a restore
  rewinds the evidence with the data.
- **Typical mistakes** presenting row history as an audit trail when the actor column is one service
  account on every row; CDC treated as the trail while its retention is measured in days; triggers on
  every write that add latency to the hot path and are quietly dropped in a migration.

### Domain events as the audit trail

The event-sourcing entry in `approaches.md` decides whether the aggregate is event-sourced; this
decides whether that log may be *called* the audit trail.

- **Honest when** the events are the source of truth for that aggregate, carry actor and origin as
  first-class fields, the store is append-only, and retention follows the obligation rather than a
  snapshot policy. **Dishonest when** the events are technical state deltas (`OrderRowUpdated`), the
  actor lives only in a middleware that never reaches the event, compaction may discard history, or
  one aggregate is event-sourced and the claim is made for the system.
- **Pros** no second write path to keep complete; replayable; complete for its aggregate.
- **Cons** the scope is the aggregate, so logins, reads, exports and denied attempts are outside it,
  and those get asked for first; erasure against an append-only store is the collision
  `operations.md` covers under retention and deletion, settled before the first event or not at all.
- **Typical mistakes** "we are event-sourced, therefore we are audited"; upcasting that rewrites past
  events in place, destroying the one property that made them evidence.

### Gateway or middleware capture

- **Use when** the requirement is coverage of an API surface — who called what — cheaply, or as a
  floor underneath one of the options above.
- **Pros** uniform and unforgettable; no application code; captures authentication and denials where
  they are decided.
- **Cons** it records HTTP, not domain: `PATCH /orders/42` does not say what changed or why, and the
  only available detail is the body, which is what must not be stored wholesale. Background jobs,
  consumers and admin scripts never pass through it.
- **Typical mistakes** recording full bodies to answer "what changed", which puts credentials and
  personal data into the store with the longest retention in the system; treating gateway records as
  the trail while half the writes come from a scheduler behind it.

### Tamper evidence

| Tier | Buys | Warranted when |
|---|---|---|
| separate store, read-restricted | an insider must cross a boundary, and the crossing is visible | the default; anything unregulated |
| append-only enforced by the store — no update or delete grant, object versioning | modification impossible by accident or by the application's own credentials | any real audit obligation |
| hash chain over the previous record, signed or anchored periodically | modification detectable afterwards, by someone who does not trust you | disputes, financial records, an outside challenger |
| WORM or immutable retention storage | modification impossible for the retention period, including by the account owner | a regulator names it |

Each tier costs the one below plus operational weight: a hash chain needs a verification job, a place
to anchor and a runbook for a failed verification, and without those three it is decoration. Choose
the lowest tier that answers "who would we have to convince, and of what" — when the answer is
nobody, record the not-applicable with that reason rather than leaving it silent.

Read access is a named role granted to few, because the trail holds what the diagnostic logs must
not, and where the content is sensitive, reads of it are audit events themselves. A trail every
engineer can query is a personal-data exposure with a compliance label on it.

## What compliance forces

- **GDPR.** Personal data in any stream, logs included, needs a lawful basis, a retention limit and a
  path for an erasure request. The tension is erasure against records an obligation makes you keep —
  resolve it in the architecture, not under a thirty-day deadline: keep personal data out of the
  diagnostic logs so only the audit trail is in scope, and tie that trail's retention to the
  obligation, so the exemption is already a recorded constraint.
- **SOC 2 and ISO 27001 class.** Three properties, not a document. *Completeness* — authentication
  successes and failures, authorization denials, privilege and configuration changes, and access to
  regulated data, from every entry point. *Separation* — the records live where the system that
  produced them cannot alter them, and a privileged user cannot edit their own trail. *Retention with
  a number* — a hot window plus an archive covering the audit period, taken from the obligation and
  enforced everywhere it applies.
- Anything asserted but not enforced — append-only claimed while the application's own credentials
  can delete — is a risk row in `07-risks.md`, not a control.

## When the evidence is thin

Recommend the reversible split: structured diagnostic logs carrying trace and correlation ids, info
in production, no personal data beyond an opaque user id, one stated hot window in days; plus an
application-level audit trail for the few actions someone would ask about — authentication, changes
to permissions and roles, and writes to the entities a customer or a regulator can see — written
transactionally with the change and shipped to a store with no update or delete grant. Note the
trigger that would raise it — a regulated data class, money that moves, a contract naming retention —
in `07-risks.md`.

## Recording the choice

1. Put the options to the human with the consequence for the affected scenarios and constraints by
   id, the recurring cost, and what reversing costs. Audit decisions reverse asymmetrically:
   retention and visibility can be cut later, records never written cannot be back-filled.
2. Give one recommendation with its driver. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`, rejected options as its alternatives with
   the reason each lost. A separate audit store is also a container row and an edge in
   `03-containers.md`; where redaction and retention are configured is referenced from
   `06-deployment.md` when that document exists.
4. Every measurable outcome becomes a row in `04-quality-scenarios.md` with a number and a unit —
   retention days per stream, sampling rate, how long after an action its record is queryable, how
   long producing one actor's history takes. Observability and data protection are two of that
   document's attributes; an attribute with no row is recorded as not applicable, with its reason.
5. Anything the human leaves open is a `TODO(question)` per `templates.md`. You do not decide it.
