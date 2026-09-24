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
check 'it goes out with the implement agent'     'You are factory-block-implement\.'
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
check 'claude carries the session name'         '^agent start t-101 .* -- .*--name "🦊 demo T-101"'
out=$(cat "$hroot/demo/.harness/T-101/herdr-tabs" 2>/dev/null)
check 'the leaf spawn is in the tab record'     '^T-101 tab-1 pane-1$'

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
check '--all names the claude session too'      '^agent start t-102 .* -- .*--name "[^ ]* plain T-102"'
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
if awk '/^tab close tab-104 / && !c { c = NR } /^agent start t-104-01 / && !a { a = NR } END { exit !(c && a && c < a) }' "$HERDR_STUB_LOG"
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
nocheck 'the skipped block starts no agent'      '^agent start t-105-01 '

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
check 'the first unit starts its agent'          '^agent start t-111-01 '
check 'the next unit starts its agent'           '^agent start t-111-02 '
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

exit $fail
