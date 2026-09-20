# Containers — image, Compose, Kubernetes

Load this when the repo already ships in containers, or when the hosting choice in
`deployment.md` has landed on containers and the depth behind that choice is now the question.
`deployment.md` owns the cross-option hosting rubric, the build/release path, and ingress, TLS
and HTTP-version networking; this file owns what has to be understood and decided once
containers are the platform.

Outputs land in `06-deployment.md` (environments, the container→runtime-unit mapping,
configuration and secret locations), in `02-constraints.md` when the platform is imposed rather
than chosen, and in an ADR per `templates.md`. Every choice below reaches the human as options
with consequences plus your recommendation, per `approaches.md`.

Docker Compose on one host is the assumed baseline: it is where most product repos start, and
every option here is measured against it. Recommend a step up only against a driver that is
written down.

## Choosing by driver

| Driver in the recorded scenarios / constraints | Candidate |
|---|---|
| One host is enough; the whole stack fits in memory; a small team owns ops | Compose on one host |
| Seconds of downtime per deploy are unacceptable (QS on availability) | Compose plus a rolling-swap tool or reverse-proxy cutover |
| Load exceeds one host, or losing the host must not lose the service | multi-node orchestration (Kubernetes, or a managed container platform) |
| Replicas must follow load automatically | Kubernetes with HPA, or a PaaS that autoscales |
| Several teams deploy independently into shared infrastructure | Kubernetes with namespaces and RBAC |
| A regulator or customer requires isolation, quotas and audited access per workload | Kubernetes, or separate hosts |
| No ops capacity at all | managed container platform — see `deployment.md` |

Nothing in that table is triggered by container count. Twenty containers on one host is a
Compose file; two containers that must survive a host failure is not.

## Image architecture

### Base image

| Family | Use when | Cost |
|---|---|---|
| Full distro (`debian`, `ubuntu`, an SDK image) | build stages, and runtimes that genuinely need a toolchain | largest surface, most CVEs to triage, slowest pulls |
| Slim (`-slim`, `-jammy`, runtime-only official images) | the default runtime base — glibc, a shell, a package manager when something must be installed | moderate surface; the shell is a real foothold after an RCE |
| Alpine | size matters more than compatibility; the stack is known to work on musl | musl, not glibc — DNS resolution, locale and native-extension differences bite late; still ships busybox and a package manager |
| Distroless / chiseled (`gcr.io/distroless`, Ubuntu chiseled, Chainguard-class) | production runtime for a compiled or self-contained app | no shell, so `docker exec` debugging and shell-based healthchecks stop working; needs a build stage that emits everything the app requires |
| `scratch` | a static binary with no runtime dependencies | you supply CA certificates, timezone data and a user database yourself |

Chiseled sits between slim and distroless for teams already on Debian/Ubuntu: the same glibc
assumptions, most of the surface removed. Match the base to what the stack reference
(`stacks/*.md`) recommends rather than choosing on image size alone.

### Build shape

- **Multi-stage is the default.** One stage compiles with the SDK, the final stage copies only
  the artifact onto the runtime base. State it as a decision only when something forces a
  single-stage build.
- **Order layers by rate of change** — dependency manifest and restore first, source last — so a
  code change does not re-download the world. A `.dockerignore` that excludes build output, the
  `.git` directory and local env files keeps the context small and keeps secrets out of it.
- **Run as a non-root user** declared in the Dockerfile, with a read-only root filesystem and
  `tmpfs` for the paths that must be writable. This is a build-time decision: retrofitting it
  onto an image whose app writes into its own install directory is a code change.
- **A rootless daemon or Podman** removes the "container root is host root on escape" class
  entirely, at the cost of extra work for privileged ports and some storage drivers. Worth
  recording on multi-tenant or customer-operated hosts.

### Identity, rot and provenance

- **A tag is a mutable pointer; a digest is the image.** `latest` and moving tags mean the host
  that pulled last week and the host that pulls today can run different code with no diff to
  show for it. Deploy an immutable tag (version or commit sha) and pin base images by digest in
  the Dockerfile, with a bot that raises the digest bump as a reviewable change.
- **Images rot even when pinned** — the base picks up CVEs whether or not anything is rebuilt.
  A pinned digest with no scheduled rebuild is an image that gets older every day. Record who
  rebuilds and on what cadence.
- **Registry choice** decides who can pull, where the bytes live and what the deploy path
  depends on: the forge's own registry (GHCR, GitLab) keeps credentials with CI; a cloud
  registry (ACR, ECR, Artifact Registry) buys workload identity on that cloud; a self-run
  registry is another thing to back up and keep available at deploy time. In every case name the
  registry and the pull credential in `06-deployment.md`.
