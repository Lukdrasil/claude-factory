#!/bin/sh
# The rebase of a stack after one of its blocks moved (T-164, ADR-0057): a review fix on a block rewrites the
# branch every later block was cut from, so every block whose base chain runs through it is rebased onto the
# new head, in dependency order, force-pushed with lease and verified again. Since 3.4 of the agent-org plan a
# new block is cut from the work branch and never from another block, so this is for a task stacked before.
#
#   restack.sh <T-NNN> <block-id> [--state <dir>] [--no-push]
#
# The chain is read from the `base:` line worktree-add.sh wrote into each block's progress file: the blocks
# based on <block-id>'s branch, then the blocks based on theirs, and so on. Each one is rebased in its own
# worktree (`<root>/<key>/<block>`), pushed with `--force-with-lease` (skipped with --no-push or when the
# worktree has no origin), and run through block-verify.sh.
#
# One line per rebased block on stdout: `<block> rebased onto <branch>`. Exit 0 when the whole chain is
# rebased and green. Exit 3 when a rebase conflicts, naming the block and the conflicting paths on stderr,
# with that block's rebase aborted and the blocks behind it untouched: the coordinator asks the human through
# skills/_shared/blocked-question.md. Exit 4 when a rebased block comes back red from block-verify.sh. Exit 1
# for a misuse or a missing worktree.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'restack: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

id='' block='' state='' push=1
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --no-push) push=0; shift ;;
    -*) die "unknown argument '$1'" ;;
    *) if [ -z "$id" ]; then id=$1; elif [ -z "$block" ]; then block=$1; else die "one parent and one block at a time"; fi; shift ;;
  esac
done
[ -n "$id" ] && [ -n "$block" ] || die "usage: restack.sh <T-NNN> <block-id> [--state <dir>] [--no-push]"
is_parent_id "$id" || die "'$id' is not a parent task id of the shape T-NNN"
is_block_of "$id" "$block" || die "'$block' is not a block of $id"

if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    here=$(pwd)
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
  fi
fi

task=$(task_of "$id" || :)
[ -n "$task" ] || die "$id resolves to no task file under $state/repos/*/tasks"
key=${task#"$state/repos/"}
key=${key%%/*}
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac

fm() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }
nullable() { case "$1" in null|'~'|'') printf '' ;; *) printf '%s' "$1" ;; esac; }

session_branch=$(nullable "$(fm "$task" branch)")
branch_of() { bt=$(task_of "$1" || :); [ -n "$bt" ] || return 0; nullable "$(fm "$bt" branch)"; }
base_of() {
  bo=$(sed -n 's/^base:[[:space:]]*//p' "$state/repos/$key/progress/$1.md" 2>/dev/null | head -n1)
  [ -n "$bo" ] || bo=$session_branch
  printf '%s' "$bo"
}

blocks=''
while IFS= read -r f; do
  [ -n "$f" ] || continue
  b=$(fm "$f" id)
  if is_block_of "$id" "$b"; then blocks="$blocks$b
"; fi
done <<EOF
$(task_files "$key")
EOF
blocks=$(printf '%s' "$blocks" | sort_ids)

moved=$(branch_of "$block")
[ -n "$moved" ] || die "block $block has no branch:, so nothing was rebased"

# invariant: the loop below rebases in this order, so a block is listed only after the block it is based on;
# invariant: a block appears once, and the id order inside one level keeps the walk deterministic
chain=''
frontier=$moved
while [ -n "$frontier" ]; do
  next=''
  for b in $blocks; do
    case " $chain " in *" $b "*) continue ;; esac
    [ "$b" != "$block" ] || continue
    bb=$(base_of "$b")
    for fr in $frontier; do
      [ "$bb" = "$fr" ] || continue
      chain="$chain $b"
      nb=$(branch_of "$b")
      [ -z "$nb" ] || next="$next $nb"
      break
    done
  done
  frontier=$next
done

for b in $chain; do
  wt="$root/$key/$b"
  [ -e "$wt/.git" ] || die "block $b has no worktree at $wt, so it cannot be rebased: run worktree-add.sh $b"
  base=$(base_of "$b")
  if ! git -C "$wt" rebase "$base" >/dev/null 2>&1; then
    paths=$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null || :)
    git -C "$wt" rebase --abort >/dev/null 2>&1 || :
    printf 'restack: block %s conflicts with %s on:\n%s\n' "$b" "$base" "$paths" >&2
    printf 'restack: the blocks behind %s are untouched. Ask the human per skills/_shared/blocked-question.md.\n' "$b" >&2
    exit 3
  fi
  printf '%s rebased onto %s\n' "$b" "$base"
  if [ "$push" = 1 ] && git -C "$wt" remote get-url origin >/dev/null 2>&1; then
    git -C "$wt" push --force-with-lease origin "$(branch_of "$b")" >/dev/null 2>&1 \
      || printf 'restack: the rebased %s could not be pushed; push it yourself before the MR is read again\n' "$b" >&2
  fi
  if ! "$bin/block-verify.sh" "$b" --state "$state" --worktree "$wt"; then
    printf 'restack: block %s is red after the rebase onto %s; fix it before the rest of the stack moves\n' \
      "$b" "$base" >&2
    exit 4
  fi
done
exit 0
