#!/bin/sh
# Registers a product clone in the standalone state repo (ADR-0049): one repos.yml line with url, default_branch,
# path and alias, and repos/<key>/toolset.md seeded from toolsets/<stack>.md. Two commits in the
# state repo, nothing pushed. Idempotent: a registered clone with an alias and a toolset is "nothing to do".
#
#   factory-add-repo.sh --root <dir> [--repo <clone-dir>] [--alias <ALIAS>] [--yes]
#   factory-add-repo.sh --root <dir> --clone <url> [--alias <ALIAS>] [--yes]
#
# The key is the basename of the origin URL without .git. The alias (2 to 4 uppercase letters, unique in repos.yml)
# makes the repo's new task ids T-<ALIAS>-<n>; it is proposed from the key unless --alias names one, and a repo
# registered before aliases gets it added to its line. Every run refreshes the doctor.json of the Setup tab.
#
# --clone first clones <url> into <clones>/<key>, <clones> being `clones:` of <root>/state/factory.yml: absolute and
# outside <root>, whose <root>/<key> holds the task worktrees. A key registered with the same URL is not cloned or
# fetched again. Each state goes to <ui home>/setup/add-repo/<key>.json for the Setup tab, when the UI home exists:
# `{"at","key","url","path","state","detail"}`, state pending, cloning, registered or failed.
#
# Exit 0 = applied, or nothing to do. Exit 3 = changes pending, printed, not written (no --yes), the same gate
# factory-init.sh has, so the skill previews and reruns identically on both scripts. Exit 4 = the URL cannot be
# reached (host, auth, no such repo). Exit 1 = refused, the reason on stderr.
set -eu

root='' repo='' yes=0 alias='' clone=''
. "$(dirname -- "$0")/lib-tasks.sh"
# why: a reason can quote the URL as it was typed, token included, so every one goes through redact_urls
why=''
die() { why=$(redact_urls "$1"); printf 'factory-add-repo: %s\n' "$why" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--repo|--alias|--clone)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --root) root=$2 ;; --repo) repo=$2 ;; --alias) alias=$2 ;; --clone) clone=$2 ;; esac
      shift 2 ;;
    --yes) yes=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
# why: the URL comes from a line typed into the UI or the terminal and ends up as a git argument: no quote, space or
# shell character, no leading - that git would read as an option, and a scheme git clones or the scp form
if [ -n "$clone" ]; then
  nourl="'$clone' is not a URL to clone: http(s)://, ssh://, file:// or user@host:path, with letters, digits and ._~:/@+- only"
  case "$clone" in -*|*[!A-Za-z0-9._~:/@+-]*) die "$nourl" ;; esac
  case "$clone" in
    http://*|https://*|ssh://*|file://*) ;;
    *://*) die "$nourl" ;;
    *) printf '%s\n' "$clone" | grep -qE '^([A-Za-z0-9._~+-]+@)?[A-Za-z0-9.-]+:.' || die "$nourl" ;;
  esac
  [ -z "$repo" ] || die "--clone and --repo exclude each other"
fi
# taken now: the doctor refresh at the end creates the UI home, and the status json is only for a UI that exists
ui_home=${FACTORY_UI_HOME:-$HOME/.claude-factory/ui}
[ -d "$ui_home" ] || ui_home=''
[ -n "$root" ] || die "--root <dir> is required"
root=$(printf '%s' "$root" | sed 's/\\/\//g; s:/*$::')
state="$root/state"
[ -f "$state/repos.yml" ] || die "$state/repos.yml does not exist - run factory-init.sh --root $root first"
plugin=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$alias" in
  ''|[A-Z][A-Z]|[A-Z][A-Z][A-Z]|[A-Z][A-Z][A-Z][A-Z]) ;;
  *) die "--alias takes 2 to 4 uppercase letters, not '$alias'" ;;
esac

top='' branch=''
if [ -n "$clone" ]; then
  # the URL as typed reaches only git ls-remote and git clone, which may need its credentials; everything printed
  # or written carries this one
  url=$(redact_urls "$clone")
else
  [ -n "$repo" ] || repo=$(pwd)
  top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null | sed 's/\\/\//g') || die "$repo is not a git clone"
  [ -n "$top" ] || die "$repo is not a git clone"
  url=$(git -C "$top" remote get-url origin 2>/dev/null) || die "$top has no origin remote"
  # why: an http(s) origin can carry user:password@ or token@ (a glpat- token), which repos.yml would put into the
  # why: state repo and its history; an scp-style git@host:path names only the ssh user and is kept as it is
  case "$url" in http://*@*|https://*@*) url=$(printf '%s' "$url" | sed 's#^\(https*://\)[^@/]*@#\1#') ;; esac
