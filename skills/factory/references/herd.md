# factory herd

`factory herd <T-NNN>`: the flow of `references/solve.md`, with the work done by interactive sessions in
herdr tabs instead of by subagents in your context. You are the monitor. You dispatch, you watch, you run
the gates, and you never write a line of the change yourself.

## You are the monitor

One herd is **one task and its subtasks**, the task the user named. If no task was named, list the ready ones
(`session-monitor.sh` with no argument) and ask which one (`_shared/ask.md`); never start a herd on a task
nobody chose, and never start a second one alongside it.

The moment `session-monitor.sh --task <T-NNN>` has printed its dispatch lines, arm the watcher through the
Monitor tool, before you read anything, answer anything or report anything:

```sh
sh <plugin-root>/bin/herd-watch.sh <T-NNN> --interval 60
```

Then say to the user that this session is the monitor of `<T-NNN>`. Going idle after a dispatch is the
failure of 2026-09-22: two coordinators sat still until the human asked whether anyone was watching. You
never wait to be asked - you wait on the watcher.

## What is different from solve

Same sixteen steps, same `<plugin-root>/bin/solve-next.sh <T-NNN>` driving them. What changes is who
executes: a work step goes out as its own session, and the session reports through the state repo, not to
you. A spawned session is not a subagent (`<plugin-root>/skills/herdr/SKILL.md`): nothing it claims comes
back in a return value, so every claim is one you rerun.

## Who owns which step

| step | owner | how |
|---|---|---|
| 3 triage | session | `session-monitor.sh --task <id> --step triage` |
| 4 grill | session | `--step grill`; the human answers the rounds in that tab |
| 5 architect plan-check | session | `--step plan-check` |
| 6 decompose | session | `--step decompose` |
| 8 cut check | monitor | `dag-check.sh`, the wave plan into the progress file |
| 9 approve and claim | monitor | the human gate is yours, never a session's |
| 10 session worktree | monitor | `worktree-add.sh` |
| 11 block work | sessions | `session-monitor.sh --task <id> --wave N`, one tab per block |
| 11 block gates | monitor | the red rerun, `block-verify.sh`, `block-merge.sh --verify`, `block-mr.sh` |
| 12, 12b acceptance, duplication | monitor | the parent's acceptance verbatim; `git diff origin/<base>...<branch> > <harness>/review.diff`, then `dup-check.sh <harness>/review.diff <worktree>`, never a task id |
| 13 review | monitor | `factory-reviewer` as a subagent, because its verdict belongs in your context |
| 14, 15, 16 MR, report, knowledge | monitor | as in solve |

The rule behind the split: anything that writes the change is a session, anything that judges it is yours.

## The loop

1. `sh <plugin-root>/bin/solve-next.sh <T-NNN>` for the step the state asks for.
2. A session step: `sh <plugin-root>/bin/session-monitor.sh --task <T-NNN> --step <name> --spawn herdr`,
   or for a wave of blocks `--wave N` with no `--step`. Each prints `<id> spawned <cwd>`. The tabs are
   created in your own herdr workspace (`$HERDR_WORKSPACE_ID`), so the group stays together. Every unit is
   claimed `in_progress` before its session starts, and the prompt opens with the reclaim command, so a
   worker's first heartbeat lands. The implement phase of a wave goes out through the same `--wave N` call
   once you armed `phase: implement` on its `tests_ready` blocks; a block whose session still runs is printed
   `skipped`.
3. Arm the watcher through the Monitor tool (step one of this file, and it stays armed for the whole herd):
   `sh <plugin-root>/bin/herd-watch.sh <T-NNN> --interval 60`. It prints one line per change:
   `<id> status <old> -> <new>`, `<id> phase <old> -> <new>`, `<id> agent <old> -> <new>` and
   `<id> mr <old> -> <new>`. A quiet pass prints nothing. The agent values are herdr's own (working, idle,
   blocked, done, unknown), plus `closed` for a tab the scripts closed and `gone` for a session no longer live.
4. On any line, rerun `solve-next.sh` and do what it prints. A monitor step you do yourself; a session step
   you dispatch and go back to 3.
5. `<id> agent <state> -> blocked` means that session is at an approval or question dialog. Read it with
   `herdr agent read <id-lowercased> --source recent-unwrapped --lines 120`, ask the human with
   an ask (`_shared/ask.md`), and answer with `herdr agent prompt <id-lowercased> "<the answer>"`. Never
   answer for the human. With `ui: docker` the monitor relays nothing: it tells the human which worker is at a
   dialog and its pane id, the wave panel of the task's drawer shows the same, and the human answers in that
   pane. No AskUserQuestion and no `herdr agent prompt` from the monitor. A worker's own asks reach the page
   and the relay types their answers into the worker's pane.
6. `<id> agent <state> -> gone` with the status unchanged is a session that died without reporting. Rerun
   `solve-next.sh` and dispatch it again; two deaths in a row is `_shared/blocked-question.md`.
   `<id> agent <state> -> closed` is no dead session: the scripts closed a tab whose work was over.
7. The scripts close the tabs, you report them. `herd-watch.sh` closes the recorded tab of every unit at
   `done` or `closed`, and the step tabs once the parent is; `session-monitor.sh` closes a unit's own tab and
   the step tabs of its parent before it starts that unit again. A tab that is focused, is your own, or holds
   an agent at work stays open. Never close a tab by hand. After each wave, post one line per active task,
   `<id> <status> <next step>`, so the human never has to ask.

## `review` is not the end

A herd ends at `done` or `closed`, and at nothing else. On 2026-09-22 the monitors that ran stopped when the
blocks reached `review` and missed both the merges and a `need_rebase` on !412.

After the last unit reaches `review`, keep the same loop running. `herd-watch.sh` runs
`mr-watch.sh <T-NNN> --once` on every pass and turns its state file into the `mr` lines, so you see the
forge without reading an MR:

| line | what it is | what you do |
|---|---|---|
| `<id> mr <any> -> merged` | the MR is in | mr-watch has retargeted the stack and set the block `done`; rerun `solve-next.sh` |
| `<id> mr <any> -> ci-failed` | the pipeline is red | dispatch the fix as a session, never fix it here |
| `<id> mr <any> -> changes-requested` | a reviewer wants work | `mr-watch.sh <T-NNN> --comments <block-id>`, then dispatch |
| `<id> mr <any> -> approved` | it waits on a human merge | say so, and keep watching |

An MR that sits at `open` after the pipeline went green is the `need_rebase` case: look with
`glab mr view <url>` or `gh pr view <url>`, and dispatch the rebase to the block's own session. Only when the
parent reads `done` or `closed` do you disarm the watcher and report to the user.

## Evidence stays yours

A session that self-reports `tests_ready` or `review` has written its own `## Evidence`. That is a claim.
Rerun the proving command yourself before you advance the flow, exactly as `references/solve.md` says: the
red tests at the commit the handoff names, `block-verify.sh` before the block MR, the parent's
`## Acceptance` verbatim before step 13.

## Without herdr

`session-monitor.sh` prints the `cd ... && claude ...` line per unit instead of opening a tab, and says why on
stderr: no `herdr` on PATH, or `HERDR_ENV` unset because this session is not in a herdr pane. The flow is
unchanged - the human starts the sessions by hand, and `herd-watch.sh` still reports their state changes
from the state repo, with every agent reading `gone`.
