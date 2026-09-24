#!/bin/sh
# The one owner of the tab record, `<root>/<key>/.harness/<T-NNN>/herdr-tabs`: one `<unit> <tab_id> <pane_id>
# [<session_id>]` line per tab session-monitor.sh created in herdr, and one `<unit> <tab_id> closed` line per tab
# this script closed. The file is only ever appended to and the last line of a unit wins, so every writer
# appends without a lock.
#
#   herdr-tabs.sh name <unit> [--state <dir>]
#   herdr-tabs.sh record <unit> <tab_id> <pane_id> [<session_id>] [--state <dir>]
#   herdr-tabs.sh session <unit> <session_id> [--state <dir>]
#   herdr-tabs.sh state <unit> [--state <dir>]
#   herdr-tabs.sh agents <T-NNN> [--state <dir>]
#   herdr-tabs.sh reattach <T-NNN> [--state <dir>]
#   herdr-tabs.sh close <unit>... [--state <dir>]
#   herdr-tabs.sh sweep <T-NNN> [--state <dir>]
#
# A unit is a task or block id (`T-NNN`, `T-NNN-NN`, `T-<ALIAS>-<n>` and its blocks) or a parent-level step
# (`<T-id>-<step>`); its T-id names the record and its task file names the repo key. `name` prints the session
# name `<emoji> <key> <unit>`, the tab label and the `claude --name` of the unit: the emoji is the repo's `emoji:`
# in repos.yml, and without one a fixed pick out of sixteen by the `cksum` of the key, so a repo keeps its emoji
# from run to run.
#
# `session` appends the unit's open record line again with the session id, once the session is known. `state`
# prints `open`, `closed`, or `none` for a unit with no record.
#
# `agents` reads one `herdr agent list` and prints `<unit> <agent_status> <pane> <session> <name>` per recorded
# unit, `-` for a field it has not: `closed` for a closed record, `gone` when no live agent carries it, and
# `unknown` for every open unit when herdr does not answer. An agent carries a unit when its
# `agent_session.value` is the recorded session id, in whatever pane, or, with no session recorded (or an agent
# reporting none), when it sits in the recorded pane; another session in that pane is `gone`.
#
# `reattach`, after a herdr restart that left the agents unnamed, matches every open record the same way and
# runs `herdr agent rename <pane> <name>` with the plan 3.6 name: `<step>_<tail>` for a step unit,
# `<role>_<tail>` for a block whose capacity lease names its role, the lowercased unit otherwise, the tail being
# the lowercased T-id with the leading `t-` dropped for an alias id (`lead_ecs-12`, `grill_t-264`). It prints
# `<unit> renamed <name> <pane>`, `<unit> named <name> <pane>` when the agent has the name already, `<unit> gone`,
# or `<unit> kept <pane> rename failed`.
#
# `close` closes the open recorded tab of each unit and prints `<unit> closed <tab_id>`, or `<unit> kept <tab_id>
# <reason>` for a tab it leaves alone: the caller's own `$HERDR_TAB_ID`, a focused tab, an agent that is not
# idle, done or unknown per `herdr tab get`, and `tab get failed` for a `tab get` that fails or answers with no
# `focused` field. A `tab get` or a close herdr answers with `tab_not_found` is a close. `sweep` runs `close`
# over every recorded unit of T-NNN whose status is `done` or `closed` or whose task is archived, a step unit
# judged by its parent. A `<T-id>-lead` unit it sweeps closes the lead's whole workspace (labelled `<T-id>
# <key>`, the workspace of the recorded tab per `tab get`) and prints `<unit> closed <workspace_id>`, keeping the
# caller's own `$HERDR_WORKSPACE_ID`; `close` of a lead closes its tab only, since its blocks may still run.
# `close`, `sweep` and `reattach` do nothing without herdr on PATH, and `agents` then reads every open unit
# `gone`.
#
# Exit 0 on success, 1 with the reason on stderr on bad usage, a unit that resolves to no task file, a
# `session` for a unit with no open record, or a `reattach` herdr does not answer.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'herdr-tabs: %s\n' "$1" >&2; exit 1; }
usage='usage: herdr-tabs.sh name <unit> | record <unit> <tab_id> <pane_id> [<session_id>] | session <unit> <session_id> | state <unit> | agents <T-NNN> | reattach <T-NNN> | close <unit>... | sweep <T-NNN> [--state <dir>]'

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
  'name 1'|'record 3'|'record 4'|'session 2'|'state 1'|'agents 1'|'reattach 1'|'sweep 1'|close\ [1-9]*) ;;
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
    *-[a-z]*) tid=${1%%-[a-z]*}; is_parent_id "$tid" ;;
    *) tid=$1; is_task_id "$tid" ;;
  esac || die "'$1' is not a task, block or step id"
  task=$(task_of "$tid" || :)
  [ -n "$task" ] || die "$1 resolves to no task file under $state/repos/*/tasks"
  key=${task#"$state/repos/"}
  key=${key%%/*}
  parent=$tid
  if is_block_id "$tid"; then parent=${tid%-*}; fi
  dir="$root/$key/.harness/$parent"
}

last() { # <unit>
  [ ! -f "$dir/herdr-tabs" ] || awk -v u="$1" '$1 == u { l = $0 } END { print l }' "$dir/herdr-tabs"
}

close_one() { # <unit> [workspace]: with a second argument the lead's whole workspace
  resolve "$1"
  line=$(last "$1")
  case "$line" in ''|*' closed') return 0 ;; esac
  tab=$(printf '%s' "$line" | cut -d' ' -f2)
  if [ "$tab" = "${HERDR_TAB_ID:-}" ]; then
    printf '%s kept %s own tab\n' "$1" "$tab"; return 0
  fi
  rc=0
  reply=$(herdr tab get "$tab" 2>&1) || rc=$?
  # `<focused> <agent_status> <workspace_id>`
  case "$rc $reply" in
    0\ *) info=$(printf '%s' "$reply" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      let t;try{t=JSON.parse(s).result.tab}catch(e){}
      process.stdout.write(t&&typeof t.focused==="boolean"?t.focused+" "+(t.agent_status||"unknown")+" "+(t.workspace_id||"-"):"failed")})') ;;
    *tab_not_found*) info=gone ;;
    *) info=failed ;;
  esac
  case "$info" in
    failed) printf '%s kept %s tab get failed\n' "$1" "$tab"; return 0 ;;
    true\ *) printf '%s kept %s focused\n' "$1" "$tab"; return 0 ;;
    gone|*\ idle\ *|*\ done\ *|*\ unknown\ *) ;;
    *) st=${info#* }; printf '%s kept %s agent %s\n' "$1" "$tab" "${st%% *}"; return 0 ;;
  esac
  ws=${info##* }
  if [ -n "${2:-}" ] && [ "$info" != gone ] && [ "$ws" != - ]; then
    if [ "$ws" = "${HERDR_WORKSPACE_ID:-}" ]; then
      printf '%s kept %s own workspace\n' "$1" "$ws"; return 0
    fi
    if ! err=$(herdr workspace close "$ws" 2>&1 >/dev/null); then
      case "$err" in
        *workspace_not_found*) ;;
        *) printf '%s kept %s herdr workspace close failed\n' "$1" "$ws"; return 0 ;;
      esac
    fi
    printf '%s %s closed\n' "$1" "$tab" >> "$dir/herdr-tabs"
    printf '%s closed %s\n' "$1" "$ws"
    return 0
  fi
  if [ "$info" != gone ] && ! err=$(herdr tab close "$tab" 2>&1 >/dev/null); then
    case "$err" in
      *tab_not_found*) ;;
      *) printf '%s kept %s herdr tab close failed\n' "$1" "$tab"; return 0 ;;
    esac
  fi
  printf '%s %s closed\n' "$1" "$tab" >> "$dir/herdr-tabs"
  printf '%s closed %s\n' "$1" "$tab"
}

# the last line of every unit of the record in $dir, in the order the units first appear
records() {
  [ ! -f "$dir/herdr-tabs" ] || awk '!($1 in l) { u[++n] = $1 } { l[$1] = $0 } END { for (i = 1; i <= n; i++) print l[u[i]] }' \
    "$dir/herdr-tabs"
}

# `<unit> <agent_status> <pane> <session> <name>` per record line on stdin, from the `agent list` JSON in $1
match() { # <agent list json>
  HT_LIST=$1 node -e '
let a=null;try{a=JSON.parse(process.env.HT_LIST).result.agents}catch(e){}
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
const ses=x=>String((x.agent_session&&x.agent_session.value)||"");
for(const l of s.split("\n")){
  const [u,tab,pane,sid]=l.split(" ");if(!u)continue;
  if(pane==="closed"){console.log(u+" closed - - -");continue}
  if(!Array.isArray(a)){console.log(u+" unknown - - -");continue}
  const m=sid?(a.find(x=>ses(x)===sid)||a.find(x=>x.pane_id===pane&&!ses(x))):a.find(x=>x.pane_id===pane);
  if(!m){console.log(u+" gone - - -");continue}
  console.log([u,m.agent_status||"unknown",m.pane_id||"-",ses(m)||"-",m.name||"-"].join(" "))}})'
}

# the herdr agent name of plan 3.6, after resolve
agent_name() { # <unit>
  tail=$(printf '%s' "$tid" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  case "$tail" in t-[0-9]*) ;; *) tail=${tail#t-} ;; esac
  case "$1" in
    *-[a-z]*) printf '%s_%s\n' "${1#"$tid"-}" "$tail"; return 0 ;;
  esac
  for f in "$state"/.capacity/*/"$1"; do
    [ -f "$f" ] || continue
    role=${f%/*}; role=${role##*/}
    case "$role" in sessions|repo-lead) continue ;; esac
    printf '%s_%s\n' "$role" "$tail"; return 0
  done
  printf '%s\n' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
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
    printf '%s %s %s%s\n' "$1" "$2" "$3" "${4:+ $4}" >> "$dir/herdr-tabs" ;;
  session)
    resolve "$1"
    line=$(last "$1")
    case "$line" in ''|*' closed') die "$1 has no open tab record in $dir/herdr-tabs" ;; esac
    printf '%s %s\n' "$(printf '%s' "$line" | cut -d' ' -f1-3)" "$2" >> "$dir/herdr-tabs" ;;
  agents)
    is_parent_id "$1" || die "'$1' is not a parent task id of the shape T-NNN"
    resolve "$1"
    if command -v herdr >/dev/null 2>&1; then
      list=$(herdr agent list 2>/dev/null) || list=''
    else
      list='{"result":{"agents":[]}}'
    fi
    records | match "$list" ;;
  reattach)
    is_parent_id "$1" || die "'$1' is not a parent task id of the shape T-NNN"
    command -v herdr >/dev/null 2>&1 || exit 0
    resolve "$1"
    [ -f "$dir/herdr-tabs" ] || exit 0
    list=$(herdr agent list 2>/dev/null) || die "herdr agent list failed; nothing renamed"
    records | match "$list" | while read -r u st pane sid name; do
      case "$st" in closed) continue ;; gone) printf '%s gone\n' "$u"; continue ;; esac
      resolve "$u"
      want=$(agent_name "$u")
      if [ "$name" = "$want" ]; then
        printf '%s named %s %s\n' "$u" "$want" "$pane"
      elif herdr agent rename "$pane" "$want" >/dev/null 2>&1; then
        printf '%s renamed %s %s\n' "$u" "$want" "$pane"
      else
        printf '%s kept %s rename failed\n' "$u" "$pane"
      fi
    done ;;
  state)
    resolve "$1"
    case "$(last "$1")" in '') echo none ;; *' closed') echo closed ;; *) echo open ;; esac ;;
  close)
    command -v herdr >/dev/null 2>&1 || exit 0
    for u; do close_one "$u"; done ;;
  sweep)
    is_parent_id "$1" || die "'$1' is not a parent task id of the shape T-NNN"
    command -v herdr >/dev/null 2>&1 || exit 0
    resolve "$1"
    [ -f "$dir/herdr-tabs" ] || exit 0
    for u in $(cut -d' ' -f1 "$dir/herdr-tabs" | sort -u); do
      resolve "$u"
      case "$task $(field "$task" status)" in
        */archive/*|*\ done|*\ closed) ;;
        *) continue ;;
      esac
      case "$u" in *-lead) close_one "$u" workspace ;; *) close_one "$u" ;; esac
    done ;;
esac
