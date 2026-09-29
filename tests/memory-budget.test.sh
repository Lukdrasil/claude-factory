#!/bin/sh
# memory-budget.sh and the repo x agent tier (agent-org plan 3.5, 3.8): scope repo-agent:<key>/<agent> counts
# repos/<key>/agents/<agent>/memory/*.md, never its proposals/, --all reports every such scope, a malformed one
# is refused, and the older scopes read as before.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

st=$tmp/state
ra=repos/demo/agents/implementer/memory
mkdir -p "$st/$ra/proposals" "$st/repos/demo/memory" "$st/memory/global" "$st/agents/scout/memory" \
  "$st/repos/demo/agents/scout/drafts"
printf 'one two three\n' > "$st/$ra/a.md"
printf 'four five\n' > "$st/$ra/b.md"
printf 'not counted at all\n' > "$st/$ra/proposals/c.md"
printf 'daily: never\nweekly: never\n' > "$st/repos/demo/agents/implementer/passes.yml"
printf 'repo lesson\n' > "$st/repos/demo/memory/r.md"
printf 'global lesson\n' > "$st/memory/global/g.md"

mb() { sh "$bin/memory-budget.sh" "$@" --state "$st"; }

check 'repo-agent scope counts its top-level lessons and words' 'repo-agent:demo/implementer 2 lessons 5 words' \
  "$(mb repo-agent:demo/implementer)"
check 'a repo-agent scope with no memory dir is 0 and 0' 'repo-agent:demo/scout 0 lessons 0 words' \
  "$(mb repo-agent:demo/scout)"
check 'repo scope unchanged' 'repo:demo 1 lessons 2 words' "$(mb repo:demo)"
check 'global scope unchanged' 'global 1 lessons 2 words' "$(mb global)"
check 'agent scope unchanged' 'agent:scout 0 lessons 0 words' "$(mb agent:scout)"
check '--all lists the repo-agent scope' 'repo:demo 1 lessons 2 words
repo-agent:demo/implementer 2 lessons 5 words
global 1 lessons 2 words
agent:scout 0 lessons 0 words' "$(mb --all)"

for bad in repo-agent:demo repo-agent:demo/ repo-agent:/implementer repo-agent:demo/a/b 'repo-agent:../x/y'; do
  mb "$bad" >/dev/null 2>&1; rc=$?
  check "malformed scope $bad is refused" 1 "$rc"
done

i=0
while [ "$i" -lt 41 ]; do printf 'w\n' > "$st/$ra/n$i.md"; i=$((i + 1)); done
check 'over 40 lessons is over budget' 'over budget' "$(mb repo-agent:demo/implementer | sed -n 2p)"

exit "$fail"
