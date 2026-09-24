---
written_against: ".NET 10, ASP.NET Core 10, Aspire 13.5, Blazor Web App, EF Core 10"
---

`written_against` names the stack this rubric was checked against: in `audit`, a finding that
contradicts it means the profile predates the solution, not that the solution drifted — say which.

# .NET stack profile

`approaches.md` decides the shape (how many deployable units, how the code inside one is organised,
how they talk). This file decides what those units *are* in .NET — which project types to propose,
and what each choice costs. Put every option to the human the same way: options, consequences,
recommendation. An invented Orders API solution (AppHost, ServiceDefaults, an `Orders.Api`
minimal API, an `Orders.Worker` background worker, PostgreSQL) is used below only as a worked example.

Consequences that belong in a document, not in a conversation: a render mode that needs websockets
is a deployment constraint (`02-constraints.md`, `06-deployment.md`); a project boundary is what
tasks get cut along; a public contract (OpenAPI, `.proto`, an event schema) is a container edge in
`03-containers.md`.

## API projects

### Minimal APIs

The default for a new HTTP surface in .NET 10. Endpoints are mapped onto route groups; groups carry
auth, filters and metadata for everything under them.

- **Use when** the surface is yours to shape, policy is uniform per group, and handlers are small.
- **Pros** handlers written as named static methods are ordinary functions — unit-testable without a
  host; groups make the policy visible in one place; lowest per-request overhead; native-AOT capable.
  .NET 10's `AddValidation` (source-generated, DataAnnotations on parameters and records, errors via
  `IProblemDetailsService`) removes the historical reason to reach for controllers.
- **Cons** nothing enforces structure — the framework is happy with a thousand-line `Program.cs`;
  cross-cutting concerns you would have got from MVC conventions (custom binders, an application
  model) are yours to build.
- **Typical mistakes** inline lambdas, which are reachable only through `WebApplicationFactory`, so
  every test becomes an integration test; every endpoint mapped in `Program.cs`, which turns the
  startup file into the merge-conflict point of every parallel task; repeating `RequireAuthorization`
  per endpoint instead of on the group, so one forgotten call is an open endpoint.

### Controllers

- **Use when** you need model-binding extensibility (`IModelBinderProvider`/`IModelBinder`),
  `IModelValidator`, application parts or the application model (conventions applied across many
  endpoints, or controllers discovered from plugin assemblies), or OData.
- **Pros** attribute conventions apply uniformly across a large surface without repeating group
  configuration; the class is the natural unit for a task and for constructor-injected tests.
- **Cons** more ceremony per endpoint; the filter pipeline is a second dispatch mechanism to learn
  alongside middleware; slower per request than minimal APIs.
- **Typical mistakes** choosing controllers "for structure" when a group-per-capability gives the
  same structure; mixing both styles with two different validation and error-shaping paths, so the
  API answers a bad request two different ways.

### Keeping the startup file thin

One `Map<Capability>Api(this IEndpointRouteBuilder)` extension per capability, one file each,
`Program.cs` reduced to composition. That is what makes an endpoint group a unit of work: one group
= one file = one task = one branch, with no shared file to conflict on. `Orders.Api`'s
`Program.cs` is 25 lines of registrations plus `app.MapOrders()`.

For integration tests, `WebApplicationFactory` needs the entry point visible — `public partial class
Program;` at the foot of `Program.cs`. Decide once whether the test seam is the host or the handler;
both is fine, silently having only the host is not.

### gRPC and SignalR

- **gRPC** when both ends are yours, calls are service-to-service, and throughput or a code-generated
  polyglot contract matters. Costs: no browser client without gRPC-Web (which drops client and
  bidirectional streaming) or JSON transcoding; HTTP/2 end to end, so every proxy hop is now a
  constraint; the `.proto` becomes a build-time dependency of every consumer.
- **SignalR** when the server pushes to clients that did not ask — broadcast, live status, progress.
  Costs: connection state per client, sticky sessions or a backplane once there is more than one
  instance. It is not a request/response transport; if the caller waits for one answer, use HTTP.

### OpenAPI and versioning

`Microsoft.AspNetCore.OpenApi` generates the document (3.1 by default in .NET 10, JSON Schema
2020-12); no UI ships with it, so Scalar or Swagger UI is a separate, explicit choice.

