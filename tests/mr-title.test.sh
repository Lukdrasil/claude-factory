#!/bin/sh
# mr_title_check, the rule both MR scripts apply to a task's `# Goal` line before they call the forge: the
# default cap is the 100 of commitlint's config-conventional (MR !412 opened a 113-character title the product
# repo's own lint then refused), and the length is counted in characters, not bytes.
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

x() { printf 'x%.0s' $(seq 1 "$1"); }        # <n> x characters
acc() { printf '\303\251%.0s' $(seq 1 "$1"); } # <n> e-acute, one character and two bytes each

try ok  'feat(mr-open): cap the title at the repo commitlint cap'
try ok  'fix: a markdown-only block diff is green on zero tests'
try ok  'refactor(bin)!: drop the old spawn path'
try bad 'cap the title at 100 characters'
try bad 'feature(mr-open): wrong type'

# `feat(x): ` is 9 characters, so 91 more make 100 and 92 make 101
try ok  "feat(x): $(x 91)"
try bad "feat(x): $(x 92)"

# 100 characters, 191 bytes: a byte count would refuse this one
multi="feat(x): $(acc 91)"
try ok  "$multi"
[ "$(printf '%s' "$multi" | wc -c | tr -d '[:space:]')" -gt 100 ]
if [ $? -eq 0 ]; then printf 'PASS the multibyte title is over 100 bytes\n'; else printf 'FAIL the multibyte title is over 100 bytes\n'; fail=1; fi

# the title of MR !412 itself: 113 characters, Conventional Commits, and over the cap
try bad "fix(gateway): bind the gateway's OpenAPI document list to Core's registrations so a new document cannot be missed"

exit $fail
