# claude-factory

The Claude Code plugin behind the factory loop: hand over a task, and one session triages it, grills the spec,
decomposes it into blocks, runs each block in its own worktree, merges the block MRs into the task's work branch
and opens the task MR for review. Skills, agents, toolsets and the policy hooks that enforce the rules, in one
installable plugin.

## Install

```
/plugin marketplace add Lukdrasil/claude-factory
/plugin install claude-factory@claude-factory
```

Skills are then invoked as `/claude-factory:<skill>`, e.g. `/claude-factory:grill`.

A Windows clone gets LF line endings by design: `.gitattributes` pins them, so the `sh` scripts run under Git Bash.

Some skills set `disable-model-invocation`, so the model never picks them on its own and they run only when
invoked by name: `quality-kit` and its sub-skills `analyze-structure`, `setup-guardrails`, `architecture-tests`,
`analyzer-fix-example`, `add-module`, `add-slice` and `write-analyzer`, and `solution-map`.

## The flow

Once per machine `/claude-factory:factory init`, once per repository `/claude-factory:factory add-repo`. The
repository needs an `origin` on GitHub or GitLab and `gh` or `glab` logged in: every block and the task end in an
MR. Then, in a session in the registered clone:

```
/claude-factory:factory solve <the task in words>
```

The session creates the task and runs `bin/solve-next.sh` step by step without stopping between steps
(`skills/factory/references/solve.md`):

| step | what happens | who |
|---|---|---|
| intake | the parent task in the state repo, from the words given | session |
| 3 triage | recon, the investigation, related issues, tier and archetype | `scout`, `triage-analyst`, `issue-finder` |
| 4 grill | the spec interview that ends in `plan-ready.md` | the human answers the rounds |
| 5 plan-check | the plan against `docs/architecture/` | `plan-architect` |
| 6-8 decompose and cut check | one block per proposal, the wave plan | session, `dag-check.sh` |
| 9 approval | the parent and its blocks to `ready` | the human, one confirm |
| 10-11 blocks | per wave: red tests, implementation, verify, review, block MR, merge into the work branch | `test-designer`, `implementer`, `code-reviewer`, `architecture-auditor` |
| 12-13 quality | acceptance, crap, duplication, the integrated review | session, `code-reviewer` |
| 14 task MR | the MR into the base branch with every block MR listed | the human reviews and merges |
| 15-16 | self-report and knowledge review | session |

While the session watches the task MR with `mr-watch.sh`, its merge closes the task; otherwise
`/claude-factory:factory done <T-id>` does. A green task of low
complexity takes the quick lane instead: one worktree, no blocks (`references/solve-quick.md`).

Task ids are `T-<ALIAS>-<n>` per repository (`alias:` in `repos.yml`), blocks `T-<ALIAS>-<n>-<NN>`; the older
`T-<n>` ids stay valid. The state commits are local and `bin/state-push.sh`, the first command of every step,
carries them to the state root.

Lessons land as proposals. `/claude-factory:memory-daily <scope>` turns verified ones into drafts, and
`/claude-factory:memory-weekly <scope>` promotes drafts into the per-repository playbooks after the human's
rounds; a session in the state clone is told which passes are due. A change to a plugin skill is always a human
PR.

## The herd lane

In a herdr pane the same flow can run with every step that writes as its own interactive session:

```
/claude-factory:factory herd <T-id>        # or: herd <the task in words>
```

This session becomes the monitor. `bin/solve-next.sh <T-id> --herd` prints each step; triage, grill, plan-check,
decompose and every block of a wave go out through `bin/session-monitor.sh`, one herdr tab per unit, named
`<role>_<unit>` and recorded in the task's `.harness/<T-id>/herdr-tabs`: a step in the registered clone, or in the
state clone for plan-check and decompose, a block in its own worktree, claimed for its session, which reports
`tests_ready` or `review` under `skills/_shared/block-session.md`.
The monitor arms `bin/herd-watch.sh <T-id>` through the Monitor tool: one `herdr agent list` per pass, one line
per change of status, phase, agent or MR, the forge read on every pass and the state pushed. It answers a session
at a dialog with the human's word, runs every gate and merges the block MRs; a dispatched session carries
`FACTORY_ROLE`, and the guard keeps the human gates from it. The Stop hook `bin/rearm-check.sh` reminds a monitor
whose watcher expired, `herdr-tabs.sh reattach <T-id>` finds the sessions again after a herdr restart, and
doctor checks herdr 0.8.2 or later, its server and its Claude integration (`skills/factory/references/herd.md`,
`skills/herdr/SKILL.md`). Without herdr the same commands are printed for the human to start by hand.

## The auto lane

