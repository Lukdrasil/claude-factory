# Operations — decision rubric

What running the system in production forces someone to decide, and the options you put to the human
for each. Companion to `approaches.md`: that file settles the shape of the system, this one settles
what operating it costs and who carries it.

Every area below ends in exactly one of three places: a row in `04-quality-scenarios.md` (an
operational property with a number and a unit, under one of that document's attributes), a row in
`02-constraints.md` (a platform, a contract or a regulator already decided), or a recorded
not-applicable naming the area and why. Silence is the fourth place and is not allowed —
`04-quality-scenarios.md` fails its "Done when" while an attribute is neither covered nor excluded.

The rule from `approaches.md` holds here. At least two options, the consequence of each stated
against scenario and constraint ids, your recommendation with the driver behind it. The human picks.

## Choosing by driver

| Signal in the repo or the interview | Area it forces | Options to put on the table |
|---|---|---|
| Any credential reaches a running process (connection string, API key, signing key) | Secrets | managed cloud store · self-run Vault/OpenBao · in-cluster sync operator · encrypted in git · platform config |
| Someone will be paged, or "why was it slow" has to be answerable after the fact | Observability | self-run stack · SaaS backend · cloud-native backend |
| More than one replica, or a scheduler that can move or restart the process | Health and lifecycle | probe semantics, drain timing, where resilience policy lives |
| Remote calls between units, or to an external system from `01-context.md` | Timeouts and retries | calling code · service mesh · edge gateway |
| Data that cannot be recomputed from another source | Backup and restore | snapshots · PITR · logical dumps |
| Personal data, or any retention or deletion obligation | Data protection | retention per data class, erasure path, key ownership |
| One process, one operator, data derivable from a source of truth | — | record the not-applicable and move on |

## Secrets

### Managed cloud secret store (Azure Key Vault, AWS Secrets Manager, GCP Secret Manager)

- **Use when** the workload runs in one cloud and can authenticate with a platform identity
  (managed identity, IRSA, workload identity) instead of a bootstrap credential.
- **Pros** nothing to operate; access control, versioning and an access audit log come from the
  platform; rotation hooks exist; cost is negligible at ordinary secret counts.
- **Cons** per-call charges and latency make a cache with a TTL mandatory; a second cloud or an
  on-prem component needs a second store or a sync; the protection is only as good as the surrounding
  IAM model; leaving the cloud rewrites the retrieval path.
- **Typical mistakes** one static client secret used to fetch every other secret, and nobody rotates
  it; fetching per request instead of caching; one store shared by production and development, so a
  laptop holds a production credential; versioning on and pruning never, so the old value is readable.

### Self-run Vault or OpenBao

- **Use when** secrets cross clouds or leave the cloud, short-TTL dynamic database credentials are a
  stated requirement, or the audit trail must be yours. Requires a team that will run an HA service
  on the critical path of every start-up.
- **Pros** dynamic secrets expire on their own, so a captured credential dies in minutes; one policy
  model across clouds and on-prem; every access is logged; PKI and transit remove homegrown crypto.
- **Cons** every deploy and restart depends on it being up; HA means a quorum with its own backups,
  upgrades and restore drill; seal, policy and token lifecycle knowledge sits with few people. The
  hosted variant is the same decision with the operations bought instead of staffed.
- **Typical mistakes** manual unseal with three key holders, so a 3 a.m. restart needs three people —
  auto-unseal against a cloud KMS, and record where that key lives; no snapshot of the storage
  backend, so a corrupt cluster loses every secret; root tokens handed out as ordinary credentials;
  running it while no dynamic secret is used, which buys the weight and no benefit.

### Kubernetes Secrets fed by an external-secrets operator

- **Use when** the workload is on Kubernetes and one of the stores above is the source of truth: the
  operator syncs values into native Secret objects, so applications read env vars and files and know
  nothing about the store.
- **Pros** applications stay platform-neutral; ownership, rotation and audit stay in the store; no
  ciphertext in git; one set of manifests over several backends.
- **Cons** the Secret object is a cache, so cluster RBAC and etcd join the blast radius; sync lag
  means rotation is not instant and running pods need a restart trigger; refresh frequency drives the
  store's API bill.
- **Typical mistakes** etcd encryption at rest left off, so base64 is the only barrier; namespace read
  access granted team-wide — RBAC drift, not an etcd attack, is how these leak; no reload on rotation,
  so the new value is live and the pods use the old one; a cluster-wide store any namespace can pull.

### Encrypted in git (SOPS, sealed-secrets)

- **Use when** the deployment must be reconstructable from the repository alone — air-gapped or
  customer-run installs, GitOps with no external store — and the secret set is small.
- **Pros** one source of truth with the manifests; review and history per change; nothing to run.
- **Cons** rotation is a commit, so it happens when someone remembers; ciphertext is permanent in
  history, so a compromised key leaks every past value; the decryption key is itself a secret needing
  a home, a backup and a rotation story.
- **Typical mistakes** no backup of the controller or age key, so every sealed value dies with the
  cluster; per-developer keys never revoked when someone leaves; the same encrypted values copied
  between environments; "it is encrypted in git" offered as compliance without naming the key holder.

### Platform configuration and environment variables

- **Use when** the platform stores the value encrypted for you (CI/CD secret variable, app setting,
  systemd credential), there is one deployment target and few secrets. Genuinely sufficient there —
  do not sell a secret store to a system with four secrets and one environment.
- **Pros** nothing extra to run or learn; already wired into the deploy.
- **Cons** no rotation, no versioning, no per-access audit; visible to anyone who can edit the
  pipeline or the app settings; each environment is a hand-maintained copy that drifts.
- **Typical mistakes** the value printed by an echo, a debug dump or a crash handler — CI logs and
  error reporters are the most common leak path there is; a `.env` committed "temporarily"; one
  credential shared by production and staging; deploys run from a laptop, which then holds them.

Whatever is chosen: `06-deployment.md` records where secrets live and never a value, and the rotation
interval with its owner becomes a security row in `04-quality-scenarios.md`. A rotation with no
interval and no owner does not happen.

## Observability

OpenTelemetry instrumentation exporting OTLP through a collector is the default wire: it separates
the instrumentation decision from the backend decision, so the backend stays reversible. Deviating
from it needs a reason recorded as a constraint.

| Signal | Answers | Decide | Lands as |
|---|---|---|---|
| Logs | what happened inside one request | structured or free text, the fields always present, trace/correlation id propagation, retention window | retention in days; a scenario for retrieving every line of one request |
| Metrics | is it healthy now, how much headroom is left | RED per request-driven service, USE per resource; which labels are allowed to exist | the thresholds and percentiles other scenarios reference |
| Traces | where the time went across a boundary | auto-instrumentation vs explicit spans; head vs tail sampling and the rate | sampling rate; retention of an error trace |

- **Typical mistakes** a metric label carrying a user id, request id or a path with an id in it —
  cardinality, not request volume, is what the bill scales with; debug level left on in production; a
  correlation id created at the edge and dropped at the first async hop; sampling decided after an
  incident, so the trace needed was discarded; a vendor SDK bolted alongside OTel.

### Self-run stack (Prometheus + Grafana + Loki/Tempo, or an OTLP-native store)

- **Use when** telemetry may not leave the network, volume makes per-GB pricing the dominant cost,
  or someone already operates it.
- **Pros** no ingest bill; retention is your decision; components are individually replaceable.
- **Cons** several stateful services with their own sizing, retention pruning, upgrades and backups;
  on-call work of its own; usually hosted inside the failure domain it observes.
- **Typical mistakes** monitoring the cluster from inside the cluster with no independent alert path;
  unbounded retention until a disk fills; no owner, so exporters rot and dashboards quietly lie.

### SaaS backend

- **Use when** the team is small, an incident costs more than the subscription, or correlated logs,
  metrics and traces are needed from day one.
- **Pros** no operations; alerting, on-call routing and dashboards included; survives your outage.
- **Cons** the bill follows data volume and cardinality rather than system size — state that budget
  risk up front; telemetry leaves your boundary, which is a constraint question, not a preference.
- **Typical mistakes** shipping every debug log and meeting the bill a quarter later; instrumenting
  with the vendor's SDK, so switching means re-instrumenting; personal data no erasure process reaches.

### Cloud-native backend (Azure Monitor, CloudWatch, Cloud Operations)

- **Use when** everything runs in one cloud and its managed services already emit there.
- **Pros** platform and application signals in one place; access from the cloud's own identity.
- **Cons** query languages and trace support vary sharply between clouds; anything outside that cloud
  stays outside; ingested GB and custom metrics are billed the way SaaS bills them.
- **Typical mistakes** custom metrics dimensioned per tenant or per user; assuming platform metrics
  answer application questions.

### Alerting and SLOs

- Alert on symptoms a user can feel — error rate, latency, queue age, failed jobs. Causes belong on
  dashboards; a cause-based page that fires while nobody is affected trains the on-call to ignore it.
  Every page names the user-visible impact and points at a runbook step, or it is a ticket instead.
- Where an SLO exists, alert on error-budget burn rate over a fast and a slow window rather than a
  single threshold crossing. The SLO is the tie back to `04-quality-scenarios.md`: the availability
  or latency scenario and the SLO are one statement, written once and referenced.
- **Typical mistakes** one alert per metric; thresholds nobody has revisited since the first release;
  an SLO target copied as 99.9% with no measurement of the current number — measure, then commit.

## Health and lifecycle

| Check | Answers | Failing it means | May depend on |
|---|---|---|---|
| liveness | is this process wedged beyond recovery | the platform restarts it | process-internal state only |
| readiness | can it serve a request right now | it leaves the load balancer and stays alive | its own warm-up, and only dependencies it cannot serve without |
| startup | has slow initialisation finished | boot gets its own budget; liveness and readiness are suspended until it passes | boot work only |

- Decide once, and write down which dependencies make an instance not ready and which leave it
  degraded but serving. A downstream outage that fails every readiness check converts a partial
  failure into a total one.
- Off Kubernetes the mechanism changes, not the need — load-balancer health check, service watchdog,
  platform warm-up path. Name it in `06-deployment.md`.
- **Typical mistakes** liveness that checks the database, so a blip restarts every replica; readiness
  that always returns 200; initialisation work in the liveness path; a check with no timeout.

### Shutdown

- On the stop signal: refuse new work, finish or hand back what is in flight, exit inside the
  platform's grace period. The two numbers must agree, and the application's drain timeout is the
  smaller one. Endpoint removal is not instantaneous, so a short delay before draining absorbs the
  requests already routed to the instance.
- **Typical mistakes** exiting immediately with requests in flight; a drain longer than the grace
  period, so the process is killed mid-drain; background consumers that ignore the signal and lose
  the message being handled; no idempotency, so the redelivery after a kill duplicates the effect.

### Timeouts, retries, circuit breaking

An architectural decision because the policy must be consistent, not because a call site is hard.
Pick one home and record it in `03-containers.md`.

| Home | Fits | Costs |
|---|---|---|
| calling code (a resilience library) | one or two languages; policy per call semantics | every service configures it separately and they drift; nothing enforces it |
| sidecar or ambient service mesh | many languages; uniform policy, mTLS and call telemetry included | a platform to run and upgrade; retries invisible in the code, so a bug is masked and amplified |
| edge gateway or reverse proxy | north-south traffic, few services | says nothing about service-to-service calls |

- Every remote call carries a timeout shorter than its caller's. Retries only on idempotent
  operations, bounded, jittered and budgeted.
- **Typical mistakes** retries at three layers multiplying into a self-inflicted DDoS on a struggling
  dependency; retrying non-idempotent writes with no dedup key; a circuit breaker with no fallback,
  which fails the same way with less evidence; a default HTTP client timeout of infinity.

## Data in operation

Backup is not the decision; **restore** is. Fix RPO (how much data may be lost) and RTO (how long
recovery may take) as numbers first, then pick a mechanism that meets them. Both become data
protection rows in `04-quality-scenarios.md`; a drill is what makes the rows true.

| Decision | Options | Consequence to state |
|---|---|---|
| what is protected | the store · store plus object storage · nothing, it is derivable | anything called derivable needs a named, tested rebuild path |
| mechanism | managed snapshots · PITR via log shipping · logical dump | snapshot RPO equals the snapshot interval; PITR reaches a second but needs retained logs and a longer restore; dumps are portable and slow |
| where copies live | same account · another region · another provider or offline | a copy inside the primary's own account survives neither a credential compromise nor an account deletion |
| who restores, last proven when | drill cadence and owner | an untested backup is a row in `07-risks.md`, not a control |

- **Typical mistakes** a green backup job whose restore has never been run; PITR claimed while log
  retention is shorter than the recovery window; backups encrypted with a key that is not itself
  backed up; a restore needing credentials stored only in the system being restored; snapshots that
  stopped silently when a resource was renamed.

### Retention, deletion, encryption

- Retention is decided per data class, not once for the system: what is kept, for how long, what
  deletes it. Logs, traces and analytics exports are data too — a user id in a log field carries the
  obligation of the row it came from.
- A deletion obligation needs a stated path through backups: a retention window short enough that
  copies expire on their own (name it), or a suppression step in the restore runbook. Append-only
  stores — event sourcing, WORM backups — collide with erasure; decide crypto-shredding, tombstoning
  or keeping personal data out of the log before the first event is written.
- Encryption at rest and in transit are two decisions with two owners. Per store and per channel,
  state who holds the key, where it rotates, and what breaks if it is lost. A platform-held key
  answers a compliance question, not an insider one; say which one is being answered.
- **Typical mistakes** unlimited retention because storage is cheap; a deletion that clears the row
  while caches, search indexes and read models keep it; TLS terminated at the edge with plaintext
  inside a network merely described as trusted; a customer key with no rotation and no recovery plan.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the reversible, low-operation one: the
platform's own secret store, OTel through a collector into whatever the platform already provides,
managed snapshots with one proven restore, resilience policy in the calling code. Record the trigger
that would change it — a second cloud, an on-call rota, a regulated data class — in `07-risks.md`.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected quality scenarios and
   constraints by id, the recurring cost in money and operational time, and what reversing costs.
2. Give one recommendation with its driver. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`, rejected options as its alternatives with
   the reason each lost. The result is referenced from `06-deployment.md` (where secrets and
   telemetry live) and `03-containers.md` (where resilience policy lives).
4. Every measurable outcome becomes a row in `04-quality-scenarios.md` with a number and a unit —
   rotation interval, retention days, RPO and RTO, sampling rate, time to alert. An attribute with no
   row is recorded as not applicable, with its reason.
5. An answer with no owner ("someone should rotate it") is a risk row in `07-risks.md`, not a
   decision. Anything the human leaves open is a `TODO(question)` per `templates.md`.
