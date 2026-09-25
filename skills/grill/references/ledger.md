# Gap ledger

The only evidence the grill happened. Every gap is a row with a type, never a note in your head.

| type | what it is | who closes it |
|---|---|---|
| `decision` | a choice between options the code cannot answer | only the human |
| `research` | a fact about the existing system | you, reading code and ADRs read-only, the answer into the row |
| `prototype` | a question code answers faster than a discussion would | throwaway code, only the finding survives |

A `prototype` row about how something looks can be closed by a drawn visual in the page instead, with
`ui: docker` in herdr: `references/visual-brief.md`. Only its finding goes into the row.

Every row carries `deps`: the rows it depends on, `-` for a root, so the design tree stays readable in the
plan. A deferred question is closed, not left open: its answer is `deferred:` and what would reopen it, and it
goes to `## Out of scope`. A reopened row is open again until the human answers it.

The ledger is clean when every row is `closed` and carries an answer. Only then comes the design round.

## Locked or routine

A closed `decision` is **locked** when it passes all three gates: hard to reverse, surprising without its
context, and a real trade-off. It goes into `## Decisions` tagged `[locked]`, with every rejected option and
why it lost, so nobody re-decides it in a block session and plan-check can hold it against the ADRs. Every
other decision is routine: one line, no tag.

## Terms

Keep `## Terms` as the vocabulary settles: the term, a one-sentence definition, and the words to avoid for it.
Use the terms in every later question, the proposals and the program design.

## What the loop must ask

- **What documentation describes the behaviour this change touches**: README quickstart, runbook, API
  contract, architecture model. `none` is an answer, not asking is not. It becomes the task's `## Docs`.
- **Acceptance driven down to a command.** "Check that the export works" is not acceptance. Keep asking
  until a command or test decides done/not-done on its own once it has run: a toolset command (`test`,
  `test-filter <expr>`, `build`), `sh tests/x.test.sh`, `curl ... | jq -e ...`. If that is not reachable,
  it is a `decision` gap, not a finished task.
- **A proposal says what must be true when it is done, never how the environment is configured.** Name the
  command, never its binding: the binding is regenerated per dispatch, a task body is immutable.
- **A `red` proposal gets quality scenarios.** Ask for the measurable quality requirements the whole spec
  has to hold and record them as `QS-NN` rows in `## Quality scenarios`, columns as in
  `docs/architecture/04-quality-scenarios.md`. Every attribute on that list is covered; one the human rules
  out is recorded as `not applicable`. A row is done when its measure is a number with a unit;
  "fast" is a `decision` gap, not a scenario.
- For a `red` implement proposal over critical logic you may *offer* `mutation <scope>` with a threshold as
  a second acceptance ingredient (issue #298). It is an offer decided here, per task: the runs are slow, and
  it is never the default for a tier.

## Dry run

Before closing the grill, walk the plan as if you were about to implement it: what would you not know in the
first minute? That is an open gap, back into the loop.

Then the doc-fact sweep over the product clone:

```sh
sh <plugin-root>/bin/doc-facts.sh <product-repo>
```

It prints every numeric claim in `docs/**`, `CONTEXT.md` and `README.md` that the repo can count beside the
real number; a repo without `docs/architecture/` prints a skip line. Every mismatch this plan would create is
a `decision` row whose answer is which task owns the update, in the branch that falsifies the count, never a
follow-up task. Declining a claim is an answer; leaving the row open is not, and neither is fixing a number
yourself. A mismatch the plan does not touch is a declined row carrying that reason.
