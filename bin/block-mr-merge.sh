#!/bin/sh
# The lead's merge of one block MR into the work branch (3.4 step 5 of the agent-org plan): the MR block-mr.sh
# opened is merged on the forge, the parent worktree follows with a fast-forward pull, the block's worktree and
# local branch are removed and the block is set done through state-report.sh.
#
#   block-mr-merge.sh <block-id> [--confirmed] [--dry-run] [--state <dir>]
#
# The MR is the block's `mr_url:`, the forge its host (github.com goes to gh, every other host to glab), the
# class the task's `.harness/<T-id>/forge.json` that block-mr.sh wrote:
#   A and B  `glab mr merge <url> --auto-merge=false --remove-source-branch --yes` or
#            `gh pr merge <url> --merge --delete-branch`, merged at once
#   C        the same with `--auto-merge` (gh: `--auto`): the forge merges once the pipeline is green, this run
#            prints `<block> auto-merge <url>` and a later run, on the merged MR, does the rest
# On glab a task whose merge method is not `merge` (ff, rebase_merge: class B) has a sibling block MR fall behind
# the work branch once the first one lands, so an MR the forge reports as `need_rebase` is rebased first with
# `glab mr rebase <url> --skip-ci`, and the merge waits until the rebase is through.
#
# Two things stop a merge before the forge is called. A block whose `.harness/<block>/arch.md` rates it `risk:
# high` exits 3: the lead asks the human, and runs this again with --confirmed after the yes. A block whose
# `.harness/<block>/review.md` verdict is `changes needed` exits 1: its blocking findings are a fix round first.
# An MR the forge already reports merged is not merged again, so a run that stopped halfway is finished by the
# next one. --dry-run prints the commands a run would make and changes nothing.
#
# Exit 0 with `<block> merged <url>` (or `<block> auto-merge <url>` in class C) on stdout. Exit 3 for a high
# risk block without --confirmed. Exit 1 with the reason on stderr for a misuse, a block with no mr_url, no
# review, a review asking for changes, no forge.json, no parent worktree, a merge the forge refused, a pull that
# is not a fast-forward, or a done the state clone refused. A worktree or branch that could not be removed is a
# note on stderr and does not fail the run.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'block-mr-merge: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

id='' confirmed='' dry='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --confirmed) confirmed=1; shift ;;
    --dry-run) dry=1; shift ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one block id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: block-mr-merge.sh <block-id> [--confirmed] [--dry-run] [--state <dir>]"
is_block_id "$id" || die "'$id' is not a block id of the shape T-<n>-<NN> or T-<ALIAS>-<n>-<NN>"

# see: block-mr.sh, the same resolution: $WORK_DIR/state when it is a clone, else what the cwd resolves to
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
[ -n "$task" ] || die "no task file with 'id: $id' in $state/repos/*/tasks/"
case "$task" in */archive/*) die "block $id is archived in $task, its MR is long merged" ;; esac
key=${task#"$state/repos/"}
key=${key%%/*}
parent=${id%-*}

fm() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }
nullable() { case "$1" in null|'~'|'') printf '' ;; *) printf '%s' "$1" ;; esac; }

url=$(nullable "$(fm "$task" mr_url)")
[ -n "$url" ] || die "block $id carries no mr_url; open its MR with block-mr.sh $id first"
branch=$(nullable "$(fm "$task" branch)")
[ -n "$branch" ] || branch="block/$id"
ptask=$(task_of "$parent" || :)
[ -n "$ptask" ] || die "block $id: its parent $parent resolves to no task file"
work=$(nullable "$(fm "$ptask" branch)")
[ -n "$work" ] || die "block $id: its parent $parent has no 'branch:', so there is no work branch to pull"

[ -n "${WORK_DIR:-}" ] || die "WORK_DIR is not set, so the parent worktree of $id is unknown"
pwt="$WORK_DIR/$key/$parent"
bwt="$WORK_DIR/$key/$id"
harness="$WORK_DIR/$key/.harness"
[ -d "$pwt" ] || die "no parent worktree at $pwt; run worktree-add.sh $parent"

review="$harness/$id/review.md"
[ -f "$review" ] || die "no review of block $id at $review, so it is not merged"
verdict=$(awk '/^###[[:space:]]*Verdict[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$review" | tr -d '`')
case "$verdict" in
  'changes needed'*) die "the review of $id says $verdict; its blocking findings are a fix round before the merge" ;;
esac

arch="$harness/$id/arch.md"
risk=''
if [ -f "$arch" ]; then
  risk=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit } sub(/^risk:[[:space:]]*/, "") { print; exit }' "$arch")
