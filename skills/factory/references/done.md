# factory done

Flips a task and every one of its blocks to `done` in the standalone state repo, after the human validated
the MR — the last step of `factory solve`, or a standalone call once a `review` task's MR merged.

## When

- the user says the MR for `T-NNN` is merged / approved / validated and asks to close it out;
- `factory solve` is asked to resume a task already in `review` with a validated MR.

## Steps

- **Confirm.** Ask the user (if not already stated) that the MR named by the task's `mr_url` is the one they
  validated — this reference does not check a forge, it trusts the human's word. Completion: a yes recorded.
- **Done.** Run `<plugin-root>/bin/task-done.sh <id> --state <root>/state`. Exit 1 prints the reason
  (no `mr_url` on the parent — the task is not ready to close): show it and stop, nothing was written.
  Completion: exit 0 and one new commit `chore(<id>): review → done, blocks included`.
- **Report.** The task and its blocks now `status: done`. Completion: the list is in front of the user.
