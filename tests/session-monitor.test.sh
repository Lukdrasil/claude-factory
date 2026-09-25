#!/bin/sh
# session-monitor.sh over a throwaway state repo: a bare call names no task and only lists what is ready,
# --all dispatches the batch, --task dispatches exactly one unit - the wave of a cut's blocks, or a ready leaf
# alone - an owned task is skipped, a task with no worktree is skipped, the manual mode prints a command
# instead of spawning anything, a parent with an open block MR gets its mr-watch.sh pass, and a real dispatch
# claims the unit in the state clone before the session starts.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

root="$tmp/factory"
state="$root/state"
mkdir -p "$state/repos/demo/tasks" "$root/demo/T-001"
printf 'spawn: manual\n' > "$state/factory.yml"

task() { # <id> <owner> <archetype>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: ready
archetype: $3
tier: green
complexity: low
owner: $2
---

# Goal
feat(demo): a goal that is also a title
EOF
}
task T-001 null feature
task T-002 null feature      # no worktree under \$root/demo/T-002
task T-003 factory@host:abc feature

fail=0
check() { # <what> <pattern>
  if printf '%s\n' "$out" | grep -q "$2"; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
nocheck() { # <what> <pattern>
  if printf '%s\n' "$out" | grep -q "$2"; then printf 'FAIL %s\n' "$1"; fail=1; else printf 'PASS %s\n' "$1"; fi
}

# the bare call: the question "which task", answered with the list, never with a dispatch
out=$(sh "$bin/session-monitor.sh" --state "$state" 2>/dev/null); rc=$?
if [ "$rc" -eq 1 ]; then printf 'PASS a bare call exits 1\n'; else printf 'FAIL a bare call exited %s\n' "$rc"; fail=1; fi
check 'a bare call lists the ready task'   '^T-001 demo ready feature feat(demo): a goal that is also a title$'
check 'a bare call lists the second one'   '^T-002 demo ready feature '
nocheck 'a bare call dispatches nothing'   'printed\|spawned'
nocheck 'a bare call leaves owned tasks out' '^T-003 '
err=$(sh "$bin/session-monitor.sh" --state "$state" 2>&1 >/dev/null || :)
out=$err
check 'the bare call asks for one task'    'name one task: --task T-NNN'

# --all: the batch mode, which now has to be asked for by name
out=$(sh "$bin/session-monitor.sh" --all --state "$state" 2>/dev/null)
check 'T-001 is printed'            '^T-001 printed '
check 'T-001 gets a claude command' 'claude --model .* "First take ownership of T-001'
check 'the prompt carries the skill' '/claude-factory:block-feature '
check 'T-002 is skipped'            '^T-002 skipped '
nocheck 'an owned task is left alone' '^T-003'

# --task: one unit and nothing else
out=$(sh "$bin/session-monitor.sh" --task T-001 --state "$state" --dry-run 2>/dev/null)
check 'the named leaf is dispatched'  '^T-001 printed '
nocheck 'no other task rides along'   '^T-002'
out=$(sh "$bin/session-monitor.sh" --task T-003 --state "$state" --dry-run 2>/dev/null)
check 'an owned task is skipped'      '^T-003 skipped '

# --task of a parent with a cut: the current wave of its blocks, not the parent itself
mkdir -p "$root/demo/T-006-01"
cat > "$state/repos/demo/tasks/T-006.md" <<'EOF'
---
id: T-006
repo: demo
status: in_progress
archetype: feature
tier: green
complexity: low
---

# Goal
feat(demo): a parent with one block
EOF
cat > "$state/repos/demo/tasks/T-006-01.md" <<'EOF'
---
id: T-006-01
repo: demo
status: ready
archetype: feature
tier: green
complexity: low
owner: null
---

# Goal
feat(demo): the one block of the cut

Design (approved in the grill):

### `src/demo.ts`

Add the thing.

## Acceptance

`npm test` is green.
EOF
out=$(sh "$bin/session-monitor.sh" --task T-006 --state "$state" --dry-run 2>/dev/null)
check 'the wave of the cut goes out'  '^T-006-01 printed '
nocheck 'the parent itself does not'  '^T-006 '

block() { # <id> <status> <owner> <phase or -> <path>
  mkdir -p "$root/demo/$1"
  {
    printf -- '---\nid: %s\nrepo: demo\nstatus: %s\narchetype: feature\ntier: yellow\ncomplexity: medium\nowner: %s\n' \
      "$1" "$2" "$3"
    [ "$4" = - ] || printf 'phase: %s\n' "$4"
    printf -- '---\n\n# Goal\nfeat(demo): block %s\n\nDesign (approved in the grill):\n\n### `%s`\n\nAdd it.\n\n## Acceptance\n\n`npm test` is green.\n' \
      "$1" "$5"
  } > "$state/repos/demo/tasks/$1.md"
}
parent() { # <id>
  printf -- '---\nid: %s\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: yellow\ncomplexity: medium\n---\n\n# Goal\nfeat(demo): a parent\n' \
    "$1" > "$state/repos/demo/tasks/$1.md"
}

# the implement phase of the last wave: every unmerged block is tests_ready with phase: implement armed
parent T-007
block T-007-01 done null - src/a.ts
block T-007-02 tests_ready null implement src/b.ts
block T-007-03 tests_ready null implement src/c.ts
out=$(sh "$bin/session-monitor.sh" --task T-007 --state "$state" --dry-run 2>/dev/null)
check 'an armed implement block goes out'        '^T-007-02 printed '
check 'every armed implement block goes out'     '^T-007-03 printed '
check 'it goes out with the implement agent'     'You are implementer\.'
nocheck 'a done block does not'                  '^T-007-01 '

# a tests_ready block the monitor has not armed is still in the hands of its tests phase
parent T-008
block T-008-01 tests_ready null - src/d.ts
out=$(sh "$bin/session-monitor.sh" --task T-008 --state "$state" --dry-run 2>/dev/null)
nocheck 'an unarmed tests_ready block is not dispatched' '^T-008-01 printed'

# a block whose session still runs is skipped, next to an armed one in the same wave
parent T-009
block T-009-01 tests_ready null implement src/e.ts
block T-009-02 in_progress factory@host:abc - src/f.ts
out=$(sh "$bin/session-monitor.sh" --task T-009 --state "$state" --dry-run 2>/dev/null)
check 'the armed block of the wave goes out'     '^T-009-01 printed '
check 'the block in its session is skipped'      '^T-009-02 skipped '
nocheck 'the block in its session gets no prompt' 'First take ownership of T-009-02'

# a block in `review` with its MR open: the batch mode watches its parent for the merge
cat > "$state/repos/demo/tasks/T-004-01.md" <<'EOF'
---
id: T-004-01
repo: demo
status: review
archetype: feature
tier: green
complexity: low
mr_url: https://forge.test/mr/1
---

# Goal
feat(demo): a block whose MR is open
EOF

out=$(sh "$bin/session-monitor.sh" --all --state "$state" --dry-run 2>/dev/null)
check 'the open block MR is watched' "mr-watch.sh T-004 --once --state $state"

# --step: one session for a parent-level step, in the registered clone when there is no session worktree yet
mkdir -p "$tmp/clone"
printf 'demo: { path: %s }\n' "$tmp/clone" > "$state/repos.yml"
task T-005 null feature
out=$(sh "$bin/session-monitor.sh" --task T-005 --step grill --state "$state" 2>/dev/null)
check 'the grill step runs in the clone' "^T-005-grill printed $tmp/clone\$"
check 'the grill step prompts the skill' '"/claude-factory:grill '

out=$(sh "$bin/session-monitor.sh" --parent T-005 --step grill --state "$state" 2>/dev/null)
check '--parent is still the same flag' "^T-005-grill printed $tmp/clone\$"

if sh "$bin/session-monitor.sh" --task T-005 --step nonsense --state "$state" >/dev/null 2>&1; then
  printf 'FAIL an unknown step was accepted\n'; fail=1
else
  printf 'PASS an unknown step is refused\n'
fi

# the claim at spawn: a real dispatch (no --dry-run) writes in_progress and the placeholder owner through
# state-report.sh, which needs the state clone to be a git clone with a root to push to
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
git -C "$state" add -A
git -C "$state" commit -q -m 'the fixture state'
git init -q --bare "$tmp/state-root"
git -C "$state" remote add origin "$tmp/state-root"
git -C "$state" push -q -u origin main

out=$(sh "$bin/session-monitor.sh" --task T-001 --spawn manual --state "$state" 2>&1)
check 'the claimed unit is still dispatched' '^T-001 printed '
claimed="$state/repos/demo/tasks/T-001.md"
out=$(cat "$claimed")
check 'the dispatch claims in_progress'  '^status: in_progress$'
check 'the dispatch claims a pending owner' "^owner: factory@.*:pending-T-001\$"

# the session name `<emoji> <repo> <id>` on the tab and in `claude --name`, and the tab record of each spawn,
# over a second state repo: `demo` carries an `emoji:`, `plain` does not
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
hroot="$tmp/h"
hstate="$hroot/state"
mkdir -p "$hstate/repos/demo/tasks" "$hstate/repos/plain/tasks" \
  "$hroot/demo/T-101" "$hroot/plain/T-102" "$hroot/demo/T-103-01"
printf 'spawn: manual\n' > "$hstate/factory.yml"
printf 'demo: { path: %s, emoji: 🦊 }\nplain: { path: %s }\n' "$tmp/clone" "$tmp/clone" > "$hstate/repos.yml"
leaf() { # <id> <repo>
  printf -- '---\nid: %s\nrepo: %s\nstatus: ready\narchetype: feature\ntier: green\ncomplexity: low\nowner: null\n---\n\n# Goal\nfeat(%s): a leaf\n' \
    "$1" "$2" "$2" > "$hstate/repos/$2/tasks/$1.md"
}
leaf T-101 demo
leaf T-102 plain
printf -- '---\nid: T-103\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\n---\n\n# Goal\nfeat(demo): a parent\n' \
  > "$hstate/repos/demo/tasks/T-103.md"
printf -- '---\nid: T-103-01\nrepo: demo\nstatus: ready\narchetype: feature\ntier: green\ncomplexity: low\nowner: null\n---\n\n# Goal\nfeat(demo): a block\n\nDesign (approved in the grill):\n\n### `src/g.ts`\n\nAdd it.\n\n## Acceptance\n\n`npm test` is green.\n' \
  > "$hstate/repos/demo/tasks/T-103-01.md"

out=$(sh "$bin/session-monitor.sh" --task T-101 --spawn herdr --state "$hstate" 2>/dev/null)
check 'a herdr spawn of a leaf goes out'        '^T-101 spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'the tab carries the session name'        '^tab create .*--label "🦊 demo T-101"'
check 'claude carries the session name'         '^agent start implementer_t-101 .* -- .*--name "🦊 demo T-101"'
out=$(cat "$hroot/demo/.harness/T-101/herdr-tabs" 2>/dev/null)
check 'the leaf spawn is in the tab record'     '^T-101 tab-1 pane-1$'

: > "$HERDR_STUB_LOG"
out=$(FACTORY_CLAUDE_ARGS='--plugin-dir /sim/plugin --settings /sim/settings.json' \
  sh "$bin/session-monitor.sh" --task T-102 --spawn herdr --state "$hstate" 2>/dev/null)
out=$(cat "$HERDR_STUB_LOG")
check 'FACTORY_CLAUDE_ARGS rides along on agent start' \
  '^agent start implementer_t-102 .* -- .*--name "[^"]*" --plugin-dir /sim/plugin --settings /sim/settings.json $'
out=$(FACTORY_CLAUDE_ARGS='--plugin-dir /sim/plugin' sh "$bin/session-monitor.sh" --task T-102 --dry-run --state "$hstate" 2>/dev/null)
check 'and on a printed line'                   'claude --model [^ ]* --name "[^"]*" --plugin-dir /sim/plugin "'

out=$(sh "$bin/session-monitor.sh" --task T-103 --spawn herdr --state "$hstate" 2>/dev/null)
check 'a herdr spawn of a block goes out'       '^T-103-01 spawned '
out=$(cat "$hroot/demo/.harness/T-103/herdr-tabs" 2>/dev/null)
check 'a block lands in its parent tab record'  '^T-103-01 tab-1 pane-1$'

out=$(sh "$bin/session-monitor.sh" --task T-101 --step grill --spawn herdr --state "$hstate" 2>/dev/null)
check 'a herdr spawn of a step goes out'        '^T-101-grill spawned '
out=$(cat "$hroot/demo/.harness/T-101/herdr-tabs" 2>/dev/null)
check 'a step lands in its task tab record'     '^T-101-grill tab-1 pane-1$'

: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --all --spawn herdr --state "$hstate" 2>/dev/null)
check '--all spawns the unit of the other repo' '^T-102 spawned '
out=$(cat "$HERDR_STUB_LOG")
check '--all names the tab by its repo'         '^tab create .*--label "[^ ]* plain T-102"'
check '--all names the claude session too'      '^agent start implementer_t-102 .* -- .*--name "[^ ]* plain T-102"'
out=$(cat "$hroot/plain/.harness/T-102/herdr-tabs" 2>/dev/null)
check '--all records its tab'                   '^T-102 tab-1 pane-1$'

