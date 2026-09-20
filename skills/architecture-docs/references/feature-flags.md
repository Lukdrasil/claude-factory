---
written_against: "web research 2026-08"
---

`written_against` names the product and licence state this rubric was checked against —
OpenFeature's CNCF status, flagd's Apache-2.0 licence, Unleash's move to AGPLv3 for the server at
v8 and the end-of-life date of its OSS Edge, and LaunchDarkly-class pricing per service connection
plus client-side MAU. A vendor page that contradicts it means this file is stale and needs
re-research, not that the solution drifted.

# Feature flags — separating deploy from release, and who cleans up afterwards

Load this when release strategy, progressive delivery, rollback plans, dark launches or kill
switches are in scope — or when a rollback plan mentions reverting migrations.
`release-strategy.md` owns how a new version replaces the old one and why schema rollback is not
real; this file owns the mechanism that makes rollback a flag flip instead of a redeploy.
`delivery-pipeline.md` owns what builds and promotes the artifact the flags live inside.

Outputs land in `03-containers.md` when a flag backend becomes a unit of its own, in
`06-deployment.md` (where the backend runs, and what the safe default is when it is unreachable),
and in an ADR per `templates.md`. Every choice below reaches the human as options with consequences
plus your recommendation, per `approaches.md`.

Deploy and release are two different events, and a flag system is what separates them. Without
one, every risky change is all-or-nothing at deploy time, and "rollback" means redeploying old code
— often entangled with a migration that will not roll back. With one, rollback is a one-second flag
flip.

The safe default is simple config flags while one team ships. Once more than one team ships, front
the flags with OpenFeature — the CNCF vendor-neutral SDK — backed either by a self-hosted provider
(flagd for minimal GitOps-driven evaluation, or the Unleash class for a management UI) or by a
vendor platform of the LaunchDarkly class. Note the licence movement: the Unleash server is AGPLv3
from v8, and its OSS Edge reaches end of life on 31 December 2026.

Flags rot. Every flag gets an owner and an expiry at creation, and a flag sitting at 100% for N
days is a cleanup ticket, not a permanent fixture.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Rollback today means `git revert` plus a redeploy entangled with migrations | a flag flip in seconds — the single biggest determinant of incident duration for bad releases |
| Multiple teams shipping to the same runtime | targeting, percentage rollout and an audit trail — or coordinated release trains return |
| Flag changes must propagate without a redeploy | config-file flags defeat the kill-switch use case for anything urgent |
| Expensive features (LLM calls, third-party APIs, heavy queries) | a kill switch wired before launch, not after the first bill |
| Low tolerance for vendor lock-in | code against OpenFeature, so the backend is a swappable provider rather than a rewrite |
| A self-hosted flag backend is another service | it must be more available than what it gates — or fail to safe defaults |
| Vendor pricing scales with client-side MAU | cheap for backend-only flags, expensive for high-MAU client apps |

## None

- **Use when** a solo project or prototype where every deploy takes under a minute and no change is
  entangled with data migrations.
- **Pros** zero infrastructure, zero flag debt, zero conditional branches.
- **Cons** rollback is a redeploy, which is impossible in practice when the bad code shipped with a
  schema migration; and there are no dark launches, so branches live long, and no kill switch, so a
  broken feature stays on until a fix ships.
- **Typical mistakes** multiple teams coordinating release trains because nobody can decouple their
  risk.

## Config-file flags

- **Use when** a single team, small scale, and the risky changes are backend behaviours where
  per-environment on/off is enough. The default starting point.
- **Pros** near-zero cost, and it decouples merge from release so unfinished code ships dark; good
  enough for kill switches if the config hot-reloads.
- **Cons** changing a flag usually means a deploy or restart, which degrades the one-second flip to
  one redeploy; and there is no percentage rollout, no cohort targeting and no audit trail, so flags
  silently become permanent settings.
- **Typical mistakes** being dishonest about whether a flag change is really faster than a deploy in
  your setup.

## OpenFeature with a self-hosted backend (flagd, Unleash class)

- **License** OpenFeature and flagd are Apache-2.0; the Unleash server is AGPLv3 from v8, and its
  OSS Edge reaches end of life on 31 December 2026.
