#!/bin/sh
# task-new.sh rewrites the `id:` and `branch:` lines of a block draft whole: a trailing `# comment` on either
# line is dropped, so the written block carries the exact `id:` line task_of looks up.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$root/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
DASHBOARD_URL=''
export WORK_DIR DASHBOARD_URL

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

exit "$fail"