out=$(sh "$bin/session-monitor.sh" --task T-101 --spawn manual --state "$hstate" 2>/dev/null)
check 'the manual line carries the session name' 'claude --model [^ ]* --name "🦊 demo T-101" "First take ownership of T-101'

out=$(sh "$bin/herdr-tabs.sh" name T-101 --state "$hstate" 2>/dev/null)
check 'an emoji: in repos.yml wins'             '^🦊 demo T-101$'
first=$(sh "$bin/herdr-tabs.sh" name T-102 --state "$hstate" 2>/dev/null)
second=$(sh "$bin/herdr-tabs.sh" name T-102 --state "$hstate" 2>/dev/null)
out=$first
check 'a repo with no emoji: still gets one'    '^[^ ][^ ]* plain T-102$'
if [ -n "$first" ] && [ "$first" = "$second" ]; then printf 'PASS two runs pick the same emoji\n'
else printf 'FAIL two runs picked %s and %s\n' "$first" "$second"; fail=1; fi

if sh "$bin/herdr-tabs.sh" name T-999 --state "$hstate" >/dev/null 2>&1; then
  printf 'FAIL an unresolvable unit was named\n'; fail=1
else
  printf 'PASS an unresolvable unit exits 1\n'
fi

# the close before start: a unit's recorded tab is closed before the unit starts again, and a tab still at
# work keeps the unit from starting
HERDR_TAB_ID=tab-self
export HERDR_TAB_ID
rec() { # <T-NNN> <unit> <tab_id>
  mkdir -p "$hroot/demo/.harness/$1"
  printf '%s %s pane-%s\n' "$2" "$3" "${3#tab-}" >> "$hroot/demo/.harness/$1/herdr-tabs"
}
armed() { # <parent> <block>
  mkdir -p "$hroot/demo/$2"
  printf -- '---\nid: %s\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: yellow\ncomplexity: medium\n---\n\n# Goal\nfeat(demo): a parent\n' \
    "$1" > "$hstate/repos/demo/tasks/$1.md"
  printf -- '---\nid: %s\nrepo: demo\nstatus: tests_ready\nphase: implement\narchetype: feature\ntier: yellow\ncomplexity: medium\nowner: null\n---\n\n# Goal\nfeat(demo): a block\n\nDesign (approved in the grill):\n\n### `src/h.ts`\n\nAdd it.\n\n## Acceptance\n\n`npm test` is green.\n' \
    "$2" > "$hstate/repos/demo/tasks/$2.md"
}

