---
name: factory-start
description: Starts the Factory UI and gives the link to open it in the chat.
disable-model-invocation: true
---

# factory-start

Plugin root: `${CLAUDE_PLUGIN_ROOT}`.

Run the Start step of `${CLAUDE_PLUGIN_ROOT}/skills/factory/references/ui.md` and follow its exit codes. Then
reply with the URL it printed as a markdown link, `[Factory UI](<url>)`, and the URL once more in a code span so
it can be copied whole with its token.
