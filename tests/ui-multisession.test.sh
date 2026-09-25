#!/bin/sh
# herd and parallel sessions: the fixture of tests/ui-fixture.sh, the stub `herdr` of tests/ui-relay-stub.sh for the
# relay and the Playwright harness of the fixture's `browser`. Two fake sessions on two tasks take 100 interleaved
# answers through POST /api/answers and one relay pass (QS-07). Four worker sessions of the herd T-030 register
# through session-start.sh from their block worktrees, the way a herdr tab does, one pane each working, idle, at a
# dialog and gone; one relay pass later tests/ui-multisession.test.js reads the wave of T-030 in the browser.
# The server runs from an image built from this checkout's ui/ under a tag of its content. The browser checks print
# their own PASS and FAIL lines. Without Docker it prints `SKIP ui-multisession: no docker`.
set -u
unset FACTORY_UI_HOME FACTORY_UI_CONTAINER WORK_DIR
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-multisession: no docker'
  exit 0
fi

tmp=$(mktemp -d)
name="cf-ui-ms-$$"
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
. "$repo/tests/ui-relay-stub.sh"
relay_stub "$tmp/relaypath"
mkdir -p "$HERDR_STUB/panes" "$HERDR_STUB/texts"
echo 0 > "$HERDR_STUB/calls"; echo 0 > "$HERDR_STUB/count"; : > "$HERDR_STUB/prompts"
relay() { PATH="$tmp/relaypath:$PATH" timeout 600 sh "$bin/ui-relay.sh" --home "$ui" --settle 0 --once > "$tmp/relay.out" 2>&1; }

st="$state1/repos/claude-factory"
task() { # <id> <status> [frontmatter line ...], stdin: the body
  id=$1 status=$2
  shift 2
  {
    printf -- '---\nid: %s\nrepo: claude-factory\nstatus: %s\ntier: yellow\narchetype: feature\ncomplexity: medium\n' "$id" "$status"
    for line in "$@"; do printf '%s\n' "$line"; done
    printf -- '---\n\n'
    cat
  } > "$st/tasks/$id-fixture.md"
}
goal() { printf '# Goal\n%s\n' "$1"; }
round() { # <sid> <ask> <task>: one open grill round
  printf -- '---\nask: %s\ntask: %s\nflow: %s\nstep: %s\nstatus: open\n---\n\n%s\n' "$2" "$3" feature 'Step 3 of 7' \
    "❓ **Q1** - **Which fixture store for $3?**: the question of the fixture.
  **A** the flat file
  **B** the table

➡️ **A**: the flat file is the fixture." | sh "$bin/ui-ask.sh" --session "$1" >/dev/null || bad "ui-ask.sh --session $1 ($2)"
}

# --- the herd T-030: four blocks in wave 1, each claimed by its worker session, the monitor on the parent ---------
goal 'feat(fx): the herd fixture task' | task T-030 in_progress 'branch: feat/T-030-fx'
goal 'feat(fx): the working block of T-030' | task T-030-01 in_progress 'phase: implement' 'owner: factory@fixture:sw1' 'mr_url: https://example.invalid/mr/301'
goal 'feat(fx): the idle block of T-030' | task T-030-02 in_progress 'phase: tests' 'owner: factory@fixture:sw2' 'mr_url: null'
goal 'feat(fx): the block of T-030 at a dialog' | task T-030-03 in_progress 'phase: implement' 'owner: factory@fixture:sw3'
goal 'feat(fx): the block of T-030 whose worker died' | task T-030-04 in_progress 'phase: tests' 'owner: factory@fixture:sw4'
mkdir -p "$st/progress"
printf '# T-030\n\n## Wave plan\n- wave 1: T-030-01, T-030-02, T-030-03, T-030-04\n' > "$st/progress/T-030.md"
sh "$bin/ui-session.sh" --session sm --pane w3:p0 --flow herd --task T-030 --step 'Step 11 of 16: wave 1 of T-030' \
  || bad 'ui-session.sh --session sm'

# the workers register through session-start.sh from their block worktrees of a registered clone, as a herdr tab does
wd="$tmp/wd"
mkdir -p "$wd/state" "$tmp/home"
git init -q "$tmp/prod"
git -C "$tmp/prod" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
printf 'claude-factory: {url: "https://forge.test/acme/claude-factory.git", default_branch: main, path: "%s"}\n' "$tmp/prod" \
  > "$wd/state/repos.yml"
