#!/bin/sh
# The fixture of the Factory UI suites, sourced by tests/ui-server.test.sh and tests/ui-page.test.sh once Docker
# is known to run, with $repo, $bin, $tmp and $name set: the check helpers, a stub `herdr` on PATH, two state
# repos on an ephemeral ui_port, and a UI home with session s1 (pane w1:p1, task T-001) and its asks q1 and q3
# open and q2 answered, each one grill round. It exports FACTORY_UI_HOME and FACTORY_UI_CONTAINER. `browser` is
# the Playwright harness of the page suites; `org_state <dir>` builds a third state repo with the real scripts for
# the request, org and setup routes.

fail=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
is() { if [ "$2" = "$3" ]; then pass "$1"; else bad "$1: want '$3', got '$2'"; fi; }
isnt() { if [ "$2" != "$3" ]; then pass "$1"; else bad "$1: got '$2' both times"; fi; }
has() { # <what> <extended regex> <text>
  if printf '%s\n' "$3" | grep -Eq -- "$2"; then pass "$1"; else bad "$1: no /$2/ in: $(printf '%s' "$3" | head -c 600)"; fi
}
hasnt() { # <what> <extended regex> <text>
  if printf '%s\n' "$3" | grep -Eq -- "$2"; then bad "$1: /$2/ in: $(printf '%s' "$3" | head -c 600)"; else pass "$1"; fi
}
now() { date +%s%3N; }

# --- a stub herdr: tabs are files under $HERDR_STUB/tabs named by tab id and holding the label; every call is logged
mkdir -p "$tmp/path" "$tmp/herdr/tabs"
cat > "$tmp/path/herdr" <<'STUB'
#!/bin/sh
set -u
s=$HERDR_STUB
printf '%s\n' "$*" >> "$s/log"
case "${1:-} ${2:-}" in
  'tab list')
    out=$(
      printf '{"id":"cli:tab:list","result":{"tabs":['
      sep=''
      for f in "$s"/tabs/*; do
        [ -f "$f" ] || continue
        printf '%s{"agent_status":"unknown","focused":false,"label":"%s","number":1,"pane_count":1,"tab_id":"%s","workspace_id":"w9"}' \
          "$sep" "$(cat "$f")" "${f##*/}"
        sep=,
      done
      printf ']}}'
    )
    sleep "${HERDR_STUB_LIST_DELAY:-0}"
    printf '%s\n' "$out"
    ;;
  'tab create')
    label='' prev=''
    for a in "$@"; do [ "$prev" = --label ] && label=$a; prev=$a; done
    id="w9:t$$"
    printf '%s' "$label" > "$s/tabs/$id"
    printf '{"id":"cli:tab:create","result":{"root_pane":{"agent_status":"unknown","cwd":"/tmp","focused":false,"pane_id":"w9:p%s","revision":0,"tab_id":"%s","workspace_id":"w9"},"tab":{"agent_status":"unknown","focused":false,"label":"%s","number":2,"pane_count":1,"tab_id":"%s","workspace_id":"w9"},"type":"tab_created"}}\n' \
      "$$" "$id" "$label" "$id"
    ;;
  'tab close')
    if [ -f "$s/tabs/${3:-}" ]; then rm -f "$s/tabs/$3"; echo '{"id":"cli:tab:close","result":{"type":"ok"}}'
    else printf '{"error":{"code":"tab_not_found","message":"tab %s not found"},"id":"cli:tab:close"}\n' "${3:-}"; exit 1; fi
    ;;
  *) echo '{"id":"cli:stub","result":{"type":"ok"}}' ;;
esac
STUB
chmod +x "$tmp/path/herdr"
HERDR_STUB="$tmp/herdr"
: > "$HERDR_STUB/log"
PATH="$tmp/path:$PATH"
FACTORY_UI_CONTAINER=$name
export HERDR_STUB PATH FACTORY_UI_CONTAINER
unset HERDR_PANE_ID HERDR_WORKSPACE_ID

# --- the fixture: two state repos and a UI home with one session, two open asks and one answered ------------------
free_port() {
  docker run -d --name "$name-free" -p 127.0.0.1::80 alpine:3.22 sleep 60 >/dev/null 2>&1 || return 1
  docker port "$name-free" 80/tcp | sed -n 's/^127\.0\.0\.1://p' | head -n1
  docker rm -f "$name-free" >/dev/null 2>&1
}
port1=$(free_port)
case "$port1" in ''|*[!0-9]*) echo "FAIL no ephemeral port from docker: '$port1'"; exit 1 ;; esac

