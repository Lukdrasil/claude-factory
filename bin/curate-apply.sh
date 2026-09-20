#!/bin/sh
# The local twin of the dashboard's proposal gate (the Proposals page; StateRepository.CurateProposalAsync and
# EditProposalAsync), the posture without a dashboard (ADR-0050): approve moves a proposal to its target — the
# path without `proposals/`, an ADR proposal numbered on the way out — reject deletes it, edit rewrites it from
# a file; every decision exactly one commit with the dashboard's message. Nothing is pushed.
#
#   curate-apply.sh list [--state <dir>]                            the queued proposals, one relative path per line
#   curate-apply.sh approve <proposal> [<target>] [--reason <text>] [--state <dir>]
#   curate-apply.sh reject <proposal> [--reason <text>] [--state <dir>]
#   curate-apply.sh edit <proposal> --body <file> [--reason <text>] [--state <dir>]   cwd = the state clone unless --state
#
# Exit 1 with the reason when the proposal is not in the queue or the target is refused (it exists, is not .md,
# carries a backslash — a Windows separator git would keep as one filename segment — has an empty/./.. segment,
# stays under proposals/, or lies outside memory/global, repos/<key>/memory, repos/<key>/adr,
# repos/<key>/architecture, agents/<agent>/memory); nothing written. --reason appends " — <text>" to the fixed
# commit message.
set -eu

cmd='' proposal='' target='' body='' state='' commit_reason=''
die() { printf 'curate-apply: %s\n' "$1" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: curate-apply.sh list|approve|reject|edit [<proposal> [<target>]] [--body <file>] [--reason <text>] [--state <dir>]"
cmd=$1; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --body) [ $# -ge 2 ] || die "--body needs a value"; body=$2; shift 2 ;;
    --reason) [ $# -ge 2 ] || die "--reason needs a value"; commit_reason=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *)
      if [ -z "$proposal" ]; then proposal=$1
      elif [ -z "$target" ]; then target=$1
      else die "too many arguments"; fi
      shift ;;
  esac
done
# resolve_state_dir (lib-tasks.sh) is the one state-clone rule the hooks share: `../state` next to a product
# clone, the standalone layout's $WORK_DIR/state, otherwise the cwd
. "$(dirname -- "$0")/lib-tasks.sh"
[ -n "$state" ] || state=$(resolve_state_dir "$(pwd)")
[ -d "$state/.git" ] || die "$state is not a state clone — run from one or pass --state <dir>"

# StateRepository.Proposals over ProposalGlobs: the top level of the five queues, sorted bytewise.
list() {
  (cd "$state" && for q in repos/*/memory/proposals memory/global/proposals repos/*/adr/proposals repos/*/architecture/proposals agents/*/memory/proposals; do
    [ -d "$q" ] || continue
    for f in "$q"/*.md; do
      [ -f "$f" ] || continue
      printf '%s\n' "$f"
    done
  done) | LC_ALL=C sort
}

in_queue() { list | grep -qxF -- "$proposal" || die "$proposal is not in the queue"; }

repo_keys() {
  for d in "$state"/repos/*/; do
    [ -d "$d" ] || continue
    d=${d%/}; printf '%s\n' "${d##*/}"
  done
}

# StateRepository.Unprefixed / AdrNumber / AdrSlug / NextAdrNumber / AdrDestination / PrimaryTarget / CheckTarget.
unprefixed() { case "$1" in [Aa][Dd][Rr]-*) printf '%s\n' "${1#????}" ;; *) printf '%s\n' "$1" ;; esac; }

adr_number() { unprefixed "$1" | sed -n 's/^\([0-9][0-9]*\).*/\1/p' | sed 's/^0*//'; }

next_adr_number() { # <key> → one past the highest number filed in repos/<key>/adr/
  max=0
  for f in "$state/repos/$1/adr"/*.md; do
    [ -f "$f" ] || continue
    n=$(adr_number "${f##*/}")
    [ -n "$n" ] || n=0
    if [ "$n" -gt "$max" ]; then max=$n; fi
  done
  echo $((max + 1))
}

adr_slug() {
  rest=$(unprefixed "$1")
  case "$rest" in
    [0-9]*) printf '%s\n' "$rest" | sed 's/^[0-9]*-*//' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

