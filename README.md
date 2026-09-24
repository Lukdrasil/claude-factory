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

A Windows clone gets LF line endings by design: `.gitattributes` pins them, so the `sh` scripts run under Git Bash.

## Layout

| path | what |
|---|---|
| `skills/` | archetype and workflow skills (`grill`, `decompose`, `block-*`, `factory`, `mr-review`, `issue-create`, ...) |
| `agents/` | subagent definitions the skills spawn |
| `bin/` | the shell implementation: gates, task API, forge, verification |
| `hooks/hooks.json` | SessionStart, PreToolUse, PreCompact and Stop wiring |
| `toolsets/` | per-stack command bindings |
| `prompts/` | the worker session system prompt |
| `tests/` | shell checks over the scripts above |
| `ui/` | the Factory UI server, a .NET Native AOT container (`ui/README.md`) |

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
