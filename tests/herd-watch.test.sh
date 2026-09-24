#!/bin/sh
# herd-watch.sh over a throwaway state repo: the first pass prints the picture, an unchanged pass prints
# nothing, a status or phase change prints one line with the transition, and the forge state mr-watch.sh
# recorded for a block becomes an `<id> mr <old> -> <new>` line, so the watch does not end at `review`. The
# agent column comes from one `herdr agent list` per pass, matched by the recorded pane and session id; a step
# unit at the prompt with an open ask prints `<unit> waits <ask>` and runs notify.sh; a unit that reads gone,
# closed or done has its capacity leases released. notify.sh is checked on its own at the end. The herdr on
# PATH is always the stub, from the first pass on.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
FACTORY_UI_HOME="$tmp/ui"
export FACTORY_UI_HOME

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

# the steps: chart and lead beside triage, grill, plan-check and decompose
task T-009 in_progress null
recs T-009 T-009-lead tab-91 sid-91
recs T-009 T-009-chart tab-92 sid-92
herdr_agent lead_t-009 working pane-91 sid-91
herdr_agent chart_t-009 idle pane-92 sid-92
out=$(sh "$bin/herd-watch.sh" T-009 --once --no-mr --state "$state")
check 'the lead step is watched'                  0 '^T-009-lead agent working$' "$out"
check 'the chart step is watched'                 0 '^T-009-chart agent ready$' "$out"

# a step at the prompt with an open ask waits: one `waits` line and one notification per ask
ask() { # <sid> <ask> <status> <question title>
  mkdir -p "$FACTORY_UI_HOME/sessions/$1/asks"
  printf -- '---\nask: %s\ntask: T-010\nflow: grill\nstep: round 1\nstatus: %s\n---\n\n%s\n' "$2" "$3" \
    "❓ **Q1** - **$4**: the question.
  **A** the first
  **B** the second" > "$FACTORY_UI_HOME/sessions/$1/asks/$2.md"
}
shows() { grep -c '^notification show' "$log"; }
printf '7171\n' > "$tmp/port" && mkdir -p "$FACTORY_UI_HOME" && mv "$tmp/port" "$FACTORY_UI_HOME/port"
task T-010 in_progress null
recs T-010 T-010-grill tab-101 sid-g
herdr_agent grill_t-010 working pane-101 sid-g
ask sid-g r1 open 'Which way'
out=$(sh "$bin/herd-watch.sh" T-010 --once --no-mr --state "$state")
check 'an open ask of a working step is no wait'  1 'waits' "$out"
herdr_agent grill_t-010 done pane-101 sid-g
: > "$log"
out=$(sh "$bin/herd-watch.sh" T-010 --once --no-mr --state "$state")
all=$(cat "$log")
check 'the step turns ready'                      0 '^T-010-grill agent working -> ready$' "$out"
check 'a ready step with an open ask waits'       0 '^T-010-grill waits r1$' "$out"
check 'the wait is shown with its label'          0 '^notification show "[^"]*demo T-010-grill waits" ' "$all"
check 'the body holds the question and the URL'   0 '^notification show .*--body "Q1 - Which way: the question\. http://127\.0\.0\.1:7171/?ask=sid-g/r1' "$all"
check 'the notification asks with a sound'        0 '^notification show .*--sound request' "$all"
out=$(sh "$bin/herd-watch.sh" T-010 --once --no-mr --state "$state")
check 'a wait already reported is not repeated'   1 'waits' "$out"
if [ "$(shows)" -eq 1 ]; then printf 'PASS one notification per ask\n'
else printf 'FAIL the ask was notified %s times\n' "$(shows)"; fail=1; fi
ask sid-g r1 answered 'Which way'
ask sid-g r2 open 'Which name'
out=$(sh "$bin/herd-watch.sh" T-010 --once --no-mr --state "$state")
check 'the next ask is a new wait'                0 '^T-010-grill waits r2$' "$out"
if [ "$(shows)" -eq 2 ]; then printf 'PASS the next ask is notified\n'
else printf 'FAIL after the next ask %s notifications\n' "$(shows)"; fail=1; fi
rec T-010 T-010-plan-check tab-102
herdr_agent - idle pane-102 sid-p
mkdir -p "$FACTORY_UI_HOME/sessions/sid-p"
printf -- '---\nsid: sid-p\npane: pane-102\nflow: solve\ntask: T-010\nstep: plan-check\n---\n' > "$FACTORY_UI_HOME/sessions/sid-p/session.md"
ask sid-p p1 open 'Is the plan right'
out=$(sh "$bin/herd-watch.sh" T-010 --once --no-mr --state "$state")
check 'a record with no session finds the ask by its pane' 0 '^T-010-plan-check waits p1$' "$out"