armed T-104 T-104-01
rec T-104 T-104-01 tab-104
herdr_tab tab-104 idle false t-104-01
: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --task T-104 --spawn herdr --state "$hstate" 2>/dev/null)
check 'an armed block with an idle tab goes out' '^T-104-01 spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'its recorded tab is closed'               '^tab close tab-104 '
if awk '/^tab close tab-104 / && !c { c = NR } /^agent start implementer_t-104-01 / && !a { a = NR } END { exit !(c && a && c < a) }' "$HERDR_STUB_LOG"
then printf 'PASS the close comes before the agent start\n'
else printf 'FAIL the close does not come before the agent start\n'; fail=1; fi

armed T-105 T-105-01
rec T-105 T-105-01 tab-105
herdr_tab tab-105 working false t-105-01
: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --task T-105 --spawn herdr --state "$hstate" 2>/dev/null)
check 'an armed block with a working tab is skipped' '^T-105-01 skipped '
out=$(cat "$HERDR_STUB_LOG")
nocheck 'the working tab is not closed'          '^tab close tab-105 '
nocheck 'the skipped block starts no agent'      '^agent start implementer_t-105-01 '

leaf T-106 demo
rec T-106 T-106-triage tab-106
herdr_tab tab-106 idle false t-106-triage
: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --task T-106 --step grill --spawn herdr --state "$hstate" 2>/dev/null)
check 'the grill step goes out'                  '^T-106-grill spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'the grill step closes the triage tab'     '^tab close tab-106 '
out=$(cat "$hroot/demo/.harness/T-106/herdr-tabs")
check 'the triage close is in the tab record'    '^T-106-triage tab-106 closed$'

# --all closes the recorded tabs of units that are over before it dispatches anything
leaf T-108 demo
sed -i 's/^status: ready$/status: done/' "$hstate/repos/demo/tasks/T-108.md"
rec T-108 T-108 tab-108
herdr_tab tab-108 idle false t-108
leaf T-109 demo
sed -i 's/^status: ready$/status: review/' "$hstate/repos/demo/tasks/T-109.md"
rec T-109 T-109 tab-109
herdr_tab tab-109 idle false t-109
: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --all --spawn herdr --state "$hstate" 2>/dev/null)
nocheck '--all prints no closed line on stdout'  ' closed tab-'
out=$(cat "$HERDR_STUB_LOG")
check '--all closes the tab of a leaf at done'   '^tab close tab-108 '
nocheck '--all keeps the tab of a leaf at review' '^tab close tab-109 '

# a tab create reply with no tab id: the agent still starts, nothing is recorded, and the batch goes on
armed T-111 T-111-01
mkdir -p "$hroot/demo/T-111-02"
sed 's/T-111-01/T-111-02/; s/h\.ts/i.ts/' "$hstate/repos/demo/tasks/T-111-01.md" > "$hstate/repos/demo/tasks/T-111-02.md"
HERDR_STUB_CREATE='{"result":{"root_pane":{"pane_id":"pane-1"}}}'
export HERDR_STUB_CREATE
: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --task T-111 --spawn herdr --state "$hstate" 2>"$tmp/t111.err"); cat "$tmp/t111.err" >&2
unset HERDR_STUB_CREATE
check 'a tab with no id still spawns the unit'   '^T-111-01 spawned '
check 'the next unit of the batch is spawned'    '^T-111-02 spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'the first unit starts its agent'          '^agent start implementer_t-111-01 '
check 'the next unit starts its agent'           '^agent start implementer_t-111-02 '
out=$(cat "$hroot/demo/.harness/T-111/herdr-tabs" 2>/dev/null)
nocheck 'a tab with no id writes no record line' '^T-111-0'

# the verbs herd-watch and session-monitor share
out=$(sh "$bin/herdr-tabs.sh" state T-108-grill --state "$hstate" 2>/dev/null)
check 'a unit with no record is none'            '^none$'
out=$(sh "$bin/herdr-tabs.sh" state T-109 --state "$hstate" 2>/dev/null)
check 'a recorded open tab is open'              '^open$'
out=$(sh "$bin/herdr-tabs.sh" state T-108 --state "$hstate" 2>/dev/null)
check 'a closed tab is closed'                   '^closed$'
out=$(sh "$bin/herdr-tabs.sh" close T-109 --state "$hstate" 2>/dev/null)
check 'close prints the closed tab'              '^T-109 closed tab-109$'
rec T-109 T-109-grill tab-110
herdr_tab tab-110 blocked false t-109-grill
out=$(sh "$bin/herdr-tabs.sh" close T-109-grill --state "$hstate" 2>/dev/null)
check 'close prints a kept tab with its reason'  '^T-109-grill kept tab-110 [^ ]'

