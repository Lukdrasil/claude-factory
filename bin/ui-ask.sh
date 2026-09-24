#!/bin/sh
# One ask of the Factory UI: the markdown the session prints, written to <UI home>/sessions/<sid>/asks/<ask>.md
# through a temp file and a rename, then its URL on stdout. --close sets its status: answered.
#
#   ui-ask.sh --session <sid> < ask.md
#   ui-ask.sh --session <sid> --close <ask>
set -eu

die() { printf 'ui-ask: %s\n' "$1" >&2; exit 1; }

sid='' close=''
while [ $# -gt 0 ]; do
  case "$1" in
    --session|--close)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --session) sid=$2 ;; --close) close=$2 ;; esac
      shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
case "$sid" in ''|*[!A-Za-z0-9-]*) die "--session <sid> takes letters, digits and -" ;; esac

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ui=${FACTORY_UI_HOME:-$HOME/.claude-factory/ui}
asks="$ui/sessions/$sid/asks"

fm() { # <file> <key>
  awk -v k="$2" 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }' "$1"
}
valid_id() { case "$1" in ''|*[!a-z0-9-]*) return 1 ;; esac; }

mkdir -p "$asks"
tmp=$(mktemp "$asks/.ask.XXXXXX")
trap 'rm -f "$tmp"' EXIT

if [ -n "$close" ]; then
  valid_id "$close" || die "'$close' is not an ask id ([a-z0-9-]+)"
  [ -f "$asks/$close.md" ] || die "no ask $close in session $sid"
  awk 'NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { fm = 0 }
    fm && /^status:/ { print "status: answered"; next }
    { print }' "$asks/$close.md" > "$tmp"
  mv -f "$tmp" "$asks/$close.md"
  exit 0
fi

if [ ! -f "$ui/sessions/$sid/session.md" ] && [ -n "${HERDR_PANE_ID:-}" ]; then
  sh "$bin/ui-session.sh" --session "$sid" --pane "$HERDR_PANE_ID"
fi
cat > "$tmp"
for k in ask task flow step status; do
  [ -n "$(fm "$tmp" "$k")" ] || die "the frontmatter has no $k:"
done
ask=$(fm "$tmp" ask)
valid_id "$ask" || die "'$ask' is not an ask id ([a-z0-9-]+)"
case "$(fm "$tmp" status)" in open|answered) ;; *) die "status: takes open or answered" ;; esac
bad=$(awk 'NR == 1 && $0 == "---" { fm = 1; next }
  fm { if ($0 == "---") fm = 0; next }
  /^```/ { fence = !fence; next }
  fence { next }
  /^(❓ |\*\*Q[0-9])/ && !/^❓ \*\*Q[0-9]+\*\* - \*\*.+\*\*/ || /^[ \t]*[-*+][ \t]+(\*\*)?[A-Z](\)|\*\*)/ { print NR ": " $0; exit }' "$tmp")
[ -z "$bad" ] || die "line $bad: a question is '❓ **Q<n>** - **Title**: ...', an option '  **A** label' (skills/grill/SKILL.md)"
mv -f "$tmp" "$asks/$ask.md"

port=$(cat "$ui/port" 2>/dev/null || :)
token=$(cat "$ui/token" 2>/dev/null || :)
printf 'http://127.0.0.1:%s/?ask=%s/%s%s\n' "${port:-7171}" "$sid" "$ask" "${token:+#token=$token}"
