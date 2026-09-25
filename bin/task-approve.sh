#!/bin/sh
# The human approval gate of a task, and in the standalone posture (ADR-0050) the whole of it: `<from> → ready`
# for every id given, under one state lock and in one commit (PLAN 3.5, fewer commits), so the CEO's plan approval
# of a request is one call. The commit flips the status (and bumps `attempt` from failed, sets `phase: implement`
# from tests_ready) and writes plan_hash, the SHA of the commit that already holds exactly the body the human
# approved: HEAD before the approval, since the approval only touches the frontmatter. A task file whose body is
# not committed yet (edited by hand) is committed first, in one commit for all such files, and plan_hash pins
# that one. Nothing is pushed; state-push.sh publishes from the monitor pass and the CEO loop (DECISIONS D4).
#
#   task-approve.sh <id>... [--state <dir>]      cwd = the state clone unless --state
#
# Every id is checked before anything is written, in the order given, and the first one that cannot be approved
# stops the run with nothing written: an unknown or archived id, a task that is `in_progress` (every other status
# may be approved to ready: `ready` is reachable from all of them, from `in_progress` it is not, and that
# includes the refinement flip `review → ready` of ADR-0031, which a narrower set here would have refused), or a
# `# Goal` line that cannot be an MR title. An id given twice is approved once.
#
# A depends_on that is not done yet (neither done nor closed, nor archived) is a warning on stderr per edge, and
# the approval goes on: the queue (queue-next.sh) starts the parent once it is done. An edge between two blocks
# of one parent is the cut's own order and no warning.
#
# Prints `<id> ready <plan_hash>` per id. Exit 0 = approved; 1 = refused, the reason on stderr, nothing written;
# 2 = written but git refused the commit.
set -eu

ids='' state=''
die() { printf 'task-approve: %s\n' "$1" >&2; exit 1; }
usage='usage: task-approve.sh <id>... [--state <dir>]'

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'; $usage" ;;
    *) ids="$ids $1"; shift ;;
  esac
done
[ -n "$ids" ] || die "$usage"
[ -n "$state" ] || state=$(pwd)
[ -d "$state/.git" ] || die "$state is not a state clone, run from one or pass --state <dir>"

# setf (Frontmatter.SetField), state_commit, task_of and task_fields are shared with task-new.sh and state-report.sh
. "$(dirname -- "$0")/lib-tasks.sh"

# T-248: the reads, the writes and the commit under the one lock per state clone (state_lock, lib-tasks.sh)
state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
  *) die "the state lock could not be taken in $state; is it a git clone?" ;;
esac

stop() { die "$1; nothing was approved"; }
family() { if is_block_id "$1"; then printf '%s' "${1%-*}"; else printf '%s' "$1"; fi; }

# every id checked before anything is written; `<id> <path relative to the state>` per approved id
todo='' seen=' '
for id in $ids; do
  case "$seen" in *" $id "*) continue ;; esac
  seen="$seen$id "
  is_task_id "$id" || stop "'$id' is not a task id"
  task=$(task_of "$id")
  [ -n "$task" ] || stop "no task file with 'id: $id' in $state/repos/*/tasks"
  case "$task" in */archive/*) stop "task $id is archived ($task), a finished task is not approved again" ;; esac

  from=$(task_fields "$task" status)
  case "$from" in
    draft|triaged|ready|claimed|tests_ready|review|blocked|failed|done|closed) ;;
    *) stop "task $id is '$from': in_progress cannot be approved to ready" ;;
  esac

  # E (2026-09-22, MR !412): approving is the last gate before the body is frozen - plan_hash pins exactly this
  # text, and the `# Goal` line in it is the MR title mr-open.sh will use. A goal that cannot be a title was
  # caught at the forge until now, after the human had approved it; it is caught here, before anything is
  # written. Triage and research goals never become titles.
  { IFS= read -r arch; IFS= read -r key; } <<EOF
$(task_fields "$task" archetype repo)
EOF
  case "$arch" in
    triage|research) ;;
    *)
      goal=$(awk '/^#+[[:space:]]*Goal[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$task")
      [ -n "$goal" ] || stop "task $id has no '# Goal' line, and it is the MR title"
      reason=$(mr_title_check "$goal" "$key") || stop "task $id cannot be approved: the '# Goal' line cannot be an MR title: $reason; fix it in $task"
      ;;
  esac
  todo="$todo$id ${task#"$state/"}
"
done

set --
while read -r id rel; do [ -z "$id" ] || set -- "$@" "$rel"; done <<EOF
$todo
EOF
list=$(printf '%s' "$todo" | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')
if [ "$#" = 1 ]; then scope=$list; else scope=approve; fi

# a body not committed yet gets its own commit first, so that a commit holds exactly what the human read
dirty=''
for rel; do [ -z "$(git -C "$state" status --porcelain -- "$rel")" ] || dirty="$dirty $rel"; done
if [ -n "$dirty" ]; then
  # shellcheck disable=SC2086 # the relative paths of the state layout carry no blank
  state_commit "$state" "chore($scope): the body as approved" $dirty \
    || { printf 'task-approve: git refused the commit of the approved body in %s\n' "$state" >&2; exit 2; }
fi
hash=$(git -C "$state" rev-parse HEAD)

body=''
while read -r id rel; do
  [ -n "$id" ] || continue
  task="$state/$rel"
  from=$(task_fields "$task" status)
  setf "$task" status ready
  if [ "$from" = failed ]; then
    attempt=$(task_fields "$task" attempt)
    case "${attempt:-}" in ''|*[!0-9]*) attempt=0 ;; esac
    setf "$task" attempt "$((attempt + 1))"
  fi
  if [ "$from" = tests_ready ]; then setf "$task" phase implement; fi
  setf "$task" plan_hash "$hash"
  body="$body$id: $from → ready
"
done <<EOF
$todo
EOF

if [ "$#" = 1 ]; then subject="chore($list): plan_hash of the approved body"
else subject="chore(approve): $list ready, plan_hash of the approved bodies"; fi
state_commit "$state" "$subject

$body" "$@" \
  || { printf 'task-approve: git refused the commit in %s: %s written but not committed\n' "$state" "$list" >&2; exit 2; }

# a warning per depends_on that is not done yet; the queue waits for it, the approval does not
while read -r id rel; do
  [ -n "$id" ] || continue
  for dep in $(task_fields "$state/$rel" depends_on | tr '[],"'"'" '    '); do
    [ "$(family "$dep")" != "$(family "$id")" ] || continue
    df=$(task_of "$dep")
    if [ -z "$df" ]; then
      printf 'task-approve: warning: %s depends on %s, which has no task file; it waits until that is done\n' "$id" "$dep" >&2
      continue
    fi
    case "$df" in */archive/*) continue ;; esac
    ds=$(task_fields "$df" status)
    case "$ds" in done|closed) ;; *)
      printf 'task-approve: warning: %s depends on %s, which is %s; it waits until that is done\n' "$id" "$dep" "$ds" >&2 ;;
    esac
  done
  printf '%s ready %s\n' "$id" "$hash"
done <<EOF
$todo
EOF
