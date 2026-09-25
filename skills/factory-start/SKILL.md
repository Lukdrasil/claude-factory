---
name: factory-start
description: Makes the Factory UI fully active, ui docker in factory.yml, the UI with its relay and the CEO session registered with it, and gives the link to open the UI in the chat.
disable-model-invocation: true
---

# factory-start

Plugin root: `${CLAUDE_PLUGIN_ROOT}`.

`<root>` is `WORK_DIR` (default `~/factory`), `<state>` is `<root>/state`. Without `<state>/repos.yml` there is no
factory yet: tell the user to run `/claude-factory:factory init` and stop.

1. **ui: docker.** Without the line `ui: docker` in `<state>/factory.yml` no session registers with the UI and no
   question reaches it. Run `sh ${CLAUDE_PLUGIN_ROOT}/bin/factory-init.sh --root <root> --ui docker`: it exits 3
   with the diff of `factory.yml` and the settings, or 0 when there is nothing to change. Show the diff, ask the
   user in the terminal, and on a yes rerun it with `--yes`. A no stops here with the diff as the report.
2. **UI.** Run the Start step of `${CLAUDE_PLUGIN_ROOT}/skills/factory/references/ui.md` and follow its exit codes.
   It also starts the relay that types the UI's answers into the sessions.
3. **CEO.** When `herdr agent get ceo` succeeds the CEO runs already: register it with the UI, so the page's
   buttons reach it, from the `agent_session.value` and `pane_id` that command printed:

   ```sh
   sh ${CLAUDE_PLUGIN_ROOT}/bin/ui-session.sh --session <agent_session.value> --pane <pane_id> --flow ceo --task ceo
   ```

   Otherwise open its tab in `<state>` and start it; it registers itself at its start:

   ```sh
   herdr tab create --cwd <state> --label ceo --focus
   herdr pane run <pane_id> "claude '/claude-factory:factory ceo'"
   ```

   `<pane_id>` is the `pane_id` in the JSON `tab create` prints.
4. **Reply** with the URL step 2 printed as a markdown link, `[Factory UI](<url>)`, the URL once more in a code
   span so it can be copied whole with its token, and whether the CEO was started or registered. When step 1
   changed `factory.yml`, add that sessions started before it, the CEO excepted, show in the UI only once
   restarted.
