#!/bin/sh
# PreToolUse tripwire for the architect curation (architect-agent plan, decision 8): a Write or Edit creating a task
# file under repos/<key>/tasks/ in a state clone needs a valid verdict when the registered clone of <key> has
# docs/architecture/. exit 2 = deny, the reason on stderr. The rule is architect_verdict in lib-tasks.sh, the one
# task-new.sh applies to every block write, and the verdict format is defined in
# skills/architect-review/SKILL.md. The state clone comes from the file path and the product repo from the
# repos.yml `path:`, never from the cwd. A Bash call is not checked here: task-new.sh applies the rule itself.
# Deny on positive evidence only: everything the gate cannot resolve passes with a warning, so a forgotten check is
# blocked and an unrelated flow never is.
set -eu

. "$(dirname -- "$0")/lib-tasks.sh"

deny() { printf 'architect-gate deny: %s\n' "$1" >&2; exit 2; }
warn() { printf 'architect-gate: %s\n' "$1" >&2; exit 0; }

input=$(cat)
# the same reader as policy-guard.sh; node is in the worker image, no parser of our own
node_json() { printf '%s' "$input" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);
const v=process.argv[1].split(".").reduce((a,k)=>a==null?a:a[k],o);
process.stdout.write(v==null?"":String(v))})' "$1"; }

tool=$(node_json tool_name) || warn "unreadable JSON on the hook stdin"
case "$tool" in Write|Edit) ;; *) exit 0 ;; esac
cwd=$(node_json cwd) || warn "unreadable JSON on the hook stdin"
p=$(node_json tool_input.file_path) || warn "unreadable JSON on the hook stdin"
[ -n "$p" ] || exit 0
case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
case "$p" in */repos/*/tasks/*) ;; *) exit 0 ;; esac
# only creating a task file is a task write; editing or overwriting one is the session's own status self-report
if [ -e "$p" ]; then exit 0; fi
state=${p%%/repos/*}
# a task path outside a state clone is somebody else's repos/<key>/tasks/, not a standalone write
[ -f "$state/repos.yml" ] || exit 0
rest=${p#*/repos/}
key=${rest%%/*}
slug=$(node_json tool_input.content | plan_slug)
# the task id the file name starts with, `<id>-<slug>.md`: its longest dash-joined prefix that lib-tasks.sh's
# is_task_id takes, so `T-246-01-x` is the block and `T-ECS-12-fix` the alias parent
task_id='' pre='' name=$(basename "$p" .md)
while [ -n "$name" ]; do
  pre=${pre:+$pre-}${name%%-*}
  case "$name" in *-*) name=${name#*-} ;; *) name='' ;; esac
  if is_task_id "$pre"; then task_id=$pre; fi
done

rc=0
reason=$(architect_verdict "$key" "$slug" "$task_id") || rc=$?
case "$rc" in
  0) exit 0 ;;
  2) warn "$reason" ;;
esac
deny "$reason"
