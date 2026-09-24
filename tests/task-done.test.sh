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

has_line() { # <what> <regex> <file>
  if grep -Eq "$2" "$3" 2>/dev/null; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: no line /%s/ in %s\n' "$1" "$2" "$3"; fail=1; fi
}

# --- T-228 A8: --close ends a parent of any archetype in closed, blocks included, with no mr_url ---
task T-007    bugfix review      null 'factory@host:sess-1'
task T-007-01 bugfix in_progress null 'factory@host:sess-1'
printf '# T-007\n' > "$state/repos/demo/progress/T-007.md"
commit_all
out=$(sh "$bin/task-done.sh" T-007 --close 'superseded by T-009' --state "$state" 2>&1); rc=$?
check '--close on a bugfix parent exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check '--close parent is closed'            closed "$(field T-007 status)"
check '--close parent owner released'       null   "$(field T-007 owner)"
check '--close block is closed'             closed "$(field T-007-01 status)"
check '--close block owner released'        null   "$(field T-007-01 owner)"
if git -C "$state" log -1 --format=%B | grep -q 'superseded by T-009'; then
  printf 'PASS the --close commit carries the reason\n'
else printf 'FAIL the --close commit carries the reason: %s\n' "$(git -C "$state" log -1 --format=%B)"; fail=1; fi
has_line 'the parent progress file has a **closed** <reason> line' \
  '^\*\*closed\*\*.*superseded by T-009' "$state/repos/demo/progress/T-007.md"
if [ -z "$(git -C "$state" status --porcelain -- repos/demo)" ]; then
  printf 'PASS the --close writes are committed\n'
else printf 'FAIL the --close writes are committed: %s\n' "$(git -C "$state" status --porcelain -- repos/demo)"; fail=1; fi

# --- --close on a block id closes that block alone ---------------------------
task T-008    feature in_progress null 'factory@host:sess-1'
task T-008-01 feature in_progress null 'factory@host:sess-1'
task T-008-02 feature in_progress null 'factory@host:sess-1'
printf '# T-008-01\n' > "$state/repos/demo/progress/T-008-01.md"
commit_all
out=$(sh "$bin/task-done.sh" T-008-01 --close 'folded into T-008-02' --state "$state" 2>&1); rc=$?
check '--close on a block exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check '--close closes the block'             closed      "$(field T-008-01 status)"
check '--close releases the block owner'     null        "$(field T-008-01 owner)"
check '--close leaves the parent alone'      in_progress "$(field T-008 status)"
check '--close leaves the sibling alone'     in_progress "$(field T-008-02 status)"
has_line 'the block progress file has a **closed** <reason> line' \
  '^\*\*closed\*\*.*folded into T-008-02' "$state/repos/demo/progress/T-008-01.md"

# --- --close without a reason is refused and writes nothing ------------------
task T-011 bugfix review null 'factory@host:sess-1'
commit_all
sh "$bin/task-done.sh" T-011 --close --state "$state" >/dev/null 2>&1; rc=$?
check '--close with no reason exits 1' 1 "$rc"
check '--close with no reason leaves the status' review "$(field T-011 status)"

# --- the push: the state root gets the done commit ---------------------------
git init -q --bare "$tmp/state-origin.git"
git -C "$state" remote add origin "$tmp/state-origin.git"
git -C "$state" push -q -u origin HEAD >/dev/null 2>&1
task T-012 bugfix review https://forge.test/mr/12 'factory@host:sess-1'
commit_all
git -C "$state" push -q >/dev/null 2>&1
sh "$bin/task-done.sh" T-012 --state "$state" >/dev/null 2>&1; rc=$?
check 'done with an origin exits 0' 0 "$rc"
check 'the done commit is pushed' "$(git -C "$state" rev-parse HEAD)" \
  "$(git -C "$tmp/state-origin.git" rev-parse HEAD 2>/dev/null)"

# --- a state root that refuses the push is exit 2, the commit stays local ---
git -C "$state" remote set-url origin "$tmp/no-such-origin.git"
task T-013 bugfix review https://forge.test/mr/13 'factory@host:sess-1'
commit_all
out=$(sh "$bin/task-done.sh" T-013 --state "$state" 2>&1); rc=$?
check 'a refused push exits 2' 2 "$rc"
check 'a refused push still commits done' done "$(field T-013 status)"
git -C "$state" remote set-url origin "$tmp/state-origin.git"
git -C "$state" push -q >/dev/null 2>&1

# --- T-228 Q2/Q16: after the push, clean worktrees and pushed branches of the task and its blocks go ---
# The registered clone has an origin; T-010 and T-010-01 are clean and pushed, T-010-02 is pushed but its
# worktree is dirty, and block/T-010-03 has no worktree and a local commit its remote-tracking ref lacks.
clone="$tmp/clone"
git init -q --bare "$tmp/clone-origin.git"
git init -q -b main "$clone"
git -C "$clone" config user.email harness@localhost
git -C "$clone" config user.name harness
git -C "$clone" commit -q --allow-empty -m init
git -C "$clone" remote add origin "$tmp/clone-origin.git"
git -C "$clone" push -q -u origin main >/dev/null 2>&1
printf 'demo: {url: %s, default_branch: main, path: %s}\n' "$tmp/clone-origin.git" "$clone" > "$state/repos.yml"

