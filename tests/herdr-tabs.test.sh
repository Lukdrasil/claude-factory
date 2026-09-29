#!/bin/sh
# herdr-tabs.sh over a throwaway state repo and the herdr stub: `record` with and without the session id and
# with the herdr name kept in `herdr-names` by `--name`, `session` adding the id to a unit's open record,
# `agents` reading one agent list, `reattach` naming each recorded agent it finds by its pane and session again
# (the kept name, else `<step>_<tail>` for a step and the lowercased unit otherwise), `sweep` closing the tabs
# of units that are over (a step by its parent) and no workspace, and every verb that needs herdr doing nothing
# without it.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR HERDR_ENV HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_PANE_ID

# a PATH with no herdr at all, for the verbs that do nothing without it
noherdr=''
oldifs=$IFS
IFS=:
for d in $PATH; do
  [ -n "$d" ] && [ ! -x "$d/herdr" ] || continue
  noherdr="${noherdr:+$noherdr:}$d"
done
IFS=$oldifs

. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
log=$HERDR_STUB_LOG

state="$tmp/factory/state"
mkdir -p "$state/repos/ecs/tasks" "$state/repos/demo/tasks"
task() { # <key> <id> <status> [<dir>]
  d=${4:-$state/repos/$1/tasks}
  mkdir -p "$d"
  printf -- '---\nid: %s\nrepo: %s\nstatus: %s\n---\n\n# Goal\nfeat(%s): a goal\n' "$2" "$1" "$3" "$1" > "$d/$2.md"
}
tabs() { cat "$tmp/factory/$1/.harness/$2/herdr-tabs" 2>/dev/null; }
names() { cat "$tmp/factory/$1/.harness/$2/herdr-names" 2>/dev/null; }
ht() { sh "$bin/herdr-tabs.sh" "$@" --state "$state"; }

