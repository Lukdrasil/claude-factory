#!/bin/sh
# mr-open.sh and block-mr.sh --dry-run over a throwaway state clone (T-253): a finished step moves to `## Done`
# as `- [x] <step>`, and the MR description renders it without the box. A bullet with no box is unchanged.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=$tmp
export WORK_DIR

state="$tmp/state"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/progress"
printf 'demo: {url: https://github.com/o/demo.git, default_branch: main, path: %s}\n' "$tmp/clone" > "$state/repos.yml"

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}

task() { # <id> <branch>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
branch: $2
status: in_progress
archetype: feature
tier: yellow
complexity: medium
depends_on: []
owner: factory@host:sess-1
mr_url: null
---

# Goal
feat(demo): ship $1
EOF
}

progress() { # <id>
  cat > "$state/repos/demo/progress/$1.md" <<'EOF'
# the progress
base: feat/T-700-demo
**acceptance green**: done.

## Done
- [x] a
- b

## Remaining
- none

## Evidence
- [x] `sh tests/x.test.sh` -> exit 0

## Follow-ups
- [ ] c
EOF
}

worktree() { # <id>
  git init -q -b main "$tmp/demo/$1"
  git -C "$tmp/demo/$1" remote add origin https://github.com/o/demo.git
}

task T-700 feat/T-700-demo
task T-700-01 block/T-700-01
progress T-700
progress T-700-01
worktree T-700
worktree T-700-01

out=$(sh "$bin/mr-open.sh" T-700 --dry-run --state "$state" --worktree "$tmp/demo/T-700" 2>&1); rc=$?
check 'mr-open.sh --dry-run exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'mr-open.sh renders - [x] a in ## Done as a' '**What changed** - a; b' \
  "$(printf '%s\n' "$out" | grep -F '**What changed**')"
check 'mr-open.sh drops the box from an Evidence bullet' '**How to verify** - `sh tests/x.test.sh` -> exit 0' \
  "$(printf '%s\n' "$out" | grep -F '**How to verify**')"
check 'mr-open.sh drops an open box from a Follow-ups bullet' '- c' \
  "$(printf '%s\n' "$out" | sed -n '/^\*\*Follow-ups\*\*$/{n;p;}')"

out=$(sh "$bin/block-mr.sh" T-700-01 --dry-run --state "$state" --worktree "$tmp/demo/T-700-01" 2>&1); rc=$?
check 'block-mr.sh --dry-run exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'block-mr.sh renders - [x] a in ## Done as a' '**What changed** - a; b' \
  "$(printf '%s\n' "$out" | grep -F '**What changed**')"
check 'block-mr.sh drops the box from an Evidence bullet' '**How to verify** - `sh tests/x.test.sh` -> exit 0' \
  "$(printf '%s\n' "$out" | grep -F '**How to verify**')"

exit $fail
