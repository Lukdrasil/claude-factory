#!/bin/sh
# session-monitor.sh over a throwaway state repo: a ready unowned task is dispatched, an owned one is not,
# a task with no worktree is skipped, the manual mode prints a command instead of spawning anything, and a
# parent with an open block MR gets its mr-watch.sh pass.
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

out=$(sh "$bin/session-monitor.sh" --state "$state" 2>/dev/null)
fail=0
check() { # <what> <pattern>
  if printf '%s\n' "$out" | grep -q "$2"; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
check 'T-001 is printed'            '^T-001 printed '
check 'T-001 gets a claude command' 'claude --model .* "/claude-factory:block-feature '
check 'T-002 is skipped'            '^T-002 skipped '
if printf '%s\n' "$out" | grep -q '^T-003'; then printf 'FAIL owned task dispatched\n'; fail=1; else printf 'PASS owned task left alone\n'; fi

# a block in `review` with its MR open: the no-argument mode watches its parent for the merge
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

out=$(sh "$bin/session-monitor.sh" --state "$state" --dry-run 2>/dev/null)
check 'the open block MR is watched' "mr-watch.sh T-004 --once --state $state"

# --step: one session for a parent-level step, in the registered clone when there is no session worktree yet
mkdir -p "$tmp/clone"
printf 'demo: { path: %s }\n' "$tmp/clone" > "$state/repos.yml"
task T-005 null feature
out=$(sh "$bin/session-monitor.sh" --parent T-005 --step grill --state "$state" 2>/dev/null)
check 'the grill step runs in the clone' "^T-005-grill printed $tmp/clone\$"
check 'the grill step prompts the skill' '"/claude-factory:grill '

if sh "$bin/session-monitor.sh" --parent T-005 --step nonsense --state "$state" >/dev/null 2>&1; then
  printf 'FAIL an unknown step was accepted\n'; fail=1
else
  printf 'PASS an unknown step is refused\n'
fi

exit $fail
