# Self-report

The state repo is the only signalling channel. The state clone is `$WORK_DIR/state`, paths below are relative
to it, and it is read-only towards the state repo: the status and the progress snapshot go the same way as
everywhere else.

```sh
sh <plugin-root>/bin/state-report.sh
```

**Progress snapshot**: `repos/<key>/progress/<id>.md`, the template in
`<plugin-root>/skills/_shared/progress-and-push.md`, with two deltas. The title is
`# <id> - triage <repo>#<number>`, and `## Evidence` holds the draft task path and the validator run that
passed.

**Status**: `status:` in the **triage task's** frontmatter, and nothing else in that frontmatter. `owner` is
set by your claim, `attempt` and `plan_hash` by `task-approve.sh`, `ready` and `closed` by the human.

| status | when |
|---|---|
| `review` | the draft exists in the state repo and passed the validator, or already existed, both recorded under `## Evidence` |
| `blocked` | the issue cannot be read, or the archetype cannot be decided from it: the question goes into the progress file as `## Question`, shaped per `<plugin-root>/skills/_shared/blocked-question.md` |
| `failed` | the draft could not be written; `state-report.sh --task <id> --attempts "attempt <N> - <model>, <what failed>"` |

Never write `done` or `ready`.

**Report** per `## Report` in `<plugin-root>/skills/_shared/progress-and-push.md`.
