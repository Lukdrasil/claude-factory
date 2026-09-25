#!/bin/sh
# ask-gate.sh (F33): with `ui: docker` in herdr, a factory session's question to the human is a UI ask
# (skills/_shared/ask.md), so AskUserQuestion, which only its terminal shows, is denied; a human's own session
# (no FACTORY_ROLE, no FACTORY_UNIT), a session outside herdr and `ui: off` keep it.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
mkdir -p "$tmp/w/state"
printf 'ui: docker\n' > "$tmp/w/state/factory.yml"

try() { # <want exit> <label> <env...>
  want=$1 label=$2; shift 2
  printf '{"tool_name":"AskUserQuestion","tool_input":{"questions":[]}}' \
    | env -u HERDR_ENV -u FACTORY_ROLE -u FACTORY_UNIT WORK_DIR="$tmp/w" "$@" sh "$root/bin/ask-gate.sh" >/dev/null 2>"$tmp/err"
  got=$?
  if [ "$got" -eq "$want" ]; then printf 'PASS %s\n' "$label"; else printf 'FAIL want=%s got=%s %s\n' "$want" "$got" "$label"; fail=1; fi
}

try 2 'a step session in herdr with ui: docker is denied'      HERDR_ENV=1 FACTORY_ROLE=decompose FACTORY_UNIT=T-TAG-2-decompose
grep -q '_shared/ask.md' "$tmp/err"; r=$?
if [ $r -eq 0 ]; then printf 'PASS the deny names _shared/ask.md\n'; else printf 'FAIL the deny names _shared/ask.md\n'; fail=1; fi
try 2 'a lead in herdr with ui: docker is denied'              HERDR_ENV=1 FACTORY_ROLE=repo-lead
try 0 'a human session (no FACTORY_ROLE or FACTORY_UNIT) keeps it' HERDR_ENV=1
try 0 'outside herdr it is allowed'                           FACTORY_ROLE=decompose
printf 'ui: off\n' > "$tmp/w/state/factory.yml"
try 0 'with ui: off it is allowed'                             HERDR_ENV=1 FACTORY_ROLE=decompose
rm "$tmp/w/state/factory.yml"
try 0 'with no factory.yml it is allowed'                      HERDR_ENV=1 FACTORY_ROLE=decompose

exit $fail
