---
written_against: "web research 2026-08"
---

`written_against` names the state this rubric was checked against — the burn-rate windows and
multi-window alerting guidance in the Google SRE Workbook, and the target conventions in current
practice. A source that contradicts it means this file is stale and needs re-research, not that the
solution drifted.

# SLOs and error budgets — which SLIs, what targets, and what burns the budget

Load this when the monitoring and alerting strategy, availability targets or on-call scope are
being decided, or when someone proposes "five nines" or a wall of threshold alerts.
`operations.md` settles the telemetry backend that produces the signal; `observability-conventions.md`
settles the metric names and cardinality the SLI is computed from; `incident-response.md` owns the
rotation the pages below reach; `machine-topology.md` owns the topology an availability target
obliges you to buy.

Outputs land in `04-quality-scenarios.md` — the availability and latency scenarios and the SLO are
one statement, written once and referenced — and in an ADR per `templates.md`. Every choice below
reaches the human as options with consequences plus your recommendation, per `approaches.md`.

Pick two or three user-facing SLIs — availability and p95 latency, adding freshness only for
pipelines — set targets you can actually miss, and derive alerts from error-budget burn rate rather
than raw thresholds. Page only on fast burn (14.4x over one hour) and ticket slow burn (1x over
three days). Measure at the load balancer or edge, not from application self-report: the app misses
the crashes, deploys and DNS failures that matter.

Without a written error budget policy the SLO is decoration — nothing changes when it is missed,
and the failure mode is a team that alerts on everything (pager fatigue, ignored pages) or on
nothing (customers find your outages first). 100% is the wrong target for everything; the gap below
100% is the budget you spend on deploys and experiments.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| How many user-facing SLIs are measured — none, an uptime ping, availability plus latency, or those plus freshness | the tier: nothing / uptime / SLO / SLO with policy |
| The SLI is measured at the LB or edge rather than from application self-report | edge measurement — self-report flatters itself and misses crashes and deploys |
| A written error budget policy with pre-agreed consequences exists | the budget-policy tier: a spent budget means a freeze or reliability-only work, with a named, expensive override path |
| Alerting on static thresholds rather than burn rate | multi-window multi-burn-rate: page at 14.4x/1h and 6x/6h, ticket at 1x/3d |
| The target is set from a measured baseline rather than an aspirational number | start where your baseline is and tighten later — an aspirational 99.99% on a 99.7% system guarantees a permanent ignored freeze |
| Nobody owns the pager or the budget review | drop to plain SLOs with ticket-only alerts — a policy nobody executes is theatre |
| No request-level telemetry exists | no SLO yet — stand up metrics with error and latency labels first |

## Nothing recorded

- **Use when** never. Even a throwaway internal tool deserves one sentence: "no target, best
  effort, no pager." Recording that *is* the decision.
- **Pros** zero effort.
- **Cons** availability expectations live in stakeholders' heads and diverge silently; the first
  outage becomes a blame negotiation instead of a policy lookup, and customers are your monitoring.
- **Typical mistakes** claiming any availability number in a contract while measuring nothing.

## Basic uptime monitoring

- **Use when** single-team internal tools, prototypes, anything where an hour of downtime costs a
  shrug: an external ping plus an alert on down. Honest and cheap.
- **Pros** minutes to set up, and it catches hard-down.
- **Cons** you learn the site is down, not that it is slow, erroring for 5% of users, or stale —
  partial degradations, which are the majority of real incidents, stay invisible. No budget means no
  principled answer to "can we ship this risky change?"
- **Typical mistakes** pinging the login page while the API that customers pay for burns.

## SLOs with an error budget

- **Use when** the safe default once real users depend on the service: two or three SLOs —
  availability as the non-5xx ratio, and p95 latency — measured at the LB or edge over rolling 30
  days. The budget is 1 minus the target.
- **Pros** "are we reliable enough?" has a number, and the budget prices risky changes and
  maintenance windows.
