#!/bin/sh
# task-new.sh allocates under the state lock and commits locally: a repo with an `alias:` in repos.yml gets
# T-<ALIAS>-<n+1> over its live and archived tasks, one without keeps the global legacy counter, a block is its
# parent plus -NN. The frontmatter carries request, priority and issue: validated, priority P2 by default, and a
# block copies all three from its parent. The push is gone, state-push.sh publishes in the background, so the
# origin never moves here; a held state lock refuses the run and writes nothing.
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

# a state clone of a bare origin: ecs (alias ECS, one archived task T-ECS-7), cf (alias CF, no task yet), demo (no
# alias, T-120 live and T-130 archived) and bad (an alias that is no alias)
st="$tmp/state"
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$st" 2>/dev/null
git -C "$st" config user.email harness@localhost
git -C "$st" config user.name harness
mkdir -p "$st/repos/ecs/archive/2026-08/tasks" "$st/repos/demo/tasks" "$st/repos/demo/archive/2026-08/tasks"
cat > "$st/repos.yml" <<EOF
ecs: {url: x, default_branch: main, path: $tmp/ecs, alias: ECS}
cf: {url: y, default_branch: main, path: $tmp/cf, alias: CF}
demo: {url: z, default_branch: main, path: $tmp/demo}
bad: {url: w, default_branch: main, path: $tmp/bad, alias: ecs1}
EOF
printf -- '---\nid: T-ECS-7\nrepo: ecs\nstatus: done\n---\n' > "$st/repos/ecs/archive/2026-08/tasks/T-ECS-7-old.md"
printf -- '---\nid: T-120\nrepo: demo\nstatus: ready\n---\n' > "$st/repos/demo/tasks/T-120-live.md"
printf -- '---\nid: T-130\nrepo: demo\nstatus: done\n---\n' > "$st/repos/demo/archive/2026-08/tasks/T-130-old.md"
git -C "$st" add -A
git -C "$st" commit -q -m init
git -C "$st" push -q origin HEAD:main 2>/dev/null
pushed=$(git -C "$st" rev-parse HEAD)

