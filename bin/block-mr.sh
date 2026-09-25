#!/bin/sh
# One MR per block (T-164, ADR-0057; 3.4 of the agent-org plan): once block-verify.sh is green and the
# code-reviewer and the architecture-auditor have judged the block diff, the block branch is pushed and an MR is
# opened whose target is the block's base, the work branch worktree-add.sh cut it from and recorded as `base:` in
# the block's progress file. The URL is written into the block's `mr_url:` through state-report.sh.
#
#   block-mr.sh <block-id> [--dry-run] [--state <dir>] [--worktree <dir>]
#
# The description is **What changed**, **Why** and **How to verify** from the block's progress file, as
# mr-open.sh builds them for the parent and under the same 120 words, then **Risk** from
# `.harness/<block>/arch.md` (the level, its sentence and the five reasons: blast radius, contracts, security,
# data, drift), **Verified** from the `.harness/<block>/verify.txt` block-verify.sh wrote, and **Review** from
# the verdict of `.harness/<block>/review.md`. The 120 words bound the part the progress file writes; the other
# three are bounded by the agents' own contracts. A block with no review.md is refused, and so is a block whose
# worktree has docs/architecture/ but no arch.md; without docs/architecture/ the auditor skips and the risk
# reads `not rated`. A verify.txt that says red is refused too.
#
# The pipeline of a block MR is skipped. The forge settings are read once per task, from the forge on the first
# block, into `.harness/<T-id>/forge.json` (`merge_method`, `pipeline_must_succeed`, `skipped_counts_as_success`),
# and the class decides the push:
#   A  pipeline not required: `git push -o ci.skip`
#   B  pipeline required, a skipped one counts as success: an empty head commit
#      `ci: skip the pipeline of a block MR [skip ci]` before a plain push, added once
#   C  pipeline required, a skipped one does not count: a plain push (block-mr-merge.sh merges on green)
# The work branch goes to origin before the first block MR targets it, with `-o ci.skip` in class A and B. A
# remote that takes no push options (GitHub, whose workflows skip a block MR by their branch filter) gets the
# same push without them. `[skip ci]` never reaches the MR title, so it never reaches a merge or squash commit:
# a `# Goal` that carries it is refused.
#
# The forge follows the origin host, the routing of bin/forge.sh: github.com goes to gh, every other host to
# glab. --dry-run prints the class, the commit and the pushes it would make, the create and the update commands
# and the description and exits 0, touching neither the forge nor the state clone; without a forge.json it reads
# the settings from the forge and does not write them. A block whose task file already carries an mr_url is a
# resume: nothing is created, the existing MR is printed, and its description is refreshed when the freshly
# built one differs from what the forge carries. Why the refresh: MR !414 went out with a truncated bullet, a
# re-run of this script only printed the URL, and the body was then written by hand with the harness footer in
# it (see bin/attribution-gate.sh). stdout stays one line, the URL; "description updated" goes to stderr, so
# every caller of this contract keeps reading what it read before.
#
# Exit 0 with the MR URL on stdout. Exit 1 with the reason on stderr when the block resolves to no task file,
# when it carries no branch, when its progress file has no `## Done` or `## Evidence` bullets, when the
# description runs over 120 words, when a review, audit or verification is missing or refuses, when there is
# no origin remote, or when the forge settings, the push or the forge refuses.
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
is_block_id "$id" || die "'$id' is not a block id of the shape T-<n>-<NN> or T-<ALIAS>-<n>-<NN>; the parent's MR is bin/mr-open.sh"

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
case "$task" in */archive/*) die "block $id is archived in $task, its MR is long merged" ;; esac
key=${task#"$state/repos/"}
key=${key%%/*}
parent=${id%-*}

goal=$(awk '/^#+[[:space:]]*Goal[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$task")
[ -n "$goal" ] || die "block $id has no '# Goal' line to title the MR with"
reason=$(mr_title_check "$goal" "$key") || die "block $id: $reason; fix the '# Goal' line of $task"
# why: the title is what a merge commit and a squash commit carry, and a `[skip ci]` there skips the pipeline of
# why: the work branch and of the task MR after it (3.4)
if printf '%s' "$goal" | grep -qiE '\[(skip ci|ci skip)\]'; then
  die "block $id: the '# Goal' line carries [skip ci], which would reach the merge commit; drop it from $task"
fi

field() { sed -n "s/^$1:[[:space:]]*//p" "$task" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }
branch=$(field branch)
[ -n "$branch" ] && [ "$branch" != null ] || die "block $id has no 'branch:' field; run worktree-add.sh $id first"
have=$(field mr_url)
[ "$have" != null ] || have=''

