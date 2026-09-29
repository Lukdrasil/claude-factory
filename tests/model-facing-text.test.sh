#!/bin/sh
# T-252-05: no skill, agent, prompt, README line, script comment or user-facing message describes the
# dashboard, the controller, the watchdog, the worker layout or claude-os code, and prompts/ is gone. Each check
# is one grep of the task's acceptance, run as written; the patterns of the two greps that scan tests/ are
# assembled from halves so this file is no hit of its own. Every grep first runs over a fixture repo holding one
# planted hit, so a grep that matches nothing cannot pass vacuously.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

g1='DASH''BOARD_URL|DASH''BOARD_API_TOKEN|HARNESS''_WORKER|STATE_REPORT''_CURL|forge''-guard|rc''-ctl'
g2='Claude''Os|Dispatch''Gate|Task''Transitions|Task''Writer|Task''Schema|State''Repository|Orches''trator|Forge''Parsing|ClaudeMd''Builder|RcBrief''Builder|prepare''_task'
g5='Started by the controller|in a worker session|os-task|Never (write )?.done.*in_progress|belong to the controller|the watchdog|## Forge in CLAUDE|generated CLAUDE.md|worker-system-prompt'

stale() { # <repo> <grep 1-5>
  case $2 in
    1) git -C "$1" grep -nE "$g1" -- bin hooks skills agents prompts tests README.md ;;
    2) git -C "$1" grep -nE "$g2" -- bin hooks skills agents tests ':!skills/architecture-docs/references/database-products.md' ;;
    3) git -C "$1" grep -n 'docs/design/' -- bin skills/factory ;;
    4) git -C "$1" grep -nE '\.\./state\b' -- skills agents ;;
    5) git -C "$1" grep -nE "$g5" -- skills agents prompts README.md bin ;;
  esac
}

fix="$tmp/fixture"
mkdir -p "$fix/bin" "$fix/skills/factory" "$fix/skills/architecture-docs/references"
printf '# reads %s_URL\n' 'DASHBOARD' > "$fix/bin/one.sh"
printf 'class %s\n' 'Orches''trator' > "$fix/skills/two.md"
printf 'the %s tool\n' 'Orches''trator' > "$fix/skills/architecture-docs/references/database-products.md"
printf 'see docs/design/toolset.md\n' > "$fix/skills/factory/three.md"
printf 'read ../state/repos.yml\n' > "$fix/skills/four.md"
printf 'Merge in a worker session\n' > "$fix/README.md"
git -C "$fix" init -q
git -C "$fix" add -A

stale "$fix" 1 | grep -q '^bin/one.sh:1:'; check 'grep 1 sees a planted hit' $?
out=$(stale "$fix" 2)
printf '%s\n' "$out" | grep -q '^skills/two.md:1:'; check 'grep 2 sees a planted hit' $?
! printf '%s\n' "$out" | grep -q 'database-products'; check 'grep 2 skips database-products.md' $?
stale "$fix" 3 | grep -q '^skills/factory/three.md:1:'; check 'grep 3 sees a planted hit' $?
stale "$fix" 4 | grep -q '^skills/four.md:1:'; check 'grep 4 sees a planted hit' $?
stale "$fix" 5 | grep -q '^README.md:1:'; check 'grep 5 sees a planted hit' $?

for n in 1 2 3 4 5; do
  out=$(stale "$root" "$n")
  [ -z "$out" ]; check "acceptance grep $n prints nothing" $?
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/  /'
done

[ ! -e "$root/prompts/worker-system-prompt.md" ]; check 'prompts/worker-system-prompt.md is deleted' $?

exit "$fail"
