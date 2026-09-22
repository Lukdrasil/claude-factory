#!/bin/sh
# The human approval gate of a task, and in the standalone posture (ADR-0050) the whole of it: `<from> → ready`
# as two commits, so plan_hash pins exactly the body a human approved — the first commit flips the status (and
# bumps `attempt` from failed, sets `phase: implement` from tests_ready, as StateRepository does), the second
# writes the SHA of that commit into plan_hash. Nothing is pushed.
#
#   task-approve.sh <id> [--state <dir>]      cwd = the state clone unless --state
#
# Exit 1 with the reason when the task is `in_progress`; nothing written. Every other status may be approved to
# ready — TaskTransitions.Allowed offers `ready` from all of them, `in_progress` from none, and that includes the
# refinement flip `review → ready` of ADR-0031, which a narrower set here would have refused.
set -eu

id='' state=''
die() { printf 'task-approve: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one task id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: task-approve.sh <id> [--state <dir>]"
[ -n "$state" ] || state=$(pwd)
[ -d "$state/.git" ] || die "$state is not a state clone — run from one or pass --state <dir>"

# setf (Frontmatter.SetField) and state_commit are shared with task-new.sh and state-report.sh
. "$(dirname -- "$0")/lib-tasks.sh"

task=$(grep -lx "id: $id" "$state"/repos/*/tasks/*.md 2>/dev/null | head -n1)
[ -n "${task:-}" ] && [ -f "$task" ] || die "no task file with 'id: $id' in $state/repos/*/tasks/"
rel=${task#"$state/"}

from=$(sed -n 's/^status:[[:space:]]*//p' "$task" | head -n1)
case "$from" in
  draft|triaged|ready|claimed|tests_ready|review|blocked|stalled|failed|done|closed) ;;
  *) die "task $id is '$from' — in_progress cannot be approved to ready (TaskTransitions.Allowed)" ;;
esac

setf "$task" status ready
if [ "$from" = failed ]; then
  attempt=$(sed -n 's/^attempt:[[:space:]]*//p' "$task" | head -n1)
  case "${attempt:-}" in ''|*[!0-9]*) attempt=0 ;; esac
  setf "$task" attempt "$((attempt + 1))"
fi
if [ "$from" = tests_ready ]; then setf "$task" phase implement; fi
state_commit "$state" "chore($id): $from → ready" "$rel"

hash=$(git -C "$state" log -1 --format=%H -- "$rel")
setf "$task" plan_hash "$hash"
state_commit "$state" "chore($id): plan_hash of the approved body" "$rel"