progress="$state/repos/$key/progress/$id.md"
[ -f "$progress" ] || die "no progress file at $progress"

# why: the base is what worktree-add.sh recorded when it cut the branch; the parent's branch is the fallback
# why: because that is where a block with no dependency was cut from anyway
base=$(sed -n 's/^base:[[:space:]]*//p' "$progress" | head -n1)
if [ -z "$base" ]; then
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

words=$(printf '**What changed** - %s\n**Why** - %s\n**How to verify** - %s\n' "$changed" "$goal" "$verify" \
  | wc -w | tr -d '[:space:]')
[ "$words" -le 120 ] \
  || die "the description is $words words and the contract caps it at 120; shorten $progress"

if [ -z "$worktree" ]; then
  [ -n "${WORK_DIR:-}" ] || die "WORK_DIR is not set, so the block worktree is unknown; pass --worktree <dir>"
  worktree="$WORK_DIR/$key/$id"
fi
[ -d "$worktree" ] || die "no block worktree at $worktree"

if resolve_layout "$worktree/mr.md" "${WORK_DIR:-}"; then desc_dir=$LO_STAMP; else desc_dir="$worktree/.harness/$id"; fi
mkdir -p "$desc_dir"
desc="$desc_dir/mr.md"

# the lines under one `### <name>` heading of an agent's report, up to the next heading
section() { # <file> <name>
  awk -v h="$2" '$0 ~ "^###[[:space:]]*" h "[[:space:]]*$" { f = 1; next } f && /^#/ { exit } f && NF { print }' "$1"
}

review="$desc_dir/review.md"
[ -f "$review" ] || die "no review of block $id at $review: the code-reviewer's report on the block diff goes there after block-verify.sh"
verdict=$(section "$review" Verdict | head -n1 | tr -d '`')
[ -n "$verdict" ] || die "$review has no '### Verdict' line"

arch="$desc_dir/arch.md"
if [ -f "$arch" ]; then
  risk=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit } sub(/^risk:[[:space:]]*/, "") { print; exit }' "$arch")
  case "$risk" in low|medium|high) ;; *) die "$arch carries no 'risk: low|medium|high' in its frontmatter" ;; esac
  risk_line=$(section "$arch" Risk | grep -v '^-' | head -n1 | tr -d '`')
  [ -n "$risk_line" ] || risk_line=$risk
  reasons=$(section "$arch" Risk | grep '^- ' || :)
elif [ -d "$worktree/docs/architecture" ]; then
  die "no architecture audit of block $id at $arch: the architecture-auditor writes it after block-verify.sh"
else
  risk_line='not rated: the repo has no docs/architecture/, so no architecture audit ran'
  reasons=''
fi

verified=''
if [ -f "$desc_dir/verify.txt" ]; then
  [ "$(sed -n 's/^verdict:[[:space:]]*//p' "$desc_dir/verify.txt" | head -n1)" != red ] \
    || die "block-verify.sh reported red for $id in $desc_dir/verify.txt; make it green and run block-verify.sh again"
  verified=$(awk 'NR > 1 && NF { gsub(/[[:space:]]+/, " "); s = s ? s "; " $0 : $0 } END { print s }' "$desc_dir/verify.txt")
fi

{
  printf '**What changed** - %s\n' "$changed"
  printf '**Why** - %s\n' "$goal"
  printf '**Risk** - %s\n' "$risk_line"
  # why: markdown reads a line right after a list item as part of that item, so the list ends on a blank line
  if [ -n "$reasons" ]; then printf '%s\n\n' "$reasons"; fi
  printf '**How to verify** - %s\n' "$verify"
  if [ -n "$verified" ]; then printf '**Verified** - %s\n' "$verified"; fi
  printf '**Review** - %s\n' "$verdict"
} > "$desc"

remote=$(git -C "$worktree" remote get-url origin 2>/dev/null || :)
[ -n "$remote" ] || die "$worktree has no origin remote, so there is no forge to open the MR on"
# why: an http(s) origin keeps its port, the forge's own (a self-hosted GitLab on :8929); an ssh one drops it, the
# why: port of the ssh daemon, and an scp-style git@host:group/repo is the bare host
case "$remote" in
  http://*|https://*) host=$(printf '%s' "$remote" | sed -e 's#^[a-z]*://##' -e 's#^[^@/]*@##' -e 's#/.*##') ;;
  *) host=$(printf '%s' "$remote" | sed -e 's#^[a-zA-Z+]*://##' -e 's#^[^@/]*@##' -e 's#[:/].*##') ;;
