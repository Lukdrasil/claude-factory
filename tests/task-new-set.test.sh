#!/bin/sh
# task-new.sh rewrites the `id:` and `branch:` lines of a block draft whole: a trailing `# comment` on either
# line is dropped, so the written block carries the exact `id:` line task_of looks up. T-252-02: the defaults
# task-new.sh fills in add no key the dashboard alone read, and the status enum it names has no stalled. The
# request, priority and issue lines a block copies from its parent replace the draft's own, comment and all.
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
printf -- '---\nid: T-001\nrepo: demo\nstatus: draft\n---\n' > "$state/repos/demo/tasks/T-001-parent.md"
git -C "$state" add -A
git -C "$state" commit -q -m init

cat > "$tmp/block.md" <<'EOF'
---
id: T-001  # x
repo: demo
branch: feat/x  # y
status: draft
tier: green
archetype: bugfix
complexity: low
priority: P1  # z
created: 2026-09-24
---

# Goal
fix(demo): a block with commented id and branch

## Acceptance
`true`
EOF

rc=0
out=$(sh "$bin/task-new.sh" --repo demo --parent T-001 --state "$state" --file "$tmp/block.md" 2>&1) || rc=$?
check "task-new.sh --parent T-001 accepts the block draft" 0 "$rc"
bf="$state/repos/demo/tasks/T-001-01-fix-demo-a-block-with-commented.md"
check "the block carries the exact line 'id: T-001-01'" 'id: T-001-01' "$(grep '^id:' "$bf" 2>/dev/null)"
check "the block carries the exact line 'branch: feat/T-001-01-x'" 'branch: feat/T-001-01-x' \
  "$(grep '^branch:' "$bf" 2>/dev/null)"
check "the block carries the exact line 'priority: P2' of its parent" 'priority: P2' "$(grep '^priority:' "$bf" 2>/dev/null)"
check "the block frontmatter holds exactly the task keys" \
  'archetype attempt branch complexity created depends_on id issue mr_url owner plan_hash priority repo request status tier ' \
  "$(awk '/^---$/ { n++; next } n == 1 { sub(/:.*/, ""); print } n == 2 { exit }' "$bf" 2>/dev/null | sort | tr '\n' ' ')"

sed 's/^status: draft$/status: bogus/' "$tmp/block.md" > "$tmp/bogus.md"
rc=0
out=$(sh "$bin/task-new.sh" --repo demo --parent T-001 --state "$state" --file "$tmp/bogus.md" 2>&1) || rc=$?
check "task-new.sh refuses an unknown status" 1 "$rc"
check "the status enum task-new.sh names" \
  'task-new: status must be one of draft|triaged|ready|claimed|in_progress|tests_ready|review|blocked|failed|done|closed' "$out"

exit "$fail"
