# Machine topology — how many hosts, what fails over, who signed the number

Load this when host count is being decided, a load balancer is being added, VMs are being sized, a
database HA option is on the table, or someone says "we need high availability" with no number
attached. `deployment.md` decides what executes the process and `containers.md` decides the depth
behind containers; this file decides how many machines there are, what survives one of them dying,
and what that costs per month. `edge-proxy.md` owns which component does the balancing once this
file has established that there is more than one backend to balance.

Outputs land in `04-quality-scenarios.md` (the availability target with its number, and the
utilisation headroom rule), in `06-deployment.md` (the host inventory and the failover path), and
in an ADR per `templates.md`. Every choice below reaches the human as options with consequences
plus your recommendation, per `approaches.md`.

Machine topology is a cost-versus-availability trade to settle on paper before anyone provisions
anything. The safe default is one adequately sized host — a 4 vCPU / 8–16 GB VM covers most
internal and small-public workloads — plus automated backups and a tested restore. That is a real
recovery story and it costs one machine. Add a second app host and a load balancer only against a
recorded availability scenario: a named outage, its business cost per hour, and a target someone
signed.

Two rules cut through most of the argument. **Redundancy climbs from the stateful bottom up** — a
topology is only as available as its least redundant stateful component, so two app hosts in front
of a single database is theatre, and the first HA spend belongs on a managed multi-AZ replica (or
Patroni if it must be self-hosted, repmgr for simpler self-hosted pairs). **HA is a property you
test** — if the primary has never been killed on purpose and watched to fail over, what exists is a
diagram, not availability. Autoscaling groups and 3+ node Kubernetes pools are for genuinely
variable or large load, not for prestige; below that they cost triple and add failure modes.

Size from measured RPS and latency, not vibes: the order-of-magnitude planning numbers below get
you a first guess, and a load test gets you the real one.

## Topology ladder

| Availability target | Minimum honest topology | What actually fails over | Monthly cost class |
|---|---|---|---|
| Business hours / best effort | 1 VM + automated backups + tested restore | nothing automatically; a human restores from backup (RTO hours) | $ (~$50–200) |
| Business hours, bounded RTO | 1 VM + warm standby with WAL shipping | a human promotes the standby via runbook (RTO 15–60 min) | $ (~$80–300) |
| 99.9% (~8.7 h down/yr) | 2 app hosts + managed LB + multi-AZ managed DB | the LB drains the dead app host in seconds; the DB fails over automatically in ~1–2 min | $$ (~$300–1,500) |
| 99.95%+ (~4.4 h down/yr or less) | 3+ app nodes across AZs + managed LB + multi-AZ DB with auto-failover, all drilled quarterly | any single node, or one full AZ; failover is rehearsed, not assumed | $$$ (~$1,500–10k+) |
| 99.99%+ / multi-region | active-active regions, replicated data, global LB — a programme, not a purchase | a whole region; requires a data-conflict strategy and dedicated ops | $$$$ (10k+/mo and headcount) |

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| The availability target is "business hours", or nobody wrote one down | a single host plus a tested restore; spend the HA budget on backups and monitoring instead |
| A written 99.9% target with a business cost per hour of downtime | two app hosts behind an LB plus a managed replicated DB, with a rehearsed failover |
| A 99.95%+ target, or a contractual SLA with penalties | multi-AZ everything: 3+ app nodes, a multi-AZ DB with automatic failover, LB health checks, regular failover drills |
| Load is spiky — launches, campaigns, batch windows | an autoscaling group or scale-out PaaS; scale on a measured metric, set a maximum, and load-test the scale-up path |
| Load is small and steady (under ~50 RPS sustained) | one right-sized VM handles this with headroom; more machines is spend, not resilience |
| Ops capacity is none or limited | PaaS or managed services; self-hosted HA (Patroni plus etcd, keepalived) is an ops product you now own |
| The database is the only stateful component | make DB redundancy the first HA spend — a managed multi-AZ replica beats a second app host every time |
| Someone proposes Kubernetes "for HA" on a small system | count the nodes: honest Kubernetes HA starts at 3 plus a managed control plane; below that it is a slower, more fragile single host |

## Single host (one VM, everything on it)

- **Use when** the default case: internal tools, small-audience products, anything where hours of
  downtime is annoying but has never been costed. The availability target is "basic".
- **Pros** one machine to patch, monitor and reason about; no distributed-systems failure modes at
  all — no split brain, no session affinity, no replication lag; cheapest by two to three times,
  with a 4 vCPU VM around $50–150/mo; and enormous vertical headroom before a second box is needed.
