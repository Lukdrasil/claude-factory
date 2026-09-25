#!/bin/sh
# Capacity per role (agent-org plan 3.3): one lease file per running unit or subagent under
# <state>/.capacity/<role>/<key> (`role=`, `session=`, `unit=`, `at=<epoch>`), the caps from `capacity:` in the
# state's factory.yml (`sessions: N` and `roles: {<role>: N, ...}`, flow or block spelling). `.capacity/.gitignore`
# holds `*`, so no lease is ever committed, and `.capacity/.lock` serializes every change: flock where it exists,
# otherwise a mkdir spin on `.capacity/.lockdir`, taken over once 120 s old. It is never the state lock, and
# nothing here calls a state writer, so a lease never waits on a report and a report never waits on a lease.
#
#   capacity.sh acquire <role> <key> [--session <sid>] | release <key> | count <role> | wait <role> [--timeout <s>]
#             | sweep | --hook pretooluse|subagentstart|subagentstop [--state <dir>]
#
# acquire never refuses: the caller checked `count` first, or a subagent is already running. Without --session
# the lease is a herdr unit's (session-monitor.sh: `sessions <unit>`, `repo-lead <T-id>`, `<agent role> <unit>`)
# and records `unit=<key>`, for repo-lead `unit=<T-id>-lead`; with --session it is a subagent's and takes the
# place of the oldest pending lease of that session and role. release drops every lease named <key> and every
# lease whose unit is <key>, so herd-watch.sh's `release <unit>` of a lead frees its repo-lead slot too.
# count prints `<n>/<cap>`, `<n>/-` for a role without a cap; wait polls it every 2 s until a slot is free
# (exit 0, the count on stdout) or the timeout, default 540 s, passes (exit 1): then the caller writes a blocked
# question, it never does the role's work itself.
#
# Hooks, each reading the hook JSON on stdin and never failing a tool call on its own error (no state, no
# factory.yml, no lock within CAPACITY_LOCK_WAIT seconds, bad JSON: exit 0, nothing printed):
# - pretooluse (Agent): the role of `tool_input.subagent_type`; live plus pending leases at the cap print the
#   deny, otherwise a pending lease `<session_id>.<tool_use_id>` is written.
# - subagentstart: `acquire <role> <agent_id> --session <session_id>`, over the cap if it must.
# - subagentstop: `release <agent_id>`.
# The role of an agent is its type without `claude-factory:`, researcher-s0..s3 being `researcher`; a role with
# no cap in the table is never counted or denied, so no `capacity:` at all means no cap anywhere.
#
# sweep, run by every count: a pending lease older than 60 s, any lease older than 2 h, and, from one `herdr agent
# list`, a unit lease older than 180 s (the agent start window) whose unit no live agent carries, and a subagent
# lease whose session is no live agent's `agent_session.value`. A unit is carried by an agent named the lowercased
# unit, `<step>_<unit tail>` for a step unit, `<role>_<unit tail>` for a block (plan 3.6: the tail drops the step
# and, for an alias id, the leading `t-`), `onboard_<key lowercased>` cut at 31 for an onboarding unit
# `onboard-<key>`, or whose title ends in the unit (the `claude --name` label). herdr not answering drops nothing
# on its account.
set -u

die() { printf 'capacity: %s\n' "$1" >&2; exit 2; }
usage='usage: capacity.sh acquire <role> <key> [--session <sid>] | release <key> | count <role> | wait <role> [--timeout <s>] | sweep | --hook pretooluse|subagentstart|subagentstop [--state <dir>]'

cmd='' a1='' a2='' n=0 state='' session='' timeout=540 hook=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --session) [ $# -ge 2 ] || die "--session needs a value"; session=$2; shift 2 ;;
    --timeout) [ $# -ge 2 ] || die "--timeout needs a value"; timeout=$2; shift 2 ;;
    --hook) [ $# -ge 2 ] || die "--hook needs a value"; hook=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *)
      n=$((n + 1))
      case $n in 1) cmd=$1 ;; 2) a1=$1 ;; 3) a2=$1 ;; *) die "too many arguments" ;; esac
      shift ;;
  esac
