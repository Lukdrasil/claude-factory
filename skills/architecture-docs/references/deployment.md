# Deployment — decision rubric

The catalogue you choose from before proposing or reviewing how a system runs, and the source of the
**options + consequences + recommendation** you put to the human about hosting, release, schema
change, configuration and ingress. This file decides; `06-deployment.md` records the result, and
that skeleton lives in `templates.md`.

Ground every option in what is recorded: `02-constraints.md` says where the system may run and who
operates it (`C-` ids), `04-quality-scenarios.md` what it must achieve (`QS-` ids). An option that
no constraint and no quality scenario distinguishes is not a real option; ask for the missing
scenario instead of guessing.

## Four decisions, decided separately

| Decision | Question | Choices |
|---|---|---|
| Hosting / runtime | what executes the process, and who operates it | IIS or Windows Service · systemd on a VM · containers on a VM · Kubernetes · PaaS · FaaS · bare metal |
| Release path | how a build reaches an environment | rebuild vs promote · rolling · blue-green · canary · feature flags |
| Schema change | when the database changes relative to the code | expand/contract · on startup vs pipeline step |
| Configuration | where per-environment values come from | env vars · files · config services |

Hosting caps release: an option cannot perform a rollout shape it has no traffic control for.
Networking cuts across all four and is at the end. Once the hosting choice lands on containers or
Kubernetes, `containers.md` owns the depth behind it; the option-level comparison stays here.

## Choosing by driver

| Driver in the recorded constraints / scenarios | Candidates to put on the table |
|---|---|
| Windows hosts, Windows authentication, an ops team that already runs them | IIS, Windows Service |
| A few long-lived Linux processes, no orchestration need | systemd, containers + compose on a VM |
| A pinned reproducible environment; one host is enough; or delivery into a customer's own infrastructure | containers + compose on a VM |
| Units with different scaling and release cadence, teams shipping independently, someone on call | Kubernetes, managed control plane |
| Ordinary HTTP services, no ops capacity, a permitted cloud | PaaS |
| Event-driven, bursty, low duty cycle; cost must follow usage | FaaS |
| Recovery in minutes without a human | anything with health-gated rollout and one-step rollback: Kubernetes, PaaS, blue-green on a VM pair |
| Hardware-bound: GPUs, a host-locked licence, data that may not leave the room | bare metal, under any of the above |

## IIS or a Windows Service

- **Use when** constraints put the app on Windows hosts someone already operates, Windows
  authentication or a Windows-only dependency is in play, and the deployable count is small.
- **Pros** the host, its patching and its supervision already exist; IIS supplies bindings, the
  certificate store, app-pool recycling and process restart without extra software.
- **Cons** the host is mutable, so what is installed on it is a fact nobody recorded; deploy is a
  file copy against a running process; two versions on one host need separate sites and pools.
- **Operating cost** monthly OS patching with a reboot window; renewal must rebind the certificate
  to the binding or expiry is a night call; whoever holds RDP is the operator, usually one person.
- **Typical mistakes** publishing from a workstation, so the artifact has no traceable source;
  configuration differing between hosts and discovered during an incident; no retained N-1 artifact,
  so there is nothing to roll back to; treating a hand-built host as reproducible.

## systemd on a VM

- **Use when** Linux, one to a few long-lived processes, and the team wants the smallest thing
  above a bare binary.
- **Pros** supervision, restart policy, resource limits, ordering and the journal come from the OS;
  one unit file per service; the artifact is a directory.
- **Cons** no orchestration — placement, rollout and scaling are yours; the VM drifts from any
  declared state without configuration management; two versions on one host clash over ports.
- **Operating cost** OS patching and reboots; ACME renewal with a reload hook; log rotation and
  disk; rollback is a script you own and exercise rarely.
- **Typical mistakes** deploying by pulling git on the host; a unit file that lives in no repo; no
  readiness check, so a process that started but cannot serve counts as up; secrets in
  `Environment=`, printed by any `systemctl show`.

## Containers and compose on a VM

- **Use when** a pinned reproducible environment matters, one host is enough capacity, and
  Kubernetes buys nothing the scenarios ask for. The standard shape for shipping into a customer's
  own infrastructure.
- **Pros** the image is the environment, identical everywhere; rollback is running the previous
  digest; the topology is a compose file in the repo; the host stays nearly empty.
