# Progress and push

## Progress snapshot

`$WORK_DIR/state/repos/<key>/progress/<id>.md`, a rewritten file (the state clone, ADR-0049).
Read mid-flight: **under 200 words**, one line per bullet, the state in the first line. Cite
`path/file.ext:line` or a SHA instead of retelling; what you considered and declined stays out.
`worktree-add.sh` creates the file, so it exists before your first snapshot: Read it before you Write or Edit it.
When the task has a `## Checklist`, `## Remaining` arrives seeded with its steps as `- [ ] <step>`; a finished
step moves to `## Done` as `- [x] <step>`.

```markdown
# <id>: <task title>
**<on track|blocked|acceptance green>**: the one thing a reader needs now.

## Done
- what is genuinely finished and verified

## In flight
- what you are working on right now

## Remaining
- what is still missing for acceptance

## Evidence
- `<the proving command>` → exit 0, `<the key line of its output>`

## Last milestone
One sentence: what you got done most recently.
```

## Evidence

Before self-reporting `review` or `tests_ready`, run the proving command **fresh in this session**, for
`review` the acceptance command (after the rebase, where the archetype has one), for `tests_ready` the red
tests failing for the right reason, and
record the command, its exit code and the key output line. The Stop hook bounces a `review`/`tests_ready` without it.

## Report

The task's `status:` and the progress file are written only through `state-report.sh`, which validates the
transition, commits in the state clone and pushes when the state clone has an origin (ADR-0050). There is no
dashboard, so never send the user to one: a task with an MR ends in `done` and a triage, ops or research task
ends in `closed`, both through
`<plugin-root>/bin/task-done.sh <id>` once the human has said so, and `ready` comes the same way, from
`<plugin-root>/bin/task-approve.sh <id>`. Rewrite the progress file, then:

```sh
sh "<plugin-root>/bin/state-report.sh" --task <id> [--set-status <status>]
```

The first report of a session is its claim, and it carries two more flags, `--set-status in_progress` and
`--owner`; the archetype's step 1 has the exact line.

`<plugin-root>` is the plugin root the skill that sent you here names. Run it at every milestone and
before a long operation (ADR-0009). Exit 1 = refused, the reason is on stderr; fix it and run again. Exit 2 = the push did not land; the local commit stays, note it and carry
on. A state clone with no origin is the state root itself: the report stays local and exits 0. The Stop hook reports for you at the end.

A **new file** of your own, a research report, an ADR or memory proposal, a plan, still goes through git:

```sh
git -C "$WORK_DIR/state" add repos/<key>/research/<id>-<slug>.md
git -C "$WORK_DIR/state" commit -m "research: <id>" -- repos/<key>/research/<id>-<slug>.md
if git -C "$WORK_DIR/state" remote get-url origin >/dev/null 2>&1; then
  git -C "$WORK_DIR/state" pull --rebase --autostash -X theirs && git -C "$WORK_DIR/state" push
fi
```
