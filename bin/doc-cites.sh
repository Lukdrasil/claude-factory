#!/bin/sh
# doc-cites.sh — the sibling of doc-facts.sh for the other half of a recorded fact: the citation that points at a
# file. Read-only, no LLM: it greps docs/**, CONTEXT.md and README.md for `path/file.ext:NN` citations and for bare
# `path/file.ext` paths, and prints each one beside what the repo has there now — the file is gone, or the cited
# line is past the end of it. Whether a dead citation matters, and which task owns the fix, stays a human answer;
# the script proposes, it never decides and never fixes.
# A repo with no docs/architecture/ is skipped, the same rule as doc-facts.sh and the architect curation.
set -eu

usage() {
  echo "usage: doc-cites.sh <product-repo>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
case "$1" in -h|--help) usage ;; esac
repo=$(CDPATH= cd -- "$1" 2>/dev/null && pwd) || { echo "doc-cites.sh: '$1' is not a directory" >&2; exit 2; }
cd "$repo"

if [ ! -d docs/architecture ]; then
  echo "doc-cites.sh: '$repo' has no docs/architecture/ — nothing to sweep, skipped."
  exit 0
fi

FILES=$(find docs -type f -name '*.md' | sort)
for f in CONTEXT.md README.md; do
  [ -f "$f" ] && FILES="$FILES
$f"
done

# ---- the candidate tokens ---------------------------------------------------------------------------------
# One `<doc>\t<line>\t<token>` row per candidate. URLs are cut out of the line before matching, so a `.md:12`
# inside a link target is never a citation.
tokens=$(printf '%s\n' "$FILES" | while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  awk -v d="$doc" '
    {
      line = $0
      gsub(/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^ )"]*/, " ", line)
      while (match(line, /[A-Za-z0-9_.\/-]+\.[A-Za-z0-9]+(:[0-9]+)?/)) {
        print d "\t" FNR "\t" substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$doc"
done)

# ---- the verdicts -----------------------------------------------------------------------------------------
# The evidence form of `references/checks.md` is `path/file.ext:line`, so a citation needs a slash: without one
# a `:NN` token is a host and a port, and a bare token is prose, a package name or a version. A bare path is a
# citation only when its first segment is a directory of this repo. A path resolves against the repo root or
# against the directory of the document that writes it — `../design/x.md` in `docs/architecture/` is the same path.
out=$(printf '%s\n' "$tokens" | while IFS="$(printf '\t')" read -r doc no tok; do
  [ -n "${tok:-}" ] || continue
  case "$tok" in http*|ADR-*|QS-*|R-[0-9]*) continue ;; esac

  path=$tok; want=''
  case "$tok" in *:[0-9]*) path=${tok%:*}; want=${tok##*:} ;; esac
  case "$path" in */*) ;; *) continue ;; esac
  [ -n "$want" ] || [ -d "${path%%/*}" ] || [ "${path%%/*}" = '..' ] || continue

  target=$path
  [ -e "$target" ] || target="$(dirname -- "$doc")/$path"

  if [ ! -e "$target" ] || { [ -n "$want" ] && [ ! -f "$target" ]; }; then
    printf '%s:%s: "%s" — MISSING FILE  [MISMATCH]\n' "$doc" "$no" "$tok"
    continue
  fi
  if [ -n "$want" ]; then
    total=$(wc -l < "$target" | tr -d ' ')
    if [ "$want" -gt "$total" ]; then
      printf '%s:%s: "%s" — line %s > %s lines  [MISMATCH]\n' "$doc" "$no" "$tok" "$want" "$total"
      continue
    fi
  fi
  printf '%s:%s: "%s" — resolves  [ok]\n' "$doc" "$no" "$tok"
done)

echo "doc-cites.sh: $repo"
echo
if [ -z "$out" ]; then
  echo "no file citation found in docs/**, CONTEXT.md, README.md."
else
  printf '%s\n' "$out"
  hits=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  misses=$(printf '%s\n' "$out" | grep -c 'MISMATCH' || true)
  echo
  echo "$hits citation(s), $misses dead."
fi
echo
echo "Candidates only. doc-cites proposes; it never repoints a citation and never deletes one."
echo "Each dead citation is a gap-ledger row whose answer is which task owns the fix — the same branch that"
echo "moved the code fixes the citation (docs/architecture/README.md § Maintenance), or it lands in the"
echo "divergence list. An explicit decline is an answer too."
exit 0