# the leases of a unit that reads gone, closed or done are released; a unit still at work keeps them
cap() { sh "$bin/capacity.sh" "$@" --state "$state" >/dev/null 2>&1; }
leased() { [ -f "$state/.capacity/$1/$2" ]; }
task T-011 in_progress null
for n in 1 2 3 4; do
  task "T-011-0$n" in_progress null
  recs T-011 "T-011-0$n" "tab-11$n" "sid-11$n"
  herdr_agent - working "pane-11$n" "sid-11$n"
  cap acquire sessions "T-011-0$n"
  cap acquire implementer "T-011-0$n"
done
recs T-011 T-011-lead tab-115 sid-115
herdr_agent lead_t-011 working pane-115 sid-115
cap acquire sessions T-011-lead
cap acquire repo-lead T-011
sh "$bin/herd-watch.sh" T-011 --once --no-mr --state "$state" >/dev/null
if leased sessions T-011-01 && leased implementer T-011-04 && leased repo-lead T-011; then
  printf 'PASS units at work keep their leases\n'
else printf 'FAIL a lease of a unit at work was released\n'; fail=1; fi
rm -f "$HERDR_STUB_DIR/panes/pane-111" "$HERDR_STUB_DIR/panes/pane-115"
task T-011-02 done null
sh "$bin/herdr-tabs.sh" close T-011-03 --state "$state" >/dev/null
out=$(sh "$bin/herd-watch.sh" T-011 --once --no-mr --state "$state")
check 'the dead unit reads gone'                  0 '^T-011-01 agent working -> gone$' "$out"
check 'the closed unit reads closed'              0 '^T-011-03 agent working -> closed$' "$out"
for c in sessions:T-011-01 implementer:T-011-01 sessions:T-011-02 implementer:T-011-02 \
  sessions:T-011-03 implementer:T-011-03 sessions:T-011-lead repo-lead:T-011; do
  if leased "${c%%:*}" "${c#*:}"; then printf 'FAIL the lease %s stays\n' "$c"; fail=1
  else printf 'PASS the lease %s is released\n' "$c"; fi
done
if leased sessions T-011-04 && leased implementer T-011-04; then printf 'PASS the unit at work keeps its leases\n'
else printf 'FAIL the unit at work lost a lease\n'; fail=1; fi

# notify.sh: once per ask, again only while the pane stays unseen (done) and the last one is old
task T-012 in_progress null
recs T-012 T-012-grill tab-121 sid-121
herdr_agent grill_t-012 done pane-121 sid-121
notify() { sh "$bin/notify.sh" T-012-grill 'L T-012-grill' "$@" --state "$state"; }
url='http://127.0.0.1:7171/?ask=sid-121/a1'
: > "$log"
notify 'Q1 - Pick one?' "$url"; rc=$?
all=$(cat "$log")
check 'notify.sh exits 0'                         0 '^0$' "$rc"
check 'notify.sh shows the label waits'           0 '^notification show "L T-012-grill waits" --body "Q1 - Pick one? http://127\.0\.0\.1:7171/?ask=sid-121/a1" --sound request $' "$all"
stamps() { ls "$tmp/factory/demo/.harness/T-012/" | grep -c '^notified-T-012-grill-'; }
check 'notify.sh stamps the ask'                  0 '^1$' "$(stamps)"
notify 'Q1 - Pick one?' "$url"
check 'the same ask is not shown twice'           0 '^1$' "$(shows)"
touch -t 200001010000 "$tmp/factory/demo/.harness/T-012/"notified-T-012-grill-*
notify 'Q1 - Pick one?' "$url"
check 'an old ask still unseen is shown again'    0 '^2$' "$(shows)"
notify 'Q1 - Pick one?' "$url"
check 'the reminder restarts the period'          0 '^2$' "$(shows)"
touch -t 200001010000 "$tmp/factory/demo/.harness/T-012/"notified-T-012-grill-*
herdr_agent grill_t-012 idle pane-121 sid-121
notify 'Q1 - Pick one?' "$url"
check 'a seen pane is not reminded'               0 '^2$' "$(shows)"
HERDR_STUB_NOTIFY=disabled notify 'Q2 - Another?' "$url"; rc=$?
check 'a notification not shown exits 0'          0 '^0$' "$rc"
check 'a notification not shown leaves no stamp'  0 '^1$' "$(stamps)"
notify 'Q3 - No page?'
check 'without a URL the body names the tab'      0 '^notification show "L T-012-grill waits" --body "Q3 - No page? tab L T-012-grill" ' "$(cat "$log")"
check 'the ask without a URL is stamped too'      0 '^2$' "$(stamps)"

exit $fail
