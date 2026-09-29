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

## Upgrading to 0.16

From 0.14, in order, once `claude plugin update` shows the new version, in a plain session in the state clone:

1. `git mv agents/<old>/memory agents/<new>/memory` for the three memory folders still under their old agent
   names (to `implementer`, `test-designer` and `code-reviewer`), in one commit; move a lesson into
   `repos/<key>/agents/<agent>/memory/` only when it names that repository; write the `alias:` of every
   repository into `repos.yml`; run `factory doctor`.
2. Clear the open proposals with `factory curate`; `bin/state-archive.sh --all`; `memory-consolidate` over
   `memory/global` when it is over budget.
3. Remove `spawn:`, `ui:`, `ui_port:` and `capacity:` from `factory.yml` if an earlier version wrote them; nothing
   reads them any more.

From 0.15, only step 3, plus: stop the 0.15 CEO session and the Factory UI (`docker rm -f claude-factory-ui`), and finish
or close the parents a lead was running, then resume each with `/claude-factory:factory solve <T-id>`. The
`request:` and `priority:` lines of old tasks and the `requests/` folder are ignored.

## Tests

```sh
for t in tests/*.test.sh; do sh "$t" || exit 1; done
```

## Dependency

Depends on the `mattpocock-skills` plugin from the `mattpocock` marketplace.
