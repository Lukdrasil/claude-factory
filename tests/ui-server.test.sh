#!/bin/sh
# The Factory UI server in its container, driven through ui-up.sh and ui-down.sh over a fixture state repo, a
# throwaway UI home, an ephemeral host port and a stub `herdr` on PATH: the token, the answer files, the change
# stream, the scan past an unreadable folder, container reuse and recreation on a label mismatch, the port
# fallback, the relay tab, the exit codes, and the server's own xunit tests in the SDK image. The container is
# named from FACTORY_UI_CONTAINER so a real claude-factory-ui on this machine is never touched.
# Without Docker it prints `SKIP ui-server: no docker` and exits 0.
set -u
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$repo/bin"

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-server: no docker'
  exit 0
fi

tmp=$(mktemp -d)
name="cf-ui-test-$$"
ver=$(sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$repo/.claude-plugin/plugin.json" | head -n1)
image="claude-factory-ui:$ver"
stream=''
cleanup() {
  [ -z "$stream" ] || kill "$stream" 2>/dev/null
  FACTORY_UI_CONTAINER=$name HERDR_ENV=1 timeout 120 sh "$bin/ui-down.sh" >/dev/null 2>&1
  docker rm -f "$name" "$name-hold" "$name-free" >/dev/null 2>&1
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

. "$repo/tests/ui-fixture.sh"

relay_tabs() { grep -lx 'factory-ui-relay' "$HERDR_STUB"/tabs/* 2>/dev/null | wc -l | tr -d ' '; }
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
if docker image inspect "$image" >/dev/null 2>&1; then
  docker image rm "$image" >/dev/null 2>&1 || echo "NOTE $image is in use by a container; it is reused, not rebuilt"
fi
up --state "$state1"; rc=$?
is 'the first ui-up.sh exits 0'                               "$rc" 0
[ "$rc" = 0 ] || sed 's/^/  up: /' "$tmp/up.err" | tail -n 30
is "the image $image exists"                                  "$(docker image inspect -f ok "$image" 2>/dev/null)" ok
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
is 'one relay tab named factory-ui-relay is open'             "$(relay_tabs)" 1
has 'the relay tab runs ui-relay.sh'                          'ui-relay\.sh' "$(cat "$HERDR_STUB/log")"
has 'the relay is pointed at the same UI home'                "$ui" "$(cat "$HERDR_STUB/log")"
ready "$port1" || bad "the server never answered / on $port1: $(docker logs "$name" 2>&1 | tail -n 20)"

# --- the token guards /api/*, never / -----------------------------------------------------------------------------
is '/ is served without the token'                            "$(http "$port1" /)" 200
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
hasnt 'the task detail carries no rendered html field'      '"html":' "$(cat "$tmp/body")"
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
  'mkdir -p /tmp/w/tests && cp -r /src/ui /tmp/w/ui && cp -r /src/tests/ui /tmp/w/tests/ui && cd /tmp/w && timeout 900 dotnet test tests/ui/FactoryUi.Tests.csproj' \
  > "$tmp/dotnet.out" 2>&1; rc=$?
is 'the SDK-image dotnet test passes'                         "$rc" 0
[ "$rc" = 0 ] || tail -n 40 "$tmp/dotnet.out" | sed 's/^/  dotnet: /'
has 'the SDK-image dotnet test ran tests'                     'Total: +[1-9]' "$(cat "$tmp/dotnet.out")"

exit $fail
