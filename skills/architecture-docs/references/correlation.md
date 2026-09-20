# Correlation — decision rubric

One user action crosses the UI, a proxy, one or more services, a queue, a background job and the
database. The property this file buys is that a single operation can be followed through the logs of
every one of them: a user reports a failure, an operator gets one id from that report, and that id
alone produces the ordered story. Everything below is judged against that walk.

This file owns the **propagation design** — where an operation's identity is born, how it survives
every hop, how it reaches every log line. It does not own the telemetry wire and backend
(`operations.md`), the shape, levels and PII rules of a log record (`logging-and-audit.md`), or which
proxy exists in front of the system (`deployment.md`). Decide the id here; those files consume it.

The result lands as an ADR referenced from `03-containers.md`, whose `Talks to` edges each state what
propagates on them; as a `C-` row in `02-constraints.md` only when something outside the team imposes
the convention (a customer's gateway, a partner's header); and as an observability row in
`04-quality-scenarios.md` with the retrieval time it must meet. The rule from `approaches.md` holds:
at least two options, the consequence of each against scenario and constraint ids, your recommendation
with its driver. The human picks.

## The identities

| Id | Answers | Scope | Where it must appear |
|---|---|---|---|
| trace id | which operation is this | whole operation, all components | every log line, every span, the response to the client |
| span id | which hop inside that operation | one unit of work | spans; a log line may carry it, nothing joins on it |
| correlation id | which operation is this, without tracing infrastructure | whole operation | same places as a trace id — it is the same role, cheaper |
| request id | which single HTTP request | one hop | the proxy access log and that hop's logs |
| session id | which visit produced this | many operations | the operation's first log line, or an attribute |
| user / tenant id | who it happened to | across sessions | per `logging-and-audit.md` rules, never as a metric label |

**Exactly one of them is the join key**, and it is the operation-scoped one: a trace id, or a
correlation id where there are no traces. Every log line of every component carries it under one field
name. The rest are filters applied after the join, not substitutes — a request id stops at the proxy,
a session id matches too much.

## Choosing by driver

| Signal in the repo or the interview | Candidates to put on the table |
|---|---|
| Several components, one operator, "why did this fail" is the question | correlation id only |
| "Where did the time go" is asked, an async hop hides the answer, or the languages have auto-instrumentation | tracing, logs correlated by trace id |
| Legacy components that will never be instrumented, alongside new ones | both, one wire format |
| An external gateway or partner already stamps an id | both — carry theirs, map it in the ADR |
| One process, one log file, one operator | record the not-applicable and move on |

## Correlation id only

A generated id, propagated as a header, written into every log line by structured logging. No SDK,
no collector, no spans.

- **Use when** the components are few and mostly synchronous, the question is "what happened to this
  request" rather than "where did the time go", and nobody will operate a tracing backend. The honest
  floor for a compose-scale system, and it answers most support tickets.
- **Pros** hours of work, not weeks; no runtime dependency, no sampling, no backend bill; works in
  any language and in components you cannot instrument, down to shell scripts; the id survives in
  logs, which are kept far longer than traces.
- **Cons** no timing and no causality — lines arrive in each component's clock order, not as a call
  tree, and host skew makes even that a guess; across an async hop the id proves the message belongs
  to the operation and nothing about how long it waited; no latency per hop, no error trace to click.
- **Typical mistakes** inventing a private header and id format, undone the day tracing arrives;
  logging it only in the request handler, so background work in the same process loses it; treating
  "we have a correlation id" as covering the observability attribute in `04-quality-scenarios.md`
  when the recorded scenario asks for latency attribution.

## OpenTelemetry tracing, logs correlated by trace id

Instrumented components produce spans; the SDK's ambient context puts `trace_id` and `span_id` into
every log record. The join key is the trace id.

- **Use when** timing across boundaries is a recorded question, async hops must show causality, or
  the languages in use have mature auto-instrumentation for the frameworks in use.
- **Pros** one operation is one tree with durations and errors on it; auto-instrumentation covers
  HTTP, database and message clients without touching business code; the same context feeds logs, so
  no second convention exists; vendor-neutral, so the backend stays reversible.
