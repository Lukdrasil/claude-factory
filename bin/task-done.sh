#!/bin/sh
# The human gate that ends a task, `factory done` (T-007), run in the standalone posture straight against the
# state clone. It flips the parent and every T-NNN-NN block to a terminal status in one commit and releases the
# owner. It does not push: the push to the state root is state-push.sh's, run in the background by the monitor
# pass and the CEO loop.
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
# `--close "<reason>"` (T-228 A8) ends any task in `closed`, a block too, with no mr_url check: the reason goes
# into the commit message and a `**closed** <reason>` line of the task's progress file.
#
# After the commit the task's leftovers go (T-228 Q2, Q16): the worktree `$WORK_DIR/<key>/<id>` of the task and
# of each block when `git status --porcelain` is empty, and the local branch (the parent's `branch:`,
# `block/<id>` for a block) when a remote-tracking ref contains its tip, read without a fetch. Whatever stays
# is one `skipped: <what> <reason>` line on stdout. Remote branches are never touched.
#
# Last, a parent (not a block) leaves the hot globs: state-archive.sh moves it with its blocks, progress and
# verdicts to repos/<key>/archive/<YYYY-MM>/ when every block is terminal and no open task depends on it, and
# otherwise leaves it live with the reason on stderr; either way the task is done and the exit is 0.
#
#   task-done.sh <T-NNN|T-NNN-NN> [--close "<reason>"] [--state <dir>]      cwd = the state clone unless --state
#
# Exit 1 with the reason when an MR archetype has no mr_url; nothing written. Exit 2 when the terminal status
# could not be committed (the state lock or git), the same meaning state-report.sh gives that code. A leftover
# and a parent that stays live are not errors.
set -eu

id='' state='' reason=''
die() { printf 'task-done: %s\n' "$1" >&2; exit 1; }
die2() { printf 'task-done: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --close)
      case "${2:-}" in ''|-*) die "--close needs a reason" ;; esac
      reason=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one task id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: task-done.sh <T-NNN|T-NNN-NN> [--close \"<reason>\"] [--state <dir>]"
[ -n "$state" ] || state=$(pwd)
[ -d "$state/.git" ] || die "$state is not a state clone - run from one or pass --state <dir>"

# setf, state_commit, state_lock and state_unlock: the one frontmatter writer, the one commit and the one lock
. "$(dirname -- "$0")/lib-tasks.sh"

parent=$(task_of "$id")
case "$parent" in */archive/*) die "task $id is archived in $parent, it is already finished" ;; esac
[ -n "${parent:-}" ] && [ -f "$parent" ] || die "no task file with 'id: $id' in $state/repos/*/tasks/"

archetype=$(sed -n 's/^archetype:[[:space:]]*//p' "$parent" | head -n1 | sed 's/[[:space:]]*#.*//')
if [ -n "$reason" ]; then
  terminal=closed
else
  case "$archetype" in
    triage|ops|research) terminal=closed ;;
    *) terminal=done
       mr_url=$(sed -n 's/^mr_url:[[:space:]]*//p' "$parent" | head -n1)
       [ "$mr_url" != null ] && [ -n "$mr_url" ] || die "task $id has no mr_url, and a $archetype task ends in done only after its MR is validated" ;;
  esac
fi

# every block of this parent: T-NNN-NN task files, sorted for a stable diff
blocks=$(task_files | while IFS= read -r f; do grep -HxE "id: $id-[0-9]{2,}" "$f"; done \
  | sed 's/^\(.*\):id: \(.*\)$/\2 \1/' | sort_ids | cut -d' ' -f2- || :)

# E3: the whole critical section, from the write to the commit, under the one lock per state clone that
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

key=${parent#"$state/repos/"}
key=${key%%/*}

message="chore($id): $from → $terminal, blocks included"
if [ -n "$reason" ]; then
  progress="$state/repos/$key/progress/$id.md"
  mkdir -p "$(dirname -- "$progress")"
  [ -f "$progress" ] || printf '# %s\n' "$id" > "$progress"
  [ -z "$(tail -c1 "$progress")" ] || printf '\n' >> "$progress"
  printf '**closed** %s\n' "$reason" >> "$progress"
  set -- "$@" "${progress#"$state/"}"
  message="$message: $reason"
fi

state_commit "$state" "$message" "$@" \
  || die2 "the $terminal of $id could not be committed in $state"
state_unlock

cleanup() { # <task file>
  cu_id=$(sed -n 's/^id:[[:space:]]*//p' "$1" | head -n1)
  if is_block_id "$cu_id"; then
    cu_branch="block/$cu_id"
  else
    cu_branch=$(sed -n 's/^branch:[[:space:]]*//p' "$1" | head -n1)
  fi
  cu_wt="$WORK_DIR/$key/$cu_id"
  if [ -e "$cu_wt" ]; then
    if [ -n "$(git -C "$cu_wt" status --porcelain 2>/dev/null)" ]; then
      printf 'skipped: %s has uncommitted changes\n' "$cu_wt"
    elif ! git -C "$cu_wt" symbolic-ref -q HEAD >/dev/null 2>&1 \
       && [ -z "$(git -C "$cu_wt" branch -r --contains HEAD 2>/dev/null)" ]; then
      printf 'skipped: %s is on a detached HEAD no remote-tracking ref contains\n' "$cu_wt"
    elif ! git -C "$clone" worktree remove "$cu_wt" >/dev/null 2>&1; then
      printf 'skipped: %s git worktree remove refused it\n' "$cu_wt"
    fi
  fi
  case "$cu_branch" in ''|null|'~') return 0 ;; esac
  git -C "$clone" show-ref --verify --quiet "refs/heads/$cu_branch" || return 0
  if [ -e "$cu_wt" ]; then
    printf 'skipped: %s is checked out in %s, which stays\n' "$cu_branch" "$cu_wt"
  elif [ -z "$(git -C "$clone" branch -r --contains "refs/heads/$cu_branch" 2>/dev/null)" ]; then
    printf 'skipped: %s is not pushed, no remote-tracking ref contains its tip\n' "$cu_branch"
  elif ! git -C "$clone" branch -D "$cu_branch" >/dev/null 2>&1; then
    printf 'skipped: %s git branch -D refused it\n' "$cu_branch"
  fi
}

clone=$(yml_field "$key" path)
if [ -n "${WORK_DIR:-}" ] && [ -n "$clone" ] && git -C "$clone" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s\n%s\n' "$parent" "$blocks" | while IFS= read -r task; do [ -z "$task" ] || cleanup "$task"; done
fi

# the parent it just closed, archived when it may be (state-archive.sh takes the lock itself and prints the moves);
# a parent that stays live is named with the reason on stderr and is no error
if ! is_block_id "$id"; then
  sh "$(dirname -- "$0")/state-archive.sh" "$id" --state "$state" || :
fi
