#!/bin/sh
# The local twin of `factory done` (T-007), run after the human validated the MR: flips the parent and every
# T-NNN-NN block to status: done in one commit. Refuses (nothing written) when the parent's mr_url is null or
# empty — blocks never carry their own mr_url (ADR-0051), so only the parent's is checked.
#
#   task-done.sh <T-NNN> [--state <dir>]      cwd = the state clone unless --state
#
# Exit 1 with the reason when the parent has no mr_url; nothing written.
set -eu

id='' state=''
die() { printf 'task-done: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one task id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: task-done.sh <T-NNN> [--state <dir>]"
[ -n "$state" ] || state=$(pwd)
[ -d "$state/.git" ] || die "$state is not a state clone — run from one or pass --state <dir>"

parent=$(grep -lx "id: $id" "$state"/repos/*/tasks/*.md 2>/dev/null | head -n1)
[ -n "${parent:-}" ] && [ -f "$parent" ] || die "no task file with 'id: $id' in $state/repos/*/tasks/"

mr_url=$(sed -n 's/^mr_url:[[:space:]]*//p' "$parent" | head -n1)
[ "$mr_url" != null ] && [ -n "$mr_url" ] || die "task $id has no mr_url — factory done runs only after the MR is validated"

# every block of this parent: T-NNN-NN task files, sorted for a stable diff
blocks=$(grep -lx "id: $id-[0-9][0-9]" "$state"/repos/*/tasks/*.md 2>/dev/null | sort || :)

# setf — the one frontmatter writer, shared with state-report.sh (T-007 review)
. "$(dirname -- "$0")/lib-tasks.sh"

setf "$parent" status done
rel_parent=${parent#"$state/"}
git -C "$state" add -- "$rel_parent"

if [ -n "$blocks" ]; then
  printf '%s\n' "$blocks" | while IFS= read -r block; do
    setf "$block" status done
    git -C "$state" add -- "${block#"$state/"}"
  done
fi

if [ -n "$(git -C "$state" config user.email || :)" ]; then
  git -C "$state" commit -q -m "chore($id): review → done, blocks included"
else
  git -C "$state" -c user.name=harness -c user.email=harness@localhost commit -q -m "chore($id): review → done, blocks included"
fi
