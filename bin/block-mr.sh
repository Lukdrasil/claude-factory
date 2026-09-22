#!/bin/sh
# One MR per block (T-164, ADR-0057): once block-verify.sh is green, the block branch is pushed and an MR is
# opened whose target is the block's base, the branch worktree-add.sh cut it from and recorded as `base:` in
# the block's progress file. The description is built like mr-open.sh does for the parent, from the block's
# progress file, under 120 words. The URL is written into the block's `mr_url:` through state-report.sh.
#
#   block-mr.sh <block-id> [--dry-run] [--state <dir>] [--worktree <dir>]
#
# The forge follows the origin host, the routing of bin/forge.sh: github.com goes to gh, every other host to
# glab. --dry-run prints the push, the create and the update commands and the description and exits 0,
# touching neither the forge nor the state clone. A block whose task file already carries an mr_url is a
# resume: nothing is created, the existing MR is printed, and its description is refreshed when the freshly
# built one differs from what the forge carries. Why the refresh: MR !414 went out with a truncated bullet, a
# re-run of this script only printed the URL, and the body was then written by hand with the harness footer in
# it (see bin/attribution-gate.sh). stdout stays one line, the URL; "description updated" goes to stderr, so
# every caller of this contract keeps reading what it read before.
#
# Exit 0 with the MR URL on stdout. Exit 1 with the reason on stderr when the block resolves to no task file,
# when it carries no branch, when its progress file has no `## Done` or `## Evidence` bullets, when the
# description runs over 120 words, when there is no origin remote, or when the push or the forge refuses.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'block-mr: %s\n' "$1" >&2; exit 1; }

id='' dry='' state='' worktree=''
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --worktree) [ $# -ge 2 ] || die "--worktree needs a value"; worktree=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one block id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: block-mr.sh <block-id> [--dry-run] [--state <dir>] [--worktree <dir>]"
case "$id" in
  T-[0-9][0-9][0-9]-[0-9][0-9]) ;;
  *) die "'$id' is not a block id of the shape T-NNN-NN; the parent's MR is bin/mr-open.sh" ;;
esac

# see: worktree-add.sh, the same resolution: $WORK_DIR/state when it is a clone, else what the cwd resolves to
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
key=${task#"$state/repos/"}
key=${key%%/*}

field() { sed -n "s/^$1:[[:space:]]*//p" "$task" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }
branch=$(field branch)
[ -n "$branch" ] && [ "$branch" != null ] || die "block $id has no 'branch:' field; run worktree-add.sh $id first"
have=$(field mr_url)
[ "$have" != null ] || have=''

goal=$(awk '/^#+[[:space:]]*Goal[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$task")
[ -n "$goal" ] || die "block $id has no '# Goal' line to title the MR with"
reason=$(mr_title_check "$goal" "$key") || die "block $id: $reason; fix the '# Goal' line of $task"

progress="$state/repos/$key/progress/$id.md"
[ -f "$progress" ] || die "no progress file at $progress"

# why: the base is what worktree-add.sh recorded when it cut the branch; the parent's branch is the fallback
# why: because that is where a block with no dependency was cut from anyway
base=$(sed -n 's/^base:[[:space:]]*//p' "$progress" | head -n1)
if [ -z "$base" ]; then
  parent=${id%-*}
  ptask=$(task_of "$parent" || :)
  [ -n "$ptask" ] || die "block $id has no 'base:' in $progress and its parent $parent resolves to no task file"
  base=$(sed -n 's/^branch:[[:space:]]*//p' "$ptask" | head -n1)
  [ -n "$base" ] && [ "$base" != null ] || die "block $id has no 'base:' in $progress and $parent has no branch:"
fi

# see: bin/mr-open.sh, the same description contract: the sections in its order, prose and not a nested list.
# why: a bullet wrapped over several physical lines used to lose everything after the first line, and MR !414
# went out with a half sentence in it. A continuation line, indented by two spaces or a tab, joins its bullet.
bullets() {
  awk -v h="$1" '
    $0 == h { f = 1; next }
    f && /^#/ { exit }
    !f { next }
    /^-[[:space:]]/ || /^-$/ { if (cur != "") print cur; sub(/^-[[:space:]]*/, ""); cur = $0; next }
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

if [ -z "$worktree" ]; then
  [ -n "${WORK_DIR:-}" ] || die "WORK_DIR is not set, so the block worktree is unknown; pass --worktree <dir>"
  worktree="$WORK_DIR/$key/$id"
fi
[ -d "$worktree" ] || die "no block worktree at $worktree"

if resolve_layout "$worktree/mr.md" "${WORK_DIR:-}"; then desc_dir=$LO_STAMP; else desc_dir="$worktree/.harness/$id"; fi
mkdir -p "$desc_dir"
desc="$desc_dir/mr.md"
{
  printf '**What changed** - %s\n' "$changed"
  printf '**Why** - %s\n' "$goal"
  printf '**How to verify** - %s\n' "$verify"
} > "$desc"

words=$(wc -w < "$desc" | tr -d '[:space:]')
[ "$words" -le 120 ] \
  || die "the description is $words words and the contract caps it at 120; shorten $progress"

remote=$(git -C "$worktree" remote get-url origin 2>/dev/null || :)
[ -n "$remote" ] || die "$worktree has no origin remote, so there is no forge to open the MR on"
host=$(printf '%s' "$remote" | sed -e 's#^[a-zA-Z+]*://##' -e 's#^[^@/]*@##' -e 's#[:/].*##')
case "$host" in
  github.com) forge=gh ;;
  *) forge=glab ;;
esac

if [ -n "$dry" ]; then
  printf 'git -C %s push --force-with-lease -u origin %s\n' "$worktree" "$branch"
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

cd "$worktree" || die "cannot enter $worktree"
git push --force-with-lease -u origin "$branch" >/dev/null 2>"$desc_dir/push.err" \
  || die "the push of $branch failed; the reason is in $desc_dir/push.err and the description stayed at $desc"

# the description the forge carries now, compared with what this run built; \r so a forge that stores CRLF
# does not read as a difference on every run
json_field() { node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let o;try{o=JSON.parse(s)}catch(err){process.exit(1)}
const v=o[process.argv[1]];process.stdout.write(v==null?"":String(v))})' "$1" 2>/dev/null || :; }
want=$(tr -d '\r' < "$desc")

url=$have
out=''
if [ "$forge" = gh ]; then
  [ -n "$url" ] || url=$(gh pr view "$branch" --json url -q .url 2>/dev/null || :)
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
  # why: glab exits 1 and prints {"error":{"message":"no open merge request available for …"}} on STDOUT
  # why: for a branch with no MR, so "it printed something" is not "an MR exists": that read the error
  # why: object as a found MR, took no web_url out of it, never ran the create and blamed the forge for
  # why: printing no URL. The exit status is the answer, and a payload with no web_url is not one either.
  iid='' have_body=''
  if out=$(glab mr view "$branch" -F json 2>/dev/null); then
    [ -n "$url" ] || url=$(printf '%s\n' "$out" | sed -n 's/.*"web_url"[^"]*"\([^"]*\)".*/\1/p' | head -n1)
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

# invariant: state-report.sh is the one writer of task frontmatter, as in worktree-add.sh for the branch
if [ "$url" != "$have" ]; then
  "$(dirname -- "$0")/state-report.sh" --task "$id" --no-status --mr-url "$url" \
    --message "chore($id): MR open into $base" >/dev/null \
    || die "the MR $url is open but state-report.sh could not write it into $task: record it and run this again"
fi
printf '%s\n' "$url"
