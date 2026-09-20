---
written_against: "web research 2026-08"
---

`written_against` names the specification state this rubric was checked against — which OpenTelemetry
semantic conventions are stable, and the ECS-to-semconv succession. A spec page that contradicts it
means this file is stale and needs re-research, not that the solution drifted.

# Observability conventions — log schema, metric names, cardinality, sampling, dashboards

Load this when an observability backend has been chosen and the team is about to instrument
services, or when cross-service debugging already hurts. `operations.md` picks the backend; this
file is the standards layer above that choice. `correlation.md` owns the propagation of the id this
file insists appears in every log line; `logging-and-audit.md` owns what a log line is for and how
long it is kept; `slo-error-budgets.md` consumes the metric names decided here.

Outputs land in `03-containers.md` (the collector as a unit), in `06-deployment.md` (where
dashboards, alert rules and sampling config live) and in an ADR per `templates.md`. Every choice
below reaches the human as options with consequences plus your recommendation, per `approaches.md`.

A backend swap is a migration; a convention swap is a rewrite of every log line and dashboard. So
the conventions matter more than the vendor. Five of them:

- **One JSON log schema** with shared field names — `trace_id`, `span_id`, `service.name`,
  `severity` — and a hard list of what never goes in logs.
- **Metric naming per OTel semantic conventions.** HTTP semconv has been stable since 2023 and
  database since 2025, so use the stable names. ECS was donated to OTel, and semconv is its
  designated successor.
- **An explicit cardinality budget.** Each unique label combination is a separate time series at
  roughly 1-3 KiB of head-block RAM; one `user_id` label on one counter can mint millions of series.
- **A written sampling policy.** Head-based sampling is cheap and predictable but cannot keep "all
  errors", because the outcome does not exist at decision time. Tail-based sampling keeps errors and
  slow traces but needs a buffering collector tier routed by trace-id hash — a round-robin load
  balancer silently breaks it.
- **Dashboards and alert rules checked into the repo.**

The failure mode this prevents: every service logs in its own dialect, cross-service debugging
degenerates into grep archaeology, and high-cardinality labels quietly drive the telemetry bill past
the compute bill.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| One service, one team | a one-page shared field list is enough — but write it down before service two exists |
| Two or more services in one request path | `trace_id` and `span_id` in every log line, or debugging is grep archaeology across dialects |
| A paid backend billing per GB or per series | a cardinality budget and a sampling policy first — conventions are also cost controls |
| Many teams instrumenting independently | OTel semconv end to end — a house dialect needs a police force, and semconv comes pre-policed by the instrumentation libraries |
| Errors are rare and the interesting traces are the failed ones | tail-based sampling at the collector |
| Dashboards rebuilt by hand after every incident | dashboards-as-code, reviewed like any other change |
| Compliance or PII exposure | the never-log list enforced in review *and* a collector redaction processor, not good intentions |

## None (each service its own way)

- **Use when** honest only for a single service read by its own author, and even then only until
  service two.
- **Pros** zero upfront agreement cost.
- **Cons** every cross-service incident starts with reverse-engineering field names; `user` versus
  `userId` versus `uid` makes queries unjoinable; and cardinality and PII discipline exist
  per-developer, which is to say not at all.
- **Typical mistakes** believing the backend's search makes schemas unnecessary — search finds
  strings, it does not join dialects.

## Shared logging schema

- **Use when** few services, one team, and no tracing backend yet: one field list (timestamp, level,
  message, service, `trace_id`, `error.*`) plus a logger wrapper per language.
- **Pros** every log line is queryable the same way; it is cheap; and the never-log list gets a home.
- **Cons** it covers logs only, so metric names and trace attributes still drift; and home-grown
  names diverge from what OTel auto-instrumentation emits, so auto-instrumented telemetry speaks a
  second dialect anyway.
- **Typical mistakes** inventing field names semconv already defines, which you will pay for in a
  later rename; leaving levels undefined, so one service's WARN is another's ERROR and alerts
  misfire.

## OTel semantic conventions end-to-end

- **Use when** the safe default for multiple services or teams: the naming argument is outsourced to
  a spec that instrumentation libraries already follow.
