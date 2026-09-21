# factory herd

`factory herd <T-NNN>`: the flow of `references/solve.md`, with the work done by interactive sessions in
herdr tabs instead of by subagents in your context. You are the monitor. You dispatch, you watch, you run
the gates, and you never write a line of the change yourself.

## What is different from solve

Same sixteen steps, same `<plugin-root>/bin/solve-next.sh <T-NNN>` driving them. What changes is who
executes: a work step goes out as its own session, and the session reports through the state repo, not to
you. A spawned session is not a subagent (`<plugin-root>/skills/herdr/SKILL.md`): nothing it claims comes
back in a return value, so every claim is one you rerun.

## Who owns which step

| step | owner | how |
|---|---|---|
| 3 triage | session | `session-monitor.sh --parent <id> --step triage` |
| 4 grill | session | `--step grill`; the human answers the rounds in that tab |
| 5 architect plan-check | session | `--step plan-check` |
| 6 decompose | session | `--step decompose` |
| 8 cut check | monitor | `dag-check.sh`, the wave plan into the progress file |
| 9 approve and claim | monitor | the human gate is yours, never a session's |
| 10 session worktree | monitor | `worktree-add.sh` |
| 11 block work | sessions | `session-monitor.sh --parent <id> --wave N`, one tab per block |
| 11 block gates | monitor | the red rerun, `block-verify.sh`, `block-merge.sh --verify`, `block-mr.sh` |
| 12, 12b acceptance, duplication | monitor | the parent's acceptance verbatim, `dup-check.sh` |
| 13 review | monitor | `factory-reviewer` as a subagent, because its verdict belongs in your context |
| 14, 15, 16 MR, report, knowledge | monitor | as in solve |

The rule behind the split: anything that writes the change is a session, anything that judges it is yours.

## The loop

1. `sh <plugin-root>/bin/solve-next.sh <T-NNN>` for the step the state asks for.
2. A session step: `sh <plugin-root>/bin/session-monitor.sh --parent <T-NNN> --step <name> --spawn herdr`,
   or for a wave of blocks `--wave N` with no `--step`. Each prints `<id> spawned <cwd>`. The tabs are
   created in your own herdr workspace (`$HERDR_WORKSPACE_ID`), so the group stays together.
3. Arm the watcher through the Monitor tool:
   `sh <plugin-root>/bin/herd-watch.sh <T-NNN> --interval 60`. It prints one line per change:
   `<id> status <old> -> <new>`, `<id> phase <old> -> <new>`, `<id> agent <old> -> <new>`. A quiet pass
   prints nothing.
4. On any line, rerun `solve-next.sh` and do what it prints. A monitor step you do yourself; a session step
   you dispatch and go back to 3.
5. `<id> agent <state> -> blocked` means that session is at an approval or question dialog. Read it with
   `herdr agent read <id-lowercased> --source recent-unwrapped --lines 120`, ask the human with
   AskUserQuestion, and answer with `herdr agent prompt <id-lowercased> "<the answer>"`. Never answer for
   the human.
6. `<id> agent <state> -> gone` with the status unchanged is a session that died without reporting. Rerun
   `solve-next.sh` and dispatch it again; two deaths in a row is `_shared/blocked-question.md`.

## Evidence stays yours

A session that self-reports `tests_ready` or `review` has written its own `## Evidence`. That is a claim.
Rerun the proving command yourself before you advance the flow, exactly as `references/solve.md` says: the
red tests at the commit the handoff names, `block-verify.sh` before the block MR, the parent's
`## Acceptance` verbatim before step 13.

## Without herdr

`session-monitor.sh` prints the `cd … && claude …` line per unit instead of opening a tab, and says why on
stderr: no `herdr` on PATH, or `HERDR_ENV` unset because this session is not in a herdr pane. The flow is
unchanged - the human starts the sessions by hand, and `herd-watch.sh` still reports their state changes
from the state repo, with every agent reading `gone`.
