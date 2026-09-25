#!/bin/sh
# The standalone factory root (ADR-0049): <root>/state as the local state repo and WORK_DIR in the user's Claude
# Code settings, and with ui: docker promptSuggestionEnabled: false there too, plus the permissions.allow rules of
# factory_allow_rules in lib-tasks.sh. Every change is printed first; nothing is written until --yes.
#
#   factory-init.sh --root <dir> [--from <url>] [--settings <file>] [--spawn herdr|manual] [--ui docker|off] [--yes]
#
# Exit 0 = applied, or nothing to do. Exit 3 = changes pending, shown as a diff, not written (no --yes).
# An existing <root>/state with a repos.yml is adopted byte for byte; only the missing pieces are added.
# --from <url> makes <root>/state a clone of an existing state repo (a second machine): the preview clones it into
# a scratch directory to show what it lacks, the apply moves that clone into place. A new factory.yml carries the
# capacity defaults. Every run refreshes the doctor.json of the Setup tab.
set -eu

root='' settings="$HOME/.claude/settings.json" yes=0 spawn='' ui='' from=''
die() { printf 'factory-init: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--settings|--spawn|--ui|--from)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --root) root=$2 ;; --settings) settings=$2 ;; --spawn) spawn=$2 ;; --ui) ui=$2 ;; --from) from=$2 ;;
      esac
      shift 2 ;;
    --yes) yes=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
# how the main session starts a task: `herdr` opens each one as its own interactive session in its own tab,
# `manual` prints the command for the human. The default follows the machine, so a factory on a box without
# herdr never asks for it.
if [ -z "$spawn" ]; then
  if command -v herdr >/dev/null 2>&1; then spawn=herdr; else spawn=manual; fi
fi
case "$spawn" in herdr|manual) ;; *) die "--spawn takes herdr or manual, not '$spawn'" ;; esac
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
# the Setup tab reads <ui home>/setup/doctor.json, so every run leaves it current; it never changes this exit
refresh_doctor() { sh "$(dirname -- "$0")/factory-doctor.sh" --json --root "$root" >/dev/null 2>&1 || :; }

# where the state repo's files are read from: the state repo, or with --from a scratch clone of the url
src=$state
if [ -n "$from" ]; then
  if [ -d "$state/.git" ]; then
    cur_origin=$(git -C "$state" remote get-url origin 2>/dev/null || :)
    [ "$cur_origin" = "$from" ] || die "$state exists with origin ${cur_origin:-none}, not $from"
  else
    [ ! -e "$state" ] || [ -z "$(ls -A "$state")" ] || die "$state exists and is no git clone, so it cannot become a clone of $from"
    git clone -q "$from" "$tmp/from" 2>"$tmp/clone.err" || die "cannot clone $from: $(tail -n1 "$tmp/clone.err")"
    src="$tmp/from"
  fi
fi
cur_ui=''
if [ -f "$src/factory.yml" ]; then
  cur_ui=$(sed -n 's/^ui:[[:space:]]*//p' "$src/factory.yml" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
fi
[ -n "$ui" ] || ui=$cur_ui
[ -n "$ui" ] || ui=off
case "$ui" in docker|off) ;; *) die "--ui takes docker or off, not '$ui'" ;; esac

# --- what is pending ---------------------------------------------------------------------------------------
need_init=0 need_yml=0 need_cfg=0 need_wd=0 need_ps=0 need_perm=0 need_curation=0 need_ui=0
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
  '# how session-monitor.sh starts a task: herdr|manual' \
  "spawn: $spawn" \
  '# the Factory UI: docker|off, and the port it listens on' \
  "ui: $ui" \
  'ui_port: 7171' \
  '# how many run at once (capacity.sh): sessions counts every herdr unit, roles the subagents per role' \
  'capacity:' \
  '  sessions: 10' \
  '  roles: {repo-lead: 3, scout: 8, triage-analyst: 2, researcher: 4, plan-architect: 2,' \
  '          architecture-auditor: 2, test-designer: 3, implementer: 4, implementer-senior: 2, code-reviewer: 2}' \
  > "$tmp/factory.yml"
