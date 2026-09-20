---
written_against: "web research 2026-08"
---

`written_against` names the state this rubric was checked against — current on-call staffing
guidance and the blameless-postmortem practice it assumes. A source that contradicts it means this
file is stale and needs re-research, not that the solution drifted.

# Incident response — the rotation, the severities, the runbooks, the postmortem

Load this when availability is high, an SLO exists, backups exist, or the system has real users
whose outage anyone would notice. `slo-error-budgets.md` decides what pages and why;
`operations.md` decides the backup mechanism this file insists someone restores from;
`observability-conventions.md` decides whether the responder can find anything once paged;
`machine-topology.md` owns the failover the runbooks below describe.

Outputs land in `04-quality-scenarios.md` (time to detect, time to acknowledge, the restore RTO),
in `06-deployment.md` (where the runbooks live and what the rollback command is) and in an ADR per
`templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

Incident response is decided before the incident, or it is improvised during one. Four things: who
gets paged — a named rotation, not "whoever notices"; severity levels that describe current
customer impact rather than technical difficulty; runbooks that live next to the code and are
actually drilled; and a blameless postmortem that turns each incident into system fixes. The
failure mode it prevents is the 3 a.m. outage where the restore procedure is invented live against
a backup nobody has ever restored.

The safe default is a single on-call rotation, two severity levels — sev1 for a full outage or data
loss, sev2 for major degradation with no workaround — the five mandatory runbooks co-located in the
repo, and a one-page postmortem template. A rotation needs enough people to be sustainable: 24/7
coverage with fewer than about six people burns them out regardless of tooling.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| The availability target is high, or an SLO exists | a named rotation with paging and severity levels — a target nobody defends is a wish |
| Ops capacity is none | ad-hoc response is the honest label; lower the availability promise to match, and automate recovery |
| One small team | a single rotation with runbooks — escalation tiers with three engineers is theatre |
| Many teams or services with different owners | formal escalation tiers and service ownership, so the pager reaches someone who can act |
| Backups exist in any form | a restore runbook drilled on a schedule — an untested backup is a hope |
| An error budget policy is in place | severity mapped to budget burn; postmortems feed the budget review |
| Frequent releases | the rollback runbook is the most-used one, and it must be one command |
| Third-party dependencies on the critical path | a dependency-outage runbook with the degrade, queue or fail decisions made in advance |

## Ad-hoc (whoever notices)

- **Use when** an internal tool with basic availability, no SLO, and users who can wait until
  morning — honest only if the stated availability target matches.
- **Pros** zero process cost and no pager burden.
- **Cons** detection is luck, and the first responder is often a user; response time is unbounded,
  knowledge lives in one head, and every incident is improvised, including the restore.
- **Typical mistakes** claiming high availability while running this; no runbooks because "we know
  the system", when the one who knows is on holiday during the outage.

## Single rotation with runbooks

- **Use when** the default for one team with real users: one rotation everyone technical joins,
  sev1 and sev2 definitions, the five mandatory runbooks in the repo, and a postmortem after every
  sev1.
- **Pros** someone specific is always responsible, so there is no diffusion; runbooks make the
  responder interchangeable with the author; and it is cheap — one schedule, one alert route, one
  template.
- **Cons** below four or five engineers the same people get paged too often and fatigue stacks
  fast; and with no tiers, a stuck responder has no formal next step beyond "wake the lead".
- **Typical mistakes** a rotation on paper while alerts still go to one person's phone; runbooks in
  a wiki that drifts from the code; paging on every warning, which teaches the responder to ignore
  the pager; nobody drilling the restore, so the runbook is fiction with formatting.

## Formal on-call with escalation tiers

- **Use when** multiple teams or services, dedicated ops capacity, and an SLO with consequences:
  primary and secondary layers, ack windows with automatic escalation, and severity wired to the
  paging policy.
- **Pros** unacknowledged pages escalate automatically instead of dying, and load is shared and
  measurable — pages per shift, off-hours pages, actionable rate.
- **Cons** it needs headcount: sustainable 24/7 coverage with layers wants eight or nine people
  once on-call time is capped near 25%.
- **Typical mistakes** tiers that all resolve to the same two people; an escalation policy defined
  but ack timeouts never configured, so tier 2 is decorative; severity assigned by technical
  difficulty instead of customer impact.

## Follow-the-sun (multi-team)

- **Use when** the organisation has staffed teams in two or three time zones and a handoff ritual
  between shifts. For everyone else it is an org chart, not an option.
- **Pros** no 3 a.m. pages — every incident lands in someone's working day.
- **Cons** it requires regional teams with equal system knowledge, and handoffs lose context unless
  they are ritualised.
- **Typical mistakes** one remote contractor labelled a "region"; no written handoff, so each shift
  re-diagnoses the ongoing incident.

## The five mandatory runbooks

| Runbook | What it must contain | How it is tested |
|---|---|---|
| Restore from backup | What is restored, from where (location, access, credentials), to where, step-by-step commands, expected duration, and a verification step proving the data is correct | Executed for real quarterly into a scratch environment; log the date, duration and deviations — an unrestored backup does not count as tested |
| Rotate a leaked secret | An inventory of every secret and its consumers, the rotation order (rotate, deploy, revoke), how to revoke without downtime, and a log check for use of the leaked value | Drill on a non-production secret; every real rotation updates the runbook with what the doc got wrong |
| Roll back a release | The exact command, how to confirm the live version, migration handling (roll forward vs down), flag kill switches, and the point of no return | Exercised on every release candidate in staging; more than one command plus one verification is a finding |
| Dependency outage | Per critical dependency: how to confirm it is them, the pre-decided degrade mode (stale, queue, fail visibly), user comms, and replay or reconcile on return | Tabletop per dependency; where feasible, block it in staging and watch the degrade mode engage |
| Disk full | How to identify the growing consumer, what is safe to delete immediately, how to expand storage, and the 80% alert that should have fired | Fill a disk in staging and verify the alert; re-verify the safe-to-delete list after storage layout changes |

## What holds whatever you pick

- Severity describes current business impact, never how hard the fix looks: sev1 is a full outage,
  data loss or breach and pages immediately; sev2 is major degradation with no clean workaround.
- Runbooks live in the repo next to the code, reviewed in the same PRs — a wiki runbook drifts
  silently until the night it is needed.
- A backup is tested by restoring it. Quarterly real restores at minimum, logged.
- Do not staff a 24/7 rotation with fewer than about six people — shrink the promise, not the sleep.
- The pager is for actionable pages only; more than two or three actionable incidents per shift
  means fix the alerts or the system, not the schedule.
- Every sev1 gets a blameless postmortem: timeline, impact, contributing factors framed as system
  conditions, and owned, due-dated action items, with names as roles rather than culprits.
- Separate mitigations from preventions that address the class of failure, and track both to done.
- Write the escalation path before the incident — an escalation policy discovered at 3 a.m. is
  chat-channel roulette.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a single rotation with sev1 and sev2
definitions, the five runbooks in the repo, a quarterly restore drill, and a one-page postmortem
after every sev1. Name the trigger that would change it — a second team with its own service, an
SLO with contractual consequences, a rotation that drops below the sustainable headcount — as a row
in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: who is on the rotation,
   what the severity definitions are, and which runbooks exist today.
2. State the recurring cost of each — the headcount a sustainable rotation needs, the drill cadence,
   the paging tool — and what reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `06-deployment.md`.
4. The measurable outcomes become rows in `04-quality-scenarios.md` with a number and a unit: time
   to detect, ack window before escalation, the restore RTO the drill actually achieved, and the
   actionable-pages-per-shift ceiling.
5. An undrilled restore, an escalation tier with no configured ack timeout, and a runbook living
   outside the repo are rows in `07-risks.md`, each with an owner. Anything the human leaves open is
   a `TODO(question)` per `templates.md`.