- **Use when** more than one team ships, ops capacity exists, and either budget is tight or
  residency rules out a vendor. Use flagd if the team lives in GitOps; use the Unleash class if
  non-engineers need a UI.
- **Pros** OpenFeature makes the backend swappable, so you can start with flagd and move without
  touching call sites; percentage rollouts, cohort targeting and runtime flips arrive without
  redeploys; and data and evaluation stay in your infrastructure, with no per-MAU bill.
- **Cons** another service to run that must be up — or fail to safe defaults — for everything it
  gates; and flagd has no UI and no audit trail, so flag edits are config commits.
- **Typical mistakes** ignoring Unleash licensing shifts, with an AGPLv3 server and OSS edge paths
  moving to paid tiers; running the flag backend with less availability than the features it gates.

## Vendor platform (LaunchDarkly class)

- **License** proprietary SaaS, priced per service connection plus per 1,000 client-side monthly
  active users.
- **Use when** multiple teams, a normal budget, and nobody wants to run flag infrastructure —
  especially when non-engineers manage releases or audit and approval workflows are needed. Front
  it with OpenFeature so the vendor stays replaceable.
- **Pros** mature progressive delivery on day one — targeting, audit, approvals and flag-lifecycle
  tooling; SDKs cache locally, so a vendor outage degrades to stale flags rather than a down app;
  and stale-flag detection is built in, which is hygiene tooling humans will not do manually.
- **Cons** cost scales with client-side MAU, so a high-traffic consumer app pays thousands a month
  for flag evaluation; and flag data and targeting attributes leave your infrastructure, which is a
  compliance conversation in regulated shops.
- **Typical mistakes** coding against the vendor SDK directly instead of OpenFeature;
  over-adopting experimentation add-ons that creep the bill.

## Rollout styles

| Rollout style | What it needs | When it pays |
|---|---|---|
| all-at-once (flag on for everyone) | any flag system, even config-file | low-risk changes; still beats no flag at all, because off is one flip away |
| percentage rollout | runtime flags with stable bucketing, plus error and latency dashboards split by flag state | diffuse risk — 5% of traffic surfaces problems before 100% suffers them; pointless without flag-attributed monitoring |
| canary-by-cohort | targeting rules on user or tenant attributes (staff first, then friendly tenants) | B2B and multi-tenant products, where blast radius means specific customers |
| kill switch | runtime evaluation with sub-second propagation, a safe default when the backend is unreachable, and a named owner who may flip it without a meeting | every expensive or externally dependent feature — wired before launch |

## What holds whatever you pick

- Separate deploy from release the moment a rollback story involves the words "revert the
  migration".
- Front every flag call site with OpenFeature once you outgrow config files, so the provider becomes
  an ops decision rather than an application rewrite.
- Every flag gets an owner and an expiry at creation. A flag without both is technical debt with no
  collection date.
- A flag at 100% for N days is a cleanup ticket, automatically. Every stale flag doubles the
  untested state space around it.
- Kill switches are wired before launch and evaluated at runtime with a safe default when the
  backend is down. The flag system must never be less available than what it gates.
- Percentage rollout without flag-attributed monitoring is theatre.
- Long-lived operational flags — kill switches and ops toggles — are a different species from
  release flags. Label them, so cleanup automation does not nag and release flags cannot hide among
  them.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend config-file flags with hot reload for a
single team, one kill switch per expensive or externally dependent feature, and an owner and expiry
recorded on every flag from the first one. Name the trigger that would move you to OpenFeature with
a real backend: a second team shipping to the same runtime, a rollback plan that has to survive a
migration, or a percentage rollout anyone actually wants. Each trigger is a row in `07-risks.md`
until it becomes a decision.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the flag mechanism, which
   features get kill switches, and the safe default when the backend is unreachable.
2. State the recurring cost of each — the MAU-scaled vendor bill, the self-hosted backend's
   availability obligation, the flag-cleanup effort — and what reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `06-deployment.md`.
4. A flag with no owner or expiry, a flag backend less available than what it gates, and a
   percentage rollout with no flag-attributed monitoring are rows in `07-risks.md`, each with an
   owner. Anything the human leaves open is a `TODO(question)` per `templates.md`.