# an existing factory.yml keeps every key and gains the ui: asked for and a ui_port: when it has none
if [ "$need_curation" = 0 ]; then
  awk -v ui="$ui" -v cur="$cur_ui" '
    /^ui:/ && !seen { if (cur != ui) sub(/^ui:[ \t]*[^ \t#]*/, "ui: " ui); seen = 1 }
    /^ui_port:/ { port = 1 }
    { print }
    END { if (!seen) print "ui: " ui; if (!port) print "ui_port: 7171" }' "$src/factory.yml" > "$tmp/factory.yml"
  { [ "$cur_ui" = "$ui" ] && grep -q '^ui_port:' "$src/factory.yml"; } || need_ui=1
fi

# the settings file with env.WORK_DIR set, with ui: docker promptSuggestionEnabled false, and every allow rule of
# factory_allow_rules appended when absent, every other key kept; node is native on win32, so the root, the ui, the
# rules and the file all go in on stdin (an env var or an argument would get its path converted by MSYS)
if [ -f "$settings" ]; then in=$settings; else in=/dev/null; fi
{ printf '%s\n%s\n%s\n' "$root" "$ui" "$(factory_allow_rules "$root" "$plugin" | paste -sd '\t' -)"; cat "$in"; } | node -e '
let s = "";
process.stdin.on("data", d => s += d).on("end", () => {
  const [wd, ui, rules] = s.split("\n", 3), rest = s.slice(wd.length + ui.length + rules.length + 3);
  const o = rest.trim() ? JSON.parse(rest) : {};
  o.env = o.env || {};
  o.env.WORK_DIR = wd;
  if (ui === "docker") o.promptSuggestionEnabled = false;
  o.permissions = o.permissions || {};
  const allow = o.permissions.allow || [];
  o.permissions.allow = allow.concat(rules.split("\t").filter(r => !allow.includes(r)));
  process.stdout.write(JSON.stringify(o, null, 2) + "\n");
});' > "$tmp/settings.json" || die "cannot parse $settings"
current=$(node -e '
let s = "";
process.stdin.on("data", d => s += d).on("end", () => {
  let o = {}; try { o = JSON.parse(s); } catch (e) {}
  process.stdout.write(((o.env && o.env.WORK_DIR) || "") + "\n" + (o.promptSuggestionEnabled === false));
});' < "$in")
[ "$(printf '%s\n' "$current" | head -n1)" = "$root" ] || need_wd=1
[ "$ui" != docker ] || [ "$(printf '%s\n' "$current" | tail -n1)" = true ] || need_ps=1
node -e 'const [a, b] = process.argv.slice(1).map(f => JSON.parse(require("fs").readFileSync(f, "utf8") || "{}"));
  process.exit(JSON.stringify((a.permissions || {}).allow) === JSON.stringify(b.permissions.allow) ? 0 : 1)' \
  "$in" "$tmp/settings.json" || need_perm=1

if [ "$need_init$need_yml$need_cfg$need_wd$need_ps$need_perm$need_curation$need_ui" = 00000000 ]; then
  echo "nothing to do: $state is a state repo and $settings has WORK_DIR=$root"
  refresh_doctor
  exit 0
fi

# --- the diff ------------------------------------------------------------------------------------------------
if [ "$need_init" = 1 ] || [ "$need_yml" = 1 ]; then
  echo "state repo $state:"
  if [ "$fresh" = 1 ]; then echo "+ git init -b main $state"
  elif [ "$need_init" = 1 ]; then echo "+ git clone $from $state"; fi
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
if [ "$need_ui" = 1 ]; then
  echo "config $state/factory.yml:"
  diff -u --label "$state/factory.yml" --label "$state/factory.yml" "$src/factory.yml" "$tmp/factory.yml" || :
fi
[ "$need_cfg" = 0 ] || echo "+ git -C $state config receive.denyCurrentBranch updateInstead"
if [ "$need_wd" = 1 ] || [ "$need_ps" = 1 ] || [ "$need_perm" = 1 ]; then
  echo "settings $settings:"
  diff -u --label "$settings" --label "$settings" "$in" "$tmp/settings.json" || :
fi

if [ "$yes" = 0 ]; then
  echo "pending - rerun with --yes to apply"
  refresh_doctor
  exit 3
fi

# --- apply -----------------------------------------------------------------------------------------------------
if [ "$need_init" = 1 ] && [ "$fresh" = 0 ]; then
  mkdir -p "$root"
  rmdir "$state" 2>/dev/null || :
  mv "$tmp/from" "$state"
fi
if [ "$fresh" = 1 ] || [ "$need_yml" = 1 ] || [ "$need_curation" = 1 ] || [ "$need_ui" = 1 ]; then
  mkdir -p "$state"
  [ "$fresh" = 0 ] || git init -q -b main "$state"
  [ "$need_yml" = 0 ] || cp "$tmp/repos.yml" "$state/repos.yml"
  [ "$need_curation$need_ui" = 00 ] || cp "$tmp/factory.yml" "$state/factory.yml"
  paths=''
  [ ! -f "$state/repos.yml" ] || paths="repos.yml"
  [ ! -f "$state/factory.yml" ] || paths="$paths factory.yml"
  msg="chore: init state repo"
  [ "$fresh" = 1 ] || [ "$need_yml" = 1 ] || msg="chore: default curation: auto"
  [ "$fresh$need_yml$need_curation" != 000 ] || msg="chore: ui: $ui"
  git -C "$state" add -- $paths
  if [ -n "$(git -C "$state" config user.email || :)" ]; then
    git -C "$state" commit -q -m "$msg" -- $paths
  else
    git -C "$state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$msg" -- $paths
  fi
fi
[ "$need_cfg" = 0 ] || git -C "$state" config receive.denyCurrentBranch updateInstead
if [ "$need_wd" = 1 ] || [ "$need_ps" = 1 ] || [ "$need_perm" = 1 ]; then
  mkdir -p "$(dirname "$settings")"
  cp "$tmp/settings.json" "$settings"
fi
echo "applied"
refresh_doctor
