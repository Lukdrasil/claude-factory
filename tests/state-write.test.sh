#!/bin/sh
# The writers of a state clone share one working tree with every other session on the machine: task-new.sh
# commits only its own file and never touches the remote (no pull, fetch or push, so no reset either), another
# session's uncommitted or staged edit survives it untouched, parallel task-new.sh runs on one clone hand out
# distinct ids, and task-approve.sh and curate-apply.sh wait for state_lock.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$root/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
export WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

new_state() { # <dir>
  mkdir -p "$1/repos/demo/tasks" "$1/repos/demo/memory/proposals"
  git init -q -b main "$1"
  git -C "$1" config user.email harness@localhost
  git -C "$1" config user.name harness
  printf 'demo: {url: %s, default_branch: main, path: %s}\n' "$tmp/demo-origin.git" "$tmp/demo" > "$1/repos.yml"
  cat > "$1/repos/demo/tasks/T-001-first.md" <<'EOF'
---
id: T-001
repo: demo
status: draft
archetype: bugfix
tier: yellow
complexity: low
owner: null
mr_url: null
---

# Goal
fix(demo): the first task
EOF
  printf 'shared notes\n' > "$1/notes.md"
  printf 'a lesson\n' > "$1/repos/demo/memory/proposals/lesson.md"
  git -C "$1" add -A
  git -C "$1" commit -q -m init
}

with_origin() { # <state> <other clone>
  git init -q --bare -b main "$1.git"
  git -C "$1" remote add origin "$1.git"
  git -C "$1" push -q -u origin main >/dev/null 2>&1
  git clone -q -b main "$1.git" "$2" >/dev/null 2>&1
  git -C "$2" config user.email other@localhost
  git -C "$2" config user.name other
}

