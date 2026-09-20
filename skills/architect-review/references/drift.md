# Drift and boundaries

The docs are the reference, but they can be stale. When the repo plainly contradicts the document, record it
as a **suggestion** with both pieces of evidence and point at an `architecture-docs audit` for the area. Do
not quietly re-read the plan against the code instead: a stale document is its own finding. A hand-written
inline C4 fence in a repo carrying a `docs/architecture/*.c4` model is the same drift and the same severity.

A **recorded fact this plan falsifies** is this axis too. `<plugin-root>/bin/doc-facts.sh` is a first pass
over the arithmetic part, the counts the repo can count; the claims it has no pattern for are exactly the
ones a reviewer is for. "No external consumer", a container's responsibility sentence, a QS measure written
as prose. Read the sweep the calling session hands you, then go looking for the claims it cannot count.

## Not this skill's findings

Leave these where they belong, so the human gets one decision per report and not three:

- a spec a fresh session could not finish: `spec-critic`
- test coverage, code quality, security of an implementation: `block-review`
- technology preferences with no constraint, scenario or ADR behind them: nothing at all