fi
key=${url%/}; key=${key##*[/:]}; key=${key%.git}
printf '%s' "$key" | grep -qE '^[A-Za-z0-9_-]+$' || die "'$key' is not a usable repo key (letters, digits, - and _)"
echo "$key"

# --- --clone: the status json, the clones directory and the target ---------------------------------------------
jpath=''
json_str() { printf '%s' "$1" | tr '\t\n\r' '   ' | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
status() { # <pending|cloning|registered|failed> <detail>: written through a temp file and a rename
  [ -n "$ui_home" ] || return 0
  st_d="$ui_home/setup/add-repo"
  { mkdir -p "$st_d" \
    && printf '{"at":"%s","key":"%s","url":"%s","path":"%s","state":"%s","detail":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$key" "$(json_str "$url")" "$(json_str "$jpath")" "$1" \
      "$(json_str "$(redact_urls "$2")")" > "$st_d/.$key.json.tmp" \
    && mv -f "$st_d/.$key.json.tmp" "$st_d/$key.json"; } || :
}
on_exit() { # <exit status>
  case "$1" in
    0) status registered '' ;;
    3) status pending "$jpath" ;;
    *) status failed "${why:-exit $1}" ;;
  esac
}
# a URL as compared: no userinfo, no trailing / and no .git
norm_url() { redact_urls "$1" | sed 's:/*$::; s:\.git$::'; }
git_net() { GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" git "$@"; }
# why: the cause is in the lines up to git's fatal: (ssh: connect to host ..., remote: Access denied); the lines
# after it are advice, so a last line would read "and the repository exists."
unreachable() { # <git's output>: exit 4 with its lines up to fatal:, at most three, on one line
  why=$(redact_urls "cannot reach $url: $(printf '%s\n' "$1" \
    | awk '{ sub(/\r$/, "") } NF { s = s (n++ ? " / " : "") $0 } /^fatal:/ || n == 3 { exit } END { print s }')")
  printf 'factory-add-repo: %s\n' "$why" >&2
  printf 'factory-add-repo: fix: check the URL and that git ls-remote %s works in your terminal (gh or glab auth login, or your ssh key)\n' "$url" >&2
  exit 4
}
fresh=0
[ -z "$clone" ] || trap 'on_exit $?' EXIT
if [ -n "$clone" ] && grep -q "^$key:" "$state/repos.yml"; then
  # F6: a registered key is not fetched or cloned again; with the same URL the registration below runs in its
  # path: (nothing to do, or the missing alias or toolset), and its onboarding runs there
  reg=$(yml_field "$key" url)
  [ "$(norm_url "$reg")" = "$(norm_url "$url")" ] || die "key $key is registered for $reg"
  top=$(yml_field "$key" path)
  jpath=$top
  [ -n "$top" ] || die "$key has no path: in repos.yml: run factory-add-repo.sh --root $root in its clone"
  git -C "$top" rev-parse --git-dir >/dev/null 2>&1 \
    || die "the path of $key, $top, is no git clone: clone it there or change its path: in $state/repos.yml"
elif [ -n "$clone" ]; then
  nodir="no clones directory: add clones: <absolute dir> to $state/factory.yml"
  cv=$(sed -n 's/^clones:[[:space:]]*//p' "$state/factory.yml" 2>/dev/null | head -n1 \
    | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//' | tr -d "\"'")
  case "$cv" in
    '') die "$nodir" ;;
    /*) ;;
    *) die "$nodir (clones: $cv is not absolute)" ;;
  esac
  # why: both sides resolved, so a symlink into the root is refused like the root itself
  clones=$(CDPATH= cd -P -- "$cv" 2>/dev/null && pwd) || die "$nodir (clones: $cv is no directory)"
  rroot=$(CDPATH= cd -P -- "$root" && pwd)
  case "$clones/" in
    "$rroot/"*) die "$nodir (clones: $cv is $root or under it, whose <key>/ directories hold the task worktrees)" ;;
  esac
  top="$clones/$key"
  jpath=$top
  if [ -e "$top" ] || [ -L "$top" ]; then
    o=$(git -C "$top" remote get-url origin 2>/dev/null || :)
    { [ -e "$top/.git" ] && [ -n "$o" ] && [ "$(norm_url "$o")" = "$(norm_url "$url")" ]; } \
      || die "$top exists and is not a clone of $url: move it away"
    echo "note: $top is already a clone of $url, reused"
  fi
  # proves reachability and auth, and names the default branch; no password prompt that would hang the caller
  lr=$(git_net ls-remote --symref -- "$clone" HEAD 2>&1) || unreachable "$lr"
  branch=$(printf '%s\n' "$lr" | sed -n 's#^ref: refs/heads/\(.*\)	HEAD$#\1#p' | head -n1)
  [ -n "$branch" ] || branch=main
  if [ ! -e "$top" ]; then
    fresh=1
    echo "+ git clone $url $top   (default branch $branch)"
  fi
fi

if [ -z "$branch" ]; then
  branch=$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || :)
  branch=${branch#origin/}; [ -n "$branch" ] || branch=main
fi

commit() { # <message> <path...>
  m=$1; shift
  git -C "$state" add -- "$@"
  if [ -n "$(git -C "$state" config user.email || :)" ]; then
    git -C "$state" commit -q -m "$m" -- "$@"
  else
    git -C "$state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$m" -- "$@"
  fi
}
# the Setup tab reads <ui home>/setup/doctor.json, so every run leaves it current; it never changes this exit
refresh_doctor() { sh "$plugin/bin/factory-doctor.sh" --json --root "$root" >/dev/null 2>&1 || :; }

# the alias proposed for a key: the initials of its words (claude-factory: CF) or the first three letters of a single
# word (nemeton: NEM); when that one is taken, the first two letters and each later letter in turn, then the first
# three and each later one (expiriointegrations: EXI beside EXP). Nothing when every candidate is taken.
propose_alias() { # <key> <taken aliases, space separated>
  printf '%s\n' "$1" | awk -v taken=" $2 " '
    function try(c) { if (length(c) >= 2 && length(c) <= 4 && index(taken, " " c " ") == 0) { print c; exit } }
    {
      n = split(toupper($0), w, /[^A-Z]+/); s = ""; l = ""; nw = 0
      for (i = 1; i <= n; i++) if (w[i] != "") { s = s substr(w[i], 1, 1); l = l w[i]; nw++ }
      if (nw >= 2) try(substr(s, 1, 4))
      try(substr(l, 1, 3))
      for (i = 3; i <= length(l); i++) try(substr(l, 1, 2) substr(l, i, 1))
      for (i = 4; i <= length(l); i++) try(substr(l, 1, 3) substr(l, i, 1))
    }'
}

# --- what is pending ---------------------------------------------------------------------------------------
need_yml=0 need_alias=0
grep -q "^$key:" "$state/repos.yml" || need_yml=1

# `<key> <alias>` of every repo that has one, in the flat or the indented spelling
aliases=$(awk '
  /^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k) }
  k != "" && match($0, /(^|[{, \t])alias[ \t]*:[ \t]*["'"'"']?[A-Za-z]+/) {
    v = substr($0, RSTART, RLENGTH); sub(/.*:[ \t]*/, "", v); gsub(/["'"'"']/, "", v); print k, v
  }' "$state/repos.yml")