esac
case "$host" in
  github.com) forge=gh ;;
  *) forge=glab ;;
esac

# the forge settings of the task, read from the forge once and kept beside the parent's other stamps
fjson="${desc_dir%/*}/$parent/forge.json"
settings() { # the three fields as one json line, from the forge's own answer
  if [ "$forge" = gh ]; then
    # why: GitHub requires a pipeline only through the protection of the target branch, and a workflow its
    # why: branch filter never starts reports nothing, so a skipped run cannot count there
    req=false
    if (cd "$worktree" && gh api "repos/{owner}/{repo}/branches/$base/protection/required_status_checks") >/dev/null 2>&1; then req=true; fi
    (cd "$worktree" && gh api 'repos/{owner}/{repo}') | REQ=$req node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let o;try{o=JSON.parse(s)}catch(e){process.exit(1)}
const m=o.allow_merge_commit?"merge":o.allow_squash_merge?"squash":"rebase";
process.stdout.write(JSON.stringify({merge_method:m,pipeline_must_succeed:process.env.REQ==="true",skipped_counts_as_success:false})+"\n")})'
  else
    (cd "$worktree" && glab api 'projects/:id') | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let o;try{o=JSON.parse(s)}catch(e){process.exit(1)}
if(!o.merge_method)process.exit(1);
process.stdout.write(JSON.stringify({merge_method:o.merge_method,pipeline_must_succeed:!!o.only_allow_merge_if_pipeline_succeeds,skipped_counts_as_success:!!o.allow_merge_on_skipped_pipeline})+"\n")})'
  fi
}
if [ -f "$fjson" ]; then
  conf=$(cat "$fjson")
else
  conf=$(settings) || conf=''
  [ -n "$conf" ] || die "the forge settings of $parent could not be read from $forge; forge.json stays unwritten at $fjson"
  if [ -z "$dry" ]; then
    mkdir -p "${fjson%/*}"
    printf '%s\n' "$conf" > "$fjson"
  fi
fi
is_true() { printf '%s' "$conf" | tr -d ' \n\t' | grep -q "\"$1\":true"; }
if ! is_true pipeline_must_succeed; then
  class=A; popt=ci.skip; bopt=ci.skip; class_why='pipeline not required, the push carries -o ci.skip'
elif is_true skipped_counts_as_success; then
  class=B; popt=''; bopt=ci.skip; class_why='pipeline required, a skipped one counts, an empty [skip ci] head commit'
else
  class=C; popt=''; bopt=''; class_why='pipeline required, a skipped one does not count, a plain push'
fi

skip_msg='ci: skip the pipeline of a block MR [skip ci]'
need_skip=''
if [ "$class" = B ] && [ "$(git -C "$worktree" log -1 --format=%s)" != "$skip_msg" ]; then need_skip=1; fi

if [ -n "$dry" ]; then
  printf 'class %s: %s (%s)\n' "$class" "$class_why" "$fjson"
  printf 'when %s is not on origin yet: git -C %s push%s -u origin %s\n' "$base" "$worktree" "${bopt:+ -o $bopt}" "$base"
  if [ -n "$need_skip" ]; then printf "git -C %s commit --allow-empty -m '%s'\n" "$worktree" "$skip_msg"; fi
  printf 'git -C %s push%s --force-with-lease -u origin %s\n' "$worktree" "${popt:+ -o $popt}" "$branch"
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

push() { # <push option or empty> <git push arguments>...
  po=$1; shift
  if [ -n "$po" ]; then
    git push -o "$po" "$@" >/dev/null 2>"$desc_dir/push.err" && return 0
    # why: a remote that advertises no push options refuses the whole push; GitHub is one, and its workflows
    # why: skip a block MR by their branch filter instead (3.4)
    grep -q 'push options' "$desc_dir/push.err" || return 1
  fi
  git push "$@" >/dev/null 2>"$desc_dir/push.err"
}

if ! git ls-remote --exit-code origin "refs/heads/$base" >/dev/null 2>&1; then
  push "$bopt" -u origin "$base" \
    || die "the push of the work branch $base failed; the reason is in $desc_dir/push.err"
fi
if [ -n "$need_skip" ]; then
  # a commit needs an identity; a bare CI or worker checkout may have none (the block-merge.sh fallback)
  ident=''
  [ -n "$(git config user.email || :)" ] || ident='-c user.name=harness -c user.email=harness@localhost'
  # shellcheck disable=SC2086
  git $ident commit -q --allow-empty -m "$skip_msg" || die "the empty [skip ci] commit could not be made in $worktree"
fi
push "$popt" --force-with-lease -u origin "$branch" \
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
