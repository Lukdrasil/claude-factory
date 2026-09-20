---
written_against: "web research 2026-08"
---

`written_against` names the product and specification state this rubric was checked against —
Kubernetes rollout primitives, Argo Rollouts v1.10 and its RolloutPlugin support for StatefulSets,
Flagger's automatic metric-driven promotion, the migration-lock behaviour of Flyway, Liquibase and
EF Core, and the guidance Harness, Liquibase and Bytebase converge on for expand-contract. A vendor
page that contradicts it means this file is stale and needs re-research, not that the solution
drifted.

# Release strategy — replacing a version without dropping traffic, and surviving two schemas at once

Load this when a deployment or release strategy is being chosen, database schema migrations are
being planned, health checks and rollout automation are being wired, or someone is deciding where
migrations execute in the pipeline. `delivery-pipeline.md` gets the artifact built and promoted to
the environment; this file decides how it replaces what is already running. `feature-flags.md` owns
the mechanism that makes a bad feature reversible without a redeploy, and `machine-topology.md`
owns whether there are enough replicas for a rolling strategy to mean anything.

Outputs land in `06-deployment.md` (the strategy, the migration execution point, the drain
settings), in `04-quality-scenarios.md` when a zero-downtime target gets a number, and in an ADR
per `templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

Zero-downtime release is two disciplines fused: a traffic strategy — recreate, rolling, blue-green
or canary — and a schema discipline, expand-contract. Every strategy except recreate runs version N
and N−1 concurrently, so both the API contract and the database schema must be N−1 compatible. The
golden rule is to never ship a breaking migration in the same artifact as the code that depends on
it.

## Expand-contract

Expand-contract (also called parallel change) sequences a schema change as four steps, not one:

1. **Expand additively** — nullable columns, new tables, `CREATE INDEX CONCURRENTLY` on Postgres.
2. **Backfill or dual-write** into the new shape.
3. **Switch reads** to the new shape.
4. **Contract** in a *later* release, once no reader depends on the old shape.

Use online DDL primitives for the expand step — `CREATE INDEX CONCURRENTLY` on Postgres, gh-ost or
pt-online-schema-change on MySQL — and test migrations against production-scale data. Two seconds in
dev can be two hours in prod.

## Where migrations run

Migrating on application startup is the simplest option and the one that breaks first: every
replica races to run it. Flyway, Liquibase and EF Core all acquire a database lock precisely
because of this — a Postgres advisory lock for Flyway, `DATABASECHANGELOGLOCK` for Liquibase, and
nothing built in for EF Core, which means you supply your own. The recommended pattern is a gated
step instead: a Kubernetes Job that gates the rollout, a Helm `pre-upgrade` hook, or init
containers that wait on the Job. Manual gates suit regulated shops. If startup migration is
genuinely unavoidable, lean on the tool's lock and treat lock timeouts as deploy failures.

## Rollback reality

Code rolls back; schema effectively does not. Data written into new structures cannot be un-written,
so mature teams roll forward and use feature flags — OpenFeature, LaunchDarkly, Unleash — to turn a
bad feature off without redeploying. Flags plus forward-only migrations are what replaces schema
rollback; see `feature-flags.md` for the mechanism and its cleanup obligation.

## Long-lived connections

WebSockets and SSE need explicit session draining rather than the HTTP defaults. Handle `SIGTERM`,
add a `preStop` sleep of 5–15 seconds so load-balancer endpoint removal propagates, send close
frames (1012) so clients reconnect to new pods, and size `terminationGracePeriodSeconds` at 90–120
seconds — far above the HTTP default.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Availability is basic and a maintenance window is genuinely acceptable (internal tool, single-tenant B2B) | recreate — stop old, start new, run migrations in the window, and skip all N−1 compatibility ceremony |
| Availability is high, with autoscaled replicas and a stateless app | rolling as the default; enforce readiness probes, connection draining and expand-contract migrations, because N and N−1 always overlap |
| An instant switch and instant traffic-level rollback are needed, e.g. a big-bang framework upgrade | blue-green — two full environments behind an LB or router flip; accept 2x infrastructure cost and accept that the database is still shared |
| High blast-radius changes plus real observability (RED/USE metrics in Prometheus or Datadog) | canary with automated analysis — an Argo Rollouts AnalysisTemplate or Flagger metric checks, with weighted routing via a service mesh or cloud ALB weighted target groups |
| A relational schema evolving frequently under any concurrent-version strategy | expand-contract as standing policy: the additive migration ships first, the contraction ships releases later, enforced in review |
| WebSockets or long-lived SSE in play | a session-draining design: `SIGTERM` handling, a `preStop` hook, close frames plus client auto-reconnect, and a generous `terminationGracePeriodSeconds` |
| The business wants dark launches or per-tenant rollout independent of deploys | feature flags (OpenFeature, Unleash, LaunchDarkly), so deploy is not release and rollback becomes flag-off rather than redeploy |

## Recreate

- **Use when** a downtime window is acceptable — internal apps, nightly-window B2B, a single
  machine or compose host. It is also the honest choice when the team cannot yet do N−1 compatible
  schemas.
- **Pros** the simplest possible model, because two versions are never live, so there is no N−1 API
  or schema compatibility work; destructive migrations can run in the window with no expand-contract
  ceremony; and it works anywhere — `docker compose down`/`up`, a single VM, an IIS app pool recycle.
- **Cons** guaranteed downtime every release, which caps release frequency; a failure mid-deploy
  means an extended outage, because rollback is another full downtime window; and it is
  habit-forming, since teams that start here never build the compatibility discipline needed to
  leave.
- **Typical mistakes** using recreate on a system with an availability SLA and calling the window
  "brief"; running long data backfills inside the window instead of online beforehand, turning two
  minutes into two hours.

## Rolling

- **Use when** the default for Kubernetes Deployments and PaaS with stateless replicas and honest
  health checks. N−1 compatibility is table stakes.
- **Pros** built into Kubernetes (`maxSurge`/`maxUnavailable`), ECS and most PaaS, so there is no
  extra tooling; no extra infrastructure cost, and gradual by nature; and combined with readiness
  probes and `preStop` draining it is genuinely zero-downtime for HTTP.
- **Cons** N and N−1 run concurrently for the whole rollout, so every API and schema change must be
  backward compatible; rollback is another rolling pass rather than instant, and a bad readiness
  probe stalls the rollout half-migrated; and there is no traffic-percentage control or metric
  gating, so a subtle bug reaches 100% of users at rollout speed.
- **Typical mistakes** a rolling deploy with an incompatible N−1 API or schema, where old pods throw
  on new payloads or columns mid-rollout; a liveness probe that checks the database, so a DB blip
  restarts every pod during a deploy; no `preStop` sleep, so the pod gets `SIGTERM` before LB
  endpoint removal propagates (5–15 seconds) and returns 502s.

## Blue-green

- **Use when** an instant cutover and instant traffic rollback are worth 2x infrastructure: risky
  framework upgrades, IIS and VM estates via a slot or LB swap, AWS ECS/CodeDeploy blue-green, Azure
  App Service slots, or Aurora blue-green for the database tier itself.
- **Pros** an atomic switch and near-instant rollback at the traffic layer, by flipping the router
  back; green is smoke-testable with production config before receiving real traffic; and it maps
  well onto non-Kubernetes estates — LB pool swap, App Service slot swap, CodeDeploy.
- **Cons** double compute cost while both environments exist; the database is almost never
  duplicated, so blue and green share one mutable DB, the schema must still be N−1 compatible and
  "instant rollback" does not cover data; and in-flight sessions and WebSockets are severed or must
  be drained across the flip.
- **Typical mistakes** treating blue and green as independent environments while they share one
  mutable database, where running green's migration breaks blue immediately; skipping connection
  draining on the old colour and dropping in-flight requests at the flip.

## Canary

- **Use when** high-traffic services where a bad release must be caught by metrics on 1–10% of
  traffic before full promotion. It needs real observability and automation: Argo Rollouts or
  Flagger on Kubernetes, ALB or Cloud LB weighted target groups, or a service-mesh traffic split
  (Istio, Linkerd, Gateway API).
- **Pros** the smallest blast radius of any strategy, and rollback is cheap because 95% of traffic
  never saw the bad version; metric-gated automation — Argo Rollouts AnalysisTemplates, Flagger's
  automatic promotion — aborts and rolls back without a human; and Argo Rollouts gives step-based
  control with manual gates while Flagger gives hands-off metric-driven promotion with minimal
  manifest changes.
- **Cons** the highest operational complexity — traffic-splitting infrastructure, SLI definitions
  and analysis tuning against false positives and negatives; a long N/N−1 coexistence window, so
  schema and API compatibility must hold for hours or days rather than minutes; and low-traffic
  services cannot reach statistical significance, which turns the canary gate into noise.
- **Typical mistakes** canary without automated metric analysis, where a human glancing at a
  dashboard is just a slow rolling deploy with extra YAML; session-sticky or cache-warmed traffic
  skewing canary metrics against stable and producing false confidence; letting the canary run
  destructive migrations, so 5% of pods rewrite the schema for 100% of the fleet.

## What holds whatever you pick

- Never ship a destructive or contracting migration in the same release as the code change. Expand
  first, contract at least one release later.
- Every strategy except recreate runs N and N−1 simultaneously: both API and schema must be
  backward compatible one version in each direction.
- Run migrations as a gated step — a Kubernetes Job, a Helm `pre-upgrade` hook, or a pipeline stage
  — rather than on app startup when replicas exceed one. If startup migration is unavoidable, rely
  on the tool's lock (a Flyway advisory lock, Liquibase's `DATABASECHANGELOGLOCK`, your own for EF
  Core) and treat lock timeouts as deploy failures.
- Plan to roll forward. Treat schema rollback as impossible once new-format data exists; feature
  flags are the real rollback mechanism for behaviour.
- Canary promotion is decided by metrics — error rate, latency, saturation — via Argo Rollouts or
  Flagger analysis with automatic abort, not by a human watching Grafana.
- Blue-green with one shared database is a traffic pattern, not environment isolation: the schema is
  a single mutable point both colours must tolerate.
- WebSockets and SSE need explicit drain choreography: a `preStop` sleep for endpoint propagation, a
  `SIGTERM` handler sending close frames, client auto-reconnect with backoff, and
  `terminationGracePeriodSeconds` sized to 90–120 seconds.
- Use online DDL primitives — `CREATE INDEX CONCURRENTLY` on Postgres, gh-ost or
  pt-online-schema-change on MySQL — and test migrations against production-scale data.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend rolling with honest readiness probes and
`preStop` draining where replicas exist, recreate where a window is genuinely acceptable, and
expand-contract as standing policy either way. Name the trigger that would escalate: a signed
zero-downtime target, a change whose blast radius justifies metric-gated canary analysis, or the
first long-lived connection in the design. Each trigger is a row in `07-risks.md` until it becomes a
scenario.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the traffic strategy, where
   migrations execute, and what rollback actually means for data.
2. State each option's infrastructure cost — the second environment for blue-green, the
   traffic-splitting and analysis stack for canary — and the compatibility discipline it obliges the
   team to hold.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `06-deployment.md`.
4. A destructive migration shipping with the code that needs it, a startup migration across multiple
   replicas, a canary judged by eyeball, and long-lived connections with no drain choreography are
   rows in `07-risks.md`, each with an owner. Anything the human leaves open is a `TODO(question)`
   per `templates.md`.
