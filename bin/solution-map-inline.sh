#!/bin/sh
# solution-map-inline.sh <index.html> — replaces the template's `<!-- slot:mermaid -->` line in a rendered
# solution map with the vendored mermaid build, so the page renders its diagrams offline (SKILL.md step 5).
# The render agent leaves the slot in place; a 3.5 MB file is not something a haiku agent should Read.
set -eu

[ $# -eq 1 ] || { echo "usage: solution-map-inline.sh <index.html>" >&2; exit 2; }
page=$1
[ -f "$page" ] || { echo "solution-map-inline.sh: '$page' not found" >&2; exit 2; }

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$here/../../dotnet/ClaudeOs.Dashboard/wwwroot/js/mermaid.min.js"
[ -f "$build" ] || { echo "solution-map-inline.sh: mermaid build not found at $build" >&2; exit 2; }

grep -qF -- '<!-- slot:mermaid -->' "$page" || { echo "solution-map-inline.sh: '$page' has no <!-- slot:mermaid -->" >&2; exit 1; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
sed -e '/<!-- slot:mermaid -->/r '"$build" -e '/<!-- slot:mermaid -->/d' "$page" > "$tmp"
cat "$tmp" > "$page"
echo "ok inline: mermaid build inlined into $page"
