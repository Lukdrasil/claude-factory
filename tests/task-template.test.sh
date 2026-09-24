#!/bin/sh
# The skeletons task-template.sh prints go through task-new.sh as they are once the placeholders are filled
# (T-249 F2, F5): a `task` draft is born `draft`, a `block` gets the exact `id:` line task_of looks up and a
# `branch:` line with no comment. Every state-report.sh call in the prose passes `--task` (F4), since the
# standalone layout has no `# Task <id>` CLAUDE.md to fall back on. T-252-02: both skeletons carry exactly the
# task keys, none the dashboard alone read.
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

state="$tmp/state"
mkdir -p "$state/repos/demo/tasks" "$tmp/demo"
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
printf 'demo: {url: %s, default_branch: main, path: %s}\n' "$tmp/origin.git" "$tmp/demo" > "$state/repos.yml"
git -C "$state" add -A
git -C "$state" commit -q -m init

fill() { # <kind> <goal> > filled markdown
  sh "$bin/task-template.sh" "$1" | sed '
    s/<key>/demo/; s/<repo-key>/demo/
    s/<green|yellow|red>/green/; s/<feature|bugfix|refactor|research|ops>/bugfix/; s/<low|medium|high>/low/
    s/<YYYY-MM-DD>/2026-09-24/' \
  | awk -v goal="$2" '/^# Goal$/ { print; print goal; skip = 1; next } skip && /^$/ { skip = 0 } !skip'
}

# --- 2a: a task draft is accepted and stays draft ------------------------------
fill task 'fix(demo): a task draft' > "$tmp/task.md"
rc=0
out=$(sh "$bin/task-new.sh" --repo demo --state "$state" --file "$tmp/task.md" 2>&1) || rc=$?
check "2a task-new.sh accepts the filled task template" 0 "$rc"
check "2a the new task is T-001" '{"id":"T-001","file":"repos/demo/tasks/T-001-fix-demo-a-task-draft.md"}' "$out"
check "2a the task is written as draft" 'status: draft' \
  "$(grep '^status:' "$state/repos/demo/tasks/T-001-fix-demo-a-task-draft.md" 2>/dev/null)"

# --- 2b: a block gets an exact id line and a branch with no comment ---------------
fill block 'fix(demo): a block' > "$tmp/block.md"
rc=0
out=$(sh "$bin/task-new.sh" --repo demo --parent T-001 --state "$state" --file "$tmp/block.md" 2>&1) || rc=$?
check "2b task-new.sh --parent T-001 accepts the filled block template" 0 "$rc"
bf="$state/repos/demo/tasks/T-001-01-fix-demo-a-block.md"
check "2b the block carries the exact line 'id: T-001-01'" 'id: T-001-01' "$(grep -x 'id: T-001-01' "$bf" 2>/dev/null)"
check "2b task_of T-001-01 finds the block" "$bf" "$(. "$bin/lib-tasks.sh"; task_of T-001-01)"
check "2b the branch line holds no '#'" 'branch: feat/T-001-01-<slug>' "$(grep '^branch:' "$bf" 2>/dev/null)"

# --- 2d: both skeletons carry exactly the task keys ---------------------------------
for kind in task block; do
  check "2d the $kind skeleton holds exactly the task keys" \
    'archetype attempt branch complexity created depends_on id mr_url owner plan_hash repo status tier ' \
    "$(sh "$bin/task-template.sh" "$kind" | awk '/^---$/ { n++; next } n == 1 { sub(/:.*/, ""); print } n == 2 { exit }' | sort | tr '\n' ' ')"
done

# --- 2c: every state-report.sh call in the prose names its task --------------------
check "2c every state-report.sh call passes --task" '' \
  "$(cd "$root" && grep -rn 'state-report\.sh --' skills agents prompts | grep -v -- '--task')"

exit "$fail"
