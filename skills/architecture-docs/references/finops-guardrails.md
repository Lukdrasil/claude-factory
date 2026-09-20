---
written_against: "web research 2026-08"
---

`written_against` names the pricing and platform state this rubric was checked against — per-GB
egress and NAT gateway processing rates, scan-priced OLAP rates, SaaS telemetry ingestion and
indexing models, and the notification-only behaviour of budget alerts on all three major clouds. A
vendor pricing page that contradicts it means this file is stale and needs re-research, not that
the solution drifted.

# FinOps guardrails — cost as a designed constraint, not an invoice surprise

Load this when any managed cloud service, SaaS observability backend, LLM API or OLAP engine enters
the design, when budget is tight, or when nobody can name the top three cost drivers.
`machine-topology.md` decides how many machines the availability target buys and
`operations.md` decides the telemetry backend; this file decides whether the per-unit meters those
choices switch on are named, capped and owned. `llm-features.md` owns the shape of an LLM feature;
the token bill it generates is settled here.

Outputs land in `02-constraints.md` (the budget and the named cost drivers), in `06-deployment.md`
(the tags, the caps and the alert thresholds), and in an ADR per `templates.md`. Every choice below
reaches the human as options with consequences plus your recommendation, per `approaches.md`.

Cost is an architectural property, not an accounting afterthought. Most organisations can attribute
only 40–60% of cloud spend to an owner, and that unowned spend is where the surprises live. The
mechanics of surprise are per-unit meters nobody modelled at design time: egress at roughly
$0.09/GB; NAT gateway processing at $0.045/GB, which was 39% of one startup's bill; SaaS log
ingestion billed per GB to ingest *and* per million events to index; OLAP scans at $6.25/TiB, where
one `SELECT *` on 10 TB costs $62.50 and a dashboard reruns it hourly; and LLM tokens, where agent
loops resend accumulated context and real incidents have burned four figures before anyone noticed.

Cloud budget alerts are notification-only — they never shut anything down — so pair them with hard
limiters wherever the meter can run away. The safe default from day one is a budget per environment
with alerts at 50, 80 and 100% of both actual and forecasted spend, five mandatory tags enforced at
provisioning, telemetry sampling and retention limits, and a monthly cost review. The failure mode
is that the first signal is the invoice, and the panic response degrades reliability: logs deleted,
replicas dropped under pressure instead of by design.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Which per-unit meters exist in this design (per GB, per scan, per token, per request) | each one is a potential surprise line item — name it at design time with a monthly estimate |
| Budget is tight | guardrails must precede the workload, because one bad month cannot be absorbed |
| A SaaS observability backend | per-GB ingestion turns a chatty debug logger into a billing event |
| LLM usage | token spend scales with loop iterations and context length, not user count |
| Scan-priced OLAP | query cost is decided by query authors, not capacity planners |
| Unallocated spend has no owner | mandatory tags enforced at provisioning — retroactive tagging campaigns always lose |
| An alert-to-action gap | anything that can run away (LLM, autoscale, streaming inserts) needs its own hard limiter |

## Nothing

- **Use when** fixed-price hosting only — one VM or flat-rate PaaS — with zero metered services. One
  metered dependency added later reopens the question.
- **Pros** free until it isn't.
- **Cons** the first cost signal is the invoice, and the response is panic plus reliability-degrading
  cuts.
- **Typical mistakes** keeping "nothing" after the first per-GB or per-token meter enters the design.

## Budget alerts only

- **Use when** a small team, one environment, spend under a few hundred a month, and no SaaS
  telemetry or LLM. Alerts at 50, 80 and 100% of actual and forecasted spend.
- **Pros** minutes to set up.
- **Cons** notification-only, so nothing stops the spend; and without tags you know *that* you
  overspent, not *where*.
- **Typical mistakes** treating the alert as a cap — on all three major clouds it never shuts
  anything down.

## Alerts plus tagging and telemetry limits

- **Use when** the default for any real system with metered services, SaaS observability or LLM
  calls: a budget per environment, five mandatory tags (team, environment, service, cost-centre,
  owner) enforced at provision time via policy, log sampling and retention caps, and an LLM hard
  limiter with a monthly cap.
