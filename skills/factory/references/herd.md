# factory herd

`factory herd <T-id>`: the flow of `references/solve.md`, with the work done by interactive sessions in herdr
tabs instead of by subagents in your context. You are the monitor. You dispatch, you watch, you run the gates,
and you never write a line of the change yourself. It needs herdr on PATH and this session in a herdr pane
(`HERDR_ENV=1`); without it the same flow runs with the sessions started by hand (Without herdr, below).

`factory herd <the task in words> [--repo <key>]` starts a new task first: the Start of `references/solve.md`,
intake and create, then this file.

## You are the monitor

One herd is **one task and its subtasks**, the task the user named. If no task was named, list the ready ones
(`session-monitor.sh` with no argument) and ask which one (`_shared/ask.md`); never start a herd on a task nobody
chose, and never start a second one alongside it.

The moment the first `session-monitor.sh --task <T-id>` has printed its dispatch lines, arm the watcher through
the Monitor tool, before you read anything, answer anything or report anything:

```sh
sh <plugin-root>/bin/herd-watch.sh <T-id> --interval 60
```

Give it the description `herd-watch.sh <T-id>` and `timeout_ms` at its maximum. A Monitor expires: arm it again
on every expiry notice. The Stop hook `rearm-check.sh` names a herd of this session that has no such monitor, at
most twice per session. Then say to the user that this session is the monitor of `<T-id>`. Going idle after a
dispatch is the failure of 2026-09-22: two coordinators sat still until the human asked whether anyone was
watching. You never wait to be asked: you wait on the watcher.

## The loop

`sh <plugin-root>/bin/solve-next.sh <T-id> --herd` for the step the state asks for, do what it prints, verify its
`Completion:` line yourself, and run it again, as in `references/solve.md`, whose human gates, owner string and
task MR ending hold here unchanged. What `--herd` changes is who executes:

| step | owner | how `--herd` prints it |
|---|---|---|
| 3 triage, 4 grill, 5 plan-check, 6 decompose | a session | `session-monitor.sh --task <id> --step <step>`; the human answers the grill rounds in that tab |
| 8 cut check, 9 approve and claim, 10 worktree | you | as in solve |
| 11 block work | sessions | `session-monitor.sh --task <id> --wave N`: one tab per block, each cut from the work branch and claimed for its session |
| 11 block gates | you | the red rerun at `tests_ready`, `block-verify.sh`, the `code-reviewer` and the `architecture-auditor` on the block diff as your subagents, `block-mr.sh`, then `block-mr-merge.sh` |
| 12 to 16 | you | as in solve |

The rule behind the split: anything that writes the change is a session, anything that judges it is yours.
A dispatched session runs with `FACTORY_ROLE`, and the guard keeps every human gate from it.

## Reading the watcher

`herd-watch.sh` prints one line per change: `<id> status <old> -> <new>`, `<id> phase <old> -> <new>`,
`<id> agent <old> -> <new>` and `<id> mr <old> -> <new>`. A quiet pass prints nothing. The agent values are
`working`, `blocked`, `ready` (herdr's idle or done), `unknown`, `closed` for a tab the scripts closed and `gone`
for a session no longer live.

1. On any line, rerun `solve-next.sh <T-id> --herd` and do what it prints.
2. `<id> agent <state> -> blocked` is a session at an approval or question dialog. Read it with
   `herdr agent read <name> --source recent-unwrapped --lines 120`, ask the human (`_shared/ask.md`), and answer
   with `herdr agent send-keys <name> <keys>` (a digit, arrows, `enter`, `esc`): a blocked agent refuses
   `herdr agent prompt`. The name is `<role>_<unit>` (`skills/herdr/SKILL.md`). Never answer for the human.
3. `<id> agent <state> -> gone` with the status unchanged is a session that died without reporting. Rerun
   `solve-next.sh --herd` and dispatch it again; two deaths in a row is `_shared/blocked-question.md`.
   `<id> agent <state> -> closed` is no dead session: the scripts closed a tab whose work was over.
4. `<block> status -> tests_ready` or `-> review`: its session ended and the Stop hook had it report, with its own
   `## Evidence`, a claim. `solve-next.sh --herd` gives you the gate that reruns it: at `tests_ready` its red
   tests at the commit its `## Handoff` names, then `phase: implement` and the implement session; at `review`
   `block-verify.sh` (and a single-phase block's red proof), the reviewer, the auditor, the block MR and its merge.
5. The scripts close the tabs, you report them. `herd-watch.sh` closes the recorded tab of every unit at
   `done` or `closed`, and the step tabs once the parent is; `session-monitor.sh` closes a unit's own tab and
   the step tabs of its parent before it starts that unit again. A tab that is focused, is your own, or holds an
   agent at work stays open. Never close a tab by hand. After each wave, post one line per active task,
   `<id> <status> <next step>`, so the human never has to ask.

After a herdr restart, `herdr-tabs.sh reattach <T-id>` finds each recorded session again by its session id or
pane and gives it back its name.

## `review` is not the end

A herd ends at `done` or `closed`, and at nothing else. On 2026-09-22 the monitors that ran stopped when the
blocks reached `review` and missed both the merges and a `need_rebase` on !412.

`herd-watch.sh` runs `mr-watch.sh <T-id> --once` on every pass, the task MR included, and turns its state file
into the `mr` lines, so you see the forge without reading an MR:

| line | what it is | what you do |
|---|---|---|
| `<block> mr <any> -> merged` | the block MR is in | mr-watch has set the block `done`; rerun `solve-next.sh --herd` |
| `<T-id> mr <any> -> merged` | the human merged the task MR | `references/done.md`, without an ask |
| `<id> mr <any> -> ci-failed` | the pipeline is red | a fix round as in `references/solve.md` |
| `<id> mr <any> -> changes-requested` | a reviewer wants work | `mr-watch.sh <T-id> --comments <id>`, then the fix round |
| `<id> mr <any> -> approved` | it waits on a human merge | say so, and keep watching |

An MR that sits at `open` after the pipeline went green is the `need_rebase` case: look with
`glab mr view <url>` or `gh pr view <url>`, and rebase it on its branch. Only when the parent reads `done` or
`closed` do you disarm the watcher and report to the user.

## Evidence stays yours

A session that self-reports `tests_ready` or `review` has written its own `## Evidence`. That is a claim. Rerun
the proving command yourself before you advance the flow, exactly as `references/solve.md` says: the red tests
at the commit the handoff names, `block-verify.sh` before the block MR, the parent's `## Acceptance` verbatim
before step 13.

## Without herdr

`session-monitor.sh` prints the `cd ... && claude ...` line per unit instead of opening a tab, and says why on
stderr when `--spawn herdr` asked for herdr: no `herdr` on PATH, or `HERDR_ENV` unset because this session is not
in a herdr pane. The flow is unchanged: the human starts the sessions by hand, and `herd-watch.sh` still reports
their state changes from the state repo, with every agent reading `gone`.