- **Cons** one host is one failure domain — no rescheduling, and a reboot is downtime; compose has
  no real rolling update; volumes, backups and their restore drill are yours.
- **Operating cost** host patching plus image rebuilds for base-image CVEs, a standing security
  debt; a registry with retention and pull credentials; TLS at a proxy container; disks filling with
  old images and logs is the routine night call.
- **Typical mistakes** deploying `latest`, so nobody can say what ran; building the image on the
  host; the database in the same compose file with a backup nobody has restored; bind-mounted
  configuration no repo tracks; presenting "it is containerised" as an availability story.

## Kubernetes

- **Use when** several independently deployable units genuinely need per-service scaling,
  health-gated rollout and self-healing, more than one team ships, and someone is on call. Managed
  control plane unless a constraint forbids the cloud.
- **Pros** declarative state and reconciliation; rolling, blue-green and canary with automated
  metric gates (Argo Rollouts, Flagger); rollback is a revision switch; migrations fit as a Job or
  init container; config, secrets, cron and autoscaling are platform primitives.
- **Cons** every team member pays for a large abstraction; the cluster is itself a distributed
  system with its own failure modes; networking and policy are a project of their own; debugging
  needs centralised logs and tracing that have to exist first.
- **Operating cost** the managed control plane, roughly $70–75 per cluster per month (AKS free
  without the higher uptime SLA), is not the real cost. Upgrades are: a cluster version every few
  months plus node images, each with removed APIs and controller compatibility to check — order of
  8–15 hours a month for a small cluster, plus etcd backup, control-plane HA and certificate rotation
  when self-run. Also plan the ingress migration: `kubernetes/ingress-nginx` reached end of life in
  March 2026 and gets no CVE fixes, so new clusters take a Gateway API implementation and existing
  ones need a scheduled migration (`ingress2gateway`). Still running it is a finding.
- **Typical mistakes** a cluster for three deployments, or a cluster per service; no resource
  requests, so the first noisy neighbour takes the node; no PodDisruptionBudget, so a node drain does
  what a deploy would not; a readiness probe returning 200 before dependencies are reachable, which
  makes every rollout gate pass; the platform work hidden outside the delivery estimate.

## PaaS (App Service, Cloud Run, Container Apps, Fly.io class)

- **Use when** the workload is ordinary HTTP, ops capacity is near zero and a specific cloud is
  permitted. The right default for a team that would otherwise run Kubernetes badly.
- **Pros** no host to patch and no listener to place; certificates issued and renewed by the
  platform; revisions or slots give blue-green and traffic splitting with no extra tooling;
  rollback is a traffic shift; scale-to-zero and threshold autoscaling where offered.
- **Cons** the platform's limits become your architecture — request timeout, payload size, what may
  run outside a request, what "idle" means; scale-to-zero puts a cold start on the tail of every
  latency scenario; private networking and egress are the awkward part; at steady load it costs more
  than a VM; the configuration does not port, not even to another PaaS.
- **Operating cost** near zero to run; what remains is pinning the platform's runtime version,
  watching quota and spend, and reading changelogs — it retires runtimes on its own schedule.
- **Typical mistakes** background or scheduled work inside a request-scoped runtime that may be
  recycled between requests; websockets or SSE against an idle timeout nobody read; configuration set
  by hand in the portal, so no environment is reproducible; claiming both scale-to-zero and a p95
  latency scenario; a database left publicly reachable because private networking cost more.

## Serverless / FaaS

The architectural side is in `approaches.md`; these are the deployment deltas.

- **Use when** work is event-driven or bursty with a low duty cycle and fits the execution-time,
  memory and payload limits. Sizing, patching and placement all disappear, cost follows usage, and
  versions with aliases give traffic-shifted rollout and immediate rollback.
- **Cons** cold starts land on the latency tail — sub-200 ms for a small script runtime, seconds for
  a large framework; snapshotting (Lambda SnapStart, GA for Java, Python and .NET) cuts it,
  provisioned concurrency removes it and bills for idle, trading away the reason you came; hard
  timeouts; connection-pool pressure from a fan of instances; the strongest lock-in here.
- **Operating cost** no hosts; the recurring cost is runtime deprecation — a forced upgrade per
  language every year or so, on a deadline you do not set.
