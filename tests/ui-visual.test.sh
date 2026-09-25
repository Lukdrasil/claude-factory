#!/bin/sh
# The visual of a prototype ledger row: the brief in skills/grill/references/visual-brief.md, then, with Docker, the
# fixture of tests/ui-fixture.sh extended with task T-030 at its grill, session s30 in herdr with an open round and a
# visual (sessions/s30/visual.html drawn by the subagent, sessions/s30/visual.md with row, version and status written
# by the session), served through ui-up.sh from an image built from this checkout's ui/ under a tag of its content.
# The shell checks GET /visual; tests/ui-visual.test.js checks the drawer through the fixture's `browser` and prints
# its own PASS and FAIL lines. Without Docker it prints `SKIP ui-visual: no docker` after the brief checks.
set -u
unset FACTORY_UI_HOME FACTORY_UI_CONTAINER WORK_DIR
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

brief="$repo/skills/grill/references/visual-brief.md"
docs_fail=0
if [ -f "$brief" ]; then printf 'PASS the visual brief exists\n'; else printf 'FAIL the visual brief exists: no %s\n' "$brief"; docs_fail=1; fi
if grep -q 'visual-brief\.md' "$repo/skills/grill/references/ledger.md"; then
  printf 'PASS the ledger reference names the visual brief\n'
else
  printf 'FAIL the ledger reference names the visual brief: no visual-brief.md in ledger.md\n'
  docs_fail=1
fi

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-visual: no docker'
  exit "$docs_fail"
fi

tmp=$(mktemp -d)
name="cf-ui-visual-$$"
tag=$(cd "$repo" && find ui -type f ! -path 'ui/bin/*' ! -path 'ui/obj/*' -exec sha256sum {} + | LC_ALL=C sort -k2 | sha256sum | cut -c1-12)
mkdir -p "$tmp/plugin/.claude-plugin"
cp -R "$repo/bin" "$repo/ui" "$tmp/plugin/"
sed 's/"version":[[:space:]]*"\([^"]*\)"/"version": "\1-'"$tag"'"/' "$repo/.claude-plugin/plugin.json" \
  > "$tmp/plugin/.claude-plugin/plugin.json"