state_repo() { # <dir> <task sentence>
  mkdir -p "$1/repos/claude-factory/tasks"
  printf 'ui: docker\nui_port: %s\nspawn: herdr\n' "$port1" > "$1/factory.yml"
  printf 'claude-factory:\n  path: /nowhere/claude-factory\n' > "$1/repos.yml"
  printf -- '---\nid: T-001\nrepo: claude-factory\nstatus: ready\ntier: yellow\narchetype: feature\n---\n\n# Goal\n%s\n' "$2" \
    > "$1/repos/claude-factory/tasks/T-001-fixture.md"
  mkdir -p "$1/locked-at-start"
  echo secret > "$1/locked-at-start/inside.md"
  git -C "$1" init -q
  git -C "$1" -c user.name=t -c user.email=t@t add -A
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm 'fixture'
  chmod 000 "$1/locked-at-start"
}
state1="$tmp/state1" state2="$tmp/state2"
state_repo "$state1" 'The fixture sentence of state one.'
state_repo "$state2" 'The fixture sentence of state two.'

org_task() { # <dir> <key> <id> <status> <request> <priority or -> <goal> [acceptance]
  {
    printf -- '---\nid: %s\nrepo: %s\nstatus: %s\ntier: green\narchetype: feature\nrequest: %s\n' "$3" "$2" "$4" "$5"
    [ "$6" = - ] || printf 'priority: %s\n' "$6"
    printf -- 'owner: null\n---\n\n# Goal\n%s\n\n## Context\nThe fixture of the org routes.\n' "$7"
    [ -z "${8:-}" ] || printf '\n## Acceptance\n%s\n\n## Out of scope\nNothing else.\n' "$8"
  } > "$1/repos/$2/tasks/$3-org.md"
}
org_state() { # <dir>: repos claude-factory (CF) and ecs (ECS); request R-20260925-1 in grilling with tickets 01
  # resolved, 02 open on the frontier, 03 dropped, 04 open behind 02, 05 claimed, and parents T-ECS-1 (P1, blocks
  # -01 without a priority and -02 at P3) and T-CF-1 (none, so P2); request R-20260920-1 done and archived with its
  # parent T-CF-2 (P0) and block T-CF-2-01 by state-archive.sh --all; leases by capacity.sh for the lead of
  # T-ECS-1, a block, a scout subagent and an uncapped architecture-auditor; passes stamped by pass-stamp.sh.
  o=$1
  mkdir -p "$o/repos/claude-factory/tasks" "$o/repos/claude-factory/progress" "$o/repos/ecs/tasks"
  git init -q -b main "$o" && git -C "$o" config user.email ui@localhost && git -C "$o" config user.name ui || return 1
  printf 'ui: docker\nui_port: %s\nspawn: herdr\ncapacity:\n  sessions: 10\n  roles: {repo-lead: 3, scout: 8, implementer: 4}\n' \
    "$port1" > "$o/factory.yml"
  printf 'claude-factory:\n  path: /nowhere/claude-factory\n  alias: CF\necs:\n  path: /nowhere/ecs\n  alias: ECS\n' > "$o/repos.yml"
  org_task "$o" ecs T-ECS-1 in_progress R-20260925-1 P1 'feat(ecs): export invoices to the ledger' '`make test` passes.'
  org_task "$o" ecs T-ECS-1-01 ready R-20260925-1 - 'feat(ecs): keep the export cursor' 'The cursor test passes.'
  org_task "$o" ecs T-ECS-1-02 ready R-20260925-1 P3 'feat(ecs): the nightly job'
  org_task "$o" claude-factory T-CF-1 ready R-20260925-1 - 'feat(ui): show the export'
  git -C "$o" add -A && git -C "$o" commit -qm 'fixture: the org state' || return 1
  org_task "$o" claude-factory T-CF-2 done R-20260920-1 P0 'fix(ui): the old export' 'It was done.'
  org_task "$o" claude-factory T-CF-2-01 done R-20260920-1 - 'fix(ui): the old block'
  printf 'The archived progress of T-CF-2.\n' > "$o/repos/claude-factory/progress/T-CF-2.md"
  git -C "$o" add -A && git -C "$o" commit -qm 'task: T-CF-2 opened' || return 1

  om() { sh "$bin/map.sh" "$@" --state "$o"; }
  om new R-20260925-1 --destination 'Invoices reach the ledger every night.' </dev/null >/dev/null || return 1
  printf 'Which ledger API do we post to?\n' | om ticket R-20260925-1 research 'Which ledger API' >/dev/null || return 1
  printf 'Where does the export keep its cursor?\n' | om ticket R-20260925-1 grilling 'Pick the store' --repo ecs --blocked-by 01 >/dev/null || return 1
  om ticket R-20260925-1 task 'Get ledger access' </dev/null >/dev/null || return 1
  om ticket R-20260925-1 grilling 'Order the exports' --blocked-by 02 </dev/null >/dev/null || return 1
  om ticket R-20260925-1 prototype 'Try the cursor' --repo ecs </dev/null >/dev/null || return 1
  om claim R-20260925-1 01 --by s-chart </dev/null >/dev/null || return 1
  printf 'The REST API, v2.\nThe report is research/ledger.md.\n' | om resolve R-20260925-1 01 >/dev/null || return 1
  printf "Access is the other team's rollout.\n" | om drop R-20260925-1 03 >/dev/null || return 1
  om claim R-20260925-1 05 --by chart_ecs-12 </dev/null >/dev/null || return 1
  printf 'How the two exports are ordered once both run.\n' | om set R-20260925-1 fog >/dev/null || return 1
  printf 'Both repos post through the REST API.\n' | om set R-20260925-1 notes >/dev/null || return 1
  printf -- '- **Ledger**: the accounting system of record. Avoid: books\n' | om set R-20260925-1 terms >/dev/null || return 1
  om status R-20260925-1 grilling </dev/null >/dev/null || return 1
  om new R-20260920-1 --destination 'The old export reached the ledger.' </dev/null >/dev/null || return 1
  for w in planned queued running done; do om status R-20260920-1 "$w" </dev/null >/dev/null || return 1; done
  sh "$bin/state-archive.sh" --all --state "$o" >/dev/null || return 1

  oc() { sh "$bin/capacity.sh" "$@" --state "$o"; }
  oc acquire sessions T-ECS-1-lead && oc acquire repo-lead T-ECS-1 && oc acquire implementer T-ECS-1-01 \
    && oc acquire scout agent-1 --session sess-1 && oc acquire architecture-auditor T-ECS-1-02 || return 1
  sh "$bin/pass-stamp.sh" daily global --state "$o" >/dev/null && sh "$bin/pass-stamp.sh" weekly repo:ecs --state "$o" >/dev/null \
    && sh "$bin/pass-stamp.sh" daily repo-agent:ecs/implementer --state "$o" >/dev/null
}

