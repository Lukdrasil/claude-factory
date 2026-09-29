#!/bin/sh
# Stop hook (herdr research R4): the monitor of `factory herd` must not go idle with a herd unwatched. It keeps one
# `herd-watch.sh <T-id>` per herd armed through the Monitor tool; a Monitor expires after at most 30 minutes and a
# restarted Claude has none, so at every Stop this hook looks at the hook's `background_tasks` and, when a herd of
# this session has no entry naming herd-watch.sh with its id, exits 2 with one `<T-id> <repo> <status>` line per
# unwatched herd. An entry of any type counts (the harness reports a Monitor task as `local_bash`), unless its
# `status` says it finished (completed, failed, killed, stopped).
#
# The herds of this session are the parents whose `<WORK_DIR>/<key>/.harness/<T-id>/herd-monitor` holds this
# session's `$HERDR_TAB_ID`: session-monitor.sh writes it on a --task spawn from the monitor's own pane. A parent
# that is done, closed or archived is no herd any more. Outside herdr (no HERDR_TAB_ID) there is nothing to look
# at, so a solve session with subagents is never asked.
#
# It writes no file of the state clone: its only file is its counter `.harness-rearm-<sid>` in the state clone's
# git dir (`git rev-parse --absolute-git-dir`), where no commit and no status sees it. Never when
# `stop_hook_active` is true, at most twice per session, and any error of its own lets the Stop through: a
# reminder, not a gate.
set -u

. "$(dirname -- "$0")/lib-tasks.sh"

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stdin=$(cat)

[ -n "${HERDR_TAB_ID:-}" ] || exit 0
[ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ] || exit 0
state=$WORK_DIR/state

# line 1 the stop_hook_active flag, line 2 the session id, then the text of every unfinished entry naming
# herd-watch.sh
parsed=$(printf '%s' "$stdin" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const h=JSON.parse(s);
const out=[h.stop_hook_active===true?"active":"idle",typeof h.session_id==="string"?h.session_id:""];
for(const t of Array.isArray(h.background_tasks)?h.background_tasks:[]){
  if(!t||/^(completed|failed|killed|stopped)$/.test(t.status||""))continue;
  const txt=((t.command||"")+" "+(t.description||"")).replace(/\s+/g," ");
  if(/herd-watch\.sh/.test(txt))out.push(txt);
}
process.stdout.write(out.join("\n")+"\n")})' 2>/dev/null) || exit 0
[ "$(printf '%s\n' "$parsed" | sed -n 1p)" = idle ] || exit 0
sid=$(printf '%s\n' "$parsed" | sed -n 2p)
case "$sid" in ''|*[!A-Za-z0-9_.-]*) exit 0 ;; esac
watched=$(printf '%s\n' "$parsed" | sed 1,2d)

lines=''
for m in "$WORK_DIR"/*/.harness/T-*/herd-monitor; do
  [ -f "$m" ] || continue
  [ "$(head -n1 "$m")" = "$HERDR_TAB_ID" ] || continue
  id=$(basename -- "$(dirname -- "$m")")
  is_parent_id "$id" || continue
  f=$(task_of "$id" || :)
  [ -n "$f" ] || continue
  case "$f" in */archive/*) continue ;; esac
  status=$(task_fields "$f" status)
  case "$status" in done|closed) continue ;; esac
  # watched when a monitor entry names herd-watch.sh and this id as a word of its own (T-CF-3 is not T-CF-30)
  if printf '%s\n' "$watched" | grep -qE "(^|[^A-Za-z0-9-])$id([^A-Za-z0-9-]|\$)"; then continue; fi
  key=${f#"$state"/repos/}; key=${key%%/*}
  lines="$lines$id $key $status
"
done
[ -n "$lines" ] || exit 0

# at most twice per session: the counter is "<blocked rounds>", keyed by the session id in its name
stamp=$(git -C "$state" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
counter="$stamp/.harness-rearm-$sid"
n=$(cat "$counter" 2>/dev/null) || n=0
case "$n" in ''|*[!0-9]*) n=0 ;; esac
[ "$n" -lt 2 ] || exit 0
printf '%s\n' "$((n + 1))" > "$counter" 2>/dev/null || exit 0

{
  printf 'Stop blocked: no herd-watch.sh runs as a monitor for these herds (background_tasks shows none), so nobody sees their sessions change:\n'
  printf '%s' "$lines"
  printf 'Arm one watcher per herd through the Monitor tool, command sh %s/herd-watch.sh <T-id> --interval 60, description herd-watch.sh <T-id>, timeout_ms at its maximum, and arm it again whenever it expires; then go on with the loop of skills/factory/references/herd.md. A herd you no longer watch on purpose is fine to leave: this reminder comes at most twice per session.\n' "$bin"
} >&2
exit 2