- **Pros** covers detection through alerts, attribution through tags, and the two fastest runaway
  meters, telemetry and tokens; and it is about a day of work.
- **Cons** tag coverage decays within months without active enforcement.
- **Typical mistakes** retroactive tagging campaigns instead of policy-as-code at provisioning.

## Full allocation and review cadence

- **Use when** multiple teams, showback or chargeback expectations, or spend where 10% waste funds a
  headcount: 90%+ tag coverage with quarantine-then-terminate enforcement, unit-cost metrics, a
  monthly review with a named owner, and anomaly detection.
- **Pros** unowned spend is unmanaged spend, and full allocation makes every line item somebody's
  problem.
- **Cons** an ongoing process cost, and coverage decays without enforcement.
- **Typical mistakes** reviewing dashboards without a named owner and a decision path.

## Cost driver, why it surprises, and the guardrail

| Cost driver | Why it surprises | Guardrail |
|---|---|---|
| egress / data transfer out | per GB (~$0.09) and invisible in architecture diagrams; cross-AZ and NAT surcharges stack | name expected egress GB/month at design time; keep chatty traffic in-region |
| NAT gateway | charges $0.045/GB on *all* traffic through it, including cloud-internal calls that never needed the internet | VPC endpoints for cloud-internal traffic; alert on the NAT data-processing line item |
| SaaS log/telemetry ingestion | billed per uncompressed GB to ingest *and* per million events to index; volume tracks debug verbosity, not traffic | sampling and severity filters at the source, retention caps, index only what you query — from day one |
| OLAP scan pricing | per byte scanned ($6.25/TiB); one `SELECT *` on 10 TB is $62.50, and dashboards rerun hourly | partitioning mandatory, per-query byte limits, capacity pricing above roughly 20–30 TB/month |
| LLM per-token spend | scales with loop iterations × accumulated context, not users; agent loops resend full history each step | a hard limiter: per-call token caps, a per-agent daily budget with cutoff, a monthly provider cap — alerts do not stop a loop |
| autoscaling | scales cost as designed; with no ceiling, a bug or an attack scales the bill too | max-instance ceilings per environment; forecasted-spend alerts |
| untagged resources | 40–60% of spend typically has no owner, and unowned spend is never cleaned up | five mandatory tags enforced at provisioning; quarantine-then-terminate for violations |

## What holds whatever you pick

- Budget alerts per environment from day one, at 50, 80 and 100% of actual and forecasted spend:
  minutes of setup against a full billing cycle of blindness.
- Cloud budget alerts are notification-only on all three major clouds. Every meter that can run away
  needs its own hard limiter.
- Enforce five mandatory tags at provisioning via policy — retroactive tagging campaigns always
  lose.
- Name the top three expected cost drivers in the design doc with a monthly estimate. If nobody can,
  the design review is not finished.
- Telemetry limits are a design decision, not a cost-cutting reaction. Deleting logs during a billing
  panic is how you lose the data for the next incident.
- Per-GB and per-scan pricing means engineers set the bill with every log statement and every query.
  Make unit costs visible to the people writing the code.
- LLM spend needs two independent controls: a limiter in the request path and a monthly cap at the
  provider. Loops defeat alerts.
- A monthly 30-minute cost review with a named owner catches drift while it is small.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a budget per environment with 50/80/100%
actual and forecasted alerts, five mandatory tags enforced at provisioning, telemetry sampling and
retention caps, and a hard limiter on anything that can loop. Then name the top three expected cost
drivers with a monthly estimate each. Name the trigger that would buy full allocation: a second team
sharing the account, a showback expectation, or spend where 10% waste funds a headcount. Each
trigger is a row in `07-risks.md` until it becomes a decision.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the guardrail tier, the tag
   set, and which meters get a hard limiter rather than an alert.
2. State the top three cost drivers with a monthly estimate each, and what the guardrails themselves
   cost in setup and ongoing process.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `02-constraints.md` and `06-deployment.md`.
4. A meter with no limiter, untagged resources, an alert with no owner, and a cost driver nobody
   estimated are rows in `07-risks.md`, each with an owner. Anything the human leaves open is a
   `TODO(question)` per `templates.md`.
