#!/bin/sh
# The writer of two settings the human changes from the UI, each in one commit under the state lock (state_write,
# lib-tasks.sh), never pushed (state-push.sh publishes): a cap of factory.yml `capacity:` and a repo's
# `default_branch:` in repos.yml. The CEO runs it on the lines `set capacity <name> <N>` and `set default branch
# <key> <branch>` (references/ceo.md). A task's own base is state-report.sh --base-branch.
#
#   state-set.sh capacity <sessions|role> <N> [--state <dir>]
#   state-set.sh default-branch <key> <branch> [--state <dir>]
#
# capacity rewrites the `<name>: <n>` pair of the capacity: block, flow or block spelling, the pair capacity.sh
# reads; a role with no cap yet is added to the flow `roles: {...}` map. default-branch rewrites the
# `default_branch:` of the key's entry, flat or indented. The same value again commits nothing. Prints
# `<name> <N>` or `<key> <branch>`.
#
# Exit 0 = set, or already set; 1 = refused (usage, a value out of range, a name or key that is not there, a
# roles: map in block spelling), nothing written; 2 = not written or not committed (the state lock was held
# longer than STATE_LOCK_WAIT seconds, default 30, or git refused the commit).
set -eu

die() { printf 'state-set: %s\n' "$1" >&2; exit 1; }
die2() { printf 'state-set: %s\n' "$1" >&2; exit 2; }
usage='usage: state-set.sh capacity <sessions|role> <N> | default-branch <key> <branch> [--state <dir>]'

what='' name='' value='' state='' n=0
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'; $usage" ;;
    *) case "$n" in 0) what=$1 ;; 1) name=$1 ;; 2) value=$1 ;; *) die "$usage" ;; esac; n=$((n + 1)); shift ;;
  esac
done
[ "$n" = 3 ] || die "$usage"
case "$name" in ''|*[!A-Za-z0-9_-]*) die "'$name' is not a key or a role name" ;; esac
case "$what" in
  capacity)
    case "$value" in ''|*[!0-9]*) die "a cap is a number from 0 to 99, not '$value'" ;; esac
    [ "$value" -le 99 ] || die "a cap is a number from 0 to 99, not '$value'"
    file=factory.yml ;;
  default-branch)
    git check-ref-format --branch "$value" >/dev/null 2>&1 || die "'$value' is not a branch name"
    file=repos.yml ;;
  *) die "$usage" ;;
esac

. "$(dirname -- "$0")/lib-tasks.sh"

if [ -z "$state" ]; then state=$(resolve_state_dir "$PWD"); fi
state=$(git -C "$state" rev-parse --show-toplevel 2>/dev/null) || die "$state is not a state clone, pass --state <dir>"
[ -f "$state/$file" ] || die "$state has no $file"

state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die2 "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
  *) die2 "the state lock could not be taken in $state, is it a git clone?" ;;
esac

# exit 3: the name or key is not there; 4: a new role and no flow roles: map to add it to
if [ "$what" = capacity ]; then
  awk -v k="$name" -v v="$value" '
    function pair(s) { return match(s, "(^|[^A-Za-z0-9_-])" k "[ \t]*:[ \t]*[0-9]+") }
    on && /^[^ \t#]/ { on = 0 }
    /^capacity:/ { on = 1 }
    on && !done && pair($0) {
      pre = substr($0, 1, RSTART - 1); m = substr($0, RSTART, RLENGTH); post = substr($0, RSTART + RLENGTH)
      lead = (m ~ /^[^A-Za-z0-9_-]/) ? substr(m, 1, 1) : ""
      $0 = pre lead k ": " v post; done = 1
    }
    { line[NR] = $0; if (on) { if ($0 ~ /roles:[ \t]*\{/) flow = NR; if (flow && $0 ~ /\}/ && !cl) cl = NR } }
    END {
      if (!done) {
        if (k == "sessions" || !cl) exit (k == "sessions" ? 3 : 4)
        s = line[cl]; i = index(s, "}"); line[cl] = substr(s, 1, i - 1) ", " k ": " v substr(s, i)
      }
      for (j = 1; j <= NR; j++) print line[j]
    }' "$state/$file" > "$state/$file.tmp" && rc=0 || rc=$?
else
  awk -v k="$name" -v v="$value" '
    /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
    key == k && !done && match($0, /default_branch[ \t]*:[ \t]*[^ \t,}#]+/) {
      $0 = substr($0, 1, RSTART - 1) "default_branch: " v substr($0, RSTART + RLENGTH); done = 1
    }
    { print }
    END { if (!done) exit 3 }' "$state/$file" > "$state/$file.tmp" && rc=0 || rc=$?
fi
case "$rc" in
  0) ;;
  3) rm -f "$state/$file.tmp"; die "$name is not in $state/$file" ;;
  4) rm -f "$state/$file.tmp"; die "$name has no cap yet and the roles: of $state/$file is no {...} map: add it there by hand" ;;
  *) rm -f "$state/$file.tmp"; die2 "$state/$file could not be rewritten" ;;
esac

if cmp -s "$state/$file" "$state/$file.tmp"; then
  rm -f "$state/$file.tmp"
else
  mv -f "$state/$file.tmp" "$state/$file"
  state_write "$state" "chore(state): $what $name $value" "$file" || die2 "git refused the commit in $state; $file is written but not committed"
fi
printf '%s %s\n' "$name" "$value"
