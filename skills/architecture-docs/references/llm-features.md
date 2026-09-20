---
written_against: "as of 2026-08 — hosted frontier APIs (Anthropic, OpenAI, Google) alongside open-weights served locally; schema-constrained structured output and tool calling first-class on all major providers; gateway/router products (LiteLLM class) and eval tooling mature but consolidating; dated model snapshots retired on published sunset schedules"
---

`architecture-docs audit` diffs this stamp against what it finds in the repo to tell "the provider
landscape moved" from "this file is stale" — bump the line when a section's guidance changes, not on
every edit.

# LLM features — decision rubric

Load this when a recorded requirement is answered by a model call. An LLM feature adds a dependency
with failure modes no other dependency has at once: non-deterministic output, latency measured in
seconds and varying by an order of magnitude, a per-token cost per call, and a new injection surface
carrying whatever an attacker can get into the context.

The driver question, before any option below: **which recorded requirement needs generation or
reasoning over open-ended input, and which needs a deterministic feature a model would merely
decorate?** Classification over ten known labels, arithmetic, lookup, ranking by a writable rule —
each has an exact implementation a model makes slower, costlier and wrong 2% of the time. Put the
deterministic option on the table as a real option, and record why it lost.

Where the result lands: each model call is a `Talks to` edge in `03-containers.md` with its failure
mode annotated (what the user sees when the provider is slow, down, or returns something unparseable);
latency and cost are `QS-` rows with numbers; the prompt-injection surface is a trust boundary in
`security.md`'s threat-model pass; the eval set is the acceptance mechanism, itself a `QS-` row. The
rule from `approaches.md` holds — two options minimum, each argued against `QS-` and `C-` ids, your
recommendation with its driver, the human decides.

## Choosing by driver

| Signal in the recorded scenarios / constraints | Decision it forces | Options to put on the table |
|---|---|---|
| A user waits for the output on screen | Interaction shape | synchronous streamed call · async job with notify |
| The work takes more than a few seconds, or fans out over several calls | Interaction shape | async job · agent loop behind a job |
| The model chooses which action to take, not just what to say | Interaction shape + tool boundary | fixed workflow of calls · agent loop with an authorised tool set |
| The action the model triggers is irreversible or externally visible | Human-in-the-loop | auto-execute · propose-then-approve · approve above a threshold |
| Prompts carry personal, health, financial or customer-confidential data | Provider coupling | provider with a residency + zero-retention term · self-hosted open weights |
| Token spend is unbounded by the request rate (free tier, public surface) | Cost control | per-user quota · cheaper model per route · gateway budget enforcement |
| The answer lives in the product's own data | Context architecture | retrieval · long context with the documents inlined · neither, if it fits the prompt |
| Output is parsed by code rather than read by a person | Output contract | schema-constrained structured output · tool call · free text plus a parser |
| Nobody can say whether a change to the prompt made it better | Evaluation | offline eval set gating deploys · online signals only · both |

## Interaction shape

The core decision: it fixes UX, timeout budget, failure surface and blast radius at once. Drivers are
the latency budget in `04-quality-scenarios.md`, the reversibility of what the feature does, and
whether a human must see the result before it takes effect.

### Synchronous inline call

The handler calls the model and answers on the same connection, streaming tokens as they arrive.
Record time-to-first-token, total completion and the call's explicit timeout as `QS-` rows.

- **Use when** the user is watching, p95 completion fits a latency scenario a person tolerates while
  output appears, and the feature only produces text.
- **Pros** no queue, job store or notification path; streaming makes seconds feel responsive;
  cancellation is the client closing the stream.
- **Cons** a thread and a connection held for the whole generation, so capacity is concurrency-bound;
  a provider slowdown becomes a backlog of held connections; a retry re-pays for spent tokens.
- **Typical mistakes** no streaming, so a 20-second call looks like a hang — SSE is the push channel
  for token streams, see `communication.md`; no timeout, so the request inherits the provider's; proxy
  buffering that withholds the stream (`deployment.md` owns proxy settings); no non-LLM fallback, so
  provider downtime is feature downtime.

### Asynchronous job

The request enqueues work, returns an id, and the result arrives by polling, SSE or a notification.

