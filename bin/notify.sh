#!/bin/sh
# Tells the human that a unit waits on an answer (plan 3.7): `herdr notification show "<label> waits" --body
# "<question> <url>" --sound request`, with `tab <label>` in place of the URL when there is none. herd-watch.sh
# runs it on every pass while a step unit waits, with the unit's session name as the label, the ask's first
# question and its page URL.
#
#   notify.sh <unit> <label> <question> [<url>] [--state <dir>]
#
# Once per ask: the ask is the `cksum` of the question, and a notification herdr showed leaves the stamp
# `<root>/<key>/.harness/<T-id>/notified-<unit>-<ask>`. A call for a stamped ask shows it again only while the
# unit's recorded pane still reads `done` in herdr, which means the human has not looked at the tab since, and
# the stamp is older than 15 minutes; the reminder renews the stamp. A notification herdr does not show
# (`disabled`, `rate_limited`, `no_foreground_client`, `busy`) leaves no stamp, so the next call tries again, and
# its reason goes to stderr. herdr caps the body at 240 characters, so the question is cut to keep the URL whole.
# A `#token=` fragment of the URL is dropped: herdr keeps the body in its notification store and the desktop
# history, and the UI token does not belong there.
#
# Exit 0 whether or not herdr showed it, and without herdr on PATH. Exit 1 with the reason on stderr on bad
# usage or a unit that resolves to no task file.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'notify: %s\n' "$1" >&2; exit 1; }
usage='usage: notify.sh <unit> <label> <question> [<url>] [--state <dir>]'

state='' n=0 unit='' label='' question='' url=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    *)
      n=$((n + 1))
      case $n in 1) unit=$1 ;; 2) label=$1 ;; 3) question=$1 ;; 4) url=$1 ;; *) die "$usage" ;; esac
      shift ;;
  esac
done
[ "$n" -ge 3 ] && [ -n "$unit" ] && [ -n "$label" ] || die "$usage"

# see: herdr-tabs.sh, the same state and record resolution
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
case "$unit" in
  *-[a-z]*) tid=${unit%%-[a-z]*}; is_parent_id "$tid" ;;
  *) tid=$unit; is_task_id "$tid" ;;
esac || die "'$unit' is not a task, block or step id"
task=$(task_of "$tid" || :)
[ -n "$task" ] || die "$unit resolves to no task file in $state"
key=${task#"$state/repos/"}
key=${key%%/*}
parent=$tid
if is_block_id "$tid"; then parent=${tid%-*}; fi
dir="$root/$key/.harness/$parent"

command -v herdr >/dev/null 2>&1 || exit 0

question=$(printf '%s' "$question" | tr '\n' ' ')
ask=$(printf '%s' "$question" | cksum | cut -d' ' -f1)
stamp="$dir/notified-$unit-$ask"
if [ -f "$stamp" ]; then
  [ -n "$(find "$stamp" -mmin +15)" ] || exit 0
  pane=$(awk -v u="$unit" '$1 == u { p = $3 } END { print p }' "$dir/herdr-tabs" 2>/dev/null || :)
  case "$pane" in ''|closed) exit 0 ;; esac
  herdr agent get "$pane" 2>/dev/null | grep -q '"agent_status":"done"' || exit 0
fi

url=${url%%#token=*}
where=${url:-tab $label}
room=$((239 - ${#where}))
question=$(printf '%s\n' "$question" | awk -v n="$room" '{ print (length($0) > n ? substr($0, 1, n - 3) "..." : $0) }')
reply=$(herdr notification show "$label waits" --body "$question $where" --sound request 2>&1) || :
case "$reply" in
  *'"shown":true'*) mkdir -p "$dir"; touch "$stamp" ;;
  *)
    reason=$(printf '%s' "$reply" | sed -n 's/.*"reason":"\([^"]*\)".*/\1/p; s/.*"code":"\([^"]*\)".*/\1/p' | head -n1)
    printf 'notify: %s waits, not shown (%s)\n' "$unit" "${reason:-no answer}" >&2 ;;
esac