# task ids past T-999: a four-digit parent owns the tab record of its blocks and steps
printf -- '---\nid: T-1000\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\n---\n\n# Goal\nfeat(demo): a parent\n' \
  > "$hstate/repos/demo/tasks/T-1000.md"
for b in T-1000-01 T-1000-02; do
  printf -- '---\nid: %s\nrepo: demo\nstatus: done\narchetype: feature\ntier: green\ncomplexity: low\n---\n\n# Goal\nfeat(demo): a block\n' \
    "$b" > "$hstate/repos/demo/tasks/$b.md"
done
out=$(sh "$bin/herdr-tabs.sh" name T-1000-01 --state "$hstate" 2>/dev/null)
check 'a four-digit block is named'              '^🦊 demo T-1000-01$'
sh "$bin/herdr-tabs.sh" record T-1000-01 tab-1001 pane-1001 --state "$hstate" 2>/dev/null
sh "$bin/herdr-tabs.sh" record T-1000-grill tab-1002 pane-1002 --state "$hstate" 2>/dev/null
out=$(cat "$hroot/demo/.harness/T-1000/herdr-tabs" 2>/dev/null)
check 'a four-digit block is recorded under its parent' '^T-1000-01 tab-1001 pane-1001$'
check 'a four-digit step is recorded under its parent'  '^T-1000-grill tab-1002 pane-1002$'
out=$(sh "$bin/herdr-tabs.sh" state T-1000-01 --state "$hstate" 2>/dev/null)
check 'a four-digit block reads its record'      '^open$'
out=$(sh "$bin/herdr-tabs.sh" state T-1000-grill --state "$hstate" 2>/dev/null)
check 'a four-digit step reads its record'       '^open$'
herdr_tab tab-1001 idle false t-1000-01
herdr_tab tab-1002 idle false t-1000-grill
: > "$HERDR_STUB_LOG"
sh "$bin/herdr-tabs.sh" sweep T-1000 --state "$hstate" >/dev/null 2>&1
out=$(cat "$HERDR_STUB_LOG")
check 'sweep of a four-digit parent closes a done block' '^tab close tab-1001 '
nocheck 'sweep keeps the step of a parent in progress'   '^tab close tab-1002 '
rec T-1000 T-1000-02 tab-1003
herdr_tab tab-1003 idle false t-1000-02
: > "$HERDR_STUB_LOG"
sh "$bin/session-monitor.sh" --all --spawn herdr --state "$hstate" >/dev/null 2>&1
out=$(cat "$HERDR_STUB_LOG")
check '--all sweeps a record under a four-digit parent'  '^tab close tab-1003 '

# the stub answers the verbs the monitor, herd-watch and capacity.sh drive with the herdr 0.8.2 shapes, over a
# fresh stub; `js <expression>` prints one expression over the JSON on stdin, `o` being the parsed reply
js() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);process.stdout.write(String(eval(process.argv[1])))})' "$1"; }
herdr_stub "$tmp/stub2"
herdr_agent lead_ecs-12 working w1:p2 sess-a
herdr_agent - idle w1:p3 sess-b
herdr_tab tab-9 done false t-009
out=$(herdr agent list | js 'o.result.type+" "+o.result.agents.map(a=>[a.name||"-",a.pane_id,a.agent_status,a.agent_session?a.agent_session.value:"-"].join(",")).sort().join(" ")')
check 'agent list names every live agent with pane, status and session' \
  '^agent_list -,w1:p3,idle,sess-b lead_ecs-12,w1:p2,working,sess-a t-009,pane-9,done,-$'
out=$(herdr agent get lead_ecs-12 | js 'o.result.type+" "+o.result.agent.pane_id+" "+o.result.agent.agent_session.value')
check 'agent get takes a name'                   '^agent_info w1:p2 sess-a$'
out=$(herdr agent get w1:p3 | js 'o.result.agent.agent_status+" "+("name" in o.result.agent)')
check 'agent get takes a pane id, an unnamed agent has no name' '^idle false$'
out=$(herdr agent get nosuch 2>&1 >/dev/null | js 'o.error.code'; herdr agent get nosuch >/dev/null 2>&1; echo " $?")
check 'an absent agent is agent_not_found, exit 1' '^agent_not_found 1$'
out=$(herdr agent wait w1:p3 --until idle --until done --timeout 1000 | js 'o.result.agent.agent_status')
check 'agent wait answers an agent already in the state' '^idle$'
out=$(herdr agent wait lead_ecs-12 --until idle --timeout 1000 2>&1 >/dev/null | js 'o.error.code'; herdr agent wait lead_ecs-12 --timeout 1 >/dev/null 2>&1; echo " $?")
check 'agent wait of a working agent times out'  '^timeout 1$'
herdr agent rename w1:p3 architecture-auditor_ecs-142-03 >/dev/null
out=$(herdr agent get architecture-auditor_ecs-142-03 | js 'o.result.agent.pane_id')
check 'agent rename names the agent of a pane'   '^w1:p3$'
out=$(HERDR_STUB_READ='Do you trust the files in this folder?' herdr agent read lead_ecs-12 --source recent --lines 40)
check 'agent read prints HERDR_STUB_READ as text' '^Do you trust the files in this folder?$'
out=$(herdr agent send-keys lead_ecs-12 1 enter | js 'o.result.type')
check 'agent send-keys answers ok'               '^ok$'
out=$(cat "$HERDR_STUB_LOG")
check 'the keys are in the log'                  '^agent send-keys lead_ecs-12 1 enter $'
out=$(herdr workspace create --cwd "$tmp" --label 'T-ECS-12 ecs' --env FACTORY_ROLE=repo-lead --no-focus \
  | js 'o.result.type+" "+o.result.workspace.workspace_id+" "+o.result.tab.tab_id+" "+o.result.root_pane.pane_id')
check 'workspace create answers workspace, tab and root pane' '^workspace_created ws-1 tab-1 pane-1$'
out=$(cat "$HERDR_STUB_DIR/env/pane-1")
check 'workspace create keeps its --env for the pane' '^FACTORY_ROLE=repo-lead$'
out=$(herdr tab create --workspace ws-1 --label 'x y' --env FACTORY_ROLE=implementer --env FACTORY_UNIT=T-ECS-12-03 --no-focus \
  | js 'o.result.type+" "+o.result.tab.tab_id+" "+o.result.tab.workspace_id+" "+o.result.root_pane.pane_id')
