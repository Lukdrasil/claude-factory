#!/bin/sh
# The Factory UI server in its container, driven through ui-up.sh and ui-down.sh over a fixture state repo, a
# throwaway UI home, an ephemeral host port and a stub `herdr` on PATH: the token, the answer files, the change
# stream, the scan past an unreadable folder, container reuse and recreation on a label mismatch, the port
# fallback, the relay tab, the exit codes, the org routes over a state built with the real scripts (requests, the
# org, setup, the archive fallback, the free message to the CEO, the scan past .git and .capacity), and the
# server's own xunit tests in the SDK image. The container is
# named from FACTORY_UI_CONTAINER and its image tagged from FACTORY_UI_IMAGE, per run, so neither a real
# claude-factory-ui on this machine nor its shared tag claude-factory-ui:<version> is ever touched or tested.
# Without Docker it prints `SKIP ui-server: no docker` and exits 0.
set -u
unset FACTORY_UI_HOME FACTORY_UI_CONTAINER WORK_DIR
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$repo/bin"

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-server: no docker'
  exit 0
fi

tmp=$(mktemp -d)
name="cf-ui-test-$$"
ver=$(sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$repo/.claude-plugin/plugin.json" | head -n1)
image="claude-factory-ui:test-$$"
shared="claude-factory-ui:$ver"
stream=''
cleanup() {
  [ -z "$stream" ] || kill "$stream" 2>/dev/null
  FACTORY_UI_CONTAINER=$name HERDR_ENV=1 timeout 120 sh "$bin/ui-down.sh" >/dev/null 2>&1
  docker rm -f "$name" "$name-hold" "$name-free" "$name-shared" >/dev/null 2>&1
  docker image rm "$image" >/dev/null 2>&1
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

. "$repo/tests/ui-fixture.sh"

relay_label='ui relay (no agent)'
relay_tabs() { grep -lxF "$relay_label" "$HERDR_STUB"/tabs/* 2>/dev/null | wc -l | tr -d ' '; }
creates() { grep -c '^tab create' "$HERDR_STUB/log" | tr -d ' '; }
closes() { grep -c '^tab close' "$HERDR_STUB/log" | tr -d ' '; }

label() { docker inspect -f "{{index .Config.Labels \"$1\"}}" "$name" 2>/dev/null; }
cid() { docker inspect -f '{{.Id}}' "$name" 2>/dev/null; }
running() { r=$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null) || r=absent; printf '%s' "$r"; }
mounts() { docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Source}} {{.RW}}{{"\n"}}{{end}}' "$name" 2>/dev/null; }
post() { # <port> <sid> <json> [token]
  http "$1" "/api/answers/$2" -X POST -H 'Content-Type: application/json' -H "X-Factory-Token: ${4:-$token}" --data-binary "$3"
}
answers() { ls -A "$ui/sessions/s1/answers" 2>/dev/null | tr '\n' ' '; }

# --- exit 4 outside herdr, exit 3 without Docker, and this suite's own skip line -----------------------------------
env -u HERDR_ENV timeout 120 sh "$bin/ui-up.sh" --state "$state1" > "$tmp/o" 2>&1; rc=$?
is 'ui-up.sh without HERDR_ENV=1 exits 4'                     "$rc" 4
is 'outside herdr no container is started'                    "$(running)" absent

mkdir -p "$tmp/nodocker"
printf '#!/bin/sh\necho "Cannot connect to the Docker daemon" >&2\nexit 1\n' > "$tmp/nodocker/docker"
chmod +x "$tmp/nodocker/docker"
PATH="$tmp/nodocker:$PATH" HERDR_ENV=1 timeout 120 sh "$bin/ui-up.sh" --state "$state1" > "$tmp/o" 2>&1; rc=$?
is 'ui-up.sh without a running Docker exits 3'                "$rc" 3
out=$(PATH="$tmp/nodocker:$PATH" timeout 60 sh "$repo/tests/ui-server.test.sh" 2>&1); rc=$?
is 'without Docker this suite prints only its skip line'      "$out" 'SKIP ui-server: no docker'
is 'without Docker this suite exits 0'                        "$rc" 0

# --- the first ui-up.sh: builds the image, starts the container as the host uid:gid, opens the relay tab ----------
# F23: with the shared tag in use by a container, as by the human's own UI, the suite still builds and runs the
# image of this checkout under its own tag and leaves the shared tag where it was
shared_id=$(docker image inspect -f '{{.Id}}' "$shared" 2>/dev/null) || shared_id=''
[ -z "$shared_id" ] || docker create --name "$name-shared" "$shared" >/dev/null
is "the per-run image $image is not there before the first ui-up.sh" "$(docker image inspect -f ok "$image" 2>/dev/null)" ''
up --state "$state1"; rc=$?
is 'the first ui-up.sh exits 0'                               "$rc" 0
[ "$rc" = 0 ] || sed 's/^/  up: /' "$tmp/up.err" | tail -n 30
is "the image $image exists"                                  "$(docker image inspect -f ok "$image" 2>/dev/null)" ok
is 'the container runs the per-run image, not the shared tag' "$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)" "$image"
is 'the container runs the image built under the per-run tag' "$(docker inspect -f '{{.Image}}' "$name" 2>/dev/null)" \
  "$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null)"
is "the shared tag $shared is left where it was"              "$(docker image inspect -f '{{.Id}}' "$shared" 2>/dev/null)" "$shared_id"
is 'the container runs'                                       "$(running)" true
is 'it runs as the host uid:gid'                              "$(docker inspect -f '{{.Config.User}}' "$name" 2>/dev/null)" "$(id -u):$(id -g)"
is 'its cf.version label is the plugin version'               "$(label cf.version)" "$ver"
is 'its cf.state label is the state dir'                      "$(label cf.state)" "$state1"
has '/state is the state dir, read-only'                      "^/state $state1 false$" "$(mounts)"
has '/ui is the UI home, read-write'                          "^/ui $ui true$" "$(mounts)"
ports=$(docker port "$name" 2>/dev/null)
has 'it is published on 127.0.0.1:<ui_port>'                  "127\.0\.0\.1:$port1\$" "$ports"
hasnt 'it is published on no other address'                   '0\.0\.0\.0|\[::\]' "$ports"
is 'the port in use is written to port in the UI home'        "$(cat "$ui/port" 2>/dev/null)" "$port1"
token=$(cat "$ui/token" 2>/dev/null)
has 'the token is 32 hex bytes'                               '^[0-9a-f]{64}$' "$token"
is 'the token file has mode 600'                              "$(stat -c %a "$ui/token" 2>/dev/null)" 600
has 'the printed URL carries the port and the token fragment' "http://127\.0\.0\.1:$port1/#.*$token" "$(cat "$tmp/up.out")"
is 'one relay tab named ui relay (no agent) is open'         "$(relay_tabs)" 1
has 'the relay tab runs ui-relay.sh'                          'ui-relay\.sh' "$(cat "$HERDR_STUB/log")"
has 'the relay is pointed at the same UI home'                "$ui" "$(cat "$HERDR_STUB/log")"
ready "$port1" || bad "the server never answered / on $port1: $(docker logs "$name" 2>&1 | tail -n 20)"

# --- the token guards /api/*, never / -----------------------------------------------------------------------------
is '/ is served without the token'                            "$(http "$port1" /)" 200
csp=$(curl -s -m 5 -o /dev/null -D - "http://127.0.0.1:$port1/" | tr -d '\r' | grep -i '^content-security-policy:')
has '/ answers with a Content-Security-Policy of self and data images' \
  "^[Cc]ontent-[Ss]ecurity-[Pp]olicy: default-src 'self'; img-src 'self' data:\$" "$csp"
is 'GET /api/board without the token is 401'                  "$(http "$port1" /api/board)" 401
is 'GET /api/board with a wrong token is 401'                 "$(http "$port1" /api/board -H 'X-Factory-Token: 0123456789abcdef')" 401
is 'GET /api/board with an empty token is 401'                "$(http "$port1" /api/board -H 'X-Factory-Token:')" 401
is 'GET /api/stream without the token is 401'                 "$(http "$port1" /api/stream -m 3)" 401
is 'POST /api/answers without the token is 401'               "$(post "$port1" s1 '{"ask":"q1","text":"Q1 A"}' wrong)" 401
is 'a refused POST writes no answer file'                     "$(answers)" ''
is 'GET /api/board with the token is 200'                     "$(http "$port1" /api/board -H "X-Factory-Token: $token")" 200
has 'the board lists the fixture task'                        'T-001' "$(cat "$tmp/body")"
is 'GET /api/tasks/T-001 with the token is 200'               "$(http "$port1" /api/tasks/T-001 -H "X-Factory-Token: $token")" 200
has 'the task detail carries its body'                        'The fixture sentence of state one\.' "$(cat "$tmp/body")"
has 'the task detail carries html.body, its body rendered'  '"html":\{"body":".*(<|\\u003[Cc])p(>|\\u003[Ee])The fixture sentence of state one\.' "$(cat "$tmp/body")"
is 'GET /api/sessions with the token is 200'                  "$(http "$port1" /api/sessions -H "X-Factory-Token: $token")" 200
view=$(grep -o '"ask":"q1".*' "$tmp/body" | head -c 3000)
has 'an ask of /api/sessions carries its view, a round'       '"view":\{"kind":"round","preamble":"[^"]*","questions":\[\{"q":"Q1","title":"Which fixture\?"' "$view"
has 'the view carries the rendered question text'             '"html":"(<|\\u003[Cc])p(>|\\u003[Ee])the question of the fixture\.' "$view"
has 'the view carries the options with their labels'          '"options":\[\{"key":"A","html":"the first"\},\{"key":"B","html":"the second"\}\]' "$view"
has 'the view carries the recommendation and its key'         '"rec":"(<|\\u003[Cc])strong(>|\\u003[Ee])A(<|\\u003[Cc])/strong(>|\\u003[Ee]): the first is the fixture\.","recKey":"A"' "$view"
has 'the ask keeps its terminal-equal body'                   '"body":"\\n.*Which fixture' "$view"
is 'GET /api/setup with the token is 200'                     "$(http "$port1" /api/setup -H "X-Factory-Token: $token")" 200
has 'the setup carries repos.yml'                             'claude-factory' "$(cat "$tmp/body")"

# --- answers: the next seq per session, written through a rename, byte for byte; refusals write nothing ----------
c1=$(post "$port1" s1 '{"ask":"q1","text":"Q1 A, Q2 \"B\" $HOME\nline 2"}')
c2=$(post "$port1" s1 '{"ask":"q1","text":"Q1 C"}')
has 'the first POST succeeds'                                 '^20[01]$' "$c1"
has 'the second POST succeeds'                                '^20[01]$' "$c2"
is 'two POSTs give answers/1-q1.txt and answers/2-q1.txt'     "$(answers)" '1-q1.txt 2-q1.txt '
want=$(printf 'Q1 A, Q2 "B" $HOME\nline 2x'); got=$(cat "$ui/sessions/s1/answers/1-q1.txt" 2>/dev/null; printf x)
is 'the answer file is the text byte for byte'                "$got" "$want"
is 'the second answer file holds the second text'             "$(cat "$ui/sessions/s1/answers/2-q1.txt" 2>/dev/null)" 'Q1 C'
is 'the answer file belongs to the host uid'                  "$(stat -c %u "$ui/sessions/s1/answers/1-q1.txt" 2>/dev/null)" "$(id -u)"
c3=$(post "$port1" s1 '{"ask":"q3","text":"Q1 D"}')
has 'a POST to another open ask succeeds'                     '^20[01]$' "$c3"
is 'the seq runs per session across asks'                     "$(answers)" '1-q1.txt 2-q1.txt 3-q3.txt '
is 'a POST to an answered ask is 409'                         "$(post "$port1" s1 '{"ask":"q2","text":"Q1 A"}')" 409
is 'a POST to an unknown ask is 404'                          "$(post "$port1" s1 '{"ask":"q9","text":"Q1 A"}')" 404
is 'a POST to an unknown session is 404'                      "$(post "$port1" nosuch '{"ask":"q1","text":"Q1 A"}')" 404
is 'a sid outside [A-Za-z0-9-]+ is 400'                       "$(post "$port1" 's_1' '{"ask":"q1","text":"Q1 A"}')" 400
is 'an ask outside [A-Za-z0-9-]+ is 400'                      "$(post "$port1" s1 '{"ask":"q_1","text":"Q1 A"}')" 400
is 'an ask with a path in it is 400'                          "$(post "$port1" s1 '{"ask":"../q1","text":"Q1 A"}')" 400
is 'refused POSTs write no answer file and leave no temp file' "$(answers)" '1-q1.txt 2-q1.txt 3-q3.txt '

# --- the Host header: 127.0.0.1 or localhost on the UI port, anything else 403 before the token is looked at -----
is 'GET / with Host: evil.test is 403'                        "$(http "$port1" / -H 'Host: evil.test')" 403
is 'GET /api/board with Host: evil.test and the token is 403' "$(http "$port1" /api/board -H 'Host: evil.test' -H "X-Factory-Token: $token")" 403
is 'GET /api/board with Host: evil.test and no token is 403'  "$(http "$port1" /api/board -H 'Host: evil.test')" 403
is 'GET /api/board with Host: evil.test:<port> is 403'        "$(http "$port1" /api/board -H "Host: evil.test:$port1" -H "X-Factory-Token: $token")" 403
is 'GET /api/board with Host: 127.0.0.1 on another port is 403' "$(http "$port1" /api/board -H 'Host: 127.0.0.1:1' -H "X-Factory-Token: $token")" 403
is 'POST /api/answers with Host: evil.test and the token is 403' \
  "$(http "$port1" /api/answers/s1 -X POST -H 'Host: evil.test' -H 'Content-Type: application/json' -H "X-Factory-Token: $token" --data-binary '{"ask":"q1","text":"Q1 A"}')" 403
is 'a POST refused for its Host writes no answer file'        "$(answers)" '1-q1.txt 2-q1.txt 3-q3.txt '
is 'GET /api/board with Host: localhost:<port> is 200'        "$(http "$port1" /api/board -H "Host: localhost:$port1" -H "X-Factory-Token: $token")" 200

# --- sent: only an answer file newer than the ask file counts, and never a `Q<n> redraw` ---------------------------
sent() { # <ask>: the sent field of that ask of s1 in /api/sessions
  http "$port1" /api/sessions -H "X-Factory-Token: $token" >/dev/null
  grep -o "\"ask\":\"$1\"[^}]*" "$tmp/body" | sed -n 's/.*"sent":\(true\|false\).*/\1/p' | head -n1
}
is 'q1, named by an answer file, reads sent'                  "$(sent q1)" true
sleep 1
ask q1 open
is 'q1 rewritten after its answer files reads open again'     "$(sent q1)" false
has 'an answer to the rewritten q1 succeeds'                  '^20[01]$' "$(post "$port1" s1 '{"ask":"q1","text":"Q1 B"}')"
is 'q1 with an answer newer than the rewrite reads sent'      "$(sent q1)" true
is 'the sent q1 carries the text of that answer'              "$(grep -o '"ask":"q1"[^}]*' "$tmp/body" | sed -n 's/.*"answer":"\([^"]*\)".*/\1/p' | head -n1)" 'Q1 B'
printf -- '---\nask: q5\ntask: T-001\nflow: grill\nstep: round 3\nstatus: open\n---\n\nThe visual row of q5.\n' > "$ui/sessions/s1/asks/q5.md"
sleep 1
has 'a redraw of q5 succeeds'                                 '^20[01]$' "$(post "$port1" s1 '{"ask":"q5","text":"Q1 redraw"}')"
is 'q5 with only a redraw answer is not sent'                 "$(sent q5)" false
has 'an answer to q5 after the redraw succeeds'               '^20[01]$' "$(post "$port1" s1 '{"ask":"q5","text":"Q1 A"}')"
is 'q5 with an answer after the redraw reads sent'            "$(sent q5)" true
printf -- '---\nask: q6\ntask: T-001\nflow: grill\nstep: round 4\nstatus: open\n---\n\nThe visual row of q6.\n' > "$ui/sessions/s1/asks/q6.md"
sleep 1
has 'a Q1 more on q6 succeeds'                                '^20[01]$' "$(post "$port1" s1 '{"ask":"q6","text":"Q1 more"}')"
is 'q6 with only a Q1 more answer is not sent'                "$(sent q6)" false

# --- held: the relay's reason reaches an ask whenever it holds any of its answers, a kept-open one included -------
held() { # <ask>: the held field of that ask of s1 in /api/sessions
  http "$port1" /api/sessions -H "X-Factory-Token: $token" >/dev/null
  grep -o "\"ask\":\"$1\"[^}]*" "$tmp/body" | sed -n 's/.*"held":"\([^"]*\)".*/\1/p' | head -n1
}
seq_of() { ls "$ui/sessions/s1/answers" | sed -n "s/^\([0-9]*\)-$1\.txt\$/\1/p" | tail -n1; }
printf -- '---\nask: q7\ntask: T-001\nflow: grill\nstep: round 5\nstatus: open\n---\n\nThe visual row of q7.\n' > "$ui/sessions/s1/asks/q7.md"
sleep 1
has 'a redraw of q7 succeeds'                                 '^20[01]$' "$(post "$port1" s1 '{"ask":"q7","text":"Q1 redraw"}')"
printf '%s gone\n' "$(seq_of q7)" > "$ui/sessions/s1/relay"
is 'q7 whose only answer is a held Q1 redraw reads held gone' "$(held q7)" gone
printf '%s gone\n' "$(seq_of q6)" > "$ui/sessions/s1/relay"
is 'q6 whose only answer is a held Q1 more reads held gone'   "$(held q6)" gone
rm -f "$ui/sessions/s1/relay"

# --- the stream: a change under /state reaches it within 1 s, past a folder it cannot read ------------------------
curl -sN -m 60 -H "X-Factory-Token: $token" "http://127.0.0.1:$port1/api/stream" > "$tmp/stream" 2>/dev/null &
stream=$!
sleep 1.5
arrives() { # <what> <file under the state dir>: its data: line reaches the stream within 1 s of the write
  mkdir -p "$(dirname "$state1/$2")"
  printf 'changed\n' > "$state1/$2"
  t0=$(now)
  while :; do
    if tr -d '\r' < "$tmp/stream" | grep -qxF "data: /state/$2"; then pass "$1 ($(( $(now) - t0 )) ms)"; return; fi
    [ $(( $(now) - t0 )) -lt 1000 ] || break
    sleep 0.05
  done
  bad "$1: no 'data: /state/$2' within 1 s; the stream so far: $(tr -d '\r' < "$tmp/stream" | tail -n 5 | tr '\n' '|')"
}
ctype=$(curl -s -m 2 -o /dev/null -w '%{content_type}' -H "X-Factory-Token: $token" "http://127.0.0.1:$port1/api/stream" 2>/dev/null)
has 'the stream is text/event-stream'                         '^text/event-stream' "$ctype"
# a rebuilt image must reach an open browser without a hard reload: the page and its modules revalidate every time
for f in / /app.js /pipeline.js /page.css; do
  cc=$(curl -s -m 2 -o /dev/null -D - "http://127.0.0.1:$port1$f" 2>/dev/null | tr -d '\r' | sed -n 's/^[Cc]ache-[Cc]ontrol: *//p')
  has "GET $f says Cache-Control: no-cache"                    'no-cache' "$cc"
done
arrives 'a new task file under /state reaches the stream within 1 s' repos/claude-factory/tasks/T-002-new.md
arrives 'a changed task file reaches the stream within 1 s'   repos/claude-factory/tasks/T-001-fixture.md
mkdir -p "$state1/locked-late"; echo secret > "$state1/locked-late/inside.md"; chmod 000 "$state1/locked-late"
if cat "$state1/locked-late/inside.md" >/dev/null 2>&1; then bad 'the locked folders are readable to this uid; the unreadable case proves nothing'
else pass 'the locked folders are unreadable to this uid'; fi
sleep 1
arrives 'with an unreadable folder at start and one made later, the scan still reports a change' after-lock.md
printf -- '---\nask: q4\ntask: T-001\nflow: grill\nstep: round 2\nstatus: open\n---\n\n## Q1\nWhich?\n' > "$ui/sessions/s1/asks/q4.md"
t0=$(now)
while ! tr -d '\r' < "$tmp/stream" | grep -qxF 'data: /ui/sessions/s1/asks/q4.md'; do
  [ $(( $(now) - t0 )) -lt 1000 ] || break
  sleep 0.05
done
if tr -d '\r' < "$tmp/stream" | grep -qxF 'data: /ui/sessions/s1/asks/q4.md'; then pass "a new ask under the UI home reaches the stream within 1 s ($(( $(now) - t0 )) ms)"
else bad "a new ask under the UI home reaches the stream within 1 s: no 'data: /ui/sessions/s1/asks/q4.md'; the stream so far: $(tr -d '\r' < "$tmp/stream" | tail -n 5 | tr '\n' '|')"; fi
is 'the unreadable folders do not stop the container'         "$(running)" true
is 'the container never restarted'                            "$(docker inspect -f '{{.RestartCount}}' "$name" 2>/dev/null)" 0
if kill -0 "$stream" 2>/dev/null; then pass 'the stream stays open'; else bad 'the stream stays open'; fi
kill "$stream" 2>/dev/null; stream=''

# --- a second ui-up.sh reuses the container, the token and the relay tab ------------------------------------------
id1=$(cid)
has 'the first container has an id'                           '^[0-9a-f]{64}$' "$id1"
up --state "$state1"; rc=$?
is 'the second ui-up.sh exits 0'                              "$rc" 0
is 'the second ui-up.sh reuses the container'                 "$(cid)" "$id1"
is 'the token is reused'                                      "$(cat "$ui/token" 2>/dev/null)" "$token"
has 'it prints the same URL'                                  "http://127\.0\.0\.1:$port1/#.*$token" "$(cat "$tmp/up.out")"
is 'no second relay tab is opened'                            "$(relay_tabs) $(creates)" '1 1'

# --- a relay tab still named factory-ui-relay (from an older plugin) is reused and renamed, not doubled -----------
old=$(grep -lxF "$relay_label" "$HERDR_STUB"/tabs/* | head -n1); printf '%s' factory-ui-relay > "$old"
up --state "$state1" >/dev/null 2>&1
is 'the old relay tab is renamed, no tab is opened'           "$(relay_tabs) $(creates)" '1 1'
is 'no tab keeps the old name'                                "$(grep -lx factory-ui-relay "$HERDR_STUB"/tabs/* 2>/dev/null | wc -l | tr -d ' ')" 0

# --- the relay tab is there but no ui-relay.sh runs in it (a herdr restart leaves a bare shell): ui-up.sh finds its
# pane through `pane list`, sees no ui-relay.sh in `pane process-info` and runs the relay there again -------------
relay_tab=$(grep -lxF "$relay_label" "$HERDR_STUB"/tabs/* 2>/dev/null | head -n1)
RELAY_TAB=${relay_tab##*/} RELAY_PROCS="$tmp/relaywrap/procs"
export RELAY_TAB RELAY_PROCS
mkdir -p "$tmp/relaywrap"
cat > "$tmp/relaywrap/herdr" <<'STUB'
#!/bin/sh
case "${1:-} ${2:-}" in
  'pane list')
    printf '%s\n' "$*" >> "$HERDR_STUB/log"
    printf '{"id":"cli:pane:list","result":{"panes":[{"agent_status":"unknown","focused":false,"pane_id":"w9:p1","tab_id":"w9:t1","workspace_id":"w9"},{"agent_status":"unknown","focused":false,"pane_id":"w9:p77","tab_id":"%s","workspace_id":"w9"}],"type":"pane_list"}}\n' "$RELAY_TAB"
    exit 0 ;;
  'pane process-info')
    printf '%s\n' "$*" >> "$HERDR_STUB/log"
    cat "$RELAY_PROCS"
    exit 0 ;;
esac
exec "$(dirname -- "$0")/../path/herdr" "$@"
STUB
chmod +x "$tmp/relaywrap/herdr"
procs() { # <foreground process json list>
  printf '{"id":"cli:pane:process_info","result":{"process_info":{"foreground_process_group_id":1001,"foreground_processes":[%s],"pane_id":"w9:p77","shell_pid":1000},"type":"pane_process_info"}}\n' "$1" > "$RELAY_PROCS"
}
runs() { grep -c '^pane run w9:p77 .*ui-relay\.sh' "$HERDR_STUB/log" | tr -d ' '; }
procs ''
(PATH="$tmp/relaywrap:$PATH"; up --state "$state1"); rc=$?
is 'ui-up.sh over a dead relay exits 0'                       "$rc" 0
has 'it asks herdr what runs in the relay pane'               '^pane process-info --pane w9:p77' "$(cat "$HERDR_STUB/log")"
is 'it runs ui-relay.sh again in the relay pane'              "$(runs)" 1
has 'the restarted relay is pointed at the UI home'           "^pane run w9:p77 .*ui-relay\.sh.*--home.*$ui" "$(cat "$HERDR_STUB/log")"
is 'a relay restart opens no tab'                             "$(relay_tabs) $(creates)" '1 1'
procs "{\"argv\":[\"sh\",\"$bin/ui-relay.sh\",\"--home\",\"$ui\"],\"cmdline\":\"sh $bin/ui-relay.sh --home $ui\",\"name\":\"sh\",\"pid\":1001}"
(PATH="$tmp/relaywrap:$PATH"; up --state "$state1"); rc=$?
is 'ui-up.sh over a live relay exits 0'                       "$rc" 0
is 'a live relay is left alone'                               "$(runs)" 1

# --- a cf.state or cf.version label mismatch recreates the container ----------------------------------------------
up --state "$state2"; rc=$?
is 'ui-up.sh with another state dir exits 0'                  "$rc" 0
isnt 'a cf.state mismatch recreates the container'            "$(cid)" "$id1"
is 'the new container carries the new cf.state'               "$(label cf.state)" "$state2"
has 'the new container mounts the new state dir at /state'    "^/state $state2 false$" "$(mounts)"
ready "$port1" || bad "the recreated server never answered on $port1"
http "$port1" /api/tasks/T-001 -H "X-Factory-Token: $token" >/dev/null
has 'the recreated server reads the new state'                'The fixture sentence of state two\.' "$(cat "$tmp/body")"

docker rm -f "$name" >/dev/null 2>&1
docker run -d --name "$name" --label cf.version=0.0.0-stale --label "cf.state=$state2" alpine:3.22 sleep 600 >/dev/null
id2=$(cid)
has 'the stale container has an id'                           '^[0-9a-f]{64}$' "$id2"
up --state "$state2"; rc=$?
is 'ui-up.sh over a stale cf.version exits 0'                 "$rc" 0
isnt 'a cf.version mismatch recreates the container'          "$(cid)" "$id2"
is 'the new container carries the plugin version'             "$(label cf.version)" "$ver"
ready "$port1" || bad "the server over the stale version never answered on $port1"
is 'the recreated server answers with the token'              "$(http "$port1" /api/board -H "X-Factory-Token: $token")" 200

# --- a taken ui_port falls back to a random free port --------------------------------------------------------------
down
docker run -d --name "$name-hold" -p "127.0.0.1:$port1:80" alpine:3.22 sleep 600 >/dev/null
up --state "$state2"; rc=$?
is 'ui-up.sh with ui_port taken exits 0'                      "$rc" 0
[ "$rc" = 0 ] || sed 's/^/  up: /' "$tmp/up.err" | tail -n 30
port2=$(cat "$ui/port" 2>/dev/null)
has 'the port in use is a number'                             '^[0-9]+$' "$port2"
isnt 'the port in use is not the taken ui_port'               "$port2" "$port1"
has 'the container is published on 127.0.0.1:<that port>'     "127\.0\.0\.1:$port2\$" "$(docker port "$name" 2>/dev/null)"
has 'the printed URL carries that port'                       "http://127\.0\.0\.1:$port2/#" "$(cat "$tmp/up.out")"
ready "$port2" || bad "the server on the fallback port $port2 never answered"
is 'the server answers on that port with the token'           "$(http "$port2" /api/board -H "X-Factory-Token: $token")" 200
has 'factory.yml keeps its ui_port'                           "^ui_port: $port1\$" "$(cat "$state2/factory.yml")"
docker rm -f "$name-hold" >/dev/null 2>&1

# --- two sessions racing ui-up.sh end with one container and one relay tab; a slow tab list makes the two overlap
# between looking for the tab and creating it, so a relay tab opened without a lock shows up as a second tab ------
down
HERDR_STUB_LIST_DELAY=3 HERDR_ENV=1 timeout 15m sh "$bin/ui-up.sh" --state "$state2" > "$tmp/race1" 2>&1 & r1=$!
HERDR_STUB_LIST_DELAY=3 HERDR_ENV=1 timeout 15m sh "$bin/ui-up.sh" --state "$state2" > "$tmp/race2" 2>&1 & r2=$!
wait "$r1"; rc1=$?
wait "$r2"; rc2=$?
is 'two racing ui-up.sh both exit 0'                          "$rc1 $rc2" '0 0'
is 'the race leaves the container running'                    "$(running)" true
is 'the race leaves one relay tab'                            "$(relay_tabs)" 1

# --- the org routes over a state built with map.sh, state-archive.sh, capacity.sh and pass-stamp.sh, a doctor.json
# in the shape factory-doctor.sh --json writes, and the CEO registered through ui-session.sh ----------------------
j() { # <js expression over b, the last body>: a string as it is, anything else as JSON
  node -e 'const b=JSON.parse(require("fs").readFileSync(process.argv[2],"utf8"));const v=eval(process.argv[1]);process.stdout.write(typeof v==="string"?v:JSON.stringify(v))' \
    "$1" "$tmp/body" 2>&1
}
state3="$tmp/state3"
if org_state "$state3" > "$tmp/org.out" 2>&1; then pass 'the org state is built with the real scripts'
else bad 'the org state is built with the real scripts'; tail -n 20 "$tmp/org.out" | sed 's/^/  org: /'; fi
sh "$bin/ui-session.sh" --session s-ceo --pane w1:p9 --flow ceo --task ceo || bad 'ui-session.sh registers the CEO'
mkdir -p "$ui/setup"
printf '{\n  "at": "2026-09-25T10:00:00Z",\n  "root": "%s",\n  "steps": [\n    {"id": "git", "state": "done", "detail": "git 2.51", "fix": ""},\n    {"id": "herdr", "state": "missing", "detail": "herdr is not on PATH", "fix": "install herdr"},\n    {"id": "repo:ecs:alias", "state": "failing", "detail": "no alias", "fix": "factory-add-repo.sh ecs --alias ECS"}\n  ]\n}\n' \
  "$tmp" > "$ui/setup/doctor.json"
# the add-repo status files of factory-add-repo.sh (C3) and two onboarding reports (C5), written here as the contracts say
mkdir -p "$ui/setup/add-repo"
printf '{"at":"2026-09-25T09:00:00Z","key":"gone","url":"https://example.test/g/gone.git","path":"/c/gone","state":"failed","detail":"cannot reach https://example.test/g/gone.git: 404"}\n' \
  > "$ui/setup/add-repo/gone.json"
printf '{"at":"2026-09-25T11:00:00Z","key":"fresh","url":"https://example.test/g/fresh.git","path":"/c/fresh","state":"pending","detail":"/c/fresh"}\n' \
  > "$ui/setup/add-repo/fresh.json"
printf '{"key":"half","state":"cloning"}\n' > "$ui/setup/add-repo/half.json"
printf '{"key":"broken",' > "$ui/setup/add-repo/broken.json"
printf -- '---\nrepo: ecs\nstatus: done\nat: 2026-09-25T12:00:00Z\nsession: 5f1c\nstack: dotnet\n---\n# Onboarding of ecs\n\n%s\n\n## Summary\nA **dotnet** service.\n\n## Checks\n%s\n%s\nnot a check line\n\n## Proposals\n%s\n' \
  'An onboarding session reports and proposes; it changes nothing. Send a proposal as a request to have a lead do it.' \
  '- done registration: ecs is in repos.yml' \
  '- failing ci: <script>x</script> never tests Fix: add a test job' \
  '- P1 ci: run the tests in "CI"' > "$state3/repos/ecs/onboarding.md"
printf -- '---\nrepo: claude-factory\nstatus: running\nat: 2026-09-25T12:30:00Z\n---\n# Onboarding of claude-factory\n' \
  > "$state3/repos/claude-factory/onboarding.md"
git -C "$state3" add repos/ecs/onboarding.md repos/claude-factory/onboarding.md && git -C "$state3" commit -qm 'fixture: onboarding reports' \
  || bad 'the onboarding reports are committed'
leases_before=$(find "$state3/.capacity" -type f | sort)
up --state "$state3"; rc=$?
is 'ui-up.sh over the org state exits 0'                      "$rc" 0
port3=$(cat "$ui/port" 2>/dev/null)
ready "$port3" || bad "the server over the org state never answered on $port3"
api() { http "$port3" "$1" -H "X-Factory-Token: $token"; }

is 'GET /api/board over the org state is 200'                 "$(api /api/board)" 200
is 'a board row has the fields of the contract, in order'     "$(j 'Object.keys(b[0]).join(",")')" 'id,status,archetype,tier,repo,owner,goal,request,priority,steps'
is 'the board lists the live tasks only'                      "$(j 'b.map(r=>r.id).sort().join(" ")')" 'T-CF-1 T-ECS-1 T-ECS-1-01 T-ECS-1-02'
is 'a parent row carries its request, priority and repo'      "$(j 'const r=b.find(r=>r.id==="T-ECS-1");[r.request,r.priority,r.repo].join(" ")')" 'R-20260925-1 P1 ecs'
is 'a block without a priority shows its parent'"'"'s'            "$(j 'b.find(r=>r.id==="T-ECS-1-01").priority')" P1
is 'a block with a priority shows its own'                    "$(j 'b.find(r=>r.id==="T-ECS-1-02").priority')" P3
is 'a parent without a priority is P2'                        "$(j 'b.find(r=>r.id==="T-CF-1").priority')" P2

is 'GET /api/requests is 200'                                 "$(api /api/requests)" 200
is 'a request row has the fields of the contract'             "$(j 'Object.keys(b[0]).join(",")')" 'id,status,destination,priority,parents,archived'
is 'requests list newest first, the archived one included'    "$(j 'b.map(r=>r.id).join(" ")')" 'R-20260925-1 R-20260920-1'
is 'the live request reads its map'                           "$(j 'const r=b[0];[r.status,r.destination,r.priority,r.parents.join("+"),r.archived].join("|")')" \
  'grilling|Invoices reach the ledger every night.|P1|T-CF-1+T-ECS-1|false'
is 'the archived request reads from requests/archive'         "$(j 'const r=b[1];[r.status,r.priority,r.parents.join("+"),r.archived].join("|")')" 'done|P0|T-CF-2|true'

is 'GET /api/requests/R-20260925-1 is 200'                    "$(api /api/requests/R-20260925-1)" 200
is 'a request has the fields of the contract, in order'       "$(j 'Object.keys(b).join(",")')" \
  'id,status,destination,notes,terms,archived,decisions,outOfScope,fog,tickets,frontier,parents,html'
is 'its decisions are the resolved tickets'                   "$(j 'b.decisions')" '[{"title":"Which ledger API","file":"01-which-ledger-api.md","gist":"The REST API, v2."}]'
is 'its out of scope is the dropped ticket'                   "$(j 'b.outOfScope')" '[{"title":"Get ledger access","file":"03-get-ledger-access.md","gist":"Access is the other team'"'"'s rollout."}]'
is 'its fog, notes and terms are the sections'                "$(j '[b.fog,b.notes,b.terms].join("|")')" \
  'How the two exports are ordered once both run.|Both repos post through the REST API.|- **Ledger**: the accounting system of record. Avoid: books'
is 'a ticket has the fields of the contract, in order'        "$(j 'Object.keys(b.tickets[0]).join(",")')" 'nn,title,type,status,blockedBy,repo,claimedBy,question,answer'
is 'the tickets come in number order with their status'       "$(j 'b.tickets.map(t=>t.nn+":"+t.status).join(" ")')" '01:resolved 02:open 03:dropped 04:open 05:claimed'
is 'ticket 02 reads its type, blockers, repo and question'    "$(j 'const t=b.tickets[1];[t.type,t.blockedBy.join("+"),t.repo,t.claimedBy,t.question,t.answer].join("|")')" \
  'grilling|01|ecs||Where does the export keep its cursor?|'
is 'ticket 01 reads its answer and who claimed it'            "$(j 'const t=b.tickets[0];[t.claimedBy,t.answer].join("|")')" \
  's-chart|The REST API, v2.
The report is research/ledger.md.'
is 'ticket 05 is claimed'                                     "$(j 'b.tickets[4].claimedBy')" chart_ecs-12
is 'the frontier is what map.sh frontier prints'              "$(j 'b.frontier.join(" ")')" \
  "$(sh "$bin/map.sh" frontier R-20260925-1 --state "$state3" | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
is 'the frontier is ticket 02'                                "$(j 'b.frontier.join(" ")')" 02
is 'a parent has the fields of the contract, in order'        "$(j 'Object.keys(b.parents[0]).join(",")')" 'id,repo,priority,status,goal,acceptance,blocks'
is 'the parents are the tasks of the request'                 "$(j 'b.parents.map(p=>p.id).join(" ")')" 'T-CF-1 T-ECS-1'
is 'a parent carries its goal and acceptance'                 "$(j 'const p=b.parents[1];[p.repo,p.priority,p.status,p.goal,p.acceptance].join("|")')" \
  'ecs|P1|in_progress|feat(ecs): export invoices to the ledger|`make test` passes.'
is 'a block has the fields of the contract, in order'         "$(j 'Object.keys(b.parents[1].blocks[0]).join(",")')" 'id,status,goal,acceptance'
is 'the blocks carry their acceptance, empty when none'       "$(j 'b.parents[1].blocks.map(k=>k.id+":"+k.acceptance).join("|")')" \
  'T-ECS-1-01:The cursor test passes.|T-ECS-1-02:'
is 'a parent without blocks has none'                         "$(j 'b.parents[0].blocks')" '[]'
is 'GET /api/requests/R-20260920-1 (archived) is 200'         "$(api /api/requests/R-20260920-1)" 200
is 'the archived request shows its archived parent and block' "$(j '[b.archived,b.parents[0].id,b.parents[0].acceptance,b.parents[0].blocks.map(k=>k.id).join("+")].join("|")')" \
  'true|T-CF-2|It was done.|T-CF-2-01'
is 'an unknown request is 404'                                "$(api /api/requests/R-20990101-1)" 404
is 'a malformed request id is 404'                            "$(api /api/requests/nonsense)" 404

is 'GET /api/tasks/T-CF-2 (archived) is 200'                  "$(api /api/tasks/T-CF-2)" 200
is 'the archived task carries its request and priority'       "$(j '[b.task.status,b.request,b.priority,b.task.request,b.task.priority].join(" ")')" 'done R-20260920-1 P0 R-20260920-1 P0'
is 'the archived task carries its archived block'             "$(j 'b.blocks.map(k=>k.id).join(" ")')" T-CF-2-01
has 'the archived task carries its archived progress'         'The archived progress of T-CF-2\.' "$(j 'b.progress')"
tl=$(j 'b.timeline.join("\n")')
has 'its timeline follows the move: the archive commit'       'chore\(T-CF-2\): archive' "$tl"
has 'its timeline follows the move: the commit before it'     'task: T-CF-2 opened' "$tl"
is 'GET /api/tasks/T-ECS-1-01 is 200'                         "$(api /api/tasks/T-ECS-1-01)" 200
is 'a block detail shows its parent'"'"'s priority'               "$(j 'b.priority')" P1

is 'GET /api/org is 200'                                      "$(api /api/org)" 200
is 'the org has the fields of the contract'                   "$(j 'Object.keys(b).join(",")')" 'capacity,leases,leads,ceo'
is 'the sessions slot counts the session leases'              "$(j 'b.capacity.sessions')" '{"used":1,"cap":10}'
is 'the roles are factory.yml in order, then the uncapped'    "$(j 'b.capacity.roles')" \
  '[{"role":"repo-lead","used":1,"cap":3},{"role":"scout","used":1,"cap":8},{"role":"implementer","used":1,"cap":4},{"role":"architecture-auditor","used":1,"cap":null}]'
has 'a lease reads its file'                                  '^\{"role":"repo-lead","key":"T-ECS-1","session":"","unit":"T-ECS-1-lead","at":"[0-9]+"\}$' \
  "$(j 'JSON.stringify(b.leases.find(l=>l.role==="repo-lead"))')"
is 'a subagent lease carries its session'                     "$(j 'const l=b.leases.find(l=>l.role==="scout");l.key+" "+l.session')" 'agent-1 sess-1'
is 'every lease is listed'                                    "$(j 'b.leases.length')" 5
is 'one lead per repo-lead lease, with its task'              "$(j 'b.leads')" \
  '[{"task":"T-ECS-1","repo":"ecs","request":"R-20260925-1","priority":"P1","status":"in_progress","unit":"T-ECS-1-lead"}]'
is 'the CEO is the session of flow ceo'                       "$(j 'b.ceo')" '{"sid":"s-ceo","pane":"w1:p9"}'
is 'reading the org leaves every lease in place'              "$(find "$state3/.capacity" -type f | sort)" "$leases_before"
is 'the org counts what capacity.sh counts'                   "$(j 'b.capacity.roles[0].used+"/"+b.capacity.roles[0].cap')" "$(sh "$bin/capacity.sh" count repo-lead --state "$state3")"

is 'GET /api/setup over the org state is 200'                 "$(api /api/setup)" 200
is 'setup keeps its fields and adds the contract'"'"'s'           "$(j 'Object.keys(b).join(",")')" 'root,reposYml,toolsets,doctorNotice,steps,doctorAt,capacity,passes,addRepos,onboarding'
is 'an add-repo entry has the fields of C6, in order'         "$(j 'Object.keys(b.addRepos[0]).join(",")')" 'key,url,path,state,detail,at'
is 'addRepos come newest first, a broken file skipped'        "$(j 'b.addRepos.map(a=>a.key+":"+a.state).join(" ")')" 'fresh:pending gone:failed half:cloning'
is 'an add-repo entry reads its file'                         "$(j 'b.addRepos[1]')" \
  '{"key":"gone","url":"https://example.test/g/gone.git","path":"/c/gone","state":"failed","detail":"cannot reach https://example.test/g/gone.git: 404","at":"2026-09-25T09:00:00Z"}'
is 'a missing field of an add-repo file reads empty'          "$(j 'b.addRepos[2]')" '{"key":"half","url":"","path":"","state":"cloning","detail":"","at":""}'
is 'an onboarding report has the fields of C6, in order'      "$(j 'Object.keys(b.onboarding[0]).join(",")')" 'repo,status,at,stack,summaryHtml,checks,proposals'
is 'the reports come in repo key order'                       "$(j 'b.onboarding.map(o=>o.repo+":"+o.status).join(" ")')" 'claude-factory:running ecs:done'
is 'a report reads its frontmatter'                           "$(j 'const o=b.onboarding[1];[o.at,o.stack].join(" ")')" '2026-09-25T12:00:00Z dotnet'
is 'the summary is rendered markdown'                         "$(j 'b.onboarding[1].summaryHtml.trim()')" '<p>A <strong>dotnet</strong> service.</p>'
is 'the checks are the lines the C5 regex matches, the fix split off, as text' "$(j 'b.onboarding[1].checks')" \
  '[{"state":"done","id":"registration","detail":"ecs is in repos.yml","fix":""},{"state":"failing","id":"ci","detail":"<script>x</script> never tests","fix":"add a test job"}]'
is 'the proposals are the lines the C5 regex matches'         "$(j 'b.onboarding[1].proposals')" '[{"id":"P1","area":"ci","text":"run the tests in \"CI\""}]'
is 'a report without sections has empty lists and no summary' "$(j 'const o=b.onboarding[0];[o.summaryHtml,o.checks.length,o.proposals.length,o.stack].join("|")')" '|0|0|'
is 'setup carries the doctor steps'                          "$(j 'b.steps.map(s=>s.id+":"+s.state).join(" ")')" 'git:done herdr:missing repo:ecs:alias:failing'
is 'a step has id, state, detail and fix'                     "$(j 'b.steps[1]')" '{"id":"herdr","state":"missing","detail":"herdr is not on PATH","fix":"install herdr"}'
is 'setup carries the doctor date'                            "$(j 'b.doctorAt')" '2026-09-25T10:00:00Z'
is 'setup carries the capacity of the org'                    "$(j 'b.capacity.sessions.used+"/"+b.capacity.roles.length')" 1/4
is 'setup lists every passes.yml by scope'                    "$(j 'b.passes.map(p=>p.scope).join(" ")')" 'global repo:ecs repo-agent:ecs/implementer'
has 'a stamped pass reads its stamp, the other never'         '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z never$' "$(j 'b.passes[0].daily+" "+b.passes[0].weekly')"
has 'a weekly stamp reads as written'                         '^never [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$(j 'b.passes[1].daily+" "+b.passes[1].weekly')"
is 'the stamp is the one passes.yml holds'                    "$(j 'b.passes[0].daily')" "$(sed -n 's/^daily: //p' "$state3/memory/global/passes.yml")"
is 'a scope with nothing to judge is due for no pass'          "$(j 'b.passes.map(p=>p.due).join(" ")')" 'none none none'

# --- a scope whose first pass is due has a row before it has a passes.yml, due as pass-stamp.sh --due says ---------
mkdir -p "$state3/repos/ecs/memory/drafts" "$state3/repos/ecs/agents/scout/memory/proposals" "$state3/agents/writer/memory/proposals"
printf 'A draft.\n' > "$state3/repos/ecs/memory/drafts/1-cursor.md"
printf 'A proposal.\nReplaces: the old grep note\n' > "$state3/repos/ecs/agents/scout/memory/proposals/1-grep.md"
printf 'A proposal.\n' > "$state3/agents/writer/memory/proposals/1-voice.md"
api /api/setup >/dev/null
is 'the scopes with work join the scopes with a passes.yml'   "$(j 'b.passes.map(p=>p.scope).join(" ")')" \
  'global repo:ecs agent:writer repo-agent:ecs/implementer repo-agent:ecs/scout'
is 'a scope without a passes.yml reads never twice'           "$(j 'b.passes.filter(p=>/writer|scout/.test(p.scope)).map(p=>p.daily+"/"+p.weekly).join(" ")')" 'never/never never/never'
due_rows=$(j 'b.passes.flatMap(p=>(p.due==="both"?["daily","weekly"]:p.due==="none"?[]:[p.due]).map(k=>p.scope+" "+k)).sort().join("\n")')
due_script=$({ sh "$bin/pass-stamp.sh" --due daily --state "$state3"; sh "$bin/pass-stamp.sh" --due weekly --state "$state3"; } | cut -d' ' -f1,2 | LC_ALL=C sort)
is 'every row due is a pass pass-stamp.sh --due lists'        "$(printf '%s\n' "$due_rows" | LC_ALL=C sort)" "$due_script"
is 'the due of each scope'                                    "$(j 'b.passes.map(p=>p.scope+"="+p.due).join(" ")')" \
  'global=none repo:ecs=daily agent:writer=both repo-agent:ecs/implementer=none repo-agent:ecs/scout=both'
rm -rf "$state3/repos/ecs/memory/drafts" "$state3/repos/ecs/agents/scout" "$state3/agents/writer"

# --- the Memory tab's start button: an empty ask is a free message to the CEO, typed by the relay like an answer ----
cmsg() { ls -A "$ui/sessions/s-ceo/answers" 2>/dev/null | tr '\n' ' '; }
is 'an empty ask to the CEO is 201'                           "$(post "$port3" s-ceo '{"ask":"","text":"start the daily pass for global"}')" 201
is 'it is written as the next answer under the ask id msg'    "$(cmsg)" '1-msg.txt '
is 'the message file is the text'                             "$(cat "$ui/sessions/s-ceo/answers/1-msg.txt" 2>/dev/null)" 'start the daily pass for global'
is 'an empty ask with no text is 400'                         "$(post "$port3" s-ceo '{"ask":"","text":""}')" 400
is 'an empty ask to an unknown session is 404'                "$(post "$port3" nosuch '{"ask":"","text":"start the daily pass for global"}')" 404
is 'refused free messages write nothing'                      "$(cmsg)" '1-msg.txt '
mkdir -p "$tmp/ceohome/sessions" "$tmp/ceowrap"
cp -r "$ui/sessions/s-ceo" "$tmp/ceohome/sessions/"
cat > "$tmp/ceowrap/herdr" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_STUB/log"
case "${1:-} ${2:-}" in
  'agent get') printf '{"id":"cli:agent:get","result":{"agent":{"agent":"claude","agent_session":{"source":"hook","value":"s-ceo"},"agent_status":"idle","pane_id":"w1:p9","state_change_seq":7},"type":"agent_info"}}\n' ;;
  *) echo '{"id":"cli:stub","result":{"type":"ok"}}' ;;
