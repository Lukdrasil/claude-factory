#!/bin/sh
# The issue script: the one code path that creates an issue, and every issue it creates carries the ai-drafted
# label, the one sanctioned marker of the attribution rule (bin/attribution-gate.sh). It resolves the clone of a
# repo-key from repos.yml, takes host and owner/repo from the clone's origin and passes them as -R, so the
# caller's cwd does not matter. github.com goes to gh, every other host to glab, the routing of bin/forge.sh.
#
#   issue-create.sh <repo-key> --title <t> --body-file <f> [--state <dir>]
#
# stdout is the forge's output, the issue URL. Exit 1 with the reason on a missing key, clone, origin or body
# file, before any forge call.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'issue-create: %s\n' "$1" >&2; exit 1; }

key='' title='' body='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --title) [ $# -ge 2 ] || die "--title needs a value"; title=$2; shift 2 ;;
    --body-file) [ $# -ge 2 ] || die "--body-file needs a value"; body=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$key" ] || die "one repo-key at a time"; key=$1; shift ;;
  esac
done
[ -n "$key" ] && [ -n "$title" ] && [ -n "$body" ] \
  || die "usage: issue-create.sh <repo-key> --title <t> --body-file <f> [--state <dir>]"
[ -f "$body" ] || die "no body file at $body"

if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    state=$(resolve_state_dir "$(pwd)")
  fi
fi
clone=$(yml_field "$key" path)
[ -n "$clone" ] || die "no repo '$key' with a path in $state/repos.yml"
[ -d "$clone" ] || die "the clone of '$key' is missing at $clone"
remote=$(git -C "$clone" remote get-url origin 2>/dev/null || :)
[ -n "$remote" ] || die "$clone has no origin remote, so there is no forge to create the issue on"

host=$(printf '%s' "$remote" | sed -e 's#^[a-zA-Z+]*://##' -e 's#^[^@/]*@##' -e 's#[:/].*##')
repo=$(printf '%s' "$remote" | sed -e 's#^[a-zA-Z+]*://##' -e 's#^[^@/]*@##' -e 's#^[^:/]*[:/]##' -e 's#/*$##' -e 's#\.git$##')

case "$host" in
  github.com)
    gh label create ai-drafted -c 7057ff -d "Drafted by an agent" >/dev/null 2>&1 || :
    gh issue create -R "$host/$repo" --title "$title" --body-file "$body" --label ai-drafted ;;
  *)
    glab issue create -R "$host/$repo" --title "$title" --description-file "$body" --label ai-drafted ;;
esac
