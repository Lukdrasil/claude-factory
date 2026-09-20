#!/bin/sh
# The standalone factory root (ADR-0049): <root>/state as the local state repo and WORK_DIR in the user's Claude
# Code settings. Every change is printed first; nothing is written until --yes.
#
#   factory-init.sh --root <dir> [--settings <file>] [--yes]
#
# Exit 0 = applied, or nothing to do. Exit 3 = changes pending, shown as a diff, not written (no --yes).
# An existing <root>/state with a repos.yml is adopted byte for byte; only the missing pieces are added.
set -eu

root='' settings="$HOME/.claude/settings.json" yes=0
die() { printf 'factory-init: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--settings)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --root) root=$2 ;; --settings) settings=$2 ;; esac
      shift 2 ;;
    --yes) yes=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
[ -n "$root" ] || die "--root <dir> is required"

root=$(printf '%s' "$root" | sed 's/\\/\//g; s:/*$::')
case "$root" in '~') root=$HOME ;; '~/'*) root="$HOME/${root#'~/'}" ;; esac
case "$root" in /*|[A-Za-z]:/*) ;; *) root="$(pwd)/$root" ;; esac
# Git Bash hands out /c/Users/…, which never matches the hook's cwd (C:\… normalises to c:/…), so the drive form
# is what goes into WORK_DIR; elsewhere cygpath does not exist and the path is already the one the hooks see.
command -v cygpath >/dev/null 2>&1 && root=$(cygpath -m "$root") || :
state="$root/state"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- what is pending ---------------------------------------------------------------------------------------
need_init=0 need_yml=0 need_cfg=0 need_wd=0 need_curation=0
[ -d "$state/.git" ] || need_init=1
[ -f "$state/repos.yml" ] || need_yml=1
[ -f "$state/factory.yml" ] || need_curation=1
[ "$(git -C "$state" config receive.denyCurrentBranch 2>/dev/null || :)" = updateInstead ] || need_cfg=1

printf '%s\n' \
  '# registry of product repos (ADR-0013): <repo-key>: {url, default_branch, path}' \
  '# my-repo: {url: "https://github.com/acme/my-repo.git", default_branch: main, path: "/home/me/src/my-repo"}' \
  '' > "$tmp/repos.yml"

printf '%s\n' \
  '# standalone factory config (ADR-0052): curation: auto|manual' \
  'curation: auto' > "$tmp/factory.yml"

# the settings file with env.WORK_DIR set, every other key kept; node is native on win32, so the root and the file
# both go in on stdin (an env var or an argument would get its path converted by MSYS)
if [ -f "$settings" ]; then in=$settings; else in=/dev/null; fi
{ printf '%s\n' "$root"; cat "$in"; } | node -e '
let s = "";
process.stdin.on("data", d => s += d).on("end", () => {
  const nl = s.indexOf("\n"), wd = s.slice(0, nl), rest = s.slice(nl + 1);
  const o = rest.trim() ? JSON.parse(rest) : {};
  o.env = o.env || {};
  o.env.WORK_DIR = wd;
  process.stdout.write(JSON.stringify(o, null, 2) + "\n");
});' > "$tmp/settings.json" || die "cannot parse $settings"
current=$(node -e '
let s = "";
process.stdin.on("data", d => s += d).on("end", () => {
  let o = {}; try { o = JSON.parse(s); } catch (e) {}
  process.stdout.write((o.env && o.env.WORK_DIR) || "");
});' < "$in")
[ "$current" = "$root" ] || need_wd=1

if [ "$need_init$need_yml$need_cfg$need_wd$need_curation" = 00000 ]; then
  echo "nothing to do: $state is a state repo and $settings has WORK_DIR=$root"
  exit 0
fi

# --- the diff ------------------------------------------------------------------------------------------------
if [ "$need_init" = 1 ] || [ "$need_yml" = 1 ]; then
  echo "state repo $state:"
  [ "$need_init" = 0 ] || echo "+ git init -b main $state"
  if [ "$need_yml" = 1 ]; then
    diff -u --label /dev/null --label "$state/repos.yml" /dev/null "$tmp/repos.yml" || :
  else
    echo "  repos.yml exists - adopted as is"
  fi
  echo "+ git -C $state commit -m 'chore: init state repo'"
fi
if [ "$need_curation" = 1 ]; then
  echo "config $state/factory.yml:"
  diff -u --label /dev/null --label "$state/factory.yml" /dev/null "$tmp/factory.yml" || :
fi
[ "$need_cfg" = 0 ] || echo "+ git -C $state config receive.denyCurrentBranch updateInstead"
if [ "$need_wd" = 1 ]; then
  echo "settings $settings (env.WORK_DIR):"
  diff -u --label "$settings" --label "$settings" "$in" "$tmp/settings.json" || :
fi

if [ "$yes" = 0 ]; then
  echo "pending - rerun with --yes to apply"
  exit 3
fi

# --- apply -----------------------------------------------------------------------------------------------------
if [ "$need_init" = 1 ] || [ "$need_yml" = 1 ] || [ "$need_curation" = 1 ]; then
  mkdir -p "$state"
  [ "$need_init" = 0 ] || git init -q -b main "$state"
  [ "$need_yml" = 0 ] || cp "$tmp/repos.yml" "$state/repos.yml"
  [ "$need_curation" = 0 ] || cp "$tmp/factory.yml" "$state/factory.yml"
  paths=''
  [ ! -f "$state/repos.yml" ] || paths="repos.yml"
  [ ! -f "$state/factory.yml" ] || paths="$paths factory.yml"
  msg="chore: init state repo"
  [ "$need_init" = 1 ] || [ "$need_yml" = 1 ] || msg="chore: default curation: auto"
  git -C "$state" add -- $paths
  if [ -n "$(git -C "$state" config user.email || :)" ]; then
    git -C "$state" commit -q -m "$msg" -- $paths
  else
    git -C "$state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$msg" -- $paths
  fi
fi
[ "$need_cfg" = 0 ] || git -C "$state" config receive.denyCurrentBranch updateInstead
if [ "$need_wd" = 1 ]; then
  mkdir -p "$(dirname "$settings")"
  cp "$tmp/settings.json" "$settings"
fi
echo "applied"
