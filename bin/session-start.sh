#!/bin/sh
# SessionStart hook, the standalone posture (ADR-0049): the context a worker gets baked into its CLAUDE.md
# (ClaudeMdBuilder, ADR-0013): the repo's toolset, then one index line per memory file of the repo and of the
# global memory instead of their bodies, top level only, never
# proposals/ — is injected as additionalContext for a registered clone, i.e. one whose toplevel is a `path:` in
# $WORK_DIR/state/repos.yml, preceded by the session's identity line (its session_id from the hook stdin and the
# `factory@<host>:<session_id>` owner string of ADR-0050). An unregistered cwd gets a one-line nudge towards the
# factory skill's init; a worker (HARNESS_WORKER=1) already has the CLAUDE.md and prints nothing. Exit 0 always.
# Two lines ride along with that context: the standalone-posture line (T-187, there is no dashboard and no gate
# that is not a command) and, when it applies, the stale-plugin warning of incident C below.
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
# Incident C (2026-09-22): the installed plugin cache is keyed by the version in `.claude-plugin/plugin.json`,
# so three merged PRs shipped nothing. The cache stayed at 0.12.0, `claude plugin update` saw no new version and
# refreshed nothing, and the day's sessions ran without attribution-gate.sh and the MR title rule while the repo
# had both. The cheapest tell is a file the running plugin root should have and does not; the version and, for a
# dev checkout, the commit are the other two. Everything here is best effort: a hook that fails tells nobody
# anything, so every step falls through to silence.
stale_plugin_warning() {
  spw_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd) || return 0
  [ -n "${spw_root:-}" ] || return 0
  spw_why=''
  [ -f "$spw_root/bin/attribution-gate.sh" ] || spw_why='bin/attribution-gate.sh is missing from it'
  spw_ver=''
  if [ -f "$spw_root/.claude-plugin/plugin.json" ]; then
    spw_ver=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$spw_root/.claude-plugin/plugin.json" | head -n1)
  fi
  spw_inst=${HOME:-}/.claude/plugins/installed_plugins.json
  if [ -z "$spw_why" ] && [ -n "$spw_ver" ] && [ -f "$spw_inst" ]; then
    # the one entry of this plugin, from its key to the end of its array; no JSON parser for two flat fields
    spw_entry=$(sed -n '/"claude-factory@/,/^[[:space:]]*\]/p' "$spw_inst" 2>/dev/null) || spw_entry=''
    spw_iver=$(printf '%s\n' "$spw_entry" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    if [ -n "$spw_iver" ] && [ "$spw_iver" != "$spw_ver" ]; then
      spw_why="the installed version is $spw_iver and this repo says $spw_ver"
    elif [ -e "$spw_root/.git" ]; then
      spw_isha=$(printf '%s\n' "$spw_entry" | sed -n 's/.*"gitCommitSha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
      spw_head=$(git -C "$spw_root" rev-parse HEAD 2>/dev/null) || spw_head=''
      if [ -n "$spw_isha" ] && [ -n "$spw_head" ] && [ "$spw_isha" != "$spw_head" ]; then
        spw_why="it was installed from $(printf '%.8s' "$spw_isha") and HEAD is $(printf '%.8s' "$spw_head")"
      fi
    fi
  fi
  [ -n "$spw_why" ] || return 0
  printf 'Warning: the installed claude-factory plugin is older than the repo (%s): run `claude plugin update claude-factory`.\n' "$spw_why"
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
  # T-187: four sessions told their user to "close it in the dashboard" on a machine that has none, because
  # every text they had read named one and the single sentence that says otherwise lives in a skill a worker
  # never loads.
  printf 'Standalone posture (ADR-0050): there is no dashboard. Every human gate is a command: task-approve.sh, task-done.sh, factory approve / done. Never tell the user to do something in a dashboard.\n'
  stale_plugin_warning
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
