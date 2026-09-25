#!/bin/sh
# Stop hook (agent-org plan 3.1, 3.7, herdr research R4): a session that watches herds must not go idle with a
# herd unwatched. The CEO and every lead keep one `herd-watch.sh <T-id>` per herd armed through the Monitor tool;
# a Monitor expires after at most 30 minutes and a restarted Claude has none, so at every Stop this hook looks at
# the hook's `background_tasks` and, when a herd of this session has no `monitor` entry naming herd-watch.sh with
# its id, exits 2 with one herd-list line per unwatched herd, `<request> <priority> <T-id> <repo> <status>`.
#
# Scope by the cwd:
#   a parent worktree <root>/<key>/<T-id>  that herd, when the monitor recorded herdr units for it
#                                          (`<root>/<key>/.harness/<T-id>/herdr-tabs`) and it is not done or closed;
#                                          a solve session with subagents records none and is never asked
#   the state clone (repos.yml, repos/)    every parent with a `request:` that is in_progress or review, has a
#                                          block in_progress, tests_ready, review, changes_requested or blocked,
#                                          or has an open step record (`<T-id>-<step>` whose last line in
#                                          `<root>/<key>/.harness/<T-id>/herdr-tabs` is not `closed`), so a
#                                          herd in triage, chart, grill or decompose is one too
#   anywhere else                          nothing
#
# It reads and never writes the state clone's files: the only file it writes is its counter
# `.harness-rearm-<sid>`, for a worktree in the task's `.harness/<T-id>/` beside self-report-check.sh's
# `.harness-stop-rounds`, for the CEO in the state clone's git dir (`git rev-parse --absolute-git-dir`). Never when
# `stop_hook_active` is true, at most twice per session, and any error of its own lets the Stop through: a
# reminder, not a gate.
set -u

. "$(dirname -- "$0")/lib-tasks.sh"

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stdin=$(cat)

# line 1 the stop_hook_active flag, line 2 the session id, then the text of every monitor entry naming herd-watch.sh
parsed=$(printf '%s' "$stdin" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const h=JSON.parse(s);
const out=[h.stop_hook_active===true?"active":"idle",typeof h.session_id==="string"?h.session_id:""];
for(const t of Array.isArray(h.background_tasks)?h.background_tasks:[]){
  if(!t||t.type!=="monitor")continue;
  const txt=((t.command||"")+" "+(t.description||"")).replace(/\s+/g," ");
  if(/herd-watch\.sh/.test(txt))out.push(txt);
}
process.stdout.write(out.join("\n")+"\n")})' 2>/dev/null) || exit 0
[ "$(printf '%s\n' "$parsed" | sed -n 1p)" = idle ] || exit 0
sid=$(printf '%s\n' "$parsed" | sed -n 2p)
case "$sid" in ''|*[!A-Za-z0-9_.-]*) exit 0 ;; esac
watched=$(printf '%s\n' "$parsed" | sed 1,2d)

# the herds of this cwd, one parent task file per line, and the stamp directory of the counter
top=$(git rev-parse --show-toplevel 2>/dev/null) || top=$PWD
files=''
if resolve_cwd_layout "$PWD" && [ "$LO_POSTURE" = standalone ] && is_parent_id "$LO_TASK"; then
  [ -s "$LO_STAMP/herdr-tabs" ] || exit 0
  state=$LO_STATE
  stamp=$LO_STAMP
  files=$(task_of "$LO_TASK")
  case "$files" in */archive/*) exit 0 ;; esac
elif [ -f "$top/repos.yml" ] && [ -d "$top/repos" ]; then
  state=$top
  # inside the clone's git dir: no commit or status sees it, and nothing lands in the factory root
  stamp=$(git -C "$top" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
  # one grep for the tasks of a request (task-new.sh --parent copies `request:` into every block), the awk only
  # over those
  requested=$(grep -l '^request:[[:space:]]*R-' $(task_files) /dev/null 2>/dev/null)
  for f in $requested; do
    id=$(task_fields "$f" id)
    is_parent_id "$id" || continue
    files="$files $f"
  done
else
  exit 0
fi

lines=''
for f in $files; do
  [ -f "$f" ] || continue
  set -- $(task_fields "$f" id status request priority | sed 's/^$/-/')
  id=$1 status=$2 request=$3 priority=$4
  case "$status" in done|closed) continue ;; esac
  if [ "$state" = "$top" ]; then
    case "$request" in -|null) continue ;; esac
    live=''
    case "$status" in in_progress|review) live=1 ;; esac
    if [ -z "$live" ]; then
      key=${f#"$state"/repos/}; key=${key%%/*}
      awk -v t="$id-" 'index($1, t) == 1 && substr($1, length(t) + 1) ~ /^[a-z]/ { l[$1] = $NF }
        END { for (u in l) if (l[u] != "closed") o = 1; exit !o }' \
        "$(dirname -- "$state")/$key/.harness/$id/herdr-tabs" 2>/dev/null && live=1
    fi
    if [ -z "$live" ]; then
      for b in $requested; do
        case "$b" in */"$id"-*) ;; *) continue ;; esac
        set -- $(task_fields "$b" id status | sed 's/^$/-/')
        is_block_of "$id" "$1" || continue
        case "$2" in in_progress|tests_ready|review|changes_requested|blocked) live=1; break ;; esac
      done
    fi
    [ -n "$live" ] || continue
  fi
  # watched when a monitor entry names herd-watch.sh and this id as a word of its own (T-CF-3 is not T-CF-30)
  if printf '%s\n' "$watched" | grep -qE "(^|[^A-Za-z0-9-])$id([^A-Za-z0-9-]|\$)"; then continue; fi
  [ "$priority" = - ] && priority=P2
  key=${f#"$state"/repos/}; key=${key%%/*}
  lines="$lines$request $priority $id $key $status
"
done
[ -n "$lines" ] || exit 0

# at most twice per session: the counter is "<blocked rounds>", keyed by the session id in its name
mkdir -p "$stamp" 2>/dev/null || :
counter="$stamp/.harness-rearm-$sid"
n=$(cat "$counter" 2>/dev/null) || n=0
case "$n" in ''|*[!0-9]*) n=0 ;; esac
[ "$n" -lt 2 ] || exit 0
printf '%s\n' "$((n + 1))" > "$counter" 2>/dev/null || exit 0

{
  printf 'Stop blocked: no herd-watch.sh runs as a monitor for these herds (background_tasks shows none), so nobody sees their sessions change:\n'
  printf '%s' "$lines"
  printf 'Arm one watcher per herd through the Monitor tool, command sh %s/herd-watch.sh <T-id> --interval 60, description herd-watch.sh <T-id>, timeout_ms at its maximum, and arm it again whenever it expires; then go on with the loop of the playbook (skills/factory/references/ceo.md or lead.md). A herd you no longer watch on purpose is fine to leave: this reminder comes at most twice per session.\n' "$bin"
} >&2
exit 2