ui="$tmp/ui"
FACTORY_UI_HOME=$ui
export FACTORY_UI_HOME
mkdir -p "$ui/sessions/s1/asks"
printf -- '---\nsid: s1\npane: w1:p1\nflow: grill\ntask: T-001\nstep: round 1\nupdated: 2026-09-24T00:00:00Z\n---\n' \
  > "$ui/sessions/s1/session.md"
ask() { # <ask> <status>
  printf -- '---\nask: %s\ntask: T-001\nflow: grill\nstep: round 1\nstatus: %s\n---\n\n%s\n' "$1" "$2" \
    '❓ **Q1** - **Which fixture?**: the question of the fixture.
  **A** the first
  **B** the second

➡️ **A**: the first is the fixture.' > "$ui/sessions/s1/asks/$1.md"
}
ask q1 open; ask q2 answered; ask q3 open

up() { # [args]: ui-up.sh, stdout in $tmp/up.out, stderr in $tmp/up.err
  HERDR_ENV=1 timeout 15m sh "$bin/ui-up.sh" "$@" > "$tmp/up.out" 2> "$tmp/up.err"
}
down() { HERDR_ENV=1 timeout 120 sh "$bin/ui-down.sh" > "$tmp/down.out" 2>&1; }
http() { # <port> <path> [curl args]: prints the status code, the body lands in $tmp/body
  p=$1 path=$2; shift 2
  curl -s -m 5 -o "$tmp/body" -w '%{http_code}' "$@" "http://127.0.0.1:$p$path"
}
ready() { # <port>: the server answers / within 20 s
  i=0
  while [ $i -lt 200 ]; do
    [ "$(http "$1" / 2>/dev/null)" = 200 ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

browser() { # <test.js>: node runs it in a Playwright container on the host network as the host uid against the
  # server on $port with $token, the UI home mounted at its own path; its output lands in $tmp/browser.out
  pw_version=1.63.0
  pw="cf-ui-playwright:$pw_version"
  if ! docker image inspect "$pw" >/dev/null 2>&1; then
    printf 'FROM mcr.microsoft.com/playwright:v%s-noble\nRUN npm install -g playwright-core@%s\nENV NODE_PATH=/usr/lib/node_modules\n' \
      "$pw_version" "$pw_version" | timeout 15m docker build -q -t "$pw" - >/dev/null \
      || { bad "the Playwright image $pw could not be built"; return 1; }
  fi
  timeout 15m docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e BASE="http://127.0.0.1:$port" -e TOKEN="$token" -e UI="$ui" \
    -v "$ui:$ui" -v "$1:/t/${1##*/}:ro" "$pw" node "/t/${1##*/}" > "$tmp/browser.out" 2>&1
}