- **Cons** the cost is per language and per framework, not per system: .NET, Java, Python, Node and
  Go have agents or one-line bootstraps, anything outside that set is manual work — and the manual
  part is where propagation quietly stops; sampling now exists and must be decided; the collector
  and backend are components someone operates and pays for.
- **Typical mistakes** believing auto-instrumentation covers async hops — producer and consumer
  usually need the context injected and extracted by hand; leaving the logging bridge unconfigured,
  so spans have ids and logs do not, the worst of both options; writing the id into logs only when
  the span is sampled; instrumenting with a vendor SDK, which makes the backend irreversible.

## Both, one wire format

Tracing where it pays, and a propagated id everywhere else — with **W3C `traceparent` as the single
wire format**, including on hops where nothing but logging exists.

- **Use when** the system is multi-component but not microservices: some parts are worth tracing,
  some will never be instrumented, and one convention beats a translation table. The default
  recommendation for the shape in the frame above.
- **Pros** the format is the standard one, so adding a traced component later needs no migration and
  every intermediary understands the header; an uninstrumented component only parses 32 hex
  characters out of a header and logs them; the trace id is the join key either way.
- **Cons** two mechanisms produce the same id, so the convention must be written down and enforced by
  review; a hand-rolled hop that forwards `traceparent` unchanged rather than updating the span id
  leaves a hole in the tree — still better than a break.
- **Typical mistakes** carrying both `traceparent` and a legacy `X-Correlation-ID` with no stated
  mapping, so two teams grep two different ids; a hand-rolled generator emitting a non-hex or
  wrong-length id, which conformant libraries discard as invalid.

`traceparent` is `00-<32 hex trace id>-<16 hex span id>-<2 hex flags>`, the lowest flag bit meaning
sampled; `tracestate` is vendor data, forwarded untouched. Business keys travel in `baggage`, which is
re-injected into every outgoing request — so no secret and no personal data goes in it, its size is
bounded on the way in, and it stops at the system boundary.

## Where the id is born, and whether to trust it

| Origin | Buys | Costs |
|---|---|---|
| Browser or client app | the click, the client-side timing and the network hop join the same story; the id is on screen for the user to quote | an unauthenticated caller chooses your id; `traceparent` must be allowed by CORS or the browser drops it silently |
| Edge proxy or gateway | one place stamps it, every component behind it inherits it, nothing internal can forget | the client's own view is a separate story unless you return the id and it logs it |
| First application component | no proxy configuration | anything ahead of it — the proxy's own access log, a redirect, a 502 — is outside every trace |

- Stamp at the edge: a missing or malformed inbound `traceparent` is replaced there, not passed on.
- Accept an inbound `traceparent` **only from a trusted caller** — an internal component or a partner
  named in `01-context.md`. From the public internet, restart the trace, as the spec expects a front
  gate to: otherwise an attacker pins every request to one id, forces the sampled flag either way, and
  merges unrelated operations. Keep the caller's id as an inbound attribute and link the new trace to
  it — the client's story survives without being trusted as the join key.
- **Return the id to the client** in a response header and in error responses. A ticket that starts
  with an id is the difference between a five-minute and a two-hour investigation.

## Every hop type

**Reverse proxy / ingress.** The proxy is a component in `03-containers.md` and its access log must
carry the id, or the front half of every story is missing. Three obligations, the same for nginx,
Traefik, YARP and a cloud load balancer: forward the header unchanged (nginx drops header names
containing underscores unless told otherwise — one reason to use the hyphenated standard name), stamp
one when absent (nginx `$request_id`), and add it to the access log format, the change people forget.

**Service-to-service HTTP.** The outgoing client injects the current context, the incoming server
extracts it. Headers only — never a query parameter (it lands in access logs and referrers), never a
body field (the body is a versioned contract). One shared HTTP client factory per component with the
propagator wired in, so a new call site cannot forget.

**Message queues and the outbox.** Inject the context into the message's **metadata**, not its payload:
the payload is a schema that will be versioned, the metadata slot will not. With an outbox, capture the
context when the row is written and store it there — the relay runs later, with a context of its own.
Then decide, per consumer, continue or link:

| Consumer starts | Fits | Because |
|---|---|---|
| a child span in the producer's trace | one message, consumed within seconds, part of the same user operation | the tree shows the whole operation, latency included |
| a new trace linked to the producer's | batching from many producers, long delay before consumption, many retries | one span has one parent, so a batch can only link; and a trace left open for hours is unusable |

