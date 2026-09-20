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
# T-164, the stack: a block is cut from the branch of the last block in its `depends_on:` (the highest numbered
# one when there are several) and from the parent's `branch:` when it depends on nothing, so blocks of one wave
# still share a base and stay parallel. The base is recorded as `base: <branch>` in the block's progress file,
# which is what block-mr.sh targets its MR at and what restack.sh walks.
#
# Exit 0 with `path: <dir>` and `branch: <branch>` on stdout, plus `base: <branch>` for a block. An existing worktree whose HEAD is already the
# task's branch is a resume: the same two lines, exit 0, nothing created. Exit 1 with the reason on stderr
# when no task id is given, when the id resolves to no task file, when the repo's clone is unknown, when the
# worktree exists on another branch, or when git refuses to create it.
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

# one field of the repos.yml line of a repo (ADR-0013 revision): `<key>: {url: …, default_branch: …, path: …}`,
# written by factory-add-repo.sh, in the flat or the indented spelling
yml_field() { # <key> <field>
  [ -f "$state/repos.yml" ] || return 0
  awk -v want="$1" -v field="$2" '
    /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
    key == want && match($0, field "[ \t]*:[ \t]*") {
      v = substr($0, RSTART + RLENGTH)
      sub(/[ \t]*[,}].*$/, "", v); sub(/[ \t]+#.*$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      if (v != "") { print v; exit }
    }' "$state/repos.yml"
}

branch_of() { # <task file>
  bo=$(sed -n 's/^branch:[[:space:]]*//p' "$1" | head -n1)
  case "$bo" in null|'~') bo='' ;; esac
  printf '%s' "$bo"
}

# the block ids of a `depends_on: [T-300-01, T-300-02]` line, one per line, sorted, so the last one is the
# highest numbered block the stack has to be cut from (T-164)
deps_of() { # <task file>
  sed -n 's/^depends_on:[[:space:]]*//p' "$1" | head -n1 \
    | tr -d '[]",' | tr ' ' '\n' | grep -E '^T-[0-9]{3}-[0-9]{2}$' | sort || :
}

# `base: <branch>` in the block's progress file, the record of what the block branch was cut from: replaced
# when the line is there, appended when it is not. Prints the file when it changed, nothing when it did not.
record_base() { # <progress file> <branch>
  mkdir -p "$(dirname -- "$1")"
  [ -f "$1" ] || printf '# %s\n' "$id" > "$1"
  if [ "$(sed -n 's/^base:[[:space:]]*//p' "$1" | head -n1)" = "$2" ]; then return 0; fi
  awk -v b="$2" '/^base:[[:space:]]*/ { if (!done) { print "base: " b; done = 1 } next }
    { print } END { if (!done) print "base: " b }' "$1" > "$1.tmp" && mv -f "$1.tmp" "$1"
  printf '%s' "$1"
}

clone=$(yml_field "$key" path)
[ -n "$clone" ] || die "repo $key has no 'path:' in $state/repos.yml, so its clone is unknown: register it with factory-add-repo.sh from inside the clone"
git -C "$clone" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "the clone registered for $key in $state/repos.yml is not a git clone: $clone"

task_branch=$(branch_of "$task")
case "$id" in
  T-*-[0-9][0-9])
    branch="block/$id"
    parent=${id%-*}
    ptask=$(task_of "$parent" || :)
    [ -n "$ptask" ] || die "block $id: its parent $parent resolves to no task file under $state/repos/*/tasks"
    base=$(branch_of "$ptask")
    [ -n "$base" ] || die "block $id: parent $parent has no 'branch:' in $ptask, so create the session worktree of $parent first"
    # the stack of T-164: a block is cut from the branch of the last block it depends on, so its MR carries only
    # its own diff; a block with no dependency is cut from the session branch and its wave stays parallel
    dep=$(deps_of "$task" | tail -n1)
    if [ -n "$dep" ]; then
      dtask=$(task_of "$dep" || :)
      [ -n "$dtask" ] || die "block $id: its dependency $dep resolves to no task file under $state/repos/*/tasks"
      dbranch=$(branch_of "$dtask")
      [ -n "$dbranch" ] || die "block $id: its dependency $dep has no 'branch:' in $dtask, so create the worktree of $dep first"
      base=$dbranch
    fi ;;
  *)
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
    [ -n "$base" ] || die "repo $key has no 'default_branch:' in $state/repos.yml and its clone is on no branch: pass --from <branch>" ;;
esac
[ -z "$from" ] || base=$from

wt="$WORK_DIR/$key/$id"

if [ -e "$wt" ]; then
  head=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null) || head=''
  [ "$head" = "$branch" ] \
    || die "$wt already exists on '${head:-no branch}', not $branch. Remove that worktree (git -C $clone worktree remove $wt) or check $branch out in it"
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
case "$id" in
  T-*-[0-9][0-9]) based=$(record_base "$state/repos/$key/progress/$id.md" "$base") ;;
esac

if [ "$task_branch" != "$branch" ] || [ -n "$based" ]; then
  (cd "$wt" && "$(dirname -- "$0")/state-report.sh" --task "$id" --no-status --branch "$branch" >/dev/null) \
    || die "the worktree $wt is there, but state-report.sh could not write 'branch: $branch' into $task (its reason is above): record it and run this again"
fi

printf 'path: %s\n' "$wt"
printf 'branch: %s\n' "$branch"
case "$id" in T-*-[0-9][0-9]) printf 'base: %s\n' "$base" ;; esac
