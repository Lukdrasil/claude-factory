#!/bin/sh
# M8 of docs/plans/slim-harness.md: the MR contract of skills/_shared/mr-description.md as a script. It reads the
# task and its progress file, builds the description (the sections in the contract's order, under 120 words, no
# factory bookkeeping), writes it to <WORK_DIR>/<key>/.harness/<id>/mr.md and opens the MR from the task's session
# worktree with the task's `branch:` as source and the repo's default branch as target.
#
#   mr-open.sh <T-NNN> [--dry-run] [--issues <file>] [--state <dir>] [--worktree <dir>]
#
# The `Issues` file is what `mr-issue-linker` answered: its `closes #12` / `refs #30` lines become the `Issues`
# line, everything else in it is ignored. --dry-run prints the commands and the description and exits 0.
#
# It is not create-only. When the MR or PR is already open, the freshly built description is compared with the
# one the forge carries and pushed with `gh pr edit --body-file` / `glab mr update --description-file` when
# they differ, so a body is fixed by fixing the progress file and running this again. Why: MR !414 went out
# with a truncated bullet, a re-run only printed the URL, and the body was then written by hand with the
# harness footer in it (see bin/attribution-gate.sh). stdout stays one line, the URL; "description updated"
# goes to stderr, so every caller of this contract keeps reading what it read before.
#
# Exit 1 with the reason when the progress file carries no `## Done` or `## Evidence` bullets to build the
# description from, or when the description runs over the contract's 120 words.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'mr-open: %s\n' "$1" >&2; exit 1; }

id='' dry='' issues='' state='' worktree=''
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --issues) [ $# -ge 2 ] || die "--issues needs a value"; issues=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --worktree) [ $# -ge 2 ] || die "--worktree needs a value"; worktree=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one task id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: mr-open.sh <T-NNN> [--dry-run] [--issues <file>]"

if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    state=$(resolve_state_dir "$(pwd)")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$(pwd)/$state" ;; esac
  fi
fi
task=$(task_of "$id" || :)
[ -n "${task:-}" ] && [ -f "$task" ] || die "no task file with 'id: $id' in $state/repos/*/tasks/"

field() { sed -n "s/^$1:[[:space:]]*//p" "$task" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }
key=$(field repo)
branch=$(field branch)
[ -n "$key" ] || die "task $id has no 'repo:' field"
[ -n "$branch" ] || die "task $id has no 'branch:' field"

goal=$(awk '/^#+[[:space:]]*Goal[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$task")
[ -n "$goal" ] || die "task $id has no '# Goal' line to title the MR with"
reason=$(mr_title_check "$goal" "$key") || die "task $id: $reason; fix the '# Goal' line of $task"

progress="$state/repos/$key/progress/$id.md"
[ -f "$progress" ] || die "no progress file at $progress"

# the bullets of one section of the progress file, as one line: the description is prose, not a nested list.
# why: a bullet wrapped over several physical lines used to lose everything after the first line, and MR !414
# went out with a half sentence in it. A continuation line, indented by two spaces or a tab, joins its bullet.
bullets() {
  awk -v h="$1" '
    $0 == h { f = 1; next }
    f && /^#/ { exit }
    !f { next }
    /^-[[:space:]]/ || /^-$/ { if (cur != "") print cur; sub(/^-[[:space:]]*/, ""); sub(/^\[[ x]\][[:space:]]*/, ""); cur = $0; next }
    (/^[ ][ ]/ || /^\t/) && cur != "" { sub(/^[[:space:]]+/, ""); cur = cur " " $0; next }
    { if (cur != "") { print cur; cur = "" } }
    END { if (cur != "") print cur }
  ' "$progress"
}
oneline() { awk 'NF { s = s ? s "; " $0 : $0 } END { if (s) print s }'; }

changed=$(bullets '## Done' | oneline)
[ -n "$changed" ] || die "$progress has no '## Done' bullets for the What changed section"
verify=$(bullets '## Evidence' | oneline)
[ -n "$verify" ] || die "$progress has no '## Evidence' bullets for the How to verify section"
follow=$(bullets '## Follow-ups')

issue_line=''
if [ -n "$issues" ]; then
  [ -f "$issues" ] || die "no issues file at $issues"
  issue_line=$(awk 'tolower($1) ~ /^(closes|refs)$/ && match($0, /#[0-9]+/) {
      printf "%s%s %s", (n++ ? ", " : ""), (tolower($1) == "closes" ? "Closes" : "Refs"), substr($0, RSTART, RLENGTH)
    } END { if (n) print "" }' "$issues")
fi

if [ -z "$worktree" ]; then
  [ -n "${WORK_DIR:-}" ] || die "WORK_DIR is not set, so the session worktree is unknown; pass --worktree <dir>"
  worktree="$WORK_DIR/$key/$id"
fi
[ -d "$worktree" ] || die "no session worktree at $worktree"

if resolve_layout "$worktree/mr.md" "${WORK_DIR:-}"; then desc_dir=$LO_STAMP; else desc_dir="$worktree/.harness/$id"; fi
mkdir -p "$desc_dir"
desc="$desc_dir/mr.md"
{
  printf '**What changed** - %s\n' "$changed"
  printf '**Why** - %s\n' "$goal"
  if [ -n "$issue_line" ]; then printf '**Issues** - %s\n' "$issue_line"; fi
  printf '**How to verify** - %s\n' "$verify"
  if [ -n "$follow" ]; then
    printf '**Follow-ups**\n'
    printf '%s\n' "$follow" | sed 's/^/- /'
  fi
} > "$desc"

words=$(wc -w < "$desc" | tr -d '[:space:]')
[ "$words" -le 120 ] \
  || die "the description is $words words and the contract caps it at 120; shorten $progress"

base=''
if [ -f "$state/repos.yml" ]; then
  base=$(sed -n "s/^$key:.*default_branch:[[:space:]]*\([A-Za-z0-9._/-][A-Za-z0-9._/-]*\).*/\1/p" "$state/repos.yml" | head -n1)
fi
if [ -z "$base" ]; then
  base=$(git -C "$worktree" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || :)
fi
[ -n "$base" ] || base=main

remote=$(git -C "$worktree" remote get-url origin 2>/dev/null || :)
[ -n "$remote" ] || die "$worktree has no origin remote, so there is no forge to open the MR on"
host=$(printf '%s' "$remote" | sed -e 's#^[a-zA-Z+]*://##' -e 's#^[^@/]*@##' -e 's#[:/].*##')
# why: the routing of bin/forge.sh, so a read and a write land on the same instance: github.com goes to gh,
# every other host to glab
case "$host" in
  github.com) forge=gh ;;
  *) forge=glab ;;
