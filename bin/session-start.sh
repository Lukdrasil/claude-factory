#!/bin/sh
# SessionStart hook, the standalone posture (ADR-0049): the context a worker gets baked into its CLAUDE.md
# (ClaudeMdBuilder, ADR-0013): the repo's toolset, then one index line per memory file of the repo and of the
# global memory instead of their bodies, top level only, never
# proposals/ — is injected as additionalContext for a registered clone, i.e. one whose toplevel is a `path:` in
# $WORK_DIR/state/repos.yml, preceded by the session's identity line (its session_id from the hook stdin and the
# `factory@<host>:<session_id>` owner string of ADR-0050). An unregistered cwd gets a one-line nudge towards the
# factory skill's init; a worker (HARNESS_WORKER=1) already has the CLAUDE.md and prints nothing. Exit 0 always.
set -u
[ "${HARNESS_WORKER:-}" != 1 ] || exit 0

. "$(dirname -- "$0")/lib-tasks.sh"
stdin=$(cat)
cwd=$(hook_field "$stdin" cwd)
[ -n "$cwd" ] || cwd=.
sid=$(hook_field "$stdin" session_id)

# ponytail: the context goes through node on stdin, so the JSON escaping of arbitrary markdown is never done by hand
emit() { node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:s}}))})'; }

key=$(repo_key_of_cwd "$cwd")
if [ -z "$key" ]; then
  printf '%s' "This clone is not registered in a factory state repo (WORK_DIR/state/repos.yml has no path: for it) — run the factory skill's init (factory init) for this repo to register it." | emit
  exit 0
fi

state=$WORK_DIR/state
budget_bin=$(dirname -- "$0")/memory-budget.sh
over_budget() { # <scope> → 0 when memory-budget.sh reports it over budget
  [ -f "$budget_bin" ] || return 1
  sh "$budget_bin" "$1" --state "$state" 2>/dev/null | grep -qx 'over budget'
}
index_line() { # <memory file> → its first non-empty line after the frontmatter, without a leading '# '
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      if (line == "") next
      sub(/^# */, "", line)
      print line
      exit
    }
  ' "$1"
}
{
  # lesson C (2026-09-07): nothing told the session its own session_id, so the coordinator wrote an owner: it
  # guessed (a bridge/cse_ id) and the owner-based Stop lookup (owned_task_ids) never found its tasks. The id
  # is in the hook stdin, so the session is told the exact owner string of ADR-0050 first thing.
  if [ -n "$sid" ]; then
    host=$(hostname 2>/dev/null || uname -n 2>/dev/null || :)
    [ -n "$host" ] || host=localhost
    printf 'Session identity: session_id %s, owner string factory@%s:%s — use exactly this for owner: in every task this session claims (ADR-0050); a bridge/cse_ id is not it.\n' "$sid" "$host" "$sid"
  fi
  printf 'Factory context for repo %s from the state repo at %s/state (ADR-0049): the sections below are concatenated from there, not files of this clone — do not edit them here; a lesson worth keeping goes through a memory proposal (ADR-0011).\n' "$key" "$WORK_DIR"
  if [ -n "${FACTORY_MEMORY_OVER_BUDGET:-}" ]; then
    printf 'Warning: the %s memory is over its budget — consolidate it (memory-consolidate) before adding to it.\n' "$FACTORY_MEMORY_OVER_BUDGET"
  else
    ! over_budget "repo:$key" \
      || printf 'Warning: the repo:%s memory is over its budget — consolidate it (memory-consolidate) before adding to it.\n' "$key"
    ! over_budget global \
      || printf 'Warning: the global memory is over its budget — consolidate it (memory-consolidate) before adding to it.\n'
  fi
  if [ -f "$state/repos/$key/toolset.md" ]; then
    printf '\n<!-- repos/%s/toolset.md -->\n\n' "$key"
    cat "$state/repos/$key/toolset.md"
  fi
  # a glob, not `$(ls | sort)`: a memory file whose name has a space in it is two words to the shell and would be
  # dropped by the word splitting. LC_ALL=C keeps the glob's own order ordinal, the order the sort used to give;
  # it is set inside this pipeline's subshell, so nothing outside it sees it.
  LC_ALL=C
  export LC_ALL
  memory_index=
  for dir in "repos/$key/memory" memory/global; do
    [ -d "$state/$dir" ] || continue
    for f in "$state/$dir"/*.md; do
      [ -f "$f" ] || continue
      memory_index=$memory_index$dir/${f##*/}": $(index_line "$f")
"
    done
  done
  if [ -n "$memory_index" ]; then
    printf '\n<!-- memory index -->\n\nMemory index, one line per file, no bodies: read %s/<dir>/<file> when its line matches the work at hand.\n\n' "$state"
    printf '%s' "$memory_index"
  fi
} | emit
exit 0
