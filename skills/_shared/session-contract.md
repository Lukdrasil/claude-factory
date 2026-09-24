# Session contract

The session mechanics of the implement archetypes, read with `<plugin-root>/skills/_shared/rules.md`,
`<plugin-root>/skills/_shared/progress-and-push.md`, `<plugin-root>/skills/_shared/knowledge-review.md` and
`<plugin-root>/skills/_shared/delegation.md`. An archetype's delta wins.

## Preconditions

- cwd is the task worktree `<plugin-root>/bin/worktree-add.sh <task-id>` printed, on the branch from the
  frontmatter; otherwise change nothing and self-report `failed`.
- The state clone is `$WORK_DIR/state` (ADR-0049: the worktrees are `$WORK_DIR/<key>/<T-NNN>`, so the clone is
  not a sibling of cwd). `WORK_DIR` comes from your environment, and the SessionStart context names the same
  path in its "Factory context for repo `<key>` from the state repo at `<WORK_DIR>/state`" line. Only in the
  older layout, where the clone really is next to the worktree, is it `../state`; `ls $WORK_DIR/state` is what
  settles it in one call.
- `<id>`, `<key>` and `<branch>` come from the frontmatter; the progress file is
  `$WORK_DIR/state/repos/<key>/progress/<id>.md`.
- This repo's memory arrives as SessionStart additionalContext, not as a file: a standalone worker has no
  `CLAUDE.md` in cwd to read. Its **toolset** section (ADR-0039) binds command names to what this repo runs;
  call them by name, never guess a stack.
  A command the toolset does not have is not a failure: note it in the progress file and move on.

## Architecture model

The architecture is LikeC4 DSL in `docs/architecture/*.c4` (issue #297), so it moves in the branch that
moves the architecture.

**Update the model only when the diff changed the architecture.** The trigger is a closed list: a component
or module added or removed; a dependency direction changed; a new external service; a new public endpoint.

**Anything else changes nothing.** A diff that stays inside one component, added methods, an extracted class,
a rename, a fixed defect, an internal refactor, leaves the `.c4` files untouched. The model stops at C4
level 3 on purpose: a hand-maintained code level dies of churn. Not updating is the normal outcome and needs
no note.

When the list fires, edit the `.c4` files in the same branch as the code, run toolset `arch-build`, and paste
`sh <plugin-root>/bin/arch-delta.sh <repo> <base-branch>` into the progress file. A red `arch-build` is red
like any other. No `arch-build` in the toolset is the Preconditions case above: note it, never a failed task.

## Output

1. `git fetch origin && git rebase origin/<base>`, `<base>` being `default_branch` for `<key>` in
   `../state/repos.yml`. Resolve conflicts here, never `--skip` and never a blind `--ours`/`--theirs`; one
   you cannot reconcile inside the task's scope is `blocked`.
2. Run acceptance again: a rebase can break what was green.
3. `git push --force-with-lease=<branch>:<sha> origin <branch>`, the only rewrite permitted and only on a
   working branch: a block's own branch, and the parent's `branch:` for the parent's owner, pushed as
   `git -C <parent worktree> push …`. Never the default branch or any other; the policy guard refuses those.
4. `sh <plugin-root>/bin/mr-open.sh <id>` builds the description and opens the MR idempotently; what it says
   and never says is `<plugin-root>/skills/_shared/mr-description.md`.
5. Write the web URL it printed into `mr_url`, then report. No forge means the output is the pushed,
   conflict-free branch and `mr_url` stays `null` (ADR-0014).

## Self-report

| status | when |
|---|---|
| `review` | acceptance ran green, the fresh run recorded under `## Evidence`, and the output exists |
| `blocked` | you need a human decision; question per `<plugin-root>/skills/_shared/blocked-question.md` |
| `failed` | acceptance could not be met; `state-report.sh --task <id> --attempts "<N>, <model>, <why>"` |

You write `status:` and `mr_url:`, nothing else: `attempt` and `plan_hash` are the controller's, `ready` and
`done` the human's (P5). Never write `done`, `ready` or `stalled`, and never a status or an `owner` on a task
that is not yours.

The one exception is your own claim: the task you were dispatched for goes `in_progress` under your own owner
string, through `state-report.sh` and never by hand, as step 1 of your archetype spells out.

The posture is standalone unless `DASHBOARD_URL` is set in your environment, which it usually is not: there is
then no dashboard anywhere, every human gate is a command (`task-approve.sh`, `task-done.sh`, `factory approve`
/ `factory done`), and telling the user to do something in a dashboard is always wrong.

## WIP push and liveness

`git push -u origin <branch>` after every green, never `--force`. Report progress before a long operation or the
watchdog declares you `stalled` (ADR-0009). Every run carries the cap in
`<plugin-root>/skills/_shared/test-budget.md`.
