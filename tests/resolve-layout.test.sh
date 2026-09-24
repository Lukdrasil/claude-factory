#!/bin/sh
# resolve_layout (lib-tasks.sh), T-252-03: it answers only the standalone layout $W/<key>/T-NNN[-NN], and every
# other path under the work root returns 1 with all five LO_ fields empty.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/bin/lib-tasks.sh"
W=/work/factory

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
layout() { # <path>
  resolve_layout "$1" "$W"
  printf '%s|%s|%s|%s|%s|%s' "$?" "$LO_POSTURE" "$LO_TASK" "$LO_OWN" "$LO_STATE" "$LO_STAMP"
}

check 'a file in a task worktree' "0|standalone|T-001|$W/cf/T-001|$W/state|$W/cf/.harness/T-001" \
  "$(layout "$W/cf/T-001/src/a.sh")"
check 'a block worktree' "0|standalone|T-001-02|$W/cf/T-001-02|$W/state|$W/cf/.harness/T-001-02" \
  "$(layout "$W/cf/T-001-02")"
check 'a path outside the work root' '1|||||' "$(layout /elsewhere/cf/T-001)"

for p in "$W/state" "$W/state/repos/cf/tasks/T-001.md" "$W/cf" "$W/cf/src" "$W/cf/.harness/T-001" \
         "$W/T-001" "$W/T-001/src/a.sh" "$W/T-001/state"; do
  check "not a task worktree: ${p#"$W"/}" '1|||||' "$(layout "$p")"
done

exit "$fail"
