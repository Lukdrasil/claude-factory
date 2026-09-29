#!/bin/sh
# The watcher of the stacked block MRs (T-164, ADR-0057): it reads every block MR of one parent through gh or
# glab and prints one line per state change since its last run, so the coordinator learns what the developer
# did on the forge without reading any MR itself. The parent's own task MR is watched the same way (F31), so its
# merge by the human is a `<T-id> merged` line; the parent is set done by task-done.sh, not here.
#
#   mr-watch.sh <T-NNN> [--once] [--interval <s>] [--comments <block-id>] [--state <dir>]
#
# The lines are `<block> merged`, `<block> changes-requested`, `<block> new-comments <n>`, `<block> ci-failed`
# and `<block> approved`, and what has already been reported is kept in
# `<root>/<key>/.harness/<T-NNN>/mr-watch.state`, one `<block> <state> <comment count>` per line. Without
# `--once` the pass repeats every five minutes, `--interval <s>` sets another period, and the coordinator arms
# the loop through the Monitor tool. `--comments <block-id>` prints that MR's review threads and exits.
#
# On `merged` the watcher does the two things the stack needs: every block MR still targeting the merged
# block's branch is retargeted at the session branch (and its `base:` follows in its progress file), and the
# merged block is set `done` through state-report.sh. The forge is chosen by the MR's own host, the routing of
# bin/forge.sh: github.com goes to gh, every other host to glab.
#
# Exit 0 after a pass (or after the loop is interrupted). Exit 1 with the reason on stderr when no parent id is
# given, when the id is not of the shape T-NNN, when it resolves to no task file, or when --comments names a
# block with no MR.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'mr-watch: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

id='' once='' interval=300 comments='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --once) once=1; shift ;;
    --interval) [ $# -ge 2 ] || die "--interval needs a value"; interval=$2; shift 2 ;;
    --comments) [ $# -ge 2 ] || die "--comments needs a value"; comments=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one parent id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: mr-watch.sh <T-NNN> [--once] [--interval <s>] [--comments <block-id>] [--state <dir>]"
is_parent_id "$id" || die "'$id' is not a parent task id of the shape T-NNN"

# see: solve-next.sh, the same resolution: $WORK_DIR/state when it is a clone, else what the cwd resolves to
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
harness="$root/$key/.harness/$id"
# invariant: state-report.sh resolves its state clone from the cwd, so the report is made from the session
# worktree of the parent, or from the work directory of the repo when the worktree is not there any more
report_dir="$root/$key/$id"
[ -d "$report_dir" ] || report_dir="$root/$key"
[ -d "$report_dir" ] || report_dir=$(pwd)
statefile="$harness/mr-watch.state"

fm() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }
nullable() { case "$1" in null|'~'|'') printf '' ;; *) printf '%s' "$1" ;; esac; }

session_branch=$(nullable "$(fm "$task" branch)")

progress_of() { printf '%s/repos/%s/progress/%s.md' "$state" "$key" "$1"; }
base_of() { # <block id>: the base its worktree was cut from, the session branch when it recorded none
  bo=$(sed -n 's/^base:[[:space:]]*//p' "$(progress_of "$1")" 2>/dev/null | head -n1)
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

forge_of() { # <mr url>: the tool that speaks to that host
  case "$(printf '%s' "$1" | sed -n 's#^[a-zA-Z+]*://\([^/]*\)/.*#\1#p')" in
    github.com) printf 'gh' ;;
    *) printf 'glab' ;;
  esac
}

view() { # <mr url>: the MR as the forge prints it, empty when the call fails
  case "$(forge_of "$1")" in
    gh) gh pr view "$1" --json state,reviewDecision,comments,statusCheckRollup 2>/dev/null || : ;;
    *) glab mr view "$1" -F json 2>/dev/null || : ;;
  esac
}

if [ -n "$comments" ]; then
  ctask=$(task_of "$comments" || :)
  [ -n "$ctask" ] || die "$comments resolves to no task file under $state/repos/*/tasks"
  curl_url=$(nullable "$(fm "$ctask" mr_url)")
  [ -n "$curl_url" ] || die "block $comments carries no mr_url, so it has no review threads yet"
  case "$(forge_of "$curl_url")" in
    gh) gh pr view "$curl_url" --comments ;;
    *) glab mr view "$curl_url" --comments ;;
  esac
  exit 0
fi

