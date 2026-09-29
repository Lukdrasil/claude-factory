#!/bin/sh
# session-monitor.sh over a throwaway state repo: a bare call names no task and only lists what is ready,
# --all dispatches the batch, --task dispatches exactly one unit - the wave of a cut's blocks, or a ready leaf
# alone - an owned task is skipped, a task with no worktree is skipped, the manual mode prints a command
# instead of spawning anything, a parent with an open block MR gets its mr-watch.sh pass, and a real dispatch
# claims the unit in the state clone before the session starts. herdr opens the tabs when it is on PATH and
# HERDR_ENV=1, the lines are printed otherwise; a --task herdr spawn leaves the monitor's HERDR_TAB_ID in the
# herd-monitor file of its parent, and every pass that is not a dry run ends with state-push.sh.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR HERDR_ENV HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_PANE_ID FACTORY_CLAUDE_ARGS HERDR_STUB_CREATE \
  HERDR_STUB_START HERDR_STUB_STALLS

# no real herdr on PATH: every directory that holds one is left out, so the first part runs with no herdr at all
nopath=''
oldifs=$IFS
IFS=:
for d in $PATH; do
  [ -n "$d" ] && [ ! -x "$d/herdr" ] || continue
  nopath="${nopath:+$nopath:}$d"
done
IFS=$oldifs
PATH=$nopath
export PATH

