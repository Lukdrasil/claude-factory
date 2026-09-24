# Exploring the code, and the specialist panel

Read alongside steps 3 and 4 of `<plugin-root>/skills/architecture-docs/SKILL.md`. The code is the source of
the `architecture/` drafts and of nothing else: `product/` comes from the human.

## What the code answers

- Deployable units come from build and deploy manifests (solution and package manifests, Dockerfiles,
  compose files, an Aspire AppHost, CI workflows), never from folder names.
- External systems come from outbound clients, connection strings and configuration keys; a channel is the
  concrete protocol and transport, not "the network".
- In `audit`, every claim the existing documents make in scope is looked up in the code. A claim you cannot
  ground is a divergence candidate, not a fact, and not yet a correction either.

## The two-round cap

Looking for the evidence of one claim gets **at most two rounds**: the first sweep, then one more with a
different search. A claim still ungrounded after the second becomes a `TODO(question)` naming what was
searched. There is never a third round: the cost of one more sweep is unbounded and the question is cheap.
`evidence_rounds` in the delivery receipt is the maximum over all claims, not an average.

Fan independent sweeps out to `scout` per `<plugin-root>/skills/_shared/delegation.md`, and verify
every citation that comes back before it enters a draft.

## The panel

Both modes take the full panel. Match the stack and the systems the exploration found against the
`Load when` column of `<plugin-root>/skills/architecture-docs/references/README.md`, and spawn one
`domain-architect` per domain that hits, in parallel. Each prompt carries the domain name, the absolute
product repo path, and the absolute paths of `architect-review/references/checks.md` and this directory's
`README.md`: a specialist preloads no skill, so those paths are how it finds the rubric and the domain index.

Each returns findings inside its own domain and nothing outside it. You synthesize them, into the options in
`bootstrap` and into the divergence list in `audit`, under the merge and arbitration rule in
`<plugin-root>/skills/architect-review/SKILL.md`. Nothing a specialist returns reaches a document before the
human confirms it in the interview.
