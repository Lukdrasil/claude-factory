---
name: solution
description: One solution to a triaged task from one point of view, written as a research file in the state clone - open, the solution you would defend in a design review, or min, the fewest changes that meet the goal. Two sessions on two models run it side by side as step 4a of factory auto, and the human picks between them. Use when factory auto dispatches it, or when the user asks for a solution proposal for a task.
---

# solution

You propose, the human picks. You implement nothing, change no task and ask nobody: every choice you would
put to the human is a row of `## Open questions` with your recommendation, and the pick between the two
solutions is the monitor's ask, never yours.

```
/claude-factory:solution <task file> --view open|min
```

The task file is `repos/<key>/tasks/<id>-<slug>.md` in the state clone; with no path, stop and say so. The
view is required.

| view | what it is |
|---|---|
| `open` | no point of view imposed: the solution you would defend in a design review, the shape the code should have, whatever it costs in edits |
| `min` | the fewest changes that meet the goal: the smallest diff, existing types and paths reused, no new abstraction, no refactor that the goal does not need; what it leaves worse is named under `## Risks`, not hidden |

Two sessions run this skill over one task, one per view and on different models, so the human sees two real
alternatives. Write yours without guessing at the other: a `min` that argues for the open shape, or an `open`
that trims itself to look cheap, gives the human one solution twice.

## Preconditions

- `<state>` resolves as in `skills/grill/SKILL.md`: ascend from cwd to a `repos.yml`; a brief naming the clone
  by absolute path overrides the walk.
- The task carries `## Context` with the investigation of triage; its report is
  `<state>/repos/<key>/research/<id>-investigation.md`. Without it, stop: the solution would be a guess.
- The product clone is read-only throughout. You run in the task worktree, detached at the base, and the
  guard refuses every write there.

## Steps

1. Read the task, the investigation report and the code they name. Facts you still need come from the code,
   read-only, or from a `scout` subagent; never from the human.
2. Write `<state>/repos/<key>/research/<id>-solution-<view>.md`, under 700 words, these sections in this
   order and none left out:

   ```markdown
   # Solution (<open|min>) for <id>

   ## Problem
   One paragraph: what is wrong or missing, in the terms of this repository.

   ## Approach
   The solution in a few sentences, and why this shape: what it keeps, what it changes.

   ## Changes
   One line per file, `new` or `existing`, the members that change and what each one does.

   ## Tests
   One line per test file, `new` or `existing`: its path and what it proves. The end-to-end test the change
   needs, or `no e2e`. Every behaviour of ## Approach is covered by a line here.

   ## Quality
   How every changed method stays at or under the toolset's crap threshold (8 by default): the extraction
   or the test that keeps it there, and any method that cannot, with why.

   ## Risks
   What can break, what this leaves worse, what a reviewer should look at first.

   ## Size
   Files touched, lines about, migrations, config, rollout steps.

   ## Open questions
   One line per decision the grill has to settle, with your recommendation.
   ```

3. Commit it in the state clone, never in the product clone:

   ```sh
   sh ${CLAUDE_PLUGIN_ROOT}/bin/state-commit.sh -m "research: <id> solution <view>" --state <state> -- repos/<key>/research/<id>-solution-<view>.md
   ```

4. Say in one line where the file is. No summary of it: the monitor shows both files to the human.

**Done when** the file exists with every section, is committed in the state clone, and the task and the
product clone are unchanged.