check 'tab create answers tab and root pane'     '^tab_created tab-1 ws-1 pane-1$'
out=$(cat "$HERDR_STUB_DIR/env/pane-1")
check 'tab create honours every --env'           '^FACTORY_UNIT=T-ECS-12-03$'
nocheck 'a new pane forgets the env of the last one' 'FACTORY_ROLE=repo-lead'
out=$(herdr tab get tab-9 | js 'o.result.tab.agent_status+" "+o.result.tab.workspace_id')
check 'tab get answers the live tab'             '^done ws-1$'
herdr tab close tab-9 >/dev/null
out=$(herdr agent get t-009 2>&1 >/dev/null | js 'o.error.code')
check 'tab close ends the agent in that tab'     '^agent_not_found$'
out=$(herdr notification show 'T-ECS-12-grill waits' --body 'Which store?' --sound request | js 'o.result.type+" "+o.result.shown+" "+o.result.reason')
check 'notification show is shown by default'    '^notification_show true shown$'
out=$(HERDR_STUB_NOTIFY=disabled herdr notification show x | js 'o.result.shown+" "+o.result.reason')
check 'HERDR_STUB_NOTIFY sets the reason'        '^false disabled$'
out=$(herdr pane process-info --pane w1:p2 | js 'o.result.type+" "+o.result.process_info.foreground_processes.map(p=>p.name).join(",")')
check 'process-info of an agent pane shows claude' '^pane_process_info claude$'
herdr_procs w1:p9 "sh $tmp/bin/ui-relay.sh --port 7171"
out=$(herdr pane process-info --pane w1:p9 | js 'o.result.process_info.foreground_processes[0].argv.join(" ")')
check 'herdr_procs sets the foreground argv'     "^sh $tmp/bin/ui-relay.sh --port 7171\$"
herdr_procs w1:p8
out=$(herdr pane process-info --pane w1:p8 | js 'o.result.process_info.foreground_processes.length')
check 'herdr_procs with no command is a bare shell' '^0$'
out=$(herdr pane process-info --pane w9:p9 2>&1 >/dev/null | js 'o.error.code')
check 'process-info of an unknown pane is pane_not_found' '^pane_not_found$'
out=$(HERDR_STUB_START=agent_not_ready herdr agent start x --kind claude --pane w1:p2 2>&1 >/dev/null | js 'o.error.code')
check 'HERDR_STUB_START fails agent start with its code' '^agent_not_ready$'

# alias ids, T-<ALIAS>-<n>: the wave of an alias cut goes out through spawn-plan.sh, herdr-tabs.sh names, records
# and reads its units under the parent, and --all sweeps that record. The grammar is lib-tasks.sh's predicates,
# so this part runs once they take alias ids and is skipped before.
if (. "$bin/lib-tasks.sh"; is_parent_id T-DM-7 && is_block_of T-DM-7 T-DM-7-01) >/dev/null 2>&1; then
  parent T-DM-7
  block T-DM-7-01 ready null - src/j.ts
  out=$(sh "$bin/session-monitor.sh" --task T-DM-7 --state "$state" --dry-run 2>/dev/null)
  check 'the wave of an alias cut goes out'        '^T-DM-7-01 printed '
  nocheck 'the alias parent itself does not'       '^T-DM-7 '

  printf -- '---\nid: T-DM-7\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\n---\n\n# Goal\nfeat(demo): an alias parent\n' \
    > "$hstate/repos/demo/tasks/T-DM-7.md"
  printf -- '---\nid: T-DM-7-01\nrepo: demo\nstatus: ready\narchetype: feature\ntier: green\ncomplexity: low\nowner: null\n---\n\n# Goal\nfeat(demo): an alias block\n\nDesign (approved in the grill):\n\n### `src/j.ts`\n\nAdd it.\n\n## Acceptance\n\n`npm test` is green.\n' \
    > "$hstate/repos/demo/tasks/T-DM-7-01.md"
  mkdir -p "$hroot/demo/T-DM-7-01"
  : > "$HERDR_STUB_LOG"
  out=$(sh "$bin/session-monitor.sh" --task T-DM-7 --spawn herdr --state "$hstate" 2>/dev/null)
  check 'a herdr spawn of an alias block goes out' '^T-DM-7-01 spawned '
  out=$(cat "$HERDR_STUB_LOG")
  check 'its agent is role_ plus the id less t-'  '^agent start implementer_dm-7-01 '
  out=$(cat "$hroot/demo/.harness/T-DM-7/herdr-tabs" 2>/dev/null)
  check 'an alias block lands in its parent tab record' '^T-DM-7-01 tab-1 pane-1$'
  out=$(sh "$bin/herdr-tabs.sh" name T-DM-7-01 --state "$hstate" 2>/dev/null)
  check 'an alias block is named'                  '^🦊 demo T-DM-7-01$'
  sh "$bin/herdr-tabs.sh" record T-DM-7-01 tab-701 pane-701 --state "$hstate" 2>/dev/null
  sh "$bin/herdr-tabs.sh" record T-DM-7-grill tab-702 pane-702 --state "$hstate" 2>/dev/null
  out=$(sh "$bin/herdr-tabs.sh" state T-DM-7-grill --state "$hstate" 2>/dev/null)
  check 'an alias step reads its record'           '^open$'
  sed -i 's/^status: .*/status: done/' "$hstate/repos/demo/tasks/T-DM-7-01.md"
  herdr_tab tab-701 idle false t-dm-7-01
  herdr_tab tab-702 idle false t-dm-7-grill
  : > "$HERDR_STUB_LOG"
  sh "$bin/session-monitor.sh" --all --spawn herdr --state "$hstate" >/dev/null 2>&1
  out=$(cat "$HERDR_STUB_LOG")
  check '--all sweeps the done block of an alias parent'   '^tab close tab-701 '
  nocheck '--all keeps the step of an alias parent at work' '^tab close tab-702 '
else
  printf 'SKIP alias ids: the lib-tasks.sh predicates take T-NNN ids only\n'
fi

# the agent org (plan 3.1, 3.3, 3.6 to 3.8), over a fresh stub and a state with an alias repo and a capacity:
# block: every herdr spawn passes the three --env pairs and names its agent <role>_<id less t->, every dispatch
# leases `sessions <unit>` (plus repo-lead for a lead and the agent role for a block), a lead gets its own
# workspace in the parent worktree and claims nothing, and every pass ends with state-push.sh
herdr_stub "$tmp/stub3"
unset HERDR_TAB_ID
oroot="$tmp/o"
ostate="$oroot/state"
mkdir -p "$ostate/repos/ecs-core/tasks" "$oroot/ecs-core/T-ECS-12/.git" "$oroot/ecs-core/T-ECS-20-01" \
  "$oroot/ecs-core/T-ECS-30" "$tmp/eclone"