printf 'spawn: herdr\nui: docker\n' > "$wd/state/factory.yml"
for w in 1 2 3 4; do
  git -C "$tmp/prod" worktree add -q -b "block/T-030-0$w" "$tmp/T-030-0$w" 2>/dev/null || bad "worktree T-030-0$w"
  printf '{"session_id":"sw%s","cwd":"%s","hook_event_name":"SessionStart"}' "$w" "$tmp/T-030-0$w" \
    | env HOME="$tmp/home" WORK_DIR="$wd" HERDR_ENV=1 HERDR_PANE_ID="w3:p$w" sh "$bin/session-start.sh" >/dev/null 2>&1
  [ -f "$ui/sessions/sw$w/session.md" ] && pass "worker sw$w registers through session-start.sh" \
    || bad "worker sw$w registers through session-start.sh"
done
round sw2 wq1 T-030-02
pane w3:p0 idle sm
pane w3:p1 working sw1
pane w3:p2 idle sw2
pane w3:p3 blocked sw3

# --- the server --------------------------------------------------------------------------------------------------
up --state "$state1"; rc=$?
is 'ui-up.sh exits 0'                                         "$rc" 0
[ "$rc" = 0 ] || { sed 's/^/  up: /' "$tmp/up.err" | tail -n 30; exit 1; }
is 'the server runs the image of this checkout'               "$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)" "$image"
port=$(cat "$ui/port" 2>/dev/null)
token=$(cat "$ui/token" 2>/dev/null)
ready "$port" || { bad "the server never answered / on $port: $(docker logs "$name" 2>&1 | tail -n 20)"; exit 1; }

# --- QS-07 through the server: two sessions on two tasks, 100 interleaved answers, 0 cross-session turns ---------
sh "$bin/ui-session.sh" --session sa --pane w4:pa --flow solve --task T-031 --step 'Step 4 of 16: grill T-031' || bad 'ui-session.sh sa'
sh "$bin/ui-session.sh" --session sb --pane w4:pb --flow solve --task T-032 --step 'Step 4 of 16: grill T-032' || bad 'ui-session.sh sb'
round sa iq T-031
round sb iq T-032
pane w4:pa idle sa
pane w4:pb idle sb
codes=''
i=1
while [ $i -le 50 ]; do
  for s in a b; do
    code=$(http "$port" "/api/answers/s$s" -X POST -H "X-Factory-Token: $token" -H 'Content-Type: application/json' \
      -d "{\"ask\":\"iq\",\"text\":\"$(printf '%s' "$s" | tr ab AB) $i\"}")
    [ "$code" = 201 ] || codes="$codes s$s#$i:$code"
  done
  i=$((i + 1))
done
is 'QS-07: the 100 interleaved POSTs all answer 201'         "${codes:-none}" none
relay
is 'the relay pass exits 0'                                   "$?" 0
k=1 cross=0 ain='' bin_=''
while [ $k -le "$(cat "$HERDR_STUB/count")" ]; do
  p=$(awk -v k=$k '$1 == k { print $3 }' "$HERDR_STUB/prompts"); t=$(cat "$HERDR_STUB/texts/$k")
  case "$p:$t" in w4:pa:A\ *) ain="$ain${t#A } " ;; w4:pb:B\ *) bin_="$bin_${t#B } " ;; *) cross=$((cross + 1)) ;; esac
  k=$((k + 1))
done
want=$(i=1; while [ $i -le 50 ]; do printf '%s ' $i; i=$((i + 1)); done)
is 'QS-07: 100 answers typed'                                 "$(cat "$HERDR_STUB/count")" 100
is 'QS-07: 0 cross-session turns in 100'                      "$cross" 0
is 'session sa of T-031 got its 50 in order'                  "$ain" "$want"
is 'session sb of T-032 got its 50 in order'                  "$bin_" "$want"
is 'no worker pane of T-030 got a turn'                       "$(awk '$3 ~ /^w3:/' "$HERDR_STUB/prompts" | wc -l | tr -d ' ')" 0

# --- the wave of T-030 in the browser ----------------------------------------------------------------------------
browser "$repo/tests/ui-multisession.test.js"
rc=$?
cat "$tmp/browser.out"
is 'the browser checks exit 0'                                "$rc" 0
has 'the browser checks ran'                                  '^PASS |^FAIL ' "$(cat "$tmp/browser.out")"

# --- herd.md step 5 with ui: docker sends the human to the worker's pane, the monitor relays nothing -------------
five=$(awk '/^5\. /{on=1} /^6\. /{on=0} on' "$repo/skills/factory/references/herd.md")
has 'herd.md step 5 names ui: docker'                         'ui: docker' "$five"
has 'herd.md step 5 sends the human to the pane of the worker at a dialog' '[Pp]ane' "$five"

exit $fail
