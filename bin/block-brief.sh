#!/bin/sh
# One self-contained brief for a block (T-128), so a coordinator spawning a wave of agents does not write five
# briefs by hand. A subagent sees none of the coordinator's context, so everything it needs goes on stdout:
# the block's archetype and phase with the subagent contract they bind to, the block's `Design (approved in
# the grill):` section verbatim, its `## Checklist` verbatim when it has one, its `## Acceptance` verbatim
# (between them they name the test files the block owns), the `## Handoff` of the block's progress file when a tests phase wrote one, the repo's toolset
# command table, and, when an agent is named, the output of the sibling bin/agent-brief.sh for that agent.
#
#   block-brief.sh <block-id> [--state <dir>] [--agent <name>] [--phase <tests|implement>]
#                             the state clone; default $WORK_DIR/state, else resolved from the cwd
#                                            an agent whose memory is prepended to the brief
#                                                           the phase line; default the task's phase: field
#
# Exit 0 with the brief on stdout. Exit 1 with the reason on stderr when no block id is given, when the id
# resolves to no task file, or when the task carries no design section. A missing toolset.md is only a note on
# stderr, not a failure. Nothing here claims anything about the ordering of the briefs of a wave.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'block-brief: %s\n' "$1" >&2; exit 1; }

id='' state='' agent='' phase=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --agent) [ $# -ge 2 ] || die "--agent needs a value"; agent=$2; shift 2 ;;
    --phase) [ $# -ge 2 ] || die "--phase needs a value"; phase=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one block id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: block-brief.sh <block-id> [--state <dir>] [--agent <name>] [--phase <tests|implement>]"
case "$phase" in ''|tests|implement) ;; *) die "--phase is tests or implement, not '$phase'" ;; esac

# see: block-merge.sh, the same resolution: $WORK_DIR/state when it is a clone, else what the cwd resolves to,
# see: anchored absolute because resolve_state_dir answers relative to the cwd
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
[ -n "$task" ] || die "block $id resolves to no task file under $state/repos/*/tasks"

design=$(awk '/^Design \(approved in the grill\):[ \t]*$/ { on = 1 }
              on && (/^Facts this block needs:/ || /^## /) { exit }
              on { print }' "$task")
[ -n "$design" ] || die "block $id has no 'Design (approved in the grill):' section in $task"

checklist=$(awk '/^## Checklist[ \t]*$/ { on = 1; print; next }
                 on && /^## / { exit }
                 on { print }' "$task")

acceptance=$(awk '/^## Acceptance[ \t]*$/ { on = 1; print; next }
                  on && /^## / { exit }
                  on { print }' "$task")

if [ -n "$agent" ]; then
  "$(dirname -- "$0")/agent-brief.sh" "$agent" --state "$state"
  printf '\n'
fi

fm() { # <key>: one flat frontmatter field of the task, `null` answering as absent
  v=$(awk -v k="$1" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    { c = index($0, ":"); if (c == 0 || $0 ~ /^[ \t]/) next
      if (substr($0, 1, c - 1) != k) next
      v = substr($0, c + 1); sub(/ #.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$task")
  [ "$v" = null ] || printf '%s' "$v"
}
archetype=$(fm archetype); [ -n "$archetype" ] || archetype=feature
[ -n "$phase" ] || phase=$(fm phase)
if [ -z "$phase" ]; then
  tier=$(fm tier); [ -n "$tier" ] || tier=yellow
  complexity=$(fm complexity); [ -n "$complexity" ] || complexity=medium
  if single_phase "$tier" "$complexity"; then phase=implement; else phase=tests; fi
fi
plugin=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
key=${task#"$state/repos/"}
key=${key%%/*}
handoff=$(awk '/^## Handoff[ \t]*$/ { on = 1; print; next }
               on && /^## / { exit }
               on { print }' "$state/repos/$key/progress/$id.md" 2>/dev/null || :)

printf '# Brief for block %s\n\n' "$id"
printf 'Task file: %s\n' "$task"
printf 'Archetype: %s (skill %s/skills/block-%s/SKILL.md)\n' "$archetype" "$plugin" "$archetype"
printf 'Phase: %s\n' "$phase"
printf 'Contract: %s/skills/_shared/block-subagent.md\n\n' "$plugin"
printf '%s\n\n' "$design"
[ -z "$checklist" ] || printf '%s\n\n' "$checklist"
printf '%s\n\n' "$acceptance"
# why: the implement agent gets the tests phase's handoff from the brief, not from a `../state` path that a
# why: block worktree under <root>/<key>/ does not have
[ -z "$handoff" ] || printf '%s\n\n' "$handoff"
toolset="$state/repos/$key/toolset.md"
if [ -f "$toolset" ]; then
  printf '## Toolset commands (%s)\n\n' "$key"
  awk '/^\|/ { print }' "$toolset"
  printf '\n'
else
  printf 'block-brief: no toolset.md for repo %s, the brief carries no command table\n' "$key" >&2
fi
