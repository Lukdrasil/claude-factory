# factory approve

Flips a task from `draft|triaged|blocked|failed|tests_ready` to `ready` in the standalone state repo.
This is the human's confirmation of a body they read — never a click the coordinator makes for them.

## When

- `factory solve` reaches the end of decompose, with the parent task and its blocks written and waiting;
- the user names a task and asks to approve it directly.

## Steps

- **Show.** Print the task body in full — `# Goal`, `## Context`, `## Acceptance`, the block list when this is
  a decomposed parent. Completion: the human has read the text they are about to approve, not a summary.
- **Ask.** AskUserQuestion: approve as is, or stop here (a "no" leaves the task exactly as it was — edit it by
  hand and ask again, this reference does not edit bodies). Completion: a yes or a no recorded.
- **Approve.** On a yes, run `<plugin-root>/bin/task-approve.sh <id> --state <root>/state`.
  Exit 1 prints the reason (the wrong starting status): show it and stop. Completion: exit 0, two new
  commits in the state repo's log (the status flip, then `plan_hash`).
- **Report.** The task's new `status: ready` and its `plan_hash`. Completion: both are in front of the user.

A recommended `/compact` point sits right after this — the grill and decompose context is spent, and the
blocks ahead each start fresh.
