---
written_against: "web research 2026-08"
---

`written_against` names the product and specification state this rubric was checked against — k6's
AGPL-3.0 relicensing, Gatling core's and Locust's permissive terms, and the CNCF incubating status
of Chaos Mesh and LitmusChaos. A vendor page that contradicts it means this file is stale and needs
re-research, not that the solution drifted.

# Load and failure testing — proving the capacity and resilience claims

Load this when the design claims a capacity number, an autoscaling behaviour, an HA failover, or a
retry and timeout policy that nobody has ever watched work — especially before a launch or a
campaign. `testing.md` decides the distribution and kinds of functional tests; this file is
narrower and different in kind: it asks how you prove the non-functional claims made elsewhere.
`machine-topology.md` is where the sizing and failover claims are written; `operations.md` owns the
telemetry, alerting and health probes that make a failure experiment readable rather than
confusing.

Outputs land in `04-quality-scenarios.md` (each claim restated as a measurable scenario with a
threshold), in `02-constraints.md` as the policy that a launch requires a passing run, and in an
ADR per `templates.md`. Options reach the human with consequences plus your recommendation, per
`approaches.md`.

Every sizing and resilience decision in an architecture document is a claim, not a fact, until a
test has forced it to happen. Load tests verify capacity claims; failure injection verifies
resilience claims. The safe default is a scripted k6 or Locust run against staging with thresholds
derived from your SLOs, wired into CI before launch, plus a game-day failure drill at least
annually. Skipping this means the launch spike is your first load test and the first real outage is
the first time your failover runs — the two worst possible moments to learn.

Tool licensing is a real 2026 input rather than a footnote: k6 is AGPL-3.0, which is fine for
scripted runs; Gatling core and Locust are permissive; Chaos Mesh and LitmusChaos are CNCF
incubating. `licensing.md` owns the question when a licence family is the thing actually in
dispute.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Untested capacity claims | the real ceiling gets discovered by the launch spike, in production, with customers watching |
| Resilience patterns that never engaged | retries, breakers and failover paths rot silently until the outage that needed them |
| Pass criteria not derived from SLOs | "it didn't crash" is not a result — codify thresholds so CI fails, rather than a human shrugging |
| Undersized staging | a green run against a quarter-scale environment licenses nothing about production |
| Autoscaling in the design | scale-up speed, cooldowns and quota limits only reveal themselves under a realistic ramp |
| Game days test people and runbooks | most outages are prolonged by humans, not code |
| No observability | injecting failures produces confusion, not confidence — match chaos maturity to platform maturity |

## None

- **Use when** internal tools with a known small user base and no SLO anyone is held to.
- **Pros** zero cost.
- **Cons** the launch spike is the load test, and the first outage is the failover drill.
- **Typical mistakes** advertising a launch while never having pushed 1.5× forecast peak.

## One-off load test before launch

- **Use when** the first launch of a modest service, where you need one honest capacity number and
  cannot yet invest in pipeline integration.
- **Pros** better than nothing — one measured number.
- **Cons** the number expires the day the code changes; without SLO thresholds it degenerates into
  "looked fine", and no resilience claim is tested at all.
- **Typical mistakes** testing against an environment sized nothing like production.

## Repeatable load tests with SLO thresholds

- **License** k6 AGPL-3.0; Locust MIT; Gatling core Apache-2.0.
- **Use when** anything with an SLO, autoscaling or a marketing calendar — the safe default:
  version-controlled scripts with pass/fail thresholds codified from the SLOs, run in CI on a
  cadence and before every major launch.
- **Pros** performance regressions fail the build instead of the launch; repeatability, so you can
  re-run after any hot-path change.
- **Cons** it costs a maintained staging environment sized honestly, plus someone who owns the
  scripts; and it proves nothing about failure behaviour.
- **Typical mistakes** thresholds invented rather than derived from the SLO; letting the scripts rot
  after the first launch.

## Load tests plus failure injection (game days)

- **License** Chaos Mesh / LitmusChaos Apache-2.0 (CNCF).
- **Use when** high availability is claimed, resilience patterns exist in the design, or an
  error-budget policy is in force: kill a pod, drop a dependency, exhaust a pool — as scheduled game
  days, annually at minimum, with runbooks exercised and findings tracked.
- **Pros** the only tier that proves resilience claims rather than asserting them; it tests people
  and runbooks, not just software.
- **Cons** it requires observability good enough to see what the injected failure did; start in
  staging and graduate toward production as confidence builds.
- **Typical mistakes** chaos in a system with no observability, which produces confusion rather
  than confidence; treating runbook gaps found during a drill as footnotes instead of launch
  blockers.

## Claim made elsewhere → the test that proves it

| Claim | Test that proves it | Tool fit |
|---|---|---|
| Sizing: "a pair of 8-core boxes handles peak" | ramp to 1.5× forecast peak against a production-like environment, with SLO thresholds as pass criteria | k6 / Locust / Gatling in CI |
| Autoscaling: "we scale out under load" | a spike test with a realistic ramp; verify scale-up latency, cooldowns and quota headroom before saturation | k6 spike scenario plus platform metrics |
| HA failover: "the standby takes over" | kill the primary during live synthetic load; measure actual failover time and error rate | Chaos Mesh / Litmus pod-kill, cloud fault injection |
| Retry/timeout policy: "we degrade gracefully" | drop or delay the dependency under load; confirm retries back off, the breaker opens, the fallback serves | network-fault injection |
| Connection pool sizing | exhaust the pool deliberately under load; confirm queuing or shedding instead of cascade | load test at saturation plus fault injection |
| DR: "warm standby comes up in N minutes" | a scheduled game-day failover to the standby, timed, with the runbook followed verbatim | game day, annually at minimum |
| Error-budget alerting pages in time | inject SLO-violating errors in a drill; confirm the alert fires and on-call responds per runbook | game day plus synthetic errors |

## What holds whatever you pick

- A capacity number nobody has measured is a guess wearing a suit — test to at least 1.5× forecast
  peak before any launch you advertised.
- Pass criteria come from SLOs or they are theatre; codify them as machine-checked thresholds so CI
  fails, not a human shrugs.
- Test the environment you deploy to, honestly sized.
- Repeatability beats heroics: version-control the scripts, run them in CI, and re-run after any
  hot-path change.
- Every resilience pattern in the design must have been observed engaging at least once — an
  untriggered failover is undocumented behaviour.
- Match failure-injection maturity to platform maturity: pod kills and dependency drops in staging
  first, production experiments only with observability that can tell you what happened.
- Run game days on a calendar — annually as the floor, quarterly for high-availability systems — and
  treat runbook gaps as launch blockers.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend one version-controlled load script with
thresholds derived from whatever SLO exists, run in CI and before launch against the most
production-like environment available, and one scheduled game day exercising the single most
load-bearing resilience claim in the design. Name the trigger that would expand it — a signed
availability target, an error-budget policy, an autoscaling claim, a marketing campaign with a
known date — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: which claims get proven,
   against which environment, with which thresholds, and on what cadence.
2. State for each what it costs — the honestly sized staging environment, the script owner's hours,
   the game-day day itself — and what an unproven claim costs if it turns out to be wrong at launch.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, restate each proven claim as a measurable scenario in `04-quality-scenarios.md`,
   and record the launch gate as a constraint in `02-constraints.md`.
4. A capacity number nobody measured, a resilience pattern nobody has watched engage, thresholds
   nobody derived from an SLO, and a staging environment sized nothing like production are rows in
   `07-risks.md`. Anything the human leaves open is a `TODO(question)` per `templates.md`.