The decision to record is what the document *is*: a published contract — generated at build time via
`Microsoft.Extensions.ApiDescription.Server`, committed, diffed in CI, breaking changes visible in
review — or a development convenience served at runtime in `Development` only. Choose versioning
before the first consumer outside the repo; retrofitting it means touching every route.

Note for existing apps: from .NET 10 API endpoints under cookie auth return 401/403 instead of
redirecting to a login page. Clients that relied on the redirect break.

## Web and UI projects

### Blazor Web App render modes

The mode decides where component code runs, and therefore what it may touch and what it costs.

- **Static SSR** — HTML per request, no interactivity, no per-user server state.
  - *Use when* the page is content, a form post, or read-heavy; and for anything that must read or
    write cookies or `HttpContext` (sign-in, sign-out, culture) — those only work in a request cycle.
  - *Pros* cheapest to run and to scale; enhanced navigation and streaming rendering give much of the
    feel of interactivity for free.
  - *Cons* every interaction is a navigation or a form post.
  - *Mistakes* writing `@onclick` handlers on a statically rendered page and wondering why nothing
    happens.
- **Interactive Server** — components run on the server, DOM diffs travel over a SignalR circuit.
  - *Use when* the UI is internal or latency-tolerant, the data is server-side, and you would rather
    not build an API just to feed your own UI.
  - *Pros* full server access from component code, no API layer, tiny download, works on thin clients,
    no app code shipped to the browser.
  - *Cons* every interaction costs one round trip, so the latency scenario is bounded by RTT; server
    memory per browser *tab*, not per user; no offline; a dropped connection is a visible reconnect.
  - *Mistakes* treating the circuit as free and putting large object graphs in component state;
    ignoring that scale-out now requires session affinity.
- **Interactive WebAssembly** — components run in the browser.
  - *Use when* the client must work offline or on flaky networks, client CPU should do the work, or
    the UI should be servable as static files behind a CDN.
  - *Pros* no per-user server state; interaction latency is local; the server becomes a plain API.
  - *Cons* first load downloads the runtime and app bundle; you now own an API contract for every
    piece of data the UI needs; nothing in client code is secret.
  - *Mistakes* assuming a `DbContext` or a connection string can be injected client-side.
- **Interactive Auto** — server first, WebAssembly once the bundle has been fetched.
  - *Use when* first interaction must be fast *and* later sessions should run client-side.
  - *Pros* both profiles without asking the user to wait.
  - *Cons* the same component must run correctly in both places, so every service it depends on needs
    a server and a client implementation; the `.Client` project boundary becomes structural, and
    components addressed by Auto or WebAssembly must live there.
  - *Mistakes* picking Auto for convenience and then writing server-only code in it — this fails on
    the second visit, not the first, which is the worst time to find out.

**Prerendering traps** (interactive modes prerender by default): initialisation runs twice, and state
does not survive the switch unless persisted — `[PersistentState]` in .NET 10. Persisted state is
transferred to the browser, so under WebAssembly or Auto it is public; a large payload can exceed the
circuit's message limit and the circuit then fails to start. `HttpContext` exists only during static
SSR and prerender: cookie-based sign-in pages stay statically rendered inside an otherwise
interactive app (`[ExcludeFromInteractiveRouting]`).

### When MVC or Razor Pages beats Blazor

Content, SEO and form-post pages; a team already fluent in MVC; a need for direct control of the HTTP
and caching pipeline; an existing MVC app that needs a few pages rather than a new model. Blazor's
component model is worth its cost when the page holds interactive *state*, not when it renders data.

### When a separate SPA against an API beats both

The frontend is owned by JS/TS people; the same backend must also serve mobile or third parties, so
the API exists regardless; UI and API must ship on separate cadences. Cost: two build chains, an API
contract that is now public, duplicated models, and token or BFF-cookie handling you would not have
needed with server-rendered UI.

### Hosting and the listener (this file owns these)

The render mode chosen above lands here as a deployment constraint.

- **Kestrel as edge** — simplest topology; Kestrel terminates TLS. You own host filtering, rate
  limiting and connection limits, and you must *not* enable forwarded-headers processing, or any
  client can spoof its scheme and IP.
- **Behind IIS / nginx / YARP / a cloud front end** — the proxy terminates TLS and centralises
  routing; the app needs forwarded headers with a trusted-proxy list, or every redirect and every
  logged IP is wrong. For interactive Server or SignalR the proxy must pass websocket upgrades and
  hold idle connections open far longer than a default HTTP timeout.