draft() { # <file> <goal subject>
  cat > "$1" <<EOF
---
id: T-000
repo: demo
branch: fix/x
status: draft
tier: green
archetype: bugfix
complexity: low
---

# Goal
fix(demo): $2

## Acceptance
\`true\`
EOF
}

# a git on PATH that logs every call that talks to a remote into $GIT_LOG, so a test can see that none was made
real_git=$(command -v git)
mkdir -p "$tmp/fakebin"
cat > "$tmp/fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" push "*|*" pull "*|*" fetch "*|*" ls-remote "*|*" remote update "*)
    [ -z "\${GIT_LOG:-}" ] || printf '%s\n' "\$*" >> "\$GIT_LOG" ;;
esac
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/fakebin/git"

# --- 1. task-new commits locally, never talks to the remote, and leaves another session's edit alone ---
st="$tmp/one/state"
new_state "$st"
with_origin "$st" "$tmp/one/other"
pushed=$(git -C "$st" rev-parse HEAD)
printf 'another session, not committed\n' >> "$st/notes.md"
draft "$tmp/one/draft.md" 'a task written beside an edit'
rc=0
out=$(PATH="$tmp/fakebin:$PATH" GIT_LOG="$tmp/one/remote.log" \
  sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/one/draft.md" 2>"$tmp/one/err") || rc=$?
check '1. task-new exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/one/err"
check '1. the new task is T-002' T-002 "$(printf '%s' "$out" | sed -n 's/^{"id":"\([^"]*\)".*/\1/p')"
check '1. no git call talked to the remote' '' "$(cat "$tmp/one/remote.log" 2>/dev/null)"
check '1. the task commit sits right on the previous HEAD' "$pushed" "$(git -C "$st" rev-parse HEAD~1)"
check '1. the origin did not move' "$pushed" "$(git -C "$st.git" rev-parse main)"
check '1. the uncommitted edit of another session survives' 'shared notes
another session, not committed' "$(cat "$st/notes.md")"
check '1. the edit is still uncommitted' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"
check '1. the task commit holds the task file only' 'repos/demo/tasks/T-002-fix-demo-a-task-written-beside.md' \
  "$(git -C "$st" show --name-only --format= HEAD)"

# --- 2. another session's staged file stays staged and out of the task commit ---------------
st="$tmp/two/state"
new_state "$st"
printf 'staged by another session\n' > "$st/staged.md"
git -C "$st" add -- staged.md
printf 'another session, not committed\n' >> "$st/notes.md"
draft "$tmp/two/draft.md" 'a task beside a staged file'
rc=0
out=$(sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/two/draft.md" 2>"$tmp/two/err") || rc=$?
check '2. task-new exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/two/err"
check '2. the task commit holds the task file only' 'repos/demo/tasks/T-002-fix-demo-a-task-beside-a.md' \
  "$(git -C "$st" show --name-only --format= HEAD)"
check '2. the staged file stays staged' 'A  staged.md' "$(git -C "$st" status --porcelain -- staged.md)"
check '2. the uncommitted edit stays uncommitted' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"

# --- 3. parallel runs on one clone take distinct ids, legacy and alias alike -----------------
st="$tmp/three/state"
new_state "$st"
printf 'ecs: {url: %s, default_branch: main, path: %s, alias: ECS}\n' "$tmp/ecs-origin.git" "$tmp/ecs" >> "$st/repos.yml"
git -C "$st" commit -q -m ecs -- repos.yml
for n in a b c d; do draft "$tmp/three/$n.md" "the parallel task $n"; done
for n in c d; do
  sed 's/^repo: demo$/repo: ecs/; s/^fix(demo)/fix(ecs)/' "$tmp/three/$n.md" > "$tmp/three/$n.ecs.md"
done
sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/three/a.md" > "$tmp/three/a.out" 2>&1 &
pa=$!
sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/three/b.md" > "$tmp/three/b.out" 2>&1 &
pb=$!
sh "$bin/task-new.sh" --repo ecs --state "$st" --file "$tmp/three/c.ecs.md" > "$tmp/three/c.out" 2>&1 &
pc=$!
sh "$bin/task-new.sh" --repo ecs --state "$st" --file "$tmp/three/d.ecs.md" > "$tmp/three/d.out" 2>&1 &
pd=$!
for n in a b c d; do
  r=0
  eval "wait \"\$p$n\"" || r=$?
  check "3. the parallel run $n exits 0" 0 "$r"
  [ "$r" = 0 ] || sed 's/^/  /' "$tmp/three/$n.out"
done
check '3. the four runs took four distinct ids' 'T-002 T-003 T-ECS-1 T-ECS-2' \
  "$(sed -n 's/^{"id":"\([^"]*\)".*/\1/p' "$tmp/three/a.out" "$tmp/three/b.out" "$tmp/three/c.out" "$tmp/three/d.out" \
     | sort | tr '\n' ' ' | sed 's/ $//')"
check '3. five distinct ids are committed' 5 \
  "$(git -C "$st" grep -h '^id:' HEAD -- repos | sort -u | wc -l | tr -d ' ')"

# --- 4. task-approve.sh and curate-apply.sh wait for the lock ----------------------
waits_for_lock() { # <name> <state> <command…>
  wl_name=$1 wl_state=$2
  shift 2
  rm -f "$tmp/held" "$tmp/release"
  (. "$bin/lib-tasks.sh"; state_lock "$wl_state" || exit 1; : > "$tmp/held"
   while [ ! -e "$tmp/release" ]; do sleep 1; done) &
  wl_holder=$!
  wl_n=0
  while [ ! -e "$tmp/held" ] && [ "$wl_n" -lt 50 ]; do sleep 0.1; wl_n=$((wl_n + 1)); done
  wl_before=$(git -C "$wl_state" rev-parse HEAD)
  STATE_LOCK_WAIT=20 "$@" >"$tmp/$wl_name.out" 2>&1 &
  wl_pid=$!
  sleep 2
  check "4. $wl_name has not committed while the lock is held" "$wl_before" "$(git -C "$wl_state" rev-parse HEAD)"
  : > "$tmp/release"
  wait "$wl_holder"
  wl_rc=0; wait "$wl_pid" || wl_rc=$?
  check "4. $wl_name exits 0 once the lock is free" 0 "$wl_rc"
  [ "$wl_rc" = 0 ] || sed 's/^/  /' "$tmp/$wl_name.out"
  check "4. $wl_name commits once the lock is free" yes \
    "$([ "$(git -C "$wl_state" rev-parse HEAD)" != "$wl_before" ] && echo yes || echo no)"
}

st="$tmp/four/state"
new_state "$st"
waits_for_lock task-approve "$st" sh "$bin/task-approve.sh" T-001 --state "$st"
check '4. task-approve made both commits' 'chore(T-001): plan_hash of the approved body' "$(git -C "$st" log -1 --format=%s)"
waits_for_lock curate-apply "$st" sh "$bin/curate-apply.sh" approve repos/demo/memory/proposals/lesson.md --state "$st"
check '4. curate-apply approved the proposal' yes "$([ -f "$st/repos/demo/memory/lesson.md" ] && echo yes || echo no)"

exit "$fail"
