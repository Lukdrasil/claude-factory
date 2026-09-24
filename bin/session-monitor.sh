#!/bin/sh
# Dispatch from the main session: one interactive Claude session per unit of work, instead of a subagent in the
# coordinator's own context. With herdr each session gets its own tab in its own worktree; without herdr the
# same lines are printed for the human to run.
#
#   session-monitor.sh [--task <T-NNN> [--wave N] [--step <name>]] [--all] [--max N] [--workspace <id>]
#                      [--state <dir>] [--dry-run]
#
# Four modes:
#   --task T-NNN     one named task as a unit, and nothing else: the current wave of its T-NNN-NN blocks when
#                    it has any a dispatch may start (the plan of bin/spawn-plan.sh, less every block that is
#                    neither ready and unowned nor tests_ready with phase: implement armed, which is skipped),
#                    and otherwise the task itself when it is a ready, unowned leaf, with its archetype skill as
#                    the prompt.
#                    `--parent` is the old spelling of the same flag and still works.
#   --task T-NNN --step <name>
#                    one session for a parent-level step of `factory herd`: triage, grill,
#                    plan-check or decompose. It runs in the registered clone, or in the session
#                    worktree once there is one.
#   --all            every task with `status: ready` and no owner, across the state repo, and one
#                    `mr-watch.sh <T-NNN> --once` pass per parent with an open block MR, whose event lines are
#                    printed through, so a merge after the solve session ended still becomes state
#   no argument      the ready, unowned tasks are listed, one `<id> <repo> <status> <archetype> <goal>` per
#                    line, and nothing is dispatched (exit 1).
#
# why: on 2026-09-22 a `/claude-factory:herdr approve` session ran this script bare and the dry run listed
# why: eight ready tasks across five repos - foreign work that only `--max 1` kept from spawning. A herd starts
# why: from one task the user named, so the batch mode now has to be asked for by name (`--all`) and the bare
# why: call only shows what there is to choose from.
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
# Every unit that is really dispatched (not a dry run) is claimed first, through the one write path:
# `state-report.sh --task <id> --set-status in_progress --owner factory@<host>:pending-<id>`. The spawned
# session's own session id does not exist yet, so the claim carries a placeholder owner and the prompt opens
# with the exact reclaim command (`--set-status in_progress --owner factory@<host>:<its session id>`, the one
# step 1 of every block skill gives), which is what makes the owner-based Stop lookup of lib-tasks.sh find the
# task again. Re-reporting `in_progress` over `in_progress` is no transition, so the one command fits both a
# task this dispatch claimed and one a session picked up by hand. A claim the state clone refuses is a warning,
# not a failure: the session still starts, and its own first heartbeat is the claim that counts.
#
# Every unit carries the session name `<emoji> <repo> <id>` of `herdr-tabs.sh name`: the tab label and the
# `claude --name` of a herdr spawn, and the `--name` of a printed manual line. The herdr agent name stays the
# lowercased id. Each tab a herdr spawn creates is appended to the tab record through `herdr-tabs.sh record`,
# `<unit> <tab_id> <pane_id>` in `<root>/<key>/.harness/<T-NNN>/herdr-tabs`.
#
# One line per unit on stdout: `<id> <state-word> <cwd>`, where the state word is `spawned`, `printed` or
# `skipped`. Exit 0 when every unit was dispatched or printed, 1 with the reason on stderr when the state or
# the task cannot be resolved and when no mode was named, 2 when herdr was asked for and a spawn failed.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'session-monitor: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

parent='' wave='' state='' dry='' max=5 step='' spawn='' all='' workspace=${HERDR_WORKSPACE_ID:-}
while [ $# -gt 0 ]; do
  case "$1" in
    # --parent is the old spelling of --task, kept so `factory herd` and every recipe that names it keep working
    --task|--parent) [ $# -ge 2 ] || die "$1 needs a value"; parent=$2; shift 2 ;;
    --all) all=1; shift ;;
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
[ -z "$step" ] || [ -n "$parent" ] || die "--step needs the --task it is a step of"
[ -z "$parent" ] || [ -z "$all" ] || die "--task names one task and --all takes every ready one; pass one of them"

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

# the goal line of a task: the first non-empty line under its first heading, the shape every task template
# writes and the one factory-list.sh reads too
goal_of() { awk 'h && NF { print; exit } /^#/ { h = 1 }' "$1"; }