root="$tmp/factory"
state="$root/state"
mkdir -p "$state/repos/demo/tasks" "$root/demo/T-001"
: > "$root/demo/T-001/.git"

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
exists() { # <what> <path>
  if [ -e "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
absent() { # <what> <path>
  if [ -e "$2" ]; then printf 'FAIL %s\n' "$1"; fail=1; else printf 'PASS %s\n' "$1"; fi
}
exits() { # <what> <want> <got>
  if [ "$3" -eq "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s (exit %s, want %s)\n' "$1" "$3" "$2"; fail=1; fi
}

# the bare call: the question "which task", answered with the list, never with a dispatch
out=$(sh "$bin/session-monitor.sh" --state "$state" 2>/dev/null); rc=$?
exits 'a bare call exits 1' 1 "$rc"
check 'a bare call lists the ready task'   '^T-001 demo ready feature feat(demo): a goal that is also a title$'
check 'a bare call lists the second one'   '^T-002 demo ready feature '
nocheck 'a bare call dispatches nothing'   'printed\|spawned'
nocheck 'a bare call leaves owned tasks out' '^T-003 '
err=$(sh "$bin/session-monitor.sh" --state "$state" 2>&1 >/dev/null || :)
out=$err
check 'the bare call asks for one task'    'name one task: --task T-NNN'

# --all: the batch mode, which has to be asked for by name; with no herdr the lines are printed
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

# --spawn herdr with no herdr on PATH prints, with the reason on stderr; unasked, the fallback is silent
out=$(sh "$bin/session-monitor.sh" --task T-001 --spawn herdr --state "$state" --dry-run 2>"$tmp/nh.err")
check '--spawn herdr with no herdr still prints the unit' '^T-001 printed '
out=$(cat "$tmp/nh.err")
check 'and says herdr is not on PATH'   'herdr is not on PATH; printing the commands instead'
sh "$bin/session-monitor.sh" --task T-001 --state "$state" --dry-run >/dev/null 2>"$tmp/nh.err"
out=$(cat "$tmp/nh.err")
nocheck 'an unasked fallback says nothing' 'printing'

# --task of a parent with a cut: the current wave of its blocks, not the parent itself
mkdir -p "$root/demo/T-006-01"
: > "$root/demo/T-006-01/.git"
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
out=$(sh "$bin/session-monitor.sh" --task T-006 --wave 1 --state "$state" --dry-run 2>/dev/null)
check '--wave 1 names the same wave'  '^T-006-01 printed '

block() { # <id> <status> <owner> <phase or -> <path>
  mkdir -p "$root/demo/$1"
  : > "$root/demo/$1/.git"
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
check 'it goes out as a block session of its archetype skill' 'skills/_shared/block-session\.md, the delivery of a block session; then /claude-factory:block-feature '
nocheck 'it is no subagent brief'                  'You are implementer'
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

# --max caps how many go out at once; the rest is skipped
out=$(sh "$bin/session-monitor.sh" --task T-007 --max 1 --state "$state" --dry-run 2>/dev/null)
check '--max 1 sends the first unit'             '^T-007-02 printed '
check '--max 1 skips the second'                 '^T-007-03 skipped '

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
check 'the grill step runs as FACTORY_ROLE=grill' 'FACTORY_ROLE=grill FACTORY_UNIT=T-005-grill CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude '
out=$(sh "$bin/session-monitor.sh" --task T-005 --step plan-check --state "$state" --dry-run 2>&1); rc=$?
exits 'plan-check before a plan exists exits 1' 1 "$rc"
check 'and names the missing plan' 'has no plan-ready file'
mkdir -p "$state/repos/demo/plans"
printf -- '---\nrepo: demo\ntask: T-005\n---\n' > "$state/repos/demo/plans/p5-plan-ready.md"
out=$(sh "$bin/session-monitor.sh" --task T-005 --step plan-check --state "$state" --dry-run 2>/dev/null)
check 'the plan-check step prompts the architect review over the plan' "\"/claude-factory:architect-review plan-check $state/repos/demo/plans/p5-plan-ready\.md\"\$"
check 'the plan-check step runs in the state clone' "^T-005-plan-check printed $state\$"
out=$(sh "$bin/session-monitor.sh" --task T-005 --step decompose --state "$state" --dry-run 2>/dev/null)
check 'the decompose step prompts the decompose skill over the plan' "\"/claude-factory:decompose $state/repos/demo/plans/p5-plan-ready\.md\"\$"

out=$(sh "$bin/session-monitor.sh" --parent T-005 --step grill --state "$state" 2>/dev/null)
check '--parent is still the same flag' "^T-005-grill printed $tmp/clone\$"

# the modes and flags the monitor no longer has, and the ones it refuses to mix
for bad in '--task T-005 --step nonsense' '--task T-005 --step chart' '--task T-005 --step lead' \
  '--task T-005 --step cross-repo' '--step pass --scope demo/implementer' '--step onboard --scope demo' \
  '--step intake --scope R-20260925-1' '--step grill' '--queue' '--task T-005 --scope demo' \
  '--task T-005 --priority P1' '--task T-005 --all' '--task T-005 --spawn tmux' '--task T-005 --max x' \
  '--task nonsense' '--task T-404'; do
  # shellcheck disable=SC2086
  sh "$bin/session-monitor.sh" $bad --state "$state" --dry-run >/dev/null 2>&1; rc=$?
  exits "$bad exits 1" 1 "$rc"
done

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
  "$hroot/demo/T-101" "$hroot/plain/T-102" "$hroot/demo/T-103-01" "$hroot/demo/T-107"
for d in demo/T-101 plain/T-102 demo/T-103-01 demo/T-107; do : > "$hroot/$d/.git"; done
printf 'demo: { path: %s, emoji: 🦊 }\nplain: { path: %s }\n' "$tmp/clone" "$tmp/clone" > "$hstate/repos.yml"
leaf() { # <id> <repo>
  printf -- '---\nid: %s\nrepo: %s\nstatus: ready\narchetype: feature\ntier: green\ncomplexity: low\nowner: null\n---\n\n# Goal\nfeat(%s): a leaf\n' \
    "$1" "$2" "$2" > "$hstate/repos/$2/tasks/$1.md"
}
leaf T-101 demo
leaf T-102 plain
leaf T-107 demo
printf -- '---\nid: T-103\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\n---\n\n# Goal\nfeat(demo): a parent\n' \
  > "$hstate/repos/demo/tasks/T-103.md"
printf -- '---\nid: T-103-01\nrepo: demo\nstatus: ready\narchetype: feature\ntier: green\ncomplexity: low\nowner: null\n---\n\n# Goal\nfeat(demo): a block\n\nDesign (approved in the grill):\n\n### `src/g.ts`\n\nAdd it.\n\n## Acceptance\n\n`npm test` is green.\n' \
  > "$hstate/repos/demo/tasks/T-103-01.md"

# the spawn mode: herdr on PATH and HERDR_ENV=1 is herdr unasked, a session outside a herdr pane prints, and
# --spawn manual prints with herdr right there
: > "$HERDR_STUB_LOG"
out=$(HERDR_ENV=0 sh "$bin/session-monitor.sh" --task T-107 --state "$hstate" --dry-run 2>"$tmp/m.err")
check 'outside a herdr pane the unit is printed'  '^T-107 printed '
out=$(cat "$tmp/m.err")
nocheck 'an unasked print says nothing'           'printing instead'
out=$(HERDR_ENV=0 sh "$bin/session-monitor.sh" --task T-107 --spawn herdr --state "$hstate" --dry-run 2>"$tmp/m.err")
check '--spawn herdr outside a pane still prints' '^T-107 printed '
out=$(cat "$tmp/m.err")
check 'and says it is not inside a herdr pane'    'not inside a herdr pane; printing instead'
out=$(sh "$bin/session-monitor.sh" --task T-107 --spawn manual --state "$hstate" --dry-run 2>/dev/null)
check '--spawn manual prints inside herdr too'    '^T-107 printed '
out=$(cat "$HERDR_STUB_LOG")
nocheck 'no printed run opens a tab'              '^tab create '

# the stub starts no agent, so the one herdr would report once claude is up is set beforehand
herdr_agent implementer_t-101 idle pane-1 sess-101
out=$(sh "$bin/session-monitor.sh" --task T-101 --state "$hstate" 2>/dev/null)
check 'herdr on PATH with HERDR_ENV=1 spawns unasked' '^T-101 spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'the tab carries the session name'        '^tab create .*--label "🦊 demo T-101"'
check 'claude carries the session name'         '^agent start implementer_t-101 .* -- .*--name "🦊 demo T-101"'
out=$(cat "$hroot/demo/.harness/T-101/herdr-tabs" 2>/dev/null)
check 'the leaf spawn is in the tab record'     '^T-101 tab-1 pane-1$'
check 'the record gains the session id once claude is up, for reattach after a herdr restart' '^T-101 tab-1 pane-1 sess-101$'
out=$(cat "$hroot/demo/.harness/T-101/herdr-names" 2>/dev/null)
check 'the record keeps the herdr name beside it' '^T-101 implementer_t-101$'
absent 'a spawn with no HERDR_TAB_ID writes no herd-monitor' "$hroot/demo/.harness/T-101/herd-monitor"

: > "$HERDR_STUB_LOG"
out=$(FACTORY_CLAUDE_ARGS='--plugin-dir /sim/plugin --settings /sim/settings.json' \
  sh "$bin/session-monitor.sh" --task T-102 --spawn herdr --state "$hstate" 2>/dev/null)
out=$(cat "$HERDR_STUB_LOG")
check 'FACTORY_CLAUDE_ARGS rides along on agent start' \
  '^agent start implementer_t-102 .* -- .*--name "[^"]*" --plugin-dir /sim/plugin --settings /sim/settings.json $'
out=$(FACTORY_CLAUDE_ARGS='--plugin-dir /sim/plugin' sh "$bin/session-monitor.sh" --task T-102 --dry-run --state "$hstate" 2>/dev/null)
check 'and on a printed line'                   'claude --model [^ ]* --name "[^"]*" --plugin-dir /sim/plugin "'

# the herd-monitor file: a --task herdr spawn from a monitor pane leaves its HERDR_TAB_ID under the parent
out=$(HERDR_TAB_ID=tab-mon sh "$bin/session-monitor.sh" --task T-103 --spawn herdr --state "$hstate" 2>/dev/null)
check 'a herdr spawn of a block goes out'       '^T-103-01 spawned '
out=$(cat "$hroot/demo/.harness/T-103/herdr-tabs" 2>/dev/null)
check 'a block lands in its parent tab record'  '^T-103-01 tab-1 pane-1$'
out=$(cat "$hroot/demo/.harness/T-103/herd-monitor" 2>/dev/null)
check 'the parent herd-monitor holds the monitor tab' '^tab-mon$'
absent 'no herd-monitor is written under the block id' "$hroot/demo/.harness/T-103-01/herd-monitor"

# a block in_progress that no live session carries (a session that died, a spawn that failed after its claim) is
# dispatched again in herdr; one whose session runs is not, and a dry run or a printed run never takes it
mkdir -p "$hroot/demo/T-108-01" && : > "$hroot/demo/T-108-01/.git"
printf -- '---\nid: T-108\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\n---\n\n# Goal\nfeat(demo): a parent\n' \
  > "$hstate/repos/demo/tasks/T-108.md"
printf -- '---\nid: T-108-01\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\nowner: factory@host:pending-T-108-01\n---\n\n# Goal\nfeat(demo): a stranded block\n\nDesign (approved in the grill):\n\n### `src/s.ts`\n\nAdd it.\n\n## Acceptance\n\n`npm test` is green.\n' \
  > "$hstate/repos/demo/tasks/T-108-01.md"
out=$(sh "$bin/session-monitor.sh" --task T-108 --dry-run --state "$hstate" 2>/dev/null)
nocheck 'a dry run leaves a stranded block alone'  '^T-108-01 printed '
out=$(sh "$bin/session-monitor.sh" --task T-108 --spawn herdr --state "$hstate" 2>/dev/null)
check 'a stranded block with no live session goes out again' '^T-108-01 spawned '
herdr_agent implementer_t-108-01 working pane-81 sess-81
printf 'T-108-01 tab-81 pane-81 sess-81\n' >> "$hroot/demo/.harness/T-108/herdr-tabs"
out=$(sh "$bin/session-monitor.sh" --task T-108 --spawn herdr --state "$hstate" 2>/dev/null)
nocheck 'a block whose session runs is not dispatched twice' '^T-108-01 spawned '

HERDR_TAB_ID=tab-mon sh "$bin/session-monitor.sh" --task T-107 --dry-run --state "$hstate" >/dev/null 2>&1
absent 'a dry run writes no herd-monitor'       "$hroot/demo/.harness/T-107/herd-monitor"
HERDR_TAB_ID=tab-mon sh "$bin/session-monitor.sh" --task T-107 --spawn manual --state "$hstate" >/dev/null 2>&1
absent 'a printed run writes no herd-monitor'   "$hroot/demo/.harness/T-107/herd-monitor"

out=$(HERDR_TAB_ID=tab-mon2 sh "$bin/session-monitor.sh" --task T-101 --step grill --spawn herdr --state "$hstate" 2>/dev/null)
check 'a herdr spawn of a step goes out'        '^T-101-grill spawned '
out=$(cat "$hroot/demo/.harness/T-101/herdr-tabs" 2>/dev/null)
check 'a step lands in its task tab record'     '^T-101-grill tab-1 pane-1$'
out=$(cat "$hroot/demo/.harness/T-101/herdr-names" 2>/dev/null)
check 'a step keeps its herdr name'             '^T-101-grill grill_t-101$'
out=$(cat "$hroot/demo/.harness/T-101/herd-monitor" 2>/dev/null)
check 'a step spawn writes the herd-monitor of its task' '^tab-mon2$'

: > "$HERDR_STUB_LOG"
out=$(HERDR_TAB_ID=tab-mon sh "$bin/session-monitor.sh" --all --spawn herdr --state "$hstate" 2>/dev/null)
check '--all spawns the unit of the other repo' '^T-102 spawned '
out=$(cat "$HERDR_STUB_LOG")
check '--all names the tab by its repo'         '^tab create .*--label "[^ ]* plain T-102"'
check '--all names the claude session too'      '^agent start implementer_t-102 .* -- .*--name "[^ ]* plain T-102"'
out=$(cat "$hroot/plain/.harness/T-102/herdr-tabs" 2>/dev/null)
check '--all records its tab'                   '^T-102 tab-1 pane-1$'
absent '--all writes no herd-monitor'           "$hroot/plain/.harness/T-102/herd-monitor"

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
  : > "$hroot/demo/$2/.git"
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
out=$(cat "$hstate/repos/demo/tasks/T-105-01.md")
nocheck 'the skipped block is not claimed'       '^status: in_progress$'

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
: > "$hroot/demo/T-111-02/.git"
sed 's/T-111-01/T-111-02/; s/h\.ts/i.ts/' "$hstate/repos/demo/tasks/T-111-01.md" > "$hstate/repos/demo/tasks/T-111-02.md"
HERDR_STUB_CREATE='{"result":{"root_pane":{"pane_id":"pane-1"}}}'
export HERDR_STUB_CREATE
: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --task T-111 --spawn herdr --state "$hstate" 2>"$tmp/t111.err")
unset HERDR_STUB_CREATE
check 'a tab with no id still spawns the unit'   '^T-111-01 spawned '
check 'the next unit of the batch is spawned'    '^T-111-02 spawned '
out=$(cat "$tmp/t111.err")
check 'a tab with no id says it has no record'   'no tab record for T-111-01'
out=$(cat "$HERDR_STUB_LOG")
check 'the first unit starts its agent'          '^agent start implementer_t-111-01 '
check 'the next unit starts its agent'           '^agent start implementer_t-111-02 '
out=$(cat "$hroot/demo/.harness/T-111/herdr-tabs" 2>/dev/null)
nocheck 'a tab with no id writes no record line' '^T-111-0'

# a tab create that gives no pane at all is a failed spawn: exit 2, no agent
armed T-112 T-112-01
: > "$HERDR_STUB_LOG"
out=$(HERDR_STUB_CREATE='' sh "$bin/session-monitor.sh" --task T-112 --spawn herdr --state "$hstate" 2>/dev/null); rc=$?
exits 'a tab create with no pane exits 2' 2 "$rc"
out=$(cat "$HERDR_STUB_LOG")
nocheck 'a tab create with no pane starts no agent' '^agent start '

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

# a herdr name stops at 31 characters
printf -- '---\nid: T-12345678901234567890123\nrepo: demo\nstatus: ready\narchetype: feature\ntier: green\ncomplexity: low\nowner: null\n---\n\n# Goal\nfeat(demo): a long id\n' \
  > "$hstate/repos/demo/tasks/T-12345678901234567890123.md"
: > "$HERDR_STUB_LOG"
sh "$bin/session-monitor.sh" --task T-12345678901234567890123 --step triage --spawn herdr --state "$hstate" >/dev/null 2>&1
out=$(cat "$HERDR_STUB_LOG")
check 'a herdr name stops at 31 characters'      '^agent start triage_t-1234567890123456789012 '
unset HERDR_TAB_ID

# the stub answers the verbs the monitor, herd-watch and herdr-tabs drive with the herdr 0.8.2 shapes, over a
# fresh stub; `js <expression>` prints one expression over the JSON on stdin, `o` being the parsed reply
js() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);process.stdout.write(String(eval(process.argv[1])))})' "$1"; }
herdr_stub "$tmp/stub2"
herdr_agent grill_ecs-12 working w1:p2 sess-a
herdr_agent - idle w1:p3 sess-b
herdr_tab tab-9 done false t-009
out=$(herdr agent list | js 'o.result.type+" "+o.result.agents.map(a=>[a.name||"-",a.pane_id,a.agent_status,a.agent_session?a.agent_session.value:"-"].join(",")).sort().join(" ")')
check 'agent list names every live agent with pane, status and session' \
  '^agent_list -,w1:p3,idle,sess-b grill_ecs-12,w1:p2,working,sess-a t-009,pane-9,done,-$'
