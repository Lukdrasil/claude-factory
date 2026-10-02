# factory auto

`factory auto <the task in words> [--repo <key>]`, or `factory auto <T-id>`: the herd of `references/herd.md`
with one interactive step and nothing else interactive. Two sessions propose a solution each, the human picks
one, and from that pick the flow runs itself to the task MR: the grill and decompose take every recommendation,
the approval is the script run, the blocks go out as sessions and come back through every gate, the build and
the tests run, the end-to-end suite included where the repo binds one, and the MR carries every decision the
grill took. The human's part is the pick, the MR review, and the few questions
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-decision.md` sends them.

Everything `references/herd.md` says holds: you are the monitor, the watcher is armed once per herd, a
session's report is a claim you rerun, `review` is not the end. This file is the delta. It needs herdr like
the herd; without it the sessions are started by hand from the printed lines.

## Start

As the Start of `references/solve.md`: intake, create, then this file. There is no quick lane: an auto task
takes the full flow whatever its tier. Then `sh <plugin-root>/bin/solve-next.sh <T-id> --auto`, do what it
prints, verify its `Completion:` line, and run it again, until step 16. `--auto` is `--herd` with the deltas
below, and it refuses to go past triage while the repo's toolset binds no `crap`: the lane promises every
changed method at or under the crap threshold, 8 unless `crap-threshold:` says otherwise, and only
`block-verify.sh` with a `crap` row can hold that. Add the row, and an `e2e` row when the repo has an
end-to-end suite, before you start.

## Step 4a: two solutions and the pick

The one step the human takes part in. After triage, `solve-next.sh --auto` dispatches two step sessions
through `session-monitor.sh --task <T-id> --step <step>`, both in the detached task worktree, read-only:

| step | model | effort | view |
|---|---|---|---|
| `solution-open` | `claude-opus-5-5` | medium | no point of view imposed: the solution the session would defend in a design review |
| `solution-min` | `claude-fable-5-1` | medium | the fewest changes that meet the goal |

Each runs `skills/solution/SKILL.md` and writes `<state>/repos/<key>/research/<T-id>-solution-<view>.md`. They
ask nobody: a `blocked` solution session is at a permission dialog, answered as `references/herd.md` says. A
session that ends with no file is dispatched again by the next `solve-next.sh --auto`; two deaths in a row
is `_shared/blocked-question.md` to the human.

Once both files exist, the step is the pick. Show both files in full, then one ask (`_shared/ask.md`):

```
❓ **Q1** - **The solution for <T-id>**
  **A** the open solution (<T-id>-solution-open.md): <its ## Approach in one line>
  **B** the minimal solution (<T-id>-solution-min.md): <its ## Approach in one line>

➡️ **<A|B>**: <one paragraph: which you would take and the trade-off, size against shape>
```

The human answers `A`, `B`, or in their own words: a mix of the two, a change to one, a third way. Write the
answer as `## Solution` at the end of the task file, verbatim:

```markdown
## Solution
- view: <open|min|mixed>
- file: repos/<key>/research/<T-id>-solution-<view>.md
- the human's words: <their answer as given, or "as written">
```

then `state-report.sh --task <T-id> --no-status --message 'chore(<T-id>): solution chosen'`. That yes is the
consent for the rest of the lane. Nothing after it asks for a confirm: not the grill, not decompose, not the
approval, not a block MR. A human who wants the gates back runs `factory herd <T-id>` on the same task instead.

## The grill and decompose, by recommendation

Step 4 dispatches `session-monitor.sh --task <T-id> --step grill --auto`, the grill skill with `--auto`
(`skills/grill/SKILL.md`, `## Auto mode`): the spec is the `## Solution` of the task and the file it names,
every round is written out with its options and recommendation and the recommendation is taken, the design
round and the proposals round the same, and only a question `_shared/auto-decision.md` names reaches the
human, in the grill's tab. The watcher's `<T-id>-grill agent ... -> blocked` is that question: tell the human
which tab. Two musts the auto grill adds, checked by you on the plan before step 5: every proposal's `steps:`
names the tests that cover its functionality, one sub-bullet per test file (`test <path>: <what it proves>`),
and the end-to-end test it needs, or `no e2e`; and `## Decisions` holds every decision taken, the ones the
human answered ending with `(human)`.

