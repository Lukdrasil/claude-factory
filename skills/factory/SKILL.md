---
name: factory
description: The standalone factory on a developer machine: init, add-repo and doctor for setup, list for what exists, curate and consolidate for the proposal queues, solve for one problem end to end, approve and done for the human gates. Use when the user says factory, or solve, approve, done, list, curate, consolidate, doctor, add-repo or init against it.
---

# factory

Plugin root: `${CLAUDE_PLUGIN_ROOT}` (the base directory of this skill is `<plugin-root>/skills/factory`).

The standalone posture (ADR-0049): no dashboard, no Docker. The session runs where the user starts it, and
the factory root `WORK_DIR` (default `~/factory`) holds `state/` and the worktrees. The scripts in
`${CLAUDE_PLUGIN_ROOT}/bin/` do the writes; this skill runs them in the right order.

| subcommand | what it does | reference |
|---|---|---|
| `init` | the factory root, `state/`, `WORK_DIR` in the settings, then add-repo and doctor for this clone | `references/init.md` |
| `add-repo` | registers a clone in `state/repos.yml` and seeds `repos/<key>/toolset.md` | `references/add-repo.md` |
| `doctor` | a report over registration, toolset, the tools on PATH and `docs/architecture/`, with a fix per missing line | `references/doctor.md` |
| `list` | every task with its status, archetype, tier, repo and owner; `--repo` and `--status` narrow it | `references/list.md` |
| `curate` | the proposal queues one proposal at a time, applied through `curate-apply.sh`, every decision a commit | `references/curate.md` |
| `consolidate` | duplicates, contradictions and staleness in one or more memory scopes, as proposals | `references/consolidate.md` |
| `solve` | one problem end to end: triage, grill, decompose, blocks in their own worktrees, the MR | `references/solve.md`, quick lane `references/solve-quick.md` |
| `monitor` | dispatch: `${CLAUDE_PLUGIN_ROOT}/bin/session-monitor.sh` starts ready tasks, or a wave of blocks, as their own sessions, and without a parent also watches every open block MR for merges | `${CLAUDE_PLUGIN_ROOT}/skills/herdr/SKILL.md` |
| `approve` | a task to `ready` through `${CLAUDE_PLUGIN_ROOT}/bin/task-approve.sh`, human confirmed | `references/approve.md` |
| `done` | a task and its blocks to `done` through `${CLAUDE_PLUGIN_ROOT}/bin/task-done.sh`, after the human validated the MR | `references/done.md` |

Read the reference for the subcommand the user asked for (`${CLAUDE_SKILL_DIR}/references/<subcommand>.md`)
and follow it. Without a subcommand: `init` when `WORK_DIR` is unset or has no `state/`, otherwise `doctor`.

## The one rule

Every write to the user's settings or to the state repo happens after the human confirmed the printed diff:
the script prints what it would change and stops (`factory-init.sh` and `factory-add-repo.sh` exit 3), you
show that output, ask with AskUserQuestion, and rerun with `--yes` on a yes. A no ends the subcommand with
the printed diff as the report and the user's files as they were. Tool installs have the same shape: doctor
prints the install command, you offer it one tool per question, and run the ones the human said yes to.

The hooks enforce the rest. A refused command carries its own fix in the deny message.

Agents and references this skill spawns or writes follow
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-guidance.md` for the model they run under.
