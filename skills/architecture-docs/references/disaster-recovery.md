---
written_against: "web research 2026-08"
---

`written_against` names the cloud and product state this rubric was checked against — the October
2025 us-east-1 outage and its blast radius, Aurora Global Database's replication lag characteristics,
storage-level geo-replication SLAs, and which regions are paired versus zone-first. A vendor page
that contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Disaster recovery — what happens when the region goes, and whether you have rehearsed it

Load this when a region-wide outage is unacceptable, compliance demands a DR plan, or someone says
"multi-region" — before money is spent on standby infrastructure. `machine-topology.md` settles
availability inside one region, which is where most incidents die; this file starts where that ends,
at the loss of the whole region. `iac-and-drift.md` is a hard prerequisite for every posture above
backup-only: a rebuild plan that is not executable code is a wish. `global-audience.md` owns the
user-geography reasons for a second region, which are not the same as the survival reasons here.

Outputs land in `04-quality-scenarios.md` (the RTO and RPO with numbers and units), in
`06-deployment.md` (the posture, the secondary region, where backups and runbooks live), and in an
ADR per `templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

DR posture is a spectrum. Backup-and-restore-only is the cheapest, with an RTO measured in hours to
days. Pilot light replicates data while compute stays dark, giving tens of minutes to hours. Warm
standby runs a scaled-down live copy for an RTO of minutes. Active-active runs full capacity in two
or more regions for a near-zero RTO, at roughly 2x cost and considerably more than 2x engineering.
The October 2025 us-east-1 outage — around three hours of DynamoDB unavailability with a cascade of
twelve hours and more — is the proof that a whole region is a real failure domain.

Two mechanics decide the numbers. **Replication mode decides RPO**: async cross-region replication
such as Aurora Global Database typically runs sub-second lag, so an unplanned failover loses
seconds of writes, while storage-level geo-replication is minutes with no SLA. **Failover is
usually DNS**, so clients move only as fast as TTLs allow, and the failover control plane must live
outside the region that just died.

The honest safe default for most systems is a single region with cross-region backups and a written
restore runbook, rehearsed at least annually with a measured RTO. Every posture above backup-only is
worthless until you have pulled the trigger on purpose and timed it.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| The real, measured cost of downtime per hour | how much standby infrastructure is rational |
| RPO tolerance — how many seconds or minutes of committed data can be lost | the replication mode, because async lag is lost on hard failover |
| An RTO target, and whether anyone has measured the actual one | the posture tier; an unrehearsed RTO is "unknown, probably days" |
| Ops capacity | active-active, and even warm standby, are ongoing programmes of drills and drift control, not purchases |
| The database supports cross-region async replication | pilot light and warm standby become practical; without it you are restoring dumps |
| Whether traffic can be flipped while the primary region's consoles are degraded | a DNS data plane and pre-provisioned routing controls outside the blast radius |
| Residency rules forbid the obvious secondary region | check before designing the pairing |
| Multi-AZ already covers most incidents | buy DR posture for the measured cost of the rare day, not for diagram prestige |

## Backup and restore only

- **Use when** downtime of hours to a day is survivable, budget is tight and ops is small — provided
  the restore is scripted, rehearsed annually, and the measured RTO is written down and accepted.
  Unrehearsed, this is not a posture, it is a hope.
- **Pros** cheapest by far, and the right answer for most internal tools and small products; RPO
  equals the backup cadence, and point-in-time recovery shrinks it.
- **Cons** a region loss blows any serious uptime target for the year; and recovery time is dominated
  by compute stand-up and data restore, usually hours.
- **Typical mistakes** backups and the runbook stored inside the primary region's blast radius;
  guessing RTO at two hours and clocking twelve during the real event.

## Pilot light

- **Use when** an RTO of about an hour is acceptable, data loss must be near zero, and the budget
  cannot carry idle full-size compute: data replicated continuously, core infrastructure defined as
  IaC, compute off or minimal.
- **Pros** an RPO of minutes or better at a fraction of a live copy's cost; the sweet spot for
  systems that matter but cannot fund warm standby.
- **Cons** RTO is dominated by standing up and scaling compute — exactly the part that fails
  untested, through quotas, images, secrets and drift.
- **Typical mistakes** no failover drills, because pilot light drifts into fiction faster than any
  other posture; a secondary region missing the instance types or quotas you need, discovered during
  the incident.

## Warm standby

- **Use when** minutes of RTO are required, competent ops exists, and the budget is
  normal-to-generous: a scaled-down but fully functional copy running in region two, continuously
  replicated and serving health checks.
- **Pros** an RTO of minutes — flip DNS and scale up — with an RPO of seconds under async database
  replication; and drift risk drops because the standby is alive.
- **Cons** you run everything twice, one of them small: the bill rises for the same reason the drift
  falls.
- **Typical mistakes** nobody keeps the standby deployed in lockstep, so a stale standby fails over
  into a broken app; a standby that never takes traffic is a rumour — send it a slice, or drill
  quarterly.

## Active-active

- **Use when** the cost of downtime is extreme, dedicated ops or SRE exists, and the data model
  tolerates async multi-writer or clean region sharding: full capacity in two or more regions, both
  live.
- **Pros** near-zero RTO and RPO for region loss, where failover is simply "stop sending traffic
  there"; and bad deploys can be caught region by region.
- **Cons** it is a programme, not a purchase — routing, conflict resolution, per-region quotas,
  drills, and keeping DNS, secrets, CI and observability out of any single region; and it is roughly
  2x infrastructure and much more than 2x engineering, forever.
- **Typical mistakes** building half of it on a limited budget, which buys warm-standby reliability
  at a premium price; treating async replication as RPO 0, when in-flight writes are lost on hard
  region loss.

## Posture ladder

| Posture | RTO class | RPO class | Cost class | What must be rehearsed |
|---|---|---|---|---|
| backup and restore only | hours to a day (measure it) | backup cadence: hours for dumps, minutes for PITR and cross-region copy | $ — storage only | a full restore into a clean region from backups alone, annually, timed |
| pilot light | tens of minutes to hours | minutes to seconds (continuous replication) | $$ — replication, IaC and minimal compute | standing up compute from IaC in region two: quotas, images, secrets, DNS flip; semi-annually |
| warm standby | minutes | seconds (async replication) | $$$ — the full stack running small | scale-up to production size plus traffic failover under load; quarterly |
| active-active | near zero (drain a region) | near zero to seconds (async lag lost on hard loss) | $$$$ — roughly 2x infrastructure, more than 2x engineering | regularly evacuating a region in production on purpose; conflict behaviour; control-plane independence |

## What holds whatever you pick

- Your DR posture is whatever you have *tested*, not whatever you have deployed. An unrehearsed
  failover has an RTO of "unknown, probably days".
- The safe default is a single region with multi-AZ HA, cross-region backups, and a restore runbook
  rehearsed annually with a measured, business-signed RTO.
- RPO comes from the replication mode: async loses the lag window on unplanned failover, and only a
  planned switchover gives RPO 0.
- Failover is only as fast as your DNS: low TTLs, health-check flips, and a control plane that does
  not live in the region you are evacuating.
- Keep the recovery toolchain out of the blast radius — backups, runbooks, IaC state, CI, secrets,
  observability. You cannot restore from a runbook stored in the region that is down.
- Do not assume a region pair exists: many newer regions are non-paired and zone-first. Verify that
  the secondary has the services, instance types and quotas *before* the incident.
- Region loss is rare, and most incidents die at multi-AZ. Write down the honest consequence of the
  posture you chose.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a single region with multi-AZ HA,
cross-region backups, a written restore runbook, and one timed annual restore drill — and record the
measured RTO as the number the business is accepting. Name the trigger that would buy a higher
posture: a measured cost per hour of downtime, a compliance clause demanding a DR plan, or a
database that gains cross-region async replication. Each trigger is a row in `07-risks.md` until it
becomes a scenario.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the posture, the secondary
   region, and the RTO and RPO each one actually delivers.
2. State the monthly cost class of each, the ops capacity it assumes, and the drill cadence it
   obliges someone to run.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `06-deployment.md`.
4. The RTO and RPO become rows in `04-quality-scenarios.md` with numbers and units; a target with no
   measurement behind it is not a scenario.
5. An unrehearsed failover, backups or runbooks inside the primary region's blast radius, an
   unverified secondary region, and a DNS TTL nobody has lowered are rows in `07-risks.md`, each with
   an owner. Anything the human leaves open is a `TODO(question)` per `templates.md`.
