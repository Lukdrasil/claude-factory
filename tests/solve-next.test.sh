#!/bin/sh
# solve-next.sh over a throwaway state clone, step 11 with the stacked block MRs: a block in `review` with its
# MR open does not hold the blocks behind it, and once every block is such a block the step is the reminder
# that lists the open MRs for the human.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

root="$tmp/factory"
state="$root/state"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/plans" "$state/repos/demo/progress" "$root/demo/T-001"
: > "$root/demo/T-001/.git"
: > "$state/repos/demo/plans/x-plan-ready.md"

cat > "$state/repos/demo/tasks/T-001.md" <<'EOF'
---
id: T-001
repo: demo
status: in_progress
archetype: feature
tier: yellow
complexity: medium
branch: work/T-001
---

# Goal
feat(demo): the parent

## Context
plans/x-plan-ready.md
EOF

printf 'wave 1: T-001-01\nwave 2: T-001-02\n' > "$state/repos/demo/progress/T-001.md"
printf 'base: work/T-001\n' > "$state/repos/demo/progress/T-001-01.md"
printf 'base: block/T-001-01\n' > "$state/repos/demo/progress/T-001-02.md"

block() { # <id> <status> <mr_url>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: $2
archetype: feature
tier: green
complexity: low
mr_url: $3
---

# Goal
feat(demo): $1
EOF
}

fail=0
check() { # <what> <pattern> <output>
  if printf '%s\n' "$3" | grep -q "$2"; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

block T-001-01 review https://forge.test/mr/1
block T-001-02 draft null
out=$(sh "$bin/solve-next.sh" T-001 --state "$state" 2>&1)
check "the step is for the later block"   "Step 11 of 16: worktree and claim for T-001-02" "$out"
if printf '%s\n' "$out" | grep -q 'waits for the developer'; then printf 'FAIL open MR stalls the stack\n'; fail=1
else printf 'PASS open MR does not stall the stack\n'; fi

block T-001-02 review https://forge.test/mr/2
out=$(sh "$bin/solve-next.sh" T-001 --state "$state" 2>&1)
check 'the reminder is the step'         'Step 11 of 16: T-001 waits for the developer' "$out"
check 'the first MR is listed with its base'  '^  T-001-01 https://forge.test/mr/1 -> work/T-001$' "$out"
check 'the second MR is listed with its base' '^  T-001-02 https://forge.test/mr/2 -> block/T-001-01$' "$out"
check 'the human is asked to review and merge' 'Completion: the human has been asked to review and merge' "$out"
check 'mr-watch is armed'                'mr-watch.sh T-001 --interval 300' "$out"
check 'new-comments has its own answer'  'new-comments' "$out"

parent() { # <id> <context line>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: in_progress
archetype: feature
tier: yellow
complexity: medium
---

# Goal
feat(demo): $1

## Context
$2
EOF
}

parent T-002 'no plan named here'
printf -- '---\nrepo: demo\ntask: T-002\n---\n' > "$state/repos/demo/plans/y-plan-ready.md"
out=$(sh "$bin/solve-next.sh" T-002 --state "$state" 2>&1)
check 'the plan is found by its task line' 'Step 6 of 16: decompose T-002' "$out"
check 'the plan found is the one naming the task' "plans/y-plan-ready.md" "$out"

mkdir -p "$tmp/product/docs/architecture"
printf 'demo:\n  path: %s\n' "$tmp/product" > "$state/repos.yml"
parent T-003 'plans/x-plan-ready.md'
block T-003-01 draft null
out=$(sh "$bin/solve-next.sh" T-003 --state "$state" 2>&1)
check 'a decomposed parent needs no verdict' 'Step 8 of 16: check the cut of T-003' "$out"

parent T-004 'plans/x-plan-ready.md'
out=$(sh "$bin/solve-next.sh" T-004 --state "$state" 2>&1)
check 'a parent with no blocks still needs the verdict' 'Step 5 of 16: architect plan-check of x' "$out"

exit $fail