esac

if [ -n "$dry" ]; then
  if [ "$forge" = gh ]; then
    printf 'gh pr create --base %s --head %s --title "%s" --body-file %s\n' "$base" "$branch" "$goal" "$desc"
    printf 'or, when the PR is already open and its body differs: gh pr edit <url> --body-file %s\n' "$desc"
  else
    printf 'glab mr create --source-branch %s --target-branch %s --title "%s" --description-file %s --yes\n' \
      "$branch" "$base" "$goal" "$desc"
    printf 'or, when the MR is already open and its description differs: glab mr update <iid> --description-file %s\n' "$desc"
  fi
  cat "$desc"
  exit 0
fi

# the description the forge carries now, compared with what this run built; \r so a forge that stores CRLF
# does not read as a difference on every run
json_field() { node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let o;try{o=JSON.parse(s)}catch(err){process.exit(1)}
const v=o[process.argv[1]];process.stdout.write(v==null?"":String(v))})' "$1" 2>/dev/null || :; }
want=$(tr -d '\r' < "$desc")

cd "$worktree" || die "cannot enter $worktree"
url=''
out=''
if [ "$forge" = gh ]; then
  url=$(gh pr view "$branch" --json url -q .url 2>/dev/null || :)
  if [ -n "$url" ]; then
    have_body=$(gh pr view "$branch" --json body -q .body 2>/dev/null | tr -d '\r' || :)
    if [ "$have_body" != "$want" ]; then
      gh pr edit "$url" --body-file "$desc" >/dev/null \
        || die "gh pr edit failed for $url; the description stayed at $desc"
      printf 'description updated on %s\n' "$url" >&2
    fi
  else
    out=$(gh pr create --base "$base" --head "$branch" --title "$goal" --body-file "$desc") \
      || die "gh pr create failed; the description stayed at $desc"
  fi
else
  # why: glab exits 1 and prints {"error":{"message":"no open merge request available for …"}} on STDOUT for
  # why: a branch with no MR, so "it printed something" is not "an MR exists": that read the error object as
  # why: a found MR, took no web_url out of it, never ran the create and blamed the forge for printing no
  # why: URL. The exit status is the answer, and a payload with no web_url is not one either.
  iid='' have_body=''
  if out=$(glab mr view "$branch" -F json 2>/dev/null); then
    url=$(printf '%s\n' "$out" | sed -n 's/.*"web_url"[^"]*"\([^"]*\)".*/\1/p' | head -n1)
    iid=$(printf '%s' "$out" | json_field iid)
    have_body=$(printf '%s' "$out" | json_field description | tr -d '\r')
    out=''
  fi
  if [ -n "$url" ]; then
    [ -n "$iid" ] || iid=${url##*/}
    if [ "$have_body" != "$want" ]; then
      case "$iid" in
        *[!0-9]*|'') printf 'the MR iid is unknown, so %s kept its description\n' "$url" >&2 ;;
        *) glab mr update "$iid" --description-file "$desc" >/dev/null \
             || die "glab mr update $iid failed; the description stayed at $desc"
           printf 'description updated on %s\n' "$url" >&2 ;;
      esac
    fi
  else
    out=$(glab mr create --source-branch "$branch" --target-branch "$base" --title "$goal" \
      --description-file "$desc" --yes) || die "glab mr create failed; the description stayed at $desc"
  fi
fi
if [ -z "$url" ]; then
  url=$(printf '%s\n' "$out" | grep -oE 'https?://[^ )"]+' | tail -n1 || :)
fi
[ -n "$url" ] || die "the forge printed no URL; the MR may still have been created, check $branch"
printf '%s\n' "$url"