- **Provenance** — SBOM plus a signature (cosign-class, keyless from CI's OIDC identity) —
  is only worth adding when something verifies it. Signing with no verification step is
  ceremony. Verification at admission belongs to Kubernetes-class platforms.

**Typical mistakes**: secrets baked into layers, where `docker history` still shows them after a
later `RUN rm`; running the SDK image in production because it "already works"; `latest` in the
compose file and a moving tag in the Dockerfile, so no environment is reproducible; a
`.dockerignore` that omits `.env`; distroless adopted without noticing that every healthcheck
and every debugging habit assumed a shell.

## Compose as a production platform

### What it genuinely does well

One file describes the whole stack, is diffed in review, and is the same artifact developers
run locally. One host means no cluster networking, no scheduler, no control plane to keep
alive, and a failure domain a person can hold in their head. `docker compose ps`, `logs` and
`up -d` are the entire operational vocabulary. For a stack that fits one machine and tolerates
seconds of downtime per deploy, this is a correct choice, not a stopgap.

### The limits, stated precisely

- **Single-host failure domain.** The host is the availability ceiling. Host down, or kernel
  patched and rebooted, means the service is down. Any availability scenario stricter than
  "restored by hand within the hour" is not met by one Compose host, whatever the restart
  policies say.
- **`docker compose up -d` is not a rolling update.** It compares the desired config against
  the running containers and recreates only the services whose image or definition changed —
  by stopping the old container and starting the new one. That is a gap of seconds per changed
  service, longer if the service is slow to become ready, and it is a hard cut for in-flight
  requests unless something in front drains them.
- **Scaling has a ceiling and no automation.** `--scale` or `deploy.replicas` runs several
  copies on the one host; a service with a fixed published port cannot be scaled at all. There
  is no autoscaling, no rescheduling of a failed container onto another node, and no bin-packing.
- **No secret rotation and no secret store.** Compose reads files and environment variables at
  container start. Rotating a credential means recreating the container. The store itself is a
  separate decision — see `operations.md`.

### Patterns that stretch it honestly

- **Healthchecks plus `depends_on: condition: service_healthy`.** The short `depends_on` form
  waits for the container to start, not for the service to accept connections — which is why
  dependency races survive it. Give every service a healthcheck whose command exists inside its
  own image (minimal images have no `curl`), and make dependents wait on health. The same
  healthcheck is what a rolling-swap tool later waits on.
- **Restart policies.** `restart: unless-stopped` (or `on-failure` with a bounded count) plus a
  healthcheck covers process crashes and host reboot. It does not cover a container that is up
  and wedged unless the healthcheck actually fails when it is.
- **A reverse-proxy container** (Traefik, nginx or Caddy class) as the single published entry
  point: TLS terminates there, everything else stays on the internal network, and it is what
  makes a cutover between old and new containers possible at all. Protocol and certificate
  specifics live in `deployment.md`.
- **Named volumes for state, and a backup that is exercised.** A named volume survives
  `up -d` and `down`; it does not survive `down -v` or the host. For databases, back up with the
  engine's own dump or snapshot tool — a file copy of a live data directory is not consistent.
  Retention and restore-drill policy belong to `operations.md`; what belongs here is naming
  every volume that holds state in `06-deployment.md`.
- **Environments as file layers and profiles.** A base `compose.yaml` plus an
  environment-specific override file (`-f base -f prod`) keeps one description of the stack;
  profiles switch optional services (seeders, admin tooling) on and off without a second file
  set. Prefer this to a forked compose file per environment, which drifts within a month.
- **Configuration versus secrets.** Non-sensitive settings come from an env file that is
  committed as an example and supplied per host; mandatory variables use the `${VAR:?}` form so
  a missing one fails at `up` rather than at runtime. For credentials, Compose secrets mount a
  file at `/run/secrets/<name>` rather than putting the value in the environment, which keeps it
  out of `docker inspect` and `/proc/1/environ` — the file on the host is still plaintext, so
  the real protection is host access control or an external store.
- **Update strategies, with their downtime truth.** `pull` then `up -d` — simplest, seconds of
  downtime per changed service. A rolling-swap CLI (`docker rollout` class) — starts the new
  container, waits for its healthcheck, then removes the old one; needs the reverse proxy and a
  healthcheck that means something. Swarm mode on the same host — brings real `update_config`
  rolling updates for the cost of a second mental model. An auto-updater (Watchtower class) —
  convenient for side projects, and note that the original project was archived at the end of
  2025; automatic image updates in production mean unreviewed code and unplanned database
  restarts, so scope it to nothing that holds state, or not at all.

**Typical mistakes**: `latest` everywhere, so nobody can say what production runs; dependency
races left to retries because `depends_on` looked sufficient; database ports published on
`0.0.0.0` instead of kept on the internal network, exposing them past a host firewall the
container publish path bypasses; volumes nobody has ever restored from; the production compose
file living only on the server, edited in place; a single host that has become load-bearing for
a scenario that says it must not be; `restart: always` used as a substitute for finding out why
the process dies.

## Kubernetes for the architect

The building blocks that shape a design, not a tutorial:

| Object | What it decides |
|---|---|
| Deployment + ReplicaSet | stateless replicas, rolling update strategy, rollback |
| Service | stable virtual IP and DNS name for a set of pods; the internal contract between containers |
| Ingress / Gateway API | HTTP entry from outside; Ingress is the incumbent, Gateway API the direction (the ingress-nginx project was retired in 2026, so controller choice is a live decision) |
| ConfigMap / Secret | configuration and credentials injected as env or files; Secrets are base64, not encrypted, without further setup |
| Probes (liveness, readiness, startup) | whether a pod takes traffic and when it is restarted — the rolling update depends entirely on readiness being honest |
| Requests and limits | scheduling and the OOM/throttle behaviour; no requests means no capacity guarantee |
| HPA | replica count from a metric; only meaningful for workloads that scale horizontally at all |
| StatefulSet + PVC | stable identity and per-pod storage |
| Operator (CRD + controller) | the operational knowledge for a stateful system, encoded |

**Stateful is where it gets hard.** A StatefulSet gives stable names and disks; it gives no
replication, no failover, no backup and no version upgrade path. Those are the database's
problems, and on Kubernetes they are solved by a mature operator (CloudNativePG class) or by
not running the database in the cluster at all — a managed database service is the honest
default for most product repos. A PVC is not a backup.

**Managed versus self-run.** Managed control planes (AKS, EKS, GKE) cost around $70–75 per
cluster per month on EKS and GKE and nothing on the AKS free tier — a rounding error next to
nodes, load balancers, storage and egress, which is where the bill actually is. Self-running a
control plane saves that rounding error and buys upgrades, etcd backups and certificate
rotation as a standing job. Take managed unless a constraint (air-gapped, on-premises hardware,
sovereignty) forbids it.

**What it demands of a team.** Someone who can read `kubectl describe` output and mean it;
manifests under version control with a deploy path (Helm or Kustomize plus a GitOps controller,
never `kubectl apply` from a laptop); cluster version upgrades a few times a year with API
deprecations to chase; centralised logs and metrics because pods are ephemeral; network policy,
RBAC and image provenance to actually get the isolation the platform is capable of. That is
roughly a part-time platform role that does not exist on a two-person team.

**It pays when** several teams deploy independently, load or availability genuinely exceeds one
host, replica count must follow demand, or the organisation already runs clusters and this repo
would be the exception. **It is résumé-driven when** the argument is portability in the
abstract, a future scale with no scenario behind it, or "everyone uses it" — for one stateless
app and one database, a Compose host or a managed platform does the same job for far less.

## Keeping the Compose → Kubernetes step cheap

These cost nothing on Compose today and are most of the migration bill later:

- **Honest healthchecks** map straight onto readiness and liveness probes.
- **12-factor configuration** — everything from environment or mounted files, nothing read from
  a path baked into the image — maps onto ConfigMaps and Secrets.
- **Stateless application containers.** No local session state, no work queue in memory, no
  writes to the container filesystem that matter after restart. State lives in the database, the
  cache or an object store.
- **No host-path coupling.** Named volumes, not `./data:/var/lib/...` bind mounts; no dependence
  on the host's clock skew, local files or a specific interface.
- **Reach services by name, never by published port**, and let one entry point own external
  ingress — this is exactly the Service-and-Ingress model.
- **An image built by CI and pushed to a registry**, not built on the deploy host; Kubernetes
  has no `build:`.

Conversion tools (kompose class) get perhaps three-quarters of the manifest and omit probes,
resource requests, secret handling and network policy. The generated YAML is a starting point,
never the deliverable. If a repo does the six things above, the migration is manifests plus a
cutover; if it does none of them, it is a rewrite of how the app handles state and config.

## Container networking

- **Compose** puts services on a user-defined bridge network where each service is reachable by
  its service name over Docker's embedded DNS. Container-to-container traffic needs no published
  port: `ports:` exists only to expose something to the host and, by default, to every interface
  the host has. Publish exactly what must be reachable from outside — usually just the reverse
  proxy — bind the rest to `127.0.0.1` if it must be published at all, and use separate networks
  when one group of services must not reach another.
- **Kubernetes** gives every pod its own IP; a Service is the stable name and load-balancing
  point in front of a changing set of pods, resolved as `<service>.<namespace>.svc`; an Ingress
  or Gateway carries HTTP from outside to a Service; NetworkPolicy is the only thing that stops
  any pod talking to any other, and it is off until written.
- TLS termination, certificate lifecycle and HTTP version selection are decided once for the
  system in `deployment.md` — record the container-side consequence here, not the choice.

## Recording the choice

1. Put the options to the human with the affected quality scenarios and constraints by id: for
   the platform (stay on Compose · Compose plus rolling swap · Kubernetes · managed platform),
   and for the image base where the stack allows more than one.
2. Name the downtime and failure-domain consequence of each in the terms the availability
   scenario uses, plus what it costs to move later.
3. Write the accepted choice as an ADR, the rejected ones as alternatives with the reason each
   lost, and reference the ADR from `06-deployment.md`.
4. Record the residue as risks in `07-risks.md` — the single host, the unexercised restore, the
   base image nobody rebuilds — each with an owner, per `templates.md`.
