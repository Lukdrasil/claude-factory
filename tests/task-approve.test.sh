#!/bin/sh
# task-approve.sh over a throwaway state clone (T-228 D2): the two approval commits reach the state root with
# the ADR-0012 retry of task-done.sh, a clone with no origin stays local and exits 0, and a root that refuses
# the push is exit 2 with both commits kept in the clone.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/state"
mkdir -p "$state/repos/demo/tasks"
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}

task() { # <id>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: draft
archetype: bugfix
tier: yellow
complexity: low
owner: null
mr_url: null
---

# Goal
fix(demo): $1
EOF
  git -C "$state" add -A
  git -C "$state" commit -q -m "fixture $1"
}

field() { # <id> <key>
  sed -n "s/^$2:[[:space:]]*//p" "$state/repos/demo/tasks/$1.md" | head -n1
}

# --- no origin: the clone stays local, exit 0 --------------------------------
task T-001
out=$(sh "$bin/task-approve.sh" T-001 --state "$state" 2>&1); rc=$?
check 'no origin exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'no origin still approves' ready "$(field T-001 status)"
check 'no origin writes plan_hash' "$(git -C "$state" rev-parse HEAD~1)" "$(field T-001 plan_hash)"

# --- T-252-02: stalled is no status any more, so it is not approved ---------
task T-009
sed -i 's/^status: draft$/status: stalled/' "$state/repos/demo/tasks/T-009.md"
git -C "$state" commit -qam 'fixture T-009 stalled'
out=$(sh "$bin/task-approve.sh" T-009 --state "$state" 2>&1); rc=$?
check 'a stalled task is refused' 1 "$rc"
check 'a refused stalled task keeps its status' stalled "$(field T-009 status)"

# --- with an origin both commits reach the state root -----------------------
git init -q --bare -b main "$tmp/origin.git"
git -C "$state" remote add origin "$tmp/origin.git"
git -C "$state" push -q -u origin main >/dev/null 2>&1
task T-002
git -C "$state" push -q >/dev/null 2>&1
out=$(sh "$bin/task-approve.sh" T-002 --state "$state" 2>&1); rc=$?
check 'with an origin exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the approval commits are pushed' "$(git -C "$state" rev-parse HEAD)" \
  "$(git -C "$tmp/origin.git" rev-parse main 2>/dev/null)"
check 'the pushed tip is the plan_hash commit' 'chore(T-002): plan_hash of the approved body' \
  "$(git -C "$tmp/origin.git" log -1 --format=%s main 2>/dev/null)"

# --- the state root moved on: the push rebases onto it -----------------------
git clone -q -b main "$tmp/origin.git" "$tmp/other"
git -C "$tmp/other" -c user.email=o@localhost -c user.name=other commit -q --allow-empty -m 'another session'
git -C "$tmp/other" push -q >/dev/null 2>&1
task T-003
out=$(sh "$bin/task-approve.sh" T-003 --state "$state" 2>&1); rc=$?
check 'behind the root exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'behind the root, the approval is pushed on top' "$(git -C "$state" rev-parse HEAD)" \
  "$(git -C "$tmp/origin.git" rev-parse main 2>/dev/null)"
if git -C "$tmp/origin.git" log --format=%s main 2>/dev/null | grep -qx 'another session'; then
  printf 'PASS the other session commit survives\n'
else printf 'FAIL the other session commit survives\n'; fail=1; fi

# --- a root that refuses the push: exit 2, both commits kept locally --------
git -C "$state" remote set-url origin "$tmp/no-such-origin.git"
task T-004
before=$(git -C "$state" rev-parse HEAD)
out=$(sh "$bin/task-approve.sh" T-004 --state "$state" 2>&1); rc=$?
check 'a refused push exits 2' 2 "$rc"
check 'a refused push keeps the approval' ready "$(field T-004 status)"
check 'a refused push keeps both commits' "$before" "$(git -C "$state" rev-parse HEAD~2)"
if printf '%s\n' "$out" | grep -q 'task-approve:'; then printf 'PASS the refusal is reported on stderr\n'
else printf 'FAIL the refusal is reported on stderr: %s\n' "$out"; fail=1; fi

exit $fail
