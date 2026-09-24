#!/bin/sh
# The human approval gate of a task, and in the standalone posture (ADR-0050) the whole of it: `<from> → ready`
# as two commits, so plan_hash pins exactly the body a human approved, the first commit flips the status (and
# bumps `attempt` from failed, sets `phase: implement` from tests_ready), the second
# writes the SHA of that commit into plan_hash. Both commits are then pushed with state_push (lib-tasks.sh), the
# retry task-done.sh uses; a clone with no origin stays local (T-228 D2).
#
#   task-approve.sh <id> [--state <dir>]      cwd = the state clone unless --state
#
# Exit 2 when both commits landed but the push to the state root did not.
# Exit 1 with the reason when the task is `in_progress`; nothing written. Every other status may be approved to
# ready: `ready` is reachable from all of them, from `in_progress` it is not, and that includes the
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
[ -d "$state/.git" ] || die "$state is not a state clone, run from one or pass --state <dir>"

# setf (Frontmatter.SetField) and state_commit are shared with task-new.sh and state-report.sh
. "$(dirname -- "$0")/lib-tasks.sh"

task=$(grep -lx "id: $id" "$state"/repos/*/tasks/*.md 2>/dev/null | head -n1)
[ -n "${task:-}" ] && [ -f "$task" ] || die "no task file with 'id: $id' in $state/repos/*/tasks/"
rel=${task#"$state/"}

# T-248: the status read, both commits and the push under the one lock per state clone (state_lock, lib-tasks.sh)
state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
  *) die "the state lock could not be taken in $state; is it a git clone?" ;;
esac

from=$(sed -n 's/^status:[[:space:]]*//p' "$task" | head -n1)
case "$from" in
  draft|triaged|ready|claimed|tests_ready|review|blocked|failed|done|closed) ;;
  *) die "task $id is '$from': in_progress cannot be approved to ready" ;;
esac

# E (2026-09-22, MR !412): approving is the last gate before the body is frozen - plan_hash pins exactly this
# text, and the `# Goal` line in it is the MR title mr-open.sh will use. A goal that cannot be a title was
# caught at the forge until now, after the human had approved it; it is caught here, before anything is
# written. Triage and research goals never become titles.
arch=$(sed -n 's/^archetype:[[:space:]]*//p' "$task" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
key=$(sed -n 's/^repo:[[:space:]]*//p' "$task" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
case "$arch" in
  triage|research) ;;
  *)
    goal=$(awk '/^#+[[:space:]]*Goal[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$task")
    [ -n "$goal" ] || die "task $id has no '# Goal' line, and it is the MR title"
    reason=$(mr_title_check "$goal" "$key") || die "task $id cannot be approved: the '# Goal' line cannot be an MR title: $reason; fix it in $task"
    ;;
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

state_push "$state" \
  || { printf 'task-approve: the push to the state root failed 3 times: %s is ready in %s but not pushed\n' "$id" "$state" >&2; exit 2; }
