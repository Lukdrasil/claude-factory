#!/bin/sh
# task-new.sh after a refused push (T-264-05): the state clone is shared by every session on the machine, so the
# retry may drop only its own commit and never another session's edit or commit, and a task commit another clone
# already published is the task that landed, not a reason to write it again. The race is made deterministic by a
# pre-push hook in clone A that runs one scenario on its first call and then refuses that push.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
STATE_DIR=''
export WORK_DIR STATE_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

clone() { # <origin> <dir>
  git clone -q "$1" "$2" 2>/dev/null
  git -C "$2" config user.email harness@localhost
  git -C "$2" config user.name harness
}

# a bare origin with one commit, clones A and B of it, and a pre-push hook in A that runs <scenario> once and
# refuses that push; every later push from A goes through
setup() { # <case dir> <scenario script>
  d=$1
  git init -q --bare -b main "$d/origin.git"
  clone "$d/origin.git" "$d/seed"
  mkdir -p "$d/seed/repos/demo/tasks" "$d/seed/plans"
  printf 'demo: {url: %s, default_branch: main, path: %s}\n' "$d/demo.git" "$d/demo" > "$d/seed/repos.yml"
  printf 'the plan as committed\n' > "$d/seed/plans/p.md"
  : > "$d/seed/repos/demo/tasks/.keep"
  git -C "$d/seed" add -A
  git -C "$d/seed" commit -q -m init
  git -C "$d/seed" push -q origin HEAD:main 2>/dev/null
  clone "$d/origin.git" "$d/A"
  clone "$d/origin.git" "$d/B"
  cat > "$d/A/.git/hooks/pre-push" <<EOF
#!/bin/sh
[ -e "$d/hook-ran" ] && exit 0
: > "$d/hook-ran"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
sh "$2" >"$d/hook.log" 2>&1
exit 1
EOF
  chmod +x "$d/A/.git/hooks/pre-push"
}

