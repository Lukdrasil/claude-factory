#!/bin/sh
# The fixture of the Factory UI suites, sourced by tests/ui-server.test.sh and tests/ui-page.test.sh once Docker
# is known to run, with $repo, $bin, $tmp and $name set: the check helpers, a stub `herdr` on PATH, two state
# repos on an ephemeral ui_port, and a UI home with session s1 (pane w1:p1, task T-001) and its asks q1 and q3
# open and q2 answered, each one grill round. It exports FACTORY_UI_HOME and FACTORY_UI_CONTAINER.

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
