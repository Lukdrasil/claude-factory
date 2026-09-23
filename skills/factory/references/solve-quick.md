# factory solve --quick

One small change in one worktree, edited by you. No blocks, no subagents, no grill.

## Entry

`factory solve <T-NNN> --quick`, or a task whose `tier` is green and whose `complexity` is low. One ask
(`_shared/ask.md`) covers both the consent to the quick lane and the approval of the task body; a no sends the
task to the full flow in `references/solve.md`.

## Exit back to the full flow

Stop and restart under `references/solve.md` as soon as any of these is true:

- the change reaches more than 3 files or about 50 lines;
- it touches a `db-schema` or `api-contracts` path;
- it needs more than one test file;
- the acceptance is not a single runnable command;
- the first attempt ends red.

Nothing done so far is lost: the task, the worktree and the branch carry over.

## Steps

1. `<plugin-root>/bin/task-new.sh --repo <key> --file <draft>`, the draft from
   `<plugin-root>/bin/task-template.sh task`.
2. `<plugin-root>/bin/task-approve.sh <id>`, then
   `<plugin-root>/bin/state-report.sh --task <id> --set-status in_progress`.
3. `<plugin-root>/bin/worktree-add.sh <id>`.
4. Edit in that worktree yourself. A bugfix starts with the failing test.
5. The repo's `build` binding, then its `test-filter` binding scoped to the touched tests, then `format`.
6. `## Evidence` in the progress file: the commands and their exit codes.
7. `<plugin-root>/bin/mr-open.sh <id>`, with `mr-issue-linker` on haiku for the issue lines.
8. `<plugin-root>/bin/state-report.sh --task <id> --set-status review`.

## Skipped

The investigation, the grill, the architect plan-check and cut-check, the decompose, `dag-check.sh`, the
block worktrees and their subagents, `block-verify.sh`, `block-merge.sh`, the full suite, `crap`,
`arch-build` and the `factory-reviewer` pass. The human reviews the MR instead.
