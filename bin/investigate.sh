#!/bin/sh
# The recon half of the triage investigation (T-153), so skills/_shared/investigate.md steps 1 to 3 cost one
# command instead of prose: the sibling bin/investigate-inventory.sh over the repo, the toolset's `find-refs`
# binding over the symbol when the toolset binds one, and the at most 8 `worker-explorer` questions the
# procedure prescribes. One block on stdout, the brief material for a `factory-investigator`.
#
#   investigate.sh <repo-dir> <symbol> [--toolset <toolset.md>]
#
# The find-refs binding is the first backticked snippet of the toolset's `find-refs <symbol>` row that carries
# `<symbol>`; the symbol is substituted into it and the result runs with the repo as its working directory.
# A toolset with no such row, or no toolset at all, leaves the find-refs block a note and makes the symbol
# greenfield, which is what the last question asks about. Exit 1 when the repo dir does not exist.
set -eu

die() { printf 'investigate: %s\n' "$1" >&2; exit 1; }

repo='' symbol='' toolset=''
while [ $# -gt 0 ]; do
  case "$1" in
    --toolset)
      [ $# -ge 2 ] || die "--toolset needs a value"
      toolset=$2
      shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *)
      if [ -z "$repo" ]; then repo=$1
      elif [ -z "$symbol" ]; then symbol=$1
      else die "unexpected argument '$1'"
      fi
      shift ;;
  esac
done
[ -n "$repo" ] || die "usage: investigate.sh <repo-dir> <symbol> [--toolset <toolset.md>]"
[ -n "$symbol" ] || die "usage: investigate.sh <repo-dir> <symbol> [--toolset <toolset.md>]"
[ -d "$repo" ] || die "$repo is not a directory"

# invariant: the symbol is spliced into the binding and run by sh -c, so it carries no shell syntax
case "$symbol" in
  *[\ \	\'\"\`\$\;\&\|\(\)\<\>]*) die "symbol '$symbol' carries shell syntax" ;;
esac

here=$(dirname -- "$0")
inventory_sh="$here/investigate-inventory.sh"
[ -f "$inventory_sh" ] || die "$inventory_sh is missing"

if [ -n "$toolset" ]; then
  inventory=$(sh "$inventory_sh" "$repo" --toolset "$toolset")
else
  inventory=$(sh "$inventory_sh" "$repo")
fi

binding=''
if [ -n "$toolset" ] && [ -f "$toolset" ]; then
  binding=$(awk -F'|' '/^\|[[:space:]]*`find-refs/ { print $3; exit }' "$toolset" \
    | grep -o '`[^`]*`' | grep '<symbol>' | head -n 1 | sed 's/^`//; s/`$//')
fi

command='' refs=''
if [ -n "$binding" ]; then
  command=$(printf '%s\n' "$binding" | sed "s|<symbol>|$symbol|g")
  refs=$( (cd "$repo" && sh -c "$command") 2>/dev/null || : )
fi

kind_lines() { printf '%s\n' "$inventory" | sed -n "s/^$1 //p"; }

questions=$(
  {
    printf 'References of %s: every caller, `path/file.ext:line`, entry point down to persistence.\n' "$symbol"
    printf 'Tests already covering %s and the chain below it: which files, which behaviour each pins.\n' "$symbol"
    if [ -z "$refs" ]; then
      printf 'Nothing references %s yet: inventory the area it lands in, the files, the tests and the seams a new entry point joins.\n' "$symbol"
    fi
    kind_lines migration | while IFS= read -r f; do
      [ -n "$f" ] || continue
      printf 'Migration %s: which tables and columns it touches, and whether the chain of %s reads or writes them.\n' "$f" "$symbol"
    done
    kind_lines contract | while IFS= read -r f; do
      [ -n "$f" ] || continue
      printf 'Contract %s: which operations the chain of %s serves or calls, and where code and contract differ.\n' "$f" "$symbol"
    done
    if [ -n "$(kind_lines client)" ]; then
      printf 'Typed HTTP client registrations the chain of %s reaches: which service each one talks to.\n' "$symbol"
    fi
    if [ -n "$(kind_lines config)" ]; then
      printf 'Configured URLs the chain of %s resolves: which setting, which environment, which default.\n' "$symbol"
    fi
  } | head -n 8 | awk '{ printf "%d. %s\n", NR, $0 }'
)

printf '# Investigation recon: %s\n\n' "$symbol"
printf 'Repo: %s\n' "$repo"
printf 'Toolset: %s\n\n' "${toolset:-none}"

printf '## Inventory\n\n'
if [ -n "$inventory" ]; then printf '%s\n\n' "$inventory"; else printf 'nothing inventoried\n\n'; fi

printf '## find-refs %s\n\n' "$symbol"
if [ -z "$binding" ]; then
  printf 'no find-refs binding in the toolset, the symbol is treated as greenfield\n\n'
else
  printf 'binding: %s\n\n' "$command"
  if [ -n "$refs" ]; then printf '%s\n\n' "$refs"; else printf 'no hits\n\n'; fi
fi

printf '## Questions (at most 8, one worker-explorer each)\n\n'
printf '%s\n' "$questions"
