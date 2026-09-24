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
transition and commits in the state clone under the state lock (ADR-0050). Nobody pushes by hand: the push to
the state root happens in the background, `state-push.sh` from the monitor pass and the CEO loop. There is no
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
before a long operation (ADR-0009). Exit 1 = refused, the reason is on stderr; fix it and run again. Exit 2 = the
report could not be written or committed (another session held the state lock too long, or git refused); run it
again, and note it in the progress file if it keeps failing. The Stop hook reports for you at the end.

Any **other state file** of your own, a research report, an ADR or memory proposal, a plan, goes in through
`state-commit.sh`: under the same state lock, and only the paths you name, so another session's uncommitted edit
never rides along. Paths are relative to the state clone; it does not push either.

```sh
sh "<plugin-root>/bin/state-commit.sh" -m "research: <id>" --state "$WORK_DIR/state" -- repos/<key>/research/<id>-<slug>.md
```

Exit 1 = refused (a path outside the state clone, a missing `-m`), exit 2 = not committed (the lock or git);
never `git commit`, `git pull` or `git push` in the state clone yourself.
