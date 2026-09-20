# claude-factory

The Claude Code plugin behind the factory loop: grill a spec, decompose it into tasks, run each block
in a worker session, review and merge. Skills, agents, toolsets and the policy hooks that enforce the
rules, in one installable plugin.

Extracted from `src/harness-plugin` of the `claude-os` repo.

## Install

```
/plugin marketplace add Lukdrasil/claude-factory
/plugin install claude-factory@claude-factory
```

Skills are then invoked as `/claude-factory:<skill>`, e.g. `/claude-factory:grill`.

## Layout

| path | what |
|---|---|
| `skills/` | archetype and workflow skills (`grill`, `decompose`, `block-*`, `factory`, `mr-review`, ...) |
| `agents/` | subagent definitions the skills spawn |
| `bin/` | the shell implementation: gates, task API, forge, verification |
| `hooks/hooks.json` | SessionStart, PreToolUse, PreCompact and Stop wiring |
| `toolsets/` | per-stack command bindings |
| `prompts/` | the worker session system prompt |

## Dependency

Depends on the `mattpocock-skills` plugin from the `mattpocock` marketplace.