- **Cons** host death or an AZ outage means downtime until the restore completes; deploys cause
  blips unless a graceful restart is scripted; OS patching means a maintenance window.
- **Typical mistakes** running it without a tested restore — the single-host strategy *is* the
  restore, and untested it is nothing; sizing it too small to save $30/mo and then blaming the
  topology for latency; co-locating the DB and the app but backing up only the app disk.

## Single host plus warm standby (restore-based)

- **Use when** 30–60 minutes of downtime is acceptable but a dead host must not become a dead day.
  The cheap insurance step before real HA.
- **Pros** recovery drops from "rebuild from scratch" to "promote the standby", so RTO is under an
  hour; no load balancer, no replication protocol, no consensus to operate; the standby can be
  stopped or minimal, costing a fraction of a second live host; and it doubles as the restore-test
  environment.
- **Cons** failover is manual — someone gets paged and runs a runbook; data since the last backup
  or WAL ship is lost unless WAL is streamed, which pgBackRest and wal-g make cheap; and the
  standby drifts from production unless provisioning is scripted.
- **Typical mistakes** never rehearsing the promotion, so a warm standby nobody has promoted is a
  cold guess; a hand-configured standby that no longer matches production the day it is needed;
  calling this "HA" in front of the business, when it is disaster recovery measured in minutes to
  hours, not seconds.

## Two app hosts behind an LB plus a managed or replicated DB

- **Use when** a recorded 99.9% target exists and someone has accepted the roughly two-to-three
  times cost. This is the minimum honest HA topology.
- **Pros** survives one app host dying with no user-visible downtime; zero-downtime deploys come
  free (drain one, deploy, swap); a managed DB with a multi-AZ replica moves the hardest HA problem
  to the cloud vendor; and LB health checks catch instances that are sick rather than dead.
- **Cons** the app must be stateless or you inherit sticky sessions and cache-coherence bugs; the
  load balancer must itself be redundant, which means the cloud's managed LB and not one nginx VM;
  a managed multi-AZ DB roughly doubles the database bill; and there are more moving parts —
  replication lag, health-check tuning, connection pooling across nodes.
- **Typical mistakes** two app hosts pointed at one unreplicated DB, where the database is now the
  entire availability story and the second host was paid for nothing; local file uploads or
  in-memory sessions that break the moment the LB round-robins; one self-managed HAProxy or nginx
  VM as the LB, which moves the single point of failure rather than removing it; never killing an
  app host in production to verify that the LB actually drains it.

## Active-passive pair (VIP or DNS failover)

- **Use when** the software is stateful or licence-constrained and cannot run active-active —
  legacy apps, some IIS and Windows stacks, self-hosted DB primaries. Often the database tier of a
  larger topology.
- **Pros** works for software that tolerates exactly one writer; simpler than consensus-based
  clustering when paired with keepalived, a VIP or cloud IP reassignment; and the passive node
  doubles as the place to test patches.
- **Cons** failover is the risky path and it runs least often, so automation (Patroni for Postgres)
  or a drilled runbook is mandatory; split brain is a real risk with naive VIP scripts, and fencing
  is not optional; and you pay for a node that serves no traffic, while DNS-based failover adds TTL
  delay measured in minutes.
- **Typical mistakes** homegrown failover shell scripts instead of Patroni or repmgr — the most
  re-invented and most-wrong wheel in ops; no fencing, so both nodes believe they are primary and
  there are now two divergent databases; testing failover once at setup and never again, while
  config drift silently breaks it.

## Autoscaling group or Kubernetes node pool (3+ nodes)

- **Use when** load is genuinely spiky or large, or Kubernetes is already run for other recorded
  reasons. Three nodes is the honest minimum for Kubernetes — etcd quorum and pod-rescheduling
  headroom.
- **Pros** absorbs traffic spikes with nobody awake; N+1 by construction, so one node dying is a
  non-event; rolling deploys, self-healing restarts and bin-packing of many services; and cloud
  ASGs with managed control planes (EKS, AKS, GKE) remove the worst of the ops burden.
- **Cons** baseline cost starts around three times a single host before one extra request is
  served; scale-up lags spikes by one to five minutes for VM boot plus health checks, so flash
  traffic still needs headroom; Kubernetes is a platform to operate — upgrades, CNI, ingress,
  certificate rotation — even when "managed"; and stateful services on Kubernetes via DB operators
  are advanced mode, so most teams should keep the database outside.
