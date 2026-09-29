#!/bin/sh
# The plugin runs one task in one session: no file of it names the Factory UI, the session org or the herdr lane, and
# `factory solve` takes a task in words, creates it and runs the loop through the human's gates only. The removed
# names are assembled from halves so this file is no hit of its own, and the grep first runs over a fixture repo
# holding one planted hit, so a grep that matches nothing cannot pass vacuously.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

gone='ui''-ask|ui''-session|ui''-up\.sh|ui''-down\.sh|ui''-relay|ask''-gate|herdr''-sound|factory''-start|FACTORY''_UI|ui: ''docker'
gone="$gone|FACTORY""_ROLE|org""-check|rearm""-check|queue""-next|task""-priority|herd""-list|capacity""\\.sh|map""\\.sh"
gone="$gone|session""-monitor|herd""-watch|herdr""-tabs|way""finder|references/(c""eo|le""ad|in""take|ro""ute|on""board|cross""-repo|he""rd)\\.md"
gone="$gone|state""-set\\.sh|the C""EO|skills/her""dr"
stale() { # <repo>
  git -C "$1" grep -nE "$gone" -- bin hooks skills agents tests README.md
}

fix="$tmp/fixture"
mkdir -p "$fix/skills"
printf 'ask through %s\n' 'ui''-ask.sh' > "$fix/skills/one.md"
git -C "$fix" init -q
git -C "$fix" add -A
stale "$fix" | grep -q '^skills/one.md:1:'; check 'the grep sees a planted hit' $?
out=$(stale "$root")
[ -z "$out" ]; check 'no file names the UI, the session org or the herdr lane' $?
[ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/  /'

for d in ui skills/way''finder skills/her''dr skills/factory''-start; do
  [ ! -e "$root/$d" ]; check "$d is gone" $?
done

skill="$root/skills/factory/SKILL.md"
solve="$root/skills/factory/references/solve.md"
grep -q 'text that$' "$skill" && grep -q 'names a task is `solve` with that text' "$skill"
check 'the factory skill hands text that names a task to solve' $?
start=$(awk '/^## / { on = ($0 == "## Start"); next } on { print }' "$solve")
printf '%s' "$start" | grep -q 'task-template\.sh task'; check 'the start of solve drafts the task from the template' $?
printf '%s' "$start" | grep -q 'task-new\.sh --repo <key> --state <state> --file <draft>'; check 'the start of solve creates it with task-new.sh' $?
printf '%s' "$start" | grep -q '/tmp/factory-intake-'; check 'the intake draft is written where the guard allows it' $?
printf '%s' "$start" | grep -q 'state-report\.sh --task <id> --owner <owner> --no-status'; check 'a resumed task is reclaimed first' $?
loop=$(awk '/^## / { on = ($0 == "## The loop"); next } on { print }' "$solve")
printf '%s' "$loop" | grep -q 'Do not stop between steps'; check 'the loop runs without stopping between steps' $?
for g in 'grill rounds' 'plan approval' 'a blocked or failed block' 'the task MR'; do
  printf '%s' "$loop" | grep -q "^| $g |"; check "the loop stops at the gate: $g" $?
done
after=$(awk '/^## / { on = ($0 == "## After the task MR"); next } on { print }' "$solve")
printf '%s' "$after" | grep -q 'mr-watch\.sh <T-id>'; check 'the merged task MR is watched with mr-watch.sh' $?
printf '%s' "$after" | grep -q 'references/done\.md'; check 'and closed through the done gate' $?

sh "$root/bin/solve-next.sh" T-001 --ui s1 >/dev/null 2>"$tmp/err"
[ $? = 1 ] && grep -q "unknown argument '--ui'" "$tmp/err"; check 'solve-next.sh takes no --ui' $?

exit "$fail"
