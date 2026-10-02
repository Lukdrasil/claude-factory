# Auto decisions

The one rule of `factory auto` and `factory autonom` (`skills/factory/references/auto.md`) for every question
a step would put to the human: the grill rounds, the design round, the proposals round, a plan-check or
cut-check finding, the spec-critic report, a blocked block's `## Question`, a review round on the task MR.
Read it whenever a skill runs with `--auto` or `--autonom`, or the monitor of such a lane reaches one of
those.

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
5. **The change reaches a surface a person sees.** The grill's UI round
   (`skills/grill/references/ui-round.md`): whether to mock the result up with variants to pick from, or to
   leave the look to the agent, and the pick of a variant after a mockup. How a thing looks is the human's
   call, so no recommendation is taken for them here; a task whose text already settles it (a design to
   build against, or the look left to the agent) is that answer, and the round is skipped.
6. **A solution session dead twice** with no file, in step 4a of `references/auto.md`: the human is told
   through `_shared/blocked-question.md`. Under `--autonom` the pick is made over the one solution that
   exists, and only both sessions dead twice reach the human.

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

## Autonomous

Under `--autonom` (`factory autonom`, `references/auto.md`) the cases above are not asked either, bar two.
Cases 1, 2, 5 and 6, and the pick of step 4a, are **analysed and decided by the session**:

1. Write the analysis as the `explore` table of the grill: one row per option, two to four pros and cons
   each, specific to this repository, over goal fit, size of the change, risk, the tests it needs and what it
   leaves worse. For the pick of step 4a the rows are the two solutions; for the UI round the rows are the
   variants, drawn as `ui-round.md` says, and the mockup page is still written so the MR reviewer sees what
   was chosen against.
2. Decide for the option the table favours. Equal rows go to the smaller change, then to the one that stays
   inside the chosen solution, then to the one easier to reverse.
3. Record it: the table into the grill file (or the block's progress file, or the task's `## Solution` as its
   why), and the decision line ending with `(analysed)`, so the MR body tells it from a recommendation taken
   and from a human's answer.

**Cases 3 and 4 are still asked**, autonomous or not: data deleted, a migration that loses rows, a forge
action beyond the task's MRs, a cost; and a block whose every option breaks the acceptance, since no table
can pick an option that fails and a block is never closed by a session (`state-report.sh` refuses it). A
block blocked again after an answer the lane gave (`(auto)` or `(analysed)` in its progress file) is the
fourth case too: the analysis did not unblock it, and a third answer over the same ground is a loop. A
permission dialog of a session is still the human's, through the monitor. A human who wants case 3 gone too
says so in the task text, in words, and that line is the answer. The pick of step 4a is the first line of
the plan's `## Decisions`, `(analysed)` or `(human)`, so the MR body carries it.
