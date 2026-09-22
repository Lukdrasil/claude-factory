#!/bin/sh
# task-done.sh over a throwaway state clone (T-186): the two endings a task has. A triage, ops or research task
# carries no mr_url and ends in `closed`; every other archetype still needs the validated MR and ends in `done`.
# Both release `owner:` on the parent and on every block, because the Stop hook finds a session's tasks by owner
# and an owned terminal task is re-reported until the round budget runs out.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/state"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/progress"
git -C "$state" init -q
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}

task() { # <id> <archetype> <status> <mr_url> <owner>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: $3
archetype: $2
tier: green
complexity: low
owner: $5
mr_url: $4
---

# Goal
$2(demo): $1
EOF
}

field() { # <id> <key>
  sed -n "s/^$2:[[:space:]]*//p" "$state/repos/demo/tasks/$1.md" | head -n1
}

commit_all() {
  git -C "$state" add -A
  git -C "$state" commit -q -m 'fixture' || :
}

# --- a triage task in review with no mr_url ends in closed -------------------
task T-001 triage review null 'factory@host:sess-1'
commit_all
out=$(sh "$bin/task-done.sh" T-001 --state "$state" 2>&1); rc=$?
check 'triage task-done exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'triage parent is closed' closed "$(field T-001 status)"
check 'triage parent owner released' null "$(field T-001 owner)"

# --- an ops and a research task end the same way -----------------------------
task T-004 ops in_progress null 'factory@host:sess-1'
task T-005 research review null 'factory@host:sess-1'
commit_all
sh "$bin/task-done.sh" T-004 --state "$state" >/dev/null 2>&1
sh "$bin/task-done.sh" T-005 --state "$state" >/dev/null 2>&1
check 'ops parent is closed'      closed "$(field T-004 status)"
check 'research parent is closed' closed "$(field T-005 status)"

# --- a bugfix with no mr_url is refused, and nothing is written ---------------
task T-002 bugfix review null 'factory@host:sess-1'
commit_all
out=$(sh "$bin/task-done.sh" T-002 --state "$state" 2>&1); rc=$?
check 'bugfix without mr_url exits 1' 1 "$rc"
check 'bugfix status untouched'   review "$(field T-002 status)"
check 'bugfix owner untouched'    'factory@host:sess-1' "$(field T-002 owner)"
if printf '%s\n' "$out" | grep -q 'no mr_url'; then printf 'PASS the refusal names the missing mr_url\n'
else printf 'FAIL the refusal names the missing mr_url: %s\n' "$out"; fail=1; fi

# --- a bugfix with an mr_url ends in done, parent and block ------------------
task T-003    bugfix review https://forge.test/mr/3 'factory@host:sess-1'
task T-003-01 bugfix review null                    'factory@host:sess-1'
commit_all
out=$(sh "$bin/task-done.sh" T-003 --state "$state" 2>&1); rc=$?
check 'bugfix with mr_url exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'bugfix parent is done'       done "$(field T-003 status)"
check 'bugfix parent owner released' null "$(field T-003 owner)"
check 'the block is done'           done "$(field T-003-01 status)"
check 'the block owner is released' null "$(field T-003-01 owner)"
if git -C "$state" log -1 --format=%s | grep -q 'chore(T-003): review . done, blocks included'; then
  printf 'PASS the commit names the transition\n'
else printf 'FAIL the commit names the transition: %s\n' "$(git -C "$state" log -1 --format=%s)"; fail=1; fi
if [ -z "$(git -C "$state" status --porcelain -- repos/demo/tasks)" ]; then
  printf 'PASS the writes are committed\n'
else printf 'FAIL the writes are committed\n'; fail=1; fi

# --- the Stop hook lets a session with a finished task stop ------------------
# self-report-check.sh finds the session's tasks by owner, so the task here keeps its owner and only the status
# is terminal: the hook must still pass, and must not report anything for it.
task T-006 triage closed null 'factory@host:sess-9'
commit_all
work="$tmp/work"
mkdir -p "$work"
WORK_DIR=$tmp
export WORK_DIR
out=$(cd "$work" && printf '{"session_id":"sess-9","cwd":"%s"}' "$work" \
  | sh "$bin/self-report-check.sh" 2>&1); rc=$?
check 'the Stop hook passes on a closed owned task' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"

exit $fail
