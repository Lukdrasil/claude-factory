#!/bin/sh
# task-approve.sh over a throwaway state clone: every id it is given flips to ready under one lock in one commit,
# plan_hash pins the commit that holds the approved body, the first id that cannot be approved stops the run
# with nothing written, each depends_on that is not done yet is a warning, and nothing is pushed (the push is
# state-push.sh's, DECISIONS D4).
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
export WORK_DIR

state="$tmp/state"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/archive/2026-08/tasks"
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
says() { # <what> <file> <text>
  if grep -qF -- "$3" "$2"; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: no [%s] in:\n' "$1" "$3"; sed 's/^/  /' "$2"; fail=1; fi
}
not_says() { # <what> <file> <text>
  if grep -qF -- "$3" "$2"; then printf 'FAIL %s: [%s] in:\n' "$1" "$3"; sed 's/^/  /' "$2"; fail=1
  else printf 'PASS %s\n' "$1"; fi
}

task() { # <id> [status] [depends_on] [dir under repos/demo]
  cat > "$state/repos/demo/${4:-tasks}/$1.md" <<EOF
---
id: $1
repo: demo
status: ${2:-draft}
archetype: bugfix
tier: yellow
complexity: low
depends_on: ${3:-[]}
attempt: 0
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
head_of() { git -C "$state" rev-parse HEAD; }

# --- one id: one commit, plan_hash is the commit that holds the body -------------
task T-001
before=$(head_of)
out=$(sh "$bin/task-approve.sh" T-001 --state "$state" 2>&1); rc=$?
check 'one id exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'one id is ready' ready "$(field T-001 status)"
check 'one id is one commit' "$before" "$(git -C "$state" rev-parse HEAD~1)"
check 'plan_hash is the commit that held the approved body' "$before" "$(field T-001 plan_hash)"
check 'the commit message' 'chore(T-001): plan_hash of the approved body' "$(git -C "$state" log -1 --format=%s)"
check 'the commit body names the flip' 'T-001: draft → ready' "$(git -C "$state" log -1 --format=%b | sed '/^$/d')"
check 'the working tree is clean' '' "$(git -C "$state" status --porcelain)"

# --- stalled is no status any more, so it is not approved ---------------------------
task T-009 stalled
out=$(sh "$bin/task-approve.sh" T-009 --state "$state" 2>&1); rc=$?
check 'a stalled task is refused' 1 "$rc"
check 'a refused stalled task keeps its status' stalled "$(field T-009 status)"

# --- several ids: one lock, one commit ------------------------------------------------
task T-010
task T-011 failed
task T-012 tests_ready
before=$(head_of)
out=$(sh "$bin/task-approve.sh" T-010 T-011 T-012 --state "$state" 2>&1); rc=$?
check 'several ids exit 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'several ids are one commit' "$before" "$(git -C "$state" rev-parse HEAD~1)"
for id in T-010 T-011 T-012; do
  check "$id is ready" ready "$(field "$id" status)"
  check "$id pins the body commit" "$before" "$(field "$id" plan_hash)"
done
check 'a failed task gets its attempt bumped' 1 "$(field T-011 attempt)"
check 'a tests_ready task moves to implement' implement "$(field T-012 phase)"
check 'the commit holds the three files' 'repos/demo/tasks/T-010.md repos/demo/tasks/T-011.md repos/demo/tasks/T-012.md' \
  "$(git -C "$state" show --name-only --format= HEAD | sort | tr '\n' ' ' | sed 's/ $//')"
check 'the commit subject for several' 'chore(approve): T-010 T-011 T-012 ready, plan_hash of the approved bodies' \
  "$(git -C "$state" log -1 --format=%s)"
check 'the commit body names each flip' 'T-010: draft → ready T-011: failed → ready T-012: tests_ready → ready' \
  "$(git -C "$state" log -1 --format=%b | sed '/^$/d' | tr '\n' ' ' | sed 's/ $//')"

# --- the same id twice is approved once -----------------------------------------------
task T-013 failed
sh "$bin/task-approve.sh" T-013 T-013 --state "$state" >/dev/null 2>&1
check 'a repeated id bumps the attempt once' 1 "$(field T-013 attempt)"

# --- the first failure stops the run, nothing is written ---------------------------------
task T-020
task T-021 in_progress
task T-022 stalled
before=$(head_of)
sh "$bin/task-approve.sh" T-020 T-021 T-022 --state "$state" >"$tmp/out" 2>&1; rc=$?
check 'a failure exits 1' 1 "$rc"
check 'a failure commits nothing' "$before" "$(head_of)"
check 'a failure writes nothing, not even the ids before it' draft "$(field T-020 status)"
check 'the working tree stays clean' '' "$(git -C "$state" status --porcelain)"
says 'the failure names the id' "$tmp/out" 'T-021'
not_says 'the run stopped at the first failure' "$tmp/out" 'T-022'
says 'the failure says nothing was approved' "$tmp/out" 'nothing was approved'

# --- an archived or unknown id is refused -------------------------------------------------
task T-900 done '[]' archive/2026-08/tasks
check 'an archived task is refused' 1 "$(sh "$bin/task-approve.sh" T-900 --state "$state" >/dev/null 2>&1; echo $?)"
check 'an unknown id is refused' 1 "$(sh "$bin/task-approve.sh" T-777 --state "$state" >/dev/null 2>&1; echo $?)"

# --- a warning per depends_on that is not done -----------------------------------------------
task T-030 draft
task T-031 done
task T-040 draft '[T-030, T-031, T-900, T-404]'
task T-040-01 draft '[]'
task T-040-02 draft '[T-040-01]'
sh "$bin/task-approve.sh" T-040 T-040-01 T-040-02 --state "$state" >"$tmp/out" 2>&1; rc=$?
check 'unfinished depends_on still approve, exit 0' 0 "$rc"
check 'T-040 is ready' ready "$(field T-040 status)"
says 'a draft dependency is a warning' "$tmp/out" 'T-040 depends on T-030, which is draft'
says 'a missing dependency is a warning' "$tmp/out" 'T-040 depends on T-404, which has no task file'
not_says 'a done dependency is no warning' "$tmp/out" 'T-031'
not_says 'an archived dependency is no warning' "$tmp/out" 'T-900'
not_says 'a sibling block is no warning' "$tmp/out" 'T-040-02 depends on'
check 'two warnings' 2 "$(grep -c 'warning' "$tmp/out")"

# --- a body edited and not committed: committed first, and plan_hash pins it --------------
task T-050
printf '\n## Context\nEdited by hand before the approval.\n' >> "$state/repos/demo/tasks/T-050.md"
before=$(head_of)
out=$(sh "$bin/task-approve.sh" T-050 --state "$state" 2>&1); rc=$?
check 'an uncommitted body exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the body commit sits before the approval' "$before" "$(git -C "$state" rev-parse HEAD~2)"
check 'plan_hash pins the body commit' "$(git -C "$state" rev-parse HEAD~1)" "$(field T-050 plan_hash)"
if git -C "$state" show "$(field T-050 plan_hash):repos/demo/tasks/T-050.md" | grep -q 'Edited by hand'; then
  printf 'PASS the pinned commit holds the edited body\n'
else printf 'FAIL the pinned commit holds the edited body\n'; fail=1; fi

# --- nothing is pushed ------------------------------------------------------------------------
git init -q --bare -b main "$tmp/origin.git"
git -C "$state" remote add origin "$tmp/origin.git"
git -C "$state" push -q -u origin main >/dev/null 2>&1
task T-060
pushed=$(git -C "$tmp/origin.git" rev-parse main)
out=$(sh "$bin/task-approve.sh" T-060 --state "$state" 2>&1); rc=$?
check 'with an origin exits 0' 0 "$rc"
check 'with an origin it is ready' ready "$(field T-060 status)"
check 'nothing reached the origin' "$pushed" "$(git -C "$tmp/origin.git" rev-parse main)"

exit $fail
