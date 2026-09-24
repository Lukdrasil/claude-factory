#!/bin/sh
# Task ids past T-999 and block numbers past 99 (T-250): a task id is T- and three or more digits, a block id a
# parent id plus - and two or more digits. The allocator, the lib-tasks.sh predicates and sort_ids, the
# architect gate, spawn-plan, worktree-add and factory-list all take the wider ids, and no fixed-width id
# pattern is left under bin/.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$root/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
export WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

nl='
'

new_state() { # <dir> <key> [clone path]
  mkdir -p "$1/repos/$2/tasks" "$1/repos/$2/progress"
  git init -q -b main "$1"
  git -C "$1" config user.email harness@localhost
  git -C "$1" config user.name harness
  printf '%s: {url: %s, default_branch: main, path: %s}\n' "$2" "$1-origin.git" "${3:-$1/../$2}" > "$1/repos.yml"
  git -C "$1" add -A
  git -C "$1" commit -q -m init
}

task_file() { # <state> <key> <id> <branch or null> [depends_on] [body]
  cat > "$1/repos/$2/tasks/$3-demo.md" <<EOF
---
id: $3
repo: $2
branch: $4
status: ready
tier: yellow
archetype: bugfix
complexity: medium
depends_on: ${5:-[]}
owner: factory@host:sess-1
mr_url: null
---

# Goal
fix($2): $3

${6:-}
EOF
}

# --- the predicates -----------------------------------------------------------
pred() { # <predicate> <args…> -> yes | no
  if (. "$bin/lib-tasks.sh"; "$@") >/dev/null 2>&1; then printf yes; else printf no; fi
}

for id in T-007 T-246 T-999 T-1000 T-1000-01 T-246-100 T-246-00; do
  check "is_task_id accepts $id" yes "$(pred is_task_id "$id")"
done
for id in T-12 T-1000-1 T-12-01 T- T-abc T-1000- T-1000-01-02 T-1000-01x t-1000 x '' 'T-1000 '; do
  check "is_task_id refuses '$id'" no "$(pred is_task_id "$id")"
done

for id in T-007 T-999 T-1000 T-12345; do
  check "is_parent_id accepts $id" yes "$(pred is_parent_id "$id")"
done
for id in T-12 T-1000-01 T-246-100 T-abc T-1000- x ''; do
  check "is_parent_id refuses '$id'" no "$(pred is_parent_id "$id")"
done

for id in T-246-00 T-246-99 T-246-100 T-1000-01 T-1000-100; do
  check "is_block_id accepts $id" yes "$(pred is_block_id "$id")"
done
for id in T-1000 T-246 T-1000-1 T-12-01 T-1000-01-02 T-1000-01x T-1000- x ''; do
  check "is_block_id refuses '$id'" no "$(pred is_block_id "$id")"
done

check 'is_block_of T-1000 T-1000-01' yes "$(pred is_block_of T-1000 T-1000-01)"
check 'is_block_of T-246 T-246-100' yes "$(pred is_block_of T-246 T-246-100)"
check 'is_block_of T-246 T-246-00' yes "$(pred is_block_of T-246 T-246-00)"
check 'is_block_of T-100 T-1000-01, a prefix is not a parent' no "$(pred is_block_of T-100 T-1000-01)"
check 'is_block_of T-246 T-2460-01' no "$(pred is_block_of T-246 T-2460-01)"
check 'is_block_of T-1000 T-1000, a parent is not its own block' no "$(pred is_block_of T-1000 T-1000)"
check 'is_block_of T-1000 T-1000-1' no "$(pred is_block_of T-1000 T-1000-1)"
check 'is_block_of T-1000 T-1000-01-02' no "$(pred is_block_of T-1000 T-1000-01-02)"
check 'is_block_of T-1000 T-1001-01' no "$(pred is_block_of T-1000 T-1001-01)"

# --- sort_ids -----------------------------------------------------------------
sorted=$(printf '%s\n' T-1000 T-246-100 T-999 T-247 T-246-99 T-2460 T-246 T-007 T-246-00 \
  | (. "$bin/lib-tasks.sh"; sort_ids) 2>/dev/null | tr '\n' ' ')
