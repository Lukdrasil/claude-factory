# Auto decisions

The one rule of `factory auto` (`skills/factory/references/auto.md`) for every question a step would put to
the human: the grill rounds, the design round, the proposals round, the spec-critic report, a cut-check
finding, a blocked block's `## Question`, a review round on the task MR. Read it whenever a skill runs with
`--auto`, or the monitor of an auto lane reaches one of those.

**The recommendation is the answer.** Every question is still worked out as the skill says: the options, the
trade-off, the recommendation and why. Then the recommendation is taken, recorded as the answer, and the step
goes on. Nothing is skipped because nobody is asked: a round with no recommendation written is a round that
did not happen.

## When the human is asked

Through `_shared/ask.md`, that one question alone, with the options and the recommendation as written, while
every question that does not hang on it goes on. Ask only when one of these holds:

1. **No recommendation stands.** The options are equal on the evidence you have, and the choice is hard to
   reverse: a schema, a public contract, a dependency, a data format.
2. **The choice leaves the chosen solution.** It adds or drops a feature, changes a public contract the
   `## Solution` of the task did not change, or moves the task's `## Out of scope`.
3. **Destructive or outward-facing.** Data deleted or a migration that loses rows, a forge action beyond the
   task's own MRs, anything that costs money or reaches outside the repository.
4. **Every option fails.** A blocked block whose options all break `## Acceptance` or the behaviour the task
   promises, or a `failed` block at its second attempt.

A permission dialog of a session is none of these: the monitor reads it and asks, as `references/herd.md`
says. The human's own words, in the `## Solution` of the task or in an answer, win over any recommendation.

## The record

- In the grill, the ledger row's `answer` is the recommendation, and `## Decisions` holds it like any other
  decision: one line, `[locked]` when it passes the three gates of `references/ledger.md`. A decision the
  human answered ends with `(human)`, so the MR body tells the two apart; everything else was taken by
  recommendation.
- In a block's `## Question`, the answer line of `_shared/blocked-question.md` reads
  `**Answer (YYYY-MM-DD): option N** (auto)`, or `(human)` when asked.
- In decompose, the spec-critic's agreed edits are its proposed edits as written, and the verdict line is
  written after them; a finding that is a question goes through this file.

The task MR carries every line of `## Decisions` (`mr-open.sh --decisions`), which is where the human reads
what was decided for them.
