#!/bin/sh
# The watcher of `factory herd` (skills/factory/references/herd.md): it reads the parent, its blocks and the
# herdr agents dispatched for them, and prints one line per change since its last run, so the monitor session
# learns what the spawned sessions did without reading any of their output.
#
#   herd-watch.sh <T-NNN> [--once] [--interval <s>] [--no-mr] [--state <dir>]
#
# The lines are `<id> status <old> -> <new>`, `<id> phase <old> -> <new>`, `<id> agent <old> -> <new>` and
# `<id> mr <old> -> <new>`, with a first sighting written without the arrow, plus `<id> waits <ask>` below. The
# agent states are `working`, `blocked` and `unknown` as herdr reads them, `ready` for herdr's idle and done
# alike (done only means the human has not looked at the tab yet), `closed` for a unit whose recorded tab
# herdr-tabs.sh closed, and `gone` for a unit no live agent carries, which is how a session that ended on its
# own reads. What has already been reported is kept in
# `<root>/<key>/.harness/<T-NNN>/herd-watch-<FACTORY_UNIT>.state` (`herd-watch.state` without FACTORY_UNIT), one
# `<id> <status> <phase> <agent> <mr> <ask>` per line, so a pass with nothing new prints nothing. One file per
# watcher: the CEO's (`ceo`) and the lead's (`<T-id>-lead`) watchers of one parent would otherwise each consume
# the other's transitions.
#
# The agent column comes from one `herdr agent list` per pass, through `herdr-tabs.sh agents`: a unit is the
# agent that reports its recorded session id, or the one in its recorded pane (plan 3.7), never an `agent get`
# per unit. A unit with no tab record reads `gone`, and a pass herdr does not answer reads `unknown`.
#
# A step unit that reads `ready` with an open ask of the Factory UI (`<UI home>/sessions/<sid>/asks/*.md` with
# `status: open`, the session being the agent's own, or with none reported the one whose session.md names the
# pane) waits on the human: the first pass that sees that ask prints `<id> waits <ask>`, and every pass while
# it waits runs `notify.sh`, which shows it once and again only while the tab stays unseen.
#
# A unit whose agent turns `gone` or `closed`, or whose status turns `done`, has its capacity leases released
# (`capacity.sh release <id>`, plan 3.3), so a slot frees in the pass that sees the session end. The parent's own
# agent is the exception: its release would drop its lead's repo-lead lease too, so its session leases are left
# to `capacity.sh sweep`, which drops a unit lease no live agent carries.
#
# The lead's unit `<T-id>-lead` that turns `gone` from a live state also has its tab record closed through
# `herdr-tabs.sh close`, which appends `<T-id>-lead <tab_id> closed` once herdr no longer has the tab or it
# closed it: queue-next.sh then offers the parent to a new lead. A lead that turns `gone` from `closed` is one
# dispatched again whose agent is not up yet, and keeps its record.
#
# why: on 2026-09-22 the monitors that ran stopped at `review` and missed the merges and a `need_rebase`. A
# task is not over at `review`, so every pass also runs `mr-watch.sh <T-NNN> --once` - which is what retargets
# the stack and sets a merged block `done` - and turns its state file into the `<id> mr <old> -> <new>` lines
# above, in this watcher's own vocabulary. mr-watch's own stdout is not passed through, so a merge is one line
# and not two. `--no-mr` leaves the forge alone, for a repo that has none.
#
# After mr-watch every pass runs `herdr-tabs.sh sweep <T-NNN>`, which closes the recorded tab of each unit that
# is `done` or `closed`, a step by its parent's status, and the lead's workspace once the parent is. Its stdout is dropped: the `<id> agent <old> -> closed`
# line of that pass is how the monitor learns of the close.
#
# The units are the parent, every block of it, and the parent-level step sessions
# `<T-id>-<triage|chart|grill|plan-check|decompose|lead>` that session-monitor.sh --step dispatches. A step
# session is tracked from the first pass that sees it live; a block with no live agent is still tracked for its
# status, because that is what the session writes through state-report.sh.
#
# Without `--once` the pass repeats every 60 seconds, `--interval <s>` sets another period, and the monitor
# arms the loop through the Monitor tool the way it arms mr-watch.sh. The sleep stays until herdr is updated
# past 0.8.2, whose `events.subscribe` replays history; then a subscription wakes the pass instead (plan 3.7).
#
# Exit 0 after a pass. Exit 1 with the reason on stderr when no parent id is given, when the id is not of the
# shape T-NNN, or when it resolves to no task file.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'herd-watch: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

