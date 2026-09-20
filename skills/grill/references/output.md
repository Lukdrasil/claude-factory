# Output

## Proposed tasks

Cut the spec into task proposals: one task is one independently verifiable result, one branch, one MR. Draw
the boundaries where the result can be verified, not along layers. Per proposal decide and justify in one
sentence: `tier`, `archetype` and `complexity` per `<plugin-root>/skills/_shared/tiers.md`; `depends_on`,
only proposals from this plan and no cycles; `docs`, `none` or the docs this task updates in the same branch;
`design`, the members of `## Program design` this task implements, by file and name, `none` only for a
`research` proposal. A proposal that changes public behaviour or architecture and still says `none` for docs
needs the one sentence why. Decompose does not remake these decisions; `decompose.sh` copies them 1:1.

## The plan file

Print the skeleton and fill it in:

```sh
sh <plugin-root>/bin/task-template.sh plan-ready
```

Write it to `<state>/repos/<repo-key>/plans/<slug>-plan-ready.md`, where `<slug>` is two to four words from
the spec, lowercase and hyphenated, and commit it from `<state>`. The plan is an artifact: it outlives the
session and shows up in the diff.

`task:` is the id of the draft task this grill hung off, the only link back: the blocks become its
`T-NNN-NN` children and carry its forge issue. `none` when the grill ran before any task existed.

Then lint it:

```sh
sh <plugin-root>/bin/plan-lint.sh <state>/repos/<repo-key>/plans/<slug>-plan-ready.md
```

Every line it prints is a must of the grill you have left open. Fix the plan and run it again; a plan that
does not pass does not go to plan-check.

## Plan-check

Resolve the product clone for `<repo-key>`. When it has `docs/architecture/`, run the `plan-check`
invocation of the `architect-review` skill over the plan. Findings come back to the human as proposed edits,
and editing the plan afterwards invalidates the verdict, so re-run `plan-check` on the edited plan.

Done when `<state>/repos/<repo-key>/verdicts/<slug>.md` exists and its `plan_hash` is the hash of the plan
you hand on. A clone with no `docs/architecture/` has nothing to curate: skip it and say so in one line. A
clone you cannot resolve is a stop-and-ask.

## Finishing

Show the human a summary in at most 12 lines: the spec in one sentence, one line per proposal (title, tier,
archetype, depends_on), out of scope, and the path to plan-ready.md. No recap of the interview, they were in
it. Then say the next step is the `decompose` skill over this file; do not create the tasks yourself.
