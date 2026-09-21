#!/bin/sh
# policy-guard.sh holds a forge command that writes an MR title to the same rule mr-open.sh and block-mr.sh
# apply: Conventional Commits, at most 130 characters. A command with no title, or a title it cannot extract,
# is not denied.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail=0
try() { # <want exit> <label> <command>
  node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",cwd:process.argv[1],tool_input:{command:process.argv[2]}}))' \
    "$root" "$3" | sh "$root/bin/policy-guard.sh" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'PASS %s\n' "$2"; else printf 'FAIL want=%s got=%s %s\n' "$1" "$got" "$2"; fail=1; fi
}
long=$(printf 'add a really long title that keeps going %.0s' 1 2 3 4)

try 2 'an over-long title'          "glab mr create --source-branch x --target-branch main --title \"$long\" --description-file /tmp/d.md --yes"
try 2 'a non-conventional title'    'glab mr create --source-branch x --target-branch main --title "not conventional at all" --description-file /tmp/d.md --yes'
try 2 'a sloppy retitle'            'gh pr edit 4 --title "sloppy retitle"'
try 0 'a conventional glab title'   'glab mr create --source-branch x --target-branch main --title "feat(factory): a proper title" --description-file /tmp/d.md --yes'
try 0 'a conventional gh title'     "gh pr create --base main --title 'fix(gate): another proper one' --body-file /tmp/d.md"
try 0 'no title at all'             'gh pr create --base main --fill'
exit $fail
