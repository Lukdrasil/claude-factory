#!/bin/sh
# Dispatch from the main session: one interactive Claude session per unit of work, instead of a subagent in the
# coordinator's own context. With herdr each session gets its own tab in its own worktree; without herdr the
# same lines are printed for the human to run.
#
#   session-monitor.sh [--task <T-id> [--wave N] [--step <name>]] [--all] [--queue] [--step pass --scope
#                      <key>/<agent>] [--max N] [--workspace <id>] [--state <dir>] [--dry-run]
#
# Six modes:
#   --task T-id      one named task as a unit, and nothing else: the current wave of its blocks when it has any
#                    a dispatch may start (the plan of bin/spawn-plan.sh, less every block that is neither ready
#                    and unowned nor tests_ready with phase: implement armed, which is skipped), and otherwise
#                    the task itself when it is a ready, unowned leaf, with its archetype skill as the prompt and
#                    its brief, agent-brief.sh of its agent (rules, memory, the repo playbook), written to
#                    `<root>/<key>/.harness/<id>/brief.md` for it to read first.
#                    `--parent` is the old spelling of the same flag and still works.
#   --task T-id --step <name>
#                    one session for a parent-level step of `factory herd`: triage, chart, grill, plan-check,
#                    decompose or lead. A step runs in the registered clone, or in the session worktree once
#                    there is one. chart prompts `/claude-factory:wayfinder chart <R-id> <T-id>` with the
#                    task's `request:`. lead (agent-org plan 3.1) runs in its own herdr workspace labelled
#                    `<T-id> <key>` with the parent worktree as its cwd, which worktree-add.sh makes first when
#                    there is none yet, and prompts `/claude-factory:factory herd <T-id>`, preceded by `Read
#                    <state>/repos/<key>/agents/repo-lead/playbook.md first.` when the repo has that playbook.
#   --step pass --scope <key>/<agent>
#                    the daily memory pass of one repo agent (plan 3.8), unit `pass-<key>-<agent>`, in the state
#                    clone, prompting `/claude-factory:memory-daily <key>/<agent>`.
#   --queue          the lines of queue-next.sh (`<T-id> <key> <priority> <request>`, in dispatch order) from the
#                    top, each as --step lead, while `capacity.sh count sessions` leaves two slots free and
#                    `count repo-lead` one; the first line that does not fit ends the take.
#   --all            every task with `status: ready` and no owner, across the state repo, and one
#                    `mr-watch.sh <T-id> --once` pass per parent with an open block MR, whose event lines are
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
# focused. A lead is the one unit that gets a workspace of its own instead of a tab.
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
# not a failure: the session still starts, and its own first heartbeat is the claim that counts. A step, a lead
# and a pass claim nothing: the lead claims its parent itself, as its own first step.
#
# Every unit has a role: the step for a step, `repo-lead` for a lead, `pass` for a pass, and the agent of
# model-for.sh --agent for a block or a leaf. A herdr spawn passes `--env FACTORY_ROLE=<role> --env
# FACTORY_UNIT=<unit> --env CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` on its create, and a printed line carries the same
# three as a prefix of its `claude` command. FACTORY_CLAUDE_ARGS, when set, is appended word by word to every
# `claude` command line, spawned or printed (a test factory loads the plugin under test with `--plugin-dir` and its
# own WORK_DIR with `--settings`). The herdr agent name is plan 3.6's `<role>_<task id lowercased>`,
# `lead` for a lead, the leading `t-` dropped for an alias id and kept for a legacy one (`lead_ecs-12`,
# `implementer_t-264-02`), and `pass_<alias>-<agent>` for a pass, cut at 31 characters.
#
# Capacity (plan 3.3): the `sessions` and `repo-lead` counts of capacity.sh are read once per pass, and every
# unit the pass sends out, printed ones included, counts against them. A unit needs one free session slot, a
# lead two plus a free repo-lead slot; a unit that does not fit is printed `skipped` with `capacity: sessions
# full` (or `repo-lead full`) on stderr, and the caller retries on its next pass. A herdr spawn acquires
# `sessions <unit>`, plus `repo-lead <T-id>` for a lead and `<role> <unit>` for a block, before it creates the
# tab; a create or an agent start that fails releases them again. herd-watch.sh releases them when the unit ends.
#
# Every unit carries the session name `<emoji> <repo> <id>` of `herdr-tabs.sh name`: the tab label and the
# `claude --name` of a herdr spawn, and the `--name` of a printed manual line; a pass, which has no task, is
# named by its unit. Each tab a herdr spawn creates is appended to the tab record through `herdr-tabs.sh
# record`, `<unit> <tab_id> <pane_id>` in `<root>/<key>/.harness/<T-id>/herdr-tabs`; a pass has no record. A tab
# with no tab id, or a record that fails, is one line on stderr and the unit still starts.
#
# The agent starts with `herdr agent start --timeout 120000`. A start that answers `agent_not_ready` stopped at a
# dialog (plan 3.7): the monitor waits for the agent with `herdr agent wait <name> --until idle --until done
# --timeout 120000` and then prompts; a wait that times out leaves the session up, unprompted, exit 2.
#
# A herdr spawn first runs `herdr-tabs.sh close` over the unit and the step units of its T-id, before the
# claim: a recorded tab whose agent is idle closes, and a unit whose own tab is kept (focused, the caller's,
# or an agent at work) is printed `skipped` and not started. `--all` first runs `herdr-tabs.sh sweep` over
# every T-id with a tab record, which closes the tabs of units at `done` or `closed` and prints one
# `<unit> closed <tab_id>` or `<unit> kept <tab_id> <reason>` line on stderr per recorded tab it tried.
#
# Every pass that is not a dry run ends with `state-push.sh` (plan 3.5): the writers commit locally, and the
# pass carries their commits to the state root. A push that does not land is a line on stderr; the commits stay
# for the next pass.
#
# One line per unit on stdout: `<id> <state-word> <cwd>`, where the state word is `spawned`, `printed` or
# `skipped`. Exit 0 when every unit was dispatched or printed, 1 with the reason on stderr when the state or
# the task cannot be resolved and when no mode was named, 2 when herdr was asked for and a spawn failed.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'session-monitor: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