- **Use when** the work runs longer than a few seconds, must survive a restart, needs bounded retry,
  or fans out over several calls. The honest default for anything but a short interactive answer.
- **Pros** the provider's latency variance stops being the request's; retry and rate-limit backoff
  live in the worker; spend is throttled by worker concurrency; partial results can be persisted.
- **Cons** job store, worker, status surface and delivery path are real components in
  `03-containers.md`; the UI renders pending, failed and stale states; a duplicated job is duplicated
  spend, so the enqueue needs an idempotency key.
- **Typical mistakes** unbounded retry against a deterministic provider error, turning one failure
  into a bill; no dead-letter path, so failed jobs are invisible (`message-bus.md` owns queue and DLQ
  semantics); the job id absent from the model call's logs, so a complaint cannot be traced
  (`correlation.md`); results held only in memory, lost on the next deploy.

### Agent loop

The model calls tools, reads results, and decides the next step until it stops. Record max steps and
token budget per run as `QS-` rows, every tool as a `Talks to` edge with its authorisation answer (see
below), and the approval gate as a runtime step in `05-runtime.md`.

- **Use when** the sequence of steps cannot be written in advance, the task needs several rounds of
  retrieval or action, and every tool the loop can reach is one you grant unconditionally.
- **Pros** covers tasks whose decomposition is unknown at design time; one loop replaces a
  combinatorial set of hand-written flows; new capability arrives as a new tool.
- **Cons** the widest blast radius of the three — every tool is a standing capability grant the model
  decides when to use; cost and latency per task are unbounded until bounded; the path differs run to
  run, so reproducing a failure means replaying the trace; an injected tool result steers every later
  step.
- **Typical mistakes** a fixed pipeline dressed as an agent, paying for non-determinism that buys
  nothing — if the steps are known, write the workflow; no step, token or wall-clock ceiling, so a run
  loops until the budget alarm; write tools with no approval gate; tool results treated as trusted
  input; no per-step trace, so the only artifact of a failed run is the wrong answer.

**Human-in-the-loop** is a separate axis, decided by reversibility: auto-execute what is cheap to
undo, propose-then-approve what is not — money movement, outbound messages, deletions, production
writes, anything a customer sees. Record the threshold, not the intention.

## Provider coupling

Prompts are user data leaving your trust boundary, so this is a `C-` row before it is a preference:
where inference runs, what the provider retains, and whether the content may train a model are
contract terms to read, not defaults to assume.

- **Direct provider API.** **Use when** one provider covers the need, volume does not yet justify an
  intermediary, and the feature leans on provider-specific capabilities (tool-use shape, prompt
  caching, a batch endpoint). **Pros** no hop to run; new capabilities available the day they ship.
  **Cons** credential, quota and spend controls are yours to build; a second provider is a second
  integration; the vendor's outage is yours. **Typical mistakes** the API key in application config
  rather than the secret store (`operations.md`); no per-tenant spend cap on a public surface; SDK
  types spread through the domain, so no call site can be substituted in a test.
- **Gateway or router in front of providers.** **Use when** spend must be attributed and capped
  centrally, several models serve different routes, or cross-provider failover is a stated
  availability requirement. **Pros** one place for keys, quotas, budgets, caching and token telemetry;
  cheap and expensive models addressable per route. **Cons** another hop on the latency budget and
  another component to run and page for; its failure takes every feature with it. **Typical mistakes**
  the abstraction-layer trap — a lowest-common-denominator interface erasing provider-specific
  capabilities produces code optimal on none of them, the same counter-truth as the message-bus
  wrapper in `message-bus.md`: abstract credentials, retries and telemetry, keep semantics visible at
  the call site. Also failover to a model no eval scored for that route — a silent quality drop.
- **Self-hosted open weights.** **Use when** a constraint forbids the data leaving (residency,
  contract, regulated class), steady volume makes fixed GPU cost beat per-token pricing, or the model
  must be frozen for years. **Pros** prompts never cross the boundary; no vendor deprecation clock;
  flat, predictable cost. **Cons** GPU capacity to size, run and patch; a real capability gap on
  reasoning-heavy tasks; serving throughput becomes someone's job; idle capacity is paid for.
  **Typical mistakes** benchmark-driven model choice with no eval on the product's own task; sizing
  for average load; treating it as ops-free because the weights are free.

