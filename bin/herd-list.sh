#!/bin/sh
# The herds in flight, one line each: every live parent that belongs to a request (`request:` set) and is not done
# or closed, whatever step it is at. Read-only, nothing is written, nothing is committed. rearm-check.sh prints
# these lines to a session whose herd watchers are gone, and the CEO reads them to see what it watches.
#
#   herd-list.sh [--state <dir>]
#
# Line: `<request> <priority> <T-id> <repo> <status>`, the task's own priority (`P2` when it has none), ordered by
# priority and then by id (sort_ids). Blocks, parents without a request and the archive are no herds.
#
# Exit 0 with the lines, or nothing when no herd is in flight; 1 on bad usage.
set -eu

state=''
die() { printf 'herd-list: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    *) die "unknown argument '$1'; usage: herd-list.sh [--state <dir>]" ;;
  esac
done

. "$(dirname -- "$0")/lib-tasks.sh"

if [ -z "$state" ]; then state=$(resolve_state_dir "$PWD"); fi
case "$state" in /*|[A-Za-z]:/*) ;; *) state="$PWD/$state" ;; esac
state=$(printf '%s' "$state" | sed 's:/*$::')
[ -d "$state/repos" ] || die "$state is not a state clone, pass --state <dir>"

set --
while IFS= read -r f; do [ -z "$f" ] || set -- "$@" "$f"; done <<EOF
$(task_files)
EOF
[ $# -gt 0 ] || exit 0

awk -v prefix="$state/repos/" '
  function flush(   p) {
    if (f["id"] !~ /^T-([A-Z]+-)?[0-9]+$/) return
    if (f["request"] == "" || f["request"] == "null" || f["status"] == "done" || f["status"] == "closed") return
    p = f["priority"]; if (p !~ /^P[0-3]$/) p = "P2"
    print f["id"], p, f["request"], k, f["status"]
  }
  FNR == 1 { flush(); split("", f); fm = 0; k = substr(FILENAME, length(prefix) + 1); sub(/\/.*$/, "", k) }
  FNR == 1 && /^---[ \t\r]*$/ { fm = 1; next }
  fm && /^---[ \t\r]*$/ { fm = 0; next }
  fm {
    c = index($0, ":"); if (c < 2 || $0 ~ /^[ \t#]/) next
    name = substr($0, 1, c - 1); if (name in f) next
    v = substr($0, c + 1); sub(/[ \t]+#.*$/, "", v); gsub(/^[ \t]+|[ \t\r]+$/, "", v)
    f[name] = v
  }
  END { flush() }' "$@" \
  | sort_ids \
  | awk '{ b[$2] = b[$2] $3 " " $2 " " $1 " " $4 " " $5 "\n" } END { printf "%s%s%s%s", b["P0"], b["P1"], b["P2"], b["P3"] }'
