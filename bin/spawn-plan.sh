#!/bin/sh
# The spawn plan of one wave of a `factory solve` cut (T-154), so the coordinator does not write five spawn
# instructions by hand.
#
#   spawn-plan.sh <T-NNN> [--wave N] [--state <dir>]
#                            the wave of the plan dag-check.sh prints; default the first wave that still has a
#                            block to run
#
# The waves are dag-check.sh's, recomputed here rather than read from the progress file, so the plan a spawn
# runs on is the plan the check passed. A block of the wave is planned when every id in its `depends_on` is a
# block whose status is `review` or `done`, which is what merged into the session branch means (solve.md step
# 11); the rest of the wave waits for the next call. A wave is at most five blocks, the width cap of solve.md.
#
# Per planned block, in wave order, stdout carries one line
#
#   <block-id> <agent> <model> <brief path>
#
# where the agent is what `model-for.sh --agent` prints, the model what `model-for.sh` prints, and the brief is
# the whole output of `block-brief.sh <block-id> --agent <agent>` written to
# `<root>/<key>/.harness/<T-NNN>/brief-<block-id>.md`. The phase both picks is the block's own `phase:` field;
# a block that has none is in the implement phase when lib-tasks.sh's single_phase says so (green, or yellow
# at complexity low: red-first TDD inside one agent) and in the tests phase otherwise.
#
# Exit 0 with the plan. Exit 1 with the reason on stderr when no parent id is given, when the id resolves to no
# task file, when dag-check.sh refuses the cut, when the requested wave is not in the plan, or when no block of
# the wave is ready to run.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'spawn-plan: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

id='' state='' want_wave=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --wave) [ $# -ge 2 ] || die "--wave needs a value"; want_wave=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one parent id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: spawn-plan.sh <T-NNN> [--wave N] [--state <dir>]"
case "$want_wave" in
  ''|*[!0-9]*) [ -z "$want_wave" ] || die "--wave takes a wave number, not '$want_wave'" ;;
esac

# see: solve-next.sh and block-brief.sh, the one state resolution of the factory scripts
if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    here=$(pwd)
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
  fi
fi

# invariant: task_of reads the shell variable $state, it takes no state argument
task=$(task_of "$id" || :)
[ -n "$task" ] || die "$id resolves to no task file under $state/repos/*/tasks"

key=${task#"$state/repos/"}
key=${key%%/*}
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac
harness="$root/$key/.harness/$id"

fm() { # <file> <key>
  v=$(awk -v k="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    { c = index($0, ":"); if (c == 0 || $0 ~ /^[ \t]/) next
      if (substr($0, 1, c - 1) != k) next
      v = substr($0, c + 1); sub(/ #.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1")
  [ "$v" = null ] || printf '%s' "$v"
}

deps_of() { # <file>
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    /^depends_on:[[:space:]]*/ {
      d = $0; sub(/^depends_on:[[:space:]]*/, "", d)
      gsub(/[][,"'"'"']/, " ", d)
      n = split(d, a, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
      exit
    }' "$1"
}

merged() { # <block id>: its status is review or done
  f=$(task_of "$1" || :)
  [ -n "$f" ] || return 1
  case "$(fm "$f" status)" in review|done|closed) return 0 ;; esac
  return 1
}

plan=$("$bin/dag-check.sh" "$id" --state "$state") || die "dag-check.sh refuses the cut of $id, so no wave of it is safe to spawn"

# the wave lines of the plan, one per line, reduced to the block ids on them
wave_ids() { # <wave number>
  printf '%s\n' "$plan" | awk -v want="$1" '
    { match($0, /wave[[:space:]]*[0-9]+/); if (RSTART == 0) next
      n = substr($0, RSTART, RLENGTH); sub(/wave[[:space:]]*/, "", n)
      if (n + 0 != want + 0) next
      while (match($0, /T-[0-9][0-9][0-9]-[0-9][0-9]/)) {
        print substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH) } }'
}

wave_numbers=$(printf '%s\n' "$plan" | awk '{ match($0, /wave[[:space:]]*[0-9]+/); if (RSTART == 0) next
  n = substr($0, RSTART, RLENGTH); sub(/wave[[:space:]]*/, "", n); print n + 0 }')

if [ -n "$want_wave" ]; then
  printf '%s\n' "$wave_numbers" | grep -qx -- "$((want_wave + 0))" \
    || die "the plan of $id has no wave $want_wave"
  wave=$want_wave
else
  # why: the first wave still carrying work is the one to spawn; an earlier wave is entirely merged already
  wave=''
  for w in $wave_numbers; do
    for b in $(wave_ids "$w"); do
      merged "$b" || { wave=$w; break; }
    done
    [ -z "$wave" ] || break
  done
  [ -n "$wave" ] || die "every block of $id is merged, so there is no wave left to spawn"
fi

mkdir -p "$harness"

lines=0
for b in $(wave_ids "$wave"); do
  [ "$lines" -lt 5 ] || break
  bf=$(task_of "$b" || :)
  [ -n "$bf" ] || continue
  merged "$b" && continue

  ready=1
  for d in $(deps_of "$bf"); do
    merged "$d" || ready=0
  done
  [ "$ready" = 1 ] || continue

  tier=$(fm "$bf" tier); [ -n "$tier" ] || tier=yellow
  archetype=$(fm "$bf" archetype); [ -n "$archetype" ] || archetype=feature
  complexity=$(fm "$bf" complexity); [ -n "$complexity" ] || complexity=medium
  attempt=$(fm "$bf" attempt); [ -n "$attempt" ] || attempt=0
  phase=$(fm "$bf" phase)
  if [ -z "$phase" ]; then
    if single_phase "$tier" "$complexity"; then phase=implement; else phase=tests; fi
  fi

  agent=$("$bin/model-for.sh" --agent "$archetype" "$tier" "$phase" "$attempt" "$complexity")
  model=$("$bin/model-for.sh" "$archetype" "$tier" "$phase" "$attempt" "$complexity")
  brief="$harness/brief-$b.md"
  "$bin/block-brief.sh" "$b" --state "$state" --agent "$agent" --phase "$phase" > "$brief"

  printf '%s %s %s %s\n' "$b" "$agent" "$model" "$brief"
  lines=$((lines + 1))
done

[ "$lines" -gt 0 ] || die "no block of wave $wave of $id is ready: every one is merged or waits on an unmerged depends_on"