parent='' wave='' state='' dry='' max=5 step='' spawn='' all='' queue='' scope='' workspace=${HERDR_WORKSPACE_ID:-}
while [ $# -gt 0 ]; do
  case "$1" in
    # --parent is the old spelling of --task, kept so `factory herd` and every recipe that names it keep working
    --task|--parent) [ $# -ge 2 ] || die "$1 needs a value"; parent=$2; shift 2 ;;
    --all) all=1; shift ;;
    --queue) queue=1; shift ;;
    --wave) [ $# -ge 2 ] || die "--wave needs a value"; wave=$2; shift 2 ;;
    --step) [ $# -ge 2 ] || die "--step needs a value"; step=$2; shift 2 ;;
    --scope) [ $# -ge 2 ] || die "--scope needs a value"; scope=$2; shift 2 ;;
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
  ''|triage|chart|grill|plan-check|decompose|lead|pass) ;;
  *) die "--step takes triage, chart, grill, plan-check, decompose, lead or pass, not '$step'" ;;
esac
if [ "$step" = pass ]; then
  [ -z "$parent" ] || die "--step pass is a repo agent's memory pass, not a step of a task; drop --task"
  case "$scope" in
    */*/*|/*|*/) die "--scope takes <key>/<agent>, not '$scope'" ;;
    */*) ;;
    *) die "--step pass needs --scope <key>/<agent>" ;;
  esac
else
  [ -z "$scope" ] || die "--scope belongs to --step pass"
  [ -z "$step" ] || [ -n "$parent" ] || die "--step needs the --task it is a step of"
fi
[ -z "$parent" ] || [ -z "$all" ] || die "--task names one task and --all takes every ready one; pass one of them"
[ -z "$queue" ] || [ -z "$parent$all$step" ] || die "--queue takes its leads from queue-next.sh; pass no --task, --all or --step with it"

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

lower() { printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'; }
# plan 3.6: `<role>_<task id lowercased>`, the leading t- dropped for an alias id (lead_ecs-12) and kept for a
# legacy one (lead_t-264). herdr names are [a-z][a-z0-9_-]{0,31} and unique among live agents; the plan keeps
# them to 31 characters.
agent_name() { # <role> <task id>
  an_t=$(lower "$2")
  case "$an_t" in t-[0-9]*) ;; *) an_t=${an_t#t-} ;; esac
  printf '%s_%s' "$1" "$an_t" | cut -c1-31
}

# the goal line of a task: the first non-empty line under its first heading, the shape every task template
# writes and the one factory-list.sh reads too
goal_of() { awk 'h && NF { print; exit } /^#/ { h = 1 }' "$1"; }

unowned() { case "$1" in ''|null|none|'~') return 0 ;; esac; return 1; }

# the blocks of a parent, and the ones a dispatch could still pick up
blocks_of() { # <T-id>
  task_files | while IFS= read -r t; do
    b=$(field "$t" id)
    if is_block_of "$1" "$b"; then printf '%s\n' "$b"; fi
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
dispatchable_blocks_of() { # <T-id>
  task_files | while IFS= read -r t; do
    b=$(field "$t" id)
    is_block_of "$1" "$b" || continue
    dispatchable "$t" || continue
    printf '%s\n' "$b"
  done
}

# The work list is `<id>\t<cwd>\t<model>\t<claim id>\t<role>\t<herdr name>\t<prompt>`, one unit per line; the
# claim id is the task the dispatch claims before it starts the session, and `-` for a unit that claims nothing
# (a step, a lead, a pass). A literal `-`, not an empty field: `read` with IFS=tab folds two tabs into one, and
# the prompt would land in the wrong field.
unit() { # <id> <cwd> <model> <claim id> <role> <herdr name> <prompt>
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

# one unit of work out of one task file: the archetype skill is the prompt, the way the batch mode has always
# built it, with the claim command in front of it and the brief of its agent to read first. A dry run writes
# no brief; one agent-brief.sh cannot write leaves the prompt without it.
unit_line() { # <task file> <id> <repo key>
  ul_arch=$(field "$1" archetype) ul_tier=$(field "$1" tier) ul_cx=$(field "$1" complexity)
  ul_phase=$(field "$1" phase)
  ul_model=$(sh "$bin/model-for.sh" "$ul_arch" "$ul_tier" "$ul_phase" 1 "$ul_cx" 2>/dev/null || echo opus)
  ul_agent=$(sh "$bin/model-for.sh" --agent "$ul_arch" "$ul_tier" "${ul_phase:-implement}" 0 "$ul_cx" 2>/dev/null \
    || echo implementer)
  ul_brief="$root/$3/.harness/$2/brief.md"
  ul_read="Read $ul_brief first, your rules, memory and the $3 playbook; then "
  if [ -z "$dry" ]; then
    mkdir -p "$(dirname -- "$ul_brief")" &&
      sh "$bin/agent-brief.sh" "$ul_agent" --key "$3" --state "$state" > "$ul_brief" </dev/null ||
      { rm -f "$ul_brief"; ul_read=''; echo "session-monitor: agent-brief.sh wrote no brief for $2" >&2; }
  fi
  unit "$2" "$root/$3/$2" "$ul_model" "$2" "$ul_agent" "$(agent_name "$ul_agent" "$2")" \
    "$(claim_prompt "$2")$ul_read/claude-factory:block-$ul_arch $1"
}

# one parent-level step of a task; a step runs before the session worktree exists, so the cwd is the
# registered clone and the worktree only once step 10 has made one. A lead always runs in the worktree.
step_unit() { # <T-id> <step>
  su_task=$(task_of "$1" || :)
  [ -n "$su_task" ] && [ -f "$su_task" ] || die "no task file with 'id: $1'"
  su_key=$(field "$su_task" repo)
  [ -n "$su_key" ] || die "task $1 has no 'repo:' field"
  su_cwd="$root/$su_key/$1"
  if [ "$2" != lead ]; then
    [ -e "$su_cwd/.git" ] || su_cwd=$(clone_path "$su_key")
    [ -n "$su_cwd" ] || die "repo '$su_key' has no path: in repos.yml and $1 has no worktree, so there is nowhere to run $2"
  fi
  su_role=$2 su_model=opus
  case "$2" in
    triage)
      su_model=$(sh "$bin/model-for.sh" triage "$(field "$su_task" tier)" '' 0 \
        "$(field "$su_task" complexity)" 2>/dev/null || echo sonnet)
      su_prompt="Triage $1. Read $(dirname -- "$bin")/skills/_shared/investigate.md and $su_task, gather the recon it asks for, write ## Context into the task, set tier: and archetype:, and report with $bin/state-report.sh --task $1 --no-status." ;;
    chart)
      su_req=$(field "$su_task" request)
      case "$su_req" in ''|null) die "$1 has no request:, so there is no request map to chart" ;; esac
      su_prompt="/claude-factory:wayfinder chart $su_req $1" ;;
    grill) su_prompt="/claude-factory:grill $su_task" ;;
    plan-check) su_prompt="/claude-factory:architect-review plan-check $su_task" ;;
    decompose) su_prompt="/claude-factory:decompose $su_task" ;;
    lead)
      su_role=repo-lead
      su_prompt="/claude-factory:factory herd $1"
      su_pb="$state/repos/$su_key/agents/repo-lead/playbook.md"
      [ ! -f "$su_pb" ] || su_prompt="Read $su_pb first. $su_prompt" ;;
  esac
  unit "$1-$2" "$su_cwd" "$su_model" - "$su_role" "$(agent_name "$2" "$1")" "$su_prompt"
}

# the daily memory pass of one repo agent (plan 3.8): it reads and writes the state clone, so it runs there
pass_unit() { # <key>/<agent>
  pu_key=${1%%/*} pu_agent=${1#*/}
  [ -d "$state/repos/$pu_key" ] || die "no repo '$pu_key' under $state/repos"
  pu_alias=$(repo_alias "$pu_key" || :)
  [ -n "$pu_alias" ] || pu_alias=$pu_key
  unit "pass-$pu_key-$pu_agent" "$state" opus - pass \
    "$(printf 'pass_%s-%s' "$(lower "$pu_alias")" "$pu_agent" | cut -c1-31)" "/claude-factory:memory-daily $1"
}