out=$(herdr agent get grill_ecs-12 | js 'o.result.type+" "+o.result.agent.pane_id+" "+o.result.agent.agent_session.value')
check 'agent get takes a name'                   '^agent_info w1:p2 sess-a$'
out=$(herdr agent get w1:p3 | js 'o.result.agent.agent_status+" "+("name" in o.result.agent)')
check 'agent get takes a pane id, an unnamed agent has no name' '^idle false$'
out=$(herdr agent get nosuch 2>&1 >/dev/null | js 'o.error.code'; herdr agent get nosuch >/dev/null 2>&1; echo " $?")
check 'an absent agent is agent_not_found, exit 1' '^agent_not_found 1$'
out=$(herdr agent wait w1:p3 --until idle --until done --timeout 1000 | js 'o.result.agent.agent_status')
check 'agent wait answers an agent already in the state' '^idle$'
out=$(herdr agent wait grill_ecs-12 --until idle --timeout 1000 2>&1 >/dev/null | js 'o.error.code'; herdr agent wait grill_ecs-12 --timeout 1 >/dev/null 2>&1; echo " $?")
check 'agent wait of a working agent times out'  '^timeout 1$'
herdr agent rename w1:p3 architecture-auditor_ecs-142-03 >/dev/null
out=$(herdr agent get architecture-auditor_ecs-142-03 | js 'o.result.agent.pane_id')
check 'agent rename names the agent of a pane'   '^w1:p3$'
out=$(herdr tab create --workspace ws-1 --label 'x y' --env FACTORY_ROLE=implementer --env FACTORY_UNIT=T-ECS-12-03 --no-focus \
  | js 'o.result.type+" "+o.result.tab.tab_id+" "+o.result.tab.workspace_id+" "+o.result.root_pane.pane_id')
