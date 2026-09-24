#!/bin/sh
# The task worktree, path and branch in one call (T-150), so the rule that lived in four prose files lives in
# one script: `$WORK_DIR/<key>/<task-id>/` on `feat/<id>-<slug>` for a parent task, cut from the repo's
# default branch, and on `block/<id>` for a block, cut from the parent's `branch:`. The branch is written into
# the task's `branch:` through state-report.sh, which is the only writer of task frontmatter.
#
#   worktree-add.sh <task-id> [--from <branch>] [--state <dir>]
#                             the commit-ish the branch is cut from, instead of the computed one
#                                              the state clone; default $WORK_DIR/state, else from the cwd
#
# 3.4 of the agent-org plan: a block is cut from the parent's `branch:`, the work branch, when its wave starts,
# whatever its `depends_on:` says, because every block of a wave is merged into the work branch before the next
# wave starts. The base is recorded as `base: <branch>` in the block's progress file, which is what block-mr.sh
# targets its MR at, and the commit it was cut from as `base_sha: <sha>` beside it (T-228 A7). The one
# exception is a task stacked before (T-164): a block whose progress file already records a `block/` base keeps
# it while that branch exists in the clone, which is what restack.sh still walks.
#
# Exit 0 with `path: <dir>` and `branch: <branch>` on stdout, plus `base: <branch>` for a block. An existing worktree whose HEAD is already the
# task's branch is a resume: the same two lines, exit 0, nothing created. A resumed block whose base moved is
# reset to it when it has no commits of its own (block_resume). Exit 1 with the reason on stderr when no task
# id is given, when the id resolves to no task file, when the repo's clone is unknown, when the worktree exists
# on another branch, when a resumed block has commits of its own on a base that moved (the rebase command is in
# the message), or when git refuses to create it.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'worktree-add: %s\n' "$1" >&2; exit 1; }

id='' from='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --from) [ $# -ge 2 ] || die "--from needs a value"; from=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one task id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: worktree-add.sh <task-id> [--from <branch>] [--state <dir>]"

# see: block-brief.sh, the same resolution: $WORK_DIR/state when it is a clone, else what the cwd resolves to,
# see: anchored absolute because resolve_state_dir answers relative to the cwd
if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    here=$(pwd)
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
  fi
fi

# invariant: task_of reads the shell variable $state, it takes no state argument
task=$(task_of "$id" || :)
[ -n "$task" ] || die "task $id resolves to no task file under $state/repos/*/tasks"

key=${task#"$state/repos/"}
key=${key%%/*}

[ -n "${WORK_DIR:-}" ] || die "WORK_DIR is not set, so there is no work root to put the worktree of $id under"
case "$WORK_DIR" in /*|[A-Za-z]:/*) ;; *) die "WORK_DIR must be an absolute path, not '$WORK_DIR'" ;; esac

branch_of() { # <task file>
  bo=$(sed -n 's/^branch:[[:space:]]*//p' "$1" | head -n1)
  case "$bo" in null|'~') bo='' ;; esac
  printf '%s' "$bo"
}

# `base: <branch>` and `base_sha: <sha>` in the block's progress file, the record of what the block branch was cut
# from: replaced when the lines are there, appended when they are not. `base:` holds the branch alone because
# block-mr.sh, mr-watch.sh, restack.sh and solve-next.sh read its whole value. Prints the file when it changed,
# nothing when it did not.
record_base() { # <progress file> <branch> <sha>
  mkdir -p "$(dirname -- "$1")"
  rb_new=''
  [ -f "$1" ] || { printf '# %s\n' "$id" > "$1"; rb_new=1; }
  if [ "$(sed -n 's/^base:[[:space:]]*//p' "$1" | head -n1)" = "$2" ] \
    && [ "$(sed -n 's/^base_sha:[[:space:]]*//p' "$1" | head -n1)" = "$3" ]; then return 0; fi
  awk -v b="$2" -v s="$3" '
    /^base_sha:[[:space:]]*/ { next }
    /^base:[[:space:]]*/ { if (!done) { print "base: " b; print "base_sha: " s; done = 1 } next }
    { print } END { if (!done) { print "base: " b; print "base_sha: " s } }' "$1" > "$1.tmp" && mv -f "$1.tmp" "$1"
  if [ -n "$rb_new" ]; then
    rb_cl=$(awk '/^## Checklist[ \t]*$/ { on = 1; next } on && /^## / { exit } on && NF { print }' "$task")
    [ -z "$rb_cl" ] || printf '\n## Remaining\n%s\n' "$rb_cl" >> "$1"
  fi
  printf '%s' "$1"
}

