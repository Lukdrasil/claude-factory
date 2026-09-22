#!/bin/sh
# policy-guard.sh holds a forge command that writes an MR title to the same rule mr-open.sh and block-mr.sh
# apply: Conventional Commits, and at most the cap of the repo the cwd belongs to (100 by default). The short
# `-t` counts as a title, and a title the guard cannot read out of the command is denied rather than passed.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
try() { # <want exit> <label> <command> [<WORK_DIR>]
  node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",cwd:process.argv[1],tool_input:{command:process.argv[2]}}))' \
    "$root" "$3" | WORK_DIR="${4:-/work}" sh "$root/bin/policy-guard.sh" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'PASS %s\n' "$2"; else printf 'FAIL want=%s got=%s %s\n' "$1" "$got" "$2"; fail=1; fi
}
long=$(printf 'add a really long title that keeps going %.0s' 1 2 3 4)
# 113 characters, Conventional Commits: what MR !412 opened, under the old 130 cap and over commitlint's 100
t190="fix(gateway): bind the gateway's OpenAPI document list to Core's registrations so a new document cannot be missed"

try 2 'an over-long title'          "glab mr create --source-branch x --target-branch main --title \"$long\" --description-file /tmp/d.md --yes"
try 2 'a non-conventional title'    'glab mr create --source-branch x --target-branch main --title "not conventional at all" --description-file /tmp/d.md --yes'
try 2 'a sloppy retitle'            'gh pr edit 4 --title "sloppy retitle"'
try 0 'a conventional glab title'   'glab mr create --source-branch x --target-branch main --title "feat(factory): a proper title" --description-file /tmp/d.md --yes'
try 0 'a conventional gh title'     "gh pr create --base main --title 'fix(gate): another proper one' --body-file /tmp/d.md"
try 0 'no title at all'             'gh pr create --base main --fill'
try 2 'the short -t flag'           'glab mr create --source-branch x --target-branch main -t "bad title" --yes'
try 0 'a proper title behind -t'    'glab mr create --source-branch x --target-branch main -t "feat(gate): a proper title" --yes'
try 2 'a title in a variable'       'glab mr create --source-branch x --target-branch main --title "$T" --yes'
try 2 'a title in a substitution'   'gh pr create --base main --title "$(head -n1 goal.txt)" --body-file /tmp/d.md'
try 2 'a bad title through the api' 'glab api projects/1/merge_requests -f title="sloppy retitle" -f source_branch=x'
try 0 'a good title through the api' 'glab api projects/1/merge_requests -f title="feat(api): a proper title" -f source_branch=x'
try 2 'the 113-character title of MR !412' "glab mr create --source-branch x --target-branch main --title \"$t190\" --yes"

# the repo's own cap wins over the default: repos.yml maps this cwd to a key whose mr_title_max is 130
mkdir -p "$tmp/state"
printf 'demo: {url: "https://forge.test/demo.git", default_branch: main, path: "%s", mr_title_max: 130}\n' "$root" > "$tmp/state/repos.yml"
try 0 'the repo mr_title_max of 130' "glab mr create --source-branch x --target-branch main --title \"$t190\" --yes" "$tmp"

exit $fail
