#!/bin/sh
# herd-watch.sh over a throwaway state repo: the first pass prints the picture, an unchanged pass prints
# nothing, a status or phase change prints one line with the transition, and the forge state mr-watch.sh
# recorded for a block becomes an `<id> mr <old> -> <new>` line, so the watch does not end at `review`.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/factory/state"
mkdir -p "$state/repos/demo/tasks"
task() { # <id> <status> <phase>
  cat > "$state/repos/demo/tasks/$1.md" <<TASK
---
id: $1
repo: demo
status: $2
phase: $3
archetype: feature
tier: green
complexity: low
---

# Goal
feat(demo): a goal that is also a title
TASK
}
task T-001 in_progress null
task T-001-01 in_progress null

fail=0
check() { # <label> <want 0 match|1 no match> <pattern> <text>
  if printf '%s\n' "$4" | grep -q "$3"; then got=0; else got=1; fi
  if [ "$got" -eq "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

out=$(sh "$bin/herd-watch.sh" T-001 --once --state "$state")
check 'the first pass reports the parent'  0 '^T-001 status in_progress$' "$out"
check 'the first pass reports the block'   0 '^T-001-01 status in_progress$' "$out"
check 'a block with no session is gone'    0 '^T-001-01 agent gone$' "$out"

out=$(sh "$bin/herd-watch.sh" T-001 --once --state "$state")
if [ -z "$out" ]; then printf 'PASS an unchanged pass is silent\n'; else printf 'FAIL an unchanged pass printed: %s\n' "$out"; fail=1; fi

task T-001-01 tests_ready null
out=$(sh "$bin/herd-watch.sh" T-001 --once --state "$state")
check 'a status change prints the transition' 0 '^T-001-01 status in_progress -> tests_ready$' "$out"
check 'the parent is not repeated'            1 '^T-001 status' "$out"

task T-001-01 in_progress implement
out=$(sh "$bin/herd-watch.sh" T-001 --once --state "$state")
check 'a phase change prints the transition'  0 '^T-001-01 phase none -> implement$' "$out"

# the forge column: mr-watch.sh's own state file is what the watcher reads, so `--no-mr` (no forge here) still
# reports the MR of a block that has one
harness="$tmp/factory/demo/.harness/T-001"
mkdir -p "$harness"
printf 'T-001-01 open 0\n' > "$harness/mr-watch.state"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'an MR is reported when it appears'  0 '^T-001-01 mr none -> open$' "$out"

printf 'T-001-01 merged 0\n' > "$harness/mr-watch.state"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'a merge prints the transition'      0 '^T-001-01 mr open -> merged$' "$out"

out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
if [ -z "$out" ]; then printf 'PASS a pass after the merge is silent\n'; else printf 'FAIL a pass after the merge printed: %s\n' "$out"; fail=1; fi

# the tab record: a unit whose work is over has its recorded tab closed once, and reads as agent `closed`
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
HERDR_TAB_ID=tab-32
export HERDR_TAB_ID
log=$HERDR_STUB_LOG
rec() { # <T-NNN> <unit> <tab_id>
  mkdir -p "$tmp/factory/demo/.harness/$1"
  printf '%s %s pane-%s\n' "$2" "$3" "${3#tab-}" >> "$tmp/factory/demo/.harness/$1/herdr-tabs"
}
closes() { grep -c "^tab close $1 " "$log"; }

task T-002 in_progress null
task T-002-01 in_progress null
rec T-002 T-002-01 tab-21
herdr_tab tab-21 idle false t-002-01
out=$(sh "$bin/herd-watch.sh" T-002 --once --no-mr --state "$state")
check 'a live recorded session reads idle'        0 '^T-002-01 agent idle$' "$out"
check 'a unit at in_progress keeps its tab'       1 '^tab close tab-21 ' "$(cat "$log")"
task T-002-01 done null
out=$(sh "$bin/herd-watch.sh" T-002 --once --no-mr --state "$state")
out2=$(sh "$bin/herd-watch.sh" T-002 --once --no-mr --state "$state")
check 'a unit gone done reads agent closed'       0 '^T-002-01 agent idle -> closed$' "$out"
check 'a closed tab never reads gone'             1 ' -> gone$' "$out
$out2"
check 'the close is in the tab record'            0 '^T-002-01 tab-21 closed$' "$(cat "$tmp/factory/demo/.harness/T-002/herdr-tabs")"
if [ "$(closes tab-21)" -eq 1 ]; then printf 'PASS two passes close the recorded tab once\n'
else printf 'FAIL two passes closed tab-21 %s times\n' "$(closes tab-21)"; fail=1; fi

# the guards: focus, the caller's own tab, a live agent, a unit that is not over, a tab nobody recorded
task T-003 in_progress null
g=0
for s in done:idle:true done:idle:false done:working:false done:blocked:false \
  review:idle:false blocked:idle:false failed:idle:false done:idle:false done:idle:false; do
  g=$((g + 1))
  u="T-003-0$g"
  task "$u" "${s%%:*}" null
  st=${s#*:}
  herdr_tab "tab-3$g" "${st%:*}" "${st#*:}" "t-003-0$g"
  [ "$g" -eq 8 ] || rec T-003 "$u" "tab-3$g"
done
out=$(sh "$bin/herd-watch.sh" T-003 --once --no-mr --state "$state")
all=$(cat "$log")
check 'a focused tab is kept'                     1 '^tab close tab-31 ' "$all"
check 'the HERDR_TAB_ID tab is kept'              1 '^tab close tab-32 ' "$all"
check 'a working agent is kept'                   1 '^tab close tab-33 ' "$all"
check 'a blocked agent is kept'                   1 '^tab close tab-34 ' "$all"
check 'a unit at review is kept'                  1 '^tab close tab-35 ' "$all"
check 'a unit at blocked is kept'                 1 '^tab close tab-36 ' "$all"
check 'a unit at failed is kept'                  1 '^tab close tab-37 ' "$all"
check 'a tab not in the record is kept'           1 '^tab close tab-38 ' "$all"
check 'the idle recorded done unit is closed'     0 '^tab close tab-39 ' "$all"

# step tabs have no status of their own: they close when the parent is over, not before
task T-004 in_progress null
rec T-004 T-004-triage tab-41
rec T-004 T-004-grill tab-42
herdr_tab tab-41 idle false t-004-triage
herdr_tab tab-42 idle false t-004-grill
out=$(sh "$bin/herd-watch.sh" T-004 --once --no-mr --state "$state")
check 'a step tab stays while the parent runs'    1 '^tab close tab-4' "$(cat "$log")"
task T-004 done null
out=$(sh "$bin/herd-watch.sh" T-004 --once --no-mr --state "$state")
all=$(cat "$log")
check 'a parent at done closes the triage tab'    0 '^tab close tab-41 ' "$all"
check 'a parent at done closes the grill tab'     0 '^tab close tab-42 ' "$all"
check 'a closed step tab reads agent closed'      0 '^T-004-grill agent idle -> closed$' "$out"

# a recorded tab herdr no longer has: the close answers tab_not_found, which is a close, not an error
task T-005 in_progress null
task T-005-01 done null
rec T-005 T-005-01 tab-51
err=$(sh "$bin/herd-watch.sh" T-005 --once --no-mr --state "$state" 2>&1 >/dev/null); rc=$?
err2=$(sh "$bin/herd-watch.sh" T-005 --once --no-mr --state "$state" 2>&1 >/dev/null); rc2=$?
if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -z "$err$err2" ]; then printf 'PASS tab_not_found is no error\n'
else printf 'FAIL tab_not_found exited %s/%s with: %s\n' "$rc" "$rc2" "$err$err2"; fail=1; fi
check 'tab_not_found appends the closed line'     0 '^T-005-01 tab-51 closed$' "$(cat "$tmp/factory/demo/.harness/T-005/herdr-tabs")"
if [ "$(closes tab-51)" -eq 0 ]; then printf 'PASS a tab get tab_not_found calls no tab close\n'
else printf 'FAIL tab-51 was closed %s times\n' "$(closes tab-51)"; fail=1; fi

# a tab get that fails for another reason, or answers with no focused field, keeps the tab
task T-006 in_progress null
task T-006-01 done null
task T-006-02 done null
rec T-006 T-006-01 tab-61
rec T-006 T-006-02 tab-62
herdr_tab tab-61 idle false t-006-01
herdr_tab tab-62 idle false t-006-02
herdr_tab_reply tab-61 1 '{"error":{"code":"timeout","message":"server did not answer"},"id":"cli:tab:get"}'
herdr_tab_reply tab-62 0 '{"id":"cli:tab:get","result":{"tab":{"agent_status":"idle","tab_id":"tab-62"},"type":"tab_info"}}'
out=$(sh "$bin/herdr-tabs.sh" close T-006-01 T-006-02 --state "$state" 2>/dev/null)
all=$(cat "$log")
tabs=$(cat "$tmp/factory/demo/.harness/T-006/herdr-tabs")
check 'a failed tab get calls no tab close'       1 '^tab close tab-61 ' "$all"
check 'a failed tab get prints the kept reason'   0 '^T-006-01 kept tab-61 tab get failed$' "$out"
check 'a failed tab get appends no closed line'   1 '^T-006-01 tab-61 closed$' "$tabs"
check 'a reply with no focused calls no close'    1 '^tab close tab-62 ' "$all"
check 'a reply with no focused is kept'           0 '^T-006-02 kept tab-62 tab get failed$' "$out"
check 'a reply with no focused appends nothing'   1 '^T-006-02 tab-62 closed$' "$tabs"

exit $fail
