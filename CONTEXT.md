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
- **drawer**: the right-hand panel of the pipeline page for one task or for setup, holding its open asks and its
  context. Avoid: modal, sidebar.
- **decision mode**: the drawer of a task with an open ask: at least 60% of the viewport wide, the asks first,
  everything else behind one collapsed "Task details". Avoid: ask mode, focus mode.

## Repositories

- **onboarding session**: the session `session-monitor.sh --step onboard --scope <key>` starts in a registered
  clone (role `onboard`, unit `onboard-<key>`), which writes its onboarding report and changes nothing else.
  Avoid: initialization lead, onboarding lead.
- **onboarding report**: `<state>/repos/<key>/onboarding.md`, the onboarding session's one write: a status, a
  summary, one line per check and the proposals the human turns into requests. Avoid: readiness report, audit.
- **clones directory**: the absolute `clones:` directory of `<state>/factory.yml`, where `factory-add-repo.sh
  --clone` puts `<clones>/<key>`; never inside `WORK_DIR`, which holds the task worktrees. Avoid: repos dir,
  work dir.
