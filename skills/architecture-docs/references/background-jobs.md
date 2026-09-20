---
written_against: "web research 2026-08"
---

`written_against` names the product state this rubric was checked against — Hangfire, Quartz.NET,
Celery and Sidekiq's licences and clustering behaviour, the Kubernetes CronJob defaults, the
RabbitMQ delayed-message plugin's archived status, SQS's delay cap. A current project page that
contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Background jobs — where deferred and scheduled work runs

`message-bus.md` decides the broker that moves facts between components. This file decides
something separate: where work that runs *later* or *on a schedule* actually executes, and what
stops it from double-firing across replicas or dying silently. `resilience-patterns.md` owns the
idempotency machinery every option here depends on; `containers.md` and `deployment.md` own the
platform whose cron primitives one of the options uses.

Load it when anything runs later or on a schedule — nightly cleanup, reports, retries, delayed
notifications — or when a timer or `BackgroundService` already exists and replicas are planned.
Outputs land in `03-containers.md` (the worker or job host as a unit), in `06-deployment.md` (the
job store, the CronJob manifest, the singleton constraint), and in an ADR per `templates.md`. Every
choice below reaches the human as options with consequences plus your recommendation, per
`approaches.md`.

Background jobs are a separate decision from the message bus: the bus moves facts between
components, jobs run work at a time. Four homes exist — an in-process hosted service or timer, a
persistent job library (Hangfire, Quartz.NET, Celery, Sidekiq class), platform-native cron
(Kubernetes CronJob, a cloud scheduler, `pg_cron`, host cron), or delayed messages on the bus. The
choice comes down to three questions: what enforces run-once with more than one replica, what
happens when a run fails, and who can see that it failed.

The safe default is a persistent job library backed by the primary store — jobs survive restarts,
run-once comes from the store's locking, and retries and a dashboard come built in. On Kubernetes,
CronJob is the honest pick for schedule-shaped work. The classic failure: the in-process timer
works perfectly on one replica, then the service scales to two and every job fires twice — or the
pod dies mid-run and nothing fires, with no record either way.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Single process, single replica, and job loss on restart is acceptable | an in-process hosted service or timer — the only situation where it is honest |
| More than one replica now or plausibly later | run-once must be enforced by a store or the platform, not by hoping |
| Jobs must survive restarts, retry, and be visible when they fail | a persistent job library backed by the primary store |
| Already on Kubernetes and the work is schedule-shaped | a Kubernetes CronJob — with `concurrencyPolicy` and `startingDeadlineSeconds` set explicitly |
| A workflow needs a delay step and a durable bus already exists | delayed messages — but verify the broker actually supports durable delay; RabbitMQ's delayed plugin is archived and dead on 4.x |
| The work is pure SQL on Postgres | `pg_cron` — it runs inside the database, keeps history in a table, and deploys nothing |
| Serverless or PaaS with no always-on process | a cloud scheduler (EventBridge class): at-least-once, configurable retries, a DLQ — design the target to be idempotent |
| No ops capacity for a second moving part | a job library inside the existing service and database — one deployable, dashboard included |

## In-process hosted service / timer

- **Use when** one replica, and the job matters so little that losing it on every restart is fine.
  That is the whole list.
- **Pros** zero infrastructure — a `BackgroundService` or `PeriodicTimer` and nothing else; trivial
  to debug locally.
- **Cons** state lives in memory, so when the pod dies the schedule dies with it, silently; two
  replicas means every job fires twice, because the timer has no idea siblings exist; no retry, no
  history, no dashboard — failure is a log line nobody reads.
- **Typical mistakes** shipping the timer "temporarily", then enabling autoscaling six months later
  — the double-fire shows up as duplicate emails or double-charged customers; a hand-rolled
  database flag used as a lock without expiry, so one crash wedges the schedule forever; assuming
  `StopAsync` always runs, when SIGKILL and OOM do not call it.

## Persistent job library (Hangfire / Quartz / Celery class)

- **License** Hangfire LGPLv3, Quartz.NET Apache-2.0, Celery BSD, Sidekiq LGPLv3 — the licence
  family question itself belongs to `licensing.md`.
- **Use when** the safe default: jobs must survive restarts, run once across replicas, retry on
  failure and be visible — all from the store you already run.
- **Pros** run-once becomes the store's problem, already solved — Hangfire distributed locks,
  Quartz clustered `AdoJobStore`, Sidekiq via Redis; retries with backoff and a failed-job list are
  built in, and Hangfire ships a dashboard; backed by the primary store, so a job can be enqueued
  in the same transaction as the state change.
- **Cons** polling costs queries, and job tables grow and need retention; delivery is at-least-once,
  so handlers must be idempotent; Celery beat does not coordinate — exactly one beat process per
  deployment, or every scheduled task fires twice.
- **Typical mistakes** pointing the job store at a different database than the app, which loses the
  transactional enqueue; running two Celery beat instances behind `replicas=2`; recurring-job
  definitions living only in a dashboard click, so a fresh environment silently has no schedule.