check 'tab create answers tab and root pane'     '^tab_created tab-1 ws-1 pane-1$'
out=$(cat "$HERDR_STUB_DIR/env/pane-1")
check 'tab create honours every --env'           '^FACTORY_UNIT=T-ECS-12-03$'
herdr tab create --env FACTORY_ROLE=grill >/dev/null
out=$(cat "$HERDR_STUB_DIR/env/pane-1")
nocheck 'a new pane forgets the env of the last one' 'FACTORY_UNIT=T-ECS-12-03'
out=$(herdr tab get tab-9 | js 'o.result.tab.agent_status+" "+o.result.tab.workspace_id')
check 'tab get answers the live tab'             '^done ws-1$'
herdr tab close tab-9 >/dev/null
out=$(herdr agent get t-009 2>&1 >/dev/null | js 'o.error.code')
check 'tab close ends the agent in that tab'     '^agent_not_found$'
out=$(HERDR_STUB_START=agent_not_ready herdr agent start x --kind claude --pane w1:p2 2>&1 >/dev/null | js 'o.error.code')
check 'HERDR_STUB_START fails agent start with its code' '^agent_not_ready$'

# alias ids, T-<ALIAS>-<n>: the wave of an alias cut goes out through spawn-plan.sh, herdr-tabs.sh names, records
# and reads its units under the parent, and --all sweeps that record
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
: > "$hroot/demo/T-DM-7-01/.git"
: > "$HERDR_STUB_LOG"
out=$(sh "$bin/session-monitor.sh" --task T-DM-7 --spawn herdr --state "$hstate" 2>/dev/null)
check 'a herdr spawn of an alias block goes out' '^T-DM-7-01 spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'its agent is role_ plus the id less t-'  '^agent start implementer_dm-7-01 '
out=$(cat "$hroot/demo/.harness/T-DM-7/herdr-tabs" 2>/dev/null)
check 'an alias block lands in its parent tab record' '^T-DM-7-01 tab-1 pane-1$'
out=$(cat "$hroot/demo/.harness/T-DM-7/herdr-names" 2>/dev/null)
check 'an alias block keeps its herdr name'      '^T-DM-7-01 implementer_dm-7-01$'
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

