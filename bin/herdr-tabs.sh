#!/bin/sh
# The one owner of the tab record, `<root>/<key>/.harness/<T-NNN>/herdr-tabs`: one `<unit> <tab_id> <pane_id>`
# line per tab session-monitor.sh created in herdr, and one `<unit> <tab_id> closed` line per tab this script
# closed. The file is only ever appended to and the last line of a unit wins, so every writer appends without
# a lock.
#
#   herdr-tabs.sh name <unit> [--state <dir>]
#   herdr-tabs.sh record <unit> <tab_id> <pane_id> [--state <dir>]
#   herdr-tabs.sh state <unit> [--state <dir>]
#   herdr-tabs.sh close <unit>... [--state <dir>]
#   herdr-tabs.sh sweep <T-NNN> [--state <dir>]
#
# A unit is a task or block id (`T-NNN`, `T-NNN-NN`) or a parent-level step (`T-NNN-<step>`); its T-NNN names
# the record and its task file names the repo key. `name` prints the session name `<emoji> <key> <unit>`, the
# tab label and the `claude --name` of the unit: the emoji is the repo's `emoji:` in repos.yml, and without one
# a fixed pick out of sixteen by the `cksum` of the key, so a repo keeps its emoji from run to run.
#
# `state` prints `open`, `closed`, or `none` for a unit with no record. `close` closes the open recorded tab of
# each unit and prints `<unit> closed <tab_id>`, or `<unit> kept <tab_id> <reason>` for a tab it leaves alone:
# the caller's own `$HERDR_TAB_ID`, a focused tab, an agent that is not idle, done or unknown per
# `herdr tab get`, and `tab get failed` for a `tab get` that fails or answers with no `focused` field. A
# `tab get` or a close herdr answers with `tab_not_found` is a close. `sweep` runs `close` over every
# recorded unit of T-NNN whose status is `done` or `closed`, a step unit judged by its parent's status. Both
# do nothing without herdr on PATH.
#
# Exit 0 on success, 1 with the reason on stderr on bad usage or a unit that resolves to no task file.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'herdr-tabs: %s\n' "$1" >&2; exit 1; }
usage='usage: herdr-tabs.sh name <unit> | record <unit> <tab_id> <pane_id> | state <unit> | close <unit>... | sweep <T-NNN> [--state <dir>]'

verb='' args='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) if [ -z "$verb" ]; then verb=$1; else args="$args $1"; fi; shift ;;
  esac
done
set -- $args
case "$verb $#" in
  'name 1'|'record 3'|'state 1'|'sweep 1'|close\ [1-9]*) ;;
  *) die "$usage" ;;
esac

if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    here=$(pwd)
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
  fi
fi
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac

field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }

resolve() { # <unit> -> tid, key, dir
  case "$1" in
    T-[0-9][0-9][0-9]|T-[0-9][0-9][0-9]-[0-9][0-9]) tid=$1 ;;
    T-[0-9][0-9][0-9]-[a-z]*) tid=${1%%-[a-z]*} ;;
    *) die "'$1' is not a task, block or step id" ;;
  esac
  task=$(task_of "$tid" || :)
  [ -n "$task" ] || die "$1 resolves to no task file under $state/repos/*/tasks"
  key=${task#"$state/repos/"}
  key=${key%%/*}
  dir="$root/$key/.harness/${tid%-[0-9][0-9]}"
}

last() { # <unit>
  [ ! -f "$dir/herdr-tabs" ] || awk -v u="$1" '$1 == u { l = $0 } END { print l }' "$dir/herdr-tabs"
}

close_one() { # <unit>
  resolve "$1"
  line=$(last "$1")
  case "$line" in ''|*' closed') return 0 ;; esac
  tab=$(printf '%s' "$line" | cut -d' ' -f2)
  if [ "$tab" = "${HERDR_TAB_ID:-}" ]; then
    printf '%s kept %s own tab\n' "$1" "$tab"; return 0
  fi
  rc=0
  reply=$(herdr tab get "$tab" 2>&1) || rc=$?
  case "$rc $reply" in
    0\ *) info=$(printf '%s' "$reply" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      let t;try{t=JSON.parse(s).result.tab}catch(e){}
      process.stdout.write(t&&typeof t.focused==="boolean"?t.focused+" "+(t.agent_status||"unknown"):"failed")})') ;;
    *tab_not_found*) info=gone ;;
    *) info=failed ;;
  esac
  case "$info" in
    failed) printf '%s kept %s tab get failed\n' "$1" "$tab"; return 0 ;;
    true\ *) printf '%s kept %s focused\n' "$1" "$tab"; return 0 ;;
    gone|*\ idle|*\ done|*\ unknown) ;;
    *) printf '%s kept %s agent %s\n' "$1" "$tab" "${info#* }"; return 0 ;;
  esac
  if [ "$info" != gone ] && ! err=$(herdr tab close "$tab" 2>&1 >/dev/null); then
    case "$err" in
      *tab_not_found*) ;;
      *) printf '%s kept %s herdr tab close failed\n' "$1" "$tab"; return 0 ;;
    esac
  fi
  printf '%s %s closed\n' "$1" "$tab" >> "$dir/herdr-tabs"
  printf '%s closed %s\n' "$1" "$tab"
}

case "$verb" in
  name)
    resolve "$1"
    emoji=$(yml_field "$key" emoji)
    if [ -z "$emoji" ]; then
      sum=$(printf '%s' "$key" | cksum | cut -d' ' -f1)
      emoji=$(printf '%s\n' 🦊 🐙 🦉 🐝 🐢 🦀 🐳 🦋 🌵 🍄 🌻 🍋 🔥 🌊 🪐 🎲 | sed -n "$((sum % 16 + 1))p")
    fi
    printf '%s %s %s\n' "$emoji" "$key" "$1" ;;
  record)
    resolve "$1"
    mkdir -p "$dir"
    printf '%s %s %s\n' "$1" "$2" "$3" >> "$dir/herdr-tabs" ;;
  state)
    resolve "$1"
    case "$(last "$1")" in '') echo none ;; *' closed') echo closed ;; *) echo open ;; esac ;;
  close)
    command -v herdr >/dev/null 2>&1 || exit 0
    for u; do close_one "$u"; done ;;
  sweep)
    case "$1" in T-[0-9][0-9][0-9]) ;; *) die "'$1' is not a parent task id of the shape T-NNN" ;; esac
    command -v herdr >/dev/null 2>&1 || exit 0
    resolve "$1"
    [ -f "$dir/herdr-tabs" ] || exit 0
    for u in $(cut -d' ' -f1 "$dir/herdr-tabs" | sort -u); do
      resolve "$u"
      case "$(field "$task" status)" in done|closed) close_one "$u" ;; esac
    done ;;
esac