Either way the producer's trace id is written into the consumer's log lines as an attribute, so the
join works even where the parent-child relationship does not.

**Scheduled and background jobs.** Every run starts its own trace, with its run id in every line of
that run; do not continue a trace from whatever caused the work, which may be days old. Where the work
has known causes, each item's originating trace id is logged with the item and its span links to that
trace. A job that logs only "processed 417 rows" is a dead end in this exact investigation.

**Webhooks out.** Send `traceparent`; the receiver is another trust domain and will probably restart,
so log your id and the delivery id their response returns. **Webhooks in.** Start a new trace and log
the provider's event or delivery id beside it in the first line — that pair is the only bridge across
an organisation boundary, and the only thing their support can act on.

**Database.** The gap most systems never close: slow-query logs name a statement, not a request. Two
mechanisms, cheapest first — set the connection's `application_name` or session context to the
component (coarse, always worth it), then append the trace context as a SQL comment on the statement
(sqlcommenter-style, since merged into the OpenTelemetry ecosystem), which makes a slow-query entry
joinable to one operation. State that second cost: a comment varying per request changes the statement
text, which affects plan caching and statement-level aggregation on engines that key on it.

## Logs are where the join happens

- **Ambient context, not a parameter.** The id lives in a context the logger reads —
  `Activity.Current`/`AsyncLocal` in .NET, MDC or the OTel context in Java, `contextvars` in Python,
  `AsyncLocalStorage` in Node. Threading it by hand through call signatures fails at the first library
  callback. Go has no ambient context: it rides in `context.Context`, so a function that does not take
  one is where it dies.
- **Enrich at the source.** A collector can add what it knows about the process (service name,
  environment, version); it cannot invent an id the process never wrote. Operation-scoped fields are
  added in-process, once, by the logging setup.
- **Sampling is the trap.** Traces are sampled, logs are not, so the trace id goes into every log
  line regardless of the sampled flag — and the flag is logged too, so the operator knows whether a
  trace exists to open. A logger that enriches only recorded spans drops the id from exactly the
  unsampled requests nobody investigated in advance.
- One field name for the join key, identical in every component and stated in the ADR — grep is the
  fallback when the backend is the thing that is down. In log fields and span attributes only, never
  in a metric label (`operations.md`, on cardinality).

## Done when

Take one recorded failing operation and follow it: the client's error report yields an id; that id
alone returns the proxy access line, every line from each service that handled it, the queue consumer's
lines, the background job that finished the work, and the database's slow-query entry if there was one
— in causal order where tracing exists. Either the walk completes, or a finding names the component
that drops the id. In `04-quality-scenarios.md`: one id, every component, within the stated minutes.

**Typical mistakes**, all from real systems: a proxy that strips the unknown header, so the id is
born twice; the id regenerated at a mid-chain component that stamps instead of accepting; a queue
consumer that starts fresh, cutting every operation in half at the async boundary; the cron job and
the database, the two places the id reliably never reaches; two teams with two header conventions
and no mapping; the id in application logs but not the access log, so the 502s that never reached
the application are invisible; the id never returned to the user, so tickets start with "around
eleven this morning".

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the reversible floor: `traceparent` stamped at
the edge, restarted for untrusted callers, forwarded on every hop and injected into message metadata;
the trace id in every log line under one field name and returned in the response header; no tracing
backend yet, since adding spans later needs no id migration. Record the trigger that would change it —
a latency question log ordering cannot answer, a second async hop, someone on call — in `07-risks.md`.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected quality scenarios and
   constraints by id, the per-language instrumentation cost, and what reversing costs.
2. Give one recommendation with its driver. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`: header and wire format, the log field name,
   where the id is born, the trust rule at the edge, the continue-or-link rule for consumers.
   Rejected options become its alternatives with the reason each lost.
4. Reference the ADR from `03-containers.md`, and annotate each edge there with what propagates on
   it. An edge that carries nothing is a finding, not a detail.
5. The retrieval property becomes an observability row in `04-quality-scenarios.md` with a number and
   a unit; a component that cannot carry the id is a row in `07-risks.md` with an owner; anything the
   human leaves open is a `TODO(question)` per `templates.md`.
