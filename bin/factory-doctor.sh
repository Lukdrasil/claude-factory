#!/bin/sh
# A report over one product clone in the standalone factory (ADR-0049): the state remote and its credentials,
# registration (one key per clone), toolset, the tools the toolset binds and what they need (a coverage collector,
# a .NET 8 runtime for dotnet-crap), docs/architecture. One line per check, `ok: ...` or `missing: ... - <what
# fixes it>`. Always exit 0: the skill offers the fixes to the human, the report gates nothing.
#
#   factory-doctor.sh --root <dir> [--repo <clone-dir>]
set -eu

root='' repo=''
die() { printf 'factory-doctor: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--repo)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --root) root=$2 ;; --repo) repo=$2 ;; esac
      shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
[ -n "$root" ] || die "--root <dir> is required"
[ -n "$repo" ] || repo=$(pwd)
root=$(printf '%s' "$root" | sed 's/\\/\//g; s:/*$::')
state="$root/state"
plugin=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null | sed 's/\\/\//g') || die "$repo is not a git clone"
[ -n "$top" ] || die "$repo is not a git clone"
url=$(git -C "$top" remote get-url origin 2>/dev/null) || die "$top has no origin remote"
key=${url%/}; key=${key##*[/:]}; key=${key%.git}

ok() { echo "ok: $1"; }
missing() { echo "missing: $1 — $2"; }
add_repo="run factory-add-repo.sh --root $root --repo $top"

# --- state remote + credentials ----------------------------------------------------------------------------------
# 2026-09-07: a state repo with no remote pushes nowhere (every WIP push of a block "succeeded" locally), and one
# with an https remote and no stored credential prompts inside a hook, where nobody answers. Only checked when the
# root has a state clone at all; a local-only state repo is a choice, so the miss names it as one.
if [ -d "$state/.git" ]; then
  if surl=$(git -C "$state" remote get-url origin 2>/dev/null) && [ -n "$surl" ]; then
    ok "state remote $surl"
    case "$surl" in
      http://*@*|https://*@*) ok "credentials for the state remote (in its url)" ;;
      http://*|https://*)
        if [ -n "$(git -C "$state" config --get credential.helper 2>/dev/null || :)" ]; then
          ok "credentials for the state remote (credential.helper)"
        elif [ -f "${HOME:-/nonexistent}/.git-credentials" ]; then
          ok "credentials for the state remote (~/.git-credentials)"
        elif [ -n "${GIT_ASKPASS:-}" ]; then
          ok "credentials for the state remote (GIT_ASKPASS)"
        else
          missing "credentials for the http(s) state remote" \
            "configure a credential helper for the state remote (e.g. git config credential.helper store, or GIT_ASKPASS with the forge token)"
        fi ;;
    esac
  else
    missing "state remote" "add one (git -C $state remote add origin <url>) or accept a local-only state repo"
  fi
fi

# --- registration ----------------------------------------------------------------------------------------------
if [ -f "$state/repos.yml" ] && grep -q "^$key:.*path:" "$state/repos.yml"; then
  # a registered path that no longer points at this clone is worse than none: the readers resolve the key from it
  regpath=$(sed -n "s/^$key:.*path:[[:space:]]*//p" "$state/repos.yml" | head -n1 \
    | sed 's/^["'\'']//; s/["'\''}].*$//; s:[[:space:]]*$::; s:/*$::')
  if [ "$regpath" = "$top" ]; then
    ok "$key registered in state/repos.yml with path"
  else
    missing "a current path for $key in state/repos.yml (registered: $regpath, this clone: $top)" \
      "change its path: to \"$top\", or run doctor from $regpath"
  fi
elif [ -f "$state/repos.yml" ] && grep -q "^$key:" "$state/repos.yml"; then
  missing "path for $key in state/repos.yml" "add path: \"$top\" to its line"
else
  missing "$key in state/repos.yml" "$add_repo"
fi

# --- one key per clone -------------------------------------------------------------------------------------------
# 2026-09-07: two keys registered for the same directory made repo_key_of_cwd pick one and the tasks the other —
# the toolset, memory and tripwire state of a session split across two keys. The same awk as lib-tasks.sh's
# repo_clone_paths, paths compared with forward slashes and no trailing slash.
if [ -f "$state/repos.yml" ]; then
  dups=$(awk '
    /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
    /path:/ && key != "" {
      p = $0; sub(/.*path:[ \t]*/, "", p); sub(/[ \t]*[,}].*$/, "", p); sub(/[ \t]+#.*$/, "", p)
      gsub(/^["'"'"']|["'"'"']$/, "", p); gsub(/\\/, "/", p); sub(/\/+$/, "", p)
      if (p != "") print p "\t" key
    }' "$state/repos.yml" | sort \
    | awk -F '\t' '$1 == prev { print pk " and " $2 " both point at " $1 } { prev = $1; pk = $2 }')
  if [ -n "$dups" ]; then
    printf '%s\n' "$dups" | while IFS= read -r d; do
      missing "one key per clone in state/repos.yml ($d)" "remove one and re-point the tasks that use it"
    done
  else
    ok "one key per clone in state/repos.yml"
  fi
fi

# --- the MR title cap ----------------------------------------------------------------------------------------
# E (2026-09-22, MR !412): the factory opened a 113-character title and the repo's own commitlint job refused
# it at 100. When the clone lints its titles, its registry entry has to carry a cap no larger than that lint's,
# or the factory will keep authoring goals the forge cannot take.
. "$plugin/bin/lib-tasks.sh"
if cc=$(commitlint_cap "$top"); then
  cc_max=$(printf '%s' "$cc" | cut -f1)
  cc_src=$(printf '%s' "$cc" | cut -f2)
  cur=''
  [ ! -f "$state/repos.yml" ] || cur=$(awk -v want="$key" '
    /^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k) }
    /mr_title_max:/ && k == want {
      v = $0; sub(/.*mr_title_max:[ \t]*/, "", v); sub(/[ \t]*[,}].*$/, "", v); sub(/[ \t]+#.*$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v); if (v ~ /^[0-9]+$/) { print v; exit }
    }' "$state/repos.yml")
  if [ -z "$cur" ]; then
    missing "mr_title_max for $key in state/repos.yml ($cc_src caps the MR title at $cc_max)" \
      "add mr_title_max: $cc_max to its line, otherwise the factory authors goals the title lint refuses"
  elif [ "$cur" -gt "$cc_max" ]; then
    missing "an mr_title_max for $key no larger than the repo's own lint (is $cur, $cc_src caps at $cc_max)" \
      "lower mr_title_max to $cc_max in its line"
  else
    ok "mr_title_max $cur for $key ($cc_src caps at $cc_max)"
  fi
fi

# --- toolset + stack ---------------------------------------------------------------------------------------------
toolset="$state/repos/$key/toolset.md"
stack=''
if [ -f "$toolset" ]; then
  ok "repos/$key/toolset.md"
  stack=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit } /^stack:[[:space:]]*/ { sub(/^stack:[[:space:]]*/, ""); print; exit }' "$toolset")
  if [ -n "$stack" ]; then ok "stack $stack"; else missing "stack in repos/$key/toolset.md" "add stack: <stack> to its frontmatter"; fi
