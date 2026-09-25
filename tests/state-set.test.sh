#!/bin/sh
# state-set.sh over a throwaway state clone: a cap of factory.yml in the flow and the block spelling of
# factory-init.sh, a new role added to the roles: map, a repo's default_branch: flat and indented, each one
# commit; the same value commits nothing, and a bad value, an unknown name or key write nothing.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/state"
mkdir -p "$state"
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
printf '%s\n' 'ui: docker' 'capacity:' '  sessions: 10' \
  '  roles: {repo-lead: 3, scout: 8, implementer: 4,' '          implementer-senior: 2, code-reviewer: 2}' 'ui_port: 7171' \
  > "$state/factory.yml"
printf '%s\n' 'demo: {url: "https://x/demo.git", default_branch: main, path: "/src/demo", alias: DEM}' \
  'other:' '  url: https://x/other.git' '  default_branch: main' '  path: /src/other' > "$state/repos.yml"
git -C "$state" add -A
git -C "$state" commit -q -m init

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
set_() { out=$(sh "$bin/state-set.sh" "$@" --state "$state" 2>&1); rc=$?; }
commits() { git -C "$state" rev-list --count HEAD; }
caps() { sed -n '/^capacity:/,/^ui_port:/p' "$state/factory.yml" | tr -s ' \n' ' '; }

set_ capacity implementer 6
check 'a cap is set'                                   0 "$rc"
check 'it prints the name and the cap'                 'implementer 6' "$out"
check 'only implementer changes, not implementer-senior' \
  'capacity: sessions: 10 roles: {repo-lead: 3, scout: 8, implementer: 6, implementer-senior: 2, code-reviewer: 2} ui_port: 7171 ' "$(caps)"
check 'it is one commit'                               2 "$(commits)"
check 'the tree is clean'                              '' "$(git -C "$state" status --porcelain)"
set_ capacity sessions 12
check 'sessions in the block spelling is set'          yes "$(grep -q '^  sessions: 12$' "$state/factory.yml" && echo yes)"
set_ capacity sessions 12
check 'the same value commits nothing'                 3 "$(commits)"
set_ capacity researcher 4
check 'a role with no cap is added to the roles map'   yes "$(grep -q 'code-reviewer: 2, researcher: 4}$' "$state/factory.yml" && echo yes)"
check 'the added role reads as a cap to capacity.sh'   '0/4' "$(sh "$bin/capacity.sh" count researcher --state "$state" 2>/dev/null)"
set_ capacity implementer 100
check 'a cap over 99 is refused'                       1 "$rc"
set_ capacity 'bad/role' 2
check 'a role name with a slash is refused'            1 "$rc"
check 'nothing refused was committed'                  4 "$(commits)"

set_ default-branch demo develop
check 'a flat default_branch is set'                   0 "$rc"
check 'the flat line keeps its other fields' \
  'demo: {url: "https://x/demo.git", default_branch: develop, path: "/src/demo", alias: DEM}' "$(sed -n 1p "$state/repos.yml")"
set_ default-branch other release/2.0
check 'an indented default_branch is set'              '  default_branch: release/2.0' "$(sed -n 4p "$state/repos.yml")"
set_ default-branch demo 'bad..name'
check 'a name git would not take is refused'           1 "$rc"
set_ default-branch nope develop
check 'an unknown key is refused'                      1 "$rc"
check 'and names it'                                   yes "$(printf '%s' "$out" | grep -q 'nope is not in' && echo yes)"
check 'two default_branch commits'                     6 "$(commits)"

exit $fail
