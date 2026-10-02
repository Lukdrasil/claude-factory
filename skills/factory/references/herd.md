# factory herd

`factory herd <T-id>`: the flow of `references/solve.md`, with the work done by interactive sessions in herdr
tabs instead of by subagents in your context. You are the monitor. You dispatch, you watch, you run the gates,
and you never write a line of the change yourself. It needs herdr on PATH and this session in a herdr pane
(`HERDR_ENV=1`); without it the same flow runs with the sessions started by hand (Without herdr, below).

`factory herd <the task in words> [--repo <key>]` starts a new task first: the Start of `references/solve.md`,
intake and create, then this file. `factory herd <T-id>` on a herd already running takes the parent back with
`state-report.sh --task <T-id> --owner <owner> --no-status` and nothing else: its blocks belong to their sessions,
and a block whose session died is dispatched again by the loop.

## You are the monitor

One herd is **one task and its subtasks**, the task the user named. If no task was named, list the open ones
(`factory-list.sh`, `references/list.md`) and ask which one (`_shared/ask.md`); never start a herd on a task
nobody chose, and never start a second one alongside it.

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
| 3 triage, 4 grill, 5 plan-check, 6 decompose | a session | `session-monitor.sh --task <id> --step <step>`: triage and grill in the task worktree, which the first of them makes detached at the base (`worktree-add.sh --detach`) and the guard keeps read-only until the approval, so no step reads the human's clone and N herds over one repo each read their own copy; plan-check and decompose over the plan in the state clone; a step whose session still runs is a wait, never a second dispatch |
| 8 cut check, 9 approve and claim, 10 worktree | you | as in solve; step 10 puts that detached worktree on the task branch |
| 11 block work | sessions | `session-monitor.sh --task <id> --wave N`: one tab per block, each cut from the work branch and claimed for its session, which runs `block-tests` or its archetype skill under `_shared/block-session.md` and self-reports `tests_ready` or `review` |
| 11 block gates | you | the red rerun at `tests_ready`, `block-verify.sh`, the `code-reviewer` and the `architecture-auditor` on the block diff as your subagents, `block-mr.sh`, then `block-mr-merge.sh` |
| 12 to 16 | you | as in solve |

The rule behind the split: anything that writes the change is a session, anything that judges it is yours. Two
exceptions stay as in solve: the fix round of a block MR that came back `changes_requested`, and the docs
subagent of step 13, both your subagents. A dispatched session runs with `FACTORY_ROLE`, and the guard denies it
the approval, the done gate, the block MR merge, a merge on the forge, a curation approve and the fields of
`state-report.sh` that are yours: a block's `done`, `--set-phase` and `--mr-url`.

The watcher is armed once per herd, as the section above says; `solve-next.sh --herd` prints it as `Monitor
tool, armed once per herd: ...`, never as a command to run.

## Reading the watcher

`herd-watch.sh` prints one line per change: `<id> status <old> -> <new>`, `<id> phase <old> -> <new>`,
`<id> agent <old> -> <new>` and `<id> mr <old> -> <new>`, a first sighting without the arrow. A quiet pass prints
nothing. The agent values are
`working`, `blocked`, `ready` (herdr's idle or done), `unknown`, `closed` for a tab the scripts closed and `gone`
for a session no longer live.

1. On any line, rerun `solve-next.sh <T-id>` with the lane's flag, `--herd`, `--auto` or `--autonom`, and do
   what it prints.
2. `<id> agent <state> -> blocked` is a session at an approval or question dialog. A step session's question
   (a grill round, a spec-critic edit, a decompose ask) is the human's to answer in that tab: tell them which
   tab, and answer nothing yourself. A block session at a permission dialog: read it with `herdr agent read
   <name> --source recent-unwrapped --lines 120`, ask the human (`_shared/ask.md`), and answer with `herdr agent
   send-keys <name> <keys>` (a digit, arrows, `enter`, `esc`): a blocked agent refuses `herdr agent prompt`. The
   name is `<role>_<unit>` (`skills/herdr/SKILL.md`). Never answer for the human.
3. `<id> agent <state> -> gone` with the status unchanged is a session that died without reporting: the wait
   step of `solve-next.sh --herd` dispatches it again, since `session-monitor.sh` starts a block no live session
   carries; two deaths in a row is `_shared/blocked-question.md`. `<id> agent <state> -> ready` with the status
   unchanged is a session that stopped without its report: prompt it once, `herdr agent prompt <name> "Finish
   your delivery and report your status through state-report.sh"`; still nothing on the next line, set it
   `failed` with `state-report.sh --task <block> --set-status failed --attempts "<why>"`, and the loop takes it
   through the human and back to `ready`. A step, `<T-id>-<step> agent <state> -> ready` with its
   Completion unmet, may be a round waiting on its human, or a turn that ended short: prompt it once, and if
   that ends short too, `solve-next.sh --herd` prints the dispatch that starts it again. `-> unknown` is herdr
   not answering: `factory doctor` names the herdr server. `<id> agent <state> -> closed` is no dead session: the
   scripts closed a tab whose work was over.
4. `<block> status -> tests_ready` or `-> review`: its session finished its phase and reported it, with its own
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
| `<id> comments <n> -> <m>` | the MR has new comments, a review that left it `open` among them | `mr-watch.sh <T-id> --comments <id>`, read the threads, then the fix round for what they ask |

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
in a herdr pane. The human starts the sessions by hand, and `herd-watch.sh` still reports the status and phase
changes the sessions write into the state repo, with every agent reading `gone`. A step session (triage, grill,
plan-check, decompose) changes no status, so rerun `solve-next.sh --herd` when the human says it is done, and a
session that died is started again by hand, never dispatched twice.
