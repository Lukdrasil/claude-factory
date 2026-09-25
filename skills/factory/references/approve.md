# factory approve

Flips one or more tasks from `draft|triaged|blocked|failed|tests_ready` to `ready` in the standalone state repo.
This is the human's confirmation of a body they read, never a click the coordinator makes for them.

## When

- `factory solve` reaches the end of decompose, with the parent task and its blocks written and waiting;
- the user names a task and asks to approve it directly.

## Steps

- **Show.** Print the task body in full, `# Goal`, `## Context`, `## Acceptance`, the block list when this is
  a decomposed parent. Completion: the human has read the text they are about to approve, not a summary.
- **Ask.** One ask (`_shared/ask.md`): approve as is, or stop here (a "no" leaves the task exactly as it was:
  edit it by hand and ask again, this reference does not edit bodies). Completion: a yes or a no recorded.
  With `ui: docker` the ask carries `flow: approve`, or inside `factory solve` its step 9 line, and the
  browser shows it as a confirm in the approve panel of the task drawer, beside the whole body.
- **Approve.** On a yes, run `<plugin-root>/bin/task-approve.sh <id>... --state <root>/state` once, with
  every id the yes covers: a decomposed parent and its blocks, or every parent of a request (the CEO's plan
  approval) in dependency order. One lock, one commit, no push (the monitor pass and the CEO loop run
  `state-push.sh`). Every id is checked before anything is written: exit 1 prints the reason for the first id
  that cannot be approved (unknown, archived, `in_progress`, a `# Goal` that cannot be an MR title) and
  approves none of them; show it and stop. A `warning:` line names a depends_on that is not done yet: the
  approval stands and the queue waits for it; show it. Exit 2: written but git refused the commit; show it.
  Completion: exit 0 and one new commit in the state repo's log (two when a body was edited by hand and not
  committed: that body first, so `plan_hash` pins it).
- **Report.** Each `<id> ready <plan_hash>` line and every warning. Completion: all are in front of the user.

A recommended `/compact` point sits right after this, the grill and decompose context is spent, and the
blocks ahead each start fresh.