- **Cons** with no written policy and no burn-rate alerts the budget is a dashboard nobody acts on:
  it burns to zero, features ship anyway, and everyone learns the SLO is fiction.
- **Typical mistakes** 15 SLOs per service, since more than the team can review quarterly means
  none are real; computing the SLI inside the app instead of at the edge.

## SLOs with budget policy and burn-rate alerts

- **Use when** multiple teams, paying customers, or an on-call rotation: a written policy — budget
  spent means a freeze or reliability-only work, with an expensive named override — plus
  multi-window burn-rate alerts.
- **Pros** pages correlate with an actual budget threat, so on-call trusts the pager; and the policy
  makes reliability a negotiated product decision rather than a shouting match.
- **Cons** real setup work — recording rules, per-SLO windows — plus a policy negotiation with
  product leadership and quarterly SLO reviews. Overkill for a single-team internal app.
- **Typical mistakes** a policy whose override is free, which means it will be overridden every
  sprint; paging on slow burn too.

## Burn-rate windows (30-day SLO, Google SRE Workbook)

| Long window | Short window (~1/12) | Burn rate | Budget consumed at alert | Action |
|---|---|---|---|---|
| 1 hour | 5 minutes | 14.4x | 2% of the 30-day budget | Page — this pace exhausts the budget in ~2 days |
| 6 hours | 30 minutes | 6x | 5% of the 30-day budget | Page — sustained burn, budget gone in ~5 days |
| 3 days | 6 hours | 1x | 10% of the 30-day budget | Ticket — fix within days, no 3 a.m. wakeup |

## SLI menu

| SLI | Good default target | Measurement point |
|---|---|---|
| Availability (non-5xx / total) | 99.9% external, 99.5% internal — start at your measured baseline | LB/edge logs, not app self-report |
| p95 latency (successful requests under threshold) | 95% under a threshold users notice, e.g. 400 ms API, 2 s page | LB/edge; exclude client network time |
| Freshness / data age | 99% of reads under X minutes old — only for pipelines, caches, replicas | Timestamp comparison at the read path |
| Durability / correctness | Only for storage or money systems; otherwise skip | End-to-end checker jobs |

## What holds whatever you pick

- Two or three SLOs per service, not 15 — every SLO is a standing promise with a pager attached.
- Measure at the load balancer or edge; an SLI computed inside the app misses the crashes, deploys
  and DNS failures.
- Both windows, long *and* short, must fire before a page — the short window makes the alert stop
  when the incident stops.
- Page only on fast burn; slow burn is a ticket. If a page does not threaten the budget it should
  not wake anyone, and that discipline is the entire cure for alert fatigue.
- No written error budget policy, no SLO: the policy names the consequence and the override path,
  and the override must be rare and expensive.
- 100% is the wrong target for everything; a team with an untouched budget is shipping too slowly.
- Threshold alerts on causes — CPU, disk, queue depth — are dashboards, not pages. Page on
  user-visible symptoms via burn rate.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend two SLIs — availability and p95 latency —
measured at the edge over rolling 30 days, with targets set at the measured baseline and slow-burn
tickets only. Name the trigger that would add the pager and the policy: the first paying customer,
the first on-call rotation, the first contractual availability number. Each trigger is a row in
`07-risks.md` until it becomes a scenario.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which SLIs exist, their
   targets, the measurement point, and whether a written budget policy exists.
2. State the recurring cost of each — the recording rules and windows to maintain, the quarterly
   review, the freeze the policy can impose on the roadmap — and what reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `04-quality-scenarios.md`.
4. Every target becomes a row in `04-quality-scenarios.md` with a number and a unit — the
   availability ratio, the latency threshold and percentile, the freshness window, the burn-rate
   thresholds that page and that ticket. A target with no measurement behind it is not a scenario.
5. An aspirational target with no baseline behind it, a budget policy with a free override, and an
   SLO with no named reviewer are rows in `07-risks.md`. Anything the human leaves open is a
   `TODO(question)` per `templates.md`.
