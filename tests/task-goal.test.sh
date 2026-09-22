#!/bin/sh
# The `# Goal` line is the MR title, and it is judged while the task is authored, not at the forge (MR !412):
# task-new.sh refuses a draft whose goal is over the repo's cap, task-approve.sh refuses to approve one, and a
# triage goal - which never becomes a title - is left alone.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/state"
mkdir -p "$state/repos/userorg/tasks"
printf 'userorg: {url: "https://forge.test/userorg.git", default_branch: main, path: "%s"}\n' "$tmp/userorg" \
  > "$state/repos.yml"
git -C "$state" init -q
git -C "$state" add -A
git -C "$state" -c user.name=t -c user.email=t@t commit -q -m init

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# `fix(gateway): ` is 14 characters; 99 more make the 113 of MR !412, 86 make the 100 that just fits
x() { printf 'x%.0s' $(seq 1 "$1"); }
g113="fix(gateway): $(x 99)"
g100="fix(gateway): $(x 86)"

draft() { # <file> <archetype> <goal>
  cat > "$1" <<EOF
---
id: T-001
repo: userorg
branch: fix/a-goal-that-is-too-long
status: draft
tier: green
archetype: $2
complexity: low
---

# Goal
$3

## Context
A draft written by hand, the way triage writes one.

## Acceptance
\`test -f README.md\`
EOF
}

draft "$tmp/long.md" bugfix "$g113"
out=$(sh "$bin/task-new.sh" --repo userorg --state "$state" --file "$tmp/long.md" 2>&1)
[ $? -ne 0 ]; check 'task-new refuses a 113-character bugfix goal' $?
printf '%s\n' "$out" | grep -q 'the title is 113 characters and the cap is 100'; check 'the refusal names the length and the cap' $?
[ -z "$(ls "$state/repos/userorg/tasks")" ]; check 'the refusal writes no task file' $?

draft "$tmp/ok.md" bugfix "$g100"
sh "$bin/task-new.sh" --repo userorg --state "$state" --file "$tmp/ok.md" >/dev/null 2>"$tmp/err"
check 'task-new accepts a 100-character bugfix goal' $?
[ -s "$tmp/err" ] && cat "$tmp/err"

# a triage goal is a note to the next session, never an MR title, so the rule does not reach it
cat > "$tmp/triage.md" <<EOF
---
id: T-001
repo: userorg
status: draft
tier: green
archetype: triage
complexity: low
---

# Goal
$g113 and it keeps going well past any title

## Context
Triage of one forge issue.
EOF
sh "$bin/task-new.sh" --repo userorg --state "$state" --file "$tmp/triage.md" >/dev/null 2>"$tmp/err2"
check 'task-new accepts a long triage goal' $?
[ -s "$tmp/err2" ] && cat "$tmp/err2"

# approve: the same rule, on the body the human is about to freeze with plan_hash
task=$(grep -rl 'archetype: bugfix' "$state/repos/userorg/tasks" | head -n1)
id=$(sed -n 's/^id:[[:space:]]*//p' "$task" | head -n1)
sed "s|^$g100\$|$g113|" "$task" > "$task.tmp" && mv -f "$task.tmp" "$task"
grep -q "$g113" "$task"; check 'the goal was lengthened in the task file' $?
out=$(sh "$bin/task-approve.sh" "$id" --state "$state" 2>&1)
[ $? -ne 0 ]; check 'task-approve refuses a 113-character goal' $?
printf '%s\n' "$out" | grep -q 'the title is 113 characters and the cap is 100'; check 'the approve refusal names the cap' $?
grep -q '^status: draft' "$task"; check 'the refused approve left the status alone' $?
grep -q '^plan_hash: null' "$task"; check 'the refused approve pinned no plan_hash' $?

exit $fail
