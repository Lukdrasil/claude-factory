#!/bin/sh
# task-priority.sh over a throwaway state clone: `P0` to `P3` only, set on a parent and cascaded to every block of
# it in one commit under the state lock; a block, an archived task and a bad value are refused with nothing
# written, and the same priority again commits nothing.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
export WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s:\n  expected [%s]\n  got      [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

st="$tmp/state"
mkdir -p "$st/repos/demo/tasks" "$st/repos/ecs/tasks" "$st/repos/demo/archive/2026-08/tasks"
git init -q -b main "$st"
git -C "$st" config user.email harness@localhost
git -C "$st" config user.name harness

task() { # <key> <id> <priority|-> [<dir under repos/<key>>]
  {
    printf -- '---\nid: %s\nrepo: %s\nstatus: ready\n' "$2" "$1"
    [ "$3" = - ] || printf 'priority: %s\n' "$3"
    printf 'owner: null\n---\n\n# Goal\nfix(%s): %s\n' "$1" "$2"
  } > "$st/repos/$1/${4:-tasks}/$2-$1.md"
}
prio() { # <key> <id> [<dir>]
  sed -n 's/^priority:[[:space:]]*//p' "$st/repos/$1/${3:-tasks}/$2-$1.md"
}
head_of() { git -C "$st" rev-parse HEAD; }

task demo T-001 P2
task demo T-001-01 P2
task demo T-001-02 -
task demo T-0010 P2
task demo T-002 P3
task ecs T-ECS-1 P2
task ecs T-ECS-1-01 P2
task ecs T-ECS-10 P2
task demo T-900 P2 archive/2026-08/tasks
git -C "$st" add -A
git -C "$st" commit -q -m fixture

# --- the enum ------------------------------------------------------------------
before=$(head_of)
for bad in P4 p1 1 high ''; do
  rc=0; sh "$bin/task-priority.sh" T-001 "$bad" --state "$st" >/dev/null 2>"$tmp/err" || rc=$?
  check "'$bad' is refused" 1 "$rc"
done
check 'a refused value commits nothing' "$before" "$(head_of)"
check 'a refused value writes nothing' P2 "$(prio demo T-001)"
check 'a refusal names the enum' yes "$(grep -q 'P0' "$tmp/err" && echo yes || echo no)"

# --- a block, an archived task, an unknown id ----------------------------------
check 'a block is refused' 1 "$(sh "$bin/task-priority.sh" T-001-01 P0 --state "$st" >/dev/null 2>&1; echo $?)"
check 'an archived task is refused' 1 "$(sh "$bin/task-priority.sh" T-900 P0 --state "$st" >/dev/null 2>&1; echo $?)"
check 'an unknown id is refused' 1 "$(sh "$bin/task-priority.sh" T-777 P0 --state "$st" >/dev/null 2>&1; echo $?)"
check 'nothing was committed' "$before" "$(head_of)"
check 'the block kept its priority' P2 "$(prio demo T-001-01)"

# --- a parent and its blocks in one commit ---------------------------------------
rc=0; sh "$bin/task-priority.sh" T-001 P0 --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'the parent is set, exit 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/out"
check 'one commit' "$before" "$(git -C "$st" rev-parse HEAD~1)"
check 'the commit message' 'chore(T-001): priority P0' "$(git -C "$st" log -1 --format=%s)"
check 'the parent is P0' P0 "$(prio demo T-001)"
check 'the first block is P0' P0 "$(prio demo T-001-01)"
check 'a block without the line gets it' P0 "$(prio demo T-001-02)"
check 'T-0010 is no block of T-001' P2 "$(prio demo T-0010)"
check 'another parent is untouched' P3 "$(prio demo T-002)"
check 'the commit holds the parent and both blocks' \
  'repos/demo/tasks/T-001-01-demo.md repos/demo/tasks/T-001-02-demo.md repos/demo/tasks/T-001-demo.md' \
  "$(git -C "$st" show --name-only --format= HEAD | sort | tr '\n' ' ' | sed 's/ $//')"
check 'the working tree is clean' '' "$(git -C "$st" status --porcelain)"

# --- an alias parent: T-ECS-10 is no block of T-ECS-1 ----------------------------
sh "$bin/task-priority.sh" T-ECS-1 P1 --state "$st" >/dev/null 2>&1
check 'the alias parent is P1' P1 "$(prio ecs T-ECS-1)"
check 'its block is P1' P1 "$(prio ecs T-ECS-1-01)"
check 'T-ECS-10 is untouched' P2 "$(prio ecs T-ECS-10)"

# --- the same priority again commits nothing -------------------------------------
before=$(head_of)
check 'the same priority again exits 0' 0 "$(sh "$bin/task-priority.sh" T-001 P0 --state "$st" >/dev/null 2>&1; echo $?)"
check 'the same priority again commits nothing' "$before" "$(head_of)"

# --- under the state lock ----------------------------------------------------------
rm -f "$tmp/held" "$tmp/release"
(. "$bin/lib-tasks.sh"; state_lock "$st" || exit 1; : > "$tmp/held"
 while [ ! -e "$tmp/release" ]; do sleep 1; done) &
holder=$!
n=0
while [ ! -e "$tmp/held" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
before=$(head_of)
rc=0; STATE_LOCK_WAIT=1 sh "$bin/task-priority.sh" T-002 P1 --state "$st" >/dev/null 2>&1 || rc=$?
check 'a held lock that is not freed in time exits 2' 2 "$rc"
check 'a held lock: nothing written' P3 "$(prio demo T-002)"
STATE_LOCK_WAIT=20 sh "$bin/task-priority.sh" T-002 P1 --state "$st" >"$tmp/out" 2>&1 &
waiter=$!
sleep 2
check 'nothing is committed while the lock is held' "$before" "$(head_of)"
: > "$tmp/release"
wait "$holder"
rc=0; wait "$waiter" || rc=$?
check 'it exits 0 once the lock is free' 0 "$rc"
check 'it commits once the lock is free' P1 "$(git -C "$st" show HEAD:repos/demo/tasks/T-002-demo.md | sed -n 's/^priority: //p')"

exit "$fail"
