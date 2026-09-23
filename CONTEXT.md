# Context

The terms of this repo, one line each. A term here means exactly this in code, skills and tasks.

## Factory UI

- **ask**: one question file a session writes for the human, a round, a confirm or a notice, at
  `sessions/<sid>/asks/<ask>.md` in the UI home, written and closed only through `bin/ui-ask.sh`. Avoid:
  prompt, request.
- **answer file**: `sessions/<sid>/answers/<seq>-<ask>.txt`, one answer's shorthand verbatim, written only by
  the server. Avoid: answer line, event, message.
- **relay**: `bin/ui-relay.sh` in its own herdr tab, typing each answer file into its session's herdr pane with
  `herdr agent prompt`. Avoid: listener, watcher, poller.
- **UI home**: `~/.claude-factory/ui` (`$FACTORY_UI_HOME`), mounted at `/ui`, one folder per session under
  `sessions/`. Avoid: session folder for the whole.