cur_alias=$(printf '%s\n' "$aliases" | awk -v k="$key" '$1 == k { print $2; exit }')
if [ -n "$alias" ]; then
  other=$(printf '%s\n' "$aliases" | awk -v k="$key" -v a="$alias" '$1 != k && $2 == a { print $1; exit }')
  [ -z "$other" ] || die "alias $alias is taken by $other"
  [ -z "$cur_alias" ] || [ "$cur_alias" = "$alias" ] \
    || die "$key already has alias $cur_alias; its ids carry it, so a change is a hand edit of repos.yml"
fi
old_line=''
if [ -z "$cur_alias" ]; then
  if [ -z "$alias" ]; then
    alias=$(propose_alias "$key" "$(printf '%s\n' "$aliases" | awk '{ printf "%s ", $2 }')")
    [ -n "$alias" ] || die "no free alias from the letters of '$key', pass --alias <2 to 4 uppercase letters>"
    echo "note: alias $alias proposed from the key - --alias <ALIAS> overrides"
  fi
  if [ "$need_yml" = 0 ]; then
    old_line=$(grep -E "^$key: \{.*\}[[:space:]]*$" "$state/repos.yml" | head -n1 || :)
    if [ -n "$old_line" ]; then
      need_alias=1
    else
      echo "note: $key is not on one {...} line in repos.yml - add alias: $alias to its entry by hand" >&2
    fi
  fi
