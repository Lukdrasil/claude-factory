#!/bin/sh
# attribution-gate.sh: a commit, a tag, an MR description or a progress file may not carry a co-author
# trailer, a session line or URL, a "generated with" line or the robot emoji; every other call passes.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail=0
try() { # <want exit> <label> <json payload>
  printf '%s' "$3" | sh "$root/bin/attribution-gate.sh" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'PASS %s\n' "$2"; else printf 'FAIL want=%s got=%s %s\n' "$1" "$got" "$2"; fail=1; fi
}
bash_payload() { node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]}}))' "$1"; }
write_payload() { node -e 'process.stdout.write(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:process.argv[2]}}))' "$1" "$2"; }

try 2 'a co-author trailer on a commit' "$(bash_payload 'git commit -m "feat: x

Co-Authored-By: Claude <noreply@anthropic.com>"')"
try 2 'a session line on a commit'      "$(bash_payload 'git commit -m "feat: x

Claude-Session: https://claude.ai/code/session_1"')"
try 2 'an attributed MR description'    "$(write_payload '/w/acme/T-001/.harness/T-001/mr.md' '**What changed** - x

Generated with [Claude Code]
')"
try 0 'a plain commit'                  "$(bash_payload 'git commit -m "feat(api): add the feed endpoint"')"
try 0 'an unrelated command'            "$(bash_payload 'ls -la')"
try 0 'a source file'                   "$(write_payload '/w/acme/T-001/src/A.cs' 'public class A { }')"
exit $fail
