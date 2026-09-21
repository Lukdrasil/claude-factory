#!/bin/sh
# The watcher of `factory herd` (skills/factory/references/herd.md): it reads the parent, its blocks and the
# herdr agents dispatched for them, and prints one line per change since its last run, so the monitor session
# learns what the spawned sessions did without reading any of their output.
#
#   herd-watch.sh <T-NNN> [--once] [--interval <s>] [--state <dir>]
#
# The lines are `<id> status <old> -> <new>`, `<id> phase <old> -> <new>` and `<id> agent <old> -> <new>`,
# with a first sighting written without the arrow. The agent states are herdr's own - working, idle, blocked,
# done, unknown - plus `gone` for a name that is no longer live, which is how a finished or closed session
# reads. What has already been reported is kept in `<root>/<key>/.harness/<T-NNN>/herd-watch.state`, one
# `<id> <status> <phase> <agent>` per line, so a pass with nothing new prints nothing.
#
# The units are the parent, every T-NNN-NN block of it, and the parent-level step sessions
# `<T-NNN>-<triage|grill|plan-check|decompose>` that session-monitor.sh --step dispatches. A step session is
# tracked from the first pass that sees it live; a block with no live agent is still tracked for its status,
# because that is what the session writes through state-report.sh.
#
# Without `--once` the pass repeats every 60 seconds, `--interval <s>` sets another period, and the monitor
# arms the loop through the Monitor tool the way it arms mr-watch.sh.
#
# Exit 0 after a pass. Exit 1 with the reason on stderr when no parent id is given, when the id is not of the
# shape T-NNN, or when it resolves to no task file.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'herd-watch: %s\n' "$1" >&2; exit 1; }

id='' once='' interval=60 state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1; shift ;;
    --interval) [ $# -ge 2 ] || die "--interval needs a value"; interval=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one parent id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: herd-watch.sh <T-NNN> [--once] [--interval <s>] [--state <dir>]"
case "$id" in
  T-[0-9][0-9][0-9]) ;;
  *) die "'$id' is not a parent task id of the shape T-NNN" ;;
esac
case "$interval" in ''|*[!0-9]*) die "--interval takes seconds, not '$interval'" ;; esac

# see: mr-watch.sh, the one state resolution of the factory scripts
if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    here=$(pwd)
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
  fi
fi
task=$(task_of "$id" || :)
[ -n "$task" ] || die "$id resolves to no task file under $state/repos/*/tasks"
key=${task#"$state/repos/"}
key=${key%%/*}
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac
harness="$root/$key/.harness/$id"
seen="$harness/herd-watch.state"

field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }

# the herdr lifecycle of one dispatched session, by the agent name session-monitor.sh started it under
agent_state() { # <unit id>
  command -v herdr >/dev/null 2>&1 || { printf 'gone'; return 0; }
  name=$(printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  out=$(herdr agent get "$name" 2>/dev/null) || { printf 'gone'; return 0; }
  printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    try{const o=JSON.parse(s);process.stdout.write(String(o.result&&o.result.agent&&o.result.agent.agent_status||"unknown"))}
    catch(e){process.stdout.write("unknown")}})'
}

prior() { # <unit id> <column: 2 status | 3 phase | 4 agent>
  [ -f "$seen" ] || return 0
  awk -v u="$1" -v c="$2" '$1 == u { print $c; exit }' "$seen"
}

pass() {
  now=$(mktemp)
  for f in "$state"/repos/"$key"/tasks/*.md; do
    [ -f "$f" ] || continue
    u=$(field "$f" id)
    case "$u" in "$id"|"$id"-[0-9][0-9]) ;; *) continue ;; esac
    s=$(field "$f" status); [ -n "$s" ] || s=none
    p=$(field "$f" phase); [ -n "$p" ] && [ "$p" != null ] || p=none
    printf '%s %s %s %s\n' "$u" "$s" "$p" "$(agent_state "$u")" >> "$now"
  done
  for step in triage grill plan-check decompose; do
    u="$id-$step"
    a=$(agent_state "$u")
    # a step session nobody dispatched is not news; one that was live and is gone is
    [ "$a" != gone ] || [ -n "$(prior "$u" 4)" ] || continue
    printf '%s none none %s\n' "$u" "$a" >> "$now"
  done
  sort -o "$now" "$now"

  while read -r u s p a; do
    for col in 2:status 3:phase 4:agent; do
      n=${col%%:*}; what=${col#*:}
      case "$n" in 2) new=$s ;; 3) new=$p ;; 4) new=$a ;; esac
      old=$(prior "$u" "$n")
      [ "$new" != "$old" ] || continue
      [ "$what" = agent ] || [ "$new" != none ] || continue
      if [ -z "$old" ]; then
        printf '%s %s %s\n' "$u" "$what" "$new"
      else
        printf '%s %s %s -> %s\n' "$u" "$what" "$old" "$new"
      fi
    done
  done < "$now"

  mkdir -p "$harness"
  mv "$now" "$seen"
}

if [ -n "$once" ]; then
  pass
  exit 0
fi
while :; do
  pass
  sleep "$interval"
done
