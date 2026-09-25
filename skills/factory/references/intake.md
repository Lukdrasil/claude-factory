# factory intake

`factory intake <R-id> <P> [<base>]`: the intake session of one request, which the CEO dispatches instead of routing it
itself (`session-monitor.sh --step intake`, `references/ceo.md`). It runs in the state clone as
`FACTORY_ROLE=intake`, unit `intake-<R-id>`. The CEO opened the map `requests/<R-id>/` with the request as its
destination and stopped there. You route the request to its repositories and write one parent per repository.
You dispatch nothing: the CEO starts the chain once you report. Every question to the human goes through
`_shared/ask.md` with flow `intake` and task `none`.

## Steps

1. **Read the request**: the destination of `requests/<R-id>/map.md`. `<P>` is its priority, `P0` to `P3`.
   Completion: the request is one line you can restate.
2. **Route** by `repos.yml` and each repo's `toolset.md`, memory and, when it exists, the `## Summary` of
   `repos/<key>/onboarding.md`: every repository the request needs. Ask the human only when two repositories fit
   equally. A request no registered repository fits is one notice ask that names why, then step 4 with
   `stopped`. Completion: the repositories, each with one sentence on why.
3. **Write the parents**, one per repository: the draft from `sh <plugin-root>/bin/task-template.sh task` with
   `request: <R-id>`, `priority: <P>`, `base_branch: <base>` when the prompt names one, and, when the request orders the repositories, `depends_on:` on the parent
   that goes first; then `sh <plugin-root>/bin/task-new.sh --repo <key> --file <draft> --state <state>`, once
   per repository. Completion: every `task-new.sh` printed its id.
4. **Report** to the CEO: `herdr agent prompt ceo "intake <R-id> done <T-id> [<T-id>...]"`, or
   `herdr agent prompt ceo "intake <R-id> stopped <reason>"`. A refusal means the CEO sits at a dialog: send it
   again, up to 3 times, 10 seconds apart, then go on. The CEO checks the parents in the state before it acts.
5. **Close your own tab**: `herdr tab close "$HERDR_TAB_ID"`. This ends the session.