fi
if [ "$risk" = high ] && [ -z "$confirmed" ]; then
  why=$(awk '/^###[[:space:]]*Risk[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$arch" | tr -d '`')
  printf 'block-mr-merge: block %s is rated high risk (%s) and is not merged: ask the human with the MR %s and the risk in %s, and after their yes run block-mr-merge.sh %s --confirmed\n' \
    "$id" "${why:-see arch.md}" "$url" "$arch" "$id" >&2
  exit 3
fi

fjson="$harness/$parent/forge.json"
[ -f "$fjson" ] || die "no forge settings at $fjson; block-mr.sh writes them when it opens the first block MR of $parent"
conf=$(tr -d ' \n\t' < "$fjson")
case "$conf" in
  *'"pipeline_must_succeed":true'*)
    case "$conf" in *'"skipped_counts_as_success":true'*) class=B ;; *) class=C ;; esac ;;
  *) class=A ;;
esac
method=$(printf '%s' "$conf" | sed -n 's/.*"merge_method":"\([^"]*\)".*/\1/p')

case "$(printf '%s' "$url" | sed -n 's#^[a-zA-Z+]*://\([^/]*\)/.*#\1#p')" in
  github.com) forge=gh ;;
  *) forge=glab ;;
esac
if [ "$forge" = gh ]; then
  set -- gh pr merge "$url" --merge --delete-branch
  [ "$class" != C ] || set -- "$@" --auto
else
  if [ "$class" = C ]; then set -- glab mr merge "$url" --auto-merge --remove-source-branch --yes
  else set -- glab mr merge "$url" --auto-merge=false --remove-source-branch --yes; fi
fi
rebase=''
[ "$forge" = gh ] || [ "${method:-merge}" = merge ] || rebase=1

if [ -n "$dry" ]; then
  [ -z "$rebase" ] || printf 'when the forge reports the MR as need_rebase: glab mr rebase %s --skip-ci\n' "$url"
  printf '%s\n' "$*"
  printf 'git -C %s pull --ff-only origin %s\n' "$pwt" "$work"
  printf 'git -C %s worktree remove --force %s\n' "$pwt" "$bwt"
  printf 'git -C %s branch -D %s\n' "$pwt" "$branch"
  printf "cd %s && %s/state-report.sh --task %s --set-status done --message 'chore(%s): its MR is merged'\n" \
    "$pwt" "$bin" "$id" "$id"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

view() { # the MR as the forge prints it, empty when the call fails
  if [ "$forge" = gh ]; then gh pr view "$url" --json state 2>/dev/null || :
  else glab mr view "$url" -F json 2>/dev/null || :; fi
}
is_merged() { printf '%s' "$1" | grep -qiE '"state"[[:space:]]*:[[:space:]]*"merged"'; }

json=$(view)
if ! is_merged "$json"; then
  if [ -n "$rebase" ] && printf '%s' "$json" | grep -qE '"detailed_merge_status"[[:space:]]*:[[:space:]]*"need_rebase"'; then
    glab mr rebase "$url" --skip-ci >/dev/null 2>"$tmp/rebase.err" \
      || die "glab mr rebase $url failed: $(cat "$tmp/rebase.err")"
    # why: the forge rebases in the background, and a merge asked for before it is through is refused
    n=0
    while json=$(view); printf '%s' "$json" | grep -qE '"rebase_in_progress"[[:space:]]*:[[:space:]]*true'; do
      n=$((n + 1))
      [ "$n" -le 90 ] || die "the rebase of $url is still running after three minutes; run this again once it is through"
      sleep 2
    done
  fi
  merr=''
  "$@" >/dev/null 2>"$tmp/merge.err" || merr=$(cat "$tmp/merge.err")
  json=$(view)
  if ! is_merged "$json"; then
    if [ "$class" = C ] && [ -z "$merr" ]; then
      printf 'block-mr-merge: %s merges once its pipeline is green; run block-mr-merge.sh %s again after that\n' "$id" "$id" >&2
      printf '%s auto-merge %s\n' "$id" "$url"
      exit 0
    fi
    die "the forge did not merge $url: ${merr:-it still reports the MR open}"
  fi
fi

git -C "$pwt" pull -q --ff-only origin "$work" >/dev/null 2>"$tmp/pull.err" \
  || die "$url is merged, but $pwt could not fast-forward to origin/$work: $(cat "$tmp/pull.err"). Fix it and run this again"

# the merge is in, so what the block worktree still holds is disposable (the block-merge.sh reasoning)
if [ -e "$bwt" ]; then
  git -C "$pwt" worktree remove --force "$bwt" >/dev/null 2>"$tmp/wt.err" \
    || printf 'block-mr-merge: %s is merged, but its worktree %s could not be removed: %s\n' "$id" "$bwt" "$(cat "$tmp/wt.err")" >&2
fi
# why: a squash merge leaves the block branch no ancestor of the work branch, so -d would refuse what is merged
if git -C "$pwt" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$pwt" branch -D "$branch" >/dev/null 2>"$tmp/br.err" \
    || printf 'block-mr-merge: %s is merged, but its branch %s could not be deleted: %s\n' "$id" "$branch" "$(cat "$tmp/br.err")" >&2
fi

# invariant: state-report.sh is the one writer of task frontmatter; it resolves the state clone from the cwd,
# invariant: so the report is made from the parent worktree
( cd "$pwt" && "$bin/state-report.sh" --task "$id" --set-status done --message "chore($id): its MR is merged" ) \
  >/dev/null 2>"$tmp/report.err" \
  || die "$url is merged, but state-report.sh could not set $id done: $(cat "$tmp/report.err")"
printf '%s merged %s\n' "$id" "$url"
