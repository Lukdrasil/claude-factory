#!/bin/sh
# capacity.sh over a throwaway state repo: acquire, release and count; the PreToolUse deny at the cap with the
# exact reason and the pending lease under it; SubagentStart replacing the oldest pending lease of its session and
# role, or acquiring over the cap when none is pending; SubagentStop releasing; the role of an agent
# (`claude-factory:` stripped, researcher-sN as researcher, an agent outside the table never counted); every
# sweep rule over a fake `herdr agent list`; wait with a timeout; and `.capacity/.lock` as a lock of its own.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# D8: a fake herdr of this suite's own, first on PATH, answering `agent list` from $tmp/agents.json with the
# 0.8.2 envelope; no such file = herdr is not answering (exit 1)
mkdir -p "$tmp/bin"
cat > "$tmp/bin/herdr" <<EOF
#!/bin/sh
case "\$1 \$2" in
  'agent list') [ -f "$tmp/agents.json" ] || { printf '{"error":{"code":"server_unavailable"}}\n' >&2; exit 1; }
                cat "$tmp/agents.json" ;;
esac
exit 0
EOF
chmod +x "$tmp/bin/herdr"
PATH="$tmp/bin:$PATH"
export PATH
unset WORK_DIR

# the live agents: one `<name> <session id> [<title words>]` per argument, `-` for no name
agents() {
  sep='' body='' n=0
  for a; do
    set -- $a
    n=$((n + 1))
    nm=''; [ "$1" = - ] || nm="\"name\":\"$1\","
    sid=$2; shift 2
    body="$body$sep{\"agent\":\"claude\",$nm\"agent_session\":{\"agent\":\"claude\",\"kind\":\"id\",\"source\":\"herdr:claude\",\"value\":\"$sid\"},\"agent_status\":\"working\",\"pane_id\":\"w1:p$n\",\"terminal_title_stripped\":\"${*:-Claude Code}\"}"
    sep=,
  done
  printf '{"id":"cli:agent:list","result":{"agents":[%s],"type":"agent_list"}}\n' "$body" > "$tmp/agents.json"
}

state="$tmp/state"
mkdir -p "$state"
git init -q "$state"
cat > "$state/factory.yml" <<'EOF'
context_window: 200000
capacity:
  sessions: 3
  roles: {repo-lead: 1, scout: 2, researcher: 1,
          implementer: 1}   # the rest of the table
review: {}
EOF

fail=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
is() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then pass "$1"; else bad "$1 (want '$2', got '$3')"; fi
}
cap() { sh "$bin/capacity.sh" "$@" --state "$state"; }
hook() { # <mode> <json>
  printf '%s' "$2" | sh "$bin/capacity.sh" --hook "$1" --state "$state"
}
pre() { # <session> <tool_use_id> <subagent_type>
  hook pretooluse "{\"session_id\":\"$1\",\"cwd\":\"$tmp\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Agent\",\"tool_use_id\":\"$2\",\"tool_input\":{\"subagent_type\":\"$3\",\"description\":\"d\",\"prompt\":\"p\"}}"
}
start() { # <session> <agent_id> <agent_type>
  hook subagentstart "{\"session_id\":\"$1\",\"cwd\":\"$tmp\",\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"$2\",\"agent_type\":\"$3\"}"
}
stop() { # <session> <agent_id> <agent_type>
  hook subagentstop "{\"session_id\":\"$1\",\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"$2\",\"agent_type\":\"$3\"}"
}
lease() { printf '%s/.capacity/%s' "$state" "$1"; }
field() { sed -n "s/^$2=//p" "$(lease "$1")"; }
age() { # <role/key> <seconds ago>
  f=$(lease "$1")
  awk -v at="$(( $(date +%s) - $2 ))" '/^at=/ { print "at=" at; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
reason() { # the deny reason of a PreToolUse answer, or the parse error
  printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const h=JSON.parse(s).hookSpecificOutput;
    process.stdout.write(h.hookEventName+" "+h.permissionDecision+" "+h.permissionDecisionReason)}catch(e){process.stdout.write("unparsable: "+s)}})'
}
reset() { rm -rf "$state/.capacity"; }