- **Pros** HTTP semconv has been stable since 2023 and DB since 2025, so the names no longer churn;
  auto-instrumentation emits these names for free, and they are backend-portable.
- **Cons** migration friction where old experimental names are deployed; and some domains (GenAI)
  are still in development, so pin what you rely on.
- **Typical mistakes** semconv for traces but legacy log field names, so logs and traces still do not
  join; treating semconv as only metric names, when resource attributes — `service.name`,
  `deployment.environment.name` — are the half that makes filtering work.

## Conventions plus dashboards-as-code

- **Use when** anything beyond a handful of services or one environment: semconv plus dashboards,
  alert rules and sampling config in the repo, via Grafana provisioning or Terraform.
- **Pros** dashboards are reviewed, versioned and reproducible, with per-service dashboards stamped
  from one template; and alert thresholds get a git history and a reviewer.
- **Cons** a tooling investment and a CI step; and UI edits drift from the repo unless a sync
  direction is enforced.
- **Typical mistakes** codifying dashboards but leaving alert rules click-ops — the alerts are the
  part that pages people.

## Convention → rule → what it prevents

| Convention | Concrete rule | What it prevents |
|---|---|---|
| Log format | JSON, one object per line; shared core fields including `trace_id`/`span_id` | Grep archaeology; logs that cannot join traces |
| Field names | OTel semconv where they exist; never invent a synonym | Three names for user id, zero joins |
| Levels | Five levels defined once with examples; ERROR means a human may act, WARN never pages | Alert fatigue from mismatched level semantics |
| Never-log list | No secrets, tokens, passwords, card numbers or full PII; collector redaction as backstop | Credential leaks via log search; compliance incidents outliving the bug |
| Metric naming | semconv names and units (`http.server.request.duration` in seconds) | Two dashboards for the same latency that disagree |
| Cardinality budget | Bounded label values only: no `user_id`, `request_id` or raw URL path; route templates, not raw paths | Series explosion — one unbounded label turns 1k series into millions, then OOM or a five-figure bill |
| Sampling policy | Head sampling (parent-based ratio) as the cheap default; tail sampling at the collector when "keep all errors" is required, with trace-id-hash load balancing in front | Paying to store 100% of healthy traces, or dropping the one failed trace the incident needed |
| Dashboards/alerts | In the repo, generated from one template per service, code-reviewed | Hand-rebuilt dashboards after every incident; environments whose dashboards lie |

## What holds whatever you pick

- Conventions outlive the backend: a backend swap is a migration, a convention swap is a rewrite of
  every log line.
- Use the stable OTel semconv names — a house dialect duplicates a spec auto-instrumentation already
  emits, and you pay the diff forever.
- `trace_id` and `span_id` go in every log line, or logs and traces are two products.
- Cardinality is the metrics bill: every unique label combination is a separate series at roughly
  1-3 KiB of RAM each. Budget labels like money.
- Head sampling cannot keep failed traces, because the outcome does not exist at decision time.
  "Keep all errors" means tail sampling at a collector tier, load-balanced by trace-id hash.
- The never-log list is enforced twice: in code review and in a collector redaction processor.
- Dashboards and alert rules live in the repo — a dashboard that exists only in a UI is one instance
  failure from not existing.
- Adopt conventions before service two; retrofitting a schema across ten dialects is the migration
  nobody schedules.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend OTel semantic conventions end to end, JSON
logs carrying `trace_id` and `span_id`, head sampling at a fixed ratio, and a never-log list
enforced in review. Name the trigger that would add the rest — a paid per-series bill, a requirement
to keep every failed trace, the first dashboard rebuilt by hand after an incident — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: the field list, whether
   semconv is adopted, the cardinality budget, and the sampling policy.
2. State the recurring cost of each — the per-series or per-GB bill the budget is meant to hold, the
   collector tier tail sampling obliges you to run, the CI step dashboards-as-code adds — and what
   reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. The measurable outcomes become rows in `04-quality-scenarios.md` with a number and a unit: the
   sampling rate, the series ceiling per service, the log retention window, and the time to retrieve
   every line of one request.
5. A never-log list with no redaction backstop, a label whose value set nobody has bounded, and
   alert rules that exist only in a UI are rows in `07-risks.md`. Anything the human leaves open is a
   `TODO(question)` per `templates.md`.
