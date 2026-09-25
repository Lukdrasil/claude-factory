#!/bin/sh
# Step 3 of _shared/investigate.md files the investigation report in the state clone and commits it there, so it
# reaches the state remote and not only the working tree of whatever session wrote it (sim F37).
set -u
f=$(CDPATH= cd -- "$(dirname -- "$0")/../skills/_shared" && pwd)/investigate.md

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

step3=$(awk '/^3\. / { on = 1 } /^4\. / { on = 0 } on' "$f" | tr '\n' ' ' | tr -s ' ')
printf '%s' "$step3" | grep -q 'research/<id>-investigation\.md'; check 'step 3 names the report path' $?
printf '%s' "$step3" | grep -q 'state-commit\.sh -m "research: <id>" --state "\$WORK_DIR/state" -- repos/<key>/research/<id>-investigation\.md'
check 'step 3 commits the report through state-commit.sh' $?
exit $fail