fi

# --clone of a new key: the stack, the solution and the commitlint cap are only known once the clone exists
if [ "$fresh" = 1 ] && [ "$yes" = 0 ]; then
  echo "+ $key: {url: \"$url\", default_branch: $branch, path: \"$top\", alias: $alias}   in $state/repos.yml"
  echo "+ $state/repos/$key/toolset.md   from the stack found after the clone"
  echo "pending - rerun with --yes to apply"
  refresh_doctor
  exit 3
fi
if [ "$fresh" = 1 ]; then
  status cloning "$top"
  # why: a clone is renamed into place only once complete; the temp directory a killed apply left is no clone
  tmpd="$clones/.$key.cf-clone"
  rm -rf "$tmpd"
  gc=$(git_net clone -q -- "$clone" "$tmpd" 2>&1) || { rm -rf "$tmpd"; unreachable "$gc"; }
  mv "$tmpd" "$top"
  echo "cloned $url into $top"
fi

files=$(git -C "$top" ls-files)

# E (2026-09-22, MR !412): the plugin capped the MR title at 130 and the product repo's CI ran commitlint,
# whose config-conventional caps the header at 100 - the job failed on a title the factory had already opened.
# A clone that lints its own titles gets that cap written into its registry entry, so mr_title_check refuses
# the goal while the task is being authored instead of the forge refusing the MR.
title_max='' title_src=''
if cc=$(commitlint_cap "$top"); then
  title_max=${cc%%	*}
  title_src=${cc#*	}
  echo "note: $title_src lints the MR title - mr_title_max: $title_max for $key"
fi

yml_line=$(printf '%s: {url: "%s", default_branch: %s, path: "%s", alias: %s%s}' \
  "$key" "$url" "$branch" "$top" "$alias" "${title_max:+, mr_title_max: $title_max}")
new_line=''
[ "$need_alias" = 0 ] || new_line=$(printf '%s\n' "$old_line" | sed "s/}[[:space:]]*\$/, alias: $alias}/")

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

if [ "$need_yml$need_alias$need_toolset" = 000 ]; then
  if [ -f "$toolset" ]; then echo "nothing to do: $key is registered with repos/$key/toolset.md"
  else echo "nothing to do: $key is registered"; fi
  refresh_doctor
  exit 0
fi

# --- the diff ------------------------------------------------------------------------------------------------
[ "$need_yml" = 0 ] || echo "+ $yml_line   in $state/repos.yml"
if [ "$need_alias" = 1 ]; then
  echo "- $old_line   in $state/repos.yml"
  echo "+ $new_line   in $state/repos.yml"
fi
[ "$need_toolset" = 0 ] || echo "+ $toolset   from toolsets/$stack.md (stack $stack${solution:+, solution $solution})"

if [ "$yes" = 0 ]; then
  echo "pending - rerun with --yes to apply"
  refresh_doctor
  exit 3
fi

# --- apply -----------------------------------------------------------------------------------------------------
if [ "$need_yml" = 1 ]; then
  [ -z "$(tail -c1 "$state/repos.yml")" ] || echo >> "$state/repos.yml"
  printf '%s\n' "$yml_line" >> "$state/repos.yml"
  commit "chore($key): register repo" repos.yml
  echo "registered $key ($url, $branch, $top, alias $alias)"
fi
if [ "$need_alias" = 1 ]; then
  awk -v old="$old_line" -v new="$new_line" '!done && $0 == old { print new; done = 1; next } { print }' \
    "$state/repos.yml" > "$state/repos.yml.tmp"
  mv "$state/repos.yml.tmp" "$state/repos.yml"
  commit "chore($key): alias $alias" repos.yml
  echo "alias $alias for $key"
fi
if [ "$need_toolset" = 1 ]; then
  mkdir -p "$state/repos/$key"
  sed "s|{{solution}}|$solution|g" "$tpl" \
    | awk -v s="stack: $stack" 'NR == 1 && $0 == "---" { print; print s; fm = 1; next } fm && /^---$/ { fm = 0 } fm && /^stack:/ { next } { print }' \
    > "$toolset"
  commit "chore($key): toolset $stack" "repos/$key/toolset.md"
  echo "toolset repos/$key/toolset.md (stack $stack${solution:+, solution $solution})"
fi
refresh_doctor
