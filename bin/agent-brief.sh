#!/bin/sh
# The twin of session-start.sh's memory injection, but for an agent's own memory (T-012): agent definitions are
# read-only plugin files, so an agent's memory reaches a spawn through this script instead of a generated file.
# Prints skills/_shared/rules.md first, so the rules that hold in every spawn are carried by the brief instead
# of by each agent file, then the top-level agents/<agent>/memory/*.md, sorted, each preceded by a
# `<!-- agents/<agent>/memory/<file> -->` marker, never proposals/, then the playbook of the repo key
# (agent-org plan 3.8), `repos/<key>/agents/<agent>/playbook.md` under its own marker, when the state has one.
# The key is --key, else the key of the cwd the way playbook-inject.sh finds it: a task worktree
# <root>/<key>/<T-id>, then the clone whose repos.yml `path:` holds the cwd; researcher-s0..s3 read researcher's
# playbook. An agent with no memory dir and no playbook still gets the rules block, exit 0.
#
#   agent-brief.sh <agent> [--key <key>] [--state <dir>]
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

agent='' state='' key=''
die() { printf 'agent-brief: %s\n' "$1" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: agent-brief.sh <agent> [--key <key>] [--state <dir>]"
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --key) [ $# -ge 2 ] || die "--key needs a value"; key=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *)
      [ -z "$agent" ] || die "too many arguments"
      agent=$1; shift ;;
  esac
done
[ -n "$agent" ] || die "usage: agent-brief.sh <agent> [--key <key>] [--state <dir>]"
[ -n "$state" ] || state=$(pwd)

rules="$(dirname -- "$0")/../skills/_shared/rules.md"
if [ -f "$rules" ]; then
  printf '<!-- skills/_shared/rules.md -->\n\n'
  cat "$rules"
  printf '\n'
fi

dir="agents/$agent/memory"
if [ -d "$state/$dir" ]; then
  for f in $(cd "$state/$dir" && ls -1 2>/dev/null | grep '\.md$' | LC_ALL=C sort); do
    [ -f "$state/$dir/$f" ] || continue
    printf '<!-- %s/%s -->\n\n' "$dir" "$f"
    cat "$state/$dir/$f"
    printf '\n'
  done
fi

if [ -z "$key" ]; then
  here=$(pwd)
  if resolve_cwd_layout "$here"; then key=${LO_OWN%/*}; key=${key##*/}; else key=$(repo_key_of_cwd "$here") || key=''; fi
fi
role=${agent#claude-factory:}
case "$role" in researcher-s[0-9]*) role=researcher ;; esac
pb="repos/$key/agents/$role/playbook.md"
if [ -n "$key" ] && [ -f "$state/$pb" ]; then
  printf '<!-- %s -->\n\n' "$pb"
  cat "$state/$pb"
  printf '\n'
fi
exit 0
