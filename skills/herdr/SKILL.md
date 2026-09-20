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

`<plugin-root>/bin/session-monitor.sh` does this for you, and it is the path to take:

```sh
sh <plugin-root>/bin/session-monitor.sh --parent T-NNN   # the blocks of one wave
sh <plugin-root>/bin/session-monitor.sh                  # every ready, unowned task
```

It reads `spawn:` from `<state>/factory.yml`. On `herdr` it opens one tab per unit, in that unit's worktree,
starts `claude` there and sends the prompt. On `manual`, or on a machine with no herdr, it prints the same
`cd … && claude …` lines for the human to run. Either way it prints one `<id> <spawned|printed|skipped> <cwd>`
line per unit, so the main session learns what went out without reading any of the work.

`--max N` caps a batch, default 5. A unit with no worktree is skipped: run
`<plugin-root>/bin/worktree-add.sh <id>` and call the monitor again.

Three reasons to drive herdr yourself instead: a layout the user asked for, reading a spawned session's
output, or answering one that is blocked.

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
