#!/bin/sh
# model-for.sh: a step the monitor spawns as its own herdr session runs in auto mode, which haiku has not, so the
# triage and ops archetypes answer sonnet; subagent-only picks (phase verify, a green tier) keep haiku.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/bin
fail=0
check() { # <what> <want> <args...>
  what=$1 want=$2; shift 2
  got=$(sh "$bin/model-for.sh" "$@" 2>&1)
  if [ "$got" = "$want" ]; then printf 'PASS %s\n' "$what"; else printf 'FAIL %s: want %s, got %s\n' "$what" "$want" "$got"; fail=1; fi
}
check 'triage runs on sonnet'              sonnet triage yellow '' 0 low
check 'ops runs on sonnet'                 sonnet ops green '' 0 low
check 'a feature runs on opus'             opus feature yellow '' 0 low
check 'phase verify stays on haiku'        haiku feature yellow verify 0 low
check 'a green research pick stays haiku'  haiku research green '' 0 low
check 'attempt 1 escalates triage to opus' opus triage yellow '' 1 low
exit "$fail"