## Platform cron (Kubernetes CronJob / cloud scheduler)

- **Use when** already on Kubernetes or serverless and the work is schedule-shaped: a container
  that starts, does the batch, and exits.
- **Pros** no scheduler code to own — the platform fires it, retries it via `backoffLimit`, and
  keeps history; isolation, since the batch gets its own pod and cannot take the API down; and
  `pg_cron` covers the pure-SQL subset with zero deploy surface.
- **Cons** at-least-once, so a job can fire twice or occasionally not at all and idempotency is on
  you; the hundred-missed-schedules trap — with `startingDeadlineSeconds` unset, a CronJob that
  misses 100 runs stops scheduling permanently with only a controller log to say so; and
  `concurrencyPolicy` defaults to `Allow`, so a slow run overlaps the next.
- **Typical mistakes** not setting `concurrencyPolicy: Forbid` and then watching Monday's slow run
  overlap Tuesday's; platform cron poking an HTTP endpoint on a multi-replica service, which just
  moves the run-once problem behind the load balancer; on compose, "platform cron" is the host's
  crontab — no retry, no history, and gone when the host is rebuilt.

## Delayed messages on the bus

- **Use when** a durable bus already exists, the delay is part of a message workflow (saga
  timeouts, a reminder sent later), and the broker natively supports scheduled delivery — verify
  that last part.
- **Pros** one piece of infrastructure: the same bus, consumers, DLQ and retry pipeline; a natural
  fit for per-message delays that cron cannot express.
- **Cons** broker support is uneven — RabbitMQ's delayed-message plugin is archived and does not
  run on 4.3+, core SQS caps delay at 15 minutes, and Kafka has no native delay; recurring
  schedules still need something to publish the first message; and a long-delay message is
  invisible in flight, so cancelling or rescheduling it is somewhere between hard and impossible.
- **Typical mistakes** building on the RabbitMQ delayed-exchange plugin in 2026; chaining TTL and
  dead-lettering for delays and hitting head-of-line blocking, where one long delay holds back
  every shorter one; adding a broker just to get a timer — the most expensive scheduler on the
  market.

## Requirement against option

| Requirement | In-process timer | Persistent job library | Platform cron | Delayed bus messages |
|---|---|---|---|---|
| Run-once across replicas | no — every replica fires; the defining failure | yes — store-level locking, except Celery beat, a mandatory singleton | yes for the trigger; still at-least-once | yes via competing consumers; duplicates possible |
| Retry on failure | none — write it yourself | built in, with backoff and a failed list | `backoffLimit` or scheduler retry, then a DLQ | consumer retry plus DLQ |
| Visibility when it fails | a log line, if you logged | a dashboard and queryable job tables | `kubectl get jobs`, events, DLQ depth | DLQ depth — a poor answer to "did last night run?" |
| Delay precision | timer-precise, until the pod dies | seconds, bounded by storage polling | minute-granularity cron | per-message where natively supported; a 15-minute cap on SQS |
| New infrastructure | none | none if backed by the primary store — that is the point | none on Kubernetes or cloud; the host crontab on compose | a durable bus with real delay support |

## What holds whatever you pick

- Jobs and the bus are different decisions: the bus moves facts, jobs run work at a time. Answer
  them separately, even when one technology could fake both.
- An in-process timer is a single-replica tool. The moment a second replica is plausible it is a
  latent double-fire, and the failure is silent.
- Everything real here is at-least-once — idempotent handlers are the entry fee, not an
  optimisation.
- Default to a persistent job library backed by the primary store: run-once, retry and visibility
  all come from infrastructure already on the pager.
- On Kubernetes, set `concurrencyPolicy` explicitly and always set `startingDeadlineSeconds`. Left
  unset, 100 missed schedules stop the CronJob permanently.
- Run-once needs a lock with an expiry in a shared store. A boolean flag is not a lock, and a lock
  without an expiry is an outage.
- Recurring schedules belong in code, not in a dashboard click.
- Do not build on the RabbitMQ delayed-message plugin: it is archived and incompatible with 4.3+.
  Long delays belong in a `due_at` table polled by the job library.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a persistent job library backed by the
primary store, with recurring schedules defined in code and handlers written to be idempotent from
the first one. Name the trigger that would change it — a move to Kubernetes where the work is
purely schedule-shaped, a workflow needing per-message delays, or a job whose runtime outgrows the
application host — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: how many replicas run the
   job host, what enforces run-once, and what is meant to happen when a run fails.
2. State what each costs — the retention on the job tables, the singleton constraint a Celery beat
   imposes, the broker a delayed message obliges someone to operate — and what reversing it later
   costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. Record the run-once mechanism and the schedule source in `06-deployment.md`, including any
   singleton the deployment must guarantee.
5. An in-process timer on a service that may scale, a lock with no expiry, a CronJob with
   `startingDeadlineSeconds` unset, and a schedule that exists only in a dashboard are rows in
   `07-risks.md` with an owner. Anything the human leaves open is a `TODO(question)` per
   `templates.md`.
