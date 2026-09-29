#!/bin/sh
# The standalone factory root (ADR-0049): <root>/state as the local state repo and WORK_DIR in the user's Claude
# Code settings, plus the permissions.allow rules of factory_allow_rules in lib-tasks.sh. Every change is printed first; nothing is written until --yes.
#
#   factory-init.sh --root <dir> [--from <url>] [--settings <file>] [--yes]
#
# Exit 0 = applied, or nothing to do. Exit 3 = changes pending, shown as a diff, not written (no --yes).
# An existing <root>/state with a repos.yml is adopted byte for byte; only the missing pieces are added.
# --from <url> makes <root>/state a clone of an existing state repo (a second machine): the preview clones it into
# a scratch directory to show what it lacks, the apply moves that clone into place. A new factory.yml carries
# curation: auto and context_window: 1000000.
set -eu

root='' settings="$HOME/.claude/settings.json" yes=0 from=''
die() { printf 'factory-init: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--settings|--from)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --root) root=$2 ;; --settings) settings=$2 ;; --from) from=$2 ;;
      esac
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
plugin=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v cygpath >/dev/null 2>&1 && plugin=$(cygpath -m "$plugin") || :
. "$plugin/bin/lib-tasks.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# where the state repo's files are read from: the state repo, or with --from a scratch clone of the url
src=$state
# why: the url as printed: the user:password@ or token@ of an http(s) url stays in the clone's .git/config (the
# why: pushes need it) and out of the output, which ends up in a session transcript
shown() { printf '%s' "$1" | sed 's#^\(https*://\)[^@/]*@#\1#'; }
if [ -n "$from" ]; then
  if [ -d "$state/.git" ]; then
    cur_origin=$(git -C "$state" remote get-url origin 2>/dev/null || :)
    [ "$cur_origin" = "$from" ] || die "$state exists with origin $(shown "${cur_origin:-none}"), not $(shown "$from")"
  else
    [ ! -e "$state" ] || [ -z "$(ls -A "$state")" ] \
      || die "$state exists and is no git clone, so it cannot become a clone of $(shown "$from")"
    git clone -q "$from" "$tmp/from" 2>"$tmp/clone.err" || die "cannot clone $(shown "$from"): $(tail -n1 "$tmp/clone.err")"
    src="$tmp/from"
  fi
fi

# --- what is pending ---------------------------------------------------------------------------------------
need_init=0 need_yml=0 need_cfg=0 need_wd=0 need_perm=0 need_curation=0
[ -d "$state/.git" ] || need_init=1
# a new repository, as opposed to the clone --from brings along with its history
fresh=$need_init
[ "$src" = "$state" ] || fresh=0
[ -f "$src/repos.yml" ] || need_yml=1
[ -f "$src/factory.yml" ] || need_curation=1
[ "$(git -C "$src" config receive.denyCurrentBranch 2>/dev/null || :)" = updateInstead ] || need_cfg=1

printf '%s\n' \
  '# registry of product repos (ADR-0013): <repo-key>: {url, default_branch, path}' \
  '# my-repo: {url: "https://github.com/acme/my-repo.git", default_branch: main, path: "/home/me/src/my-repo"}' \
  '' > "$tmp/repos.yml"

printf '%s\n' \
  '# standalone factory config (ADR-0052): curation: auto|manual' \
  'curation: auto' \
  '# the context window of the sessions in tokens (compact-tripwire.sh): 1000000 on a 1M model, 200000 otherwise' \
  'context_window: 1000000' \
  > "$tmp/factory.yml"

# the settings file with env.WORK_DIR set and every allow rule of factory_allow_rules appended when absent, every
# other key kept; node is native on win32, so the root, the rules and the file all go in on stdin (an env var or an argument would get its path converted by MSYS)
if [ -f "$settings" ]; then in=$settings; else in=/dev/null; fi
{ printf '%s\n%s\n' "$root" "$(factory_allow_rules "$root" "$plugin" | paste -sd '\t' -)"; cat "$in"; } | node -e '
let s = "";
process.stdin.on("data", d => s += d).on("end", () => {
  const [wd, rules] = s.split("\n", 2), rest = s.slice(wd.length + rules.length + 2);
  const o = rest.trim() ? JSON.parse(rest) : {};
  o.env = o.env || {};
  o.env.WORK_DIR = wd;
  o.permissions = o.permissions || {};
  const allow = o.permissions.allow || [];
  o.permissions.allow = allow.concat(rules.split("\t").filter(r => !allow.includes(r)));
  process.stdout.write(JSON.stringify(o, null, 2) + "\n");
});' > "$tmp/settings.json" || die "cannot parse $settings"
current=$(node -e '
let s = "";
process.stdin.on("data", d => s += d).on("end", () => {
  let o = {}; try { o = JSON.parse(s); } catch (e) {}
  process.stdout.write((o.env && o.env.WORK_DIR) || "");
});' < "$in")
[ "$current" = "$root" ] || need_wd=1
node -e 'const [a, b] = process.argv.slice(1).map(f => JSON.parse(require("fs").readFileSync(f, "utf8") || "{}"));
  process.exit(JSON.stringify((a.permissions || {}).allow) === JSON.stringify(b.permissions.allow) ? 0 : 1)' \
  "$in" "$tmp/settings.json" || need_perm=1

if [ "$need_init$need_yml$need_cfg$need_wd$need_perm$need_curation" = 000000 ]; then
  echo "nothing to do: $state is a state repo and $settings has WORK_DIR=$root"
  exit 0
fi

# --- the diff ------------------------------------------------------------------------------------------------
if [ "$need_init" = 1 ] || [ "$need_yml" = 1 ]; then
  echo "state repo $state:"
  if [ "$fresh" = 1 ]; then echo "+ git init -b main $state"
  elif [ "$need_init" = 1 ]; then echo "+ git clone $(shown "$from") $state"; fi
  if [ "$need_yml" = 1 ]; then
    diff -u --label /dev/null --label "$state/repos.yml" /dev/null "$tmp/repos.yml" || :
  elif [ "$fresh" = 1 ]; then
    echo "  repos.yml exists - adopted as is"
  else
    echo "  repos.yml from the clone - adopted as is"
  fi
  [ "$fresh$need_yml" = 00 ] || echo "+ git -C $state commit -m 'chore: init state repo'"
fi
if [ "$need_curation" = 1 ]; then
  echo "config $state/factory.yml:"
  diff -u --label /dev/null --label "$state/factory.yml" /dev/null "$tmp/factory.yml" || :
fi
[ "$need_cfg" = 0 ] || echo "+ git -C $state config receive.denyCurrentBranch updateInstead"
if [ "$need_wd" = 1 ] || [ "$need_perm" = 1 ]; then
  echo "settings $settings:"
  diff -u --label "$settings" --label "$settings" "$in" "$tmp/settings.json" || :
fi

if [ "$yes" = 0 ]; then
  echo "pending - rerun with --yes to apply"
  exit 3
fi

# --- apply -----------------------------------------------------------------------------------------------------
if [ "$need_init" = 1 ] && [ "$fresh" = 0 ]; then
  mkdir -p "$root"
  rmdir "$state" 2>/dev/null || :
  mv "$tmp/from" "$state"
fi
if [ "$fresh" = 1 ] || [ "$need_yml" = 1 ] || [ "$need_curation" = 1 ]; then
  mkdir -p "$state"
  [ "$fresh" = 0 ] || git init -q -b main "$state"
  [ "$need_yml" = 0 ] || cp "$tmp/repos.yml" "$state/repos.yml"
  [ "$need_curation" = 0 ] || cp "$tmp/factory.yml" "$state/factory.yml"
  paths=''
  [ ! -f "$state/repos.yml" ] || paths="repos.yml"
  [ ! -f "$state/factory.yml" ] || paths="$paths factory.yml"
  msg="chore: init state repo"
  [ "$fresh" = 1 ] || [ "$need_yml" = 1 ] || msg="chore: default curation: auto"
  git -C "$state" add -- $paths
  if [ -n "$(git -C "$state" config user.email || :)" ]; then
    git -C "$state" commit -q -m "$msg" -- $paths
  else
    git -C "$state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$msg" -- $paths
  fi
fi
[ "$need_cfg" = 0 ] || git -C "$state" config receive.denyCurrentBranch updateInstead
if [ "$need_wd" = 1 ] || [ "$need_perm" = 1 ]; then
  mkdir -p "$(dirname "$settings")"
  cp "$tmp/settings.json" "$settings"
fi
echo "applied"