- **Scale-out** — circuits and SignalR connections are pinned to one process. More than one replica
  means session affinity (or a SignalR backplane / Azure SignalR), and a shared Data Protection key
  ring, which is a piece of infrastructure someone must provision.
- **Protocols** — gRPC needs HTTP/2 on every hop; IIS out-of-process hosting proxies to Kestrel over
  HTTP/1.1, so gRPC does not survive it. HTTP/3 is supported by Kestrel and by IIS on Windows Server
  2022+ with the feature enabled; treat it as an optimisation that falls back, never as a dependency.

## Composition

### Aspire (AppHost + ServiceDefaults)

- **Use when** the solution starts more than one process locally — API plus UI plus a database or
  broker — and you want one command to run it and traces across it from the first day.
- **Pros** the local topology is code rather than a compose file that drifts; connection strings,
  environment and service discovery are derived from the resource graph; the dashboard gives logs,
  traces and metrics with no vendor decision; `aspire publish` emits Compose files, Kubernetes/Helm
  charts or Bicep, and `aspire deploy` applies them (Compose, Kubernetes, AKS, Azure Container Apps,
  Azure App Service).
- **Cons** every service references ServiceDefaults, so its choices — the OpenTelemetry pipeline, the
  health and liveness endpoints, the HttpClient resilience handler — become house defaults inherited
  everywhere; the AppHost runs at development and publish time only, so anything hand-tuned in the
  deployed environment silently diverges from the model unless the model stays the source; the
  AppHost is a real program (parameters, secrets, container arguments) that no test covers by
  default; the SDK version is a solution-wide upgrade on a fast cadence.
- **Plain compose is enough** for a single service plus a database, or where an ops team already owns
  the deployment files and will not take generated ones. ServiceDefaults is usable on its own if all
  you wanted was OpenTelemetry.
- **Typical mistakes** logic in the AppHost that belongs in a service; editing the generated manifest
  by hand and calling it the deployment; keeping a hand-written compose file *and* an AppHost without
  recording which one production follows. If the Orders API kept both, that split would be a
  decision, not an accident.

### Background work

| Option | Use when | Costs |
|---|---|---|
| Hosted service inside a web app | work is short, in-process, tied to the app's lifetime, and losable on shutdown | it scales with web replicas — N replicas run N copies unless there is a lock or leader; it competes with requests for CPU; an unhandled failure in it can take the host down |
| Separate worker project | the work has its own schedule, scaling or failure profile, or must not be duplicated by web scale-out | another deployable, another configuration and telemetry surface, and a way to hand it work |
| Queue-driven | work must survive restarts, absorb bursts, or have retry and dead-letter semantics | a broker to operate, idempotent handlers, poison-message handling |

The Orders API runs the second shape: `OrderExpiryService` and `PaymentPoller` live in `Orders.Worker`,
so scaling `Orders.Api` out does not duplicate them. The worker itself assumes a single instance, a
risk to record in `07-risks.md` with the trigger (a second worker replica) that changes the answer.

## Data access

- **EF Core** when the model is aggregate-shaped, writes dominate, and schema change should be
  versioned. Consequences: migrations become an ordered step in every deployment; the `DbContext` is
  scoped and never crosses a background thread or a Blazor circuit; a query one LINQ operator away
  from client evaluation or an N+1 will pass every mocked test.
- **Dapper or raw SQL** when reads dominate, the SQL *is* the design, or the shape is a report.
  Consequences: mapping, schema-change safety and type drift are yours; there is no migrations story
  unless you adopt one separately.
- **Mixed** — EF Core for writes, Dapper for reporting queries — is a normal answer, and one to write
  down rather than let happen per file.

Whichever wins sets the testing boundary: query behaviour is only proven against a real database
engine. Tests over a mocked repository prove the caller, never the query.

## Recording the choice

Project types and their responsibilities go in `03-containers.md`; the hosting and protocol
consequences above go in `02-constraints.md` and `06-deployment.md`; latency, scale-out and
availability consequences go in `04-quality-scenarios.md`; the option that was rejected and why goes
in an ADR, per `approaches.md`. Anything the human leaves open becomes a `TODO(question)` line.