unowned() { case "$1" in ''|null|none|'~') return 0 ;; esac; return 1; }

# the T-NNN-NN blocks of a parent, and the ones a dispatch could still pick up
blocks_of() { # <T-NNN>
  for t in "$state"/repos/*/tasks/*.md; do
    [ -f "$t" ] || continue
    b=$(field "$t" id)
    case "$b" in "$1"-[0-9][0-9]) printf '%s\n' "$b" ;; esac
  done
}
# a block a dispatch may start: ready and unowned, or tests_ready with the implement phase the monitor armed,
# whose tests session has reported and holds nothing
dispatchable() { # <task file>
  case "$(field "$1" status)" in
    ready) unowned "$(field "$1" owner)" ;;
    tests_ready) [ "$(field "$1" phase)" = implement ] ;;
    *) return 1 ;;
  esac
}
dispatchable_blocks_of() { # <T-NNN>
  for t in "$state"/repos/*/tasks/*.md; do
    [ -f "$t" ] || continue
    b=$(field "$t" id)
    case "$b" in "$1"-[0-9][0-9]) ;; *) continue ;; esac
    dispatchable "$t" || continue
    printf '%s\n' "$b"
  done
}

# one unit of work out of one task file: the archetype skill is the prompt, the way the batch mode has always
# built it, with the claim command in front of it
unit_line() { # <task file> <id> <repo key>
  ul_model=$(sh "$bin/model-for.sh" "$(field "$1" archetype)" "$(field "$1" tier)" \
    "$(field "$1" phase)" 1 "$(field "$1" complexity)" 2>/dev/null || echo opus)
  printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$root/$3/$2" "$ul_model" "$2" \
    "$(claim_prompt "$2")/claude-factory:block-$(field "$1" archetype) $1"
}

# the ready, unowned tasks of the whole state repo, one `<id> <repo> <status> <archetype> <goal>` per line
list_ready() {
  for t in "$state"/repos/*/tasks/*.md; do
    [ -f "$t" ] || continue
    [ "$(field "$t" status)" = ready ] || continue
    unowned "$(field "$t" owner)" || continue
    printf '%s %s %s %s %s\n' "$(field "$t" id)" "$(field "$t" repo)" "$(field "$t" status)" \
      "$(field "$t" archetype)" "$(goal_of "$t")"
  done
}

host=$(hostname 2>/dev/null || uname -n 2>/dev/null || :)
[ -n "$host" ] || host=localhost

# the claim at spawn: the unit is in_progress under a placeholder owner before its session exists, so nothing
# else picks it up in the seconds before that session makes its own first heartbeat. state-report.sh resolves
# its state clone from the cwd, so it runs in the state clone itself (the triage-session case of
# resolve_state_dir). A refusal is a warning: the session still starts and claims the task itself.
claim() { # <id>
  ( cd "$state" && sh "$bin/state-report.sh" --task "$1" --set-status in_progress \
      --owner "factory@$host:pending-$1" --message "claim: $1 dispatched by session-monitor" >/dev/null ) \
    || printf 'session-monitor: the claim of %s was refused; its session claims it with its own first heartbeat\n' "$1" >&2
}

# why: on 2026-09-22 every herdr-spawned worker's first heartbeat was refused and each one read
# why: state-report.sh's source to find the claim. The exact command is the first thing the prompt says now.
# No backtick, no redirection and no dollar sign in it: the prompt is pasted inside a double-quoted
# `claude "<prompt>"` line that a human runs.
claim_prompt() { # <id>
  printf 'First take ownership of %s, the one command of step 1 of your skill: sh %s/state-report.sh --task %s --set-status in_progress --owner factory@%s:YOUR-SESSION-ID, with the session_id of your SessionStart identity line in place of YOUR-SESSION-ID (it is already in_progress for you under the placeholder owner factory@%s:pending-%s, and the owner-based Stop lookup only finds it once it carries your own id). Then: ' \
    "$1" "$bin" "$1" "$host" "$host" "$1"
}

# no mode at all is not a batch: it is the question "which task", and the answer is a list to choose from
if [ -z "$parent" ] && [ -z "$all" ]; then
  list_ready
  echo "session-monitor: name one task: --task T-NNN (--all dispatches every ready task, and only a user who asked for that by name gets it)" >&2
  exit 1
fi

# --- the work list -------------------------------------------------------------------------------------------
# `<id>\t<cwd>\t<model>\t<claim id>\t<prompt>`, one unit per line; the claim id is the task the dispatch
# claims before it starts the session, and `-` for a unit that claims nothing (a parent-level step). A literal
# `-`, not an empty field: `read` with IFS=tab folds two tabs into one, and the prompt would land in claimid.
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
    printf '%s\t%s\t%s\t%s\t%s\n' "$parent-$step" "$cwd" "$model" - "$prompt" > "$units"
  elif [ -n "$(dispatchable_blocks_of "$parent")" ]; then
    # the parent is a cut: its current wave goes out, one session per block, and nothing outside this cut does
    set -- "$parent"
    [ -z "$wave" ] || set -- "$@" --wave "$wave"
    plan=$(sh "$bin/spawn-plan.sh" "$@" --state "$state") || die "spawn-plan refused the cut of $parent"
    printf '%s\n' "$plan" | while IFS=' ' read -r bid agent model brief; do
      [ -n "$bid" ] || continue
      bf=$(task_of "$bid")
      if ! dispatchable "$bf"; then
        printf '%s skipped %s\n' "$bid" "$root/$key/$bid"
        printf 'session-monitor: %s is %s and owned by %s; only a ready, unowned block or a tests_ready one armed with phase: implement is dispatched\n' \
          "$bid" "$(field "$bf" status)" "$(field "$bf" owner)" >&2
        continue
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$bid" "$root/$key/$bid" "$model" "$bid" \
        "$(claim_prompt "$bid")You are $agent. Read $brief and do exactly what it says." >> "$units"
    done
  elif [ -n "$(blocks_of "$parent")" ]; then
    echo "nothing to dispatch: every block of $parent is claimed, in review or done"
    exit 0
  else
    # a leaf task, the bugfix a single session solves: it is the unit, with its archetype skill as the prompt,
    # exactly as --all builds it
    pstatus=$(field "$ptask" status)
    cwd="$root/$key/$parent"
    if [ "$pstatus" != ready ] || ! unowned "$(field "$ptask" owner)"; then
      printf '%s skipped %s\n' "$parent" "$cwd"
      printf 'session-monitor: %s is %s and owned by %s; only a ready, unowned task is dispatched\n' \
        "$parent" "$pstatus" "$(field "$ptask" owner)" >&2
      exit 0
    fi
    unit_line "$ptask" "$parent" "$key" > "$units"
  fi
else
  for task in "$state"/repos/*/tasks/*.md; do
    [ -f "$task" ] || continue
    [ "$(field "$task" status)" = ready ] || continue
    unowned "$(field "$task" owner)" || continue
    unit_line "$task" "$(field "$task" id)" "$(basename -- "$(dirname -- "$(dirname -- "$task")")")"
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
while IFS='	' read -r id cwd model claimid prompt; do
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
  # the claim goes out before the session does, so no second dispatch sees the unit as ready; a dry run
  # changes nothing, so it claims nothing
  [ -n "$dry" ] || [ "$claimid" = - ] || claim "$claimid"
  label=$(sh "$bin/herdr-tabs.sh" name "$id" --state "$state")
  if [ "$mode" = manual ] || [ -n "$dry" ]; then
    printf '%s printed %s\n' "$id" "$cwd"
    printf '  cd %s && claude --model %s --name "%s" "%s"\n' "$cwd" "$model" "$label" "$prompt"
    continue
  fi
  # herdr agent names are [a-z][a-z0-9_-]{0,31} and unique among live agents
  name=$(printf '%s' "$id" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  # the tab belongs to the caller's own workspace, not to whatever another client has focused
  set -- tab create --cwd "$cwd" --label "$label" --no-focus
  [ -z "$workspace" ] || set -- "$@" --workspace "$workspace"
  created=$(herdr "$@" || :)
  pane=$(printf '%s' "$created" | json result.root_pane.pane_id)
  if [ -z "$pane" ]; then
    echo "session-monitor: herdr tab create gave no pane id for $id" >&2
    rc=2; continue
  fi
  sh "$bin/herdr-tabs.sh" record "$id" "$(printf '%s' "$created" | json result.tab.tab_id)" "$pane" --state "$state"
  if ! herdr agent start "$name" --kind claude --pane "$pane" -- --model "$model" --name "$label" >/dev/null; then
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
