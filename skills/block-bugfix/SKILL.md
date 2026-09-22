---
name: block-bugfix
description: Fixing a defect in a worker session: reproduce with a test, smallest possible fix, WIP push, self-reporting progress and status into the state repo. Started by the controller after dispatch with the path to the task file.
---

# block-bugfix

Plugin root: `${CLAUDE_PLUGIN_ROOT}`.

Fix the defect the task describes and finish in status `review` with merge-ready output. The argument is
the task file's absolute path in the state clone; read all of it, it is a self-contained spec (P4).

## Session contract

Spawned as a block subagent by a `factory solve` coordinator, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md`
replaces this section and steps 1, 9 and 10 below; the brief says which you are. As a session, read
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/session-contract.md` before step 1 and follow it, with the files
it names (`rules.md`, `progress-and-push.md`, `knowledge-review.md`, `delegation.md`). `mr_url` set in the
frontmatter means `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refinement.md` (ADR-0031) replaces the procedure.

Deltas: Toolset commands (ADR-0039) here are `build`, `test`, `test-filter <expr>`, `coverage`,
`crap <scope>`, `format`, `arch-build`. `worker-explorer` fans out while you hunt the cause; the
reproduction test you write yourself, as the contract of the fix.

## Procedure

1. **Claim the task, then snapshot.** The claim is one command, and the exact one, so nobody has to read
   `state-report.sh` to find it:

   ```sh
   sh ${CLAUDE_PLUGIN_ROOT}/bin/state-report.sh --task <id> --set-status in_progress --owner factory@<host>:<session_id>
   ```

   `factory@<host>:<session_id>` is the owner string of your SessionStart identity line, verbatim; the
   owner-based Stop lookup finds this task only under it. The command is the same whether the task is still
   `ready` or was already claimed `in_progress` for you under a `pending-<id>` owner. Then write the progress
   snapshot and run `state-report.sh --task <id>` again: that is the first heartbeat.
2. **Reproduce the defect with a test** that fails on the current code, on exactly what the task describes.
   Fix nothing before it exists. A defect you cannot reproduce is `blocked`, not a guess.
3. Find the cause, not the symptom, and write one sentence about it into the progress file; nobody learns
   it anywhere else. Done when it explains the failing test.
4. The smallest fix that turns the test green (`test-filter`), in the stack's idiom
   (`${CLAUDE_PLUGIN_ROOT}/skills/modern-idioms/SKILL.md`), then the whole suite green: a regression is worse
   than the defect. WIP push after every green, snapshot and report after every milestone.
5. Run the command from `## Acceptance` verbatim, never edited. Green, or back to step 3.
6. Do what `## Docs` says, in this branch; absent or `none` means nothing.
7. Quality loop, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/crap-loop.md`: CRAP over the methods this diff
   touched, never the whole repo, the table into `## Quality`.
8. **Architecture model** (issue #297), the contract's `## Architecture model`, only if the diff changed
   the architecture; a fix in place did not.
9. Knowledge review, then deliver per the contract's `## Output`.
10. Self-report `review`.

A fix revealing a wider problem never widens the task: the finding is a note and a proposed follow-up
(ADR-0014).

## Implement phase (ADR-0030)

A progress file with a `## Handoff` section means the tests phase ran before you and step 2 is done:
confirm the red tests still fail as described, then hunt the cause under
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/implement-phase.md`, which defines the test lock, the
`## Test deviations` route and the blocked cases. Without it the procedure runs unchanged.

## As a block subagent

Steps 2 to 8, then the report of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md`. A WIP push is a
commit on the block branch.
