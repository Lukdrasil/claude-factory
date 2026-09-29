#!/bin/sh
# solve-next.sh over a throwaway state clone, step 11 with the stacked block MRs of a task already stacked (a
# block cut from a block branch): a block in `review` with its MR open does not hold the blocks behind it, and
# once every block is such a block the step is the reminder that lists the open MRs for the human. T-252-02:
# stalled is no status any more, so it is not sent to approval. Step 11 of a task whose blocks are cut from the
# work branch merges a finished wave with block-mr-merge.sh before the next is cut, step 14 is the task MR the
# human reviews, and every step opens with state-push.sh.
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

check 'state-push.sh is the first command of the step' "^  .*state-push\.sh --state $state\$" \
  "$(printf '%s\n' "$out" | sed -n '/^Commands:$/{n;p;}')"

block T-001-02 review https://forge.test/mr/2
out=$(sh "$bin/solve-next.sh" T-001 --state "$state" 2>&1)
check 'the reminder is the step'         'Step 11 of 16: T-001 waits for the developer' "$out"
check 'the first MR is listed with its base'  '^  T-001-01 https://forge.test/mr/1 -> work/T-001$' "$out"
check 'the second MR is listed with its base' '^  T-001-02 https://forge.test/mr/2 -> block/T-001-01$' "$out"
check 'the human is asked to review and merge' 'Completion: the human has been asked to review and merge' "$out"
check 'mr-watch is armed'                'mr-watch.sh T-001 --interval 300' "$out"
check 'new-comments has its own answer'  'new-comments' "$out"
check 'an extra block gets a cut-check' 'skills/architect-review/SKILL.md.*cut-check\|cut-check.*skills/architect-review/SKILL.md' "$out"
check 'an extra block is written by task-new.sh --parent' 'task-new\.sh.*--parent' "$out"
if printf '%s\n' "$out" | grep -q 'task-template\.sh block > .*&&'; then printf 'FAIL the template is chained into task-new.sh\n'; fail=1
else printf 'PASS the template is not chained into task-new.sh\n'; fi
if printf '%s\n' "$out" | grep -q 'verdicts/x\.md'; then printf 'FAIL a clone without docs/architecture/ has no verdict to remove\n'; fail=1
else printf 'PASS a clone without docs/architecture/ has no verdict to remove\n'; fi

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

out=$(sh "$bin/solve-next.sh" T-001 --state "$state" 2>&1)
check 'with docs/architecture/, step 11 removes the extra block verdict' 'verdicts/x\.md' "$out"

parent T-004 'plans/x-plan-ready.md'
out=$(sh "$bin/solve-next.sh" T-004 --state "$state" 2>&1)
check 'a parent with no blocks still needs the verdict' 'Step 5 of 16: architect plan-check of x' "$out"

sed -i 's/^status: in_progress$/status: blocked/' "$state/repos/demo/tasks/T-001.md"
out=$(sh "$bin/solve-next.sh" T-001 --state "$state" 2>&1)
check 'a blocked parent is sent to approval' 'Step 9 of 16: approve and claim T-001' "$out"
sed -i 's/^status: blocked$/status: stalled/' "$state/repos/demo/tasks/T-001.md"
out=$(sh "$bin/solve-next.sh" T-001 --state "$state" 2>&1)
if printf '%s\n' "$out" | grep -q 'Step 9 of 16'; then printf 'FAIL a stalled parent is not sent to approval\n'; fail=1
else printf 'PASS a stalled parent is not sent to approval\n'; fi

no() { # <what> <pattern> <output>
  if printf '%s\n' "$3" | grep -q "$2"; then printf 'FAIL %s\n' "$1"; fail=1; else printf 'PASS %s\n' "$1"; fi
}

# --- steps 3 and 4: triage until ## Related issues is written, then the grill ------------------------------
cat > "$state/repos/demo/tasks/T-010.md" <<EOF
---
id: T-010
repo: demo
status: triaged
archetype: feature
tier: yellow
complexity: medium
---

