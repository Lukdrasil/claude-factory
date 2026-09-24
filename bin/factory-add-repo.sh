#!/bin/sh
# Registers a product clone in the standalone state repo (ADR-0049): one repos.yml line with url, default_branch
# and path, and repos/<key>/toolset.md seeded from toolsets/<stack>.md. Two commits in the
# state repo, nothing pushed. Idempotent: a registered clone with a toolset is "nothing to do".
#
#   factory-add-repo.sh --root <dir> [--repo <clone-dir>] [--yes]
#
# The key is the basename of the origin URL without .git.
#
# Exit 0 = applied, or nothing to do. Exit 3 = changes pending, printed, not written (no --yes), the same gate
# factory-init.sh has, so the skill previews and reruns identically on both scripts.
set -eu

root='' repo='' yes=0
die() { printf 'factory-add-repo: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--repo)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --root) root=$2 ;; --repo) repo=$2 ;; esac
      shift 2 ;;
    --yes) yes=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
[ -n "$root" ] || die "--root <dir> is required"
[ -n "$repo" ] || repo=$(pwd)
root=$(printf '%s' "$root" | sed 's/\\/\//g; s:/*$::')
state="$root/state"
[ -f "$state/repos.yml" ] || die "$state/repos.yml does not exist - run factory-init.sh --root $root first"
plugin=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null | sed 's/\\/\//g') || die "$repo is not a git clone"
[ -n "$top" ] || die "$repo is not a git clone"
url=$(git -C "$top" remote get-url origin 2>/dev/null) || die "$top has no origin remote"
key=${url%/}; key=${key##*[/:]}; key=${key%.git}
printf '%s' "$key" | grep -qE '^[A-Za-z0-9_-]+$' || die "'$key' is not a usable repo key (letters, digits, - and _)"
branch=$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || :)
branch=${branch#origin/}; [ -n "$branch" ] || branch=main

commit() { # <message> <path...>
  m=$1; shift
  git -C "$state" add -- "$@"
  if [ -n "$(git -C "$state" config user.email || :)" ]; then
    git -C "$state" commit -q -m "$m" -- "$@"
  else
    git -C "$state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$m" -- "$@"
  fi
}

echo "$key"

# --- what is pending ---------------------------------------------------------------------------------------
need_yml=0
grep -q "^$key:" "$state/repos.yml" || need_yml=1

files=$(git -C "$top" ls-files)

# E (2026-09-22, MR !412): the plugin capped the MR title at 130 and the product repo's CI ran commitlint,
# whose config-conventional caps the header at 100 - the job failed on a title the factory had already opened.
# A clone that lints its own titles gets that cap written into its registry entry, so mr_title_check refuses
# the goal while the task is being authored instead of the forge refusing the MR.
. "$(dirname -- "$0")/lib-tasks.sh"
title_max='' title_src=''
if cc=$(commitlint_cap "$top"); then
  title_max=${cc%%	*}
  title_src=${cc#*	}
  echo "note: $title_src lints the MR title - mr_title_max: $title_max for $key"
fi

yml_line=$(printf '%s: {url: "%s", default_branch: %s, path: "%s"%s}' \
  "$key" "$url" "$branch" "$top" "${title_max:+, mr_title_max: $title_max}")

if printf '%s\n' "$files" | grep -qE '\.(sln|slnx|csproj)$'; then stack=dotnet
elif printf '%s\n' "$files" | grep -qE '(^|/)pyproject\.toml$'; then stack=python
elif printf '%s\n' "$files" | grep -qE '(^|/)package\.json$'; then stack=typescript
else stack=unknown; fi

toolset="$state/repos/$key/toolset.md"
tpl="$plugin/toolsets/$stack.md"
need_toolset=0 solution=''
if [ -f "$toolset" ]; then
  :
elif [ ! -f "$tpl" ]; then
  echo "note: stack $stack has no toolsets/$stack.md yet - $key is registered without a toolset; write repos/$key/toolset.md by hand (the plugin's toolsets/dotnet.md shows the format)" >&2
else
  need_toolset=1
  solution=$(printf '%s\n' "$files" | grep -E '\.slnx$' | head -n1)
  [ -n "$solution" ] || solution=$(printf '%s\n' "$files" | grep -E '\.sln$' | head -n1)
  [ -n "$solution" ] || solution=$(printf '%s\n' "$files" | grep -E '\.csproj$' | head -n1)
fi

if [ "$need_yml$need_toolset" = 00 ]; then
  if [ -f "$toolset" ]; then echo "nothing to do: $key is registered with repos/$key/toolset.md"
  else echo "nothing to do: $key is registered"; fi
  exit 0
fi

# --- the diff ------------------------------------------------------------------------------------------------
[ "$need_yml" = 0 ] || echo "+ $yml_line   in $state/repos.yml"
[ "$need_toolset" = 0 ] || echo "+ $toolset   from toolsets/$stack.md (stack $stack${solution:+, solution $solution})"

if [ "$yes" = 0 ]; then
  echo "pending - rerun with --yes to apply"
  exit 3
fi

# --- apply -----------------------------------------------------------------------------------------------------
if [ "$need_yml" = 1 ]; then
  [ -z "$(tail -c1 "$state/repos.yml")" ] || echo >> "$state/repos.yml"
  printf '%s\n' "$yml_line" >> "$state/repos.yml"
  commit "chore($key): register repo" repos.yml
  echo "registered $key ($url, $branch, $top)"
fi
if [ "$need_toolset" = 1 ]; then
  mkdir -p "$state/repos/$key"
  sed "s|{{solution}}|$solution|g" "$tpl" \
    | awk -v s="stack: $stack" 'NR == 1 && $0 == "---" { print; print s; fm = 1; next } fm && /^---$/ { fm = 0 } fm && /^stack:/ { next } { print }' \
    > "$toolset"
  commit "chore($key): toolset $stack" "repos/$key/toolset.md"
  echo "toolset repos/$key/toolset.md (stack $stack${solution:+, solution $solution})"
fi
