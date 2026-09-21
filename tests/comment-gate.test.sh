#!/bin/sh
# comment-gate.sh: inside a task worktree a doc comment passes and every other comment line is denied.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state/repos/acme/tasks" "$tmp/acme/T-001/src"
printf 'id: T-001\nrepo: acme\n' > "$tmp/state/repos/acme/tasks/T-001.md"

fail=0
try() { # <want exit> <label> <file content>
  payload=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Write",cwd:process.argv[1]+"/acme/T-001",
    tool_input:{file_path:"src/A.cs",content:process.argv[2]}}))' "$tmp" "$3")
  printf '%s' "$payload" | WORK_DIR="$tmp" sh "$root/bin/comment-gate.sh" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'PASS %s\n' "$2"; else printf 'FAIL want=%s got=%s %s\n' "$1" "$got" "$2"; fail=1; fi
}

try 0 'doc comment on a public class'   '/// <summary>Reads a feed.</summary>
public class A { }
'
try 0 'no comment at all'               'public class A { }
'
try 2 'a why-prefixed line'             '// why: the upstream api is broken
public class A { }
'
try 2 'a plain comment'                 '// read the feed
public class A { }
'
try 2 'a commented-out line'            '// var a = 1;
public class A { }
'
exit $fail