**Model-upgrade churn applies to every hosted option.** Behaviour drifts on the provider's schedule and
dated snapshots retire on published sunset dates — a floating alias changes phrasing, refusals,
tool-call formatting and token usage with no error in the logs; a pinned snapshot fails loudly on its
date. Pin the dated version, subscribe to the deprecation notice, make "re-run the eval set against the
replacement" the migration step, and name the pinned id in the approving ADR.

## Prompt and context as a versioned contract

Prompt template, tool schemas, output schema and retrieval configuration together determine the
behaviour. They are a deployable artifact, not content: version them with the code, review changes as
code, tie each eval run to the version it scored.

- The unit an ADR approves and an eval scores is the **pair** — this prompt version against this model
  version. A result carried over from another pair is not evidence.
- Where code parses the output, constrain it: schema-enforced structured output or a tool call, schema
  in the repo. Conformance is now reliable enough to retire parse-and-repair loops, but conformance is
  not correctness — the eval still measures whether the fields are right.
- The output schema evolves under the same rules as any contract in `communication.md`: added optional
  fields are safe, renamed or removed fields break the parser.
- **Typical mistakes** the prompt edited in a production console or a database row with no diff, review
  or eval run; templates assembled by string concatenation, so user text and instructions are
  indistinguishable; a schema change shipped ahead of its parser; few-shot examples drifted out of sync
  with the schema; the model id hardcoded in three places.

## Retrieval and context architecture

Reach for retrieval when the answer lives in **your** data, that data changes, and it is too large to
inline. That is the whole test.

- **Long context, documents inlined** — when the corpus fits the window at acceptable cost and latency.
  No index, no sync path, no staleness, nothing to rebuild. Costs: tokens per call scale with the
  corpus, and accuracy degrades as irrelevant content crowds the window.
- **Retrieval (RAG)** — when the corpus exceeds what is affordable to inline, or freshness matters more
  than a training run can hold. Costs: the index is a **second store** needing what every second store
  needs — a named owner, an explicit sync path from the source of truth, and a staleness row saying how
  far behind it may fall (`data.md`). Retrieval quality becomes its own measurable thing, separate from
  generation quality.
- **Fine-tuning** — for stable behaviour, format and tone, not for facts. Facts baked into weights go
  stale and need another training run to correct; it is the option most often chosen for a problem
  retrieval solves.
- **Rebuildability is the property to protect.** Chunking strategy and embedding model are part of the
  index's identity — changing either invalidates every stored vector. Version both, and make a full
  rebuild from the source of truth a documented, exercised path, like a restore drill.
- **Typical mistakes** an index built once by a script nobody kept; source deletions that never reach
  the index, so the model cites content the user removed; retrieval ignoring the caller's permissions,
  making the index a bypass around authorisation; no answer to "did the right chunks come back", so
  every quality problem is blamed on the model.

## Guardrails and the tool boundary

Prompt injection is untrusted-input handling, not a novelty: anything reaching the context — user text,
a retrieved document, a web page, a tool result, a file — can carry instructions, and no filter removes
that class of risk. Design so that a successful injection cannot do much.

- **Layer the filtering as a decision, not a product purchase.** Model-side controls (system prompt
  discipline, refusal behaviour, provider safety settings) are cheapest and weakest; app-side checks
  (schema validation, allow-lists, PII detection, length limits) are deterministic and testable; a
  human gate is the only layer holding against a determined attacker. Pick per action, driven by what
  that action can do.
- **Every tool an agent can call is a `Talks to` edge in `03-containers.md`**, needing what any boundary
  crossing needs: who is the caller, whose authority the call carries, what it may reach, what is
  logged. Scope tools to the acting user's own permissions rather than a service account with
  everything — `security.md` owns the authorisation model; this file insists only that the question is
  answered per tool, in writing.
- **Data exfiltration through tool results is the named failure mode.** A loop holding both a
  confidential read tool and any outbound channel (HTTP fetch, email, a webhook, a remote image URL)
  can be talked into moving one into the other. Break the pair, or gate the outbound step.