ocaps() { # <sessions> <repo-lead>
  printf 'spawn: herdr\ncapacity:\n  sessions: %s\n  roles: {repo-lead: %s, implementer: 4}\n' "$1" "$2" > "$ostate/factory.yml"
}
ocaps 10 3
printf 'ecs-core: { path: %s, alias: ECS, emoji: 🐳 }\n' "$tmp/eclone" > "$ostate/repos.yml"
otask() { # <state> <id> <status> [<frontmatter line>...]
  ot_f="$1/repos/ecs-core/tasks/$2.md" ot_id=$2 ot_st=$3
  shift 3
  { printf -- '---\nid: %s\nrepo: ecs-core\nstatus: %s\narchetype: feature\ntier: green\ncomplexity: low\nowner: null\n' "$ot_id" "$ot_st"
    for l; do printf '%s\n' "$l"; done
    printf -- '---\n\n# Goal\nfeat(ecs): %s\n\nDesign (approved in the grill):\n\n### `src/%s.ts`\n\nAdd it.\n\n## Acceptance\n\n`npm test` is green.\n' \
      "$ot_id" "$ot_id"
  } > "$ot_f"
}
otask "$ostate" T-ECS-12 ready 'request: R-20260925-1' 'priority: P2'
otask "$ostate" T-ECS-13 ready 'request: R-20260925-1'
otask "$ostate" T-ECS-14 ready 'request: R-20260925-1'
otask "$ostate" T-ECS-20 in_progress
otask "$ostate" T-ECS-20-01 ready
otask "$ostate" T-ECS-30 ready
otask "$ostate" T-ECS-50 ready 'request: R-20260925-1'
git init -q -b main "$ostate"
git -C "$ostate" config user.email harness@localhost
git -C "$ostate" config user.name harness
git -C "$ostate" add -A
git -C "$ostate" commit -q -m 'the org fixture state'
git init -q --bare "$tmp/o-root"
git -C "$ostate" remote add origin "$tmp/o-root"
git -C "$ostate" push -q -u origin main
sm() { sh "$bin/session-monitor.sh" "$@" --state "$ostate"; }
envof() { cat "$HERDR_STUB_DIR/env/pane-1" 2>/dev/null; }
exists() { # <what> <path>
  if [ -e "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
absent() { # <what> <path>
  if [ -e "$2" ]; then printf 'FAIL %s\n' "$1"; fail=1; else printf 'PASS %s\n' "$1"; fi
}
before() { # <what> <first pattern> <second pattern>: both in the stub log, the first one earlier
  if awk -v a="$2" -v b="$3" '$0 ~ a && !x { x = NR } $0 ~ b && !y { y = NR } END { exit !(x && y && x < y) }' "$HERDR_STUB_LOG"
  then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
lease="$ostate/.capacity"

# --step chart: a step tab with the env, the name and the wayfinder prompt, leased and not claimed
: > "$HERDR_STUB_LOG"
out=$(sm --task T-ECS-12 --step chart 2>/dev/null)
check 'the chart step goes out'                     "^T-ECS-12-chart spawned $oroot/ecs-core/T-ECS-12\$"
out=$(envof)
check 'a spawn passes FACTORY_ROLE'                 '^FACTORY_ROLE=chart$'
check 'a spawn passes FACTORY_UNIT'                 '^FACTORY_UNIT=T-ECS-12-chart$'
check 'a step passes its task'                      '^FACTORY_TASK=T-ECS-12$'
check 'a step passes its solve step line'           '^FACTORY_STEP=Step 3b of 16: chart R-20260925-1$'
check 'a spawn turns the auto memory off'           '^CLAUDE_CODE_DISABLE_AUTO_MEMORY=1$'
out=$(cat "$HERDR_STUB_LOG")
check 'a step agent is <step>_<id less t->'         '^agent start chart_ecs-12 --kind claude '
check 'agent start waits up to 120 s'               '^agent start chart_ecs-12 .*--timeout 120000 '
check 'the chart prompt charts the request map'     '^agent prompt chart_ecs-12 "/claude-factory:wayfinder chart R-20260925-1 T-ECS-12" --wait --until working --until blocked --until done --timeout 60000 $'
exists 'a step leases a sessions slot'              "$lease/sessions/T-ECS-12-chart"
out=$(cat "$ostate/repos/ecs-core/tasks/T-ECS-12.md")
check 'a chart step claims nothing'                 '^status: ready$'
if sm --task T-ECS-20 --step chart --dry-run >/dev/null 2>&1; then
  printf 'FAIL a chart of a task with no request: was accepted\n'; fail=1
else
  printf 'PASS a chart of a task with no request: is refused\n'
fi

# --step lead: its own workspace in the parent worktree, the lead name and role, two leases, no claim
: > "$HERDR_STUB_LOG"
out=$(sm --task T-ECS-12 --step lead 2>/dev/null)
check 'a lead goes out in the parent worktree'      "^T-ECS-12-lead spawned $oroot/ecs-core/T-ECS-12\$"
out=$(cat "$HERDR_STUB_LOG")
check 'a lead gets its own workspace'               "^workspace create --cwd $oroot/ecs-core/T-ECS-12 --label \"T-ECS-12 ecs-core\" .*--no-focus"
nocheck 'a lead opens no tab'                       '^tab create '
check 'the lead starts in the root pane'            '^agent start lead_ecs-12 --kind claude --pane pane-1 '
check 'the lead prompt herds its task'              '^agent prompt lead_ecs-12 "/claude-factory:factory herd T-ECS-12" --wait --until working --until blocked --until done --timeout 60000 $'
out=$(envof)
check 'the lead role is repo-lead'                  '^FACTORY_ROLE=repo-lead$'
check 'the lead unit is <T-id>-lead'                '^FACTORY_UNIT=T-ECS-12-lead$'
nocheck 'a lead is no solve step'                   '^FACTORY_STEP='
exists 'a lead leases a sessions slot'              "$lease/sessions/T-ECS-12-lead"
exists 'a lead leases a repo-lead slot'             "$lease/repo-lead/T-ECS-12"
out=$(cat "$ostate/repos/ecs-core/tasks/T-ECS-12.md")
check 'a lead leaves the status alone'              '^status: ready$'
check 'a lead claims no owner'                      '^owner: null$'
out=$(cat "$oroot/ecs-core/.harness/T-ECS-12/herdr-tabs" 2>/dev/null)
check 'the lead tab is in the tab record'           '^T-ECS-12-lead tab-1 pane-1$'

# the lead prompt reads the repo-lead playbook first, only when there is one; a manual line carries the env
out=$(sm --task T-ECS-12 --step lead --dry-run 2>/dev/null)
check 'with no playbook the lead prompt is the herd' ' "/claude-factory:factory herd T-ECS-12"$'
check 'a manual line prints the env as a prefix' \
  "cd $oroot/ecs-core/T-ECS-12 && FACTORY_ROLE=repo-lead FACTORY_UNIT=T-ECS-12-lead CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude --model "
mkdir -p "$ostate/repos/ecs-core/agents/repo-lead"
printf '# repo-lead\n' > "$ostate/repos/ecs-core/agents/repo-lead/playbook.md"
out=$(sm --task T-ECS-12 --step lead --dry-run 2>/dev/null)
check 'with a playbook the lead reads it first' \
  "\"Read $ostate/repos/ecs-core/agents/repo-lead/playbook.md first. /claude-factory:factory herd T-ECS-12\"\$"
sm --task T-ECS-14 --step chart --dry-run >/dev/null 2>&1
absent 'a dry run leases nothing'                   "$lease/sessions/T-ECS-14-chart"
out=$(sm --task T-ECS-14 --step triage --dry-run 2>/dev/null)
check 'the triage prompt asks for ## Related issues as its own section' 'write ## Related issues as its own section after ## Context'
check 'the triage prompt names the report path in the state clone' "file the investigation report at $ostate/repos/ecs-core/research/T-ECS-14-investigation.md, "

# agent_not_ready: the start dialog is waited out, then the prompt goes in; a wait that times out prompts nothing
herdr_agent chart_ecs-13 idle pane-13
: > "$HERDR_STUB_LOG"
out=$(HERDR_STUB_START=agent_not_ready sm --task T-ECS-13 --step chart 2>/dev/null)
check 'a start at a dialog still goes out'          '^T-ECS-13-chart spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'agent_not_ready waits for idle or done'      '^agent wait chart_ecs-13 --until idle --until done --timeout 120000 '
before 'the prompt comes after the wait'            '^agent wait chart_ecs-13 ' '^agent prompt chart_ecs-13 '
herdr_agent chart_ecs-14 working pane-14
: > "$HERDR_STUB_LOG"
out=$(HERDR_STUB_START=agent_not_ready sm --task T-ECS-14 --step chart 2>/dev/null); rc=$?
if [ "$rc" -eq 2 ]; then printf 'PASS a wait that times out exits 2\n'; else printf 'FAIL a wait that timed out exited %s\n' "$rc"; fail=1; fi
out=$(cat "$HERDR_STUB_LOG")
nocheck 'a wait that times out prompts nothing'     '^agent prompt chart_ecs-14 '

# a prompt herdr saw no state change after (agent_prompt_stalled) is typed once more; a second stall exits 2
: > "$HERDR_STUB_LOG"
rm -f "$HERDR_STUB_DIR/stalls"
out=$(HERDR_STUB_STALLS=1 sm --task T-ECS-13 --step chart 2>/dev/null)
check 'a prompt that stalled once still goes out'   '^T-ECS-13-chart spawned '
out=$(grep -c '^agent prompt chart_ecs-13 ' "$HERDR_STUB_LOG")
check 'the stalled prompt is typed twice'           '^2$'
: > "$HERDR_STUB_LOG"
rm -f "$HERDR_STUB_DIR/stalls"
HERDR_STUB_STALLS=2 sm --task T-ECS-13 --step chart >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then printf 'PASS a prompt that stalls twice exits 2\n'; else printf 'FAIL a prompt that stalled twice exited %s\n' "$rc"; fail=1; fi
out=$(grep -c '^agent prompt chart_ecs-13 ' "$HERDR_STUB_LOG")
check 'it is not typed a third time'                '^2$'

# the sessions cap: a block with no slot is skipped and not claimed; a lead needs two free slots
rm -rf "$lease"
ocaps 2 3
sh "$bin/capacity.sh" acquire sessions T-X-1 --state "$ostate"
sh "$bin/capacity.sh" acquire sessions T-X-2 --state "$ostate"
: > "$HERDR_STUB_LOG"
out=$(sm --task T-ECS-20 2>&1)
check 'a block with no slot is skipped'             '^T-ECS-20-01 skipped '
check 'the skip says the sessions cap is full'      'capacity: sessions full'
out=$(cat "$HERDR_STUB_LOG")
nocheck 'a block with no slot starts no agent'      '^agent start '
out=$(cat "$ostate/repos/ecs-core/tasks/T-ECS-20-01.md")
check 'a block with no slot is not claimed'         '^status: ready$'
sh "$bin/capacity.sh" release T-X-2 --state "$ostate"
: > "$HERDR_STUB_LOG"
out=$(sm --task T-ECS-20 2>/dev/null)
check 'a block with a free slot goes out'           '^T-ECS-20-01 spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'a block agent is <role>_<id less t->'        '^agent start implementer_ecs-20-01 '
out=$(envof)
check 'a block passes its agent role'               '^FACTORY_ROLE=implementer$'
exists 'a block leases a sessions slot'             "$lease/sessions/T-ECS-20-01"
exists 'a block leases its agent role'              "$lease/implementer/T-ECS-20-01"
rm -rf "$lease"
ocaps 3 3
sh "$bin/capacity.sh" acquire sessions T-X-1 --state "$ostate"
sh "$bin/capacity.sh" acquire sessions T-X-2 --state "$ostate"
out=$(sm --task T-ECS-12 --step lead 2>&1)
check 'a lead with one free slot is skipped'        '^T-ECS-12-lead skipped '
check 'the lead skip names the sessions cap'        'capacity: sessions full'
# a finished step whose idle tab still holds a sessions lease: the close frees the slot before the room check
sh "$bin/capacity.sh" release T-X-2 --state "$ostate"
sh "$bin/capacity.sh" acquire sessions T-ECS-12-grill --state "$ostate"
printf 'T-ECS-12-grill tab-77 pane-77\n' >> "$oroot/ecs-core/.harness/T-ECS-12/herdr-tabs"
herdr_tab tab-77 idle false grill_ecs-12
out=$(sm --task T-ECS-12 --step lead 2>&1)
check 'a lead goes out once the finished step tab is closed' '^T-ECS-12-lead spawned '
absent 'the closed step tab gives its sessions lease back' "$lease/sessions/T-ECS-12-grill"
rm -rf "$lease"
ocaps 10 3

# a leaf reads its brief from .harness/<id>/brief.md; a dry run pushes and writes nothing, a pass pushes
git -C "$ostate" commit -q --allow-empty -m 'a local commit'
sm --task T-ECS-30 --dry-run >/dev/null 2>&1
absent 'a dry run writes no brief'                  "$oroot/ecs-core/.harness/T-ECS-30/brief.md"
out=$(git -C "$tmp/o-root" log --format=%s main)
nocheck 'a dry run pushes nothing'                  '^a local commit$'
out=$(sm --task T-ECS-30 --spawn manual 2>/dev/null)
check 'a leaf reads its brief'                      "\"First take ownership of T-ECS-30.* Read $oroot/ecs-core/.harness/T-ECS-30/brief.md "
check 'a leaf still runs its archetype skill'       '/claude-factory:block-feature '
check 'a leaf runs as its agent role'               'FACTORY_ROLE=implementer FACTORY_UNIT=T-ECS-30 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude '
if [ -s "$oroot/ecs-core/.harness/T-ECS-30/brief.md" ]; then printf 'PASS the leaf brief is written\n'
else printf 'FAIL the leaf brief is not written\n'; fail=1; fi
out=$(git -C "$tmp/o-root" log --format=%s main)
check 'the pass ends with state-push.sh'            '^claim: T-ECS-30 '
check 'the push carries the earlier commit too'     '^a local commit$'

# --step pass: the daily memory pass of one repo agent, in the state clone
: > "$HERDR_STUB_LOG"
out=$(sm --step pass --scope ecs-core/implementer 2>/dev/null)
check 'the daily pass goes out in the state clone'  "^pass-ecs-core-implementer spawned $ostate\$"
out=$(cat "$HERDR_STUB_LOG")
check 'the pass is pass_<alias>-<agent>'            '^agent start pass_ecs-implementer '
check 'the pass prompts the daily skill'            '^agent prompt pass_ecs-implementer "/claude-factory:memory-daily ecs-core/implementer" --wait --until working --until blocked --until done --timeout 60000 $'
out=$(envof)
check 'the pass unit is pass-<key>-<agent>'         '^FACTORY_UNIT=pass-ecs-core-implementer$'
exists 'a pass leases a sessions slot'              "$lease/sessions/pass-ecs-core-implementer"
: > "$HERDR_STUB_LOG"
sm --step pass --scope ecs-core/implementer-senior-architecture >/dev/null 2>&1
out=$(cat "$HERDR_STUB_LOG")
check 'a herdr name stops at 31 characters'         '^agent start pass_ecs-implementer-senior-arc '
for bad in '--step pass' '--scope ecs-core/implementer' '--task T-ECS-12 --step pass --scope ecs-core/implementer' \
  '--step pass --scope ecs-core'; do
  # shellcheck disable=SC2086
  if sm $bad --dry-run >/dev/null 2>&1; then printf 'FAIL %s was accepted\n' "$bad"; fail=1
  else printf 'PASS %s is refused\n' "$bad"; fi
done

# a lead with no parent worktree has worktree-add.sh make it first; one it cannot make is skipped
out=$(sm --task T-ECS-50 --step lead --dry-run 2>/dev/null)
check 'a lead with no worktree makes it first'      "worktree-add.sh T-ECS-50 "
out=$(sm --task T-ECS-50 --step lead --spawn manual 2>/dev/null)
check 'a lead whose worktree fails is skipped'      '^T-ECS-50-lead skipped '

# --queue: queue-next.sh lines from the top, each as --step lead, while two sessions and one repo-lead are free
qroot="$tmp/q"
qstate="$qroot/state"
mkdir -p "$qstate/repos/ecs-core/tasks" "$qroot/ecs-core/T-ECS-40/.git" "$qroot/ecs-core/T-ECS-41/.git" \
  "$qroot/ecs-core/T-ECS-42/.git"
printf 'ecs-core: { path: %s, alias: ECS }\n' "$tmp/eclone" > "$qstate/repos.yml"
printf 'spawn: herdr\ncapacity:\n  sessions: 5\n  roles: {repo-lead: 3}\n' > "$qstate/factory.yml"
otask "$qstate" T-ECS-40 ready 'request: R-20260925-2' 'priority: P2'
otask "$qstate" T-ECS-41 ready 'request: R-20260925-2' 'priority: P0'
otask "$qstate" T-ECS-42 ready 'request: R-20260925-2' 'priority: P1'
qbin=$bin
if [ ! -f "$bin/queue-next.sh" ]; then
  printf 'SKIP queue: bin/queue-next.sh is not there yet\n'
  # a throwaway copy of bin/ with a stand-in that prints the contract's lines, so the monitor's side still runs
  qbin="$tmp/qbin"
  cp -R "$bin" "$qbin"
  cat > "$qbin/queue-next.sh" <<'EOF'
#!/bin/sh
max=5
while [ $# -gt 0 ]; do case "$1" in --max) max=$2; shift 2 ;; *) shift ;; esac; done
printf 'T-ECS-41 ecs-core P0 R-20260925-2\nT-ECS-42 ecs-core P1 R-20260925-2\nT-ECS-40 ecs-core P2 R-20260925-2\n' | head -n "$max"
EOF
fi
qm() { sh "$qbin/session-monitor.sh" "$@" --state "$qstate"; }
out=$(qm --queue --dry-run 2>/dev/null)
order=$(printf '%s\n' "$out" | awk '$2 == "printed" { printf "%s ", $1 }')
if [ "$order" = 'T-ECS-41-lead T-ECS-42-lead T-ECS-40-lead ' ]; then printf 'PASS the queue goes out in dispatch order\n'
else printf 'FAIL the queue went out as %s\n' "$order"; fail=1; fi
check 'a queued unit is a lead' \
  "cd $qroot/ecs-core/T-ECS-41 && FACTORY_ROLE=repo-lead FACTORY_UNIT=T-ECS-41-lead CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude "
out=$(qm --queue --max 1 --dry-run 2>/dev/null)
check '--queue --max 1 takes the top line'          '^T-ECS-41-lead printed '
nocheck '--queue --max 1 takes no second line'      '^T-ECS-42-lead '
sh "$qbin/capacity.sh" acquire sessions T-X-1 --state "$qstate"
sh "$qbin/capacity.sh" acquire sessions T-X-2 --state "$qstate"
: > "$HERDR_STUB_LOG"
out=$(qm --queue 2>/dev/null)
check 'the queue spawns the first lead'             '^T-ECS-41-lead spawned '
check 'the queue spawns while two slots are free'   '^T-ECS-42-lead spawned '
nocheck 'the queue stops at one free slot'          '^T-ECS-40-lead '
exists 'a queued lead leases a repo-lead slot'      "$qstate/.capacity/repo-lead/T-ECS-41"
exists 'a queued lead leases a sessions slot'       "$qstate/.capacity/sessions/T-ECS-41-lead"
out=$(cat "$HERDR_STUB_LOG")
check 'a queued lead gets its own workspace'        '^workspace create .*--label "T-ECS-41 ecs-core"'
out=$(cat "$qstate/repos/ecs-core/tasks/T-ECS-41.md")
check 'the queue claims nothing'                    '^owner: null$'
rm -rf "$qstate/.capacity"
printf 'spawn: herdr\ncapacity:\n  sessions: 10\n  roles: {repo-lead: 1}\n' > "$qstate/factory.yml"
sh "$qbin/capacity.sh" acquire repo-lead T-ECS-99 --state "$qstate"
out=$(qm --queue --dry-run 2>/dev/null)
nocheck 'a full repo-lead cap takes nothing'        ' printed '

exit $fail