fail=0
check() { # <label> <want 0 match|1 no match> <pattern> <text>
  if printf '%s\n' "$4" | grep -q "$3"; then got=0; else got=1; fi
  if [ "$got" -eq "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# record: the session id is the optional fourth field
task ecs T-ECS-12 in_progress
task ecs T-ECS-12-01 in_progress
ht record T-ECS-12-triage tab-1 pane-1 sid-1; rc=$?
ht record T-ECS-12-01 tab-2 pane-2
check 'record with a session exits 0'             0 '^0$' "$rc"
check 'record keeps the session id'               0 '^T-ECS-12-triage tab-1 pane-1 sid-1$' "$(tabs ecs T-ECS-12)"
check 'record without a session has three fields' 0 '^T-ECS-12-01 tab-2 pane-2$' "$(tabs ecs T-ECS-12)"
check 'record without --name keeps no name'       1 '.' "$(names ecs T-ECS-12)"

# session: the last open line of the unit again, with the session id
ht session T-ECS-12-01 sid-2; rc=$?
check 'session exits 0'                           0 '^0$' "$rc"
check 'session appends the id to the open record' 0 '^T-ECS-12-01 tab-2 pane-2 sid-2$' "$(tabs ecs T-ECS-12)"
check 'the unit stays open'                       0 '^open$' "$(ht state T-ECS-12-01)"
ht session T-ECS-12-plan-check sid-9 2>/dev/null; rc=$?
check 'session of a unit with no record exits 1'  0 '^1$' "$rc"
check 'session of a unit with no record writes nothing' 1 'T-ECS-12-plan-check' "$(tabs ecs T-ECS-12)"

# record --name: the herdr name goes to herdr-names beside the record, the last line of a unit wins
task ecs T-ECS-12-02 in_progress
task ecs T-ECS-12-03 in_progress
ht record T-ECS-12-02 tab-4 pane-4 sid-4 --name test-designer_ecs-12-02; rc=$?
check 'record --name exits 0'                     0 '^0$' "$rc"
check 'record --name keeps the record as it was'  0 '^T-ECS-12-02 tab-4 pane-4 sid-4$' "$(tabs ecs T-ECS-12)"
check 'record --name appends <unit> <name>'       0 '^T-ECS-12-02 test-designer_ecs-12-02$' "$(names ecs T-ECS-12)"
check 'the name stays out of the tab record'      1 'test-designer' "$(tabs ecs T-ECS-12)"
ht record T-ECS-12-02 tab-4 pane-4 sid-4 --name implementer_ecs-12-02
check 'a second --name is appended too'           0 '^T-ECS-12-02 implementer_ecs-12-02$' "$(names ecs T-ECS-12)"

# reattach after a herdr restart: the agents are unnamed, found by the recorded pane and session id
ht record T-ECS-12-plan-check tab-3 pane-3 sid-3
ht record T-ECS-12-grill tab-5 pane-5 sid-5
ht record T-ECS-12-decompose tab-6 pane-6 sid-6
ht record T-ECS-12-03 tab-7 pane-7 sid-7 --name architecture-auditor_ecs-12-03
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
check 'a step is named <step>_<alias id>'         0 '^agent rename pane-1 triage_ecs-12 $' "$all"
check 'a hyphenated step keeps its whole name'    0 '^agent rename pane-3 plan-check_ecs-12 $' "$all"
check 'a block takes the name record --name kept' 0 '^agent rename pane-14 implementer_ecs-12-02 $' "$all"
check 'the last kept name wins'                   1 'test-designer' "$all$out"
check 'a block with no kept name is its lowercased id' 0 '^agent rename pane-2 t-ecs-12-01 $' "$all"
check 'another session at the pane is not renamed' 1 '^agent rename pane-5 ' "$all"
check 'an agent with its name is not renamed'     1 '^agent rename pane-6 ' "$all"
check 'reattach prints the renamed unit'          0 '^T-ECS-12-triage renamed triage_ecs-12 pane-1$' "$out"
check 'reattach prints the kept name it gave'     0 '^T-ECS-12-02 renamed implementer_ecs-12-02 pane-14$' "$out"
check 'reattach prints an unchanged name'         0 '^T-ECS-12-decompose named decompose_ecs-12 pane-6$' "$out"
check 'reattach prints the unit it did not find'  0 '^T-ECS-12-grill gone$' "$out"
check 'reattach prints a unit with no agent gone' 0 '^T-ECS-12-03 gone$' "$out"
: > "$log"
out=$(ht reattach T-ECS-12)
check 'a second reattach renames nothing'         1 '^agent rename ' "$(cat "$log")"
check 'a second reattach finds the kept name in place' 0 '^T-ECS-12-02 named implementer_ecs-12-02 pane-14$' "$out"

# agents: one line per recorded unit, `-` for a field it has not
: > "$log"
out=$(ht agents T-ECS-12)
check 'agents reads one agent list'               0 '^1$' "$(grep -c '^agent list' "$log")"
check 'agents prints status, pane, session and name' 0 '^T-ECS-12-decompose idle pane-6 sid-6 decompose_ecs-12$' "$out"
check 'agents matches a session in another pane'  0 '^T-ECS-12-02 done pane-14 sid-4 implementer_ecs-12-02$' "$out"
check 'agents reads a unit no agent carries gone' 0 '^T-ECS-12-grill gone - - -$' "$out"
ht agents T-ECS-12-01 >/dev/null 2>&1; rc=$?
check 'agents of a block id exits 1'              0 '^1$' "$rc"

# a legacy id keeps its t-, and a closed record is not reattached
task demo T-264 in_progress
task demo T-264-01 in_progress
ht record T-264-grill tab-8 pane-8 sid-8
ht record T-264-01 tab-9 pane-9 sid-9
printf 'T-264-01 tab-9 closed\n' >> "$tmp/factory/demo/.harness/T-264/herdr-tabs"
herdr_agent - idle pane-8 sid-8
herdr_agent - idle pane-9 sid-9
: > "$log"
out=$(ht reattach T-264)
check 'a legacy step is named <step>_t-<n>'       0 '^agent rename pane-8 grill_t-264 $' "$(cat "$log")"
check 'a closed record is not reattached'         1 'pane-9' "$(cat "$log")$out"
check 'agents reads a closed record closed'       0 '^T-264-01 closed - - -$' "$(ht agents T-264)"

# sweep: the tab of a block at done closes, a block at work keeps its tab, and a step closes with its parent
task ecs T-ECS-13 in_progress
task ecs T-ECS-13-01 done
task ecs T-ECS-13-02 in_progress
ht record T-ECS-13-01 tab-31 pane-31 sid-31
ht record T-ECS-13-02 tab-32 pane-32 sid-32
ht record T-ECS-13-grill tab-33 pane-33 sid-33
herdr_tab tab-31 idle false t-ecs-13-01
herdr_tab tab-32 idle false t-ecs-13-02
herdr_tab tab-33 idle false grill_ecs-13
: > "$log"
out=$(ht sweep T-ECS-13)
all=$(cat "$log")
check 'sweep closes the tab of a done block'      0 '^tab close tab-31 ' "$all"
check 'sweep prints the closed tab'               0 '^T-ECS-13-01 closed tab-31$' "$out"
check 'sweep keeps a block at work'               1 '^tab close tab-32 ' "$all"
check 'sweep keeps a step while the parent runs'  1 '^tab close tab-33 ' "$all"
task ecs T-ECS-13 done
: > "$log"
ht sweep T-ECS-13 >/dev/null
all=$(cat "$log")
check 'a done parent closes its step tab'         0 '^tab close tab-33 ' "$all"
check 'a done parent leaves a block at work'      1 '^tab close tab-32 ' "$all"
check 'a closed tab is not closed again'          1 '^tab close tab-31 ' "$all"
check 'sweep closes no workspace'                 1 '^workspace ' "$all"
check 'the step record reads closed'              0 '^T-ECS-13-grill tab-33 closed$' "$(tabs ecs T-ECS-13)"

task ecs T-ECS-14 in_progress "$state/repos/ecs/archive/2026-09/tasks"
ht record T-ECS-14-triage tab-41 pane-41 sid-41
herdr_tab tab-41 idle false triage_ecs-14
: > "$log"
ht sweep T-ECS-14 >/dev/null
check 'an archived parent closes its step tab'    0 '^tab close tab-41 ' "$(cat "$log")"

task ecs T-ECS-15 done
ht record T-ECS-15 tab-51 pane-51 sid-51
herdr_tab tab-51 idle false t-ecs-15
: > "$log"
out=$(HERDR_TAB_ID=tab-51 sh "$bin/herdr-tabs.sh" sweep T-ECS-15 --state "$state")
check 'the caller tab is kept'                    1 '^tab close tab-51 ' "$(cat "$log")"
check 'sweep says why it kept the tab'            0 '^T-ECS-15 kept tab-51 own tab$' "$out"

task ecs T-ECS-16 in_progress
: > "$log"
out=$(ht sweep T-ECS-16); rc=$?
check 'sweep of a parent with no record exits 0'  0 '^0$' "$rc"
check 'and asks herdr nothing'                    1 '.' "$(cat "$log")"

# without herdr on PATH: close, sweep and reattach do nothing, and agents reads every open unit gone
task ecs T-ECS-17 done
ht record T-ECS-17 tab-71 pane-71 sid-71
herdr_agent t-ecs-17 idle pane-71 sid-71
out=$(PATH=$noherdr sh "$bin/herdr-tabs.sh" close T-ECS-17 --state "$state"); rc=$?
check 'close with no herdr exits 0'               0 '^0$' "$rc"
check 'close with no herdr closes nothing'        0 '^open$' "$(ht state T-ECS-17)"
PATH=$noherdr sh "$bin/herdr-tabs.sh" sweep T-ECS-17 --state "$state" >/dev/null; rc=$?
check 'sweep with no herdr exits 0'               0 '^0$' "$rc"
check 'sweep with no herdr closes nothing'        0 '^open$' "$(ht state T-ECS-17)"
out=$(PATH=$noherdr sh "$bin/herdr-tabs.sh" reattach T-ECS-17 --state "$state"); rc=$?
check 'reattach with no herdr exits 0 and prints nothing' 0 '^0 $' "$rc $out"
out=$(PATH=$noherdr sh "$bin/herdr-tabs.sh" agents T-ECS-17 --state "$state")
check 'agents with no herdr reads the open unit gone' 0 '^T-ECS-17 gone - - -$' "$out"

# the refusals: bad usage and a unit that resolves to no task file
for bad in 'record T-ECS-12-01 tab-1' 'record T-ECS-12-01 tab-1 pane-1 --name' 'name' 'name T-ECS-99' \
  'name nonsense' 'session T-ECS-12-01' 'nosuch T-ECS-12' 'sweep T-ECS-12-01' 'reattach T-ECS-12-01' \
  'record T-ECS-12-01 tab-1 pane-1 --capacity x'; do
  # shellcheck disable=SC2086
  ht $bad >/dev/null 2>&1; rc=$?
  check "herdr-tabs.sh $bad exits 1" 0 '^1$' "$rc"
done

exit $fail
