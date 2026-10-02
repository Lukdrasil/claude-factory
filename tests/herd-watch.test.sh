#!/bin/sh
# herd-watch.sh over a throwaway state repo: the first pass prints the picture, an unchanged pass prints
# nothing, a status or phase change prints one line with the transition, and the forge state mr-watch.sh
# recorded for a block becomes an `<id> mr <old> -> <new>` line, so the watch does not end at `review`. The
# agent column comes from one `herdr agent list` per pass, matched by the recorded pane and session id; the
# step units are triage, grill, plan-check and decompose; what was reported is kept in herd-watch.state, one
# five-column line per unit, and every pass ends with state-push.sh. The herdr on PATH is always the stub, from
# the first pass on.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_PANE_ID FACTORY_UNIT
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"

state="$tmp/factory/state"
mkdir -p "$state/repos/demo/tasks"
task() { # <id> <status> <phase> [<tasks dir>]
  d=${4:-$state/repos/demo/tasks}
  mkdir -p "$d"
  cat > "$d/$1.md" <<TASK
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
check 'a phase of null is not reported'    1 '^T-001-01 phase' "$out"
check 'a step nobody dispatched is not news' 1 '^T-001-\(triage\|grill\|plan-check\|decompose\) ' "$out"
seen="$tmp/factory/demo/.harness/T-001/herd-watch.state"
check 'the state file keeps six columns per unit' 0 '^T-001-01 in_progress none gone none 0$' "$(cat "$seen" 2>/dev/null)"

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
# a comment on an MR that stays open is news through the count mr-watch.sh keeps, the task MR's review included
printf 'T-001-01 merged 2\nT-001 open 3\n' > "$harness/mr-watch.state"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'new comments on a block MR print the count'    0 '^T-001-01 comments 0 -> 2$' "$out"
check 'the task MR is sighted'                       0 '^T-001 mr none -> open$' "$out"
check 'its comments are counted from zero'            0 '^T-001 comments 0 -> 3$' "$out"
printf 'T-001-01 merged 2\nT-001 open 5\n' > "$harness/mr-watch.state"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'more comments on the task MR print the step'  0 '^T-001 comments 3 -> 5$' "$out"
check 'an unchanged count prints nothing'            1 '^T-001-01 comments' "$out"
# a state file from before the comments column: the first count is a baseline, not a line
printf 'T-001 in_progress none gone open\nT-001-01 in_progress none gone merged\n' > "$seen"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'an old five-column record reports no comments line' 1 ' comments ' "$out"
check 'but the record now carries the count'            0 '^T-001 in_progress none gone open 5$' "$(cat "$seen")"
printf 'T-001-01 merged 2\nT-001 open 6\n' > "$harness/mr-watch.state"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'and the next count is news from that baseline' 0 '^T-001 comments 5 -> 6$' "$out"
# an MR whose count mr-watch.sh could not read yet (its first inline call failed) is no count: the first count
# read after it is the baseline, not every comment on the MR as new
printf 'T-001-01 merged 2\nT-001 open \n' > "$harness/mr-watch.state"
printf 'T-001 in_progress none gone open 6\nT-001-01 in_progress none gone merged 2\n' > "$seen"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'a count not read yet prints no comments line'    1 '^T-001 comments' "$out"
check 'and the record says so'                          0 '^T-001 in_progress none gone open -$' "$(cat "$seen")"
printf 'T-001-01 merged 2\nT-001 open 4\n' > "$harness/mr-watch.state"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'the first count read after it is the baseline'   1 '^T-001 comments' "$out"
check 'and is recorded'                                  0 '^T-001 in_progress none gone open 4$' "$(cat "$seen")"
printf 'T-001-01 merged 2\nT-001 open 5\n' > "$harness/mr-watch.state"
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'and the next count is news from it'              0 '^T-001 comments 4 -> 5$' "$out"
printf 'T-001-01 merged 2\n' > "$harness/mr-watch.state"

out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
if [ -z "$out" ]; then printf 'PASS a pass after the merge is silent\n'; else printf 'FAIL a pass after the merge printed: %s\n' "$out"; fail=1; fi

# one watcher, one state file: herd-watch.state, whatever unit runs the watcher
FACTORY_UNIT=T-001-lead sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state" >/dev/null
check 'the state file is always herd-watch.state' 0 '^herd-watch.state $' \
  "$(ls "$harness" | grep '^herd-watch' | LC_ALL=C sort | tr '\n' ' ')"

# the tab record: a unit whose work is over has its recorded tab closed once, and reads as agent `closed`
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
check 'a live recorded idle session reads ready' 0 '^T-002-01 agent ready$' "$out"
check 'a unit at in_progress keeps its tab'       1 '^tab close tab-21 ' "$(cat "$log")"
task T-002-01 done null
out=$(sh "$bin/herd-watch.sh" T-002 --once --no-mr --state "$state")
out2=$(sh "$bin/herd-watch.sh" T-002 --once --no-mr --state "$state")
check 'a unit gone done reads agent closed'       0 '^T-002-01 agent ready -> closed$' "$out"
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
check 'a live step is tracked from its first pass' 0 '^T-004-triage agent ready$' "$out"
check 'a step unit carries no status line'        1 '^T-004-grill status' "$out"
task T-004 done null
out=$(sh "$bin/herd-watch.sh" T-004 --once --no-mr --state "$state")
all=$(cat "$log")
check 'a parent at done closes the triage tab'    0 '^tab close tab-41 ' "$all"
check 'a parent at done closes the grill tab'     0 '^tab close tab-42 ' "$all"
check 'a closed step tab reads agent closed'      0 '^T-004-grill agent ready -> closed$' "$out"

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

# one `agent list` per pass, matched by the recorded pane, never an `agent get` per unit; idle and done read ready
recs() { # <T-NNN> <unit> <tab_id> <session>
  mkdir -p "$tmp/factory/demo/.harness/$1"
  printf '%s %s pane-%s %s\n' "$2" "$3" "${3#tab-}" "$4" >> "$tmp/factory/demo/.harness/$1/herdr-tabs"
}
task T-007 in_progress null
task T-007-01 in_progress null
task T-007-02 in_progress null
rec T-007 T-007-01 tab-71
rec T-007 T-007-02 tab-72
herdr_agent - working pane-71
herdr_agent - done pane-72
: > "$log"
out=$(sh "$bin/herd-watch.sh" T-007 --once --no-mr --state "$state")
lists=$(grep -c '^agent list' "$log") gets=$(grep -c '^agent get' "$log")
if [ "$lists" -eq 1 ] && [ "$gets" -eq 0 ]; then printf 'PASS one agent list per pass and no agent get\n'
else printf 'FAIL a pass ran %s agent list and %s agent get\n' "$lists" "$gets"; fail=1; fi
check 'an unnamed agent at the recorded pane is the unit' 0 '^T-007-01 agent working$' "$out"
check 'done reads ready'                          0 '^T-007-02 agent ready$' "$out"

# the recorded session id: another session at the pane is gone, the session in another pane is still the unit
task T-008 in_progress null
task T-008-01 in_progress null
task T-008-02 in_progress null
task T-008-03 in_progress null
recs T-008 T-008-01 tab-81 sid-81
recs T-008 T-008-02 tab-82 sid-82
recs T-008 T-008-03 tab-83 sid-83
herdr_agent - working pane-81 sid-81
herdr_agent - working pane-82 sid-other
herdr_agent - blocked pane-93 sid-83
out=$(sh "$bin/herd-watch.sh" T-008 --once --no-mr --state "$state")
check 'the recorded pane and session match'       0 '^T-008-01 agent working$' "$out"
check 'another session at the pane is gone'       0 '^T-008-02 agent gone$' "$out"
check 'the session in another pane is matched'    0 '^T-008-03 agent blocked$' "$out"

# the steps: plan-check and decompose beside triage and grill; a step that was live and ended reads gone, and
# lead and chart are no units of the watcher any more
task T-009 in_progress null
recs T-009 T-009-plan-check tab-91 sid-91
recs T-009 T-009-decompose tab-92 sid-92
recs T-009 T-009-lead tab-93 sid-93
recs T-009 T-009-chart tab-94 sid-94
herdr_agent plan-check_t-009 working pane-91 sid-91
herdr_agent decompose_t-009 idle pane-92 sid-92
herdr_agent lead_t-009 working pane-93 sid-93
herdr_agent chart_t-009 working pane-94 sid-94
out=$(sh "$bin/herd-watch.sh" T-009 --once --no-mr --state "$state")
check 'the plan-check step is watched'            0 '^T-009-plan-check agent working$' "$out"
check 'the decompose step is watched'             0 '^T-009-decompose agent ready$' "$out"
check 'a lead is no unit of the watcher'          1 '^T-009-lead ' "$out"
check 'a chart is no unit of the watcher'         1 '^T-009-chart ' "$out"
rm -f "$HERDR_STUB_DIR/panes/pane-91"
out=$(sh "$bin/herd-watch.sh" T-009 --once --no-mr --state "$state")
check 'a step that ended reads gone'              0 '^T-009-plan-check agent working -> gone$' "$out"
out=$(sh "$bin/herd-watch.sh" T-009 --once --no-mr --state "$state")
check 'a gone step is not repeated'               1 '^T-009-plan-check ' "$out"

# a pass herdr does not answer reads every open unit unknown
task T-010 in_progress null
task T-010-01 in_progress null
recs T-010 T-010-01 tab-101 sid-101
herdr_agent - working pane-101 sid-101
sh "$bin/herd-watch.sh" T-010 --once --no-mr --state "$state" >/dev/null
mkdir -p "$tmp/deaf"
printf '#!/bin/sh\nexit 1\n' > "$tmp/deaf/herdr"
chmod +x "$tmp/deaf/herdr"
out=$(PATH="$tmp/deaf:$PATH" sh "$bin/herd-watch.sh" T-010 --once --no-mr --state "$state")
check 'a herdr that does not answer reads unknown' 0 '^T-010-01 agent working -> unknown$' "$out"

# an archived parent is still watched, its blocks with it
arch="$state/repos/demo/archive/2026-09/tasks"
task T-011 done null "$arch"
task T-011-01 done null "$arch"
out=$(sh "$bin/herd-watch.sh" T-011 --once --no-mr --state "$state")
check 'an archived parent is watched'             0 '^T-011 status done$' "$out"
check 'the block of an archived parent too'       0 '^T-011-01 status done$' "$out"

# the refusals
for bad in '' 'T-001-01' 'nonsense' 'T-404' 'T-001 T-002' 'T-001 --interval x' 'T-001 --ask'; do
  # shellcheck disable=SC2086
  sh "$bin/herd-watch.sh" $bad --once --no-mr --state "$state" >/dev/null 2>&1; rc=$?
  check "herd-watch.sh $bad exits 1" 0 '^1$' "$rc"
done

# every pass ends with state-push.sh, whether or not it printed anything
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
git -C "$state" add -A
git -C "$state" commit -q -m 'the fixture state'
git init -q --bare "$tmp/state-root"
git -C "$state" remote add origin "$tmp/state-root"
git -C "$state" push -q -u origin main 2>/dev/null
git -C "$state" commit -q --allow-empty -m 'a report of a session'
out=$(sh "$bin/herd-watch.sh" T-001 --once --no-mr --state "$state")
check 'a silent pass prints nothing'              1 '.' "$out"
check 'the pass pushes the reports of the sessions' 0 '^a report of a session$' "$(git -C "$tmp/state-root" log --format=%s main)"

exit $fail