- **Typical mistakes** sizing memory by guess when memory also buys CPU; a latency scenario written
  for the warm path only; per-function pipelines with no promotion between environments; long jobs
  squeezed under the timeout instead of moved off it.

## Bare metal

Owning the hardware is a separate decision from the runtime on top, which is still one of the
options above — usually systemd, containers or a self-run cluster.

- **Use when** a constraint names the hardware — GPUs, a host-locked licence, storage the cloud does
  not sell, data that may not leave a room — or load is steady and large enough that the cloud
  premium exceeds an operator's salary. Buys control, predictable performance and no per-hour bill.
- **Cons and operating cost** capacity is a purchase with lead time and there is no API for a new
  host; redundancy is bought twice; firmware, disks, spares and a physically reachable person;
  disaster recovery must be rehearsed, because there is no other region to fail into.
- **Typical mistakes** choosing it on cost for a workload idle most of the day; one machine presented
  as production; backups on that machine; the build environment being that machine.

## Build and release path

- **Build once, promote the artifact.** One build per commit, referenced by content — an image
  digest, not a moving tag. Every environment deploys that exact artifact and differs only in
  configuration; a rebuild per environment means what was tested is not what shipped.
- **Pipeline shape.** Push (CI holds the credentials and deploys) is simpler and fits VMs, IIS and
  PaaS. Pull/GitOps (a controller reconciles the environment from a git revision) keeps production
  credentials out of CI and makes environment state auditable; it earns its setup on Kubernetes.
- **Rollout shapes.** Rolling replaces instances gradually and requires N and N-1 to coexist.
  Blue-green switches all traffic at once, needs double capacity for the window, and does not roll
  back the shared database. Canary shifts a traffic fraction behind a metric gate that promotes or
  aborts, and needs per-request traffic control plus a metric worth gating on.
- **Rollback reality.** Real rollback returns to N-1 without a human editing the running system:
  Kubernetes a revision rollback, PaaS a previous revision or slot, containers the previous digest,
  FaaS an alias move; systemd and IIS only if the N-1 artifact is kept on the host and the deploy
  script can select it — usually true on paper, untested in practice. **The database breaks all of
  them**: code rolls back, schema does not. The claim holds only if the previous version still runs
  against the current schema, which is what expand/contract buys — record it once exercised, not
  before.
- **Feature flags** decouple release from deploy: ship dark, enable for a cohort, disable in seconds
  with no deploy — the only rollback that still works after the schema moved forward. The cost is a
  live branch tested both ways; give every flag an expiry, and one past it is debt in `07-risks.md`.

## Schema migration

- **Expand/contract by default** wherever two code versions can be live at once — every rolling
  deploy, every canary, every blue-green over a shared database. Add the new shape additively;
  deploy code that writes both and reads the old; backfill in batches; deploy code that reads the
  new; contract in a later release, as its own deploy.
- **Migration as a pipeline step, not on startup.** Startup migration races the other replicas, ties
  migration time to the readiness probe, and leaves the deploy no point at which to stop before the
  code arrives. Run it as a job, an init container or a reviewed script or bundle that must succeed
  before the new version rolls. EF Core 9 and later lock the database in `Migrate()`, which removes
  the race but not the coupling; on-startup stays acceptable only for a single instance.
- **Long locks are downtime under another name.** Index builds, column rewrites and defaulted
  backfills lock large tables — use the engine's concurrent or online form, batch the backfill, and
  set a statement timeout so an unbounded lock fails the deploy instead of taking the system down.
- **Zero-downtime is a property of the migration strategy**, not of the hosting option. The claim in
  `06-deployment.md` is false unless it names the approach keeping N-1 and N on one schema.

## Configuration

- **The boundary**: what differs per environment (endpoints, sizes, toggles, credentials) comes from
  the environment; what is identical everywhere is in the artifact. Twelve-factor's rule holds at
  that boundary and no further.
- **Environment variables** suit a small flat set — on every platform, present before the process
  starts, nothing to mount. They break down for anything structured or large (process environment is
  a global, untyped, size-limited blob inherited by children and captured in crash dumps and debug
  endpoints), and rotating a value means a restart.