The herd with one interactive step:

```
/claude-factory:auto <T-id>                # or: auto <the task in words>; the same as factory auto <...>
```

After triage, `solve-next.sh <T-id> --auto` dispatches two solution sessions in the task worktree:
`solution-open` on `claude-opus-5-5` with no point of view imposed, and `solution-min` on `claude-fable-5-1`
held to the fewest changes, both at effort medium, each writing `research/<T-id>-solution-<view>.md` through
`skills/solution/SKILL.md`. The monitor shows both and the human picks, in one ask; the pick lands as
`## Solution` in the task and is the consent for the rest. The grill and decompose then run with `--auto`:
every round is written with its options and recommendation and the recommendation is taken, the human asked
only where `skills/_shared/auto-decision.md` says so (no recommendation stands, the choice leaves the chosen
solution, something destructive, every option fails). Every proposal names the tests that cover it, the
approval is the script run, a blocked block is answered by its recommendation, step 12 runs `build`, `test`
and the toolset's `e2e` when it binds one, and `block-verify.sh` holds every changed method to the crap
threshold, which is why the lane refuses a toolset without a `crap` row. The task MR is opened with
`mr-open.sh --decisions`, so its body lists every decision of the grill beside what changed and why, and the
watcher turns the human's review of that MR into fix rounds, approved without an ask, until it is merged
(`skills/factory/references/auto.md`).

`/claude-factory:autonom <T-id>` is the same lane with no pick and no question: the monitor compares the two
solutions and chooses, and a question with no recommendation is analysed over a table of its options and
decided by the session that meets it, the line marked `(analysed)` in the MR body. A destructive or
outward-facing choice and a session's permission dialog still reach the human.

## Layout

| path | what |
|---|---|
| `skills/` | archetype and workflow skills (`grill`, `decompose`, `block-*`, `factory`, `mr-review`, `issue-create`, ...) |
| `agents/` | subagent definitions the skills spawn |
| `bin/` | the shell implementation: gates, task state, forge, verification |
| `hooks/hooks.json` | SessionStart, PreToolUse, SubagentStart, PreCompact and Stop wiring (`hooks/README.md`) |
| `toolsets/` | per-stack command bindings |
| `tests/` | shell checks over the scripts above |

## Agents

Since 0.15.0 the agent names say what they do:

| agent | does |
|---|---|
| `scout` | read-only recon: blast radius, references, existing tests |
| `triage-analyst` | judges the triage recon into the parent's context |
| `issue-finder` | the open issues a problem or a finished change touches |
| `researcher-s0` to `researcher-s3` | deep research at four tiers |
| `plan-architect` | plan-check and cut-check before the approval |
| `domain-architect` | the per-domain review both architects call |
| `architecture-auditor` | after a change, per block and once per parent: does the architecture still hold, and the architectural risk |
| `test-designer` | the tests phase of a block: analysis, red tests, handoff |
| `implementer`, `implementer-senior` | the implement phase of a block, the second at high complexity |
| `test-writer`, `step-implementer` | characterization tests, one scoped implementation step |
| `code-reviewer` | the review of a block diff and of the whole task diff |
| `docs-architect` | the architecture docs |

`spec-critic`, `memory-curator`, `mr-reviewer`, `report-preview` and `solution-map-*` kept their names.

## Upgrading to 0.17

From 0.14, in order, once `claude plugin update` shows the new version, in a plain session in the state clone:

1. `git mv agents/<old>/memory agents/<new>/memory` for the three memory folders still under their old agent
   names (to `implementer`, `test-designer` and `code-reviewer`), in one commit; move a lesson into
   `repos/<key>/agents/<agent>/memory/` only when it names that repository; write the `alias:` of every
   repository into `repos.yml`; run `factory doctor`.
2. Clear the open proposals with `factory curate`; `bin/state-archive.sh --all`; `memory-consolidate` over
   `memory/global` when it is over budget.
3. Remove `spawn:`, `ui:`, `ui_port:` and `capacity:` from `factory.yml` if an earlier version wrote them; nothing
   reads them any more. The herd lane needs no `spawn:`: `factory herd` uses herdr whenever this session runs in
   a herdr pane.

From 0.15, only step 3, plus: stop the 0.15 CEO session and the Factory UI (`docker rm -f claude-factory-ui`), and finish
or close the parents a lead was running, then resume each with `/claude-factory:factory solve <T-id>`. The
`request:` and `priority:` lines of old tasks and the `requests/` folder are ignored.

## Tests

```sh
for t in tests/*.test.sh; do sh "$t" || exit 1; done
```

## Dependency

Depends on the `mattpocock-skills` plugin from the `mattpocock` marketplace.
