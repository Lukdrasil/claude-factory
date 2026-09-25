#!/bin/sh
# queue-next.sh over a throwaway state clone: the parents a lead may be dispatched for, `<T-id> <key> <priority>
# <request>` in dispatch order. A parent is in the queue when it is `ready`, has a `request:`, `owner: null`, no
# open `<T-id>-lead` tab record, every depends_on done (an archived id counts as done), and, when it has open
# blocks, at least one block whose own depends_on are done ([XR] 4: a task whose blocks waited on another
# parent is dispatchable again once that parent is done). The effective priority is the best of its own and of
# every open task that depends on it, directly or through another; the id order breaks a tie. A lead record is
# open only while a live agent carries it: the herdr on PATH is the stub, and a lead that ended puts its parent
# back in the queue.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
. "$(dirname -- "$0")/herdr-stub.sh"
herdr_stub "$tmp/stub"
FACTORY_UI_HOME="$tmp/ui"
unset FACTORY_UNIT
export FACTORY_UI_HOME

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

task() { # <key> <id> <status> <priority|-> <request> <owner> <depends_on> [<dir under repos/<key>>]
  tk_dir="$st/repos/$1/${8:-tasks}"
  {
    printf -- '---\nid: %s\nrepo: %s\nstatus: %s\n' "$2" "$1" "$3"
    [ "$4" = - ] || printf 'priority: %s\n' "$4"
    printf 'request: %s\nowner: %s\ndepends_on: %s\n---\n\n# Goal\nfix(%s): %s\n' "$5" "$6" "$7" "$1" "$2"
  } > "$tk_dir/$2-$1.md"
}
lead() { # <parent> <key> <line>
  mkdir -p "$tmp/$2/.harness/$1"
  printf '%s\n' "$3" >> "$tmp/$2/.harness/$1/herdr-tabs"
}

# in the queue at P2
task demo T-101 ready P2 R-20260925-1 null '[]'
task demo T-101-01 ready P2 R-20260925-1 null '[]'
# no request, an owner, not ready
task demo T-102 ready P2 null null '[]'
task demo T-103 ready P2 R-20260925-1 'factory@host:abc' '[]'
task demo T-104 draft P2 R-20260925-1 null '[]'
# an open lead record keeps it out, a closed one does not
task demo T-105 ready P2 R-20260925-1 null '[]'
lead T-105 demo 'T-105-lead tab-5 pane-5 sess-5'
herdr_agent lead_t-105 working pane-5 sess-5
task demo T-106 ready P2 R-20260925-1 null '[]'
lead T-106 demo 'T-106-lead tab-6 pane-6'
lead T-106 demo 'T-106-lead tab-6 closed'
# depends_on: a draft keeps it out, an archived one counts as done, an id with no task file keeps it out
task demo T-107 ready P2 R-20260925-1 null '[T-104]'
task demo T-900 done P2 R-20260801-1 null '[]' archive/2026-08/tasks
task demo T-108 ready P2 R-20260925-1 null '[T-900]'
task demo T-113 ready P2 R-20260925-1 null '[T-999]'
# a P0 dependent lifts its P3 parent to the top, across repos
task demo T-109 ready P3 R-20260925-2 null '[]'
task ecs T-ECS-3 draft P0 R-20260925-2 null '[T-109]'
# P1 of its own
task demo T-110 ready P1 R-20260925-1 null '[]'
# lifted through a chain: T-116 (P1) waits on T-115, which waits on T-114
task demo T-114 ready P3 R-20260925-3 null '[]'
task demo T-115 draft P3 R-20260925-3 null '[T-114]'
task demo T-116 draft P1 R-20260925-3 null '[T-115]'
# a finished dependent lifts nothing
task demo T-117 ready P3 R-20260925-1 null '[]'
task demo T-118 done P0 R-20260925-1 null '[T-117]'
# [XR] 4: every open block of T-111 waits on T-ECS-5, which is not done; the block of T-112 waited on T-ECS-6,
# which is done now
task demo T-111 ready P2 R-20260925-1 null '[]'
task demo T-111-01 blocked P2 R-20260925-1 null '[T-ECS-5]'
task demo T-111-02 done P2 R-20260925-1 null '[]'
task ecs T-ECS-5 draft P2 R-20260925-1 null '[]'
task demo T-112 ready P2 R-20260925-1 null '[]'
task demo T-112-01 blocked P2 R-20260925-1 null '[T-ECS-6]'
task ecs T-ECS-6 done P2 R-20260925-1 null '[]'
# no priority line is P2
task demo T-119 ready - R-20260925-1 null '[]'
# alias ids after the legacy ones, by number
task ecs T-ECS-10 ready P2 R-20260925-4 null '[]'
task ecs T-ECS-2 ready P2 R-20260925-4 null '[]'
task ecs T-ECS-1 ready P2 R-20260925-4 null '[]'
git -C "$st" add -A
git -C "$st" commit -q -m fixture

want='T-109 demo P0 R-20260925-2
T-110 demo P1 R-20260925-1
T-114 demo P1 R-20260925-3
T-101 demo P2 R-20260925-1
T-106 demo P2 R-20260925-1
T-108 demo P2 R-20260925-1
T-112 demo P2 R-20260925-1
T-119 demo P2 R-20260925-1
T-ECS-1 ecs P2 R-20260925-4
T-ECS-2 ecs P2 R-20260925-4
T-ECS-10 ecs P2 R-20260925-4
T-117 demo P3 R-20260925-1'

