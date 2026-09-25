#!/bin/sh
# dag-check.sh over a throwaway state clone of a repo whose files sit at its root: a design heading claims its
# file with or without a `/`, a backticked Docs token claims a file when it has a `/` or a file extension, and a
# Docs token that is a symbol or a call stays prose.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/state"
tasks="$state/repos/notes/tasks"
mkdir -p "$tasks"
printf -- '---\nid: T-001\nrepo: notes\nstatus: in_progress\n---\n\n# Goal\nfeat(notes): the parent\n' > "$tasks/T-001.md"

block() { # <id> <design heading> <docs line> [depends_on]
  printf -- '---\nid: %s\nrepo: notes\nstatus: draft\ndepends_on: [%s]\n---\n\n# Goal\nfeat(notes): %s\n\nDesign (approved in the grill):\n### `%s` (existing)\nexport function remove(file, id)\n\n## Acceptance\n`node --test`\n\n## Docs\n%s\n' \
    "$1" "${4:-}" "$1" "$2" "$3" > "$tasks/$1.md"
}

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
dag() { rc=0; out=$(sh "$bin/dag-check.sh" T-001 --state "$state" 2>&1) || rc=$?; }

block T-001-01 notes.js 'README.md (the API sentence gains `remove(file, id)`)'
dag
check 'a root-level design heading is a claim' '0 wave 1: T-001-01' "$rc $out"

block T-001-01 notes.js '`README.md` gains `remove(file, id)`'
block T-001-02 cli.js '`README.md` gains the remove command'
dag
check 'a backticked root-level doc with an extension is a claim' 1 "$rc"
check 'the overlap names the doc' yes "$(printf '%s' "$out" | grep -q 'README.md' && echo yes || echo no)"

block T-001-02 notes.js '`search(file, term)` and `--state` are not files'
dag
check 'two blocks on one root-level file overlap' 1 "$rc"
check 'the overlap names the file' yes "$(printf '%s' "$out" | grep -q 'notes.js' && echo yes || echo no)"

block T-001-02 cli.js '`search(file, term)` and `--state` are not files'
dag
check 'a symbol or a flag in Docs is prose' '0 wave 1: T-001-01 T-001-02' "$rc $out"

exit $fail