image="claude-factory-ui:$(sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp/plugin/.claude-plugin/plugin.json" | head -n1)"
bin="$tmp/plugin/bin"
cleanup() {
  FACTORY_UI_CONTAINER=$name HERDR_ENV=1 timeout 120 sh "$bin/ui-down.sh" >/dev/null 2>&1
  docker rm -f "$name" "$name-free" >/dev/null 2>&1
  docker image rm "$image" >/dev/null 2>&1
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

. "$repo/tests/ui-fixture.sh"
fail=$docs_fail

st="$state1/repos/claude-factory"
printf -- '---\nid: T-030\nrepo: claude-factory\nstatus: in_progress\ntier: yellow\narchetype: feature\ncomplexity: medium\n---\n\n# Goal\n%s\n' \
  'feat(fx): the fixture task with a drawn visual' > "$st/tasks/T-030-fixture.md"
printf -- '---\nid: T-031\nrepo: claude-factory\nstatus: in_progress\ntier: yellow\narchetype: feature\ncomplexity: medium\n---\n\n# Goal\n%s\n' \
  'feat(fx): the fixture task without a visual' > "$st/tasks/T-031-fixture.md"

session() { sh "$bin/ui-session.sh" "$@" || bad "ui-session.sh $*"; }
session --session s30 --pane w2:p30 --flow solve --task T-030 --step 'Step 4 of 16: grill T-030'
session --session s31 --pane w2:p31 --flow solve --task T-031 --step 'Step 4 of 16: grill T-031'
printf -- '---\nask: g1\ntask: T-030\nflow: solve\nstep: Step 4 of 16: grill T-030\nstatus: open\n---\n\n%s\n' \
  '❓ **Q3** - **Does the fixture grid fit on one screen?**: a prototype row, closed by the drawn visual.
  **A** yes
  **B** no, it scrolls

➡️ **A**: the visual shows it.' | sh "$bin/ui-ask.sh" --session s30 >/dev/null || bad 'ui-ask.sh --session s30 (g1)'

visual() { # <sid> <version>: the self-contained page the subagent draws; its script proves it ran and that the page is out of its reach
  cat <<EOF
<!doctype html>
<html><head><meta charset="utf-8"><title>visual</title></head>
<body><p id="out">not drawn</p>
<script>
let reach;
try { reach = window.parent.document.title; } catch (e) { reach = 'isolated'; }
document.getElementById('out').textContent = 'drawn v$2 of $1 by script, ' + (reach === 'isolated' ? 'isolated from the page' : 'reached the page: ' + reach);
</script></body></html>
EOF
}
visual s30 1 > "$ui/sessions/s30/visual.html"
printf -- '---\nrow: 3\nversion: 1\nstatus: current\n---\n' > "$ui/sessions/s30/visual.md"

# --- the server ---------------------------------------------------------------------------------------------------
up --state "$state1"; rc=$?
is 'ui-up.sh exits 0'                                         "$rc" 0
[ "$rc" = 0 ] || { sed 's/^/  up: /' "$tmp/up.err" | tail -n 30; exit 1; }
is 'the server runs the image of this checkout'               "$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)" "$image"
port=$(cat "$ui/port" 2>/dev/null)
token=$(cat "$ui/token" 2>/dev/null)
ready "$port" || { bad "the server never answered / on $port: $(docker logs "$name" 2>&1 | tail -n 20)"; exit 1; }

# --- GET /visual: the token as a query parameter, one visual per session --------------------------------------------
code=$(http "$port" "/visual?sid=s30&token=$token" -D "$tmp/headers")
is 'GET /visual with the token answers 200'                   "$code" 200
if cmp -s "$tmp/body" "$ui/sessions/s30/visual.html"; then pass 'GET /visual serves the session'"'"'s visual.html byte for byte'
else bad "GET /visual serves the session's visual.html byte for byte: $(head -c 300 "$tmp/body")"; fi
has 'GET /visual is text/html'                                '^[Cc]ontent-[Tt]ype: text/html' "$(cat "$tmp/headers")"
is 'GET /visual sends the Content-Security-Policy that keeps the token from leaving' \
  "$(tr -d '\r' < "$tmp/headers" | sed -n 's/^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]-[Ss][Ee][Cc][Uu][Rr][Ii][Tt][Yy]-[Pp][Oo][Ll][Ii][Cc][Yy]:[[:space:]]*//p')" \
  "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:"

code=$(http "$port" '/visual?sid=s30')
is 'GET /visual without a token answers 401'                  "$code" 401
hasnt 'GET /visual without a token serves nothing of the visual' 'drawn v' "$(cat "$tmp/body")"
code=$(http "$port" '/visual?sid=s30&token=0000')
is 'GET /visual with a wrong token answers 401'               "$code" 401
hasnt 'GET /visual with a wrong token serves nothing of the visual' 'drawn v' "$(cat "$tmp/body")"
code=$(http "$port" "/visual?sid=s31&token=$token")
is 'GET /visual of a session without a visual answers 404'    "$code" 404
code=$(http "$port" "/visual?sid=nobody&token=$token")
is 'GET /visual of an unknown session answers 404'            "$code" 404
code=$(http "$port" "/visual?sid=..%2Fs30&token=$token")
is 'GET /visual with a sid outside [A-Za-z0-9-]+ answers 400' "$code" 400
code=$(http "$port" "/visual?token=$token")
is 'GET /visual without a sid answers 400'                    "$code" 400

# --- the drawer, in the browser -------------------------------------------------------------------------------------
browser "$repo/tests/ui-visual.test.js"
rc=$?
cat "$tmp/browser.out"
is 'the browser checks exit 0'                                "$rc" 0
has 'the browser checks ran'                                  '^PASS |^FAIL ' "$(cat "$tmp/browser.out")"

exit $fail
