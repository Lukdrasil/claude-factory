#!/bin/sh
# herd-list.sh over a throwaway state clone: one `<request> <priority> <T-id> <repo> <status>` line per live
# parent that belongs to a request and is not finished, by priority and then by id. Blocks, parents without a
# request, done and closed parents and the archive are not herds.
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

task() { # <key> <id> <status> <priority|-> <request> [<dir under repos/<key>>]
  {
    printf -- '---\nid: %s\nrepo: %s\nstatus: %s\n' "$2" "$1" "$3"
    [ "$4" = - ] || printf 'priority: %s # the queue order\n' "$4"
    printf 'request: %s\nowner: null\n---\n\n# Goal\nfix(%s): %s\n' "$5" "$1" "$2"
  } > "$st/repos/$1/${6:-tasks}/$2-$1.md"
}

task demo T-201 in_progress P2 R-20260924-3
task demo T-201-01 in_progress P2 R-20260924-3
task demo T-202 ready P1 R-20260925-1
task demo T-203 done P0 R-20260925-1
task demo T-204 draft P2 null
task demo T-205 closed P1 R-20260925-1
task demo T-206 draft - R-20260925-2
task demo T-900 ready P0 R-20260801-1 archive/2026-08/tasks
task ecs T-ECS-10 review P3 R-20260925-2
task ecs T-ECS-2 blocked P3 R-20260925-2

want='R-20260925-1 P1 T-202 demo ready
R-20260924-3 P2 T-201 demo in_progress
R-20260925-2 P2 T-206 demo draft
R-20260925-2 P3 T-ECS-2 ecs blocked
R-20260925-2 P3 T-ECS-10 ecs review'

out=$(sh "$bin/herd-list.sh" --state "$st" 2>"$tmp/err"); rc=$?
check 'exit 0' 0 "$rc"
[ ! -s "$tmp/err" ] || sed 's/^/  stderr: /' "$tmp/err"
check 'one line per herd' "$want" "$out"
check 'the cwd is the state clone' "$want" "$(cd "$st" && sh "$bin/herd-list.sh" 2>&1)"
check 'an unknown argument is refused' 1 "$(sh "$bin/herd-list.sh" --bogus --state "$st" >/dev/null 2>&1; echo $?)"

mkdir -p "$tmp/empty/state/repos"
git init -q -b main "$tmp/empty/state"
check 'an empty state prints nothing' '0 ' "$(sh "$bin/herd-list.sh" --state "$tmp/empty/state"; echo "$? ")"

exit "$fail"