esac
STUB
chmod +x "$tmp/ceowrap/herdr"
PATH="$tmp/ceowrap:$PATH" timeout 60 sh "$bin/ui-relay.sh" --home "$tmp/ceohome" --settle 0 --once > "$tmp/relay.out" 2>&1
has 'the relay types the free message into the CEO pane'     '^agent prompt w1:p9 start the daily pass for global' "$(cat "$HERDR_STUB/log")"
is 'the relay records it delivered'                           "$(cat "$tmp/ceohome/sessions/s-ceo/delivered" 2>/dev/null)" 1

# --- the scan: one per mount for every client, a commit is one stamp on .git/logs/HEAD, .capacity is never read ---
curl -sN -m 30 -H "X-Factory-Token: $token" "http://127.0.0.1:$port3/api/stream" > "$tmp/stream3" 2>/dev/null &
stream=$!
curl -sN -m 30 -H "X-Factory-Token: $token" "http://127.0.0.1:$port3/api/stream" > "$tmp/stream4" 2>/dev/null &
stream4=$!
sleep 1.5
printf 'Both repos post through the REST API, nightly.\n' | sh "$bin/map.sh" set R-20260925-1 notes --state "$state3" >/dev/null \
  || bad 'map.sh set notes commits'
sh "$bin/capacity.sh" acquire scout agent-2 --session sess-2 --state "$state3" || bad 'capacity.sh acquires a second scout'
printf 'plain\n' > "$state3/plain.md"
t0=$(now)
until tr -d '\r' < "$tmp/stream3" | grep -qxF 'data: /state/plain.md' && tr -d '\r' < "$tmp/stream4" | grep -qxF 'data: /state/plain.md' \
  && tr -d '\r' < "$tmp/stream3" | grep -qxF 'data: /state/.git/logs/HEAD'; do
  [ $(( $(now) - t0 )) -lt 3000 ] || break
  sleep 0.05
