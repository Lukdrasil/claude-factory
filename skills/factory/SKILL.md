---
name: factory
description: The standalone factory on a developer machine: solve takes a task in words or by id and runs it end to end (triage, grill, plan-check, decompose, blocks in their own worktrees, block MRs merged, the task MR for the human); init, add-repo and doctor for setup; list for what exists; curate and consolidate for the proposal queues; approve and done for the human gates; herd runs the same flow with every step that writes as an interactive session in a herdr tab and this session as its monitor. Use when the user says factory, or solve, herd, approve, done, list, curate, consolidate, doctor, add-repo or init against it, or hands the factory a task.
---

# factory

Plugin root: `${CLAUDE_PLUGIN_ROOT}` (the base directory of this skill is `<plugin-root>/skills/factory`).

The standalone posture (ADR-0049): no dashboard, no Docker. The session runs where the user
starts it, and the factory root `WORK_DIR` (default `~/factory`) holds `state/` and the worktrees. The scripts
in `${CLAUDE_PLUGIN_ROOT}/bin/` do the writes; this skill runs them in the right order.

| subcommand | what it does | reference |
|---|---|---|
| `solve` | one task end to end in this session: `solve <the task in words> [--repo <key>]` creates it, `solve <T-id>` resumes it; triage, grill, plan-check, decompose, the blocks with their MRs merged into the work branch, the task MR the human merges | `references/solve.md`, quick lane `references/solve-quick.md` |
| `herd` | the same flow as `solve`, `herd <T-id>` or `herd <the task in words> [--repo <key>]`, with triage, grill, plan-check, decompose and every block as an interactive session in a herdr tab, dispatched by `${CLAUDE_PLUGIN_ROOT}/bin/session-monitor.sh`; this session is the monitor: it watches with `herd-watch.sh` and runs every gate | `references/herd.md`, `${CLAUDE_PLUGIN_ROOT}/skills/herdr/SKILL.md` |
| `init` | the factory root, `state/`, `WORK_DIR` in the settings, then add-repo and doctor for this clone | `references/init.md` |
| `add-repo` | registers a clone in `state/repos.yml` and seeds `repos/<key>/toolset.md`; with `--clone <url>` it clones the repository into the clones directory first | `references/add-repo.md` |
| `doctor` | a report over registration, toolset, the tools on PATH, the forge and `docs/architecture/`, with a fix per missing line | `references/doctor.md` |
| `list` | every task with its status, archetype, tier, repo and owner; `--repo` and `--status` narrow it | `references/list.md` |
| `curate` | the proposal queues one proposal at a time, applied through `curate-apply.sh`, every decision a commit | `references/curate.md` |
| `consolidate` | duplicates, contradictions and staleness in one or more memory scopes, as proposals | `references/consolidate.md` |
| `approve` | a task to `ready` through `${CLAUDE_PLUGIN_ROOT}/bin/task-approve.sh`, human confirmed | `references/approve.md` |
| `done` | a task and its blocks to `done` through `${CLAUDE_PLUGIN_ROOT}/bin/task-done.sh`, after the human validated the MR | `references/done.md` |

Read the reference for the subcommand the user asked for (`${CLAUDE_SKILL_DIR}/references/<subcommand>.md`)
and follow it. Without a subcommand: `init` when `WORK_DIR` is unset or has no `state/`; otherwise text that
names a task is `solve` with that text, and nothing at all is `doctor`.

## The one rule

Every write to the user's settings or to the state repo happens after the human confirmed the printed diff:
the script prints what it would change and stops (`factory-init.sh` and `factory-add-repo.sh` exit 3), you
show that output, ask through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ask.md`, and rerun with `--yes` on a yes.
A no ends the subcommand with the printed diff as the report and the user's files as they were. Tool installs
have the same shape: doctor prints the install command, you offer it one tool per question, and run the ones
the human said yes to.

The hooks enforce the rest. A refused command carries its own fix in the deny message.

Agents and references this skill spawns or writes follow
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-guidance.md` for the model they run under.
