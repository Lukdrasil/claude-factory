#!/bin/sh
# The playbook of an agent's role for one repository (agent-org plan 3.8), the third of the three ways a playbook
# reaches an agent: the lead's prompt names the repo-lead playbook, agent-brief.sh prints it in a brief, and this
# script hands it to every subagent at SubagentStart. The file is `repos/<key>/agents/<role>/playbook.md` in the
# state clone (the weekly pass keeps it under 800 words), printed after a `<!-- <that path> -->` marker. The role
# is the agent type without `claude-factory:`, researcher-s0..s3 reading researcher's playbook.
#
#   playbook-inject.sh <agent> <key>   the playbook from $WORK_DIR/state, or nothing
#   playbook-inject.sh --hook          SubagentStart JSON on stdin: the role from `agent_type`, the key from `cwd`
#                                      (a task worktree <root>/<key>/<T-id> through resolve_cwd_layout, then the
#                                      clone whose repos.yml `path:` holds the cwd), the state clone of that layout
#                                      or $WORK_DIR/state; prints `additionalContext` JSON or nothing, and exits 0
#                                      whatever goes wrong, so a subagent never fails to start on its account.
set -u
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'playbook-inject: %s\n' "$1" >&2; exit 2; }

playbook() { # <state> <key> <agent>
  pb_role=${3#claude-factory:}
  case "$pb_role" in researcher-s[0-9]*) pb_role=researcher ;; esac
  pb="repos/$2/agents/$pb_role/playbook.md"
  [ -f "$1/$pb" ] || return 0
  printf '<!-- %s -->\n\n' "$pb"
  cat "$1/$pb"
}

if [ "${1:-}" != --hook ]; then
  [ $# -eq 2 ] || die "usage: playbook-inject.sh <agent> <key> | --hook"
  [ -n "${WORK_DIR:-}" ] || exit 0
  text=$(playbook "$WORK_DIR/state" "$2" "$1")
  [ -z "$text" ] || printf '%s\n' "$text"
  exit 0
fi

fields=$(node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let o;try{o=JSON.parse(s)}catch(e){process.exit(3)}
const v=x=>String(x==null?"":x).replace(/[\r\n]/g," ");
process.stdout.write([o.cwd,o.agent_type].map(v).join("\n"))})' 2>/dev/null) || exit 0
{ IFS= read -r cwd || cwd=''
  IFS= read -r agent || agent=''
} <<EOF
$fields
EOF
[ -n "$cwd" ] && [ -n "$agent" ] || exit 0

if resolve_cwd_layout "$cwd"; then
  key=${LO_OWN%/*}; key=${key##*/}; state=$LO_STATE
else
  key=$(repo_key_of_cwd "$cwd" 2>/dev/null) || key=''
  state=${WORK_DIR:+$WORK_DIR/state}
fi
[ -n "$key" ] && [ -n "$state" ] || exit 0
text=$(playbook "$state" "$key" "$agent")
[ -n "$text" ] || exit 0
printf '%s' "$text" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:s}})+"\n")})' || :
exit 0