done

if [ -z "$state" ] && [ -n "${WORK_DIR:-}" ]; then state="$WORK_DIR/state"; fi
if [ -z "$state" ] || [ ! -d "$state" ]; then
  [ -z "$hook" ] || exit 0
  die "no state clone: pass --state <dir> or set WORK_DIR"
fi
cdir="$state/.capacity"

# `<role> <cap>` per line: every `<name>: <number>` pair of the capacity: block, `sessions` among them
caps=$(awk '
  on && /^[^ \t#]/ { exit }
  /^capacity:/ { on = 1; sub(/^capacity:/, "") }
  on {
    s = $0; sub(/#.*/, "", s)
    while (match(s, /[A-Za-z0-9_-]+[ \t]*:[ \t]*[0-9]+/)) {
      p = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      k = p; sub(/[ \t]*:.*/, "", k); v = p; sub(/.*:[ \t]*/, "", v)
      print k, v
    }
  }' "$state/factory.yml" 2>/dev/null)
cap_of() { printf '%s\n' "$caps" | awk -v r="$1" '$1 == r { print $2; exit }'; }
role_of() { r=${1#claude-factory:}; case "$r" in researcher-s[0-9]*) r=researcher ;; esac; printf '%s' "$r"; }
valid_key() { case "$1" in ''|.*|*/*) return 1 ;; esac; }

LOCK_HELD=''
cap_lock() {
  mkdir -p "$cdir" 2>/dev/null || return 2
  [ -f "$cdir/.gitignore" ] || printf '*\n' > "$cdir/.gitignore" || return 2
  cl_wait=${CAPACITY_LOCK_WAIT:-10}
  if command -v flock >/dev/null 2>&1; then
    exec 8>"$cdir/.lock" || return 2
    flock -w "$cl_wait" 8 || { exec 8>&-; return 1; }
    LOCK_HELD=fd
    return 0
  fi
  cl_n=0
  until mkdir "$cdir/.lockdir" 2>/dev/null; do
    cl_since=$(cat "$cdir/.lockdir/since" 2>/dev/null || :)
    case "$cl_since" in *[!0-9]*) cl_since='' ;; esac
    if [ -n "$cl_since" ] && [ $(( $(date +%s) - cl_since )) -ge 120 ]; then rm -rf "$cdir/.lockdir"; continue; fi
    cl_n=$((cl_n + 1))
    [ "$cl_n" -lt "$cl_wait" ] || return 1
    sleep 1
  done
  date +%s > "$cdir/.lockdir/since"
  LOCK_HELD=dir
}
cap_unlock() {
  case "$LOCK_HELD" in
    fd) exec 8>&- ;;
    dir) rm -rf "$cdir/.lockdir" ;;
  esac
  LOCK_HELD=''
}
locked() { cap_lock || { [ -n "$hook" ] && exit 0; printf 'capacity: %s/.lock stays held, nothing changed\n' "$cdir" >&2; exit 1; }; }

write_lease() { # <role> <key> <session> <unit>
  mkdir -p "$cdir/$1" || return 1
  printf 'role=%s\nsession=%s\nunit=%s\nat=%s\n' "$1" "$3" "$4" "$(date +%s)" > "$cdir/$1/.$2.tmp" &&
    mv -f "$cdir/$1/.$2.tmp" "$cdir/$1/$2"
}

count_of() { # <role>
  set -- "$cdir/$1"/*
  if [ -e "$1" ]; then printf '%s' $#; else printf 0; fi
}

acquire() { # <role> <key> <session or empty>
  if [ -n "$3" ]; then
    ac_old=$(for f in "$cdir/$1/$3".*; do
               [ -f "$f" ] && printf '%s %s\n' "$(sed -n 's/^at=//p' "$f")" "$f"
             done | sort -n | head -n1 | cut -d' ' -f2-)
    [ -z "$ac_old" ] || rm -f "$ac_old"
    write_lease "$1" "$2" "$3" ''
  else
    ac_unit=$2
    [ "$1" != repo-lead ] || ac_unit="$2-lead"
    write_lease "$1" "$2" '' "$ac_unit"
  fi
}

release() { # <key>
  for f in "$cdir"/*/"$1"; do [ -f "$f" ] && rm -f "$f"; done
  grep -lxF "unit=$1" "$cdir"/*/* 2>/dev/null | while IFS= read -r f; do rm -f "$f"; done
}

# `<session>|<unit>|<at>|<file>` per lease, one awk over every lease file
lease_rows() {
  set -- "$cdir"/*/*
  [ -e "$1" ] || return 0
  awk 'FNR == 1 { if (f != "") print s "|" u "|" a "|" f; f = FILENAME; s = u = a = "" }
       /^session=/ { s = substr($0, 9) } /^unit=/ { u = substr($0, 6) } /^at=/ { a = substr($0, 4) }
       END { if (f != "") print s "|" u "|" a "|" f }' "$@"
}

sweep() {
  sw_now=$(date +%s)
  sw_rows=$(lease_rows)
  [ -n "$sw_rows" ] || return 0
  set --
  while IFS='|' read -r s u a f; do
    case "$a" in ''|*[!0-9]*) a=0 ;; esac
    k=${f##*/}
    if [ $((sw_now - a)) -gt 7200 ]; then rm -f "$f"; continue; fi
    if [ -n "$s" ] && [ "${k#"$s".}" != "$k" ] && [ $((sw_now - a)) -gt 60 ]; then rm -f "$f"; continue; fi
    if [ -n "$u" ]; then
      [ $((sw_now - a)) -le 180 ] || set -- "$@" "u $u"
    elif [ -n "$s" ]; then
      set -- "$@" "s $s"
    fi
  done <<EOF
$sw_rows
EOF
  [ $# -gt 0 ] || return 0
  command -v herdr >/dev/null 2>&1 || return 0
  # the lock's fd is closed for herdr, so a server it may start never inherits the lock
  sw_gone=$(herdr agent list 2>/dev/null 8>&- | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let a;try{a=JSON.parse(s).result.agents}catch(e){process.exit(3)}
if(!Array.isArray(a))process.exit(3);
const names=a.map(x=>String(x.name||""));
const sids=new Set(a.map(x=>String((x.agent_session&&x.agent_session.value)||"")));
const ends=new Set(a.map(x=>String(x.terminal_title_stripped||"").trim().split(/\s+/).pop()));
const live=u=>{
  if(ends.has(u)||names.includes(u.toLowerCase()))return true;
  if(u.startsWith("onboard-"))return names.includes(("onboard_"+u.slice(8)).toLowerCase().slice(0,31));
  const m=/^(.*?)-([a-z].*)$/.exec(u),step=m?m[2]:"";
  let t=(m?m[1]:u).toLowerCase();if(!/^t-[0-9]/.test(t))t=t.replace(/^t-/,"");
  return names.some(n=>{const i=n.indexOf("_");return i>0&&n.slice(i+1)===t&&(!step||n.slice(0,i)===step)});
};
for(const q of process.argv.slice(1)){const v=q.slice(2);if(q[0]==="u"?!live(v):!sids.has(v))process.stdout.write(q+"\n")}})' "$@") || return 0
  [ -n "$sw_gone" ] || return 0
  while IFS='|' read -r s u a f; do
    [ -f "$f" ] || continue
    case "$a" in ''|*[!0-9]*) a=0 ;; esac
    if [ -n "$u" ]; then
      [ $((sw_now - a)) -gt 180 ] && printf '%s\n' "$sw_gone" | grep -qxF "u $u" && rm -f "$f"
    elif [ -n "$s" ]; then
      printf '%s\n' "$sw_gone" | grep -qxF "s $s" && rm -f "$f"
    fi
  done <<EOF
$sw_rows
EOF
  return 0
}

count_line() { # <role>
  locked
  sweep
  cl_count=$(count_of "$1")
  cap_unlock
  cl_cap=$(cap_of "$1")
  printf '%s/%s\n' "$cl_count" "${cl_cap:--}"
}

hook_main() {
  fields=$(node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let o;try{o=JSON.parse(s)}catch(e){process.exit(3)}
const t=o.tool_input||{};
const v=x=>String(x==null?"":x).replace(/[\r\n]/g," ");
process.stdout.write([o.tool_name,o.session_id,o.tool_use_id,t.subagent_type,o.agent_id,o.agent_type].map(v).join("\n"))})') || return 0
  { IFS= read -r h_tool || h_tool=''
    IFS= read -r h_session || h_session=''
    IFS= read -r h_use || h_use=''
    IFS= read -r h_subagent || h_subagent=''
    IFS= read -r h_agent || h_agent=''
    IFS= read -r h_type || h_type=''
  } <<EOF
$fields
EOF
  case "$hook" in
    pretooluse)
      case "$h_tool" in Agent|Task) ;; *) return 0 ;; esac
      role=$(role_of "$h_subagent"); cap=$(cap_of "$role")
      [ -n "$cap" ] && valid_key "$h_session" && valid_key "$h_use" || return 0
      locked
      sweep
      used=$(count_of "$role")
      if [ "$used" -ge "$cap" ]; then
        cap_unlock
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"role %s is full (%s/%s): run capacity.sh wait %s and call the agent again"}}\n' \
          "$role" "$used" "$cap" "$role"
        return 0
      fi
      write_lease "$role" "$h_session.$h_use" "$h_session" ''
      cap_unlock ;;
    subagentstart)
      role=$(role_of "$h_type")
      [ -n "$(cap_of "$role")" ] && valid_key "$h_agent" && valid_key "$h_session" || return 0
      locked
      acquire "$role" "$h_agent" "$h_session"
      cap_unlock ;;
    subagentstop)
      valid_key "$h_agent" || return 0
      locked
      release "$h_agent"
      cap_unlock ;;
  esac
  return 0
}

