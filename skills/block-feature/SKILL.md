---
name: block-feature
description: Implementing a feature task in a worker session: TDD, WIP push, self-reporting progress and status into the state repo. Started by the controller after dispatch with the path to the task file.
---

# block-feature

Plugin root: `${CLAUDE_PLUGIN_ROOT}`.

Add the functionality the task describes and finish in status `review` with merge-ready output. The
argument is the task file's absolute path in the state clone; read all of it, it is a self-contained spec
(P4).

## Session contract

Spawned as a block subagent by a `factory solve` coordinator, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md`
replaces this section and steps 1, 8 and 9 below; the brief says which you are. As a session, read
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/session-contract.md` before step 1 and follow it, with the files
it names (`rules.md`, `progress-and-push.md`, `knowledge-review.md`, `delegation.md`). With `mr_url` set in
the frontmatter, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refinement.md` (ADR-0031) replaces the procedure: the
MR exists and your assignment is its review comments.

Deltas: Toolset commands (ADR-0039) you will use are `build`, `test`, `test-filter <expr>`, `coverage`,
`crap <scope>`, `format`, `arch-build`. `worker-explorer` fans out for the bearings, `worker-implementer`
takes a large well-scoped step; the red-green rhythm itself is serial.

## Procedure

1. Write the progress snapshot and run `state-report.sh`. Done when the first heartbeat is in.
2. Get your bearings: `CLAUDE.md`, the affected code, the existing tests. Done when you know what verifies
   `## Acceptance` and where the change belongs.
3. TDD in the smallest steps: a test that fails for the right reason, proved by running `test-filter` over it;
   the smallest code that turns it green, in the stack's idiom
   (`${CLAUDE_PLUGIN_ROOT}/skills/modern-idioms/SKILL.md`); refactor only on a green `test`. WIP push after
   every green, progress snapshot and `state-report.sh` after every milestone.
4. Run the command from `## Acceptance` verbatim. Never edit it to make it pass: it is the single done
   criterion. Done when it exits green, otherwise back to step 3.
5. Do what `## Docs` says, in this branch. Absent or `none` means nothing to do.
6. Quality loop, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/crap-loop.md`: CRAP over the methods this diff touched,
   never the whole repo, the table into the progress file as `## Quality`.
7. **Architecture model** (issue #297), the contract's `## Architecture model`, only if the diff changed
   the architecture.
8. Knowledge review, then deliver per the contract's `## Output`.
9. Self-report `review`.

Nothing from `## Out of scope` enters the diff, not even a few lines. Ideas beyond the task are a note in the
progress file and a follow-up task, never this session (ADR-0014, ADR-0031).

## Implement phase (ADR-0030)

A progress file with a `## Handoff` section means the tests phase ran before you: take your bearings from it
and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/implement-phase.md`, which defines the test lock, the
`## Test deviations` route and the blocked cases. Without `## Handoff` the procedure above runs unchanged.

## As a block subagent

Steps 2 to 7, then the report of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md`. A WIP push is a
commit on the block branch.