adr_destination() { # <relative> → numbered when it is repos/<key>/adr/<name>, otherwise unchanged
  case "$1" in
    repos/*/adr/*)
      key=${1#repos/}; key=${key%%/*}
      name=${1#"repos/$key/adr/"}
      case "$name" in
        */*) printf '%s\n' "$1" ;;
        *) printf 'repos/%s/adr/ADR-%04d-%s\n' "$key" "$(next_adr_number "$key")" "$(adr_slug "$name")" ;;
      esac ;;
    *) printf '%s\n' "$1" ;;
  esac
}

primary_target() {
  case "$1" in
    repos/*/adr/proposals/*)
      key=${1#repos/}; key=${key%%/*}
      name=${1#"repos/$key/adr/proposals/"}
      case "$name" in */*) ;; *) adr_destination "repos/$key/adr/$name"; return ;; esac ;;
  esac
  printf '%s\n' "$1" | sed 's|/proposals/|/|'
}

check_target() { # <relative> → the reason on stdout, nothing when the target is allowed
  case "$1" in */*.md) ;; *) echo "the target must be a .md file in the state repo"; return ;; esac
  case "/$1/" in *\\*|*//*|*/./*|*/../*) echo "invalid path: $1"; return ;; esac
  case "/$1/" in */proposals/*) echo "the target must not stay in proposals"; return ;; esac
  roots="memory/global"
  for key in $(repo_keys); do roots="$roots repos/$key/memory repos/$key/adr repos/$key/architecture"; done
  case "$1" in agents/*/memory/*) return ;; esac
  for r in $roots; do
    case "$1" in "$r"/*) return ;; esac
  done
  echo "the target must live under $(printf '%s' "$roots" | sed 's/ /, /g'), agents/<agent>/memory"
}

commit() { # <message> <path>…
  msg=$1; shift
  [ -z "$commit_reason" ] || msg="$msg — $commit_reason"
  if [ -n "$(git -C "$state" config user.email || :)" ]; then
    git -C "$state" commit -q -m "$msg" -- "$@"
  else
    git -C "$state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$msg" -- "$@"
  fi
}

case "$cmd" in
  list)
    [ -z "$proposal" ] || die "list takes no proposal"
    list ;;
  approve)
    [ -n "$proposal" ] || die "usage: curate-apply.sh approve <proposal> [<target>] [--state <dir>]"
    in_queue
    dst=$(adr_destination "${target:-$(primary_target "$proposal")}")
    reason=$(check_target "$dst")
    [ -z "$reason" ] || die "$reason"
    [ ! -e "$state/$dst" ] || die "$dst already exists"
    mkdir -p "$state/$(dirname "$dst")"
    # an agent may leave its proposal untracked; git mv refuses a path git does not know, and a pathspec git
    # knows nothing about aborts the whole commit — so stage it first and name only the paths that survive
    git -C "$state" add -- "$proposal"
    git -C "$state" mv "$proposal" "$dst"
    if git -C "$state" cat-file -e "HEAD:$proposal" 2>/dev/null; then
      commit "chore(proposal): approve $proposal -> $dst" "$proposal" "$dst"
    else
      commit "chore(proposal): approve $proposal -> $dst" "$dst"
    fi ;;
  reject)
    [ -n "$proposal" ] && [ -z "$target" ] || die "usage: curate-apply.sh reject <proposal> [--state <dir>]"
    in_queue
    if git -C "$state" cat-file -e "HEAD:$proposal" 2>/dev/null; then
      git -C "$state" rm -q -f -- "$proposal"
      commit "chore(proposal): reject $proposal" "$proposal"
    else
      # never committed: there is nothing in the history to record, only the file to take away
      git -C "$state" rm -q -f --ignore-unmatch -- "$proposal"
      rm -f -- "$state/$proposal"
      echo "curate-apply: $proposal was never committed — removed, no commit to make" >&2
    fi ;;
  edit)
    [ -n "$proposal" ] && [ -z "$target" ] && [ -n "$body" ] || die "usage: curate-apply.sh edit <proposal> --body <file> [--state <dir>]"
    [ -f "$body" ] || die "$body is not a file"
    in_queue
    cat -- "$body" > "$state/$proposal"
    git -C "$state" add -- "$proposal"
    commit "chore(proposal): edit $proposal" "$proposal" ;;
  *) die "unknown subcommand '$cmd' — one of list, approve, reject, edit" ;;
esac
