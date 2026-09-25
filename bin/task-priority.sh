#!/bin/sh
# The one writer of `priority:`: sets it on a parent and cascades it to every block of the parent, in one commit
# under the state lock (state_write, lib-tasks.sh), never pushed (state-push.sh publishes). The priority orders the
# queue (queue-next.sh) and stops nothing that is already running.
#
#   task-priority.sh <T-id> <P0|P1|P2|P3> [--state <dir>]
#
# Only a parent takes a priority: a block always carries its parent's. An archived task is history and is refused.
# The same priority again commits nothing. Prints `<id> <priority>` for the parent and each block.
#
# Exit 0 = set, or already set; 1 = refused (usage, a value outside P0 to P3, a block, an unknown or archived id),
# nothing written; 2 = not written or not committed (the state lock was held longer than STATE_LOCK_WAIT seconds,
# default 30, or git refused the commit).
set -eu

id='' prio='' state='' n=0
die() { printf 'task-priority: %s\n' "$1" >&2; exit 1; }
die2() { printf 'task-priority: %s\n' "$1" >&2; exit 2; }
usage='usage: task-priority.sh <T-id> <P0|P1|P2|P3> [--state <dir>]'

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'; $usage" ;;
    *) case "$n" in 0) id=$1 ;; 1) prio=$1 ;; *) die "$usage" ;; esac; n=$((n + 1)); shift ;;
  esac
done
[ "$n" = 2 ] || die "$usage"
case "$prio" in P0|P1|P2|P3) ;; *) die "the priority is one of P0 P1 P2 P3, not '$prio'" ;; esac

. "$(dirname -- "$0")/lib-tasks.sh"

is_block_id "$id" && die "$id is a block, it carries the priority of its parent ${id%-*}: set it there"
is_parent_id "$id" || die "'$id' is not a parent task id"

if [ -z "$state" ]; then state=$(resolve_state_dir "$PWD"); fi
state=$(git -C "$state" rev-parse --show-toplevel 2>/dev/null) || die "$state is not a state clone, pass --state <dir>"

state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die2 "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
  *) die2 "the state lock could not be taken in $state, is it a git clone?" ;;
esac

task=$(task_of "$id")
[ -n "$task" ] || die "no task file with 'id: $id' in $state"
case "$task" in */archive/*) die "$id is archived ($task), its priority stays as it finished" ;; esac
key=${task#"$state/repos/"}
key=${key%%/*}

# the parent first, then its blocks, found by their `id:` line: a file name is only a hint (T-ECS-10-x.md is no
# block of T-ECS-1)
set -- "$task"
while IFS= read -r f; do
  [ -n "$f" ] && [ "$f" != "$task" ] || continue
  is_block_of "$id" "$(task_fields "$f" id)" && set -- "$@" "$f"
done <<EOF
$(task_files "$key")
EOF

for f in "$@"; do
  [ "$(task_fields "$f" priority)" = "$prio" ] || setf "$f" priority "$prio"
done
for f; do shift; set -- "$@" "${f#"$state"/}"; done
state_write "$state" "chore($id): priority $prio" "$@" || die2 "git refused the commit in $state; the priority is written but not committed"
for f; do printf '%s %s\n' "$(task_fields "$state/$f" id)" "$prio"; done