- **Files** — mounted configuration or a secret volume — carry structure and size, reload without a
  restart and keep secrets out of the process environment; whatever places the file is where drift
  enters.
- **Config services** (App Configuration, Parameter Store and their kind) give one place, an audit
  trail and change without redeploy, at the price of a runtime dependency in the startup path and a
  second source of truth. Secret stores are the same decision stricter, and `operations.md` owns it.
- **Drift is the real failure mode.** Declare the key set once in the repo and validate it at startup
  into a typed options object, failing fast on a missing or unparsable key rather than at first use.
  An undeclared key present in one environment is drift; so is a default only production overrides.
- **Never in the artifact**: secrets, and any value that differs between environments.
  `06-deployment.md` records names and locations, never values.

## Networking

- **Ingress** follows from the hosting choice, not from preference: PaaS and FaaS bring their own; a
  VM uses nginx, Caddy or Traefik, or YARP where the routing rules deserve to be application code
  with tests; Kubernetes uses a Gateway API implementation (see the retirement note above), usually
  with a cloud load balancer still in front.
- **TLS termination point.** Record where the cipher ends — at the edge or CDN, at the proxy, or in
  the process. Terminating early gives one place for certificates and renewal; in the process is what
  an end-to-end-encryption or client-certificate constraint forces; re-encrypting to the backend costs
  a second certificate lifecycle. Whoever terminates owns renewal, and unautomated renewal is a
  scheduled outage.
- **Protocol version.** HTTP/1.1 is the safe default every intermediary understands. HTTP/2 matters
  where many concurrent streams share a connection — gRPC requires it, and SSE over it escapes the
  browser's per-host connection limit; a proxy speaking h2 to the client commonly speaks h1 to the
  backend, so a gRPC backend needs that hop configured. HTTP/3 (QUIC over UDP 443) helps on lossy
  and mobile networks and survives network changes, but needs UDP 443 open end to end and falls back
  silently where a network blocks it — measure it, never claim it in a quality scenario.
- **Long-lived connections.** Websockets and SSE die on defaults: proxy read and idle timeouts (often
  60 s) must exceed the application heartbeat interval, response buffering must be off, and
  websockets need the upgrade headers forwarded. Prefer SSE where traffic is server-to-client only —
  ordinary HTTP survives more intermediaries unchanged. Across instances, websockets need sticky
  sessions or a backplane, and sticky sessions weaken rolling deploys because every deploy drops
  every connection — so client reconnect and resume is part of this decision.
- **Service discovery.** Prefer the platform's own — DNS names in Kubernetes, the PaaS's service
  names, a load balancer address on VMs. A separate registry (Consul, Cloud Map) earns its keep when
  the fleet spans platforms. A service mesh answers discovery and also brings mTLS, retries and
  traffic policy; it is worth its operating cost only when two of those are recorded requirements.
- **Internal versus external traffic.** Keep the surfaces separate: a public ingress for what users
  reach, private addressing for service-to-service and for admin, health and metrics endpoints. Which
  endpoints are reachable from outside belongs in `06-deployment.md`; "not linked anywhere" is not a
  boundary.
- Listener and host specifics for one stack — Kestrel endpoints and forwarded headers, an ASGI
  server's worker model, a proxy-trust setting — belong in `stacks/<stack>.md`, not here.

## When the evidence is thin

Recommend the smallest operating surface that still satisfies the recorded scenarios: one artifact
built once and promoted by digest, hosted on whatever the team already operates, released as a rolling
deploy over real health checks, migrations as a pipeline step in expand/contract form, configuration
from the environment with fail-fast validation, TLS terminated at one proxy. Name the trigger that
would change it ("a second team needing its own release cadence", "the availability scenario reaching
two nines") as a risk in `07-risks.md`.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected `QS-` and `C-` ids, the
   operating cost in whose hours, and what changing it later costs.
2. Give one recommendation with the driver behind it. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected options as its alternatives
   with the reason each lost.
4. Create `06-deployment.md` only when its criterion in `templates.md` is met, and have it reference
   the ADR; when the criterion is not met, the decision is still an ADR.
5. Untested rollback, unautomated certificate renewal and a retired ingress controller are rows in
   `07-risks.md`, not sentences in the deployment document. Anything the human leaves open is a
   `TODO(question)` in the affected document, per `templates.md`.