draft() { # <file> <context line>
  cat > "$1" <<EOF
---
id: T-001
repo: demo
branch: fix/refused-push
status: draft
tier: green
archetype: bugfix
complexity: low
---

# Goal
fix(demo): a refused push keeps the clone intact

## Context
$2

## Acceptance
\`test -f README.md\`
EOF
}

origin_tasks() { # <case dir> -> the task files on the origin's main, one line
  git --git-dir="$1/origin.git" ls-tree --name-only main repos/demo/tasks/ | sed 's|.*/||' | grep '\.md$' | tr '\n' ' '
}
origin_show() { # <case dir> <path>
  git --git-dir="$1/origin.git" show "main:$2" 2>/dev/null
}
new_task() { # <case dir> -> task-new's stdout in A, then its exit code on the last line
  out=$(sh "$bin/task-new.sh" --repo demo --state "$1/A" --file "$1/a.md" 2>"$1/err")
  printf '%s\n%s' "$out" "$?"
}
slug=fix-demo-a-refused-push-keeps

# --- clone B publishes A's unpushed task commit before A's push is refused ------------
c="$tmp/landed"
mkdir -p "$c"
cat > "$c/scenario.sh" <<EOF
git -C "$c/B" fetch -q "$c/A" main
git -C "$c/B" merge -q --ff-only FETCH_HEAD
git -C "$c/B" push -q origin main
EOF
setup "$c" "$c/scenario.sh"
draft "$c/a.md" 'written by clone A'
res=$(new_task "$c")
check 'the hook refused the first push after B published the commit' 'yes' "$([ -e "$c/hook-ran" ] && echo yes)"
check 'task-new exits 0 when its commit landed through another clone' 0 "$(printf '%s\n' "$res" | tail -n1)"
check 'task-new prints the id that landed' \
  "{\"id\":\"T-001\",\"file\":\"repos/demo/tasks/T-001-$slug.md\"}" "$(printf '%s\n' "$res" | sed -n 1p)"
check 'the origin carries the task once, under the id that landed' \
  "T-001-$slug.md " "$(origin_tasks "$c")"
check 'clone A carries the task once' "T-001-$slug.md" "$(cd "$c/A/repos/demo/tasks" && ls ./*.md | sed 's|^\./||' | tr '\n' ' ' | sed 's/ $//')"

# --- another clone took the same id, with the same slug, first ------------------------
c="$tmp/taken"
mkdir -p "$c"
cat > "$c/scenario.sh" <<EOF
sh "$bin/task-new.sh" --repo demo --state "$c/B" --file "$c/b.md"
EOF
setup "$c" "$c/scenario.sh"
draft "$c/a.md" 'written by clone A'
draft "$c/b.md" 'written by clone B'
res=$(new_task "$c")
check "B's task-new ran inside A's refused push" 'yes' "$(grep -q '"id":"T-001"' "$c/hook.log" && echo yes)"
check 'task-new exits 0 after the id was taken' 0 "$(printf '%s\n' "$res" | tail -n1)"
check 'task-new writes its task under the next id' \
  "{\"id\":\"T-002\",\"file\":\"repos/demo/tasks/T-002-$slug.md\"}" "$(printf '%s\n' "$res" | sed -n 1p)"
check 'both tasks exist on the origin' "T-001-$slug.md T-002-$slug.md " "$(origin_tasks "$c")"
check "B's task keeps B's body under T-001" 'written by clone B' \
  "$(origin_show "$c" "repos/demo/tasks/T-001-$slug.md" | grep 'written by')"
check "A's task has A's body under T-002" 'written by clone A' \
  "$(origin_show "$c" "repos/demo/tasks/T-002-$slug.md" | grep 'written by')"
check "A's task says id T-002" 'id: T-002' "$(origin_show "$c" "repos/demo/tasks/T-002-$slug.md" | grep '^id:')"

# --- an unrelated uncommitted edit in A survives the refused push ---------------------
c="$tmp/edit"
mkdir -p "$c"
cat > "$c/scenario.sh" <<EOF
sh "$bin/task-new.sh" --repo demo --state "$c/B" --file "$c/b.md"
EOF
setup "$c" "$c/scenario.sh"
draft "$c/a.md" 'written by clone A'
draft "$c/b.md" 'written by clone B'
printf 'another session is editing this plan\n' > "$c/A/plans/p.md"
res=$(new_task "$c")
check 'task-new exits 0 with an edit in the clone' 0 "$(printf '%s\n' "$res" | tail -n1)"
check "the other session's uncommitted edit keeps its content" 'another session is editing this plan' \
  "$(cat "$c/A/plans/p.md")"
check 'the edit is not committed with the task' 'the plan as committed' "$(origin_show "$c" plans/p.md)"

# --- another session commits on top of A's task commit before the push is refused -----
c="$tmp/ontop"
mkdir -p "$c"
cat > "$c/scenario.sh" <<EOF
printf 'another session committed this plan\n' > "$c/A/plans/p.md"
git -C "$c/A" commit -q -m 'plan: another session' -- plans/p.md && : > "$c/committed"
EOF
setup "$c" "$c/scenario.sh"
draft "$c/a.md" 'written by clone A'
res=$(new_task "$c")
check "the other session's commit was made inside A's refused push" 'yes' "$([ -e "$c/committed" ] && echo yes)"
check 'task-new fails when HEAD is no longer its own commit' 1 \
  "$([ "$(printf '%s\n' "$res" | tail -n1)" != 0 ] && echo 1 || echo 0)"
check "the other session's commit stays on A's branch" 'another session committed this plan' \
  "$(git -C "$c/A" show HEAD:plans/p.md)"
check "A's own task commit stays under it" 'chore(T-001): new draft task' "$(git -C "$c/A" log -1 --format=%s HEAD~1)"
check 'no second copy of the task is written' "T-001-$slug.md" \
  "$(cd "$c/A/repos/demo/tasks" && ls ./*.md | sed 's|^\./||' | tr '\n' ' ' | sed 's/ $//')"
check 'nothing reaches the origin' '' "$(origin_tasks "$c")"

# --- task-new waits for the state lock another session holds ----------------------------
c="$tmp/locked"
mkdir -p "$c"
: > "$c/scenario.sh"
setup "$c" "$c/scenario.sh"
draft "$c/a.md" 'written by clone A'
(. "$bin/lib-tasks.sh"; state_lock "$c/A" && : > "$c/held" && exec sleep 30) &
holder=$!
n=0
until [ -e "$c/held" ] || [ "$n" -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
res=$(STATE_LOCK_WAIT=1 new_task "$c")
kill "$holder" 2>/dev/null
check 'task-new does not run while another session holds the state lock' 1 \
  "$([ "$(printf '%s\n' "$res" | tail -n1)" != 0 ] && echo 1 || echo 0)"
check 'nothing is written under a held lock' '' "$(cd "$c/A/repos/demo/tasks" && ls ./*.md 2>/dev/null)"
check 'nothing reaches the origin under a held lock' '' "$(origin_tasks "$c")"

exit $fail
