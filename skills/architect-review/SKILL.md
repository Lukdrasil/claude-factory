---
name: architect-review
description: Architecture curation of a grilled plan and of a task cut before the tasks are written, plan-check after the grill and cut-check after decompose, ending in the verdict file the architect gate reads. Use when the product repo has docs/architecture/; repos without those docs skip curation.
---

# architect-review

Two invocations, one contract. Both run in the session that precedes the task write, and both are
interactive: the reviewer reports, the human decides.

| invocation | when | input |
|---|---|---|
| `plan-check` | after the grill, before decompose | `repos/<key>/plans/<slug>-plan-ready.md` in the state clone |
| `cut-check` | after decompose, before the task write | the proposed task markdown, still in its temporary files |

## Preconditions

- cwd is the state clone. `<key>` comes from the plan's frontmatter `repo:`, `<slug>` from the plan file name.
- The product clone for `<key>` resolves and has `docs/architecture/`. Without those docs there is nothing to
  curate: skip the invocation, write no verdict file, and say so in one line.
- The curation runs at every tier. Tier decides how hard a finding is argued and whether the specialist panel
  of step 5 fires, never whether the check runs.

## Steps

1. Read `references/checks.md`, the rubric the reviewer judges by and the one you read its report against,
   and `references/axes.md`, the five axes it draws findings from.
2. On a `cut-check`, fix the scope first per `references/cut-check.md`: an unchanged plan narrows the review
   to the cut itself and fires no specialist panel.
3. Run `sh ${CLAUDE_PLUGIN_ROOT}/bin/doc-facts.sh <product-repo>` and
   `sh ${CLAUDE_PLUGIN_ROOT}/bin/doc-cites.sh <product-repo>` and hand both outputs to the reviewer with the
   input; the agent has no Bash.
4. Spawn the `plan-architect` agent with the invocation name and the absolute paths of the input, the
   product repo and `references/checks.md`. It runs on a fresh context and returns a report, never an edit.
5. Match the input's scope against the `Load when` column of `architecture-docs/references/README.md`. One or
   two touched domains, or a plan whose every proposal is `green`: the reviewer loads those rubrics itself.
   Three or more at `yellow`, or any `red` tier: spawn one `domain-architect` per domain, in parallel,
   each carrying the same absolute paths plus that index.
6. Check every finding carries its axis, a severity and evidence a human can open. Send an unevidenced
   finding back once; if it returns unevidenced, drop it.
7. Synthesize one report and one verdict, whatever the panel size, arbitrating where two domains contradict
   each other and recording the trade-off as a finding of its own.
8. Write the verdict file per `references/verdict.md`, show the human the report as proposed edits, and let
   them choose: edit and re-run, reopen the grill, or accept the risk. You never decide a finding away.
9. Commit and push: with plan-ready for `plan-check`, before the task write for `cut-check`.

**Done when** `repos/<key>/verdicts/<slug>.md` carries the current `verdict` and a `plan_hash` that matches
plan-ready.md, every touched domain has a rubric or a specialist report behind it, and every finding in the
report has evidence.
