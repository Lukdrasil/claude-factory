#!/bin/sh
# The tasks in the state repo, one line each: id, status, archetype, tier, repo, owner and the goal line.
# Read-only, nothing is written, nothing is committed.
#
#   factory-list.sh --root <dir> [--repo <key>] [--status <s>[,<s>…]]
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

root='' repo='' status=''
die() { printf 'factory-list: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--repo|--status)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --root) root=$2 ;; --repo) repo=$2 ;; --status) status=$2 ;; esac
      shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done
[ -n "$root" ] || die "--root <dir> is required"
root=$(printf '%s' "$root" | sed 's:/*$::')
state="$root/state"
[ -d "$state/repos" ] || die "$state/repos is not there, is $root the factory root?"

# the same glob the hooks read tasks with (lib-tasks.sh); an unmatched glob stays literal, hence the -f guard
set -- "$state"/repos/*/tasks/*.md
[ -f "$1" ] || exit 0

# ponytail: one awk over every task file; the frontmatter is flat key: value (task-new.sh validates it),
# so a line-wise read is enough, no yaml parser for six keys.
awk -v want_repo="$repo" -v want_status="$status" '
  function flush() {
    if (f["id"] == "") return
    if (want_repo != "" && f["repo"] != want_repo) return
    if (want_status != "" && index("," want_status ",", "," f["status"] ",") == 0) return
    printf "%-11s %-12s %-9s %-7s %-14s %-22s %s\n", f["id"], f["status"], f["archetype"], f["tier"],
      f["repo"], (f["owner"] == "" || f["owner"] == "null" ? "-" : f["owner"]), goal
  }
  FNR == 1 { flush(); split("", f); goal = ""; infm = 0; seen_goal = 0 }
  FNR == 1 && $0 == "---" { infm = 1; next }
  infm && $0 == "---" { infm = 0; next }
  infm {
    c = index($0, ":"); if (c == 0 || $0 ~ /^[ \t]/) next
    k = substr($0, 1, c - 1); v = substr($0, c + 1)
    sub(/ #.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
    f[k] = v; next
  }
  # the goal is the first non-empty line under the first heading, the shape every task template writes
  !infm && /^#/ { seen_goal = 1; next }
  !infm && seen_goal && goal == "" && $0 !~ /^[ \t]*$/ { goal = $0 }
  END { flush() }
' "$@" | sort_ids
