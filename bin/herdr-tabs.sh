#!/bin/sh
# The one owner of the tab record, `<root>/<key>/.harness/<T-NNN>/herdr-tabs`: one `<unit> <tab_id> <pane_id>`
# line per tab session-monitor.sh created in herdr. The file is only ever appended to and the last line of a
# unit wins, so every writer appends without a lock.
#
#   herdr-tabs.sh name <unit> [--state <dir>]
#   herdr-tabs.sh record <unit> <tab_id> <pane_id> [--state <dir>]
#
# A unit is a task or block id (`T-NNN`, `T-NNN-NN`) or a parent-level step (`T-NNN-<step>`); its T-NNN names
# the record and its task file names the repo key. `name` prints the session name `<emoji> <key> <unit>`, the
# tab label and the `claude --name` of the unit: the emoji is the repo's `emoji:` in repos.yml, and without one
# a fixed pick out of sixteen by the `cksum` of the key, so a repo keeps its emoji from run to run.
#
# Exit 0 on success, 1 with the reason on stderr on bad usage or a unit that resolves to no task file.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'herdr-tabs: %s\n' "$1" >&2; exit 1; }
usage='usage: herdr-tabs.sh name <unit> | record <unit> <tab_id> <pane_id> [--state <dir>]'

verb='' unit='' tab='' pane='' state='' n=0
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *)
      n=$((n + 1))
      case "$n" in 1) verb=$1 ;; 2) unit=$1 ;; 3) tab=$1 ;; 4) pane=$1 ;; *) die "$usage" ;; esac
      shift ;;
  esac
done
case "$verb $n" in
  'name 2'|'record 4') ;;
  *) die "$usage" ;;
esac

case "$unit" in
  T-[0-9][0-9][0-9]|T-[0-9][0-9][0-9]-[0-9][0-9]) tid=$unit ;;
  T-[0-9][0-9][0-9]-[a-z]*) tid=${unit%%-[a-z]*} ;;
  *) die "'$unit' is not a task, block or step id" ;;
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

task=$(task_of "$tid" || :)
[ -n "$task" ] || die "$unit resolves to no task file under $state/repos/*/tasks"
key=${task#"$state/repos/"}
key=${key%%/*}
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac

case "$verb" in
  name)
    emoji=$(yml_field "$key" emoji)
    if [ -z "$emoji" ]; then
      sum=$(printf '%s' "$key" | cksum | cut -d' ' -f1)
      emoji=$(printf '%s\n' 🦊 🐙 🦉 🐝 🐢 🦀 🐳 🦋 🌵 🍄 🌻 🍋 🔥 🌊 🪐 🎲 | sed -n "$((sum % 16 + 1))p")
    fi
    printf '%s %s %s\n' "$emoji" "$key" "$unit" ;;
  record)
    dir="$root/$key/.harness/${tid%-[0-9][0-9]}"
    mkdir -p "$dir"
    printf '%s %s %s\n' "$unit" "$tab" "$pane" >> "$dir/herdr-tabs" ;;
esac
