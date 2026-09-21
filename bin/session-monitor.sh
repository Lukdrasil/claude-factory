#!/bin/sh
# Dispatch from the main session: one interactive Claude session per unit of work, instead of a subagent in the
# coordinator's own context. With herdr each session gets its own tab in its own worktree; without herdr the
# same lines are printed for the human to run.
#
#   session-monitor.sh [--parent <T-NNN> [--wave N] [--step <name>]] [--max N] [--workspace <id>]
#                      [--state <dir>] [--dry-run]
#
# Three modes:
#   --parent T-NNN   the blocks of one wave of a solve cut, from bin/spawn-plan.sh
#   --parent T-NNN --step <name>
#                    one session for a parent-level step of `factory herd`: triage, grill,
#                    plan-check or decompose. It runs in the registered clone, or in the session
#                    worktree once there is one.
#   no argument      every task with `status: ready` and no owner, across the state repo, and one
#                    `mr-watch.sh <T-NNN> --once` pass per parent with an open block MR, whose event lines are
#                    printed through, so a merge after the solve session ended still becomes state
#
# --workspace <id> is the herdr workspace the tabs are created in, default $HERDR_WORKSPACE_ID, so a
# dispatched session lands in the caller's own group and not in whatever workspace another client has
# focused.
#
# `spawn:` in <state>/factory.yml decides how: `herdr` opens the sessions, `manual` (the default, and what a
# machine without herdr falls back to) prints them. --spawn <herdr|manual> overrides it for one call, which is
# what `factory herd` passes, since herd is the herdr flow whatever the config says. --dry-run prints whatever it would do and changes nothing.
# --max caps how many go out at once, default 5, the width cap of solve.md.
#
# One line per unit on stdout: `<id> <state-word> <cwd>`, where the state word is `spawned`, `printed` or
# `skipped`. Exit 0 when every unit was dispatched or printed, 1 with the reason on stderr when the state or
# the parent cannot be resolved, 2 when herdr was asked for and a spawn failed.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'session-monitor: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

parent='' wave='' state='' dry='' max=5 step='' spawn='' workspace=${HERDR_WORKSPACE_ID:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --parent) [ $# -ge 2 ] || die "--parent needs a value"; parent=$2; shift 2 ;;
    --wave) [ $# -ge 2 ] || die "--wave needs a value"; wave=$2; shift 2 ;;
    --step) [ $# -ge 2 ] || die "--step needs a value"; step=$2; shift 2 ;;
    --max) [ $# -ge 2 ] || die "--max needs a value"; max=$2; shift 2 ;;
    --workspace) [ $# -ge 2 ] || die "--workspace needs a value"; workspace=$2; shift 2 ;;
    --spawn) [ $# -ge 2 ] || die "--spawn needs a value"; spawn=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
case "$max" in ''|*[!0-9]*) die "--max takes a number, not '$max'" ;; esac
case "$step" in
  ''|triage|grill|plan-check|decompose) ;;
  *) die "--step takes triage, grill, plan-check or decompose, not '$step'" ;;
esac
[ -z "$step" ] || [ -n "$parent" ] || die "--step needs the --parent it is a step of"

# see: solve-next.sh and spawn-plan.sh, the one state resolution of the factory scripts
if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    here=$(pwd)
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
  fi
fi
[ -d "$state/repos" ] || die "no state repo at $state"
root=$(dirname -- "$state")

mode=manual
if [ -f "$state/factory.yml" ]; then
  mode=$(sed -n 's/^spawn:[[:space:]]*//p' "$state/factory.yml" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
  [ -n "$mode" ] || mode=manual
fi
[ -z "$spawn" ] || mode=$spawn
case "$mode" in
  herdr|manual) ;;
  *) die "spawn: in $state/factory.yml is '$mode'; it takes herdr or manual" ;;
esac
# a config that asks for herdr on a machine that has none is a fallback, not a failure: the commands still
# print and the human still runs them
if [ "$mode" = herdr ] && ! command -v herdr >/dev/null 2>&1; then
  echo "session-monitor: spawn: herdr, but herdr is not on PATH; printing the commands instead" >&2
  mode=manual
fi
if [ "$mode" = herdr ] && [ "${HERDR_ENV:-}" != 1 ]; then
  echo "session-monitor: spawn: herdr, but this session is not inside a herdr pane; printing instead" >&2
  mode=manual
fi

field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//'; }
# see: solve-next.sh, the `path:` of a repo in this state clone's own repos.yml; nothing when it has none
clone_path() { # <key>
  [ -f "$state/repos.yml" ] || return 0
  awk -v want="$1" '
    /^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k) }
    index($0, "path:") && k == want {
      p = $0; sub(/.*path:[ \t]*/, "", p); sub(/[ \t]*[,}].*$/, "", p); sub(/[ \t]+#.*$/, "", p)
      gsub(/^["'"'"']|["'"'"']$/, "", p); if (p != "") { print p; exit }
    }' "$state/repos.yml"
}
json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const o=JSON.parse(s);process.stdout.write(String(process.argv[1].split(".").reduce((a,k)=>a&&a[k],o)||""))}catch(e){}})' "$1"; }

# --- the work list -------------------------------------------------------------------------------------------
# `<id>\t<cwd>\t<model>\t<prompt>`, one unit per line
units=$(mktemp)
trap 'rm -f "$units"' EXIT

