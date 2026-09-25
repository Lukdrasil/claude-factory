#!/bin/sh
# org-check.sh over the herdr stub and a throwaway state clone: an agent blocked or idle past its threshold is one
# line, printed again only after --repeat minutes while it lasts, a status change starts the clock over, an idle
# agent with an open ask of the UI, the CEO and an unnamed agent are never a finding, and approved parents waiting
# while capacity is free are one queue line. ORG_CHECK_NOW stands in for the clock.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
FACTORY_UI_HOME="$tmp/ui"
WORK_DIR=''
export FACTORY_UI_HOME WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s:\n  expected [%s]\n  got      [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

st="$tmp/factory/state"
mkdir -p "$st/repos/demo/tasks"
git init -q -b main "$st"
printf 'demo: { path: %s/demo }\n' "$tmp" > "$st/repos.yml"
printf 'capacity:\n  sessions: 10\n  roles: {repo-lead: 3}\n' > "$st/factory.yml"

t0=1790000000
oc() { # <minutes after t0> [args...]
  m=$1; shift
  ORG_CHECK_NOW=$((t0 + m * 60)) sh "$bin/org-check.sh" --once --state "$st" "$@" 2>&1
}

# blocked: a line at 10 minutes, not before, again only after 30 more
herdr_agent implementer_demo-7-01 blocked pane-1 s-impl
check 'a fresh block prints nothing'                  '' "$(oc 0)"
check 'blocked for 9 minutes prints nothing'          '' "$(oc 9)"
check 'blocked for 11 minutes is one line'            'implementer_demo-7-01 blocked 11 min' "$(oc 11)"
check 'the same block a minute later prints nothing'  '' "$(oc 12)"
check 'the block again after 30 more minutes'         'implementer_demo-7-01 blocked 42 min' "$(oc 42)"

# a status change starts the clock over
herdr_agent implementer_demo-7-01 working pane-1 s-impl
check 'a working agent prints nothing'                '' "$(oc 43)"
herdr_agent implementer_demo-7-01 blocked pane-1 s-impl
check 'blocked again 6 minutes later prints nothing'  '' "$(oc 49)"
herdr_agent implementer_demo-7-01 working pane-1 s-impl

# idle or done with no open ask: stalled or finished and left open
herdr_agent grill_demo-8 idle pane-2 s-grill
herdr_agent lead_demo-9 done pane-3 s-lead
oc 50 >/dev/null
check 'idle and done agents after 10 minutes are one line each' \
  'grill_demo-8 idle 10 min, no open ask
lead_demo-9 idle 10 min, no open ask' "$(oc 60)"

# an idle agent whose session has an open ask waits on the human, not on the CEO
mkdir -p "$FACTORY_UI_HOME/sessions/s-wait/asks"
printf -- '---\nask: q1\nstatus: open\n---\n\nWhich?\n' > "$FACTORY_UI_HOME/sessions/s-wait/asks/q1.md"
herdr_agent decompose_demo-10 idle pane-4 s-wait
herdr_agent ceo idle pane-5 s-ceo
herdr_agent - idle pane-6 s-human
oc 61 >/dev/null
out=$(oc 80)
case "$out" in *decompose_demo-10*) check 'an idle agent with an open ask is no finding' '' "$out" ;;
  *) check 'an idle agent with an open ask is no finding' ok ok ;; esac
case "$out" in *ceo*) check 'the CEO is never a finding' '' "$out" ;; *) check 'the CEO is never a finding' ok ok ;; esac
case "$out" in *s-human*|*' idle'*pane-6*) check 'an unnamed agent is never a finding' '' "$out" ;;
  *) check 'an unnamed agent is never a finding' ok ok ;; esac
for p in pane-2 pane-3 pane-4 pane-5 pane-6; do rm -f "$HERDR_STUB_DIR/panes/$p"; done

# approved parents waiting while two sessions and a repo-lead slot are free
printf -- '---\nid: T-101\nrepo: demo\nstatus: ready\npriority: P1\nrequest: R-20260925-1\nowner: null\ndepends_on: []\n---\n\n# Goal\nfix(demo): x\n' \
  > "$st/repos/demo/tasks/T-101-demo.md"
check 'a waiting parent with free capacity is the queue line' 'queue 1 parents wait with 10 sessions free' "$(oc 100)"
check 'the queue line waits 30 minutes to repeat'      '' "$(oc 101)"
i=1
while [ "$i" -le 9 ]; do sh "$bin/capacity.sh" acquire sessions "T-X-$i" --state "$st"; i=$((i + 1)); done
rm -f "$tmp/factory/.org-check.state"
check 'with one session slot free the queue is no finding' '' "$(ORG_CHECK_NOW=$((t0 + 6000)) sh "$bin/org-check.sh" --once --state "$st" 2>&1)"

# herdr that does not answer is a pass with no agent finding, and the usage is checked
out=$(PATH="$tmp/nobin:/usr/bin:/bin" ORG_CHECK_NOW=$t0 sh "$bin/org-check.sh" --once --state "$st" 2>&1); rc=$?
check 'no herdr on PATH still exits 0'                 0 "$rc"
sh "$bin/org-check.sh" --once --state "$tmp/nowhere" >/dev/null 2>&1; rc=$?
check 'no state clone exits 1'                         1 "$rc"
sh "$bin/org-check.sh" --once --state "$st" --blocked x >/dev/null 2>&1; rc=$?
check 'a threshold that is no number exits 1'          1 "$rc"

exit $fail
