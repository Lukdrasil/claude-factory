#!/bin/sh
# session-monitor.sh over a throwaway state repo: a ready unowned task is dispatched, an owned one is not,
# a task with no worktree is skipped, and the manual mode prints a command instead of spawning anything.
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

exit $fail