# A block branch that already exists is a resume, and its base may have moved since it was cut (T-228 A7: T-208-05
# stayed on a squashed parent commit). A tip still at the recorded `base_sha:` has no commits of its own and is
# reset to the new base; a tip past it is refused with the rebase command. With no `base_sha:` (a progress file
# from before T-228) only a tip that is an ancestor of the new base is reset, and anything else is left as it is.
block_resume() { # <progress file> <new base sha>
  git -C "$clone" show-ref --verify --quiet "refs/heads/$branch" || return 0
  br_tip=$(git -C "$clone" rev-parse "refs/heads/$branch")
  br_old=$(sed -n 's/^base_sha:[[:space:]]*//p' "$1" 2>/dev/null | head -n1)
  [ "$br_tip" != "$2" ] || return 0
  if [ -n "$br_old" ]; then
    [ "$br_old" != "$2" ] || return 0
    [ "$br_tip" = "$br_old" ] \
      || die "block $id has commits of its own on $br_old, and its base $base has moved to $2. Rebase them onto it (git -C $clone rebase --onto $2 $br_old $branch) and run this again"
  else
    git -C "$clone" merge-base --is-ancestor "$br_tip" "$2" || return 0
  fi
  if [ -e "$wt" ]; then
    git -C "$wt" reset -q --keep "$2" || die "$wt could not be reset from $br_tip to its new base $2 (git -C $wt reset --keep $2)"
  else
    git -C "$clone" branch -f "$branch" "$2" >/dev/null || die "$branch could not be reset from $br_tip to its new base $2"
  fi
  printf 'worktree-add: %s was reset from %s to its new base %s\n' "$branch" "$br_tip" "$2" >&2
}

clone=$(yml_field "$key" path)
[ -n "$clone" ] || die "repo $key has no 'path:' in $state/repos.yml, so its clone is unknown: register it with factory-add-repo.sh from inside the clone"
git -C "$clone" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "the clone registered for $key in $state/repos.yml is not a git clone: $clone"

task_branch=$(branch_of "$task")
if is_block_id "$id"; then
    branch="block/$id"
    parent=${id%-*}
    ptask=$(task_of "$parent" || :)
    [ -n "$ptask" ] || die "block $id: its parent $parent resolves to no task file under $state/repos/*/tasks"
    base=$(branch_of "$ptask")
    [ -n "$base" ] || die "block $id: parent $parent has no 'branch:' in $ptask, so create the session worktree of $parent first"
    # why: a task stacked before 3.4 resumes on the block branch its progress file records; once that branch is
    # why: gone (merged and deleted) the work branch is the base, as for every new block
    recorded=$(sed -n 's/^base:[[:space:]]*//p' "$state/repos/$key/progress/$id.md" 2>/dev/null | head -n1)
    case "$recorded" in
      block/*) if git -C "$clone" show-ref --verify --quiet "refs/heads/$recorded"; then base=$recorded; fi ;;
    esac
else
    branch=$task_branch
    if [ -z "$branch" ]; then
      slug=${task##*/}
      slug=${slug%.md}
      slug=${slug#"$id"}
      slug=${slug#-}
      branch="feat/$id"
      [ -z "$slug" ] || branch="feat/$id-$slug"
    fi
    base=$(yml_field "$key" default_branch)
    [ -n "$base" ] || base=$(git -C "$clone" symbolic-ref --short HEAD 2>/dev/null) || base=''
    [ -n "$base" ] || die "repo $key has no 'default_branch:' in $state/repos.yml and its clone is on no branch: pass --from <branch>"
fi
[ -z "$from" ] || base=$from

wt="$WORK_DIR/$key/$id"
progress="$state/repos/$key/progress/$id.md"

if [ -e "$wt" ]; then
  head=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null) || head=''
  [ "$head" = "$branch" ] \
    || die "$wt already exists on '${head:-no branch}', not $branch. Remove that worktree (git -C $clone worktree remove $wt) or check $branch out in it"
fi

if is_block_id "$id"; then
    base_sha=$(git -C "$clone" rev-parse --verify --quiet "$base^{commit}") \
      || die "block $id: its base $base is no commit in $clone"
    block_resume "$progress" "$base_sha"
fi

if [ -e "$wt" ]; then
  printf 'worktree-add: %s already exists on %s, reused\n' "$wt" "$branch" >&2
else
  mkdir -p "$WORK_DIR/$key" || die "the work directory $WORK_DIR/$key could not be created"
  if git -C "$clone" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$clone" worktree add "$wt" "$branch" >/dev/null \
      || die "git could not add the worktree $wt on the existing branch $branch"
  else
    git -C "$clone" worktree add -b "$branch" "$wt" "$base" >/dev/null \
      || die "git could not add the worktree $wt on a new branch $branch cut from $base"
  fi
fi

# the `branch:` block-merge.sh merges by is written the one way task frontmatter is ever written, and only when
# it is not already that branch: a report that changes nothing would still commit and push into the state clone
based=''
if is_block_id "$id"; then
  based=$(record_base "$progress" "$base" "$(git -C "$clone" merge-base "refs/heads/$branch" "$base_sha")")
fi

if [ "$task_branch" != "$branch" ] || [ -n "$based" ]; then
  (cd "$wt" && "$(dirname -- "$0")/state-report.sh" --task "$id" --no-status --branch "$branch" >/dev/null) \
    || die "the worktree $wt is there, but state-report.sh could not write 'branch: $branch' into $task (its reason is above): record it and run this again"
fi

printf 'path: %s\n' "$wt"
printf 'branch: %s\n' "$branch"
if is_block_id "$id"; then printf 'base: %s\n' "$base"; fi