# the env, the agent start and the prompt of a herdr spawn, over a fresh stub and a state with an alias repo:
# every spawn passes the three --env pairs and no other, names its agent <role>_<id less t->, and every pass
# that is not a dry run ends with state-push.sh
herdr_stub "$tmp/stub3"
oroot="$tmp/o"
ostate="$oroot/state"
mkdir -p "$ostate/repos/ecs-core/tasks" "$oroot/ecs-core/T-ECS-12/.git" "$oroot/ecs-core/T-ECS-20-01" \
  "$oroot/ecs-core/T-ECS-30" "$tmp/eclone"
for d in T-ECS-20-01 T-ECS-30; do : > "$oroot/ecs-core/$d/.git"; done
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
otask "$ostate" T-ECS-12 ready
otask "$ostate" T-ECS-13 ready
otask "$ostate" T-ECS-14 ready
otask "$ostate" T-ECS-20 in_progress
otask "$ostate" T-ECS-20-01 ready
otask "$ostate" T-ECS-30 ready
otask "$ostate" T-ECS-40 in_progress
otask "$ostate" T-ECS-40-01 done
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
before() { # <what> <first pattern> <second pattern>: both in the stub log, the first one earlier
  if awk -v a="$2" -v b="$3" '$0 ~ a && !x { x = NR } $0 ~ b && !y { y = NR } END { exit !(x && y && x < y) }' "$HERDR_STUB_LOG"
  then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# --step grill: a step tab in the session worktree with the env, the name and the grill prompt, not claimed
: > "$HERDR_STUB_LOG"
out=$(sm --task T-ECS-12 --step grill --workspace ws-7 2>/dev/null)
check 'the grill step goes out in the session worktree' "^T-ECS-12-grill spawned $oroot/ecs-core/T-ECS-12\$"
out=$(envof)
check 'a spawn passes FACTORY_ROLE'                 '^FACTORY_ROLE=grill$'
check 'a spawn passes FACTORY_UNIT'                 '^FACTORY_UNIT=T-ECS-12-grill$'
check 'a spawn turns the auto memory off'           '^CLAUDE_CODE_DISABLE_AUTO_MEMORY=1$'
nocheck 'a spawn passes no FACTORY_TASK'            '^FACTORY_TASK='
nocheck 'a spawn passes no FACTORY_STEP'            '^FACTORY_STEP='
nocheck 'a spawn passes no FACTORY_FLOW'            '^FACTORY_FLOW='
out=$(cat "$HERDR_STUB_LOG")
check 'the tab lands in --workspace'                "^tab create --cwd $oroot/ecs-core/T-ECS-12 --label \"🐳 ecs-core T-ECS-12-grill\" --no-focus --workspace ws-7 "
check 'a step agent is <step>_<id less t->'         '^agent start grill_ecs-12 --kind claude --pane pane-1 '
check 'agent start waits up to 120 s'               '^agent start grill_ecs-12 .*--timeout 120000 '
check 'the grill prompt runs the grill skill'       "^agent prompt grill_ecs-12 \"/claude-factory:grill $ostate/repos/ecs-core/tasks/T-ECS-12.md\" --wait --until working --until blocked --until done --timeout 60000 \$"
out=$(cat "$ostate/repos/ecs-core/tasks/T-ECS-12.md")
check 'a step leaves the status alone'              '^status: ready$'
check 'a step claims no owner'                      '^owner: null$'
: > "$HERDR_STUB_LOG"
HERDR_WORKSPACE_ID=ws-9 sm --task T-ECS-13 --step grill >/dev/null 2>&1
out=$(cat "$HERDR_STUB_LOG")
check 'the workspace defaults to HERDR_WORKSPACE_ID' '^tab create .* --workspace ws-9 '

# a manual line carries the env as a prefix; the triage prompt names its report path and sections
out=$(sm --task T-ECS-14 --step triage --dry-run 2>/dev/null)
check 'a manual line prints the env as a prefix' \
  "cd \"$tmp/eclone\" && FACTORY_ROLE=triage FACTORY_UNIT=T-ECS-14-triage CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude --model "
check 'the triage prompt asks for ## Related issues as its own section' 'write ## Related issues as its own section after ## Context'
check 'the triage prompt names the report path in the state clone' "file the investigation report at $ostate/repos/ecs-core/research/T-ECS-14-investigation.md, "
out=$(sm --task T-ECS-14 --step grill --dry-run 2>/dev/null)
check 'a step with no worktree runs in the registered clone' "^T-ECS-14-grill printed $tmp/eclone\$"

# agent_not_ready: the start dialog is waited out, then the prompt goes in; a wait that times out prompts nothing
herdr_agent grill_ecs-13 idle pane-13
: > "$HERDR_STUB_LOG"
out=$(HERDR_STUB_START=agent_not_ready sm --task T-ECS-13 --step grill 2>/dev/null)
check 'a start at a dialog still goes out'          '^T-ECS-13-grill spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'agent_not_ready waits for idle or done'      '^agent wait grill_ecs-13 --until idle --until done --timeout 120000 '
before 'the prompt comes after the wait'            '^agent wait grill_ecs-13 ' '^agent prompt grill_ecs-13 '
herdr_agent grill_ecs-14 working pane-14
: > "$HERDR_STUB_LOG"
out=$(HERDR_STUB_START=agent_not_ready sm --task T-ECS-14 --step grill 2>/dev/null); rc=$?
exits 'a wait that times out exits 2' 2 "$rc"
out=$(cat "$HERDR_STUB_LOG")
nocheck 'a wait that times out prompts nothing'     '^agent prompt grill_ecs-14 '
: > "$HERDR_STUB_LOG"
out=$(HERDR_STUB_START=agent_failed sm --task T-ECS-14 --step triage 2>/dev/null); rc=$?
exits 'a start that fails otherwise exits 2' 2 "$rc"
out=$(cat "$HERDR_STUB_LOG")
nocheck 'a failed start waits for nothing'          '^agent wait '
nocheck 'a failed start prompts nothing'            '^agent prompt '

# a prompt herdr saw no state change after (agent_prompt_stalled) is typed once more; a second stall exits 2
: > "$HERDR_STUB_LOG"
rm -f "$HERDR_STUB_DIR/stalls"
out=$(HERDR_STUB_STALLS=1 sm --task T-ECS-13 --step grill 2>/dev/null)
check 'a prompt that stalled once still goes out'   '^T-ECS-13-grill spawned '
out=$(grep -c '^agent prompt grill_ecs-13 ' "$HERDR_STUB_LOG")
check 'the stalled prompt is typed twice'           '^2$'
: > "$HERDR_STUB_LOG"
rm -f "$HERDR_STUB_DIR/stalls"
HERDR_STUB_STALLS=2 sm --task T-ECS-13 --step grill >/dev/null 2>&1; rc=$?
exits 'a prompt that stalls twice exits 2' 2 "$rc"
out=$(grep -c '^agent prompt grill_ecs-13 ' "$HERDR_STUB_LOG")
check 'it is not typed a third time'                '^2$'
rm -f "$HERDR_STUB_DIR/stalls"

# a block of a cut: its agent role and name, and its claim
: > "$HERDR_STUB_LOG"
out=$(sm --task T-ECS-20 2>/dev/null)
check 'a block goes out'                            '^T-ECS-20-01 spawned '
out=$(cat "$HERDR_STUB_LOG")
check 'a block agent is <role>_<id less t->'        '^agent start implementer_ecs-20-01 '
out=$(envof)
check 'a block passes its agent role'               '^FACTORY_ROLE=implementer$'
check 'a block passes its unit'                     '^FACTORY_UNIT=T-ECS-20-01$'
out=$(cat "$ostate/repos/ecs-core/tasks/T-ECS-20-01.md")
check 'a spawned block is claimed'                  '^owner: factory@.*:pending-T-ECS-20-01$'

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

# a pass that dispatches nothing still pushes what the writers committed; a dry one still does not
git -C "$ostate" commit -q --allow-empty -m 'a second local commit'
out=$(sm --task T-ECS-40 --dry-run 2>/dev/null)
check 'a parent with every block done has nothing to dispatch' '^nothing to dispatch: every block of T-ECS-40 '
out=$(git -C "$tmp/o-root" log --format=%s main)
nocheck 'the dry nothing-to-dispatch pushes nothing' '^a second local commit$'
out=$(sm --task T-ECS-40 2>/dev/null)
out=$(git -C "$tmp/o-root" log --format=%s main)
check 'a nothing-to-dispatch pass still pushes'     '^a second local commit$'
git -C "$ostate" commit -q --allow-empty -m 'a third local commit'
out=$(sm --task T-ECS-30 2>/dev/null)
check 'a leaf no longer ready is skipped'           '^T-ECS-30 skipped '
out=$(git -C "$tmp/o-root" log --format=%s main)
check 'a pass that only skips still pushes'         '^a third local commit$'

exit $fail