- **Typical mistakes** a one- or two-node Kubernetes "cluster" with no quorum and no rescheduling
  headroom, which is a single host with extra YAML; autoscaling on CPU when the bottleneck is
  database connections, which scales the app into a database pile-up; no maximum instance count,
  so a retry storm autoscales into a five-figure bill; choosing Kubernetes for a monolith at 20 RPS
  because the topology looked impressive on the diagram.

## PaaS scales it (App Service, Cloud Run, Fly.io, Heroku-likes)

- **Use when** ops capacity is none or limited and the app fits the platform's model — stateless
  HTTP with a managed DB add-on. Small teams shipping product, not infrastructure.
- **Pros** multi-instance HA and zero-downtime deploys are checkboxes rather than projects; nobody
  on the team ever patches an OS; scale-to-zero options (Cloud Run) make tiny workloads nearly
  free; and the platform's LB, TLS and health checks are better than what you would build.
- **Cons** two to five times the unit cost of raw VMs at steady scale, with the crossover usually
  around a few hundred dollars a month of sustained compute; platform limits — request timeouts,
  background work, disk — surface exactly when you least want them; the platform's outage is your
  outage and you hold no levers; and egress and add-on pricing punish chatty or data-heavy apps.
- **Typical mistakes** assuming "PaaS" means HA, when a single dyno or instance tier is still a
  single machine — pay for two or more instances if you claim 99.9%; ignoring the managed DB tier's
  own replication setting, so the app scaled and the $7 database did not; rebuilding half the
  platform in cron VMs and queue VMs beside the PaaS, losing the simplicity that was paid for.

## Rough sizing heuristics

| Workload shape | Order-of-magnitude capacity | Notes (planning numbers — measure before scaling) |
|---|---|---|
| Typical CRUD API (DB-bound, 10–50 ms/req) | ~100–500 RPS per core | compiled and async stacks (Go, .NET, JVM) sit at the top; interpreted sync stacks (Python, Ruby workers) at 10–50 RPS/core. The DB usually saturates first |
| Static or cached responses | ~5,000–20,000+ RPS per core | nginx/CDN territory; almost never your bottleneck — cache before you scale |
| CPU-heavy endpoint (rendering, crypto, ML inference) | ~1–20 RPS per core | scale equals cores; queue it and process async instead of buying web hosts |
| Postgres, transactional | ~500–5,000 simple TPS per 4 vCPU / 16 GB; keep active connections at ~2–4× cores via a pooler | the working set in RAM matters more than cores; add pgbouncer long before a bigger box |
| Memory rule of thumb | app: 1–4 GB per service process; DB: RAM ≥ hot working set | a 4 vCPU / 8–16 GB VM comfortably runs app plus DB for most systems under ~50 sustained RPS |
| Headroom rule | plan peak at ≤60–70% utilisation; in an N-node HA pool, survive N−1 at ≤80% | if losing one node overloads the rest, you do not have HA, you have a cascade |

## What holds whatever you pick

- Default to one adequately sized host plus a tested restore; add machines only against a recorded
  availability scenario with a signed target.
- Redundancy climbs from the stateful bottom up: replicate the database before duplicating app
  hosts.
- HA you have not failure-tested is a diagram. Kill the primary on purpose in a drill before
  claiming the number.
- The load balancer must itself be redundant — use the cloud's managed LB, never one nginx VM.
- Kubernetes HA starts at 3 nodes; one or two nodes is a single host with extra failure modes.
- Size from measured RPS at ≤70% utilisation: heuristics pick the first VM, load tests pick the
  second.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend one right-sized host, automated backups,
one proven restore, and no load balancer at all — then name the trigger that would change it: a
signed availability target with a cost per hour behind it, sustained load approaching the host's
headroom rule, or a stateful component whose loss is unacceptable. Each trigger is a row in
`07-risks.md` until it becomes a scenario.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the host count, what fails
   over to what, and which stateful component is the availability ceiling.
2. State the monthly cost class of each, the ops capacity it assumes, and the drill it obliges
   someone to run.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `06-deployment.md`.
4. The availability target becomes a row in `04-quality-scenarios.md` with a number and a unit, and
   the utilisation headroom rule becomes a second one. A target with no measurement behind it is
   not a scenario.
5. An untested failover, a non-redundant load balancer and an unreplicated database under a
   two-host topology are rows in `07-risks.md`, each with an owner. Anything the human leaves open
   is a `TODO(question)` per `templates.md`.
