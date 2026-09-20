# Progress and push

## Progress snapshot

`../state/repos/<key>/progress/<id>.md`, a rewritten file.
Read mid-flight: **under 200 words**, one line per bullet, the state in the first line. Cite
`path/file.ext:line` or a SHA instead of retelling; what you considered and declined stays out.

```markdown
# <id> — <task title>
**<on track|blocked|acceptance green>** — the one thing a reader needs now.

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

Before self-reporting `review` or `tests_ready`, run the proving command **fresh in this session** — for
`review` the acceptance command (after the rebase, where the archetype has one), for `tests_ready` the red
tests failing for the right reason — and
record the command, its exit code and the key output line. The Stop hook bounces a `review`/`tests_ready` without it.

## Report

The task's `status:` and the progress file are written only through `state-report.sh`, which in the
standalone posture of this plugin (ADR-0050, `DASHBOARD_URL` unset) validates the transition, commits in the
state clone and pushes. Rewrite the progress file, then:

```sh
sh "<plugin-root>/bin/state-report.sh" --task <id> [--set-status <status>]
```

`<plugin-root>` is the plugin root the skill that sent you here names. Run it at every milestone: that
report is the liveness signal (ADR-0009), so a long operation goes after one. Exit 1 = refused, the reason
is on stderr; fix it and run again. Exit 2 = the push did not land; the local commit stays, note it and carry
on. The Stop hook reports for you at the end.

A **new file** of your own — a research report, an ADR or memory proposal, a plan — still goes through git:

```sh
git -C ../state add repos/<key>/research/<id>-<slug>.md
git -C ../state commit -m "research: <id>"
git -C ../state pull --rebase --autostash -X theirs && git -C ../state push
```
