---
name: factory
description: The standalone factory on a developer machine: init, add-repo and doctor for setup, list for what exists, curate and consolidate for the proposal queues, solve for one problem end to end, herd for the same flow driven from a monitor session, ceo for the session that runs the whole org from the state clone, lead for the session that runs one approved parent, onboard for the session that reports how ready an added repository is, approve and done for the human gates. Use when the user says factory, or ceo, lead, solve, herd, approve, done, list, curate, consolidate, doctor, add-repo, onboard or init against it.
---

# factory

Plugin root: `${CLAUDE_PLUGIN_ROOT}` (the base directory of this skill is `<plugin-root>/skills/factory`).

The standalone posture (ADR-0049): no dashboard, no Docker. The session runs where the user starts it, and
the factory root `WORK_DIR` (default `~/factory`) holds `state/` and the worktrees. The scripts in
`${CLAUDE_PLUGIN_ROOT}/bin/` do the writes; this skill runs them in the right order.

| subcommand | what it does | reference |
|---|---|---|
| `init` | the factory root, `state/`, `WORK_DIR` in the settings, then add-repo and doctor for this clone | `references/init.md` |
| `add-repo` | registers a clone in `state/repos.yml` and seeds `repos/<key>/toolset.md`; with `--clone <url>` it clones the repository into the clones directory first | `references/add-repo.md` |
| `onboard` | the onboarding session the CEO starts in a registered clone (`FACTORY_ROLE=onboard`): a report of how ready the repository is, in `repos/<key>/onboarding.md`, with the proposals the human turns into requests; it changes nothing | `references/onboard.md` |
| `doctor` | a report over registration, toolset, the tools on PATH and `docs/architecture/`, with a fix per missing line | `references/doctor.md` |
| `list` | every task with its status, archetype, tier, repo and owner; `--repo` and `--status` narrow it | `references/list.md` |
| `curate` | the proposal queues one proposal at a time, applied through `curate-apply.sh`, every decision a commit | `references/curate.md` |
| `consolidate` | duplicates, contradictions and staleness in one or more memory scopes, as proposals | `references/consolidate.md` |
| `solve` | one problem end to end: triage, grill, decompose, blocks in their own worktrees, the MR | `references/solve.md`, quick lane `references/solve-quick.md` |
| `herd` | one task the user named, end to end like `solve`, but every work step runs as an interactive session in a herdr tab and this session becomes its monitor: it dispatches, watches until `done` or `closed`, and gates | `references/herd.md` |
| `ceo` | the org: one herdr session in `$WORK_DIR/state`, started there with `claude '/claude-factory:factory ceo'`, that takes requests, routes them per repository under one request id, dispatches the chain as step sessions, asks the plan approval, starts a lead per approved parent from the queue, watches every herd and offers the memory passes | `references/ceo.md` |
| `lead` | one approved parent end to end in its worktree: `herd` for that parent with the block MRs merged by the lead and the task MR for the human; a session the CEO started as `lead_<unit>` (`FACTORY_ROLE=repo-lead`) reads this with its `herd` | `references/lead.md` |
| `monitor` | dispatch: `${CLAUDE_PLUGIN_ROOT}/bin/session-monitor.sh --task <T-NNN>` starts one named task, or the current wave of its blocks, as their own sessions and claims each one; with no argument it only lists the ready tasks to choose from, and `--all` (the batch a user has to ask for by name) also watches every open block MR for merges | `${CLAUDE_PLUGIN_ROOT}/skills/herdr/SKILL.md` |
| `approve` | a task to `ready` through `${CLAUDE_PLUGIN_ROOT}/bin/task-approve.sh`, human confirmed | `references/approve.md` |
| `done` | a task and its blocks to `done` through `${CLAUDE_PLUGIN_ROOT}/bin/task-done.sh`, after the human validated the MR | `references/done.md` |

Read the reference for the subcommand the user asked for (`${CLAUDE_SKILL_DIR}/references/<subcommand>.md`)
and follow it. Without a subcommand: `init` when `WORK_DIR` is unset or has no `state/`, otherwise `doctor`.

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
