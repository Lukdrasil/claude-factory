# Block session

Read by a block that `factory herd` runs as its own interactive session (`bin/session-monitor.sh`), not as a
subagent: `block-tests` in its tests phase, the archetype skill (`block-feature`, `block-bugfix`, ...) in its
implement phase or as a single-phase block. You follow that skill as a session, with
`_shared/session-contract.md`, and this file replaces the delivery of both: the monitor, the session that
dispatched you, verifies, reviews, opens and merges the block MR (`skills/factory/references/herd.md`).

## Binding

- Claim first, the command your prompt opens with, and snapshot the progress file: you own the block and its
  progress file, never the parent, another block or the task MR.
- cwd is the block worktree on the block branch. `git push` only that branch; no rebase onto the base, no MR,
  no `mr-open.sh`, `block-mr.sh` or `block-mr-merge.sh`, no merge. The guard keeps every human gate from you.
- The tests phase is `block-tests` as written: the red tests, the pushed branch, `## Handoff` and the red run
  under `## Evidence` in the progress file, then self-report `tests_ready`.
- The implement phase starts from the `## Handoff` in the progress file. With `phase: implement` armed the test
  files are locked: turn them green, never bend them.
- A single-phase block (no `## Handoff`, no tests phase before you): red first, and the first commit on the block
  branch carries the new tests alone; name that commit under `## Red proof` in the progress file.

## Delivery

In place of the skill's delivery and the contract's `## Output`:

1. Run `## Acceptance` verbatim, and the toolset's `test-filter` over the tests this block touched.
2. `git push -u origin <block branch>`.
3. Rewrite the progress file: `## Done` with one bullet per step you finished, `## Evidence` with each proving
   command, its exit code and the key output line, and `## Red proof` for a single-phase block.
4. The knowledge review of the skill, lessons as proposals (`_shared/knowledge-review.md`).
5. Self-report `review` with `mr_url` left `null`: the monitor reruns your evidence, runs `block-verify.sh`, the
   code-reviewer and the architecture-auditor, opens the block MR and merges it.

A human decision is `blocked` with `## Question` (`_shared/blocked-question.md`), a contract you cannot meet is
`failed` with its `## Attempts` line, as in the skill.
