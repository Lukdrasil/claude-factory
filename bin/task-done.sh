#!/bin/sh
# The human gate that ends a task, `factory done` (T-007), run in the standalone posture straight against the
# state clone. It flips the parent and every T-NNN-NN block to a terminal status in one commit, releases the
# owner and pushes.
#
# There are two endings, decided by the parent's `archetype:` (T-186):
#   * a task with an MR ends in `done`, and only after a human validated that MR, so a parent whose `mr_url` is
#     null or empty is refused. Blocks never carry their own mr_url (ADR-0051), so only the parent's is checked.
#   * a triage, ops or research task never opens an MR (task-new.sh gives triage and ops no branch, and
#     block-research is read-only towards the product repo), so it ends in `closed` and needs no mr_url. Before
#     T-186 those archetypes had no terminal status at all: this script refused them for the missing mr_url and
#     state-report.sh refused `done` from an agent, so T-186 and T-187 sat in `review` forever.
# `owner:` goes to null in the same commit either way. A terminal task has no owner, and leaving one set is what
# made the Stop hook's owner-based lookup re-report a finished task until its round budget ran out.
#
#   task-done.sh <T-NNN> [--state <dir>]      cwd = the state clone unless --state
#
# Exit 1 with the reason when an MR archetype has no mr_url; nothing written. Exit 2 when the commit landed but
# the push to the state root did not, the same meaning state-report.sh gives that code.
set -eu

id='' state=''
die() { printf 'task-done: %s\n' "$1" >&2; exit 1; }
die2() { printf 'task-done: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one task id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: task-done.sh <T-NNN> [--state <dir>]"
[ -n "$state" ] || state=$(pwd)
[ -d "$state/.git" ] || die "$state is not a state clone - run from one or pass --state <dir>"

# setf, state_commit, state_lock and state_unlock: the one frontmatter writer, the one commit and the one lock
. "$(dirname -- "$0")/lib-tasks.sh"

parent=$(grep -lx "id: $id" "$state"/repos/*/tasks/*.md 2>/dev/null | head -n1)
[ -n "${parent:-}" ] && [ -f "$parent" ] || die "no task file with 'id: $id' in $state/repos/*/tasks/"

archetype=$(sed -n 's/^archetype:[[:space:]]*//p' "$parent" | head -n1 | sed 's/[[:space:]]*#.*//')
case "$archetype" in
  triage|ops|research) terminal=closed ;;
  *) terminal=done
     mr_url=$(sed -n 's/^mr_url:[[:space:]]*//p' "$parent" | head -n1)
     [ "$mr_url" != null ] && [ -n "$mr_url" ] || die "task $id has no mr_url, and a $archetype task ends in done only after its MR is validated" ;;
esac

# every block of this parent: T-NNN-NN task files, sorted for a stable diff
blocks=$(grep -lx "id: $id-[0-9][0-9]" "$state"/repos/*/tasks/*.md 2>/dev/null | sort || :)

# E3: the whole critical section, from the write to the push, under the one lock per state clone that
# state-report.sh takes, so a report running beside this one cannot ride in on its commit.
state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die2 "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
  *) die2 "the state lock could not be taken in $state; is it a git clone?" ;;
esac

from=$(sed -n 's/^status:[[:space:]]*//p' "$parent" | head -n1)

setf "$parent" status "$terminal"
setf "$parent" owner null
rel_parent=${parent#"$state/"}
set -- "$rel_parent"

if [ -n "$blocks" ]; then
  # a `while read` in a pipeline runs in a subshell, so the paths are collected into "$@" here instead
  oldifs=$IFS
  IFS='
'
  set -f
  for block in $blocks; do
    setf "$block" status "$terminal"
    setf "$block" owner null
    set -- "$@" "${block#"$state/"}"
  done
  set +f
  IFS=$oldifs
fi

state_commit "$state" "chore($id): $from → $terminal, blocks included" "$@" \
  || die2 "the $terminal of $id could not be committed in $state"

# the push recipe of ADR-0012, three tries, the same one state-report.sh uses in the standalone posture; a clone
# with no origin stays local (task-new.sh has the same rule) and is not an error
if git -C "$state" remote get-url origin >/dev/null 2>&1; then
  n=0
  until git -C "$state" pull -q --rebase --autostash -X theirs >/dev/null 2>&1 && git -C "$state" push -q >/dev/null 2>&1; do
    n=$((n + 1))
    [ "$n" -lt 3 ] || die2 "the push to the state root failed 3 times: $id is $terminal in $state but not pushed"
    sleep 1
  done
fi