with_branch() { # <id> <branch>
  f="$state/repos/demo/tasks/$1.md"
  awk -v b="$2" '{ print } /^repo:/ { print "branch: " b }' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
}
wt_on() { # <id> <branch>
  git -C "$clone" worktree add -q -b "$2" "$tmp/demo/$1" main >/dev/null 2>&1
  git -C "$tmp/demo/$1" commit -q --allow-empty -m "work of $1"
  git -C "$tmp/demo/$1" push -q -u origin "$2" >/dev/null 2>&1
}
mkdir -p "$tmp/demo"
task T-010    bugfix review https://forge.test/mr/10 'factory@host:sess-1'
task T-010-01 bugfix review null 'factory@host:sess-1'
task T-010-02 bugfix review null 'factory@host:sess-1'
task T-010-03 bugfix review null 'factory@host:sess-1'
with_branch T-010    feat/T-010-demo
with_branch T-010-01 block/T-010-01
with_branch T-010-02 block/T-010-02
with_branch T-010-03 block/T-010-03
commit_all
git -C "$state" push -q >/dev/null 2>&1
wt_on T-010    feat/T-010-demo
wt_on T-010-01 block/T-010-01
wt_on T-010-02 block/T-010-02
printf 'uncommitted\n' > "$tmp/demo/T-010-02/scratch.txt"
git -C "$clone" branch -q block/T-010-03 main
git -C "$clone" push -q origin block/T-010-03 >/dev/null 2>&1
git -C "$clone" worktree add -q "$tmp/demo/T-010-03" block/T-010-03 >/dev/null 2>&1
git -C "$tmp/demo/T-010-03" commit -q --allow-empty -m 'local only'
git -C "$clone" worktree remove "$tmp/demo/T-010-03"
task T-010-04 bugfix review null 'factory@host:sess-1'
task T-010-05 bugfix review null 'factory@host:sess-1'
commit_all
git -C "$state" push -q >/dev/null 2>&1
git -C "$clone" worktree add -q --detach "$tmp/demo/T-010-04" main >/dev/null 2>&1
git -C "$tmp/demo/T-010-04" commit -q --allow-empty -m 'detached, local only'
git -C "$clone" worktree add -q --detach "$tmp/demo/T-010-05" main >/dev/null 2>&1
git -C "$tmp/demo/T-010-05" commit -q --allow-empty -m 'detached, pushed'
git -C "$tmp/demo/T-010-05" push -q origin HEAD:refs/heads/block/T-010-05 >/dev/null 2>&1

branch_there() { git -C "$clone" show-ref --verify --quiet "refs/heads/$1" && echo yes || echo no; }
dir_there() { [ -e "$1" ] && echo yes || echo no; }

out=$(sh "$bin/task-done.sh" T-010 --state "$state" 2>&1); rc=$?
check 'done with leftovers still exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the parent is done'                       done "$(field T-010 status)"
check 'the clean parent worktree is removed'     no  "$(dir_there "$tmp/demo/T-010")"
check 'the pushed parent branch is deleted'      no  "$(branch_there feat/T-010-demo)"
check 'the clean block worktree is removed'      no  "$(dir_there "$tmp/demo/T-010-01")"
check 'the pushed block branch is deleted'       no  "$(branch_there block/T-010-01)"
check 'the dirty block worktree is kept'         yes "$(dir_there "$tmp/demo/T-010-02")"
check 'the dirty block file survives'            yes "$(dir_there "$tmp/demo/T-010-02/scratch.txt")"
check 'the branch of the dirty worktree is kept' yes "$(branch_there block/T-010-02)"
check 'a branch ahead of its remote is kept'     yes "$(branch_there block/T-010-03)"
check 'a clean detached worktree no remote-tracking ref contains is kept' yes "$(dir_there "$tmp/demo/T-010-04")"
check 'a clean detached worktree whose HEAD is pushed is removed'         no  "$(dir_there "$tmp/demo/T-010-05")"
check 'the remote branches are not touched'      yes \
  "$(git -C "$tmp/clone-origin.git" show-ref --verify --quiet refs/heads/block/T-010-01 && echo yes || echo no)"
if printf '%s\n' "$out" | grep -E '^skipped: ' | grep -q "$tmp/demo/T-010-02"; then
  printf 'PASS a skipped: line names the dirty worktree\n'
else printf 'FAIL a skipped: line names the dirty worktree: %s\n' "$out"; fail=1; fi
if printf '%s\n' "$out" | grep -E '^skipped: ' | grep -q 'block/T-010-03'; then
  printf 'PASS a skipped: line names the unpushed branch\n'
else printf 'FAIL a skipped: line names the unpushed branch: %s\n' "$out"; fail=1; fi
if printf '%s\n' "$out" | grep -E '^skipped: ' | grep -q "$tmp/demo/T-010-04"; then
  printf 'PASS a skipped: line names the detached worktree\n'
else printf 'FAIL a skipped: line names the detached worktree: %s\n' "$out"; fail=1; fi
if printf '%s\n' "$out" | grep -E '^skipped: ' | grep -q 'T-010-01'; then
  printf 'FAIL no skipped: line for what was removed: %s\n' "$out"; fail=1
else printf 'PASS no skipped: line for what was removed\n'; fi

# --- --close runs the same cleanup -------------------------------------------
task T-014 bugfix in_progress null 'factory@host:sess-1'
with_branch T-014 feat/T-014-demo
commit_all
git -C "$state" push -q >/dev/null 2>&1
wt_on T-014 feat/T-014-demo
sh "$bin/task-done.sh" T-014 --close 'abandoned' --state "$state" >/dev/null 2>&1; rc=$?
check '--close with a worktree exits 0' 0 "$rc"
check '--close removes the clean worktree' no "$(dir_there "$tmp/demo/T-014")"
check '--close deletes the pushed branch'  no "$(branch_there feat/T-014-demo)"

exit $fail