if [ -n "$parent" ]; then
  is_task_id "$parent" || die "'$parent' is not a task id"
  ptask=$(task_of "$parent" || :)
  [ -n "${ptask:-}" ] && [ -f "$ptask" ] || die "no task file with 'id: $parent'"
  key=$(field "$ptask" repo)
  [ -n "$key" ] || die "task $parent has no 'repo:' field"
  if [ -n "$step" ]; then
    # a parent-level step runs before the session worktree exists, so the cwd is the registered clone and the
    # worktree only once step 10 has made one
    cwd="$root/$key/$parent"
    [ -e "$cwd/.git" ] || cwd=$(clone_path "$key")
    [ -n "$cwd" ] || die "repo '$key' has no path: in repos.yml and $parent has no worktree, so there is nowhere to run $step"
    plugin=$(dirname -- "$bin")
    case "$step" in
      triage)
        model=$(sh "$bin/model-for.sh" triage "$(field "$ptask" tier)" '' 0 \
          "$(field "$ptask" complexity)" 2>/dev/null || echo sonnet)
        prompt="Triage $parent. Read $plugin/skills/_shared/investigate.md and $ptask, gather the recon it asks for, write ## Context into the task, set tier: and archetype:, and report with $bin/state-report.sh --task $parent --no-status." ;;
      grill)
        model=opus
        prompt="/claude-factory:grill $ptask" ;;
      plan-check)
        model=opus
        prompt="/claude-factory:architect-review plan-check $ptask" ;;
      decompose)
        model=opus
        prompt="/claude-factory:decompose $ptask" ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$parent-$step" "$cwd" "$model" "$prompt" > "$units"
  else
    set -- "$parent"
    [ -z "$wave" ] || set -- "$@" --wave "$wave"
    plan=$(sh "$bin/spawn-plan.sh" "$@" --state "$state") || die "spawn-plan refused the cut of $parent"
    printf '%s\n' "$plan" | while IFS=' ' read -r bid agent model brief; do
      [ -n "$bid" ] || continue
      printf '%s\t%s\t%s\t%s\n' "$bid" "$root/$key/$bid" "$model" \
        "You are $agent. Read $brief and do exactly what it says."
    done > "$units"
  fi
else
  for task in "$state"/repos/*/tasks/*.md; do
    [ -f "$task" ] || continue
    [ "$(field "$task" status)" = ready ] || continue
    owner=$(field "$task" owner)
    case "$owner" in ''|null|none) ;; *) continue ;; esac
    id=$(field "$task" id)
    key=$(basename -- "$(dirname -- "$(dirname -- "$task")")")
    model=$(sh "$bin/model-for.sh" "$(field "$task" archetype)" "$(field "$task" tier)" \
      "$(field "$task" phase)" 1 "$(field "$task" complexity)" 2>/dev/null || echo opus)
    printf '%s\t%s\t%s\t%s\n' "$id" "$root/$key/$id" "$model" \
      "/claude-factory:block-$(field "$task" archetype) $task"
  done > "$units"
fi

# --- the open block MRs --------------------------------------------------------------------------------------
# why: T-164, the solve session that opened the block MRs may be over, so the standalone monitor is what turns
# why: a merge on the forge into state
if [ -z "$parent" ]; then
  parents=$(
    for task in "$state"/repos/*/tasks/*.md; do
      [ -f "$task" ] || continue
      [ "$(field "$task" status)" = review ] || continue
      case "$(field "$task" mr_url)" in ''|null) continue ;; esac
      bid=$(field "$task" id)
      case "$bid" in T-[0-9][0-9][0-9]-[0-9][0-9]) printf '%s\n' "${bid%-*}" ;; esac
    done | sort -u
  )
  for p in $parents; do
    if [ -n "$dry" ]; then
      printf '  sh %s/mr-watch.sh %s --once --state %s\n' "$bin" "$p" "$state"
    elif ! sh "$bin/mr-watch.sh" "$p" --once --state "$state"; then
      echo "session-monitor: mr-watch.sh refused $p" >&2
    fi
  done
fi

[ -s "$units" ] || { echo "nothing to dispatch"; exit 0; }

# --- dispatch ------------------------------------------------------------------------------------------------
rc=0 n=0
while IFS='	' read -r id cwd model prompt; do
  n=$((n + 1))
  if [ "$n" -gt "$max" ]; then
    printf '%s skipped %s\n' "$id" "$cwd"
    continue
  fi
  if [ ! -d "$cwd" ]; then
    printf '%s skipped %s\n' "$id" "$cwd"
    echo "session-monitor: no worktree at $cwd; run worktree-add.sh $id first" >&2
    continue
  fi
  if [ "$mode" = manual ] || [ -n "$dry" ]; then
    printf '%s printed %s\n' "$id" "$cwd"
    printf '  cd %s && claude --model %s "%s"\n' "$cwd" "$model" "$prompt"
    continue
  fi
  # herdr agent names are [a-z][a-z0-9_-]{0,31} and unique among live agents
  name=$(printf '%s' "$id" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  # the tab belongs to the caller's own workspace, not to whatever another client has focused
  set -- tab create --cwd "$cwd" --label "$id" --no-focus
  [ -z "$workspace" ] || set -- "$@" --workspace "$workspace"
  pane=$(herdr "$@" | json result.root_pane.pane_id)
  if [ -z "$pane" ]; then
    echo "session-monitor: herdr tab create gave no pane id for $id" >&2
    rc=2; continue
  fi
  if ! herdr agent start "$name" --kind claude --pane "$pane" -- --model "$model" >/dev/null; then
    echo "session-monitor: herdr agent start failed for $id in pane $pane" >&2
    rc=2; continue
  fi
  if ! herdr agent prompt "$name" "$prompt" >/dev/null; then
    echo "session-monitor: herdr agent prompt failed for $id; the session is up, prompt it by hand" >&2
    rc=2; continue
  fi
  printf '%s spawned %s\n' "$id" "$cwd"
done < "$units"
exit $rc