else
  missing "repos/$key/toolset.md" "$add_repo"
fi

# --- how tasks are dispatched -------------------------------------------------------------------------------
spawn=manual
[ ! -f "$state/factory.yml" ] || spawn=$(sed -n 's/^spawn:[[:space:]]*//p' "$state/factory.yml" | head -n1 \
  | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
[ -n "$spawn" ] || spawn=unset
case "$spawn" in
  manual) ok "spawn: manual (session-monitor.sh prints the commands)" ;;
  herdr)
    if command -v herdr >/dev/null 2>&1; then
      ok "spawn: herdr, herdr on PATH"
    else
      missing "spawn: herdr, but herdr is not on PATH" \
        'install herdr from https://herdr.dev, or set spawn: manual in factory.yml'
    fi ;;
  unset) missing "spawn: in factory.yml" 'add `spawn: manual` or `spawn: herdr` to it' ;;
  *) missing "spawn: $spawn in factory.yml" 'it takes herdr or manual' ;;
esac

# --- the Factory UI ------------------------------------------------------------------------------------------
ui=off
[ ! -f "$state/factory.yml" ] || ui=$(sed -n 's/^ui:[[:space:]]*//p' "$state/factory.yml" | head -n1 \
  | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
if [ "$ui" = docker ]; then
  if docker info >/dev/null 2>&1; then ok "ui: docker, the Docker daemon answers"
  else missing "ui: docker, but the Docker daemon does not answer" 'install and start Docker, or set ui: off in factory.yml'; fi
  if command -v herdr >/dev/null 2>&1; then ok "ui: docker, herdr on PATH"
  else missing "ui: docker, but herdr is not on PATH" 'install herdr from https://herdr.dev, or set ui: off in factory.yml'; fi
  if grep -Eq '"promptSuggestionEnabled"[[:space:]]*:[[:space:]]*false' "${HOME:-/nonexistent}/.claude/settings.json" 2>/dev/null; then
    ok "ui: docker, promptSuggestionEnabled: false in ~/.claude/settings.json"
  else
    missing "ui: docker, but promptSuggestionEnabled is not false in ~/.claude/settings.json" \
      "run factory-init.sh --root $root --ui docker"
  fi
fi

# --- the tools the toolset binds ---------------------------------------------------------------------------------
tool() { # <binary> <install command>
  if command -v "$1" >/dev/null 2>&1; then ok "$1 on PATH"; else missing "$1 on PATH" "$2"; fi
}
# only the tools this toolset actually binds: a repo that deleted the row it cannot run must not be told to
# install the tool behind it (ADR-0039 — a command the toolset lacks does not exist for the repo)
binds() { # <command name> → true when the toolset has a table row for it
  [ -f "$toolset" ] && grep -q "^|[[:space:]]*\`$1" "$toolset"
}
if [ "$stack" = dotnet ]; then
  ! binds coverage || tool reportgenerator 'dotnet tool install -g dotnet-reportgenerator-globaltool'
  ! binds crap || tool dotnet-crap 'dotnet tool install -g Crap4DotNet'
  ! binds mutation || tool dotnet-stryker 'dotnet tool install -g dotnet-stryker'
fi
! binds arch-build || tool likec4 'npm i -g likec4'

# --- test-globs ----------------------------------------------------------------------------------------------------
globs=''
[ ! -f "$toolset" ] || globs=$(awk '/^test-globs:[[:space:]]*$/ { g=1; next }
     g && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); print; next }
     g { exit }' "$toolset" | tr '\n' ' ' | sed 's/ $//')
