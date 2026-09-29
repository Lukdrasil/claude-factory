#!/bin/sh
# curate-apply.sh and the repo x agent tier (agent-org plan 3.5, 3.8): the queue holds
# repos/<key>/agents/<agent>/memory/proposals, a proposal is filed into repos/<key>/agents/<agent>/memory, a
# `Replaces: <path>, <path>` line deletes those files in the approving commit (and refuses, writing nothing,
# when one is missing or outside the memory roots), and a decision waits for the state lock.
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
has() { [ -e "$st/$1" ] && echo yes || echo no; }

st=$tmp/state
q=repos/demo/agents/implementer/memory/proposals
mkdir -p "$st/$q" "$st/repos/demo/memory" "$st/repos/demo/tasks" "$st/memory/global" "$st/agents/scout/memory"
git init -q -b main "$st"
git -C "$st" config user.email harness@localhost
git -C "$st" config user.name harness
printf 'demo: {url: x, default_branch: main, path: %s}\n' "$tmp/demo" > "$st/repos.yml"
printf '# a lesson\n' > "$st/$q/plain.md"
printf '# another lesson\n' > "$st/$q/moved.md"
printf '# a one-off\n' > "$st/$q/one-off.md"
printf '# old global\n' > "$st/memory/global/old-a.md"
printf '# old repo\n' > "$st/repos/demo/memory/old-b.md"
printf '# kept\n' > "$st/repos/demo/memory/kept.md"
printf -- '---\nid: T-001\nstatus: draft\n---\n' > "$st/repos/demo/tasks/T-001.md"
printf '# merged\n\nWhy: both said it.\nEvidence: T-001.\nReplaces: memory/global/old-a.md, `repos/demo/memory/old-b.md`\n' \
  > "$st/$q/merged.md"
printf '# merged\n\nReplaces: repos/demo/memory/gone.md\n' > "$st/$q/missing.md"
printf '# merged\n\nReplaces: repos/demo/tasks/T-001.md\n' > "$st/$q/outside.md"
git -C "$st" add -A
git -C "$st" commit -q -m init

ca() { sh "$bin/curate-apply.sh" "$@" --state "$st"; }

# --- 1. the queue -----------------------------------------------------------------------------------------------
check '1. list holds the repo x agent queue' yes \
  "$(ca list | grep -qxF "$q/plain.md" && echo yes || echo no)"

# --- 2. approve into the repo x agent memory --------------------------------------------------------------------
ca approve "$q/plain.md" >/dev/null 2>&1; rc=$?
check '2. approve to the default target exits 0' 0 "$rc"
check '2. the lesson is filed in repos/demo/agents/implementer/memory' yes "$(has repos/demo/agents/implementer/memory/plain.md)"
check '2. the approval is one commit' "chore(proposal): approve $q/plain.md -> repos/demo/agents/implementer/memory/plain.md" \
  "$(git -C "$st" log -1 --format=%s)"
ca approve "$q/moved.md" repos/demo/agents/scout/memory/moved.md >/dev/null 2>&1; rc=$?
check '2. an explicit target in another agent of the repo is accepted' 0 "$rc"
check '2. and filed there' yes "$(has repos/demo/agents/scout/memory/moved.md)"
head=$(git -C "$st" rev-parse HEAD)
ca approve "$q/one-off.md" repos/demo/agents/implementer/drafts/one-off.md >/dev/null 2>"$tmp/err"; rc=$?
check '2. a target in drafts/ is refused' 1 "$rc"
check '2. the refusal names the repo x agent root' yes \
  "$(grep -q 'repos/<key>/agents/<agent>/memory' "$tmp/err" && echo yes || echo no)"
check '2. nothing is committed on a refusal' "$head" "$(git -C "$st" rev-parse HEAD)"
ca approve "$q/one-off.md" repos/nope/agents/implementer/memory/x.md >/dev/null 2>&1; rc=$?
check '2. a repo x agent target of an unknown repo is refused' 1 "$rc"
ca approve "$q/one-off.md" repos/demo/agents/a/b/memory/x.md >/dev/null 2>&1; rc=$?
check '2. a nested agent segment is refused' 1 "$rc"

# --- 3. reject --------------------------------------------------------------------------------------------------
ca reject "$q/one-off.md" --reason 'one task only' >/dev/null 2>&1; rc=$?
check '3. reject of a repo x agent proposal exits 0' 0 "$rc"
check '3. the proposal is gone' no "$(has "$q/one-off.md")"
check '3. the reason rides in the commit' "chore(proposal): reject $q/one-off.md, one task only" "$(git -C "$st" log -1 --format=%s)"

# --- 4. Replaces: on approve ------------------------------------------------------------------------------------
ca approve "$q/merged.md" >/dev/null 2>&1; rc=$?
check '4. approve with Replaces: exits 0' 0 "$rc"
check '4. the merged lesson is filed' yes "$(has repos/demo/agents/implementer/memory/merged.md)"
check '4. the first replaced file is deleted' no "$(has memory/global/old-a.md)"
check '4. the second replaced file is deleted' no "$(has repos/demo/memory/old-b.md)"
check '4. an unnamed file stays' yes "$(has repos/demo/memory/kept.md)"
check '4. the deletions ride in the approving commit' 'D	memory/global/old-a.md
D	repos/demo/memory/old-b.md' \
  "$(git -C "$st" show --name-status --format= HEAD | grep '^D' | LC_ALL=C sort)"
check '4. the tree is clean after it' '' "$(git -C "$st" status --porcelain)"
head=$(git -C "$st" rev-parse HEAD)
ca approve "$q/missing.md" >/dev/null 2>"$tmp/err"; rc=$?
check '4. a Replaces: path that does not exist is refused' 1 "$rc"
check '4. the refusal names it' yes "$(grep -q 'repos/demo/memory/gone.md' "$tmp/err" && echo yes || echo no)"
check '4. the proposal stays queued' yes "$(has "$q/missing.md")"
check '4. nothing is committed' "$head" "$(git -C "$st" rev-parse HEAD)"
ca approve "$q/outside.md" >/dev/null 2>&1; rc=$?
check '4. a Replaces: path outside the memory roots is refused' 1 "$rc"
check '4. the task file stays' yes "$(has repos/demo/tasks/T-001.md)"
check '4. nothing is committed either' "$head" "$(git -C "$st" rev-parse HEAD)"

# --- 5. a decision waits for the state lock ---------------------------------------------------------------------
printf '# locked\n' > "$st/$q/locked.md"
git -C "$st" add -A && git -C "$st" commit -q -m 'queue locked'
rm -f "$tmp/held" "$tmp/release"
(. "$bin/lib-tasks.sh"; state_lock "$st" || exit 1; : > "$tmp/held"
 while [ ! -e "$tmp/release" ]; do sleep 1; done) &
holder=$!
n=0
while [ ! -e "$tmp/held" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
before=$(git -C "$st" rev-parse HEAD)
STATE_LOCK_WAIT=20 sh "$bin/curate-apply.sh" approve "$q/locked.md" --state "$st" >/dev/null 2>&1 &
pid=$!
sleep 2
check '5. approve has not committed while the lock is held' "$before" "$(git -C "$st" rev-parse HEAD)"
: > "$tmp/release"
wait "$holder"
rc=0; wait "$pid" || rc=$?
check '5. approve exits 0 once the lock is free' 0 "$rc"
check '5. and files the lesson' yes "$(has repos/demo/agents/implementer/memory/locked.md)"

exit "$fail"
