#!/bin/sh
# solution-map-check.sh — the fidelity checker for the solution-map skill. Read-only, no jq: grep/sed over the
# markdown, the extractor's JSON and the rendered HTML. Two independent checks, run at different steps of the
# skill (SKILL.md steps 3 and 5):
#
#   md   <map.json> <file.md>...   every backticked C#-style type name in the markdown is a real type the
#                                   extractor found — a name an explorer invented never survives this check.
#   html <index.html> <file.md>... every `##`/`###` heading of the markdown made it into the rendered page —
#                                   a section the render agent dropped or mangled never survives this check.
#
# Neither check fixes anything; a failure is a list of exact misses for the skill to act on.
set -eu

usage() {
  echo "usage: solution-map-check.sh md <map.json> <file.md>..." >&2
  echo "       solution-map-check.sh html <index.html> <file.md>..." >&2
  exit 2
}

[ $# -ge 1 ] || usage
mode=$1
shift
case "$mode" in
  md|html) : ;;
  *) usage ;;
esac
[ $# -ge 2 ] || usage

target=$1
shift
[ -f "$target" ] || { echo "solution-map-check.sh: '$target' not found" >&2; exit 2; }
for f in "$@"; do
  [ -f "$f" ] || { echo "solution-map-check.sh: '$f' not found" >&2; exit 2; }
done

work=$(mktemp)
trap 'rm -f "$work"' EXIT

if [ "$mode" = "md" ]; then
  # ---- the ground truth: every "name": "<value>" the JSON carries, one per line --------------------------
  names_file=$(mktemp)
  trap 'rm -f "$work" "$names_file"' EXIT
  grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$target" \
    | sed -E 's/^"name"[[:space:]]*:[[:space:]]*"//; s/"$//' \
    > "$names_file" || :

  total=0
  missing=0
  for f in "$@"; do
    # A backtick span whose whole content is a C#-style type name: starts uppercase, letters/digits only —
    # that character class alone rules out dots and parentheses, so no separate filter is needed for either.
    grep -oE '`[A-Za-z0-9]+`' "$f" | sed -E 's/^`//; s/`$//' | grep -E '^[A-Z][A-Za-z0-9]+$' > "$work" || :
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      total=$((total + 1))
      if ! grep -qxF "$name" "$names_file"; then
        echo "missing $f: $name"
        missing=$((missing + 1))
      fi
    done < "$work"
  done

  [ "$missing" -eq 0 ] || exit 1
  echo "ok md: $total identifiers grounded"
  exit 0
fi

# ---- html mode: every "## "/"### " heading, backticks stripped, must occur verbatim in the page -----------
total=0
missing=0
for f in "$@"; do
  grep -E '^(## |### )' "$f" | sed -E 's/^## //; s/^### //; s/[[:space:]]+$//' > "$work" || :
  while IFS= read -r heading; do
    [ -n "$heading" ] || continue
    stripped=$(printf '%s' "$heading" | tr -d '`')
    total=$((total + 1))
    if ! grep -qF -- "$stripped" "$target"; then
      echo "missing heading: $stripped"
      missing=$((missing + 1))
    fi
  done < "$work"
done

[ "$missing" -eq 0 ] || exit 1
echo "ok html: $total headings present"
