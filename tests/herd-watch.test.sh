#!/bin/sh
# herd-watch.sh over a throwaway state repo: the first pass prints the picture, an unchanged pass prints
# nothing, and a status or phase change prints one line with the transition.
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

exit $fail