id='' once='' interval=60 state='' nomr=''
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1; shift ;;
    --no-mr) nomr=1; shift ;;
    --interval) [ $# -ge 2 ] || die "--interval needs a value"; interval=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one parent id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: herd-watch.sh <T-NNN> [--once] [--interval <s>] [--no-mr] [--state <dir>]"
is_parent_id "$id" || die "'$id' is not a parent task id of the shape T-NNN"
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
[ -n "$task" ] || die "$id resolves to no task file in the live tasks or the archive of $state"
key=${task#"$state/repos/"}
key=${key%%/*}
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac
harness="$root/$key/.harness/$id"
seen="$harness/herd-watch${FACTORY_UNIT:+-$FACTORY_UNIT}.state"
mrseen="$harness/mr-watch.state"
ui=${FACTORY_UI_HOME:-$HOME/.claude-factory/ui}
# an archived parent is still watched to its end, its blocks with it
all=''
case "$task" in */archive/*) all=--all ;; esac

field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }

# the agent state of one unit from this pass's `herdr-tabs.sh agents` lines in $agents
agent_state() { # <unit id>
  st=$(printf '%s\n' "$agents" | awk -v u="$1" '$1 == u { print $2; exit }')
  case "$st" in
    idle|done) printf 'ready' ;;
    working|blocked|unknown|closed) printf '%s' "$st" ;;
    ''|gone) printf 'gone' ;;
    *) printf 'unknown' ;;
  esac
}

# the newest open ask of a unit's session, `<ask> <ask file>`, or nothing
open_ask() { # <unit id>
  set -- $(printf '%s\n' "$agents" | awk -v u="$1" '$1 == u { print $3, $4; exit }')
  [ $# -eq 2 ] || return 0
  if [ "$2" != - ]; then
    set -- "$ui/sessions/$2"
  else
    set -- $(grep -lx "pane: $1" "$ui"/sessions/*/session.md 2>/dev/null | sed 's|/session\.md$||')
  fi
  for d; do
    for a in $(ls -t "$d"/asks/*.md 2>/dev/null); do
      awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
        /^status:[ \t]*open[ \t]*$/ { o = 1; exit } END { exit !o }' "$a" || continue
      a2=${a##*/}
      printf '%s %s\n' "${a2%.md}" "$a"
      return 0
    done
  done
}

# notify.sh for one ask: its first question, and its page URL the way ui-ask.sh prints it
notify_ask() { # <unit id> <ask file>
  question=$(awk 'NR == 1 && $0 == "---" { fm = 1; next } fm { if ($0 == "---") fm = 0; next }
    /^❓ / { q = $0; exit } f == "" && NF { f = $0 } END { print (q != "" ? q : f) }' "$2" \
    | sed 's/^❓ //; s/\*\*//g')
  sid=${2%/asks/*}; sid=${sid##*/}
  ask=${2##*/}; ask=${ask%.md}
  port=$(cat "$ui/port" 2>/dev/null || :)
  token=$(cat "$ui/token" 2>/dev/null || :)
  url="http://127.0.0.1:${port:-7171}/?ask=$sid/$ask${token:+#token=$token}"
  label=$(sh "$bin/herdr-tabs.sh" name "$1" --state "$state" 2>/dev/null) || label=$1
  sh "$bin/notify.sh" "$1" "$label" "$question" "$url" --state "$state" >/dev/null 2>&1 || :
}

# the forge state of one block, as mr-watch.sh last recorded it: `<block> <state> <comment count>`
mr_state() { # <unit id>
  [ -f "$mrseen" ] || { printf 'none'; return 0; }
  mw=$(awk -v u="$1" '$1 == u { print $2; exit }' "$mrseen")
  printf '%s' "${mw:-none}"
}

prior() { # <unit id> <column: 2 status | 3 phase | 4 agent | 5 mr | 6 ask>
  [ -f "$seen" ] || return 0
  awk -v u="$1" -v c="$2" '$1 == u { print $c; exit }' "$seen"
}

pass() {
  # the forge first, so the mr column of this pass is the one mr-watch just wrote; a watcher that cannot reach
  # the forge is not a failed pass, the task columns are still news
  [ -n "$nomr" ] || sh "$bin/mr-watch.sh" "$id" --once --state "$state" >/dev/null || :
  sh "$bin/herdr-tabs.sh" sweep "$id" --state "$state" >/dev/null || :
  # a record that cannot be read is no pass: every unit would read gone and lose its leases
  agents=$(sh "$bin/herdr-tabs.sh" agents "$id" --state "$state" 2>/dev/null) || return 0
  now=$(mktemp)
  : > "$now.asks"
  for f in $(task_files $all "$key"); do
    u=$(field "$f" id)
    [ "$u" = "$id" ] || is_block_of "$id" "$u" || continue
    s=$(field "$f" status); [ -n "$s" ] || s=none
    p=$(field "$f" phase); [ -n "$p" ] && [ "$p" != null ] || p=none
    printf '%s %s %s %s %s none\n' "$u" "$s" "$p" "$(agent_state "$u")" "$(mr_state "$u")" >> "$now"
  done
  for step in triage chart grill plan-check decompose lead; do
    u="$id-$step"
    a=$(agent_state "$u")
    # a step session nobody dispatched is not news; one that was live and is gone is
    [ "$a" != gone ] || [ -n "$(prior "$u" 4)" ] || continue
    w=none
    if [ "$a" = ready ]; then
      ask=$(open_ask "$u")
      if [ -n "$ask" ]; then w=${ask%% *}; printf '%s %s\n' "$u" "${ask#* }" >> "$now.asks"; fi
    fi
    printf '%s none none %s none %s\n' "$u" "$a" "$w" >> "$now"
  done
  sort_ids < "$now" > "$now.sorted"
  mv -f "$now.sorted" "$now"

  while read -r u s p a m w; do
    for col in 2:status 3:phase 4:agent 5:mr; do
      n=${col%%:*}; what=${col#*:}
      case "$n" in 2) new=$s ;; 3) new=$p ;; 4) new=$a ;; 5) new=${m:-none} ;; esac
      old=$(prior "$u" "$n")
      [ "$new" != "$old" ] || continue
      # the parent's own agent never releases: `release <T-id>` also drops the repo-lead lease of its lead
      release=''
      case "$what $new" in
        'agent gone'|'agent closed') [ "$u" = "$id" ] || release=1 ;;
        'status done') release=1 ;;
      esac
      [ -z "$release" ] || sh "$bin/capacity.sh" release "$u" --state "$state" >/dev/null 2>&1 || :
      if [ "$u $what $new" = "$id-lead agent gone" ] && [ "$old" != closed ]; then
        sh "$bin/herdr-tabs.sh" close "$u" --state "$state" >/dev/null 2>&1 || :
      fi
      [ "$what" = agent ] || [ "$new" != none ] || continue
      if [ -z "$old" ]; then
        printf '%s %s %s\n' "$u" "$what" "$new"
      else
        printf '%s %s %s -> %s\n' "$u" "$what" "$old" "$new"
      fi
    done
    [ "${w:-none}" = none ] || [ "$w" = "$(prior "$u" 6)" ] || printf '%s waits %s\n' "$u" "$w"
  done < "$now"

  mkdir -p "$harness"
  mv "$now" "$seen"
  while read -r u f; do notify_ask "$u" "$f"; done < "$now.asks"
  rm -f "$now.asks"
}

if [ -n "$once" ]; then
  pass
  exit 0
fi
while :; do
  pass
  sleep "$interval"
done
