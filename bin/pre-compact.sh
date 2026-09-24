#!/bin/sh
# PreCompact hook: the progress snapshot of every task this session owns reaches the state root before the context
# is compacted, so a compact never loses what the session had already written down. Standalone (ADR-0050) the
# tasks are the ones in $WORK_DIR/state whose `owner:` ends in this session's id, each reported from its own work
# dir $WORK_DIR/<key>/<id>. Through state-report.sh --no-status: a status is not this hook's business, only the snapshot. Never blocks: exit 0 always.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$bin/lib-tasks.sh"
stdin=$(cat)
sid=$(hook_field "$stdin" session_id)

report() { # <id> <work dir>
  if [ ! -d "$2" ]; then printf 'pre-compact: %s skipped, no work dir %s\n' "$1" "$2" >&2; return 0; fi
  if err=$(cd "$2" && sh "$bin/state-report.sh" --task "$1" --no-status --message "precompact: $1" 2>&1 >/dev/null); then
    printf 'pre-compact: %s reported\n' "$1" >&2
  else
    printf 'pre-compact: %s not reported: %s\n' "$1" "$(printf '%s\n' "$err" | tail -n1)" >&2
  fi
}

[ -n "$sid" ] && [ -d "${WORK_DIR:-}/state" ] || exit 0
state=$WORK_DIR/state
for id in $(owned_task_ids "$sid"); do
  task=$(task_of "$id")
  [ -n "$task" ] || continue
  rest=${task#"$state/repos/"}
  dir="$WORK_DIR/${rest%%/*}/$id"
  # why: a coordinator (ADR-0049) owns its parent task from the registered clone itself and never gets a work dir
  # $WORK_DIR/<key>/<id>; without this its snapshot is skipped for a work dir that does not exist.
  if [ ! -d "$dir" ] && resolve_session_layout "$PWD" "$id" && [ "$LO_POSTURE" = standalone ] && [ -d "$LO_OWN" ]; then
    dir=$LO_OWN
  fi
  report "$id" "$dir"
done
exit 0
