#!/bin/sh
# The twin of session-start.sh's memory injection, but for an agent's own memory (T-012): agent definitions are
# read-only plugin files, so an agent's memory reaches a spawn through this script instead of a generated file.
# Prints skills/_shared/rules.md first, so the rules that hold in every spawn are carried by the brief instead
# of by each agent file, then the top-level agents/<agent>/memory/*.md, sorted, each preceded by a
# `<!-- agents/<agent>/memory/<file> -->` marker, never proposals/. An agent with no memory dir at all still
# gets the rules block, exit 0.
#
#   agent-brief.sh <agent> [--state <dir>]
set -eu

agent='' state=''
die() { printf 'agent-brief: %s\n' "$1" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: agent-brief.sh <agent> [--state <dir>]"
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *)
      [ -z "$agent" ] || die "too many arguments"
      agent=$1; shift ;;
  esac
done
[ -n "$agent" ] || die "usage: agent-brief.sh <agent> [--state <dir>]"
[ -n "$state" ] || state=$(pwd)

rules="$(dirname -- "$0")/../skills/_shared/rules.md"
if [ -f "$rules" ]; then
  printf '<!-- skills/_shared/rules.md -->\n\n'
  cat "$rules"
  printf '\n'
fi

dir="agents/$agent/memory"
[ -d "$state/$dir" ] || exit 0
for f in $(cd "$state/$dir" && ls -1 2>/dev/null | grep '\.md$' | LC_ALL=C sort); do
  [ -f "$state/$dir/$f" ] || continue
  printf '<!-- %s/%s -->\n\n' "$dir" "$f"
  cat "$state/$dir/$f"
  printf '\n'
done
exit 0