# the ready, unowned tasks of the whole state repo, one `<id> <repo> <status> <archetype> <goal>` per line
list_ready() {
  task_files | while IFS= read -r t; do
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

# plan 3.5: the writers commit locally and every pass carries their commits to the state root; a dry run
# changed nothing, so it pushes nothing, and a push that does not land stays for the next pass
end_pass() { # <exit code>
  if [ -z "$dry" ] && ! sh "$bin/state-push.sh" --state "$state" >/dev/null 2>&1 </dev/null; then
    echo "session-monitor: state-push.sh did not land; the commits stay in $state for the next pass" >&2
  fi
  exit "$1"
}

# no mode at all is not a batch: it is the question "which task", and the answer is a list to choose from
if [ -z "$parent$all$queue$step" ]; then
  list_ready
  echo "session-monitor: name one task: --task T-NNN (--all dispatches every ready task, and only a user who asked for that by name gets it)" >&2
  exit 1
fi

# --- the work list -------------------------------------------------------------------------------------------
units=$(mktemp)
trap 'rm -f "$units"' EXIT

if [ "$step" = pass ]; then
  pass_unit "$scope" > "$units"
elif [ -n "$queue" ]; then
  [ -f "$bin/queue-next.sh" ] || die "bin/queue-next.sh is not there, so there is no queue to take from"
  qlines=$(sh "$bin/queue-next.sh" --max "$max" --state "$state") || die "queue-next.sh refused the queue"
  # a line whose task does not resolve costs its own lead, not the rest of the queue
  printf '%s\n' "$qlines" | while IFS=' ' read -r qid qrest; do
    [ -n "$qid" ] || continue
    ( step_unit "$qid" lead ) || :
  done > "$units"
elif [ -n "$parent" ]; then
  is_task_id "$parent" || die "'$parent' is not a task id"
  ptask=$(task_of "$parent" || :)
  [ -n "${ptask:-}" ] && [ -f "$ptask" ] || die "no task file with 'id: $parent'"
  key=$(field "$ptask" repo)
  [ -n "$key" ] || die "task $parent has no 'repo:' field"
  if [ -n "$step" ]; then
    step_unit "$parent" "$step" > "$units"
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
      unit "$bid" "$root/$key/$bid" "$model" "$bid" "$agent" "$(agent_name "$agent" "$bid")" \
        "$(claim_prompt "$bid")You are $agent. Read $brief and do exactly what it says." >> "$units"
    done
  elif [ -n "$(blocks_of "$parent")" ]; then
    echo "nothing to dispatch: every block of $parent is claimed, in review or done"
    end_pass 0
  else
    # a leaf task, the bugfix a single session solves: it is the unit, with its archetype skill as the prompt,
    # exactly as --all builds it
    pstatus=$(field "$ptask" status)
    cwd="$root/$key/$parent"
    if [ "$pstatus" != ready ] || ! unowned "$(field "$ptask" owner)"; then
      printf '%s skipped %s\n' "$parent" "$cwd"
      printf 'session-monitor: %s is %s and owned by %s; only a ready, unowned task is dispatched\n' \
        "$parent" "$pstatus" "$(field "$ptask" owner)" >&2
      end_pass 0
    fi
    unit_line "$ptask" "$parent" "$key" > "$units"
  fi
else
  if [ "$mode" = herdr ] && [ -z "$dry" ]; then
    for rec in "$root"/*/.harness/T-*/herdr-tabs; do
      [ -f "$rec" ] || continue
      p=$(basename -- "$(dirname -- "$rec")")
      is_parent_id "$p" || continue
      sh "$bin/herdr-tabs.sh" sweep "$p" --state "$state" >&2 || :
    done
  fi
  task_files | while IFS= read -r task; do
    [ "$(field "$task" status)" = ready ] || continue
    unowned "$(field "$task" owner)" || continue
    unit_line "$task" "$(field "$task" id)" "$(basename -- "$(dirname -- "$(dirname -- "$task")")")"
  done > "$units"
fi

# --- the open block MRs --------------------------------------------------------------------------------------
# why: T-164, the solve session that opened the block MRs may be over, so the standalone monitor is what turns
# why: a merge on the forge into state
if [ -n "$all" ]; then
  parents=$(
    task_files | while IFS= read -r task; do
      [ "$(field "$task" status)" = review ] || continue
      case "$(field "$task" mr_url)" in ''|null) continue ;; esac
      bid=$(field "$task" id)
      if is_block_id "$bid"; then printf '%s\n' "${bid%-*}"; fi
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

[ -s "$units" ] || { echo "nothing to dispatch"; end_pass 0; }

# --- capacity ------------------------------------------------------------------------------------------------
# the `sessions` and `repo-lead` counts, read once: every unit this pass sends out counts against them, a
# printed one included, so a dry run takes what the real pass would take. A cap of `-` is none.
cap_count() { sh "$bin/capacity.sh" count "$1" --state "$state" 2>/dev/null </dev/null || echo 0/-; }
s_line=$(cap_count sessions) l_line=$(cap_count repo-lead)
s_used=${s_line%/*} s_cap=${s_line#*/} l_used=${l_line%/*} l_cap=${l_line#*/}
room() { # <session slots needed> <repo-lead slots needed>: the reason on stdout when they are not free
  if [ "$s_cap" != - ] && [ $((s_cap - s_used)) -lt "$1" ]; then
    printf 'capacity: sessions full (%s/%s, this unit needs %s free)' "$s_used" "$s_cap" "$1"; return 1
  fi
  if [ "$2" -gt 0 ] && [ "$l_cap" != - ] && [ $((l_cap - l_used)) -lt "$2" ]; then
    printf 'capacity: repo-lead full (%s/%s)' "$l_used" "$l_cap"; return 1
  fi
}
lease() { # <id> <role>
  sh "$bin/capacity.sh" acquire sessions "$1" --state "$state" </dev/null || :
  if [ "$2" = repo-lead ]; then
    sh "$bin/capacity.sh" acquire repo-lead "${1%-lead}" --state "$state" </dev/null || :
  elif is_block_id "$1"; then
    sh "$bin/capacity.sh" acquire "$2" "$1" --state "$state" </dev/null || :
  fi
}
unlease() { sh "$bin/capacity.sh" release "$1" --state "$state" </dev/null || :; }

# --- dispatch ------------------------------------------------------------------------------------------------
rc=0 n=0
while IFS='	' read -r id cwd model claimid role name prompt; do
  n=$((n + 1))
  if [ "$n" -gt "$max" ]; then
    printf '%s skipped %s\n' "$id" "$cwd"
    continue
  fi
  need=1 leads=0
  [ "$role" != repo-lead ] || need=2 leads=1
  if ! why=$(room "$need" "$leads"); then
    if [ -n "$queue" ]; then
      printf 'session-monitor: %s; the queue waits from %s on\n' "$why" "$id" >&2
      break
    fi
    printf '%s skipped %s\n' "$id" "$cwd"
    printf 'session-monitor: %s: %s\n' "$id" "$why" >&2
    continue
  fi
  # the lead lives in the parent worktree (plan 3.1); when the queue starts it, step 10 of the herd has not made
  # it yet, so the dispatch does, and a lead whose worktree cannot be made does not start
  wt=''
  if [ "$role" = repo-lead ] && [ ! -e "$cwd/.git" ]; then
    if [ -n "$dry" ]; then
      wt="  sh $bin/worktree-add.sh ${id%-lead} --state $state"
    elif ! sh "$bin/worktree-add.sh" "${id%-lead}" --state "$state" >/dev/null </dev/null; then
      printf '%s skipped %s\n' "$id" "$cwd"
      echo "session-monitor: worktree-add.sh made no worktree for ${id%-lead}, so its lead has nowhere to run" >&2
      continue
    fi
  fi
  if [ -z "$wt" ] && [ ! -d "$cwd" ]; then
    printf '%s skipped %s\n' "$id" "$cwd"
    echo "session-monitor: no worktree at $cwd; run worktree-add.sh $id first" >&2
    continue
  fi
  # the unit's own earlier tab and the step tabs of its parent close before it starts again, and before the
  # claim, so a unit whose tab is still at work is neither claimed nor started twice; a pass has no record
  if [ "$mode" = herdr ] && [ -z "$dry" ] && [ "$role" != pass ]; then
    t=${id%%-[a-z]*}
    if is_block_id "$t"; then t=${t%-*}; fi
    kept=$(sh "$bin/herdr-tabs.sh" close "$id" "$t-triage" "$t-chart" "$t-grill" "$t-plan-check" "$t-decompose" \
      --state "$state" | awk -v u="$id" '$1 == u && $2 == "kept"')
    if [ -n "$kept" ]; then
      printf '%s skipped %s\n' "$id" "$cwd"
      printf 'session-monitor: %s has a tab herdr-tabs.sh kept: %s\n' "$id" "$kept" >&2
      continue
    fi
  fi
  # the claim goes out before the session does, so no second dispatch sees the unit as ready; a dry run
  # changes nothing, so it claims nothing
  [ -n "$dry" ] || [ "$claimid" = - ] || claim "$claimid"
  s_used=$((s_used + 1)) l_used=$((l_used + leads))
  if [ "$role" = pass ]; then
    label=$id
  else
    label=$(sh "$bin/herdr-tabs.sh" name "$id" --state "$state")
  fi
  if [ "$mode" = manual ] || [ -n "$dry" ]; then
    printf '%s printed %s\n' "$id" "$cwd"
    [ -z "$wt" ] || printf '%s\n' "$wt"
    printf '  cd %s && FACTORY_ROLE=%s FACTORY_UNIT=%s CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 claude --model %s --name "%s"%s "%s"\n' \
      "$cwd" "$role" "$id" "$model" "$label" "${FACTORY_CLAUDE_ARGS:+ $FACTORY_CLAUDE_ARGS}" "$prompt"
    continue
  fi
  lease "$id" "$role"
  if [ "$role" = repo-lead ]; then
    # plan 3.1: one workspace per lead, so the block tabs it opens land in its own $HERDR_WORKSPACE_ID
    set -- workspace create --cwd "$cwd" --label "${id%-lead} $(basename -- "$(dirname -- "$cwd")")" --no-focus
  else
    # the tab belongs to the caller's own workspace, not to whatever another client has focused
    set -- tab create --cwd "$cwd" --label "$label" --no-focus
    [ -z "$workspace" ] || set -- "$@" --workspace "$workspace"
  fi
  set -- "$@" --env "FACTORY_ROLE=$role" --env "FACTORY_UNIT=$id" --env CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
  created=$(herdr "$@" || :)
  pane=$(printf '%s' "$created" | json result.root_pane.pane_id)
  if [ -z "$pane" ]; then
    echo "session-monitor: herdr $1 create gave no pane id for $id" >&2
    unlease "$id"
    rc=2; continue
  fi
  tab=$(printf '%s' "$created" | json result.tab.tab_id)
  if [ "$role" != pass ] && { [ -z "$tab" ] || ! sh "$bin/herdr-tabs.sh" record "$id" "$tab" "$pane" --state "$state"; }; then
    echo "session-monitor: no tab record for $id, so its tab is not closed by the scripts" >&2
  fi
  if ! err=$(herdr agent start "$name" --kind claude --pane "$pane" --timeout 120000 -- --model "$model" --name "$label" ${FACTORY_CLAUDE_ARGS:-} 2>&1 >/dev/null); then
    case "$err" in
      *agent_not_ready*)
        # plan 3.7: a dialog at startup (trust, login) answers agent_not_ready at once and the name is already
        # usable, so the prompt waits for the agent to settle
        if ! herdr agent wait "$name" --until idle --until done --timeout 120000 >/dev/null 2>&1; then
          echo "session-monitor: $id is up but still at a dialog after 120 s; answer it in its tab and prompt it by hand" >&2
          rc=2; continue
        fi ;;
      *)
        echo "session-monitor: herdr agent start failed for $id in pane $pane" >&2
        unlease "$id"
        rc=2; continue ;;
    esac
  fi
  if ! herdr agent prompt "$name" "$prompt" >/dev/null; then
    echo "session-monitor: herdr agent prompt failed for $id; the session is up, prompt it by hand" >&2
    rc=2; continue
  fi
  printf '%s spawned %s\n' "$id" "$cwd"
done < "$units"
end_pass $rc
