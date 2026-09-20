#!/bin/sh
# mr_title_check, the rule both MR scripts apply to a task's `# Goal` line before they call the forge.
set -u
. "$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)/lib-tasks.sh"

fail=0
try() { # <ok|bad> <title>
  if reason=$(mr_title_check "$2"); then got=ok; else got=bad; fi
  if [ "$got" = "$1" ]; then
    printf 'PASS %-3s %.55s\n' "$1" "$2"
  else
    printf 'FAIL want=%s got=%s %.55s (%s)\n' "$1" "$got" "$2" "${reason:-}"
    fail=1
  fi
}

try ok  'feat(mr-open): cap the title at 130 characters'
try ok  'fix: a markdown-only block diff is green on zero tests'
try ok  'refactor(bin)!: drop the old spawn path'
try bad 'cap the title at 130 characters'
try bad 'feature(mr-open): wrong type'
try bad "feat(mr-open): $(printf 'x%.0s' $(seq 1 130))"
exit $fail
