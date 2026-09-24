#!/bin/sh
# Starts the Factory UI: builds the image claude-factory-ui:<plugin version> when missing, starts or reuses the
# one container as the host uid:gid with the state dir at /state read-only and the UI home at /ui read-write,
# published on 127.0.0.1:<ui_port> or a random free port when that is taken, opens the relay in the herdr tab
# factory-ui-relay when none is open, and prints the URL with the token. A state dir is one with a repos.yml. With
# no --state and none to resolve from the cwd, as before factory init, it starts with /ui only on port 7171. A
# running container whose cf.version or cf.state label differs is recreated. Exits 3 when Docker is not running,
# 4 outside herdr.
#
#   ui-up.sh [--state <dir>]
set -eu

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=${bin%/*}
. "$bin/lib-tasks.sh"

die() { printf 'ui-up: %s\n' "$1" >&2; exit "${2:-1}"; }

state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ "${HERDR_ENV:-}" = 1 ] || die "the Factory UI runs only inside herdr (HERDR_ENV=1)" 4
docker info >/dev/null 2>&1 || die "Docker is not running" 3

if [ -n "$state" ]; then
  state=$(CDPATH= cd -- "$state" 2>/dev/null && pwd) || die "no state dir at '$state'"
  [ -f "$state/repos.yml" ] || die "$state is not a factory state repo (no repos.yml)"
else
  state=$(CDPATH= cd -- "$(resolve_state_dir "$PWD")" 2>/dev/null && pwd) || state=''
  [ -n "$state" ] && [ -f "$state/repos.yml" ] || state=''
fi

name=${FACTORY_UI_CONTAINER:-claude-factory-ui}
ui=${FACTORY_UI_HOME:-$HOME/.claude-factory/ui}
ver=$(sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -n1)
image="claude-factory-ui:$ver"
port=''
[ -z "$state" ] || port=$(sed -n 's/^ui_port:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$state/factory.yml" 2>/dev/null | head -n1)
port=${port:-7171}

mkdir -p "$ui"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$ui/.up.lock"
  flock -w 900 9 || die "another ui-up.sh held $ui/.up.lock for 15 minutes"
fi

put() { # <file> <text>: through a temp file and a rename
  printf '%s\n' "$2" > "$1.$$"
  mv -f "$1.$$" "$1"
}

if [ ! -s "$ui/token" ]; then
  (umask 077; put "$ui/token" "$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')")
fi
token=$(cat "$ui/token")

err=$(mktemp)
trap 'rm -f "$err"' EXIT

run() { # <publish spec>: docker run's stderr in $err
  publish=$1
  set --
  [ -z "$state" ] || set -- -e "FACTORY_ROOT=${state%/*}" -v "$state:/state:ro"
  docker run -d --name "$name" --user "$(id -u):$(id -g)" \
    --label "cf.version=$ver" --label "cf.state=$state" \
    "$@" -v "$ui:/ui" -p "$publish" "$image" >/dev/null 2>"$err"
}

start() {
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker build -t "$image" "$root/ui" >&2 || die "building $image failed"
  fi
  run "127.0.0.1:$port:8080" && return 0
  if grep -q 'is already in use by container' "$err"; then return 0; fi
  docker rm -f "$name" >/dev/null 2>&1 || :
  run "127.0.0.1::8080" || die "docker run failed: $(cat "$err")"
}

current=$(docker inspect -f '{{index .Config.Labels "cf.version"}}|{{index .Config.Labels "cf.state"}}|{{.State.Running}}' \
  "$name" 2>/dev/null) || current=''
if [ -n "$current" ] && [ "$current" != "$ver|$state|true" ]; then
  docker rm -f "$name" >/dev/null
  current=''
fi
[ -n "$current" ] || start

port=$(docker port "$name" 8080/tcp | sed -n 's/^127\.0\.0\.1://p' | head -n1)
[ -n "$port" ] || die "the container $name publishes no port on 127.0.0.1"
put "$ui/port" "$port"

if ! herdr tab list 2>/dev/null | tr '{' '\n' | grep -Eq '"label":"factory-ui-relay"[,}]'; then
  set -- tab create --label factory-ui-relay --no-focus
  [ -z "${HERDR_WORKSPACE_ID:-}" ] || set -- "$@" --workspace "$HERDR_WORKSPACE_ID"
  pane=$(herdr "$@" | grep -o '"pane_id":"[^"]*"' | head -n1 | cut -d'"' -f4)
  [ -n "$pane" ] || die "herdr tab create gave no pane for the relay"
  herdr pane run "$pane" "sh '$bin/ui-relay.sh' --home '$ui'" >/dev/null || die "herdr pane run failed in $pane"
fi

printf 'http://127.0.0.1:%s/#token=%s\n' "$port" "$token"