if [ -n "$hook" ]; then
  case "$hook" in pretooluse|subagentstart|subagentstop) ;; *) exit 0 ;; esac
  ( hook_main ) || :
  exit 0
fi

case "$cmd" in
  acquire)
    [ -n "$a1" ] && [ -n "$a2" ] || die "$usage"
    valid_key "$a1" && valid_key "$a2" || die "a role or key must not be empty, start with '.' or hold '/'"
    locked
    acquire "$a1" "$a2" "$session"
    cap_unlock ;;
  release)
    [ -n "$a1" ] && [ -z "$a2" ] || die "$usage"
    valid_key "$a1" || die "a key must not be empty, start with '.' or hold '/'"
    locked
    release "$a1"
    cap_unlock ;;
  count)
    [ -n "$a1" ] && [ -z "$a2" ] || die "$usage"
    valid_key "$a1" || die "a role must not be empty, start with '.' or hold '/'"
    count_line "$a1" ;;
  wait)
    [ -n "$a1" ] && [ -z "$a2" ] || die "$usage"
    valid_key "$a1" || die "a role must not be empty, start with '.' or hold '/'"
    case "$timeout" in ''|*[!0-9]*) die "--timeout takes whole seconds" ;; esac
    deadline=$(( $(date +%s) + timeout ))
    while :; do
      line=$(count_line "$a1") || exit 1
      used=${line%/*} cap=${line#*/}
      if [ "$cap" = - ] || [ "$used" -lt "$cap" ]; then printf '%s\n' "$line"; exit 0; fi
      if [ "$(date +%s)" -ge "$deadline" ]; then
        printf 'capacity: role %s is still full (%s) after %s s: write a blocked question, never do the work of the role yourself\n' \
          "$a1" "$line" "$timeout" >&2
        exit 1
      fi
      sleep 2
    done ;;
  sweep)
    [ -z "$a1" ] || die "$usage"
    locked
    sweep
    cap_unlock ;;
  *) die "$usage" ;;
esac
exit 0
