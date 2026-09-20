#!/bin/sh
# Deterministic inventory for the triage investigation (T-013): every migration, API contract, typed HTTP
# client registration and configured URL a code-changing task's chain might touch — one line per match,
# `LC_ALL=C sort`, paths relative to the repo. An empty repo prints nothing and exits 0.
#
#   investigate-inventory.sh <repo-dir> [--toolset <toolset.md>]
#
# Without --toolset, migration/contract use the built-in dotnet heuristics (Migrations/ dirs, *.sql,
# openapi/swagger/proto files). With --toolset, a toolset carrying db-schema/api-contracts frontmatter lists
# narrows migration/contract to those globs instead; a toolset without either row falls back to the heuristic.
set -eu

die() { printf 'investigate-inventory: %s\n' "$1" >&2; exit 1; }

repo='' toolset=''
while [ $# -gt 0 ]; do
  case "$1" in
    --toolset)
      [ $# -ge 2 ] || die "--toolset needs a value"
      toolset=$2
      shift 2 ;;
    *)
      [ -z "$repo" ] || die "unexpected argument '$1'"
      repo=$1
      shift ;;
  esac
done
[ -n "$repo" ] || die "<repo-dir> is required"
[ -d "$repo" ] || die "$repo is not a directory"

# same awk shape docs/design/toolset.md uses for test-globs, over a different frontmatter key
extract() { awk -v key="$2:" '$0 == key { g=1; next }
     g && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); print; next }
     g { exit }' "$1"; }

db_globs='' api_globs=''
if [ -n "$toolset" ] && [ -f "$toolset" ]; then
  db_globs=$(extract "$toolset" "db-schema" | sed 's/\*\*/*/g')
  api_globs=$(extract "$toolset" "api-contracts" | sed 's/\*\*/*/g')
fi

# does relative path $1 match any glob in the newline-separated list $2? (sh case patterns already match
# '*' across '/', unlike pathname expansion, so a plain case is enough once '**' is folded to '*'). Each glob
# is tried as rewritten and again with a leading '*/' folded away, the way policy-guard.sh's path_is_test
# tries the path with and without a leading '/': '**/Migrations/**' becomes '*/Migrations/*', which needs a
# segment before 'Migrations/' and would miss 'Migrations/Init.cs' in the repo root.
matches_any() {
  path=$1
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$path" in
      $g) return 0 ;;
    esac
    unanchored=${g#\*/}
    case "$path" in
      $unanchored) return 0 ;;
    esac
  done <<EOF
$2
EOF
  return 1
}

cd "$repo"

{
  # --- migration -----------------------------------------------------------------------------------------
  if [ -n "$db_globs" ]; then
    find . -type f | sed 's|^\./||' | while IFS= read -r f; do
      if matches_any "$f" "$db_globs"; then printf 'migration %s\n' "$f"; fi
    done
  else
    find . -type f \( -path '*/Migrations/*' -o -name '*.sql' \) 2>/dev/null | sed 's|^\./||' \
      | while IFS= read -r f; do printf 'migration %s\n' "$f"; done
  fi

  # --- contract --------------------------------------------------------------------------------------------
  if [ -n "$api_globs" ]; then
    find . -type f | sed 's|^\./||' | while IFS= read -r f; do
      if matches_any "$f" "$api_globs"; then printf 'contract %s\n' "$f"; fi
    done
  else
    find . -type f \( -iname 'openapi*.json' -o -iname 'openapi*.yaml' -o -iname 'openapi*.yml' \
      -o -iname 'swagger*.json' -o -name '*.proto' \) 2>/dev/null | sed 's|^\./||' \
      | while IFS= read -r f; do printf 'contract %s\n' "$f"; done
  fi

  # --- client (AddHttpClient registrations) -----------------------------------------------------------------
  # one grep over the tree instead of one per file; `cut -f1,2` keeps `<file>:<line>` out of the matched text
  grep -rn --include='*.cs' --exclude-dir=.git --exclude-dir=bin --exclude-dir=obj 'AddHttpClient' . 2>/dev/null \
    | cut -d: -f1,2 | sed 's|^\./||; s|^|client |'

  # --- config (http(s) URLs in appsettings*.json) ------------------------------------------------------------
  grep -rnE --include='appsettings*.json' --exclude-dir=.git --exclude-dir=bin --exclude-dir=obj 'https?://' . 2>/dev/null \
    | cut -d: -f1,2 | sed 's|^\./||; s|^|config |'
} | LC_ALL=C sort -u
