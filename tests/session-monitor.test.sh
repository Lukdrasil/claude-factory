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

exit $fail