done
s3=$(tr -d '\r' < "$tmp/stream3")
has 'a new file reaches the first client'                     '^data: /state/plain\.md$' "$s3"
has 'the same change reaches a second client'                 '^data: /state/plain\.md$' "$(tr -d '\r' < "$tmp/stream4")"
has 'a commit reaches the stream as .git/logs/HEAD'           '^data: /state/\.git/logs/HEAD$' "$s3"
has 'the committed map reaches the stream'                    '^data: /state/requests/R-20260925-1/map\.md$' "$s3"
hasnt 'nothing else under .git reaches the stream'            '^data: /state/\.git/(objects|refs|index|COMMIT_EDITMSG|logs/refs)' "$s3"
hasnt 'nothing under .capacity reaches the stream'            '/\.capacity/' "$s3"
kill "$stream" "$stream4" 2>/dev/null; stream=''
is 'a new lease shows in the org at once'                     "$(api /api/org >/dev/null; j 'b.capacity.roles.find(r=>r.role==="scout").used')" 2

# --- ui-down.sh removes the container and closes the relay tab; with neither it does nothing ----------------------
down; rc=$?
is 'ui-down.sh exits 0'                                       "$rc" 0
is 'ui-down.sh removes the container'                         "$(running)" absent
is 'ui-down.sh closes the relay tab'                          "$(relay_tabs)" 0
n=$(closes)
down; rc=$?
is 'ui-down.sh with nothing running exits 0'                  "$rc" 0
is 'ui-down.sh with nothing running closes nothing'           "$(closes)" "$n"

