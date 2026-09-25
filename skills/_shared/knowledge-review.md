# Knowledge review

Before you finish, decide what the system keeps from this session (ADR-0015). A task that produced no
insight should not invent one.

Write straight into `proposals/`, never into `memory/`, `drafts/`, `playbook.md`, `adr/` or `architecture/`, and
never into a subdirectory of `proposals/`: the passes and the curation gate do not see them.

- **Lesson** to `$WORK_DIR/state/repos/<key>/agents/<agent>/memory/proposals/<id>-<slug>.md`, `<key>` the repo
  of the task and `<agent>` the agent you run as without `claude-factory:` (`researcher-s0`..`s3` write under
  `researcher`), or your role when you run as none (`$FACTORY_ROLE`, e.g. `repo-lead`; `factory` without one).
  With no repo key at all, `$WORK_DIR/state/agents/<agent>/memory/proposals/`. The daily pass
  (`claude-factory:memory-daily`) judges it and turns a verified lesson into a draft of that agent's playbook
  for the repo; a lesson that holds for the role in every repo reaches the plugin as a K1 draft, never by
  your own edit. **At most two lessons per task**; with more candidates, keep the two that would save the most
  next time. A lesson is a sentence you needed at the start of this session and that was not in its
  SessionStart context, your brief or your playbook. It is kept only when it applies beyond this one task, its
  evidence reproduces, and no live skill or playbook already says it.
- **ADR proposal** to `$WORK_DIR/state/repos/<key>/adr/proposals/<slug>.md` when this session decided something that
  shapes the architecture: a pattern chosen, a dependency direction set, an alternative rejected. Write it
  **without a number**; the gate numbers it on acceptance.
- **Architecture proposal** to `$WORK_DIR/state/repos/<key>/architecture/proposals/<slug>.md` when the result made
  something in the product repo's `docs/architecture/` stale and your branch did not fix it. Name the
  document and section, what the merged result does, and the edit to paste.

A reader decides yes or no from the proposal alone, so the decision is the title line and the rest is what
backs it. **Under 80 words per proposal**, ADR `## Context`/`## Decision`/`## Consequences` under 40 each,
and no account of how you arrived at it. The daily pass decides on a lesson, a human or the `memory-curator`
agent under ADR-0052 on an ADR or architecture proposal.

```markdown
# <the lesson in one sentence>

Why: why it holds and what happens when it is forgotten.
Evidence: <id>, `path/file.ext:line`, a commit SHA or command output.
```

An ADR proposal is Nygard: `Status: Proposed`, then `## Context` (what forced a choice),
`## Decision` (what was chosen, active voice) and `## Consequences` (what follows, the price as well as the
win). An architecture proposal is a diff against the docs: `Document:`, `Now:`, `Actually:` with a
`path/file.ext:line` or SHA, and `Edit:`.

Commit proposals the way `<plugin-root>/skills/_shared/progress-and-push.md` commits a new file of your own.
