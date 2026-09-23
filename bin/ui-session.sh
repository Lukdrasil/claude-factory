#!/bin/sh
# The one writer of <UI home>/sessions/<sid>/session.md: creates it, or updates the keys given and keeps the rest.
#
#   ui-session.sh --session <sid> [--pane <id>] [--flow <name>] [--task <id>] [--step <text>]
set -eu

die() { printf 'ui-session: %s\n' "$1" >&2; exit 1; }

sid='' pane='' flow='' task='' step=''
set_pane=0 set_flow=0 set_task=0 set_step=0
while [ $# -gt 0 ]; do
  case "$1" in
    --session|--pane|--flow|--task|--step)
      [ $# -ge 2 ] || die "$1 needs a value"
      v=$(printf '%s' "$2" | tr '\n' ' ')
      case "$1" in
        --session) sid=$v ;;
        --pane) pane=$v set_pane=1 ;;
        --flow) flow=$v set_flow=1 ;;
        --task) task=$v set_task=1 ;;
        --step) step=$v set_step=1 ;;
      esac
      shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
case "$sid" in ''|*[!A-Za-z0-9-]*) die "--session <sid> takes letters, digits and -" ;; esac

dir="${FACTORY_UI_HOME:-$HOME/.claude-factory/ui}/sessions/$sid"
file="$dir/session.md"
mkdir -p "$dir"

old() { # <key>
  [ -f "$file" ] || return 0
  awk -v k="$1" 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); print v; exit }' "$file"
}
[ "$set_pane" = 1 ] || pane=$(old pane)
[ "$set_flow" = 1 ] || flow=$(old flow)
[ "$set_task" = 1 ] || task=$(old task)
[ "$set_step" = 1 ] || step=$(old step)

tmp=$(mktemp "$dir/.session.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf -- '---\nsid: %s\npane: %s\nflow: %s\ntask: %s\nstep: %s\nupdated: %s\n---\n' \
  "$sid" "$pane" "$flow" "$task" "$step" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp"
mv -f "$tmp" "$file"
