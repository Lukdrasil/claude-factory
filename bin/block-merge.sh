#!/bin/sh
# The coordinator's merge of a block into the session branch (T-007): run from the session worktree,
# `git merge --no-ff <block branch>`, then remove the block's worktree and delete its branch. A conflict aborts
# the merge, leaves the session worktree exactly as it was and keeps the block worktree/branch in place — the
# coordinator resolves it there per skills/factory/references/solve.md.
#
#   block-merge.sh <block-id> [--session-worktree <dir>] [--branch <name>] [--verify]
#                                                        cwd = the session worktree unless --session-worktree
#
# --verify turns the merge into a gated one for the wave flow: the block is merged, the repo's `build` binding
# from <state>/repos/<key>/toolset.md runs over the merged tree in the session worktree under a `timeout` (a
# toolset with no `build` binding says so on stderr and skips the stage), then block-verify.sh runs the block's
# own tests and the repo's `crap` binding against the merged tree, so a method over the toolset's
# `crap-threshold:` (8 by default) is red here too and not only in the block's own worktree (T-163). The
# reason is on block-verify.sh's stderr, which this script lets through.
# Both stages run against the merged tree and nothing is ever committed under --verify (T-164): a green run
# undoes the merge and exits 0 with the verdict on stderr, because the block's own MR into its base is what
# lands the work now (bin/block-mr.sh, ADR-0057) and the block's worktree and branch have to survive for it.
# A red stage aborts the merge just the same, so the session branch is back at the commit it started from with
# no merge commit ever written, leaves the block's worktree and branch in place and exits 4 with the failing
# stage on stderr. A red
# build stage reports at most the last 30 lines of the build output, never the whole log. A conflict still
# exits 3 and runs no stage. Without --verify the script behaves as it always did: the merge is committed
# unverified.
#
# The block branch is --branch when given, else the `branch:` of the block's task file in the state clone, else
# `block/<id>`. 2026-09-07: a block whose task file named another branch was merged as the hard-coded `block/<id>`
# — "not something we can merge" — so the task file is the source of truth and the convention only the fallback.
# Every note of this script, the skipped build stage included, goes to stderr: stdout is the merge SHA alone.
# Prints the merge SHA on a clean merge (exit 0, even when the merged block's worktree or branch could not be
# cleaned up — that is reported on stderr); a conflict exits 3 with the conflicting paths on stderr.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'block-merge: %s\n' "$1" >&2; exit 1; }

id='' session='' branch='' verify=''
while [ $# -gt 0 ]; do
  case "$1" in
    --session-worktree) [ $# -ge 2 ] || die "--session-worktree needs a value"; session=$2; shift 2 ;;
    --branch) [ $# -ge 2 ] || die "--branch needs a value"; branch=$2; shift 2 ;;
    --verify) verify=1; shift ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one block id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: block-merge.sh <block-id> [--session-worktree <dir>] [--branch <name>] [--verify]"
[ -n "$session" ] || session=$(pwd)
[ -d "$session/.git" ] || [ -f "$session/.git" ] || die "$session is not a git worktree"

# the state clone: $WORK_DIR/state when it is one (the standalone layout, ADR-0049), otherwise what the session
# worktree resolves to; resolve_state_dir answers relative to the cwd, so a relative answer is anchored in $session
state='' task=''
resolve_state() {
  [ -z "$state" ] || return 0
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    state=$(resolve_state_dir "$session")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$session/$state" ;; esac
  fi
  task=$(task_of "$id" || :)
}