agents "- S1" "- S2"

# acquire, release, count
is 'count with no lease is 0 of the cap' '0/2' "$(cap count scout)"
cap acquire scout k1
is 'acquire adds one lease' '1/2' "$(cap count scout)"
is 'a lease file names its role' 'scout' "$(field scout/k1 role)"
is 'a lease acquired without --session is a unit lease' 'k1' "$(field scout/k1 unit)"
case "$(field scout/k1 at)" in ''|*[!0-9]*) bad 'a lease carries at=<epoch>' ;; *) pass 'a lease carries at=<epoch>' ;; esac
is '.capacity/.gitignore holds *' '*' "$(cat "$state/.capacity/.gitignore" 2>/dev/null)"
[ -e "$state/.capacity/.lock" ] || [ -d "$state/.capacity/.lockdir" ]; is 'the lease lock lives in .capacity/' 0 $?
is 'the state clone shows no lease' '' "$(git -C "$state" status --porcelain -- .capacity)"
cap release k1
is 'release drops the lease' '0/2' "$(cap count scout)"
is 'release of an unknown key is not an error' 0 "$(cap release nothing >/dev/null 2>&1; echo $?)"
is 'the sessions cap is sessions:' '0/3' "$(cap count sessions)"
is 'a role outside the table has no cap' '0/-' "$(cap count Explore)"
cap acquire sessions T-001-01 --session S1
is 'acquire with --session records the session' 'S1' "$(field sessions/T-001-01 session)"
reset

# a lead's repo-lead lease is keyed by the task id and released by its unit
cap acquire repo-lead T-ECS-12
cap acquire sessions T-ECS-12-lead
is 'a repo-lead lease records the lead unit' 'T-ECS-12-lead' "$(field repo-lead/T-ECS-12 unit)"
cap release T-ECS-12-lead
is 'release of the lead unit drops its session lease' '0/3' "$(cap count sessions)"
is 'release of the lead unit drops its repo-lead lease' '0/1' "$(cap count repo-lead)"
reset

# PreToolUse on Agent
out=$(pre S1 tu1 scout)
is 'under the cap the hook prints nothing' '' "$out"
[ -f "$(lease scout/S1.tu1)" ]; is 'under the cap the hook writes the pending lease <session>.<tool_use_id>' 0 $?
is 'the pending lease records its session' 'S1' "$(field scout/S1.tu1 session)"
age scout/S1.tu1 10
is 'the claude-factory: prefix is stripped' '' "$(pre S1 tu2 claude-factory:scout)"
is 'pending leases count' '2/2' "$(cap count scout)"
out=$(pre S1 tu3 scout)
is 'at the cap the hook denies with the reason' \
  'PreToolUse deny role scout is full (2/2): run capacity.sh wait scout and call the agent again' "$(reason "$out")"
[ ! -e "$(lease scout/S1.tu3)" ]; is 'a denied call writes no lease' 0 $?

# SubagentStart and SubagentStop
is 'SubagentStart prints nothing' '' "$(start S1 A1 claude-factory:scout)"
[ -f "$(lease scout/A1)" ]; is 'SubagentStart acquires <agent_id>' 0 $?
[ ! -e "$(lease scout/S1.tu1)" ]; is 'SubagentStart replaces the oldest pending lease of its session' 0 $?
[ -f "$(lease scout/S1.tu2)" ]; is 'the younger pending lease stays' 0 $?
is 'replacing keeps the count' '2/2' "$(cap count scout)"
start S2 A2 scout
[ -f "$(lease scout/A2)" ]; is 'SubagentStart with nothing pending acquires over the cap' 0 $?
is 'the count may exceed the cap' '3/2' "$(cap count scout)"
[ -f "$(lease scout/S1.tu2)" ]; is 'another session pending lease is not taken' 0 $?
stop S1 A1 claude-factory:scout
[ ! -e "$(lease scout/A1)" ]; is 'SubagentStop releases the agent' 0 $?
reset