- **Typical mistakes** trusting a filter to make injection impossible; a read-only design that quietly
  gained a write tool with no re-review; tool results concatenated into the prompt with no marker
  separating them from instructions; the agent acting as a shared admin credential; exposure recorded
  as a prose paragraph instead of `R-` rows with owners.

## Evaluation as the quality scenario

An LLM feature with no eval set is unreviewable: nobody can say whether a change improved it, and there
is nothing to run against next quarter's model. The eval set is the acceptance mechanism, and it
belongs in `04-quality-scenarios.md` with numbers.

- **Offline evals** — a fixed set of inputs with expected outcomes, scored against one prompt+model
  pair, run in CI before deploy. Build it from real traces, especially failures, and express the target
  as any other `QS-` row: an accuracy, groundedness or task-completion rate with a number and a floor
  that gates the deploy.
- **Online signals** — thumbs, correction rate, abandonment, escalation to a human, retry rate. They
  measure what users actually got; they lag, and they exist only if the UI collects them. Feeding
  low-scoring production traces back into the offline set is how regression coverage grows.
- **LLM-as-judge** covers what no assertion can check, with caveats worth writing down: it is a
  classifier, so calibrate it against human labels before its scores gate anything; a narrow pass/fail
  question calibrates far better than a broad quality score; pin the judge's own model version, or it
  silently re-scores your history.
- **Regression evals on provider updates** are the standing obligation: the set runs against every
  candidate replacement model before the pin moves, not after the sunset email.
- **Cost and latency are observability, not finance.** Token spend per feature — and per tenant on a
  public surface — is a metric with an owner and an alert threshold, alongside p95 latency and provider
  error rate (`operations.md` owns backend and alerting). Prompts and completions carry user data, so
  what enters a log or trace follows `logging-and-audit.md`, the trace id is on every model call per
  `correlation.md`, and stored prompts get a retention answer.
- `testing.md` owns the strategy this sits beside: evals score a non-deterministic output against a
  threshold; they do not replace deterministic tests around the feature — parsing, tool
  implementations, job lifecycle, guardrail checks.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the reversible, small-blast-radius set: one
hosted provider called directly behind one thin internal seam, a pinned dated model, structured output
wherever code parses the result, an async job for anything over a few seconds and a streamed
synchronous call otherwise, no agent loop and no write tools until a fixed workflow has proved
insufficient, retrieval only once the corpus outgrows the context window, and a twenty-case eval set
committed with the first prompt. Record the trigger that would change it — a residency clause, a second
provider for failover, a spend curve outrunning the request rate — in `07-risks.md`.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected `QS-` and `C-` ids, the
   recurring token cost, and what changing it later costs — for context architecture and provider choice
   that means rebuilding an index or re-running evals, so say so. Include the deterministic non-LLM
   option wherever one exists.
2. Give one recommendation with the driver behind it. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`, rejected options as its alternatives with the
   reason each lost. The ADR names the **pinned model id and prompt version** it approves, and is
   referenced from `03-containers.md` beside the edge.
4. Annotate `03-containers.md`: every model call is an edge naming provider, synchronous or queued, its
   timeout, and what the user sees when it fails; every agent tool is its own edge with its
   authorisation answer; a vector store or job store is a container with an owner.
5. Every measurable outcome becomes a `QS-` row with a number and a unit — time to first token,
   completion p95, cost per request or per tenant per month, accuracy or groundedness floor, max agent
   steps and token budget per run, index staleness. An attribute with no row is recorded as not
   applicable, with its reason.
6. Prompt data crossing the boundary is a `C-` row where a contract or regulation fixes it, and a trust
   boundary in `security.md`'s threat-model pass either way. Accepted injection exposure, an unevaluated
   fallback model, an index with no rebuild path and an unowned spend line are `R-` rows in `07-risks.md`
   with owners. Anything left open is a `TODO(question)` per `templates.md`.

**Done when** every model call in `03-containers.md` is visible as an edge with its failure mode and
timeout; latency, cost and output quality each have a `QS-` row or a recorded not-applicable; and every
tool an agent can call is listed with the answer to who authorises it.
