---
name: herdr
description: Start factory tasks as real interactive Claude sessions in herdr tabs, and inspect or control the panes, tabs and agents of a herdr session. Use when the user mentions herdr, when factory.yml says `spawn: herdr`, or when a task should run as its own session instead of a subagent. Requires HERDR_ENV=1.
---

# herdr

Herdr is a terminal multiplexer for coding agents. A pane can hold an agent it recognises, and the `herdr`
CLI drives panes, tabs and those agents.

Check first, and stop if it fails:

```sh
test "${HERDR_ENV:-}" = 1
```

Outside a herdr pane there is nothing to control. Say so and use the manual path below.

## The CLI

The installed binary is the authority, and it ships its own reference:

```sh
herdr --skill
```

Read that before any command this file does not already give you. Do not run bare `herdr`: it launches the
TUI.

## Starting factory tasks

One task per start, and the user names it. On 2026-09-22 a bare `session-monitor.sh` listed eight ready tasks
across five repos and would have spawned foreign work; a start is a dialog now, not a batch.

1. The ready, unowned tasks:

```sh
sh <plugin-root>/bin/session-monitor.sh                # lists them: <id> <repo> <status> <archetype> <goal>
sh <plugin-root>/bin/factory-list.sh --root <work-dir> --status ready
```

2. Ask **which one** through `<plugin-root>/skills/_shared/ask.md`, one option per ready task with its goal
   line, nothing pre-selected. Ask even when only one task is ready. Never spawn before the answer. Skip the
   question only when the user's own message already named exactly one task id.

3. Start it, and only it:

```sh
sh <plugin-root>/bin/session-monitor.sh --task T-NNN --spawn herdr
```

   It dispatches the current wave of that task's ready blocks, or the task alone when it is a ready leaf, and
   claims each unit `in_progress` under `factory@<host>:pending-<id>` before the session starts. The prompt it
   sends opens with the reclaim command, so the spawned session's first heartbeat is not a refused guess.

4. Arm the watcher through the Monitor tool, before anything else:

```sh
sh <plugin-root>/bin/herd-watch.sh T-NNN --interval 60
```

   Then say it: this session is now the monitor of T-NNN. It runs the loop of
   `<plugin-root>/skills/factory/references/herd.md` until the task is `done` or `closed`, and it never writes
   the change itself.

`--all` dispatches every ready, unowned task across the state repo. It is for a user who asked for every ready
task in those words, and for nobody else.

```sh
sh <plugin-root>/bin/session-monitor.sh --task T-NNN --step grill   # one parent-level step of factory herd
```

It reads `spawn:` from `<state>/factory.yml`. On `herdr` it opens one tab per unit, in that unit's worktree,
starts `claude` there and sends the prompt. On `manual`, or on a machine with no herdr, it prints the same
`cd ... && claude ...` lines for the human to run. Either way it prints one `<id> <spawned|printed|skipped>
<cwd>` line per unit, so the main session learns what went out without reading any of the work.

`--max N` caps a batch, default 5. A unit with no worktree is skipped: run
`<plugin-root>/bin/worktree-add.sh <id>` and call the monitor again. `--spawn herdr` overrides `spawn:` for
one call, and the tabs are created in `$HERDR_WORKSPACE_ID` unless `--workspace` names another, so a
dispatched session lands in the caller's own group.

## Driving herdr by hand

Three reasons, and no others: a layout the user asked for, reading a spawned session's output, or answering
one that is blocked. Starting a task by hand with `herdr tab create` and `herdr agent start` is none of them,
it walks around the claim and the prompt contract above.

```sh
herdr agent list                       # what is live, and its state
herdr agent read <name>                # its terminal output
herdr agent prompt <name> "<text>"     # send it work
```

`blocked` means the session is at an approval or question dialog. Read it, ask the user, then answer.

## Spawned sessions are not subagents

A spawned session has its own context, its own hooks and its own state reports. It is not a subagent, so its
report does not come back to the caller: it lands in the state repo, and
`<plugin-root>/bin/factory-list.sh` and `state-report.sh` are how the main session reads it. The rules in
`<plugin-root>/skills/_shared/delegation.md` about verifying a claim still hold, more so, since nothing is
returned to you directly.
