# claude-factory

The Claude Code plugin behind the factory loop: grill a spec, decompose it into tasks, run each block
in its own worktree, review and merge. Skills, agents, toolsets and the policy hooks that enforce the
rules, in one installable plugin.

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

## Layout

| path | what |
|---|---|
| `skills/` | archetype and workflow skills (`grill`, `decompose`, `block-*`, `factory`, `mr-review`, `issue-create`, ...) |
| `agents/` | subagent definitions the skills spawn |
| `bin/` | the shell implementation: gates, task state, forge, verification |
| `hooks/hooks.json` | SessionStart, PreToolUse, SubagentStart, SubagentStop, PreCompact and Stop wiring (`hooks/README.md`) |
| `toolsets/` | per-stack command bindings |
| `tests/` | shell checks over the scripts above |
| `ui/` | the Factory UI server, a .NET Native AOT container (`ui/README.md`) |

## The org

The factory runs as an org of interactive Claude Code sessions in herdr, never as a headless run (`claude -p`,
the Agent SDK, a routine or a cron that starts `claude`), and never under `bypassPermissions`.

- **CEO** (`skills/factory/references/ceo.md`): one session in `$WORK_DIR/state`, started there inside herdr
  with `claude '/claude-factory:factory ceo'`. It starts the UI, takes a request with a priority, opens a request map
  (`requests/<R-id>/`), makes one parent per repository under that request id, and runs the automatic chain as
  step sessions (triage, the map chart with `claude-factory:wayfinder`, grill, plan-check, decompose). The
  human answers the grilling rounds and approves the plan once per request; approved parents queue by priority
  and start as capacity frees up. It watches every herd, re-arms its watchers after a restart and offers the
  daily and weekly memory passes.
- **Lead** (`lead_<unit>`, `skills/factory/references/lead.md`): one session per approved parent, in the
  parent's worktree and its own herdr workspace. It runs the herd flow for that parent, one MR per block into
  the task's work branch that it merges itself (a high-risk block waits for the human), and one MR per parent
  into the base branch that the human reviews and merges. It ends with its task.
- **Team**: the agents under `agents/`, briefed per repository by the playbooks in the state repo
  (`repos/<key>/agents/<agent>/playbook.md`). Each role has a capacity shared across all leads (`capacity:` in
  `factory.yml`), enforced by the hooks on `Agent`, `SubagentStart` and `SubagentStop`.
- **Knowledge**: lessons land as proposals, the daily pass turns verified ones into drafts, the weekly pass
  promotes drafts into the playbooks after the human's rounds; a change to a plugin skill is always a human PR.

Task ids are `T-<ALIAS>-<n>` per repository (`alias:` in `repos.yml`), blocks `T-<ALIAS>-<n>-<NN>`; the older
`T-<n>` ids stay valid.

### Agents

Since 0.15.0 the agent names say what they do:

| agent | does |
|---|---|
| `scout` | read-only recon: blast radius, references, existing tests |
| `triage-analyst` | judges the triage recon into the parent's context |
| `issue-finder` | the open issues a problem or a finished change touches |
| `researcher-s0` to `researcher-s3` | deep research at four tiers, counted as one `researcher` role |
| `plan-architect` | plan-check and cut-check before the approval |
| `domain-architect` | the per-domain review both architects call |
| `architecture-auditor` | after a change, per block and once per parent: does the architecture still hold, and the architectural risk |
| `test-designer` | the tests phase of a block: analysis, red tests, handoff |
| `implementer`, `implementer-senior` | the implement phase of a block, the second at high complexity |
| `test-writer`, `step-implementer` | characterization tests, one scoped implementation step |
| `code-reviewer` | the review of a block diff and of the whole task diff |
| `docs-architect` | the architecture docs |

`spec-critic`, `memory-curator`, `mr-reviewer`, `report-preview` and `solution-map-*` kept their names.

### After the upgrade to 0.15.0

In order, once `claude plugin update` shows 0.15.0:

1. **M0** (you, in a plain session in the state clone): `git mv agents/<old>/memory agents/<new>/memory` for
   the three memory folders still under their old agent names (to `implementer`, `test-designer` and
   `code-reviewer`), in one commit; move a lesson into
   `repos/<key>/agents/<agent>/memory/` only when it names that repository; write the `alias:` of every
   repository into `repos.yml`; run `factory doctor`.
2. **M1** (you, with `factory curate`, then the scripts): clear the open proposals; `bin/state-archive.sh --all`;
   archive retired keys and finished leftovers; `memory-consolidate` over `memory/global` when it is over
   budget.
3. **M2** (the CEO session): the daily pass per scope over the older lessons, then the weekly rounds with you.
4. **M3** (you, in the Setup tab or the terminal): `capacity:` in `factory.yml`, the priority defaults, doctor
   green, then start the CEO: `claude '/claude-factory:factory ceo'` in `$WORK_DIR/state`, in a herdr pane.
5. **M4** (you and the CEO): one live request across two repositories from intake to both task MRs merged; what
   it teaches becomes the first lessons of the repo-lead playbooks.

## Browser UI

An optional local page beside the CLI, for Claude Code sessions inside herdr with `ui: docker` in
`factory.yml`. It needs Docker, and nothing else on the host.

```sh
sh bin/ui-up.sh [--state <dir>]   # build the image when missing, start or reuse the container, open the relay tab
sh bin/ui-down.sh                  # remove the container and close the relay tab
```

`ui-up.sh` prints `http://127.0.0.1:<port>/#token=<token>`. Open that URL: the token in the fragment is what the
page sends with every API call. The port is `ui_port` from `factory.yml` (7171 by default), or a random free
port when that one is taken. The port in use is written to `port` in the UI home (`~/.claude-factory/ui`,
or `$FACTORY_UI_HOME`). One container serves every session on the machine. It is recreated when the plugin
version or the state dir changes. `ui-up.sh` exits 3 when Docker is not running and 4 outside herdr.

## Tests

```sh
for t in tests/*.test.sh; do sh "$t" || exit 1; done
```

## Dependency

Depends on the `mattpocock-skills` plugin from the `mattpocock` marketplace.