# Goal
feat(demo): the invoice export
EOF
out=$(sh "$bin/solve-next.sh" T-010 --state "$state" 2>&1)
check 'a draft with tier: but no ## Related issues is still triage' '^## Step 3 of 16: triage T-010$' "$out"
printf '\n## Related issues\n\nnone\n' >> "$state/repos/demo/tasks/T-010.md"
out=$(sh "$bin/solve-next.sh" T-010 --state "$state" 2>&1)
check 'a triaged parent goes to the grill' '^## Step 4 of 16: grill T-010$' "$out"
check 'the grill reads its skill' 'skills/grill/SKILL.md' "$out"
no 'no request map is charted' 'map\.sh' "$out"

# --- step 11: the automatic block merges, one wave merged before the next is cut -------------------------
mkdir -p "$root/demo/T-005"
: > "$root/demo/T-005/.git"
parent T-005 'plans/x-plan-ready.md'
sed -i 's/^complexity: medium$/complexity: medium\nbranch: feat\/T-005-export/' "$state/repos/demo/tasks/T-005.md"
printf 'wave 1: T-005-01 T-005-03\nwave 2: T-005-02\n' > "$state/repos/demo/progress/T-005.md"
printf 'base: feat/T-005-export\n' > "$state/repos/demo/progress/T-005-01.md"
printf 'base: feat/T-005-export\n' > "$state/repos/demo/progress/T-005-03.md"
block T-005-01 review https://forge.test/mr/51
block T-005-03 draft null
block T-005-02 draft null
out=$(sh "$bin/solve-next.sh" T-005 --state "$state" 2>&1)
check 'a block of the same wave is worked past an open MR' 'Step 11 of 16: worktree and claim for T-005-03' "$out"
mkdir -p "$root/demo/T-005-03"
: > "$root/demo/T-005-03/.git"
block T-005-03 in_progress null
sed -i 's/^complexity: low$/complexity: low\nphase: implement/' "$state/repos/demo/tasks/T-005-03.md"
out=$(sh "$bin/solve-next.sh" T-005 --state "$state" 2>&1)
check 'a finished block is verified, reviewed and put up' '^## Step 11 of 16: verify, review and open the MR for T-005-03$' "$out"
check 'block-verify.sh runs first' '^  .*block-verify\.sh T-005-03' "$out"
check 'the reviewer and the auditor leave their reports' "Completion:.*\.harness/T-005-03/review\.md.*\.harness/T-005-03/arch\.md" "$out"
check 'block-mr.sh opens the block MR' '^  .*block-mr\.sh T-005-03' "$out"
check 'the block is review before its merge' "^  .*state-report\.sh --task T-005-03 --set-status review" "$out"
no 'no merge proof into a stack' 'block-merge\.sh' "$out"
block T-005-03 review https://forge.test/mr/53
out=$(sh "$bin/solve-next.sh" T-005 --state "$state" 2>&1)
check 'a finished wave is merged before the next' '^## Step 11 of 16: merge the block MRs of T-005$' "$out"
check 'the first block MR is merged by the script' '^  .*block-mr-merge\.sh T-005-01$' "$out"
check 'the second block MR is merged by the script' '^  .*block-mr-merge\.sh T-005-03$' "$out"
check 'a high-risk block merges too, recorded for the human' 'Completion:.*high risk too, recorded as ## Merged' "$out"
no 'no block waits for a confirm' '--confirmed' "$out"
check 'class C merges on its own and is rerun' 'Completion:.*auto-merge' "$out"
no 'the next wave is not cut yet' 'worktree and claim for T-005-02' "$out"
no 'the developer is not asked to merge a block' 'waits for the developer' "$out"

# --- step 14: the task MR for the human's review ---------------------------------------------------------
block T-005-01 done null
block T-005-02 done null
block T-005-03 done null
printf 'wave 1: T-005-01 T-005-03\nwave 2: T-005-02\n## Evidence\nok\n## Duplication\nnone\n## Review\nok\n' \
  > "$state/repos/demo/progress/T-005.md"
out=$(sh "$bin/solve-next.sh" T-005 --state "$state" 2>&1)
check 'step 14 is the human review of the task MR' "^## Step 14 of 16: the task MR of T-005 for the human's review\$" "$out"
check 'mr-open.sh opens the task MR' 'mr-open\.sh T-005' "$out"
check 'the human reviews and merges it' 'Completion:.*human.*review and merge' "$out"

exit $fail
