---
name: herdr
description: Start factory tasks as real interactive Claude sessions in herdr tabs, and inspect or control the panes, tabs and agents of a herdr session. Use when the user mentions herdr, runs factory herd, or wants a task to run as its own session instead of a subagent. Requires HERDR_ENV=1.
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
sh <plugin-root>/bin/session-monitor.sh --task T-NNN
```

   It dispatches the current wave of that task's ready blocks, or the task alone when it is a ready leaf, and
   claims each unit `in_progress` under `factory@<host>:pending-<id>` before the session starts. The prompt it
   sends opens with the reclaim command, so the spawned session's first heartbeat is not a refused guess. A
   block runs `block-tests` or its archetype skill as a session, under `skills/_shared/block-session.md`: it
   reports `tests_ready` or `review` and leaves its MR to the monitor. A block in progress that no live session
   carries, one that died or whose spawn failed, goes out again on the next call.
   The implement phase of a wave goes out through the same `--task T-NNN --wave N` call once the monitor armed
   `phase: implement` on its `tests_ready` blocks; a block whose session still runs is printed `skipped`.

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

With herdr on PATH and this session in a herdr pane it opens one tab per unit, in that unit's worktree, starts
`claude` there and sends the prompt; `--spawn manual`, or a machine with no herdr, prints the same
`cd ... && claude ...` lines for the human to run. Either way it prints one `<id> <spawned|printed|skipped>
<cwd>` line per unit, so the main session learns what went out without reading any of the work.

Every session is named `<role emoji> <emoji> <repo> <id>`, for example `🔨 🦊 arthurcore T-251-01`: the tab label
and the `claude --name`, and the `--name` of a printed line too. The role emoji marks the phase: 🔎 triage,
🎤 grill, 📐 plan-check, 🧩 decompose, 🧪 test-designer, 🔨 implementer, 🧠 implementer-senior. The monitor's own
tab is renamed `📡 <emoji> <repo> <T-id>` on its first `--task` pass. The emoji after it is the repo's `emoji:` in
`repos.yml`, else a fixed pick by the repo key. The herdr agent name is `<role>_<unit>`, the unit lowercased without its leading
`t-` for an alias id (`implementer_ecs-142-03`, `grill_cf-3`) and with it for a legacy id (`grill_t-264`).
`herdr agent read <name>` takes that name. Every spawn passes `--env FACTORY_ROLE=<role> --env
FACTORY_UNIT=<unit> --env CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`; the guard keeps every human gate from a session
with a `FACTORY_ROLE`. Each tab it opens is recorded as `<unit> <tab_id> <pane_id> [<session_id>]` in
`<work-dir>/<repo>/.harness/<T-NNN>/herdr-tabs`, and its name in `herdr-names` beside it, written only through
`bin/herdr-tabs.sh`; after a herdr restart `herdr-tabs.sh reattach <T-NNN>` finds each recorded pane and session
again and renames it back.

Closing is scripted, never done by hand. Before a unit starts again, `session-monitor.sh` closes its recorded
tab and the step tabs of its parent, and prints the unit `skipped` when its own tab is still at work. Every
`herd-watch.sh` pass, and every `--all` run, closes the recorded tabs of units at `done` or `closed`. A
focused tab, the caller's own `$HERDR_TAB_ID`, an agent that is `working` or `blocked` and a tab `herdr tab
get` cannot read are kept, and a tab not in the record is never touched.

`--max N` caps a batch, default 5. A block or leaf with no worktree is skipped: run
`<plugin-root>/bin/worktree-add.sh <id>` and call the monitor again. A triage or grill step with none gets the
task worktree detached at the base (`worktree-add.sh <T-id> --detach`), read-only until the approval. The tabs are created in
`$HERDR_WORKSPACE_ID` unless `--workspace` names another, so a dispatched session lands in the caller's own group.

## Driving herdr by hand

Three reasons, and no others: a layout the user asked for, reading a spawned session's output, or answering
one that is blocked. Starting a task by hand with `herdr tab create` and `herdr agent start` is none of them,
it walks around the claim and the prompt contract above.

```sh
herdr agent list                       # what is live, and its state
herdr agent read <name>                # its terminal output
herdr agent send-keys <name> <key>...  # answer a dialog: a digit, up, down, enter, esc
herdr agent prompt <name> "<text>"     # a line to an idle or working session
```

`blocked` means the session is at an approval or question dialog. Read it (`herdr agent read <name> --source
recent-unwrapped --lines 120`), ask the user, then answer with `herdr agent send-keys`: a blocked agent refuses
`herdr agent prompt`.

## Spawned sessions are not subagents

A spawned session has its own context, its own hooks and its own state reports. It is not a subagent, so its
report does not come back to the caller: it lands in the state repo, and
`<plugin-root>/bin/factory-list.sh` and `herd-watch.sh` are how the main session reads it, and the session
itself writes it through `state-report.sh`. The rules in
`<plugin-root>/skills/_shared/delegation.md` about verifying a claim still hold, more so, since nothing is
returned to you directly.

SendMessage reaches only the calling session's own subagents and teammates, never a spawned session. The
monitor talks to a spawned session through `herdr agent prompt <name> "<line>"`. An idle
session takes the line as its next prompt, a `working` one queues it and reads it when its turn ends, and a
`blocked` one refuses it (`agent_blocked`), so the sender sends it again once the dialog is answered. The line
arrives like a typed prompt: the receiver checks it against the state repo, and it never carries an
approval.
