#!/bin/sh
# state-archive.sh over a throwaway state clone: a finished parent (done or closed, every block terminal, no open
# task depending on it or on a block of it) moves with its blocks, progress and verdicts to
# repos/<key>/archive/<YYYY-MM>/{tasks,progress,verdicts}/ in one commit, YYYY-MM being the month of the last
# commit of the parent's task file; a done request moves to requests/archive/<YYYY-MM>/<R-id>/.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
export WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
has() { # <file> <text>
  if grep -qF -- "$2" "$1"; then printf yes; else printf no; fi
}
there() { [ -e "$st/$1" ] && echo yes || echo no; }

st="$tmp/state"
d="$st/repos/demo"
mkdir -p "$d/tasks" "$d/progress" "$d/verdicts" "$d/plans"
git init -q -b main "$st"
git -C "$st" config user.email harness@localhost
git -C "$st" config user.name harness

task() { # <id> <status> [depends_on] [plan slug]
  cat > "$d/tasks/$1-demo.md" <<EOF
---
id: $1
repo: demo
status: $2
archetype: bugfix
tier: green
complexity: low
depends_on: ${3:-[]}
owner: null
mr_url: null
---

# Goal
fix(demo): $1

## Context
${4:+The plan is repos/demo/plans/$4-plan-ready.md.}
EOF
}
commit_at() { # <date> <message>
  git -C "$st" add -A
  GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" git -C "$st" commit -q -m "$2"
}

# T-001: done, two terminal blocks, progress and verdicts, the verdict of its plan; committed in August
task T-001 done '[]' plan-a
task T-001-01 done
task T-001-02 closed '[T-001-01]'
printf '# T-001\n' > "$d/progress/T-001.md"
printf '# T-001-01\n' > "$d/progress/T-001-01.md"
printf 'verdict: aligned\n' > "$d/verdicts/T-001-01-first.md"
printf 'verdict: aligned\n' > "$d/verdicts/plan-a.md"
printf '# plan a\n' > "$d/plans/plan-a-plan-ready.md"
# T-002: done, but a block still in progress
task T-002 done
task T-002-01 in_progress
# T-003: done, but the open T-004 depends on a block of it
task T-003 closed
task T-003-01 done
task T-004 ready '[T-003-01]'
# T-005: still in review
task T-005 review '[]' plan-b
# T-006: closed, no blocks, shares plan-b with the open T-005
task T-006 closed '[]' plan-b
printf 'verdict: aligned\n' > "$d/verdicts/plan-b.md"
# T-007: done, no blocks
task T-007 done
# two requests: one done, one running
mkdir -p "$st/requests/R-20260901-1/issues" "$st/requests/R-20260902-1"
printf -- '---\ntitle: a\n---\n\nStatus: done\n\n# Map\n' > "$st/requests/R-20260901-1/map.md"
printf 'Type: task\nStatus: resolved\n' > "$st/requests/R-20260901-1/issues/01-one.md"
printf -- '---\ntitle: b\n---\n\nStatus: running\n' > "$st/requests/R-20260902-1/map.md"
printf 'shared notes\n' > "$st/notes.md"
commit_at '2026-08-15T10:00:00' fixture

# --- one parent with its blocks, progress and verdicts, in one commit ---------------------
printf 'another session, not committed\n' >> "$st/notes.md"
before=$(git -C "$st" rev-parse HEAD)
rc=0
sh "$bin/state-archive.sh" T-001 --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'T-001 archives, exit 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/out"
a=repos/demo/archive/2026-08
for f in tasks/T-001-demo.md tasks/T-001-01-demo.md tasks/T-001-02-demo.md progress/T-001.md \
         progress/T-001-01.md verdicts/T-001-01-first.md verdicts/plan-a.md; do
  check "$f is in $a" yes "$(there "$a/$f")"
  check "$f is no longer live" no "$(there "repos/demo/$f")"
