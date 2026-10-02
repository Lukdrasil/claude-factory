# factory done

Ends a task and every one of its blocks in the standalone state repo: the last step of `factory solve`, or a
standalone call once a task is finished. There is no dashboard and no write-back button anywhere; this command
is the gate.

A task ends in one of two ways, and `<plugin-root>/bin/task-done.sh` picks by the parent's `archetype:`:

- **`done`**, for an archetype that opens an MR (feature, bugfix, refactor, review), and only after the human
  validated that MR. A parent whose `mr_url` is `null` is refused.
- **`closed`**, for `triage`, `ops` and `research`, which never open an MR. No `mr_url` is needed or expected.

Either way `owner:` is released to `null` on the parent and on every block in the same commit, and
`state-push.sh` carries that commit to the state root.

## When

- the user says the MR for `T-NNN` is merged / approved / validated and asks to close it out;
- a triage, ops or research task is finished: the draft is written, the ops action is carried out, the report is
  in `repos/<key>/research/`;
- `factory solve` is asked to resume a task already in `review` with a validated MR.

A merged task MR needs none of this by hand: `mr-watch.sh <T-id> --finish` (armed after step 16, and run by
`herd-watch.sh` in the herd) and `review-sweep.sh` (run at every session start) run the Done step themselves and
print `<T-id> done`. Report that line as the Report step says.

## Steps

- **Confirm.** For an MR archetype, ask the user (if not already stated) that the MR named by the task's
  `mr_url` is the one they validated: this reference does not check a forge, it trusts the human's word. A task
  MR that mr-watch reports `merged` is that word already, since only the human merges a task MR: no ask. For a
  triage, ops or research task, confirm the output they asked for exists. Completion: a yes recorded.
- **Done.** Run `<plugin-root>/bin/task-done.sh <id> --state <root>/state`. Exit 1 prints the reason (an MR
  archetype whose parent has no `mr_url`, so the task is not ready to close): nothing was written, show the
  reason and say what the user can do about it. Exit 2 means the terminal status could not be committed
  (the state lock or git): say so. Then `<plugin-root>/bin/state-push.sh --state <root>/state`. Completion: exit 0
  and one new commit `chore(<id>): <from> → <terminal>, blocks included`, pushed.
- **Report.** Name the terminal status the task and its blocks now carry, `done` or `closed`, and that their
  owner is released. Completion: the list is in front of the user.