if [ -n "$globs" ]; then ok "test-globs ($globs)"; else missing "test-globs in repos/$key/toolset.md" "add the frontmatter list (docs/design/toolset.md)"; fi

# --- what the dotnet coverage and crap rows need beyond the binaries ------------------------------------------------
if [ "$stack" = dotnet ]; then
  # 2026-09-07: `coverage` ran green and produced no cobertura file, so `crap` had nothing to score and the gate
  # could never be met — no test project referenced a collector. A test project is a *.csproj under a path one of
  # the test-globs matches (`**/` → any directories, `*` → one segment) or one that declares itself a test project.
  if binds coverage || binds crap; then
    glob_re=''
    p1=$(printf '\001'); p2=$(printf '\002')
    for gl in $globs; do
      re=$(printf '%s' "$gl" | sed "s/[.]/\\\\./g; s#\\*\\*/#$p1#g; s#\\*\\*#$p2#g; s/\\*/[^\\/]*/g; s#$p1#(.*/)?#g; s#$p2#.*#g")
      glob_re="${glob_re:+$glob_re|}^($re)\$"
    done
    testprojs=$(find "$top" -name '*.csproj' -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/.git/*' 2>/dev/null \
      | while IFS= read -r f; do
          rel=${f#"$top"/}
          if { [ -n "$glob_re" ] && printf '%s\n' "$rel" | grep -qE "$glob_re"; } \
            || grep -qiE '<IsTestProject>[[:space:]]*true|Microsoft\.NET\.Test\.Sdk|Microsoft\.Testing\.Platform' "$f" 2>/dev/null; then
            printf '%s\n' "$f"
          fi
        done)
    collector=''
    if [ -n "$testprojs" ]; then
      # Directory.Build.props/targets can carry the PackageReference for every test project at once
      collector=$( { printf '%s\n' "$testprojs"; find "$top" -name 'Directory.Build.props' -o -name 'Directory.Build.targets' 2>/dev/null; } \
        | xargs -r grep -liE 'coverlet\.collector|Microsoft\.Testing\.Extensions\.CodeCoverage|coverlet\.msbuild' 2>/dev/null | head -n 1 || :)
    fi
    if [ -n "$collector" ]; then
      ok "a coverage collector in a test project (${collector#"$top"/})"
    else
      missing "a coverage collector in a test project" \
        "add coverlet.collector (VSTest) or Microsoft.Testing.Extensions.CodeCoverage (MTP) to a test project, otherwise the crap gate can never be met"
    fi
  fi
  # 2026-09-07: Crap4DotNet targets net8.0 and refuses to start on a machine with only a newer runtime unless told
  # to roll forward — the toolset's crap row carries DOTNET_ROLL_FORWARD=Major, this names the other way out
  if command -v dotnet-crap >/dev/null 2>&1 && command -v dotnet >/dev/null 2>&1; then
    if dotnet --list-runtimes 2>/dev/null | grep -q '^Microsoft\.NETCore\.App 8\.'; then
      ok "a .NET 8 runtime for dotnet-crap"
    else
      missing "a .NET 8 runtime for dotnet-crap" \
        "run it with DOTNET_ROLL_FORWARD=Major (the toolset's crap row does) or install the 8.0 runtime"
    fi
  fi
fi

# --- docs/architecture ---------------------------------------------------------------------------------------------
if [ -d "$top/docs/architecture" ]; then ok "docs/architecture in $top"; else missing "docs/architecture" "run the architecture-docs bootstrap"; fi

# --- curation --------------------------------------------------------------------------------------------------
curation=auto
[ ! -f "$state/factory.yml" ] || curation=$(sed -n 's/^curation:[[:space:]]*//p' "$state/factory.yml" | head -n 1 | sed 's/[[:space:]]*$//')
case "${curation:-auto}" in
  auto|manual) ok "curation ${curation:-auto}" ;;
  *) missing "factory.yml curation must be auto|manual (is '$curation')" "set curation: auto or curation: manual in $state/factory.yml" ;;
