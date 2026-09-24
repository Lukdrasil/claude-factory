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

Some skills set `disable-model-invocation`, so the model never picks them on its own and they run only when
invoked by name: `quality-kit` and its sub-skills `analyze-structure`, `setup-guardrails`, `architecture-tests`,
`analyzer-fix-example`, `add-module`, `add-slice` and `write-analyzer`, and `solution-map`.

## Layout

| path | what |
|---|---|
| `skills/` | archetype and workflow skills (`grill`, `decompose`, `block-*`, `factory`, `mr-review`, `issue-create`, ...) |
| `agents/` | subagent definitions the skills spawn |
| `bin/` | the shell implementation: gates, task state, forge, verification |
| `hooks/hooks.json` | SessionStart, PreToolUse, PreCompact and Stop wiring |
| `toolsets/` | per-stack command bindings |
| `tests/` | shell checks over the scripts above |

## Tests

```sh
for t in tests/*.test.sh; do sh "$t" || exit 1; done
```

## Dependency

Depends on the `mattpocock-skills` plugin from the `mattpocock` marketplace.
