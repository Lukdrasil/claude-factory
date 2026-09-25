#!/bin/sh
# PreToolUse ask gate (P7 "the text describes, the hook enforces"): the deterministic twin of
# skills/_shared/ask.md. With `ui: docker` in herdr every question a factory session puts to the human is an ask
# the browser shows, so AskUserQuestion, which only the session's terminal shows, is denied and the reason names
# the shared rule. A session with no FACTORY_ROLE and no FACTORY_UNIT is a human's own and keeps it.
# exit 2 = deny, the reason on stderr reaches the agent.
set -eu

[ "${HERDR_ENV:-}" = 1 ] || exit 0
[ -n "${FACTORY_ROLE:-}${FACTORY_UNIT:-}" ] || exit 0
[ -n "${WORK_DIR:-}" ] || exit 0
ui=$(sed -n 's/^ui:[[:space:]]*//p' "$WORK_DIR/state/factory.yml" 2>/dev/null | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
[ "$ui" = docker ] || exit 0
printf 'ask-gate deny: with ui: docker in herdr a question to the human goes through skills/_shared/ask.md: print the round in the terminal and write it with bin/ui-ask.sh, so the browser and the CEO see it; AskUserQuestion shows only in this terminal.\n' >&2
exit 2
