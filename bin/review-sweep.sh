#!/bin/sh
# The catch-up of `mr-watch.sh --finish` for the time no session watched: every live parent in `review` with an
# `mr_url` gets one `mr-watch.sh <T-NNN> --once --finish --task-mr-only` pass, one forge call for its task MR, so a task MR the human merged after its session
# ended closes the task, cleans up and archives it when the next session starts (session-start.sh runs this).
#
#   review-sweep.sh [--repo <key>] [--state <dir>]
#
# Prints only what the passes finished: `<T-NNN> done`, `<T-NNN> skipped: <what> <reason>`,
# `<T-NNN> push-failed`, `<T-NNN> finish-failed <reason>` and `<T-NNN> closed-unmerged`; a task MR still open
# prints nothing. A parent whose task MR mr-watch.sh already recorded closed-unmerged is not asked again. A forge that does not answer is no error.
# Exit 0 always, except exit 1 with the reason on stderr for an unknown argument or a state dir with no repos/.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'review-sweep: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

key='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; key=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
[ -n "$state" ] || state=${WORK_DIR:-}/state
[ -d "$state/repos" ] || die "$state has no repos/, pass --state <the state clone>"
# see: mr-watch.sh, the factory root its harness files live under
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac

for f in $(task_files $key); do
  { IFS= read -r t_id || :; IFS= read -r t_status || :; IFS= read -r t_url || :; } <<EOT
$(task_fields "$f" id status mr_url)
EOT
  is_parent_id "$t_id" && [ "$t_status" = review ] || continue
  case "$t_url" in null|'~'|'') continue ;; esac
  t_key=${f#"$state/repos/"}; t_key=${t_key%%/*}
  awk -v i="$t_id" '$1 == i && $2 == "closed-unmerged" { f = 1 } END { exit !f }' \
    "$root/$t_key/.harness/$t_id/mr-watch.state" 2>/dev/null && continue
  sh "$bin/mr-watch.sh" "$t_id" --once --finish --task-mr-only --state "$state" 2>/dev/null </dev/null \
    | grep -E "^$t_id (done|skipped:|push-failed|finish-failed|closed-unmerged)" || :
done
exit 0
