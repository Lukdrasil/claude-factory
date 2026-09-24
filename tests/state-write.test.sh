#!/bin/sh
# The writers of a state clone share one working tree with every other session on the machine: a refused push in
# task-new.sh undoes only its own commit and file, never another session's uncommitted edit or commit, two
# task-new.sh runs on one clone hand out two ids, and task-approve.sh and curate-apply.sh wait for state_lock.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$root/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
DASHBOARD_URL=''
export WORK_DIR DASHBOARD_URL

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

foreign_task() { # <other clone> <id>: the lines of a script that pushes a task with that id from the other clone
  printf "printf -- '---\\nid: %s\\nrepo: demo\\nstatus: draft\\n---\\n' > %s/repos/demo/tasks/%s-foreign.md\n" "$2" "$1" "$2"
  printf 'git -C %s add -A\ngit -C %s commit -q -m "foreign %s"\ngit -C %s push -q >/dev/null 2>&1\n' "$1" "$1" "$2" "$1"
}

# a git on PATH that runs $FIRST_PUSH once, before the first push it is asked for, so the remote (and in case 2
# the clone itself) moves between task-new.sh's commit and its push
real_git=$(command -v git)
mkdir -p "$tmp/fakebin"
cat > "$tmp/fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" push "*)
    if [ -n "\${FIRST_PUSH:-}" ] && [ ! -e "\$FIRST_PUSH.done" ]; then
      : > "\$FIRST_PUSH.done"
      sh "\$FIRST_PUSH"
    fi ;;
esac
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/fakebin/git"

# --- 1. a refused push keeps another session's uncommitted edit ---------------------
st="$tmp/one/state"
new_state "$st"
with_origin "$st" "$tmp/one/other"
foreign_task "$tmp/one/other" T-002 > "$tmp/one/first-push.sh"
printf 'another session, not committed\n' >> "$st/notes.md"
draft "$tmp/one/draft.md" 'a task written while the remote moves'
rc=0
out=$(PATH="$tmp/fakebin:$PATH" FIRST_PUSH="$tmp/one/first-push.sh" \
  sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/one/draft.md" 2>"$tmp/one/err") || rc=$?
check '1. the push was refused once' yes "$([ -e "$tmp/one/first-push.sh.done" ] && echo yes || echo no)"
check '1. task-new exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/one/err"
check '1. the new task takes the id after the remote one' T-003 "$(printf '%s' "$out" | sed -n 's/^{"id":"\([^"]*\)".*/\1/p')"
check '1. the uncommitted edit of another session survives' 'shared notes
another session, not committed' "$(cat "$st/notes.md")"
check '1. the edit is still uncommitted' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"
check '1. the remote holds T-002 once' 1 \
  "$(git -C "$st.git" grep -l '^id: T-002$' main -- repos 2>/dev/null | wc -l | tr -d ' ')"
check '1. the remote holds the new T-003' 1 \
  "$(git -C "$st.git" grep -l '^id: T-003$' main -- repos 2>/dev/null | wc -l | tr -d ' ')"

# --- 2. HEAD is no longer task-new's own commit: stop, keep everything ----------------
st="$tmp/two/state"
new_state "$st"
with_origin "$st" "$tmp/two/other"
{
  printf 'printf "foreign\\n" > %s/foreign.md\n' "$st"
  printf 'git -C %s add -- foreign.md\n' "$st"
  printf 'git -C %s commit -q -m "a foreign commit" -- foreign.md\n' "$st"
  foreign_task "$tmp/two/other" T-002
} > "$tmp/two/first-push.sh"
printf 'another session, not committed\n' >> "$st/notes.md"
draft "$tmp/two/draft.md" 'a task under a foreign commit'
rc=0
out=$(PATH="$tmp/fakebin:$PATH" FIRST_PUSH="$tmp/two/first-push.sh" \
  sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/two/draft.md" 2>"$tmp/two/err") || rc=$?
check '2. task-new exits 1' 1 "$rc"
check '2. the refusal is reported on stderr' yes "$(grep -q '^task-new: .*HEAD' "$tmp/two/err" && echo yes || echo no)"
check '2. the foreign commit is still HEAD' 'a foreign commit' "$(git -C "$st" log -1 --format=%s)"
check '2. the own commit is kept under it' 'chore(T-002): new draft task' "$(git -C "$st" log -1 --format=%s HEAD~1)"
check '2. the own task file is kept' yes \
  "$([ -f "$st/repos/demo/tasks/T-002-fix-demo-a-task-under-a.md" ] && echo yes || echo no)"
check '2. the uncommitted edit of another session survives' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"

# --- 3. two runs in parallel on one clone take two ids ----------------------------
st="$tmp/three/state"
new_state "$st"
draft "$tmp/three/a.md" 'the first parallel task'
draft "$tmp/three/b.md" 'the second parallel task'
sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/three/a.md" > "$tmp/three/a.out" 2>&1 &
pa=$!
sh "$bin/task-new.sh" --repo demo --state "$st" --file "$tmp/three/b.md" > "$tmp/three/b.out" 2>&1 &
pb=$!
ra=0; wait "$pa" || ra=$?
rb=0; wait "$pb" || rb=$?
check '3. the first parallel run exits 0' 0 "$ra"
check '3. the second parallel run exits 0' 0 "$rb"
ida=$(sed -n 's/^{"id":"\([^"]*\)".*/\1/p' "$tmp/three/a.out")
idb=$(sed -n 's/^{"id":"\([^"]*\)".*/\1/p' "$tmp/three/b.out")
check '3. the two runs took two different ids' 'T-002 T-003' "$(printf '%s\n%s\n' "$ida" "$idb" | sort | tr '\n' ' ' | sed 's/ $//')"
check '3. three distinct ids are committed' 3 \
  "$(git -C "$st" grep -h '^id:' HEAD -- repos/demo/tasks | sort -u | wc -l | tr -d ' ')"

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