Step 5, plan-check, is the herd's. Step 6 dispatches `--step decompose --auto` (`skills/decompose/SKILL.md`,
`## Auto mode`): the spec-critic's proposed edits are applied as written, a cut-check finding is taken by its
recommendation, and the block list ends the step as a notice.

Step 9 is `task-approve.sh` over the parent and its blocks with no ask, the bodies printed as a notice so the
human can read what went ready. Step 10 and step 11 are the herd's: one session per block, the red tests
rerun by you at `tests_ready`, `block-verify.sh`, the reviewer and the auditor as your subagents, `block-mr.sh`,
`block-mr-merge.sh`. The crap gate inside `block-verify.sh` is the lane's promise: a block over the threshold
is red, its fix loop `_shared/crap-loop.md`, and a block red twice is `failed`, which is a question under
`_shared/auto-decision.md` (its fourth case) before anything is dispatched again.

A block that comes back `blocked` is yours to answer: read its `## Question`, take the recommendation, write
the answer line with `(auto)`, apply what the option requires and `task-approve.sh` it back to `ready`. Ask
the human only where `_shared/auto-decision.md` says so. A draft block written after the pick (a fix round,
a thread outside a block's acceptance) is approved the same way, without an ask.

## Steps 12 to 16: build, tests, the MR

Step 12 runs the parent's `## Acceptance` verbatim, then the toolset's `build` and `test` bindings over the
work branch, then `e2e` when the toolset binds one, each with its exit code under `## Evidence`; a toolset
without `e2e` gets the line `no e2e binding` there. A red run is a fix block, as a `changes needed` verdict is
in `references/solve.md`, approved without an ask. `crap`, `format` and `arch-build` as in solve.

Step 14 opens the task MR with `mr-open.sh <T-id> --decisions`: the description of
`_shared/mr-description.md`, what changed and why in under 120 words, the `## Blocks` list, and a
`## Decisions` section with every bullet of the plan's `## Decisions`, the `[locked]` tag dropped. That
section is how the human reviews what was decided for them; the lines ending with `(human)` are the ones they
answered. Tell the human the MR is theirs to review, and nothing else: the lane does not ask them to merge.

Step 16 ends the loop as in solve. The watcher stays armed: `herd-watch.sh` runs `mr-watch.sh` on every pass,
and the task MR's lines are the human's review coming back:

| line | what you do |
|---|---|
| `<T-id> mr <any> -> merged` | `references/done.md`, without an ask |
| `<T-id> mr <any> -> changes-requested`, `new-comments` | the fix round of `references/solve.md` (`## After the task MR`): read the threads with `mr-watch.sh <T-id> --comments <T-id>`, one fix block per change asked, cut-check, `task-new.sh --parent`, approved without an ask, worked as a block session through step 11, then steps 12 to 14 again and `mr-open.sh --decisions` to refresh the body |
| `<T-id> mr <any> -> ci-failed` | a fix round the same way |
| `<T-id> mr <any> -> approved` | say so, keep watching |

A thread that is a question is answered on the MR by the human, as in solve; a thread that asks for work the
chosen solution does not cover is the second case of `_shared/auto-decision.md`: ask. Only `done` or `closed`
disarms the watcher.

## What stays the human's

The pick of step 4a, the questions `_shared/auto-decision.md` sends them, the permission dialogs of the
sessions, and the review and merge of the task MR. Everything else the lane decides and records: the grill's
`## Decisions`, the answer lines of the blocks, the `## Merged` lines of the block MRs. A human who reads the
MR body and disagrees with a decision answers on the MR, and the fix round above carries it.