# the role of an agent
is 'researcher-s2 passes under the researcher cap' '' "$(pre S1 tu1 claude-factory:researcher-s2)"
[ -f "$(lease researcher/S1.tu1)" ]; is 'researcher-s2 counts as researcher' 0 $?
is 'researcher-s0 is denied when researcher is full' \
  'PreToolUse deny role researcher is full (1/1): run capacity.sh wait researcher and call the agent again' \
  "$(reason "$(pre S1 tu2 researcher-s0)")"
for a in Explore general-purpose claude-factory:mr-reviewer claude-factory:spec-critic other:scout; do
  pre S1 tu9 "$a" > "$tmp/out"; start S1 A9 "$a" >> "$tmp/out"
  is "$a is not counted" '' "$(cat "$tmp/out"; ls "$state/.capacity" | grep -vx researcher)"
done
reset

# no capacity: in factory.yml means no cap
cp "$state/factory.yml" "$tmp/factory.yml"
printf 'context_window: 200000\n' > "$state/factory.yml"
pre S1 tu1 scout > "$tmp/out"; pre S1 tu2 scout >> "$tmp/out"; pre S1 tu3 scout >> "$tmp/out"
is 'without capacity: the hook never denies' '' "$(cat "$tmp/out")"
is 'without capacity: count has no cap' '0/-' "$(cap count scout)"
cp "$tmp/factory.yml" "$state/factory.yml"
reset

# sweep
now=$(date +%s)
pre S1 old scout; age scout/S1.old 61
pre S1 new scout; age scout/S1.new 30
cap acquire sessions T-001-01; age sessions/T-001-01 600
cap acquire sessions T-001-02; age sessions/T-001-02 600
cap acquire sessions T-001-03
cap acquire sessions T-ECS-12-lead; age sessions/T-ECS-12-lead 600
cap acquire repo-lead T-ECS-12; age repo-lead/T-ECS-12 600
cap acquire implementer T-ECS-12-03; age implementer/T-ECS-12-03 600
cap acquire sessions T-262-grill; age sessions/T-262-grill 600
start S2 A1 scout
start S9 A9 researcher
cap acquire sessions T-001-04; age sessions/T-001-04 7201
agents "t-001-02 S1" "lead_ecs-12 S2" "implementer_ecs-12-03 S3" "- S4 nexusapi T-262-grill" "t-001-04 S5"
cap sweep
[ ! -e "$(lease scout/S1.old)" ]; is 'sweep drops a pending lease older than 60 s' 0 $?
[ -f "$(lease scout/S1.new)" ]; is 'sweep keeps a pending lease of 30 s' 0 $?
[ ! -e "$(lease sessions/T-001-01)" ]; is 'sweep drops a session lease whose unit is absent from agent list' 0 $?
[ -f "$(lease sessions/T-001-02)" ]; is 'a unit whose lowercased id is an agent name stays' 0 $?
[ -f "$(lease sessions/T-001-03)" ]; is 'a unit just dispatched stays while its agent starts' 0 $?
[ -f "$(lease sessions/T-ECS-12-lead)" ]; is 'a lead unit whose agent is lead_<alias>-<n> stays' 0 $?
[ -f "$(lease repo-lead/T-ECS-12)" ]; is 'the repo-lead lease of a live lead stays' 0 $?
[ -f "$(lease implementer/T-ECS-12-03)" ]; is 'a block unit whose agent is <role>_<alias>-<n>-<NN> stays' 0 $?
[ -f "$(lease sessions/T-262-grill)" ]; is 'a unit named last in the agent title stays' 0 $?
[ -f "$(lease scout/A1)" ]; is 'a subagent lease of a live herdr session stays' 0 $?
[ ! -e "$(lease researcher/A9)" ]; is 'sweep drops a subagent lease whose session is no herdr agent' 0 $?
[ ! -e "$(lease sessions/T-001-04)" ]; is 'sweep drops any lease older than 2 h' 0 $?
rm -f "$tmp/agents.json"
cap acquire sessions T-001-05; age sessions/T-001-05 600
start S9 A8 scout
cap count scout > /dev/null
[ -f "$(lease sessions/T-001-05)" ]; is 'with herdr not answering a unit lease stays' 0 $?
[ -f "$(lease scout/A8)" ]; is 'with herdr not answering a subagent lease stays' 0 $?
cap acquire scout P1; age scout/P1 7300
cap count scout > /dev/null
[ ! -e "$(lease scout/P1)" ]; is 'count runs the sweep' 0 $?
agents "- S1" "- S2"
reset

