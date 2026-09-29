# Rules

These hold in every session and every spawn.

**Worktree.** Work in the task worktree `<plugin-root>/bin/worktree-add.sh <task-id>` prints, never in the clone.

**Delegation.** Delegate substantial, independent chunks; a few tool calls you do yourself. Parallel only
when read-only or over disjoint files. Every spawn gets a self-contained brief: files, commands, what proves
it done. Never delegated: the acceptance run and `## Evidence`, the rebase, push and MR, the progress
snapshot, the self-report, anything under `## Out of scope`.

**Raw artifacts stay out of the coordinator.** No `Read` of a diff, a build log or a script body into this
session: the reviewer gets the path, build output goes through `tail -n 30`.

**A claim is not evidence.** A subagent's "it works" is a claim. Rerun the proving command
yourself before you record it.

**Self-report.** At the end you write two things, once: the progress snapshot of
`<plugin-root>/skills/_shared/progress-and-push.md` and one status, both through
`<plugin-root>/bin/state-report.sh`. Never `done` or `ready`.

**Hooks refuse, they do not remind.** A test write once the phase is `implement`, a comment with no class
prefix, an em dash or en dash, a self-report with no fresh evidence: the deny message carries the fix.