out=$(sh "$bin/queue-next.sh" --state "$st" 2>"$tmp/err"); rc=$?
check 'exit 0' 0 "$rc"
[ ! -s "$tmp/err" ] || sed 's/^/  stderr: /' "$tmp/err"
check 'the dispatch order' "$want" "$out"

ids=$(printf '%s\n' "$out" | cut -d' ' -f1 | tr '\n' ' ')
for gone in T-101-01 T-102 T-103 T-104 T-105 T-107 T-113 T-111 T-900 T-ECS-3; do
  case " $ids" in *" $gone "*) check "$gone is not in the queue" no yes ;; *) check "$gone is not in the queue" no no ;; esac
done

check '--max 3 takes the first three' "$(printf '%s\n' "$want" | head -n 3)" \
  "$(sh "$bin/queue-next.sh" --max 3 --state "$st" 2>&1)"
check '--max 0 is refused' 1 "$(sh "$bin/queue-next.sh" --max 0 --state "$st" >/dev/null 2>&1; echo $?)"
check '--max x is refused' 1 "$(sh "$bin/queue-next.sh" --max x --state "$st" >/dev/null 2>&1; echo $?)"

# the cwd is the state clone when --state is not given
check 'the cwd is the state clone' "$want" "$(cd "$st" && sh "$bin/queue-next.sh" 2>&1)"

# once the lead record of T-105 is closed it is back in the queue
lead T-105 demo 'T-105-lead tab-5 closed'
case " $(sh "$bin/queue-next.sh" --state "$st" | cut -d' ' -f1 | tr '\n' ' ')" in
  *' T-105 '*) check 'a closed lead record puts T-105 back' yes yes ;;
  *) check 'a closed lead record puts T-105 back' yes no ;;
esac

# DECISIONS D20, [XR] 4: a lead ends with its parent left in_progress and the dependent blocks blocked; the
# parent is back in the queue, whatever its owner, once no lead record is open and one block is runnable again
task demo T-130 in_progress P2 R-20260925-5 'factory@host:old' '[]'
task demo T-130-01 ready P2 R-20260925-5 null '[]'
lead T-130 demo 'T-130-lead tab-30 pane-30'
herdr_agent lead_t-130 working pane-30
task demo T-131 in_progress P2 R-20260925-5 'factory@host:old' '[]'
task demo T-131-01 blocked P2 R-20260925-5 null '[T-ECS-6]'
task demo T-132 in_progress P2 R-20260925-5 'factory@host:old' '[]'
task demo T-132-01 blocked P2 R-20260925-5 null '[T-ECS-5]'
task demo T-132-02 done P2 R-20260925-5 null '[]'
task demo T-133 in_progress P2 null 'factory@host:old' '[]'
task demo T-133-01 ready P2 null null '[]'
task demo T-134 in_progress P1 R-20260925-5 'factory@host:old' '[]'
task demo T-134-01 blocked P1 R-20260925-5 null '[T-900]'
lead T-134 demo 'T-134-lead tab-34 pane-34'
lead T-134 demo 'T-134-lead tab-34 closed'
task demo T-135 in_progress P2 R-20260925-5 null '[]'
git -C "$st" add -A
git -C "$st" commit -q -m 'fixture in_progress'
out=$(sh "$bin/queue-next.sh" --state "$st" 2>&1)
has_line() { printf '%s\n' "$out" | grep -qx -- "$1" && echo yes || echo no; }
has_id() { printf '%s\n' "$out" | grep -q "^$1 " && echo yes || echo no; }
check 'in_progress with an open lead record is not in the queue' no "$(has_id T-130)"
check 'in_progress, no lead record, a block runnable again is in the queue' yes "$(has_line 'T-131 demo P2 R-20260925-5')"
check 'in_progress with only blocks waiting on an open dependency is not in the queue' no "$(has_id T-132)"
check 'in_progress without a request is not in the queue' no "$(has_id T-133)"
check 'in_progress with a closed lead record and an archived dependency is in the queue' yes \
  "$(has_line 'T-134 demo P1 R-20260925-5')"
check 'in_progress without a block is not in the queue' no "$(has_id T-135)"
check 'in_progress parents keep the priority order' 'T-110 T-114 T-134' \
  "$(printf '%s\n' "$out" | awk '$3 == "P1" { printf "%s%s", s, $1; s = " " }')"

# a lead that ended (a crash, a herdr restart, a Claude exit) leaves its record open with no live agent: after
# one herd-watch pass its parent is back in the queue
task demo T-136 in_progress P2 R-20260925-5 'factory@host:old' '[]'
task demo T-136-01 ready P2 R-20260925-5 null '[]'
lead T-136 demo 'T-136-lead t1 p1'
git -C "$st" add -A
git -C "$st" commit -q -m 'fixture ended lead'
sh "$bin/herd-watch.sh" T-136 --once --no-mr --state "$st" >/dev/null 2>&1
out=$(sh "$bin/queue-next.sh" --state "$st" 2>&1)
check 'a lead record no live agent carries puts its parent back' yes "$(has_line 'T-136 demo P2 R-20260925-5')"
check 'a lead record a live agent carries still keeps it out' no "$(has_id T-130)"

# an empty state prints nothing and exits 0
mkdir -p "$tmp/empty/state/repos"
git init -q -b main "$tmp/empty/state"
check 'an empty state prints nothing' '0 ' "$(sh "$bin/queue-next.sh" --state "$tmp/empty/state"; echo "$? ")"

exit "$fail"
