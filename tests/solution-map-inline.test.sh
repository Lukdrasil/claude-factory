#!/bin/sh
# solution-map-inline.sh inlines the mermaid build vendored in the plugin, and report-preview names the same
# vendored copy instead of a claude-os checkout (T-249 F3).
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

page="$tmp/index.html"
cat > "$page" <<'EOF'
<!doctype html>
<html>
<head>
<script>
<!-- slot:mermaid -->
</script>
</head>
<body></body>
</html>
EOF

sh "$root/bin/solution-map-inline.sh" "$page" >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ]; check '3a solution-map-inline.sh exits 0 on a page with the slot' $?
[ -s "$tmp/err" ] && cat "$tmp/err"
! grep -q 'slot:mermaid' "$page"; check '3a no slot:mermaid is left in the page' $?
grep -qF 'version:"11.17.0"' "$page"; check '3a the page holds the mermaid 11.17.0 build' $?

n=$(grep -c claude-os "$root/agents/report-preview.md")
[ "$n" = 0 ]; check '3b agents/report-preview.md does not name claude-os' $?

exit "$fail"
