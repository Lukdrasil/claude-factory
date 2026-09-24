#!/bin/sh
# herdr-tabs.sh over a throwaway state repo and the herdr stub: `record` with and without the session id,
# `session` adding the id to a unit's open record, `reattach` naming each recorded agent it finds by its pane
# and session again (plan 3.6 names, a block by the role of its capacity lease), and `sweep` closing the
# workspace of a lead whose parent is done or archived.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
log=$HERDR_STUB_LOG
unset HERDR_TAB_ID HERDR_WORKSPACE_ID

state="$tmp/factory/state"
mkdir -p "$state/repos/ecs/tasks" "$state/repos/demo/tasks"
task() { # <key> <id> <status> [<dir>]
  d=${4:-$state/repos/$1/tasks}
  mkdir -p "$d"
  printf -- '---\nid: %s\nrepo: %s\nstatus: %s\n---\n\n# Goal\nfeat(%s): a goal\n' "$2" "$1" "$3" "$1" > "$d/$2.md"
}
tabs() { cat "$tmp/factory/$1/.harness/$2/herdr-tabs" 2>/dev/null; }
ht() { sh "$bin/herdr-tabs.sh" "$@" --state "$state"; }

fail=0
check() { # <label> <want 0 match|1 no match> <pattern> <text>
  if printf '%s\n' "$4" | grep -q "$3"; then got=0; else got=1; fi
  if [ "$got" -eq "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# record: the session id is the optional fourth field
task ecs T-ECS-12 in_progress
task ecs T-ECS-12-01 in_progress
ht record T-ECS-12-chart tab-1 pane-1 sid-1; rc=$?
ht record T-ECS-12-01 tab-2 pane-2
check 'record with a session exits 0'             0 '^0$' "$rc"
check 'record keeps the session id'               0 '^T-ECS-12-chart tab-1 pane-1 sid-1$' "$(tabs ecs T-ECS-12)"
check 'record without a session has three fields' 0 '^T-ECS-12-01 tab-2 pane-2$' "$(tabs ecs T-ECS-12)"

# session: the last open line of the unit again, with the session id
ht session T-ECS-12-01 sid-2; rc=$?
check 'session exits 0'                           0 '^0$' "$rc"
check 'session appends the id to the open record' 0 '^T-ECS-12-01 tab-2 pane-2 sid-2$' "$(tabs ecs T-ECS-12)"
check 'the unit stays open'                       0 '^open$' "$(ht state T-ECS-12-01)"
ht session T-ECS-12-lead sid-9 2>/dev/null; rc=$?
check 'session of a unit with no record exits 1'  0 '^1$' "$rc"
check 'session of a unit with no record writes nothing' 1 'T-ECS-12-lead' "$(tabs ecs T-ECS-12)"

# reattach after a herdr restart: the agents are unnamed, found by the recorded pane and session id
ht record T-ECS-12-lead tab-3 pane-3 sid-3
ht record T-ECS-12-02 tab-4 pane-4 sid-4
ht record T-ECS-12-grill tab-5 pane-5 sid-5
ht record T-ECS-12-decompose tab-6 pane-6 sid-6
ht record T-ECS-12-triage tab-7 pane-7 sid-7
task ecs T-ECS-12-02 in_progress
mkdir -p "$state/.capacity/implementer" "$state/.capacity/sessions"
printf 'role=implementer\nsession=\nunit=T-ECS-12-02\nat=1\n' > "$state/.capacity/implementer/T-ECS-12-02"
printf 'role=sessions\nsession=\nunit=T-ECS-12-02\nat=1\n' > "$state/.capacity/sessions/T-ECS-12-02"
herdr_agent - idle pane-1 sid-1
herdr_agent - working pane-2 sid-2
herdr_agent - working pane-3 sid-3
herdr_agent - done pane-14 sid-4
herdr_agent - idle pane-5 sid-other
herdr_agent decompose_ecs-12 idle pane-6 sid-6
: > "$log"
out=$(ht reattach T-ECS-12); rc=$?
all=$(cat "$log")
check 'reattach exits 0'                          0 '^0$' "$rc"
check 'reattach reads one agent list'             0 '^1$' "$(grep -c '^agent list' "$log")"
check 'a step is named <step>_<alias id>'         0 '^agent rename pane-1 chart_ecs-12 $' "$all"
check 'the lead is named lead_<alias id>'         0 '^agent rename pane-3 lead_ecs-12 $' "$all"
check 'a block is named by its lease role'        0 '^agent rename pane-14 implementer_ecs-12-02 $' "$all"
check 'a block with no role lease keeps its id'   0 '^agent rename pane-2 t-ecs-12-01 $' "$all"
check 'another session at the pane is not renamed' 1 '^agent rename pane-5 ' "$all"
check 'an agent with its name is not renamed'     1 '^agent rename pane-6 ' "$all"
check 'reattach prints the renamed unit'          0 '^T-ECS-12-chart renamed chart_ecs-12 pane-1$' "$out"
check 'reattach prints an unchanged name'         0 '^T-ECS-12-decompose named decompose_ecs-12 pane-6$' "$out"
check 'reattach prints the unit it did not find'  0 '^T-ECS-12-grill gone$' "$out"
check 'reattach prints a unit with no agent gone' 0 '^T-ECS-12-triage gone$' "$out"

# a legacy id keeps its t-, and a closed record is not reattached
task demo T-264 in_progress
ht record T-264-grill tab-8 pane-8 sid-8
ht record T-264-01 tab-9 pane-9 sid-9
printf 'T-264-01 tab-9 closed\n' >> "$tmp/factory/demo/.harness/T-264/herdr-tabs"
task demo T-264-01 in_progress
herdr_agent - idle pane-8 sid-8
herdr_agent - idle pane-9 sid-9
: > "$log"
out=$(ht reattach T-264)
check 'a legacy step is named <step>_t-<n>'       0 '^agent rename pane-8 grill_t-264 $' "$(cat "$log")"
check 'a closed record is not reattached'         1 'pane-9' "$(cat "$log")$out"

# sweep: the workspace of a lead closes once its parent is done or archived, never before, never the caller's
task ecs T-ECS-13 in_progress
ht record T-ECS-13-lead tab-31 pane-31 sid-31
herdr_tab tab-31 idle false lead_ecs-13
: > "$log"
ht sweep T-ECS-13 >/dev/null
check 'a running parent keeps the lead workspace' 1 '^workspace close' "$(cat "$log")"
task ecs T-ECS-13 done
out=$(ht sweep T-ECS-13)
all=$(cat "$log")
check 'a done parent closes the lead workspace'   0 '^workspace close ws-1 $' "$all"
check 'the lead tab is not closed on its own'     1 '^tab close tab-31 ' "$all"
check 'the lead record reads closed'              0 '^T-ECS-13-lead tab-31 closed$' "$(tabs ecs T-ECS-13)"
check 'sweep prints the closed workspace'         0 '^T-ECS-13-lead closed ws-1$' "$out"

task ecs T-ECS-14 done "$state/repos/ecs/archive/2026-09/tasks"
ht record T-ECS-14-lead tab-41 pane-41 sid-41
herdr_tab tab-41 idle false lead_ecs-14
: > "$log"
ht sweep T-ECS-14 >/dev/null
check 'an archived parent closes the lead workspace' 0 '^workspace close ws-1 $' "$(cat "$log")"

task ecs T-ECS-15 done
ht record T-ECS-15-lead tab-51 pane-51 sid-51
herdr_tab tab-51 idle false lead_ecs-15
: > "$log"
out=$(HERDR_WORKSPACE_ID=ws-1 sh "$bin/herdr-tabs.sh" sweep T-ECS-15 --state "$state")
check 'the caller workspace is kept'              1 '^workspace close' "$(cat "$log")"
check 'sweep says why it kept the workspace'      0 '^T-ECS-15-lead kept ws-1 own workspace$' "$out"

task ecs T-ECS-16 in_progress
ht record T-ECS-16-lead tab-61 pane-61 sid-61
herdr_tab tab-61 idle false lead_ecs-16
: > "$log"
ht close T-ECS-16-lead >/dev/null
all=$(cat "$log")
check 'close of a lead closes its tab only'       0 '^tab close tab-61 ' "$all"
check 'close of a lead leaves the workspace'      1 '^workspace close' "$all"

exit $fail
