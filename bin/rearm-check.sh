#!/bin/sh
# Stop hook: the monitor of `factory herd` must not go idle with a herd unwatched. It keeps one
# `herd-watch.sh <T-id>` per herd armed through the Monitor tool; a Monitor expires after at most 30 minutes and a
# restarted Claude has none, so at every Stop this hook looks at the hook's `background_tasks` and, when a herd of
# this session has no entry naming herd-watch.sh with its id, exits 2 with one `<T-id> <repo> <status>` line per
# unwatched herd. An entry of any type counts (the harness reports a Monitor task as `local_bash`), unless its
# `status` says it finished (completed, failed, killed, stopped).
#
# The herds of this session are the parents whose `<WORK_DIR>/<key>/.harness/<T-id>/herd-monitor` holds this
# session's `$HERDR_TAB_ID`: session-monitor.sh writes it on a --task spawn from the monitor's own pane. A parent
# that is done, closed or archived is no herd any more. Outside herdr (no HERDR_TAB_ID) there is nothing to look
# at for herds.
#
# The solo lane has the same gap after step 16: a parent owned by this session (owner:
# `factory@<host>:<session_id>`) that is in `review` with an `mr_url` waits on the human's merge, and only an
# `mr-watch.sh <T-id> --finish` Monitor ends it on that merge. Such a parent with no unfinished entry naming
# herd-watch.sh, or mr-watch.sh with --finish, with its id is one more `<T-id> <repo> review` line, inside herdr
# or not; an mr-watch.sh without --finish (the one of step 11) would not end it, so it does not count. A parent
# whose task MR mr-watch.sh recorded closed-unmerged waits on the human, not on a watcher, and is left out.
#
# It writes no file of the state clone: its only file is its counter `.harness-rearm-<sid>` in the state clone's
# git dir (`git rev-parse --absolute-git-dir`), where no commit and no status sees it. Never when
# `stop_hook_active` is true, at most twice per session, and any error of its own lets the Stop through: a
# reminder, not a gate.
set -u

. "$(dirname -- "$0")/lib-tasks.sh"

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stdin=$(cat)

[ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ] || exit 0
state=$WORK_DIR/state

# line 1 the stop_hook_active flag, line 2 the session id, then the text of every unfinished entry naming
# herd-watch.sh or mr-watch.sh
parsed=$(printf '%s' "$stdin" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const h=JSON.parse(s);
const out=[h.stop_hook_active===true?"active":"idle",typeof h.session_id==="string"?h.session_id:""];
for(const t of Array.isArray(h.background_tasks)?h.background_tasks:[]){
  if(!t||/^(completed|failed|killed|stopped)$/.test(t.status||""))continue;
  const txt=((t.command||"")+" "+(t.description||"")).replace(/\s+/g," ");
  if(/(herd|mr)-watch\.sh/.test(txt))out.push(txt);
}
process.stdout.write(out.join("\n")+"\n")})' 2>/dev/null) || exit 0
[ "$(printf '%s\n' "$parsed" | sed -n 1p)" = idle ] || exit 0
sid=$(printf '%s\n' "$parsed" | sed -n 2p)
case "$sid" in ''|*[!A-Za-z0-9_.-]*) exit 0 ;; esac
watched=$(printf '%s\n' "$parsed" | sed 1,2d)

# watched when an entry names <script> and this id as a word of its own (T-CF-3 is not T-CF-30)
named() { # <id> <script regex>
  printf '%s\n' "$watched" | grep -E "$2" | grep -qE "(^|[^A-Za-z0-9-])$1([^A-Za-z0-9-]|\$)"
}

herds='' solo=''
[ -n "${HERDR_TAB_ID:-}" ] && for m in "$WORK_DIR"/*/.harness/T-*/herd-monitor; do
  [ -f "$m" ] || continue
  [ "$(head -n1 "$m")" = "$HERDR_TAB_ID" ] || continue
  id=$(basename -- "$(dirname -- "$m")")
  is_parent_id "$id" || continue
  f=$(task_of "$id" || :)
  [ -n "$f" ] || continue
  case "$f" in */archive/*) continue ;; esac
  status=$(task_fields "$f" status)
  case "$status" in done|closed) continue ;; esac
  ! named "$id" 'herd-watch\.sh' || continue
  key=${f#"$state"/repos/}; key=${key%%/*}
  herds="$herds$id $key $status
"
done

for id in $(owned_task_ids "$sid"); do
  is_parent_id "$id" || continue
  f=$(task_of "$id" || :)
  [ -n "$f" ] || continue
  case "$f" in */archive/*) continue ;; esac
  [ "$(task_fields "$f" status)" = review ] || continue
  case "$(task_fields "$f" mr_url)" in null|'~'|'') continue ;; esac
  ! named "$id" 'herd-watch\.sh|mr-watch\.sh.*--finish' || continue
  key=${f#"$state"/repos/}; key=${key%%/*}
  ! awk -v i="$id" '$1 == i && $2 == "closed-unmerged" { f = 1 } END { exit !f }' \
    "$WORK_DIR/$key/.harness/$id/mr-watch.state" 2>/dev/null || continue
  case "$herds" in "$id "*|*"
$id "*) continue ;; esac
  solo="$solo$id $key review
"
done
[ -n "$herds$solo" ] || exit 0

# at most twice per session: the counter is "<blocked rounds>", keyed by the session id in its name
stamp=$(git -C "$state" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
counter="$stamp/.harness-rearm-$sid"
n=$(cat "$counter" 2>/dev/null) || n=0
case "$n" in ''|*[!0-9]*) n=0 ;; esac
[ "$n" -lt 2 ] || exit 0
printf '%s\n' "$((n + 1))" > "$counter" 2>/dev/null || exit 0

{
  if [ -n "$herds" ]; then
    printf 'Stop blocked: no herd-watch.sh runs as a monitor for these herds (background_tasks shows none), so nobody sees their sessions change:\n'
    printf '%s' "$herds"
    printf 'Arm one watcher per herd through the Monitor tool, command sh %s/herd-watch.sh <T-id> --interval 60, description herd-watch.sh <T-id>, timeout_ms at its maximum, and arm it again whenever it expires; then go on with the loop of skills/factory/references/herd.md. A herd you no longer watch on purpose is fine to leave: this reminder comes at most twice per session.\n' "$bin"
  fi
  if [ -n "$solo" ]; then
    printf 'Stop blocked: these tasks of this session wait on the human merge of their task MR and no mr-watch.sh runs as a monitor for them (background_tasks shows none), so the merge would not end them:\n'
    printf '%s' "$solo"
    printf 'Arm one watcher per task through the Monitor tool, command sh %s/mr-watch.sh <T-id> --finish --interval 300, description mr-watch.sh <T-id>, timeout_ms at its maximum, and arm it again whenever it expires; a <T-id> done line ends it, see skills/factory/references/solve.md, After the task MR. A task you no longer watch on purpose is fine to leave: the next session start finishes it once merged, and this reminder comes at most twice per session.\n' "$bin"
  fi
} >&2
exit 2