# --- the server's own tests in the SDK image, as the host uid so an unreadable folder is unreadable there too ------
timeout 15m docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 \
  -v "$repo:/src:ro" mcr.microsoft.com/dotnet/sdk:10.0-alpine sh -c \
  'mkdir -p /tmp/w/tests && cp -r /src/ui /tmp/w/ui && cp -r /src/tests/ui /tmp/w/tests/ui && cd /tmp/w && timeout 900 dotnet test tests/ui/FactoryUi.Tests.csproj --logger "console;verbosity=normal"' \
  > "$tmp/dotnet.out" 2>&1; rc=$?
is 'the SDK-image dotnet test passes'                         "$rc" 0
[ "$rc" = 0 ] || tail -n 40 "$tmp/dotnet.out" | sed 's/^/  dotnet: /'
has 'the SDK-image dotnet test ran tests'                     'Total tests: +[1-9]' "$(cat "$tmp/dotnet.out")"
has 'the SDK-image dotnet test ran AskParserTests'           'Passed AskParserTests\.' "$(cat "$tmp/dotnet.out")"
for c in RequestMapTests OrgTests StateReaderTests UiHomeTests MountScannerTests; do
  has "the SDK-image dotnet test ran $c"                      "Passed $c\\." "$(cat "$tmp/dotnet.out")"
done

exit $fail