draft() { # <file> <repo> <goal subject> [branch] [frontmatter lines]
  cat > "$1" <<EOF
---
id: T-000
repo: $2
branch: ${4:-fix/x}
status: draft
tier: green
archetype: bugfix
complexity: low
${5:-}
---

# Goal
fix($2): $3

## Acceptance
\`true\`
EOF
}

# runs task-new.sh on <draft> for <repo> and sets rc, out (stdout and stderr) and id (the allocated id or empty)
new_task() { # <repo> <draft> [task-new args…]
  nt_repo=$1 nt_file=$2
  shift 2
  rc=0
  out=$(sh "$bin/task-new.sh" --repo "$nt_repo" --state "$st" --file "$nt_file" "$@" 2>&1) || rc=$?
  id=$(printf '%s' "$out" | sed -n 's/^{"id":"\([^"]*\)".*/\1/p')
}
field() { # <id> <key>
  sed -n "s/^$2:[[:space:]]*//p" "$st"/repos/*/tasks/"$1"-*.md 2>/dev/null | head -n1
}
commits() { git -C "$st" rev-list --count HEAD; }

# --- per-repo allocation ---------------------------------------------------------------
draft "$tmp/cf1.md" cf 'the first task of a repo with an alias'
new_task cf "$tmp/cf1.md"
check 'the first task of a repo with an alias is T-CF-1, printed with its file' \
  '{"id":"T-CF-1","file":"repos/cf/tasks/T-CF-1-fix-cf-the-first-task-of.md"}' "$out"
draft "$tmp/cf2.md" cf 'the second task'
new_task cf "$tmp/cf2.md"
check 'the second one is T-CF-2' T-CF-2 "$id"
check 'the commit is chore(<id>): new draft task' 'chore(T-CF-2): new draft task' "$(git -C "$st" log -1 --format=%s)"

draft "$tmp/ecs1.md" ecs 'a task after an archived one' fix/x 'request: R-20260924-3
priority: P0
issue: https://forge.example/g/ecs/-/issues/42'
new_task ecs "$tmp/ecs1.md"
check 'the counter of a repo counts its archived tasks: T-ECS-7 archived gives T-ECS-8' T-ECS-8 "$id"
draft "$tmp/ecs2.md" ecs 'a branch that carries an old id' fix/T-ECS-3-carried-over
new_task ecs "$tmp/ecs2.md"
check 'the next ecs task is T-ECS-9, the cf tasks do not count' T-ECS-9 "$id"
check 'the branch loses its old alias id' fix/T-ECS-9-carried-over "$(field T-ECS-9 branch)"

draft "$tmp/demo1.md" demo 'a task of a repo without an alias'
new_task demo "$tmp/demo1.md"
check 'a repo without an alias keeps the legacy counter over live and archived ids: T-131' T-131 "$id"
draft "$tmp/demo2.md" demo 'the next legacy task'
new_task demo "$tmp/demo2.md"
check 'the alias ids do not move the legacy counter' T-132 "$id"

draft "$tmp/bad.md" bad 'a repo whose alias is no alias'
before=$(commits)
new_task bad "$tmp/bad.md"
check 'an alias that is not 2 to 4 uppercase letters is refused' 1 "$rc"
check 'the refusal names the alias' yes "$(printf '%s' "$out" | grep -q "alias 'ecs1'" && echo yes || echo no)"
check 'nothing is committed for the refused alias' "$before" "$(commits)"

# --- blocks ------------------------------------------------------------------------------
draft "$tmp/b1.md" ecs 'the first block' block/T-000 'request: null
priority: P3
issue: null'
new_task ecs "$tmp/b1.md" --parent T-ECS-8
check 'a block of T-ECS-8 is T-ECS-8-01' T-ECS-8-01 "$id"
draft "$tmp/b2.md" ecs 'the second block' block/T-000
new_task ecs "$tmp/b2.md" --parent T-ECS-8
check 'the next block is T-ECS-8-02' T-ECS-8-02 "$id"
draft "$tmp/ecs3.md" ecs 'after the blocks'
new_task ecs "$tmp/ecs3.md"
check 'blocks do not move the parent counter' T-ECS-10 "$id"
draft "$tmp/b3.md" ecs 'a block of nothing' block/T-000
new_task ecs "$tmp/b3.md" --parent T-ECS-99
check 'a block of a parent that does not exist is refused' 1 "$rc"
draft "$tmp/b4.md" demo 'a block of a legacy parent' block/T-000
new_task demo "$tmp/b4.md" --parent T-120
check 'a block of a legacy parent is T-120-01' T-120-01 "$id"

# --- request, priority, issue -----------------------------------------------------------------
check 'a parent without the three lines gets priority P2' P2 "$(field T-CF-1 priority)"
check 'a parent without the three lines gets request null' null "$(field T-CF-1 request)"
check 'a parent without the three lines gets issue null' null "$(field T-CF-1 issue)"
check 'a parent keeps its request' R-20260924-3 "$(field T-ECS-8 request)"
check 'a parent keeps its priority' P0 "$(field T-ECS-8 priority)"
check 'a parent keeps its issue' https://forge.example/g/ecs/-/issues/42 "$(field T-ECS-8 issue)"
check 'a block copies the priority of its parent over its own' P0 "$(field T-ECS-8-01 priority)"
check 'a block copies the request of its parent' R-20260924-3 "$(field T-ECS-8-01 request)"
check 'a block copies the issue of its parent' https://forge.example/g/ecs/-/issues/42 "$(field T-ECS-8-01 issue)"
check 'a block of a parent without the lines gets P2, null, null' 'P2 null null' \
  "$(printf '%s %s %s' "$(field T-120-01 priority)" "$(field T-120-01 request)" "$(field T-120-01 issue)")"

refused() { # <what> <frontmatter line> <message part>
  draft "$tmp/r.md" cf "refused for $1" fix/x "$2"
  r_before=$(commits)
  new_task cf "$tmp/r.md"
  check "task-new refuses $1" 1 "$rc"
  check "the refusal of $1 says why" yes "$(printf '%s' "$out" | grep -qF -- "$3" && echo yes || echo no)"
  check "nothing is committed for $1" "$r_before" "$(commits)"
}
refused 'priority P4' 'priority: P4' 'priority must be one of P0|P1|P2|P3'
refused 'a lower-case priority' 'priority: p1' 'priority must be one of P0|P1|P2|P3'
refused 'a request without its date' 'request: R-2026-1' 'request must be R-YYYYMMDD-n or null'
refused 'an issue that is no url' 'issue: see the ticket' 'issue must be an http(s) url or null'
check 'no task file was left behind by a refusal' '' "$(ls "$st"/repos/cf/tasks/ | grep refused)"

# --- no push -----------------------------------------------------------------------------------
check 'the origin never moved' "$pushed" "$(git --git-dir="$tmp/origin.git" rev-parse main)"
check 'every task is a local commit on top of the pushed one' 10 "$(git -C "$st" rev-list --count "$pushed..HEAD")"
git -C "$st" remote set-url origin "$tmp/no-such-origin.git"
draft "$tmp/cf3.md" cf 'an origin that cannot be reached'
new_task cf "$tmp/cf3.md"
check 'an unreachable origin changes nothing' '0 T-CF-3' "$rc $id"

# --- task-new waits for the state lock another session holds ----------------------------
draft "$tmp/locked.md" cf 'written under a held lock'
before=$(commits)
(. "$bin/lib-tasks.sh"; state_lock "$st" && : > "$tmp/held" && exec sleep 30) &
holder=$!
n=0
until [ -e "$tmp/held" ] || [ "$n" -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
STATE_LOCK_WAIT=1 new_task cf "$tmp/locked.md"
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
check 'task-new does not run while another session holds the state lock' 1 "$rc"
check 'nothing is written under a held lock' '' "$(ls "$st"/repos/cf/tasks/ | grep held)"
check 'nothing is committed under a held lock' "$before" "$(commits)"

# --- the <new-id> placeholder of task-template.sh is replaced, not kept behind the id ------
draft "$tmp/placeholder.md" cf 'a branch with the template placeholder' 'feat/<new-id>-delete-and-search'
new_task cf "$tmp/placeholder.md"
check 'the <new-id> placeholder in the branch becomes the id' feat/T-CF-4-delete-and-search "$(field T-CF-4 branch)"

exit $fail