# the state of one MR as one word, in the order a coordinator acts on it: a merged MR is news whatever else it
# carries, a red pipeline before a review verdict
state_word() { # <the forge's json>
  if printf '%s' "$1" | grep -qiE '"(state|merge_status)"[[:space:]]*:[[:space:]]*"merged"'; then
    printf 'merged'
  elif printf '%s' "$1" | grep -qiE '"(conclusion|status|detailed_merge_status)"[[:space:]]*:[[:space:]]*"(failure|failed|ci_must_pass)"'; then
    printf 'ci-failed'
  elif printf '%s' "$1" | grep -qiE '"(reviewDecision|review_decision)"[[:space:]]*:[[:space:]]*"changes_requested"|"changes_requested"[[:space:]]*:[[:space:]]*true'; then
    printf 'changes-requested'
  elif printf '%s' "$1" | grep -qiE '"(reviewDecision|review_decision)"[[:space:]]*:[[:space:]]*"approved"|"approved"[[:space:]]*:[[:space:]]*true'; then
    printf 'approved'
  else
    printf 'open'
  fi
}

# GitLab counts the notes itself; GitHub hands over the array, so its elements are counted here
comment_count() { # <the forge's json>
  n=$(printf '%s' "$1" | sed -n 's/.*"user_notes_count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)
  [ -n "$n" ] || n=$(printf '%s' "$1" | grep -o '"body"' | wc -l | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  printf '%s' "$n"
}

remembered() { # <block> <field number>: what the last pass wrote, or the empty string
  [ -f "$statefile" ] || return 0
  awk -v b="$1" -v f="$2" '$1 == b { print $f; exit }' "$statefile"
}

retarget() { # <the merged block> <its branch>
  [ -n "$session_branch" ] || return 0
  for c in $blocks; do
    [ "$c" != "$1" ] || continue
    [ "$(base_of "$c")" = "$2" ] || continue
    ctask=$(task_of "$c" || :)
    [ -n "$ctask" ] || continue
    curl_url=$(nullable "$(fm "$ctask" mr_url)")
    if [ -n "$curl_url" ]; then
      case "$(forge_of "$curl_url")" in
        gh) gh pr edit "$curl_url" --base "$session_branch" >/dev/null 2>&1 || : ;;
        *) glab mr update "$curl_url" --target-branch "$session_branch" >/dev/null 2>&1 || : ;;
      esac
    fi
    cp="$(progress_of "$c")"
    if [ -f "$cp" ]; then
      awk -v b="$session_branch" '/^base:[[:space:]]*/ { if (!d) { print "base: " b; d = 1 } next }
        { print } END { if (!d) print "base: " b }' "$cp" > "$cp.tmp" && mv -f "$cp.tmp" "$cp"
    fi
    printf '%s retargeted %s\n' "$c" "$session_branch"
  done
}

pass() {
  mkdir -p "$harness"
  new="$harness/mr-watch.state.new"
  : > "$new"
  for b in $blocks $id; do
    btask=$(task_of "$b" || :)
    [ -n "$btask" ] || continue
    url=$(nullable "$(fm "$btask" mr_url)")
    [ -n "$url" ] || continue
    json=$(view "$url")
    [ -n "$json" ] || { printf '%s %s %s\n' "$b" "$(remembered "$b" 2)" "$(remembered "$b" 3)" >> "$new"; continue; }
    w=$(state_word "$json")
    n=$(comment_count "$json")
    was=$(remembered "$b" 2)
    wasn=$(remembered "$b" 3)
    case "$wasn" in ''|*[!0-9]*) wasn=0 ;; esac
    if [ "$w" != "$was" ] && [ "$w" != open ]; then
      printf '%s %s\n' "$b" "$w"
      if [ "$w" = merged ] && [ "$b" != "$id" ]; then
        branch=$(nullable "$(fm "$btask" branch)")
        [ -z "$branch" ] || retarget "$b" "$branch"
        ( cd "$report_dir" && "$bin/state-report.sh" --task "$b" --set-status done \
            --message "chore($b): its MR is merged" ) >/dev/null 2>"$harness/report.err" \
          || printf 'mr-watch: %s is merged but state-report.sh could not set it done (%s); do it and run this again\n' \
               "$b" "$(cat "$harness/report.err")" >&2
      fi
    fi
    if [ "$n" -gt "$wasn" ]; then printf '%s new-comments %s\n' "$b" "$((n - wasn))"; fi
    printf '%s %s %s\n' "$b" "$w" "$n" >> "$new"
  done
  mv -f "$new" "$statefile"
}

while :; do
  pass
  [ -z "$once" ] || break
  sleep "$interval"
done
exit 0