esac

# --- context_window (T-056) -------------------------------------------------------------------------------------
# the compact tripwire's window: absent stays the 200000 default (no line, not a miss), present has to be a
# positive integer, same ok:/missing: shape as curation. A leading zero (007) is refused outright rather than
# read as 7 with the zero stripped — a hand-edited typo should not turn into a legitimate-looking tiny window,
# and this is the same value compact-tripwire.sh's cfg_window guard refuses (T-056-04).
context_window=
[ ! -f "$state/factory.yml" ] || context_window=$(sed -n 's/^context_window:[[:space:]]*//p' "$state/factory.yml" | head -n 1 | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
if [ -n "$context_window" ]; then
  case "$context_window" in
    *[!0-9]*|'') missing "factory.yml context_window must be a positive integer (is '$context_window')" "set context_window: <tokens> in $state/factory.yml or remove the key to use the default" ;;
    0?*) missing "factory.yml context_window must not have a leading zero (is '$context_window')" "set context_window: <tokens> in $state/factory.yml or remove the key to use the default" ;;
    *[!0]*) ok "context_window $context_window" ;;
    *) missing "factory.yml context_window must be a positive integer (is '$context_window')" "set context_window: <tokens> in $state/factory.yml or remove the key to use the default" ;;
  esac
fi

# --- memory budget ----------------------------------------------------------------------------------------------
if [ -f "$plugin/bin/memory-budget.sh" ]; then
  if out=$(sh "$plugin/bin/memory-budget.sh" --all --state "$state" 2>&1); then
    over=$(printf '%s\n' "$out" | awk '$0 == "over budget" { print scope; next } { scope = $1 }')
    if [ -n "$over" ]; then
      for scope in $over; do missing "memory over budget in $scope" "run factory consolidate $scope"; done
    else
      ok "memory within budget"
    fi
  else
    missing "memory budget unreadable" "$(printf '%s\n' "$out" | tail -n 1 | sed 's/^memory-budget: //')"
  fi
fi
exit 0