done
check 'the plan itself stays' yes "$(there repos/demo/plans/plan-a-plan-ready.md)"
check 'one commit' "$before" "$(git -C "$st" rev-parse HEAD~1)"
check 'the commit is renames only' 7 "$(git -C "$st" show -M --name-status --format= HEAD | grep -c '^R')"
check 'the commit names the parent' yes "$(git -C "$st" log -1 --format=%s | grep -q T-001 && echo yes || echo no)"
check 'the foreign edit is still uncommitted' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"
check 'nothing else is left behind' '' "$(git -C "$st" status --porcelain -- repos)"
check 'the history follows the move' 2 \
  "$(git -C "$st" log --follow --format=%h -- "$a/tasks/T-001-demo.md" | wc -l | tr -d ' ')"
git -C "$st" checkout -q -- notes.md

rc=0
sh "$bin/state-archive.sh" T-001 --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'an archived parent again exits 0' 0 "$rc"
check 'and says it is archived' yes "$(has "$tmp/out" 'already archived')"
rc=0
sh "$bin/task-done.sh" T-001 --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'task-done on an archived parent exits 1' 1 "$rc"
check 'and names the archive' yes "$(has "$tmp/out" 'is archived')"
rc=0
(cd "$st" && sh "$bin/state-report.sh" --task T-001 --no-status) >"$tmp/out" 2>&1 || rc=$?
check 'state-report on an archived task exits 2' 2 "$rc"
check 'and names the archive' yes "$(has "$tmp/out" 'is archived')"

# --- what stays live ---------------------------------------------------------------------
before=$(git -C "$st" rev-parse HEAD)
rc=0; sh "$bin/state-archive.sh" T-002 --state "$st" >/dev/null 2>"$tmp/err" || rc=$?
check 'a non-terminal block exits 1' 1 "$rc"
check 'and names the block' yes "$(has "$tmp/err" T-002-01)"
check 'T-002 stays live' yes "$(there repos/demo/tasks/T-002-demo.md)"
rc=0; sh "$bin/state-archive.sh" T-003 --state "$st" >/dev/null 2>"$tmp/err" || rc=$?
check 'an open dependent exits 1' 1 "$rc"
check 'and names the dependent' yes "$(has "$tmp/err" T-004)"
check 'T-003 stays live' yes "$(there repos/demo/tasks/T-003-demo.md)"
rc=0; sh "$bin/state-archive.sh" T-005 --state "$st" >/dev/null 2>"$tmp/err" || rc=$?
check 'a parent in review exits 1' 1 "$rc"
check 'and names its status' yes "$(has "$tmp/err" review)"
rc=0; sh "$bin/state-archive.sh" T-001-01 --state "$st" >/dev/null 2>&1 || rc=$?
check 'a block id is refused' 1 "$rc"
rc=0; sh "$bin/state-archive.sh" T-099 --state "$st" >/dev/null 2>&1 || rc=$?
check 'an unknown id is refused' 1 "$rc"
check 'no refusal committed anything' "$before" "$(git -C "$st" rev-parse HEAD)"

# --- --dry-run prints the moves and moves nothing -----------------------------------------
rc=0
sh "$bin/state-archive.sh" T-006 --dry-run --state "$st" >"$tmp/out" 2>&1 || rc=$?
check '--dry-run exits 0' 0 "$rc"
check '--dry-run prints the move' yes "$(has "$tmp/out" 'repos/demo/tasks/T-006-demo.md')"
check '--dry-run leaves the file' yes "$(there repos/demo/tasks/T-006-demo.md)"
check '--dry-run makes no commit' "$before" "$(git -C "$st" rev-parse HEAD)"
rc=0
sh "$bin/state-archive.sh" --all --dry-run --state "$st" >"$tmp/out" 2>&1 || rc=$?
check '--all --dry-run exits 0' 0 "$rc"
check '--all --dry-run prints T-007' yes "$(has "$tmp/out" 'T-007-demo.md')"
check '--all --dry-run prints the done request' yes "$(has "$tmp/out" 'requests/R-20260901-1')"
check '--all --dry-run makes no commit' "$before" "$(git -C "$st" rev-parse HEAD)"
check '--all --dry-run moves nothing' '' "$(git -C "$st" status --porcelain)"

