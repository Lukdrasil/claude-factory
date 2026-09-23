#!/bin/sh
# The grill file is written where a round ends: the interview loop paragraph that recomputes the frontier
# and Steps item 1 both name it, so a session that answers a round cannot skip the write (T-211).
set -u
skill=$(CDPATH= cd -- "$(dirname -- "$0")/../skills/grill" && pwd)/SKILL.md

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# paragraphs of `## Interview loop` that say to recompute the frontier
loop=$(awk '
  /^## / { in_loop = ($0 == "## Interview loop"); next }
  in_loop { if ($0 == "") { if (p ~ /[Rr]ecompute/) print p; p = "" } else p = p " " $0 }
  END { if (in_loop && p ~ /[Rr]ecompute/) print p }
' "$skill")
[ -n "$loop" ]; check 'the interview loop has a paragraph that recomputes the frontier' $?
printf '%s' "$loop" | grep -q -- '-grill\.md'; check 'that paragraph names the grill file' $?

# Steps item 1, up to item 2
step1=$(awk '
  /^## / { in_steps = ($0 == "## Steps"); next }
  in_steps && /^1\. / { on = 1 }
  in_steps && /^2\. / { on = 0 }
  on { print }
' "$skill")
[ -n "$step1" ]; check 'Steps has an item 1' $?
printf '%s' "$step1" | grep -q -- '-grill\.md'; check 'Steps item 1 names the grill file' $?

# the section keeps the resume rule and points the slug to references/output.md
section=$(awk '/^## / { on = ($0 == "## The grill file"); next } on { print }' "$skill")
printf '%s' "$section" | grep -q 'resume'; check 'the grill file section keeps the resume rule' $?
printf '%s' "$section" | grep -q 'references/output\.md'; check 'the grill file section points the slug to references/output.md' $?

exit "$fail"
