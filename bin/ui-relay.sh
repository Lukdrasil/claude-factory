#!/bin/sh
# The one relay of the Factory UI: types each answer file after <UI home>/sessions/<sid>/delivered into the herdr
# pane of that session.md, in seq order, once the pane has held idle or done for the settle time and still reports
# the session id, then records the seq in delivered. A held answer stays queued and sessions/<sid>/relay says why:
# `<seq> blocked|gone|prompt-failed`. --once makes one pass over every session and exits.
#
#   ui-relay.sh [--home <dir>] [--settle <s>] [--once]
set -eu

die() { printf 'ui-relay: %s\n' "$1" >&2; exit 1; }

home=${FACTORY_UI_HOME:-$HOME/.claude-factory/ui} settle=2 once=0
while [ $# -gt 0 ]; do
  case "$1" in
    --home|--settle)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --home) home=$2 ;; --settle) settle=$2 ;; esac
      shift 2 ;;
    --once) once=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
case "$settle" in ''|.|*[!0-9.]*|*.*.*) die "--settle <s> takes seconds" ;; esac
settle_ms=$(awk -v s="$settle" 'BEGIN { printf "%d", s * 1000 }')

state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT
trap 'exit 143' INT TERM

now() { date +%s%3N; }

pane_of() { # <session.md>
  awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
    index($0, "pane:") == 1 { v = substr($0, 6); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1"
}

put() { # <file> <line>: through a temp file and a rename, only when the line changes
  [ "$(cat "$1" 2>/dev/null)" != "$2" ] || return 0
  printf '%s\n' "$2" > "${1%/*}/.relay.$$"
  mv -f "${1%/*}/.relay.$$" "$1"
}

queued() { # <session dir> <delivered>: "<seq> <file>" of the lowest answer after delivered
  ls -- "$1/answers" 2>/dev/null | awk -v d="$2" '/^[0-9]+-[a-z0-9-]+\.txt$/ {
    s = substr($0, 1, index($0, "-") - 1) + 0; if (s > d + 0) print s, $0 }' | sort -n | head -n 1
}

settled() { # <sid> <state_change_seq>: the pane has shown this state for the settle time, and nothing was typed into it
  t=$(now)
  read -r seen since < "$state/$1" 2>/dev/null || seen='' since=''
  if [ "$seen" != "$2" ]; then printf '%s %s\n' "$2" "$t" > "$state/$1"; since=$t; fi
  [ "$since" != typed ] && [ $((t - since)) -ge "$settle_ms" ]
}

typed_into() { # <pane> <text>: herdr took the text; a stall comes after the input was sent, so it counts as typed
  out=$(herdr agent prompt "$1" "$2" --wait --until working --until idle --until done --until blocked 2>/dev/null) \
    && return 0
  case "$out" in *'"agent_prompt_stalled"'*) return 0 ;; esac
  return 1
}

step() { # <session dir>: types at most one answer; 0 while the queue may still move in this pass
  dir=$1 sid=${1##*/}
  [ -f "$dir/session.md" ] || return 1
  d=$(cat "$dir/delivered" 2>/dev/null) || d=0
  case "$d" in ''|*[!0-9]*) d=0 ;; esac
  next=$(queued "$dir" "$d")
  if [ -z "$next" ]; then rm -f "$dir/relay"; return 1; fi
  seq=${next%% *} file=$dir/answers/${next#* }

  pane=$(pane_of "$dir/session.md") json=''
  [ -z "$pane" ] || json=$(herdr agent get "$pane" 2>/dev/null) || json=''
  got=$(printf '%s' "$json" | sed -n 's/.*"agent_session":{[^}]*"value":"\([^"]*\)".*/\1/p')
  if [ -z "$pane" ] || [ "$got" != "$sid" ]; then put "$dir/relay" "$seq gone"; return 1; fi
  case "$(printf '%s' "$json" | sed -n 's/.*"agent_status":"\([^"]*\)".*/\1/p')" in
    idle|done) ;;
    blocked) put "$dir/relay" "$seq blocked"; return 1 ;;
    *) return 1 ;;
  esac
  cseq=$(printf '%s' "$json" | sed -n 's/.*"state_change_seq":\([0-9]*\).*/\1/p')
  settled "$sid" "$cseq" || return 0

  text=$(cat "$file"; printf x)
  if typed_into "$pane" "${text%x}"; then
    printf '%s typed\n' "$cseq" > "$state/$sid"
    put "$dir/delivered" "$seq"
    moved=1
    return 0
  fi
  printf '%s %s\n' "$cseq" "$(now)" > "$state/$sid"
  put "$dir/relay" "$seq prompt-failed"
  return 1
}

done_here=' '
while :; do
  busy=0 moved=0
  for dir in "$home"/sessions/*/; do
    dir=${dir%/}
    case "$done_here" in *" ${dir##*/} "*) continue ;; esac
    if step "$dir"; then busy=1; elif [ "$once" = 1 ]; then done_here="$done_here${dir##*/} "; fi
  done
  [ "$once" = 0 ] || [ "$busy" = 1 ] || exit 0
  [ "$moved" = 1 ] || sleep 0.25
done
