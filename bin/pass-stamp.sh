#!/bin/sh
# The dates of the memory passes (agent-org plan 3.8, Q4): the daily and the weekly pass of a scope end by
# stamping its passes.yml, two lines `daily: <UTC, YYYY-MM-DDTHH:MM:SSZ>|never` and `weekly: ...`, written and
# committed alone under the state lock (state_write, lib-tasks.sh; no push). A scope keeps the file in the folder
# it owns:
#   global                    memory/global/passes.yml
#   repo:<key>                repos/<key>/memory/passes.yml
#   agent:<agent>             agents/<agent>/memory/passes.yml
#   repo-agent:<key>/<agent>  repos/<key>/agents/<agent>/passes.yml
# --due prints one `<scope> <daily|weekly> <last stamp|never>` line per scope whose pass is due, sorted bytewise:
# daily when never stamped or stamped 24 h ago or more and the scope holds a proposal (memory/proposals/*.md) or a
# draft (drafts/*.md beside passes.yml), weekly when never stamped or stamped 7 d ago or more and it holds a draft.
# A scope with nothing to judge is never due: a pass is an interactive session and costs one. PASS_STAMP_NOW
# (epoch seconds) stands in for the clock of --due.
#
#   pass-stamp.sh <daily|weekly> <scope> [--state <dir>]   exit 0 stamped, 1 refused, 2 lock or git
#   pass-stamp.sh --due <daily|weekly> [--state <dir>]     exit 0, 1 on a wrong kind
set -eu

kind='' scope='' state='' due=0
die() { printf 'pass-stamp: %s\n' "$1" >&2; exit 1; }
usage="usage: pass-stamp.sh <daily|weekly> <scope> [--state <dir>] | --due <daily|weekly> [--state <dir>]"

while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --due) due=1; shift ;;
    -*) die "unknown argument '$1'" ;;
    *)
      if [ -z "$kind" ]; then kind=$1
      elif [ -z "$scope" ] && [ "$due" = 0 ]; then scope=$1
      else die "too many arguments"; fi
      shift ;;
  esac
done
case "$kind" in daily|weekly) ;; *) die "$usage" ;; esac
[ "$due" = 1 ] || [ -n "$scope" ] || die "$usage"

. "$(dirname -- "$0")/lib-tasks.sh"
[ -n "$state" ] || state=$(resolve_state_dir "$(pwd)")

one_segment() { case "$1" in ''|*/*|.*) return 1 ;; esac; }

# the folder a scope owns, where its passes.yml and drafts/ sit, and its memory dir; nothing when malformed
scope_dir() { # <scope>
  case "$1" in
    global) printf '%s\n' memory/global ;;
    repo:*) one_segment "${1#repo:}" && printf '%s\n' "repos/${1#repo:}/memory" ;;
    agent:*) one_segment "${1#agent:}" && printf '%s\n' "agents/${1#agent:}/memory" ;;
    repo-agent:*/*)
      sd_k=${1#repo-agent:}; sd_a=${sd_k#*/}; sd_k=${sd_k%%/*}
      one_segment "$sd_k" && one_segment "$sd_a" && printf '%s\n' "repos/$sd_k/agents/$sd_a" ;;
  esac
}
memory_dir() { # <scope> <its folder>
  case "$1" in repo-agent:*) printf '%s\n' "$2/memory" ;; *) printf '%s\n' "$2" ;; esac
}

last() { # <passes.yml> <kind> → the stamp, or never
  l_v=''
  [ ! -f "$1" ] || l_v=$(sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
  printf '%s\n' "${l_v:-never}"
}

any_md() { # <dir> → 0 when it holds a top-level *.md
  for am_f in "$1"/*.md; do [ -f "$am_f" ] && return 0; done
  return 1
}

if [ "$due" = 1 ]; then
  now=${PASS_STAMP_NOW:-$(date +%s)}
  case "$kind" in daily) max=86400 ;; weekly) max=604800 ;; esac
  {
    [ ! -d "$state/memory/global" ] || echo global
    for d in "$state"/repos/*/memory; do [ -d "$d" ] || continue; k=${d%/memory}; echo "repo:${k##*/}"; done
    for d in "$state"/agents/*/memory; do [ -d "$d" ] || continue; a=${d%/memory}; echo "agent:${a##*/}"; done
    for d in "$state"/repos/*/agents/*/; do
      [ -d "$d" ] || continue
      d=${d%/}; a=${d##*/}; k=${d%/agents/*}
      echo "repo-agent:${k##*/}/$a"
    done
  } | while IFS= read -r s; do
    dir=$(scope_dir "$s") || continue
    [ -n "$dir" ] || continue
    work=0
    any_md "$state/$dir/drafts" && work=1
    if [ "$work" = 0 ] && [ "$kind" = daily ]; then any_md "$state/$(memory_dir "$s" "$dir")/proposals" && work=1; fi
    [ "$work" = 1 ] || continue
    at=$(last "$state/$dir/passes.yml" "$kind")
    # a stamp is UTC; days from the civil date, so no date(1) dialect is needed to read one back
    awk -v at="$at" -v now="$now" -v max="$max" 'BEGIN {
      if (at !~ /^[0-9]+-[0-9]+-[0-9]+T[0-9]+:[0-9]+:[0-9]+Z$/ || length(at) != 20) exit 0
      if (substr(at, 5, 1) substr(at, 8, 1) substr(at, 11, 1) substr(at, 14, 1) substr(at, 17, 1) != "--T::") exit 0
      y = substr(at, 1, 4) + 0; m = substr(at, 6, 2) + 0; d = substr(at, 9, 2) + 0
      if (m <= 2) { y--; m += 12 }
      days = 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d - 719469
      t = days * 86400 + substr(at, 12, 2) * 3600 + substr(at, 15, 2) * 60 + substr(at, 18, 2)
      exit (now - t >= max) ? 0 : 1
    }' || continue
    printf '%s %s %s\n' "$s" "$kind" "$at"
  done | LC_ALL=C sort
  exit 0
fi

dir=$(scope_dir "$scope") || dir=''
[ -n "$dir" ] || die "unknown scope '$scope', one of global, repo:<key>, agent:<agent>, repo-agent:<key>/<agent>"
case "$scope" in
  repo:*|repo-agent:*)
    k=${scope#*:}; k=${k%%/*}
    [ -d "$state/repos/$k" ] || die "no repo $k in $state" ;;
esac
[ -d "$state/.git" ] || die "$state is not a state clone, run from one or pass --state <dir>"

# the other line is read inside the lock, so two passes of one scope never write each other's date away
state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) printf 'pass-stamp: another session holds the state lock of %s, waited %s s; nothing was written\n' "$state" "${STATE_LOCK_WAIT:-30}" >&2; exit 2 ;;
  *) printf 'pass-stamp: the state lock could not be taken in %s\n' "$state" >&2; exit 2 ;;
esac
f=$dir/passes.yml
stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
daily=$(last "$state/$f" daily)
weekly=$(last "$state/$f" weekly)
case "$kind" in daily) daily=$stamp ;; weekly) weekly=$stamp ;; esac
mkdir -p "$state/$dir"
printf 'daily: %s\nweekly: %s\n' "$daily" "$weekly" > "$state/$f"
state_write "$state" "chore(memory): $kind pass $scope" "$f" || {
  printf 'pass-stamp: git refused the commit of %s\n' "$f" >&2; exit 2; }
printf '%s %s %s\n' "$scope" "$kind" "$stamp"