check 'sort_ids orders numerically, a parent before its blocks' \
  'T-007 T-246 T-246-00 T-246-99 T-246-100 T-247 T-999 T-1000 T-2460 ' "$sorted"
sorted=$(printf '%s\n' 'T-1000 b' 'T-999 z' 'T-1000 a' | (. "$bin/lib-tasks.sh"; sort_ids) 2>/dev/null | tr '\n' '|')
check 'sort_ids keys on the first word and breaks a tie on the whole line' 'T-999 z|T-1000 a|T-1000 b|' "$sorted"
sorted=$(printf '%s\n' T-246 T-246-00 T-246 | (. "$bin/lib-tasks.sh"; sort_ids) 2>/dev/null | tr '\n' ' ')
check 'sort_ids keeps duplicate lines, a caller wanting unique ones runs sort -u first' 'T-246 T-246 T-246-00 ' "$sorted"

# --- the allocator ----------------------------------------------------------------
st="$tmp/alloc/state"
new_state "$st" demo
task_file "$st" demo T-999 fix/T-999-demo
git -C "$st" add -A && git -C "$st" commit -q -m T-999

draft() { # <file> <goal> <branch>
  cat > "$1" <<EOF
---
id: T-000
repo: demo
branch: $3
status: draft
tier: yellow
archetype: bugfix
complexity: medium
---

# Goal
fix(demo): $2

## Acceptance
\`true\`
EOF
}

new_id() { # <task-new.sh args…> -> the allocated id, or the refusal
  out=$(sh "$bin/task-new.sh" --repo demo --state "$st" "$@" 2>&1) \
    && printf '%s' "$out" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' || printf '%s' "$out"
}

draft "$tmp/d1.md" 'first past the three digits' fix/new-thing
check 'a state holding T-999 allocates T-1000' T-1000 "$(new_id --file "$tmp/d1.md")"
draft "$tmp/d2.md" 'second past the three digits' fix/T-1000-carried-over
check 'the next one is T-1001, not a second T-1000' T-1001 "$(new_id --file "$tmp/d2.md")"
check 'exactly one task file holds id: T-1000' 1 "$(grep -lx 'id: T-1000' "$st"/repos/demo/tasks/*.md | wc -l | tr -d ' ')"
check 'the branch loses its old four-digit id, not only three digits of it' fix/T-1001-carried-over \
  "$(sed -n 's/^branch:[[:space:]]*//p' "$st"/repos/demo/tasks/T-1001-*.md 2>/dev/null | head -n1)"

draft "$tmp/d3.md" 'a block of a four-digit parent' block/T-000
check 'task-new.sh --parent T-1000 allocates T-1000-01' T-1000-01 "$(new_id --parent T-1000 --file "$tmp/d3.md")"
draft "$tmp/d4.md" 'the next block of it' block/T-000
check 'the next block of T-1000 is T-1000-02' T-1000-02 "$(new_id --parent T-1000 --file "$tmp/d4.md")"

task_file "$st" demo T-500 fix/T-500-demo
for n in $(seq -w 1 99); do printf -- '---\nid: T-500-%s\n---\n' "$n" > "$st/repos/demo/tasks/T-500-$n-b.md"; done
git -C "$st" add -A && git -C "$st" commit -q -m 'T-500 and 99 blocks'
draft "$tmp/d5.md" 'the hundredth block' block/T-000
check 'a parent with 99 blocks allocates -100' T-500-100 "$(new_id --parent T-500 --file "$tmp/d5.md")"
draft "$tmp/d6.md" 'the hundred and first block' block/T-000
check 'and then -101' T-500-101 "$(new_id --parent T-500 --file "$tmp/d6.md")"
draft "$tmp/d7.md" 'a top-level task after the blocks' fix/after
check 'three-digit blocks do not move the parent counter' T-1002 "$(new_id --file "$tmp/d7.md")"

# --- architect-gate reads the verdict of the whole id -----------------------------
gs="$tmp/gate/state"
mkdir -p "$gs/repos/demo/tasks" "$gs/repos/demo/verdicts" "$tmp/gate/demo/docs/architecture"
printf 'demo: {url: x, default_branch: main, path: "%s"}\n' "$tmp/gate/demo" > "$gs/repos.yml"
quick() { printf -- '---\nscope: quick\nverdict: aligned\n---\n' > "$gs/repos/demo/verdicts/$1.md"; }
gate() { # <task file name> -> the gate's exit code
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s","content":"from repos/demo/plans/unreviewed-plan-ready.md"}}' \
    "$gs" "$gs/repos/demo/tasks/$1" | sh "$bin/architect-gate.sh" >/dev/null 2>&1
  printf '%s' $?
}

quick T-250
check 'a Write of T-250-slug.md passes on verdicts/T-250.md' 0 "$(gate T-250-slug.md)"
rm -f "$gs"/repos/demo/verdicts/*
quick T-1000
check 'a Write of T-1000-slug.md passes on verdicts/T-1000.md' 0 "$(gate T-1000-slug.md)"
rm -f "$gs"/repos/demo/verdicts/*
quick T-100
check 'a Write of T-1000-slug.md does not pass on verdicts/T-100.md' 2 "$(gate T-1000-slug.md)"
rm -f "$gs"/repos/demo/verdicts/*
quick T-1000-01
check 'a Write of T-1000-01-slug.md passes on verdicts/T-1000-01.md' 0 "$(gate T-1000-01-slug.md)"
rm -f "$gs"/repos/demo/verdicts/*
quick T-1000
check 'a Write of T-1000-01-slug.md does not pass on its parent verdict' 2 "$(gate T-1000-01-slug.md)"
rm -f "$gs"/repos/demo/verdicts/*
quick T-246-100
check 'a Write of T-246-100-slug.md passes on verdicts/T-246-100.md' 0 "$(gate T-246-100-slug.md)"

# --- spawn-plan -----------------------------------------------------------------
ss="$tmp/spawn/state"
new_state "$ss" demo
design() { printf 'Design (approved in the grill):\n### `%s` (existing)\nmain\n  a member.\n\n## Acceptance\n`true`\n' "$1"; }
task_file "$ss" demo T-1000 fix/T-1000-demo
task_file "$ss" demo T-1000-01 null '[]' "$(design src/a.sh)"
task_file "$ss" demo T-246 fix/T-246-demo
task_file "$ss" demo T-246-99 null '[]' "$(design src/b.sh)"
task_file "$ss" demo T-246-100 null '[]' "$(design src/c.sh)"
git -C "$ss" add -A && git -C "$ss" commit -q -m fixture
plan=$(sh "$bin/spawn-plan.sh" T-1000 --state "$ss" 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
check 'spawn-plan lists T-1000-01 in its wave' 'T-1000-01 ' "$plan"
plan=$(sh "$bin/spawn-plan.sh" T-246 --state "$ss" 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ')
check 'spawn-plan lists T-246-99 and T-246-100, not T-246-10' 'T-246-100 T-246-99 ' "$plan"

# --- worktree-add stacks on the whole dependency id -------------------------------
w="$tmp/wt"
WORK_DIR=$w
export WORK_DIR
clone="$w/clone"
new_state "$w/state" demo "$clone"
git init -q --bare "$w/state-origin.git"
git -C "$w/state" remote add origin "$w/state-origin.git"
git -C "$w/state" push -q -u origin main >/dev/null 2>&1
git init -q -b main "$clone"
git -C "$clone" config user.email harness@localhost
git -C "$clone" config user.name harness
git -C "$clone" commit -q --allow-empty -m init
git -C "$clone" branch -q feat/T-1000-demo main
git -C "$clone" branch -q feat/T-246-demo main
task_file "$w/state" demo T-1000 feat/T-1000-demo
task_file "$w/state" demo T-1000-01 null
task_file "$w/state" demo T-1000-02 null '[T-1000-01]'
task_file "$w/state" demo T-246 feat/T-246-demo
task_file "$w/state" demo T-246-99 null
task_file "$w/state" demo T-246-100 null
task_file "$w/state" demo T-246-101 null '[T-246-100, T-246-99]'
git -C "$w/state" add -A && git -C "$w/state" commit -q -m fixture && git -C "$w/state" push -q >/dev/null 2>&1

wt() { # <id> -> worktree-add's stdout lines joined by |
  (cd "$clone" && sh "$bin/worktree-add.sh" "$1" --state "$w/state" 2>/dev/null) | tr '\n' '|'
}
wt T-1000-01 >/dev/null
check 'worktree-add stacks a T-1000 block on its T-1000 dependency' \
  "path: $w/demo/T-1000-02|branch: block/T-1000-02|base: block/T-1000-01|" "$(wt T-1000-02)"
check 'a hundredth block is a block, cut from its parent' \
  "path: $w/demo/T-246-100|branch: block/T-246-100|base: feat/T-246-demo|" "$(wt T-246-100)"
wt T-246-99 >/dev/null
check 'the stack base is the highest dependency by number, T-246-100 over T-246-99' \
  "path: $w/demo/T-246-101|branch: block/T-246-101|base: block/T-246-100|" "$(wt T-246-101)"
WORK_DIR=''

# --- factory-list ---------------------------------------------------------------
ls_root="$tmp/list"
mkdir -p "$ls_root/state/repos/demo/tasks"
for id in T-1000 T-246-100 T-999 T-246 T-246-99 T-246-00; do task_file "$ls_root/state" demo "$id" null; done
listed=$(sh "$bin/factory-list.sh" --root "$ls_root" 2>&1 | awk '{print $1}' | tr '\n' ' ')
check 'factory-list orders T-246 before its blocks, T-246-99 before T-246-100, T-999 before T-1000' \
  'T-246 T-246-00 T-246-99 T-246-100 T-999 T-1000 ' "$listed"

# --- solve-next and herd-watch order blocks missing from the wave plan by id -------------
sn="$tmp/sn/state"
mkdir -p "$sn/repos/demo/tasks" "$sn/repos/demo/plans" "$sn/repos/demo/progress" "$tmp/sn/demo/T-246"
: > "$tmp/sn/demo/T-246/.git"
printf -- '---\ntask: T-246\n---\n' > "$sn/repos/demo/plans/x-plan-ready.md"
printf 'wave 1:\n' > "$sn/repos/demo/progress/T-246.md"
task_file "$sn" demo T-246 fix/T-246-demo
(. "$bin/lib-tasks.sh"; setf "$sn/repos/demo/tasks/T-246-demo.md" status in_progress)
task_file "$sn" demo T-246-99 null
task_file "$sn" demo T-246-100 null
check 'solve-next reaches T-246-99 before T-246-100 when neither is in the wave plan' \
  '## Step 11 of 16: worktree and claim for T-246-99' "$(sh "$bin/solve-next.sh" T-246 --state "$sn" 2>&1 | head -n1)"
watched=$(sh "$bin/herd-watch.sh" T-246 --once --no-mr --state "$sn" 2>&1 | awk '$2 == "status" { print $1 }' | tr '\n' ' ')
check 'herd-watch lists T-246-99 before T-246-100' 'T-246 T-246-99 T-246-100 ' "$watched"

# --- no fixed-width id pattern left under bin/ ---------------------------------------
# An unquantified run of two or more [0-9] classes, or an exact {2} / {3} count, is a fixed-width id pattern.
# lib-tasks.sh's predicate bodies are the one place allowed to spell the shape out. forge.sh, curate-apply.sh and
# mr-watch.sh match numbers that are no task id with [0-9][0-9]*, which the allow-list strips before the grep.
fixed=$(for f in "$bin"/*.sh; do
  n=${f##*/}
  case "$n" in
    lib-tasks.sh)
      awk '/^(is_task_id|is_parent_id|is_block_id|is_block_of)[[:space:]]*\(\)/ { skip = 1; one = /}[[:space:]]*$/ }
        skip { print ""; if (one || /^}/) skip = 0; next } { print }' "$f" ;;
    forge.sh|curate-apply.sh|mr-watch.sh) sed 's/\[0-9\]\[0-9\]\*//g' "$f" ;;
    *) cat "$f" ;;
  esac | grep -nE '(\[0-9\]){2,}([^+[]|$)|\{[23]\}' | sed "s|^|$n:|"
done)
check 'no fixed-width id pattern under bin/' '' "$fixed"

exit $fail