# wait
cap acquire implementer T-001-01
t0=$(date +%s)
cap wait implementer --timeout 2 > "$tmp/out" 2> "$tmp/err"; rc=$?
t1=$(date +%s)
is 'wait on a full role times out with a failure' 1 "$rc"
[ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 6 ]; is "wait honours --timeout ($((t1 - t0)) s)" 0 $?
grep -q 'implementer is still full (1/1)' "$tmp/err"; is 'the timeout names the role and the count' 0 $?
cap release T-001-01
is 'wait on a free role returns the count at once' '0/1' "$(cap wait implementer --timeout 2)"
reset

# the lock is .capacity/.lock, never the state lock
if command -v flock >/dev/null 2>&1; then
  mkdir -p "$state/.capacity"
  flock "$state/.git/factory-state.lock" sleep 4 &
  sleep 1
  t0=$(date +%s)
  cap acquire scout k1
  t1=$(date +%s)
  wait
  [ $((t1 - t0)) -le 2 ] && [ -f "$(lease scout/k1)" ]; is 'the state lock does not hold up a lease' 0 $?
  flock "$state/.capacity/.lock" sleep 4 &
  sleep 1
  CAPACITY_LOCK_WAIT=1 sh "$bin/capacity.sh" acquire scout k2 --state "$state" 2>/dev/null
  is 'a held .capacity/.lock holds up acquire' 1 $?
  out=$(export CAPACITY_LOCK_WAIT=1; pre S1 tu1 scout); rc=$?
  is 'a hook that cannot take the lock prints nothing and exits 0' '0 ' "$rc $out"
  wait
  reset
else
  printf 'SKIP the lock checks, no flock here\n'
fi

# a hook never fails a tool call on its own error
out=$(printf '{"session_id":"S1","tool_name":"Agent","tool_use_id":"t","tool_input":{"subagent_type":"scout"}}' \
  | sh "$bin/capacity.sh" --hook pretooluse); rc=$?
is 'no --state and no WORK_DIR: the hook exits 0 with nothing' '0 ' "$rc $out"
out=$(printf '{}' | WORK_DIR="$tmp/nowhere" sh "$bin/capacity.sh" --hook subagentstart); rc=$?
is 'a missing state: the hook exits 0 with nothing' '0 ' "$rc $out"
out=$(printf 'not json' | sh "$bin/capacity.sh" --hook pretooluse --state "$state"); rc=$?
is 'unparsable stdin: the hook exits 0 with nothing' '0 ' "$rc $out"
mkdir -p "$tmp/work/state"
cp "$state/factory.yml" "$tmp/work/state/"
printf '{"session_id":"S1","tool_name":"Agent","tool_use_id":"t","tool_input":{"subagent_type":"scout"}}' \
  | WORK_DIR="$tmp/work" sh "$bin/capacity.sh" --hook pretooluse
[ -f "$tmp/work/state/.capacity/scout/S1.t" ]; is 'without --state the hook uses $WORK_DIR/state' 0 $?

exit $fail
