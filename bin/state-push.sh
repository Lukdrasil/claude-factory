#!/bin/sh
# The push of a state clone to its state root, taken out of every writer: state-report.sh, task-done.sh,
# state-commit.sh and the other writers commit locally under the state lock and return, and this script, run in
# the background by the monitor pass and the CEO loop, carries the commits to the root. It never runs under the
# write lock and never waits for another push: its own lock is <git-dir>/factory-push.lock taken with flock -n
# (a mkdir lock where flock is missing, the way state_lock falls back), and a push already running means this one
# has nothing to do.
#
#   state-push.sh [--state <dir>]
#
# Fetch, and rebase only when the remote moved; the rebase alone runs under the state lock, because it rewrites
# the branch the writers commit on. Never an autostash and never a hard reset: a working tree with another
# session's uncommitted edit is not rebased, and a rebase that conflicts is aborted, so every local commit and
# every uncommitted edit stays exactly where it was. The next pass tries again.
#
# A rebase that conflicts is not solved by trying again, so it leaves the marker <git-dir>/factory-push.blocked:
# its first line the reason, one conflicting path per line after it. Every pass that refuses while the marker
# exists prints it on stderr after its own reason, and a pass that finds nothing left to push or pushes removes
# it; the conflict itself is resolved by hand (rebase the clone onto origin, or drop the local commit).
#
# Exit 0 = pushed, nothing to push, no origin (the clone is the state root itself), or another push holds the
# lock; 1 = the push did not land (refused, unreachable, or the rebase could not run), the commits stay local.
set -eu

state=''
die() { printf 'state-push: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    *) die "unknown argument '$1'; usage: state-push.sh [--state <dir>]" ;;
  esac
done

. "$(dirname -- "$0")/lib-tasks.sh"

[ -n "$state" ] || state=$(resolve_state_dir "$PWD")
state=$(git -C "$state" rev-parse --show-toplevel 2>/dev/null) || die "$state is not a state clone, pass --state <dir>"
git -C "$state" remote get-url origin >/dev/null 2>&1 || exit 0
gd=$(git -C "$state" rev-parse --path-format=absolute --git-dir)
blocked="$gd/factory-push.blocked"
die() {
  printf 'state-push: %s\n' "$1" >&2
  [ ! -f "$blocked" ] || sed "s|^|state-push: blocked ($blocked): |" "$blocked" >&2
  exit 1
}

# one push at a time per clone; a held lock is a push already on its way
if command -v flock >/dev/null 2>&1; then
  exec 8>"$gd/factory-push.lock" || die "the push lock $gd/factory-push.lock could not be opened"
  flock -n 8 || exit 0
else
  pl="$gd/factory-push.lockdir"
  if ! mkdir "$pl" 2>/dev/null; then
    pl_since=$(cat "$pl/since" 2>/dev/null || :)
    case "$pl_since" in *[!0-9]*) pl_since='' ;; esac
    # a push that died mid-way leaves its directory; it is taken over once it is 120 s old
    [ -n "$pl_since" ] && [ $(( $(date +%s) - pl_since )) -ge 120 ] || exit 0
    rm -rf "$pl"
    mkdir "$pl" 2>/dev/null || exit 0
  fi
  date +%s > "$pl/since"
  trap 'rm -rf "$pl"' EXIT
fi

branch=$(git -C "$state" symbolic-ref -q --short HEAD) || die "HEAD of $state is detached, there is no branch to push"
up="refs/remotes/origin/$branch"

# nothing new since the last push this clone knows of: no network at all
if git -C "$state" rev-parse -q --verify "$up" >/dev/null && git -C "$state" merge-base --is-ancestor HEAD "$up"; then
  rm -f "$blocked"
  exit 0
fi

git -C "$state" fetch -q origin 2>/dev/null || die "the fetch from origin failed, the commits of $state stay local"

if git -C "$state" rev-parse -q --verify "$up" >/dev/null; then
  if git -C "$state" merge-base --is-ancestor HEAD "$up"; then rm -f "$blocked"; exit 0; fi
  if ! git -C "$state" merge-base --is-ancestor "$up" HEAD; then
    # the remote moved: rebase onto it under the state lock, no writer commits while the branch is rewritten
    state_lock "$state" && lrc=0 || lrc=$?
    [ "$lrc" = 0 ] || die "the state lock of $state was busy, the rebase onto origin/$branch waits for the next pass"
    if [ -n "$(git -C "$state" status --porcelain --untracked-files=no)" ]; then
      state_unlock
      die "origin/$branch moved and $state has uncommitted edits; no autostash, the commits stay local until the tree is clean"
    fi
    if ! git -C "$state" -c rebase.autoStash=false rebase -q "$up" >/dev/null 2>&1; then
      {
        printf 'the rebase onto origin/%s conflicts (%s), resolve it by hand; the conflicting paths:\n' "$branch" "$(date '+%Y-%m-%d %H:%M')"
        git -C "$state" diff --name-only --diff-filter=U
      } > "$blocked" 2>/dev/null || :
      git -C "$state" rebase --abort >/dev/null 2>&1 || :
      state_unlock
      die "the rebase onto origin/$branch conflicts, it was aborted; the commits of $state stay local"
    fi
    state_unlock
  fi
fi

git -C "$state" push -q origin "HEAD:refs/heads/$branch" >/dev/null 2>&1 \
  || die "the state root refused the push, the commits of $state stay local"
rm -f "$blocked"
