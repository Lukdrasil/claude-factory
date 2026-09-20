# Block subagent

Read by every agent a `factory solve` coordinator spawns into a block worktree: `factory-block-tests`,
`factory-block-implement` and `factory-block-implement-medium`. It replaces `_shared/session-contract.md`
and its siblings: you are not the session. The coordinator owns the state repo, the progress file, the push,
the MR, the self-report and the knowledge review. You own the worktree and your final message.

## Binding

- cwd is the block worktree on the block branch. Work nowhere else, never in the clone.
- The brief carries the task path, the archetype, the phase, the approved design, `## Acceptance`, the
  `## Handoff` of the tests phase when one ran, and the toolset command table. Read the task file in full.
- Never: `git push`, an edit of the task file or of anything under the state clone, `state-report.sh`, an MR,
  a proposal, a knowledge review. Commit on the block branch after every green.
- `## Acceptance` is never edited. Nothing from `## Out of scope` enters the diff.
- Every test or build command runs under `timeout 15m` (`_shared/test-budget.md`); a cap that fires is a
  line in your report, never a wait.
- The hooks refuse, they do not remind: a test-file write once `phase: implement` is armed
  (`_shared/implement-phase.md`), a comment with no class prefix, an em dash. The deny message carries the fix.

## Phase tests

`block-tests`, from the blast radius through the red tests: baseline green, characterization tests, red
tests that fail for the right reason. Production code stays untouched. Your report ends with the `## Handoff`
section `task-template.sh handoff` prints, filled in.

## Phase implement

The archetype skill the brief names, `block-feature`, `block-bugfix` or `block-refactor`, from the bearings
through the architecture-model step: red-first TDD, acceptance verbatim, `## Docs`, the CRAP table of
`_shared/crap-loop.md`, the model only when the diff changed the architecture. With a `## Handoff` in the
brief the red tests are the contract (`_shared/implement-phase.md`). Without one, the block is single-phase
and the red tests are your first commit on the block branch, test files only, before any production code;
the coordinator checks that commit out and runs them red itself, so a red test folded into a later commit is
a block with no proof. Every member follows
`modern-idioms/SKILL.md`, every comment line `comment-policy/SKILL.md`, every log call and catch block
`logging-decisions/SKILL.md`.

## Report

Your final message, nothing else:

```markdown
## Ran
- `<command>` -> exit <n>, `<the key line of its output>`

## Red proof
<single-phase implement only: the SHA of the tests-only first commit, the test files in it, the exit code of the red run>

## Quality
<the CRAP table of crap-loop.md; implement phase only>

## Handoff
<the filled-in handoff; tests phase only>

## Lessons
<at most one line, Why plus evidence; omit the section without one>
```

The coordinator reruns `build`, `test`, the red tests and `crap` over your diff before anything is merged. A
claim with no command behind it is not read.
