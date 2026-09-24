#!/bin/sh
# The one way an agent commits its own files in the state clone (a research report, an ADR or memory proposal, a
# plan): under the state lock every writer shares (state_lock, lib-tasks.sh) and scoped to the paths it names, so
# another session's uncommitted edit in the same working tree never rides along and is never touched. It does not
# push; the push to the state root is state-push.sh's, run in the background by the monitor pass and the CEO loop.
# The task's status and progress file still go through state-report.sh, which validates the transition.
#
#   state-commit.sh -m <message> [--state <dir>] -- <path>...
#
# A path is relative to the state clone, or absolute inside it. --state defaults to the clone resolve_state_dir
# (lib-tasks.sh) finds from the cwd, the rule state-report.sh uses.
#
# Exit 0 = committed, or nothing to commit; 1 = refused (usage, a path outside the clone), nothing written;
# 2 = not committed (another session held the state lock for longer than STATE_LOCK_WAIT seconds, default 30, or
# git refused the commit).
set -eu

msg='' state=''
die() { printf 'state-commit: %s\n' "$1" >&2; exit 1; }
die2() { printf 'state-commit: %s\n' "$1" >&2; exit 2; }
usage='usage: state-commit.sh -m <message> [--state <dir>] -- <path>...'

while [ $# -gt 0 ]; do
  case "$1" in
    -m) [ $# -ge 2 ] || die "-m needs a message"; msg=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --) shift; break ;;
    *) die "unknown argument '$1'; $usage" ;;
  esac
done
[ -n "$msg" ] || die "no -m; $usage"
[ $# -gt 0 ] || die "no path after --; $usage"

. "$(dirname -- "$0")/lib-tasks.sh"

[ -n "$state" ] || state=$(resolve_state_dir "$PWD")
state=$(git -C "$state" rev-parse --show-toplevel 2>/dev/null) || die "$state is not a state clone, pass --state <dir>"

# the paths as the clone sees them: an absolute one has to be inside it
n=$#
while [ "$n" -gt 0 ]; do
  p=$1
  shift
  case "$p" in
    "$state"/?*) p=${p#"$state"/} ;;
    /*) die "$p is outside the state clone $state" ;;
  esac
  set -- "$@" "$p"
  n=$((n - 1))
done

state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die2 "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was committed, run it again" ;;
  *) die2 "the state lock could not be taken in $state, is it a git clone?" ;;
esac
state_commit "$state" "$msg" "$@" || die2 "git refused the commit in $state, nothing was committed"