# warn: --verify needs the state clone and the repo key even when --branch spared us the task lookup
[ -z "$verify" ] || resolve_state
if [ -z "$branch" ]; then
  resolve_state
  if [ -n "$task" ]; then
    # the first `branch:` of the frontmatter, a trailing ` # comment` and quotes stripped
    branch=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit }
      /^branch:[[:space:]]*/ { sub(/^branch:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$task" \
      | sed 's/^["'"'"'"'"'"']//; s/["'"'"'"'"'"']$//')
  fi
  [ -n "$branch" ] || branch="block/$id"
fi

# see: docs/design/toolset.md and bin/block-verify.sh, the same reader for a command's binding cell
binding_of() { # <toolset file> <command name>
  [ -f "$1" ] || return 0
  awk -F '|' -v want="$2" '
    NF >= 3 {
      name = $2; bind = $3
      gsub(/`/, "", name); gsub(/`/, "", bind)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); gsub(/^[[:space:]]+|[[:space:]]+$/, "", bind)
      sub(/[[:space:]].*$/, "", name)
      if (name == want && bind != "" && bind != "binding") { print bind; exit }
    }' "$1"
}

[ "$branch" = "block/$id" ] || printf 'block-merge: merging block %s from branch %s\n' "$id" "$branch" >&2

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# a merge commit needs an identity; a bare CI or worker checkout may have none (the task-approve.sh fallback)
ident=''
[ -n "$(git -C "$session" config user.email || :)" ] || ident='-c user.name=harness -c user.email=harness@localhost'
pre_sha=$(git -C "$session" rev-parse HEAD)

if [ -n "$verify" ]; then
  set -- merge --no-commit --no-ff "$branch"
else
  set -- merge --no-ff -m "merge: block $id" "$branch"
fi
# shellcheck disable=SC2086
if ! git -C "$session" $ident "$@" >"$tmp/out" 2>"$tmp/err"; then
  conflicts=$(git -C "$session" diff --name-only --diff-filter=U)
  # "is a merge in progress" is asked of the session worktree, never of a path under cwd: `--git-path
  # MERGE_HEAD` answers `.git/MERGE_HEAD` for a main clone, which `[ -e ]` would then resolve against the
  # *caller's* cwd - false either way when the caller is elsewhere, and false-positive inside another repo
  # mid-merge, which is how a merge that never started came to be aborted (`fatal: There is no merge to abort`,
  # exit 128). `rev-parse -q --verify` asks git itself, in $session (T-007 review).
  if [ -n "$conflicts" ] || git -C "$session" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    git -C "$session" merge --abort
    printf 'block-merge: merge of %s conflicts:
%s
' "$branch" "$conflicts" >&2
    printf 'block-merge: a conflict in a test file is a cut defect, not a lock breach: rebase the later block on the session branch and run it again.
' >&2
    exit 3
  fi
  printf 'block-merge: merge of %s failed:
' "$branch" >&2; cat "$tmp/err" >&2
  exit 1
fi

if [ -n "$verify" ]; then
  key=''
  [ -z "$task" ] || { key=${task#"$state"/repos/}; key=${key%%/*}; }
  build_binding=''
  [ -z "$key" ] || build_binding=$(binding_of "$state/repos/$key/toolset.md" build)

  # why: both stages run before the commit, so a red one has nothing to undo but the uncommitted merge itself
  red() { # <stage> <reason>
    # why: an "Already up to date" merge staged nothing, so there is no MERGE_HEAD and `merge --abort` would
    # why: print `fatal: There is no merge to abort` over the stage reason before the exit 4
    if git -C "$session" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      git -C "$session" merge --abort
    fi
    printf 'block-merge: block %s is red at the %s stage, the merge was undone: %s\n' "$id" "$1" "$2" >&2
    exit 4
  }

  if [ -n "$build_binding" ]; then
    set +e
    ( cd "$session" && eval "timeout 20m $build_binding" ) >"$tmp/build" 2>&1
    build_rc=$?
    set -e
    # why: a failing build is read by the coordinator, and a whole log there is tens of thousands of
    # why: characters of context for a handful of diagnostic lines, so the tail is the whole report
    [ "$build_rc" -eq 0 ] || red build "$(tail -n 30 "$tmp/build")"
  else
    # why: stdout is the merge SHA alone, so every note of this script goes to stderr
    printf 'block-merge: no `build` binding in repos/%s/toolset.md, the build stage is skipped\n' "${key:-?}" >&2
  fi

  set +e
  "$(dirname -- "$0")/block-verify.sh" "$id" --state "$state" --worktree "$session" --base "$pre_sha"
  verify_rc=$?
  set -e
  [ "$verify_rc" -eq 0 ] || red verify "block-verify.sh reported red for $id against the merged tree"

  # T-164: the merge is proof, not an integration step. The block's own MR is what lands it on the forge, so a
  # green run undoes the merge it staged, leaves the block's worktree and branch alone (the MR needs them) and
  # exits 0 with the verdict on stderr; stdout stays empty, because there is no merge SHA to print.
  if git -C "$session" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    git -C "$session" merge --abort
  fi
  git -C "$session" checkout -- . 2>/dev/null || :
  printf 'block-merge: block %s would merge green into %s; nothing was committed, open its MR with block-mr.sh %s\n' \
    "$id" "$(git -C "$session" rev-parse --abbrev-ref HEAD)" "$id" >&2
  exit 0
fi

merge_sha=$(git -C "$session" rev-parse HEAD)

# find the block worktree from git worktree list — match by branch, not by a guessed path
block_path=$(git -C "$session" worktree list --porcelain | awk -v b="refs/heads/$branch" '
  /^worktree / { wt = $2 }
  /^branch / { if ($2 == b) { print wt } }
')
[ -n "$block_path" ] || die "no worktree found for branch $branch"

# `--force`: the merge is in, so whatever the subagent left uncommitted in the block worktree is disposable —
# a plain `worktree remove` refuses a dirty worktree and would fail a merge that already succeeded (T-007
# review). A removal that still fails is reported and does not undo the merge: the SHA is printed, exit 0, and
# the coordinator is told which worktree/branch is left behind.
left() { # <what> <the git output>
  printf 'block-merge: block %s is merged (%s) but %s:\n%s\n' "$id" "$merge_sha" "$1" "$2" >&2
  printf '%s\n' "$merge_sha"
  exit 0
}
if ! out=$(git -C "$session" worktree remove --force "$block_path" 2>&1); then
  left "its worktree $block_path could not be removed" "$out"
fi
if ! out=$(git -C "$session" branch -d "$branch" 2>&1); then
  left "the branch $branch could not be deleted" "$out"
fi

printf '%s\n' "$merge_sha"
