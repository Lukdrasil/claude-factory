#!/bin/sh
# doc-facts.sh — the mechanical half of "a recorded fact this plan falsifies" (issue #458). Read-only, no LLM:
# it greps docs/**, CONTEXT.md and README.md for numeric claims about things the repo can count, and prints each
# claim beside the current real number. Whether a mismatch matters, which task owns the update, or whether it is
# explicitly declined stays a human answer in the gap ledger — the script proposes, it never decides and never fixes.
# A repo with no docs/architecture/ is skipped, the same rule as the architect curation (architect-gate.sh).
set -eu

usage() {
  echo "usage: doc-facts.sh <product-repo>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
case "$1" in -h|--help) usage ;; esac
repo=$(CDPATH= cd -- "$1" 2>/dev/null && pwd) || { echo "doc-facts.sh: '$1' is not a directory" >&2; exit 2; }
cd "$repo"

if [ ! -d docs/architecture ]; then
  echo "doc-facts.sh: '$repo' has no docs/architecture/ — nothing to sweep, skipped."
  exit 0
fi

# The documents that record facts. `docs/**` plus the two repo-root files the architect rubric reads
# (references/checks.md § Evidence).
FILES=$(find docs -type f -name '*.md' | sort)
for f in CONTEXT.md README.md; do
  [ -f "$f" ] && FILES="$FILES
$f"
done

# ---- the real numbers -------------------------------------------------------------------------------------
# Tests: the attribute vocabulary of the repo's toolset (ADR-0039) — xunit `[Fact]`/`[Theory]`, NUnit/MSTest
# `[Test]`/`[TestCase]`/`[TestMethod]`. A repo on another stack adds its marker here; that is the one edit.
# docs/ is excluded so a document *quoting* an attribute is not counted as a test.
tests=$(grep -rIhoE '\[(Fact|Theory|Test|TestCase|TestMethod)(\]|\(|,)' . \
  --exclude-dir=.git --exclude-dir=docs --exclude-dir=node_modules --exclude-dir=bin --exclude-dir=obj \
  2>/dev/null | wc -l | tr -d ' ')

# Risks: the `| R-NN |` rows of 07-risks.md, and of those the ones whose State column is bare `open`.
risks_file=docs/architecture/07-risks.md
risks_total=0
risks_open=0
if [ -f "$risks_file" ]; then
  rows=$(grep -E '^\|[[:space:]]*R-[0-9]+[[:space:]]*\|' "$risks_file" || true)
  if [ -n "$rows" ]; then
    risks_total=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
    risks_open=$(printf '%s\n' "$rows" | grep -cE '\|[[:space:]]*open[[:space:]]*\|?[[:space:]]*$' || true)
  fi
fi

adrs=$(find docs/adr -maxdepth 1 -type f -name 'ADR-*.md' 2>/dev/null | wc -l | tr -d ' ')

# ---- the claims -------------------------------------------------------------------------------------------

# <claim regex> <context regex or ''> <expected numbers, space separated> <what the number is>
# The claim is reported when its first number is not among the expected ones. `~800` is still a mismatch
# against 749 — the tilde is printed with the claim so the human can decide that an approximation is fine.
scan() {
  pat=$1; ctx=$2; expect=$3; what=$4
  # shellcheck disable=SC2086
  lines=$(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -nHE "$pat" 2>/dev/null || true)
  [ -n "$lines" ] || return 0
  if [ -n "$ctx" ]; then
    lines=$(printf '%s\n' "$lines" | grep -iE "$ctx" || true)
    [ -n "$lines" ] || return 0
  fi
  printf '%s\n' "$lines" | while IFS= read -r l; do
    [ -n "$l" ] || continue
    file=${l%%:*}; rest=${l#*:}; no=${rest%%:*}; text=${rest#*:}
    claim=$(printf '%s' "$text" | grep -oE "$pat" | head -n1)
    n=$(printf '%s' "$claim" | grep -oE '[0-9]+' | head -n1)
    verdict='MISMATCH'
    for e in $expect; do
      [ "$n" = "$e" ] && verdict='ok'
    done
    printf '%s:%s: "%s" — %s now %s  [%s]\n' \
      "$file" "$no" "$claim" "$what" "$(printf '%s' "$expect" | sed 's/ / or /g')" "$verdict"
  done
}

# The three claim shapes of issue #458. "N of N" is only a count claim on a line that is about risks —
# anywhere else it is a fraction of something the repo cannot count.
out_tests=$(scan '~?[0-9]+ tests' '' "$tests" 'test attributes in the repo')
out_open=$(scan '[0-9]+ open risks' '' "$risks_open" 'open rows in 07-risks.md')
out_of=$(scan '[0-9]+ of [0-9]+' '[Rr]isk' "$risks_open $risks_total" 'open / total rows in 07-risks.md')
out_adr=$(scan '[0-9]+ ADRs' '' "$adrs" 'files in docs/adr/')

out=$(printf '%s\n%s\n%s\n%s\n' "$out_tests" "$out_open" "$out_of" "$out_adr" | grep -v '^$' || true)

echo "doc-facts.sh: $repo"
echo "counted now: $tests test attributes · $risks_total risk rows ($risks_open open) · $adrs ADRs"
echo
if [ -z "$out" ]; then
  echo "no numeric claim of a countable kind found in docs/**, CONTEXT.md, README.md."
else
  printf '%s\n' "$out"
  hits=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  misses=$(printf '%s\n' "$out" | grep -c 'MISMATCH' || true)
  echo
  echo "$hits claim(s), $misses mismatch(es)."
fi
echo
echo "Candidates only. doc-facts proposes; it never fixes a number and never decides that one is wrong."
echo "Each mismatch is a gap-ledger row whose answer is which task owns the update — the same branch that"
echo "falsifies the count updates it (docs/architecture/README.md § Maintenance). An explicit decline is an answer too."
exit 0
