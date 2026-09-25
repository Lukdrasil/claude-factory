#!/bin/sh
# The CEO's periodic check that every session does what it should (references/ceo.md, Watch): the loop the CEO
# arms through the Monitor tool, a pass every --interval seconds (default 300). One pass reads one `herdr agent
# list`, the open asks of the Factory UI, queue-next.sh and capacity.sh, and prints one line per finding:
#
#   <name> blocked <m> min              a named agent at a dialog for --blocked minutes or more (default 10)
#   <name> idle <m> min, no open ask    a named agent other than the CEO, idle or done for --idle minutes or more
#                                       (default 10), whose session has no open ask of the UI (<UI home>/sessions/
#                                       <agent_session>/asks/*.md with `status: open`): it finished and was left
#                                       open, or stopped mid-work
#   queue <n> parents wait with <free> sessions free
#                                       queue-next.sh names approved parents while capacity.sh leaves two session
#                                       slots and a repo-lead slot free, so a `session-monitor.sh --queue` was missed
#
# A finding prints when it first passes its threshold and again every --repeat minutes (default 30) while it
# lasts. `<key> <since> <last printed>` per finding, the key `<name>:<blocked|idle>` or `queue`, is kept in
# `<factory root>/.org-check.state`, so a pass with nothing new prints nothing and a status change starts the clock
# over. ORG_CHECK_NOW (epoch seconds) stands in for the clock in tests.
#
#   org-check.sh [--once] [--interval <s>] [--blocked <min>] [--idle <min>] [--repeat <min>] [--state <dir>]
#
# Exit 0 after a pass; 1 on bad usage or no state clone. herdr not answering is a pass with no agent finding.
set -eu

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
die() { printf 'org-check: %s\n' "$1" >&2; exit 1; }

once='' interval=300 blocked=10 idle=10 repeat=30 state=${WORK_DIR:+$WORK_DIR/state}
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1; shift ;;
    --interval|--blocked|--idle|--repeat|--state)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --interval) interval=$2 ;; --blocked) blocked=$2 ;; --idle) idle=$2 ;; --repeat) repeat=$2 ;; --state) state=$2 ;;
      esac
      shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
for n in "$interval" "$blocked" "$idle" "$repeat"; do
  case "$n" in ''|*[!0-9]*) die "a period takes a number of seconds or minutes, not '$n'" ;; esac
done
[ -n "$state" ] && [ -f "$state/repos.yml" ] || die "no state clone at '${state:-}': pass --state <dir> or set WORK_DIR"
statefile="$(dirname -- "$state")/.org-check.state"
ui=${FACTORY_UI_HOME:-$HOME/.claude-factory/ui}

# the free slots of one capacity role, a large number for a role without a cap
free() { # <role>
  c=$(sh "$bin/capacity.sh" count "$1" --state "$state" 2>/dev/null </dev/null) || c=''
  case "$c" in */[0-9]*) echo $(( ${c#*/} - ${c%/*} )) ;; *) echo 999 ;; esac
}

# one finding: printed once it has lasted <threshold> minutes, then every --repeat minutes; its state line goes to $next
finding() { # <key> <threshold min> <line with %d for the minutes>
  prev=$(awk -v k="$1" '$1 == k { print $2, $3; exit }' "$statefile" 2>/dev/null || :)
  since=${prev% *} printed=${prev#* }
  [ -n "$prev" ] || { since=$now printed=0; }
  mins=$(( (now - since) / 60 ))
  if [ "$mins" -ge "$2" ] && { [ "$printed" -eq 0 ] || [ $((now - printed)) -ge $((repeat * 60)) ]; }; then
    # shellcheck disable=SC2059
    case "$3" in *%d*) printf "$3\n" "$mins" ;; *) printf '%s\n' "$3" ;; esac
    printed=$now
  fi
  printf '%s %s %s\n' "$1" "$since" "$printed" >> "$next"
}

pass() {
  now=${ORG_CHECK_NOW:-$(date +%s)}
  next="$statefile.$$"
  : > "$next"
  agents=$(herdr agent list 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let a=[];try{a=JSON.parse(s).result.agents||[]}catch(e){}
for(const x of a){const n=String(x.name||"");if(!n||n==="ceo")continue;
process.stdout.write([n,x.agent_status||"",(x.agent_session&&x.agent_session.value)||"-"].join("\t")+"\n")}})' 2>/dev/null) || agents=''
  while IFS='	' read -r name st sid; do
    [ -n "$name" ] || continue
    case "$st" in
      blocked) finding "$name:blocked" "$blocked" "$name blocked %d min" ;;
      idle|done)
        if [ "$sid" != - ] && grep -qs '^status:[[:space:]]*open' "$ui/sessions/$sid/asks/"*.md; then continue; fi
        finding "$name:idle" "$idle" "$name idle %d min, no open ask" ;;
    esac
  done <<EOF
$agents
EOF
  waiting=$(sh "$bin/queue-next.sh" --state "$state" 2>/dev/null </dev/null | grep -c . || :)
  sfree=$(free sessions)
  if [ "${waiting:-0}" -gt 0 ] && [ "$sfree" -ge 2 ] && [ "$(free repo-lead)" -ge 1 ]; then
    finding queue 0 "queue $waiting parents wait with $sfree sessions free"
  fi
  mv -f "$next" "$statefile"
}

pass
[ -z "$once" ] || exit 0
while :; do
  sleep "$interval"
  pass
done
