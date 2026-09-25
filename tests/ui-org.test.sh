#!/bin/sh
# The Org tab in a browser: the fixture of tests/ui-fixture.sh served through ui-up.sh from an image of this tree, and
# tests/ui-org.test.js driving the tab through the fixture's `browser` against the /api/org shapes of the wave-2
# contract, answered by the browser's own routes, and against a server without the route; then phase real, the
# Pipeline, Map, Plan, Org and Memory tabs over the server of the fixture's `org_state`.
# The browser checks print their own PASS and FAIL lines. Without Docker it prints `SKIP ui-org: no docker`.
set -u
unset FACTORY_UI_HOME FACTORY_UI_CONTAINER WORK_DIR
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$repo/bin"

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-org: no docker'
  exit 0
fi

tmp=$(mktemp -d)
name="cf-ui-org-$$"
cleanup() {
  FACTORY_UI_CONTAINER=$name HERDR_ENV=1 timeout 120 sh "$bin/ui-down.sh" >/dev/null 2>&1
  docker rm -f "$name" "$name-free" >/dev/null 2>&1
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

. "$repo/tests/ui-fixture.sh"

ver=$(sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$repo/.claude-plugin/plugin.json" | head -n1)
timeout 15m docker build -q -t "claude-factory-ui:$ver" "$repo/ui" > "$tmp/build.out" 2>&1 \
  || { bad "building claude-factory-ui:$ver failed: $(tail -n 20 "$tmp/build.out")"; exit 1; }
up --state "$state1"; rc=$?
is 'ui-up.sh exits 0'                                         "$rc" 0
[ "$rc" = 0 ] || { sed 's/^/  up: /' "$tmp/up.err" | tail -n 30; exit 1; }
port=$(cat "$ui/port" 2>/dev/null)
token=$(cat "$ui/token" 2>/dev/null)
ready "$port" || { bad "the server never answered / on $port: $(docker logs "$name" 2>&1 | tail -n 20)"; exit 1; }

browser "$repo/tests/ui-org.test.js"
rc=$?
cat "$tmp/browser.out"
is 'the browser checks exit 0'                                "$rc" 0
has 'the browser checks ran'                                  '^PASS |^FAIL ' "$(cat "$tmp/browser.out")"

# --- phase real: the server over the org state tests/ui-fixture.sh builds with map.sh, capacity.sh and pass-stamp.sh,
# the CEO registered through ui-session.sh; once the page asks for it with $ui/lease-now, capacity.sh takes one more
# scout lease 2 s later, a change under .capacity that never reaches the event stream -----------------------------
state3="$tmp/state3"
org_state "$state3" > "$tmp/org.out" 2>&1 || { bad "org_state: $(tail -n 20 "$tmp/org.out")"; exit 1; }
sh "$bin/ui-session.sh" --session s-ceo --pane w1:p9 --flow ceo --task ceo || bad 'ui-session.sh registers the CEO'
up --state "$state3"; rc=$?
is 'ui-up.sh over the org state exits 0'                      "$rc" 0
[ "$rc" = 0 ] || { sed 's/^/  up: /' "$tmp/up.err" | tail -n 30; exit 1; }
port=$(cat "$ui/port" 2>/dev/null)
ready "$port" || { bad "the server over the org state never answered on $port"; exit 1; }
printf 'real\n' > "$ui/org-phase"
(
  i=0
  while [ ! -f "$ui/lease-now" ] && [ $i -lt 1200 ]; do sleep 0.1; i=$((i + 1)); done
  [ -f "$ui/lease-now" ] && sleep 2 && sh "$bin/capacity.sh" acquire scout agent-2 --session sess-2 --state "$state3" >/dev/null 2>&1
) &
lease=$!
browser "$repo/tests/ui-org.test.js"
rc=$?
kill "$lease" 2>/dev/null
cat "$tmp/browser.out"
is 'the browser checks of phase real exit 0'                  "$rc" 0
has 'the browser checks of phase real ran'                    '^PASS |^FAIL ' "$(cat "$tmp/browser.out")"
is 'capacity.sh took the second scout lease'                  "$(sh "$bin/capacity.sh" count scout --state "$state3")" 2/8

exit $fail