# --- a family with an uncommitted edit is left alone ---------------------------------------
printf 'edited\n' >> "$d/tasks/T-007-demo.md"
rc=0; sh "$bin/state-archive.sh" T-007 --state "$st" >/dev/null 2>"$tmp/err" || rc=$?
check 'an uncommitted edit in the family exits 1' 1 "$rc"
check 'and names the file' yes "$(has "$tmp/err" T-007-demo.md)"
git -C "$st" checkout -q -- repos/demo/tasks/T-007-demo.md

# --- the lock is taken ---------------------------------------------------------------------
rm -f "$tmp/held" "$tmp/release"
(. "$bin/lib-tasks.sh"; state_lock "$st" || exit 1; : > "$tmp/held"
 while [ ! -e "$tmp/release" ]; do sleep 0.2; done) &
holder=$!
n=0; while [ ! -e "$tmp/held" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
rc=0; STATE_LOCK_WAIT=1 sh "$bin/state-archive.sh" T-007 --state "$st" >/dev/null 2>&1 || rc=$?
check 'a held state lock exits 2' 2 "$rc"
check 'a held state lock moves nothing' yes "$(there repos/demo/tasks/T-007-demo.md)"
: > "$tmp/release"; wait "$holder"

# --- --all: every finished parent and the done request, nothing else -----------------------
# the request's own month is the one of its last commit
printf '\nnotes\n' >> "$st/requests/R-20260901-1/map.md"
commit_at '2026-09-03T10:00:00' 'request note'
rc=0
sh "$bin/state-archive.sh" --all --state "$st" >"$tmp/out" 2>&1 || rc=$?
check '--all exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/out"
check '--all moves T-006' yes "$(there repos/demo/archive/2026-08/tasks/T-006-demo.md)"
check '--all moves T-007' yes "$(there repos/demo/archive/2026-08/tasks/T-007-demo.md)"
check '--all keeps T-002' yes "$(there repos/demo/tasks/T-002-demo.md)"
check '--all keeps T-003' yes "$(there repos/demo/tasks/T-003-demo.md)"
check '--all keeps T-004' yes "$(there repos/demo/tasks/T-004-demo.md)"
check '--all keeps T-005' yes "$(there repos/demo/tasks/T-005-demo.md)"
check 'a verdict an open task still names stays' yes "$(there repos/demo/verdicts/plan-b.md)"
check '--all moves the done request' yes "$(there requests/archive/2026-09/R-20260901-1/map.md)"
check '--all moves the request tickets along' yes "$(there requests/archive/2026-09/R-20260901-1/issues/01-one.md)"
check 'the done request is no longer live' no "$(there requests/R-20260901-1)"
check '--all keeps the running request' yes "$(there requests/R-20260902-1/map.md)"
check '--all leaves a clean tree' '' "$(git -C "$st" status --porcelain)"

# --- once the dependent closes, T-003 goes too ---------------------------------------------
sed -i 's/^status: ready$/status: closed/' "$d/tasks/T-004-demo.md"
commit_at '2026-09-10T10:00:00' 'T-004 closed'
rc=0
sh "$bin/state-archive.sh" --all --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'the next --all exits 0' 0 "$rc"
check 'T-003 is archived once nothing open depends on it' yes "$(there repos/demo/archive/2026-08/tasks/T-003-demo.md)"
check 'its block goes with it' yes "$(there repos/demo/archive/2026-08/tasks/T-003-01-demo.md)"
check 'T-004 is archived in the month of its closing commit' yes "$(there repos/demo/archive/2026-09/tasks/T-004-demo.md)"

exit "$fail"
