#!/bin/sh
# Counts one memory scope's top-level *.md — lessons and words — and warns "over budget" when lessons > 40 or
# words > 3000, whichever first (T-012). Scopes: repo:<key>, global, agent:<name>. --all reports every scope
# present in the state repo. Exit 0 always, even for a scope with no memory dir at all (0 lessons, 0 words).
#
#   memory-budget.sh <scope> [--state <dir>]
#   memory-budget.sh --all [--state <dir>]
set -eu

scope='' state='' all=0
die() { printf 'memory-budget: %s\n' "$1" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: memory-budget.sh <scope>|--all [--state <dir>]"
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --all) all=1; shift ;;
    -*) die "unknown argument '$1'" ;;
    *)
      [ -z "$scope" ] || die "too many arguments"
      scope=$1; shift ;;
  esac
done
[ -n "$state" ] || state=$(pwd)

scope_dir() { # <scope> → the memory dir relative to $state, nothing when the scope is malformed
  case "$1" in
    repo:*) printf '%s\n' "repos/${1#repo:}/memory" ;;
    global) printf '%s\n' "memory/global" ;;
    agent:*) printf '%s\n' "agents/${1#agent:}/memory" ;;
  esac
}

report() { # <scope>
  name=$1
  dir=$(scope_dir "$name")
  [ -n "$dir" ] || die "unknown scope '$name' — one of repo:<key>, global, agent:<name>"
  lessons=0 words=0
  if [ -d "$state/$dir" ]; then
    set -- "$state/$dir"/*.md
    [ -e "$1" ] || set --
    lessons=$#
    [ $# -eq 0 ] || words=$(LC_ALL=C.UTF-8 wc -w -- "$@" | awk 'END { print $1 }')
  fi
  printf '%s %s lessons %s words\n' "$name" "$lessons" "$words"
  if [ "$lessons" -gt 40 ] || [ "$words" -gt 3000 ]; then printf 'over budget\n'; fi
}

if [ "$all" = 1 ]; then
  for d in "$state"/repos/*/memory; do
    [ -d "$d" ] || continue
    key=${d%/memory}; key=${key##*/}
    report "repo:$key"
  done
  [ ! -d "$state/memory/global" ] || report global
  for d in "$state"/agents/*/memory; do
    [ -d "$d" ] || continue
    name=${d%/memory}; name=${name##*/}
    report "agent:$name"
  done
else
  [ -n "$scope" ] || die "usage: memory-budget.sh <scope>|--all [--state <dir>]"
  report "$scope"
fi
exit 0
