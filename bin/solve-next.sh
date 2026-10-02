#!/bin/sh
# The next step of `factory solve` for one parent task (T-154), worked out from state instead of carried in the
# coordinator's context: the parent task file, its T-NNN-NN blocks and their statuses, the worktrees under
# <root>/<key>/, the architect verdict file and the progress file.
#
#   solve-next.sh <T-NNN> [--state <dir>] [--herd|--auto|--autonom]
#                            the state clone; default $WORK_DIR/state, else resolved from the cwd
#                            --herd prints the steps of `factory herd` (skills/factory/references/herd.md): a
#                            step that writes goes out as an interactive session through session-monitor.sh,
#                            one per parent-level step (3 to 6) and one per block of a wave (11), and a block
#                            whose session still works is a wait on herd-watch.sh; every gate stays yours
#                            --auto prints the steps of `factory auto` (skills/factory/references/auto.md): the
#                            herd, with step 4a in front of the grill, two solution sessions and the human's
#                            pick, the one gate the human answers; from there the grill and decompose go out
#                            with --auto, the approval, a blocked block and a review round take the
#                            recommendation (skills/_shared/auto-decision.md), step 12 runs the toolset's e2e
#                            when it binds one, and the task MR carries the plan's decisions (mr-open.sh
#                            --decisions). It needs a `crap` row in the toolset: the auto lane holds every
#                            changed method to the crap threshold through block-verify.sh
#                            --autonom is --auto with the human's pick taken by the monitor itself, after an
#                            analysis of both solutions, and the grill and decompose dispatched with
#                            --autonom, so a decision with no recommendation is analysed and taken by the
#                            session (the autonomous section of skills/_shared/auto-decision.md)
#
# T-164: a block ends in its own MR into the branch of the block it was cut from, so step 11 runs until every
# block is `done`, which is what mr-watch.sh writes when the developer merges that MR on the forge. A block in
# `review` with an `mr_url` is waiting for the developer, so step 11 steps over it to the next block that still
# needs work and only prints the reminder with the open MRs when every remaining block is one of those; a block
# in `changes_requested` is a fix round. That holds for a task already stacked (a block whose progress file
# records `base: block/...`). Every other task cuts its blocks from the work branch, one wave at a time, and puts
# each one up through block-verify.sh, the code-reviewer and the architecture-auditor, then block-mr.sh: a block
# in `review` with an `mr_url` does not hold the blocks of its own wave, and before a block of a later wave is
# cut, step 11 is the automatic merge of the waiting block MRs through block-mr-merge.sh, a high-risk one too.
# Step 14 is then the task MR the human reviews and merges.
#
# It prints exactly one step of skills/factory/references/solve.md: a `## Step <n> ...` heading, one line
# beginning `Completion:`, and under `Commands:` the commands to run, two spaces in front of each. The work
# root is the parent directory of the state clone, so every path printed is absolute: `<root>/<key>/T-NNN` is
# the session worktree, `<root>/<key>/T-NNN-NN` a block worktree, `<root>/<key>/.harness/T-NNN` the scratch
# directory of the run. Every step opens with state-push.sh, so the commits the writers made locally reach the
# state root once per step.
#
# The state a step is read off, in the order the steps are tried: no `tier` is step 3, and so is no plan-ready
# file on a feature, bugfix or refactor with no `## Related issues`; no plan-ready file is step 4 (the plan-ready file is the one whose
# frontmatter says `task: <id>`, else the one the parent's ## Context names), no blocks
# and a product repo with docs/architecture/ and no verdict is step 5, no blocks is step 6, blocks with no
# wave plan in the progress file is step 8, a parent that is not `in_progress` is step 9, no session worktree
# is step 10, a block that is not `done` is step 11, every block done is step 12, no `## Duplication` in the
# progress file is step 12b, no `## Review` in it is step 13, no `mr_url` is step 14, a parent that is not
# `review` is step 15, and step 16 last. Step 12b carries a letter rather than a number of its own because it
# is a gate inside the quality stage, not a stage the other sixteen renumber around (T-163).
#
# Exit 0 with the step on stdout. Exit 1 with the reason on stderr when no parent id is given, when the id is
# not of the shape T-NNN, or when it resolves to no task file.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'solve-next: %s\n' "$1" >&2; exit 1; }

bin=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
plugin=$(dirname -- "$bin")

id='' state='' herd='' auto='' autonom=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --herd) herd=1; shift ;;
    # the auto lane is the herd with its own step 4a and its decisions taken by recommendation; the autonomous
    # lane is the auto lane with the pick and the undecidable questions taken by the sessions after an analysis
    --auto) herd=1; auto=1; shift ;;
    --autonom) herd=1; auto=1; autonom=1; shift ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one parent id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: solve-next.sh <T-NNN> [--state <dir>] [--herd|--auto|--autonom]"
is_parent_id "$id" || die "'$id' is not a parent task id of the shape T-NNN"

# see: block-brief.sh, the same resolution: $WORK_DIR/state when it is a clone, else what the cwd resolves to,
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
[ -n "$task" ] || die "$id resolves to no task file under $state/repos/*/tasks"

key=${task#"$state/repos/"}
key=${key%%/*}
case "$state" in */state) root=${state%/state} ;; *) root=$(dirname -- "$state") ;; esac
own="$root/$key"
worktree="$own/$id"
harness="$own/.harness/$id"
progress="$state/repos/$key/progress/$id.md"

# one flat frontmatter field of a task file, with `null` answering as absent the way the templates write it
fm() { # <file> <key>
  v=$(awk -v k="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    { c = index($0, ":"); if (c == 0 || $0 ~ /^[ \t]/) next
      if (substr($0, 1, c - 1) != k) next
      v = substr($0, c + 1); sub(/ #.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1")
  [ "$v" = null ] || printf '%s' "$v"
}

# the `path:` of a repo in the state clone's own repos.yml (ADR-0013 revision); nothing when it is not registered
clone_path() { # <key>
  [ -f "$state/repos.yml" ] || return 0
  awk -v want="$1" '
    /^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k) }
    index($0, "path:") && k == want {
      p = $0; sub(/.*path:[ \t]*/, "", p); sub(/[ \t]*[,}].*$/, "", p); sub(/[ \t]+#.*$/, "", p)
      gsub(/^["'"'"']|["'"'"']$/, "", p); if (p != "") { print p; exit }
    }' "$state/repos.yml"
}

# the parent's base: its `base_branch:`, else the repo's `default_branch:` in repos.yml, main when neither names one
base_branch() {
  b=$(task_base "$task" "$key")
  [ -n "$b" ] || b=main
  printf '%s' "$b"
}

emit() { # <heading> <completion line>
  printf '## %s\n' "$1"
  printf 'Completion: %s\n' "$2"
  printf 'Commands:\n'
  printf '  %s\n' "$bin/state-push.sh --state $state"
}
cmd() { printf '  %s\n' "$1"; }
# a parent-level step of the herd, one session of session-monitor.sh; the watcher reports it
# the watcher is armed once per herd through the Monitor tool, never run as a command of its own: it never ends
watch_line() { cmd "Monitor tool, armed once per herd: $bin/herd-watch.sh $id --interval 60 --state $state"; }
# a parent-level step of the herd, one session of session-monitor.sh; a step whose session still runs in its tab
# is a wait, since a second dispatch would close that tab and lose the conversation a grill holds with the human.
# The auto lane passes --auto on to the grill and decompose dispatch, and the watch line follows the caller's
# last dispatch, since step 4a dispatches two sessions under one watcher
auto_arg=''
[ -z "$auto" ] || auto_arg=' --auto'
[ -z "$autonom" ] || auto_arg=' --autonom'
dispatch_step() { # <step>
  ds_agent=$(sh "$bin/herdr-tabs.sh" agents "$id" --state "$state" 2>/dev/null | awk -v u="$id-$1" '$1 == u { print $2; exit }')
  ds_auto=''
  case "$1" in grill|plan-check|decompose) ds_auto=$auto_arg ;; esac
  case "$ds_agent" in
    ''|gone|closed) cmd "$bin/session-monitor.sh --task $id --step $1$ds_auto --state $state" ;;
    idle|done)
      # why: an idle step may be a round waiting on its human, or a turn that ended short of the step; only the
      # why: second is started again, after one prompt, and session-monitor.sh keeps a focused or busy tab
      cmd "# $id-$1 is idle in its tab: its human may be answering it there. Once its turn ended short of the Completion above, prompt it once (herdr agent prompt $1_<tail> ...), and if that ends short too, start it again:"
      cmd "$bin/session-monitor.sh --task $id --step $1$ds_auto --state $state" ;;
    unknown) cmd "# herdr does not answer, so $id-$1 cannot be read: run factory doctor for the herdr server, then this step again" ;;
    *) cmd "# $id-$1 runs in its tab (agent $ds_agent); wait on the watcher, and its human answers it there" ;;
  esac
}

tier=$(fm "$task" tier)
archetype=$(fm "$task" archetype)
complexity=$(fm "$task" complexity)
[ -n "$complexity" ] || complexity=medium
status=$(fm "$task" status)
branch=$(fm "$task" branch)
mr_url=$(fm "$task" mr_url)

triage_step() {
  emit "Step 3 of 16: triage $id" "tier and archetype are set on $id and ## Related issues is written for a feature, bugfix or refactor."
  if [ -n "$herd" ]; then dispatch_step triage; watch_line; exit 0; fi
  cmd "cat $task"
  cmd "cat $plugin/skills/_shared/investigate.md"
  cmd "$bin/state-report.sh --task $id --no-status --message 'chore($id): triaged'"
  exit 0
}
[ -n "$tier" ] && [ -n "$archetype" ] || triage_step

slug=''
for f in "$state/repos/$key/plans/"*-plan-ready.md; do
  [ -f "$f" ] && [ "$(fm "$f" task)" = "$id" ] || continue
  slug=${f##*/}; slug=${slug%-plan-ready.md}
  break
done
[ -n "$slug" ] || slug=$(grep -oE 'plans/[A-Za-z0-9_.-]+-plan-ready\.md' "$task" 2>/dev/null | head -n1 | sed 's|^plans/||; s|-plan-ready\.md$||' || :)
plan="$state/repos/$key/plans/$slug-plan-ready.md"

# why: task-new.sh requires tier: of every draft, so before the plan triage is done only once investigate.md
# why: step 4 has written ## Related issues (feature, bugfix and refactor only)
triaged() {
  case "$archetype" in feature|bugfix|refactor) grep -q '^## Related issues[[:space:]]*$' "$task" ;; esac
}

# step 4a of the auto lane (skills/factory/references/auto.md): two solution sessions, then the human's pick,
# written as `## Solution` into the task; the one gate the human answers in that lane
toolset="$state/repos/$key/toolset.md"
# see: toolset_binding of lib-tasks.sh, the reader block-verify.sh runs the row through, so a row it would run
# see: is a row this lane accepts, and an empty cell is none for both
binds() { [ -n "$(toolset_binding "$toolset" "$1")" ]; }
# a solution file counts once its session committed it in the state clone: a file on disk may be a draft of
# a session still writing, or of one that died mid-write; a state directory that is no git clone (a test
# fixture) falls back to the file
written() { # <file under the state clone>
  [ -f "$1" ] || return 1
  git -C "$state" rev-parse --git-dir >/dev/null 2>&1 || return 0
  [ -n "$(git -C "$state" log -1 --format=%h -- "${1#"$state/"}" 2>/dev/null)" ]
}
sol_open="$state/repos/$key/research/$id-solution-open.md"
sol_min="$state/repos/$key/research/$id-solution-min.md"
# the pick the lane wrote: a `## Solution` heading with the `- view:` line under it, so a heading an issue body
# carried into the task is not read as a human's consent
# why: an issue body may carry its own `## Solution` heading above the lane's, so every such section is read
picked() { awk '/^## Solution[[:space:]]*$/ { f = 1; next } f && /^#/ { f = 0 } f && /^- view:/ { ok = 1 } END { exit !ok }' "$task"; }
auto_solutions_step() {
  ! picked || return 0
  # why: the lane promises every changed method at or under the crap threshold, and block-verify.sh can only
  # why: hold that with a crap row; without one the gate reads `not bound` and the promise is empty
  ts_stack=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit }
    /^stack:[[:space:]]*/ { sub(/^stack:[[:space:]]*/, ""); sub(/[[:space:]].*$/, ""); print; exit }' "$toolset" 2>/dev/null)
  if [ "$ts_stack" = dotnet ] && binds coverage && ! grep -E '^\|[[:space:]]*`?coverage' "$toolset" | grep -q Cobertura; then
    # why: a row seeded before 0.19 wrote no Cobertura report, so crap read nothing and every block went red
    emit "Step 4a of 16: the coverage row of $key writes no Cobertura report" "the coverage row of $toolset carries Cobertura in its -reporttypes (the plugin's toolsets/dotnet.md shows the row), so the crap run of block-verify.sh has a report to read; factory doctor names it too."
    cmd "cat $toolset"
    cmd "$bin/factory-doctor.sh --root $root"
    exit 0
  fi
  if ! binds crap; then
    emit "Step 4a of 16: the toolset of $key binds no crap" "$toolset has a \`crap <scope>\` row (and a \`coverage\` row it reads), so block-verify.sh holds every changed method to the crap threshold; factory doctor names the tools it needs. Add an \`e2e\` row too when the repo has an end-to-end suite, so step 12 runs it."
    cmd "cat $toolset"
    cmd "$bin/factory-doctor.sh --root $root"
    exit 0
  fi
  if ! written "$sol_open" || ! written "$sol_min"; then
    if [ -n "$autonom" ]; then
      emit "Step 4a of 16: two solutions for $id" "$sol_open (the solution-open session, opus, no point of view imposed) and $sol_min (the solution-min session, fable, the fewest changes) exist, committed in the state clone; the watcher reports each session ready or gone, and a session gone twice with no file leaves the pick to the one solution that exists: write ## Solution over it yourself, its lines - view: <open|min>, - file: <that file>, - chosen by: agent and the reason, and the lane goes on; both gone twice with no file is _shared/blocked-question.md to the human."
    else
      emit "Step 4a of 16: two solutions for $id" "$sol_open (the solution-open session, opus, no point of view imposed) and $sol_min (the solution-min session, fable, the fewest changes) exist, committed in the state clone; the watcher reports each session ready or gone, and a session gone twice with no file is _shared/blocked-question.md to the human."
    fi
    written "$sol_open" || dispatch_step solution-open
    written "$sol_min" || dispatch_step solution-min
    watch_line
    exit 0
  fi
  if [ -n "$autonom" ]; then
    emit "Step 4a of 16: the monitor picks the solution for $id" "you compared the two solutions below under the autonomous section of _shared/auto-decision.md, one row per solution over goal fit, size, risk, tests and what it leaves worse, and ## Solution is written at the end of $task, naming the view, the file, chosen by: agent and that table as the why, reported with state-report.sh --no-status; nobody was asked (references/auto.md, autonom)."
  else
    emit "Step 4a of 16: the human picks the solution for $id" "the human chose through _shared/ask.md between the two solutions below (A the open one, B the minimal one, or their own words over either), and ## Solution is written at the end of $task, naming the view, the file (both files for a mixed answer) and the human's words, reported with state-report.sh --no-status. That yes is the consent for the rest of the lane: the grill, decompose, the approval, the blocks and the task MR run without another ask (references/auto.md)."
  fi
  cmd "cat $sol_open"
  cmd "cat $sol_min"
  cmd "cat $plugin/skills/factory/references/auto.md"
  [ -z "$autonom" ] || cmd "cat $plugin/skills/_shared/auto-decision.md"
  cmd "$bin/state-report.sh --task $id --no-status --message 'chore($id): solution chosen'"
  exit 0
}

# why: `factory auto <T-id>` over a task another lane already grilled has no pick to call its consent, so
# why: without `## Solution` the auto lane keeps the herd's gates from here on: the ask of step 9, the human
# why: at a blocked block. The autonomous lane needs no consent and keeps its flag
if [ -n "$auto" ] && [ -z "$autonom" ] && [ -n "$slug" ] && [ -f "$plan" ] && ! picked; then
  auto='' auto_arg=''
fi

if [ -z "$slug" ] || [ ! -f "$plan" ]; then
  triaged || triage_step
  [ -z "$auto" ] || auto_solutions_step
  if [ -n "$auto" ]; then
    emit "Step 4 of 16: grill $id" "no open gaps, the program design and the proposals are taken by their recommendations under _shared/auto-decision.md (the human asked only where that file says so), every proposal's steps name the tests that cover it (plan-lint.sh --auto passes over the plan), and $state/repos/$key/plans/<slug>-plan-ready.md exists with task: $id in its frontmatter."
    dispatch_step grill; watch_line; exit 0
  fi
  emit "Step 4 of 16: grill $id" "no open gaps, the program design is approved and $state/repos/$key/plans/<slug>-plan-ready.md exists with task: $id in its frontmatter."
  if [ -n "$herd" ]; then dispatch_step grill; watch_line; exit 0; fi
  cmd "cat $plugin/skills/grill/SKILL.md"
  cmd "cat $task"
  exit 0
fi

blocks=$(task_files | while IFS= read -r f; do
  b=$(fm "$f" id)
  if is_block_of "$id" "$b"; then printf '%s\n' "$b"; fi
done | sort_ids)

product=$(clone_path "$key")
verdict="$state/repos/$key/verdicts/$slug.md"

# why: the auto grill's musts (a test line and an e2e line under every proposal's steps) are checked by
# why: plan-lint.sh --auto, and nothing after the grill would run it otherwise: a plan that fails it goes back
# why: to the grill before plan-check or decompose read it
if [ -n "$auto" ] && [ -z "$blocks" ] && ! lint_out=$(sh "$bin/plan-lint.sh" "$plan" --auto 2>&1); then
  emit "Step 4 of 16: the plan of $id misses the auto musts" "plan-lint.sh $plan --auto passes: every proposal names its tests and says e2e or no e2e under steps:, the grill session having fixed the plan (prompt it with the lines below, or start it again)."
  printf '%s\n' "$lint_out" | sed 's/^/  # /'
  cmd "$bin/plan-lint.sh $plan --auto"
  dispatch_step grill; watch_line
  exit 0
fi

# a verdict whose plan_hash is the plan's current hash; one written before an edit of the plan is none, as
# task-new.sh reads it (lib-tasks.sh architect_verdict), so step 5 runs again rather than a decompose it refuses
# why: with no sha256 tool at all the hash cannot be recomputed, and a verdict read as stale would print
# why: step 5 forever; that is a stop naming the tool, before the verdict is read
verdict_current() {
  [ -f "$verdict" ] || return 1
  vc_want=$(sed -n 's/^plan_hash:[[:space:]]*//p' "$verdict" | head -n1)
  if command -v sha256sum >/dev/null 2>&1; then vc_have=$(sha256sum "$plan" | cut -d' ' -f1)
  elif command -v shasum >/dev/null 2>&1; then vc_have=$(shasum -a 256 "$plan" | cut -d' ' -f1)
  elif command -v openssl >/dev/null 2>&1; then vc_have=$(openssl dgst -sha256 "$plan" | sed 's/^.*= //')
  else die "no sha256 tool on PATH (sha256sum, shasum or openssl), so the plan hash of $verdict cannot be checked; install one and run this again"; fi
  [ "$vc_want" = "$vc_have" ]
}

# why: the auto lane never writes overridden-by-human, so a misaligned verdict is a stop with the findings,
# why: not a decompose that task-new.sh refuses and the loop dispatches again; one over an edited plan is
# why: stale and plan-check runs again instead
if [ -n "$auto" ] && [ -z "$blocks" ] && verdict_current \
  && [ "$(sed -n 's/^verdict:[[:space:]]*//p' "$verdict" | head -n1)" = misaligned ]; then
  emit "Step 5 of 16: plan-check found $slug misaligned" "the lane stops here, nothing dispatched: the findings of $verdict are in front of the human as a notice, and the plan is edited (then plan-check runs again, with the lane's flag) or the task goes on under factory herd, where a human may override the verdict."
  cmd "cat $verdict"
  exit 0
fi

# why: task-new.sh refuses the block writes of step 8 without a verdict whose plan_hash still matches, so
# why: the curation is the next step and not a note beside a later one; decompose deletes the verdict once it
# why: writes the blocks, so a parent with blocks is past this step
if [ -z "$blocks" ] && [ -n "$product" ] && [ -d "$product/docs/architecture" ] && { [ ! -f "$verdict" ] || ! verdict_current; }; then
  emit "Step 5 of 16: architect plan-check of $slug" "$verdict records a verdict whose plan_hash is the current hash of $plan$( [ ! -f "$verdict" ] || printf ' (the one there is stale: the plan was edited after it)')."
  if [ -n "$herd" ]; then dispatch_step plan-check; watch_line; exit 0; fi
  cmd "cat $plugin/skills/architect-review/SKILL.md"
  cmd "sha256sum $plan"
  exit 0
fi

if [ -z "$blocks" ]; then
  emit "Step 6 of 16: decompose $id into blocks" "every block of the cut is a draft T-NNN-NN file, at most 12 of them, each with its depends_on."
  if [ -n "$herd" ]; then dispatch_step decompose; watch_line; exit 0; fi
  cmd "cat $plugin/skills/decompose/SKILL.md"
  cmd "cat $plan"
  exit 0
fi

# the wave plan dag-check.sh printed, as the coordinator pasted it into the progress file
wave_lines() { grep -E 'wave[[:space:]]*[0-9]+[[:space:]]*:' "$progress" 2>/dev/null || :; }

if [ -z "$(wave_lines)" ]; then
  emit "Step 8 of 16: check the cut of $id" "dag-check.sh exits 0 and its wave plan is in $progress."
  cmd "$bin/dag-check.sh $id --state $state"
  exit 0
fi

# invariant: only a status the approval still lies ahead of asks for step 9; `review` and `done` are past it and
# invariant: are answered by step 15 and step 16 at the bottom of this file.
case "$status" in
  draft|triaged|ready|claimed|blocked|failed)
    # why: the blocks decompose wrote are draft, and draft -> in_progress is no agent transition, so the one approval
    # why: of the human covers the parent and every block still waiting for it
    approve=''
    case "$status" in draft|triaged|blocked|failed) approve=$id ;; esac
    for b in $blocks; do
      bf=$(task_of "$b" || :)
      [ -n "$bf" ] || continue
      case "$(fm "$bf" status)" in draft|triaged) approve="$approve $b" ;; esac
    done
    approve=${approve# }
    if [ -n "$auto" ]; then
      # why: the human's pick of step 4a is the consent of the auto lane, so the approval is the script run
      # why: and no ask; the bodies are still printed, as a notice, so the human can read what went ready
      emit "Step 9 of 16: approve and claim $id" "task-approve.sh has set $id and its blocks ready without an ask, the human's pick of step 4a being the consent (references/auto.md), the bodies shown as a notice, and $id is in_progress with plan_hash set and owner: the owner string of your Session identity line."
    else
      emit "Step 9 of 16: approve and claim $id" "the human said yes in the approval ask of references/approve.md, and $id is in_progress with plan_hash set and owner: the owner string of your Session identity line."
    fi
    if [ -n "$approve" ]; then
      if [ -n "$auto" ]; then
        for a in $approve; do cmd "cat $(task_of "$a")"; done
      else
        cmd "cat $plugin/skills/factory/references/approve.md"
      fi
      cmd "$bin/task-approve.sh $approve --state $state"
    fi
    cmd "$bin/state-report.sh --task $id --set-status in_progress --owner <owner> --message 'chore($id): claimed'"
    exit 0 ;;
esac

# why: nothing from step 11 on runs in the clone, so no block stage is reachable before this one; the detached
# why: worktree the herd's steps read in before the approval is no session worktree until it is on a branch
if [ ! -e "$worktree/.git" ] || [ "$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null)" = HEAD ]; then
  emit "Step 10 of 16: session worktree for $id" "git -C $worktree rev-parse --abbrev-ref HEAD prints the session branch, written into the parent's branch: field."
  cmd "$bin/worktree-add.sh $id"
  cmd "git -C $worktree rev-parse --abbrev-ref HEAD"
  exit 0
fi

# the blocks in the order the wave plan names them, the rest appended so a block missing from the plan is still
# reached; an id is listed once, at its first mention
ordered=$(
  { wave_lines | grep -oE "$id-[0-9]{2,}" || :
    printf '%s\n' "$blocks"
  } | awk 'NF && !seen[$0]++'
)

wave_of() { # <block id>: the number of the wave line naming it, or nothing
  wave_lines | awk -v b="$1" 'index($0, b) {
      match($0, /wave[[:space:]]*[0-9]+/); n = substr($0, RSTART, RLENGTH)
      sub(/wave[[:space:]]*/, "", n); print n; exit }'
}

pending='' waiting='' working=''
for b in $ordered; do
  bf=$(task_of "$b" || :)
  [ -n "$bf" ] || continue
  bs=$(fm "$bf" status)
  # why: T-164, the stacked MRs: a block is finished when its own MR is merged on the forge and mr-watch.sh
  # why: set it done, so `review` is still a step of the flow (waiting for the developer) and not the end
  case "$bs" in
    done|closed) continue ;;
  esac
  # why: an open block MR is the developer's turn, not a stall: the blocks behind it are still worked on, and
  # why: the reminder below is printed only when nothing else is left to do
  if [ "$bs" = review ] && [ -n "$(fm "$bf" mr_url)" ]; then
    waiting="$waiting$b
"
    continue
  fi
  # why: in the herd a block at work in its session holds nothing: a later block of its wave that is ready for
  # why: a gate or a dispatch comes first, and the wait is the step only when nothing else is left to do
  if [ -n "$herd" ] && { [ "$bs" = in_progress ] || [ "$bs" = claimed ]; }; then
    [ -n "$working" ] || working=$b
    continue
  fi
  if [ -n "$working" ] && [ "$(wave_of "$b")" != "$(wave_of "$working")" ]; then break; fi
  pending=$b
  break
done
[ -n "$pending" ] || pending=$working

# a task already stacked has a block cut from another block's branch; its block MRs stay the developer's to merge
stacked=''
for b in $blocks; do
  case "$(sed -n 's/^base:[[:space:]]*//p' "$state/repos/$key/progress/$b.md" 2>/dev/null | head -n1)" in
    block/*) stacked=1 ;;
  esac
done

# why: every other task cuts a wave's blocks from the work branch once the wave before it is merged, so a block
# why: of a later wave than a waiting MR is not started; the merges below come first
if [ -n "$pending" ] && [ -n "$waiting" ] && [ -z "$stacked" ]; then
  for b in $waiting; do
    [ "$(wave_of "$b")" = "$(wave_of "$pending")" ] || { pending=''; break; }
  done
fi

if [ -n "$pending" ]; then
  bf=$(task_of "$pending")
  bs=$(fm "$bf" status)
  bt=$(fm "$bf" tier); [ -n "$bt" ] || bt=yellow
  ba=$(fm "$bf" archetype); [ -n "$ba" ] || ba=feature
  bc=$(fm "$bf" complexity); [ -n "$bc" ] || bc=medium
  bn=$(fm "$bf" attempt); [ -n "$bn" ] || bn=0
  bp=$(fm "$bf" phase)
  bwt="$own/$pending"
  bprogress="$state/repos/$key/progress/$pending.md"
  wave=$(wave_of "$pending")
  wave_arg=''
  [ -z "$wave" ] || wave_arg=" --wave $wave"

  if [ "$bs" = blocked ] || [ "$bs" = failed ]; then
    if [ -n "$herd" ]; then bretry="the next dispatch of its wave, a fresh session"; else bretry="a fresh implement subagent"; fi
    if [ -n "$auto" ]; then
      # why: the fourth case of auto-decision.md: a block failed at its second attempt is the human's in every
      # why: lane, so the autonomous answer covers a blocked block and a first failure only
      # why: task-approve.sh counts attempts from failed only, so a block blocked again after an answer the lane
      # why: gave is counted here, by the answer lines its progress file holds: the second one is the human's,
      # why: or the same analysis would set it ready forever
      lane_answers=$(grep -cE '^\*\*Answer \([0-9-]+\): option [0-9]+\*\*.*\((auto|analysed)\)[[:space:]]*$' "$bprogress" 2>/dev/null || :)
      case "$lane_answers" in ''|*[!0-9]*) lane_answers=0 ;; esac
      if [ -n "$autonom" ] && { { [ "$bs" = blocked ] && [ "$lane_answers" -lt 1 ]; } || { [ "$bs" = failed ] && [ "$bn" -lt 1 ]; }; }; then
        emit "Step 11 of 16: $pending is $bs" "you answered the question in $bprogress with its recommendation, or with the option your analysis picked where none stood (the autonomous section of _shared/auto-decision.md; a block whose every option fails, or failed at its second attempt, is the human's, through _shared/blocked-question.md, in this lane too), applied what the answer requires to the block, and task-approve.sh has set $pending ready again for its retry with attempt $((bn + 1)) on $bretry."
      elif [ -n "$autonom" ] && [ "$bs" = blocked ]; then
        emit "Step 11 of 16: $pending is blocked again, after $lane_answers answer$( [ "$lane_answers" -eq 1 ] || printf s) of the lane" "the human has answered the question in $bprogress (a block blocked again after an answer the lane gave is the fourth case of _shared/auto-decision.md: the lane's analysis did not unblock it, and a third answer over the same ground is a loop), what the answer requires is applied to the block, and task-approve.sh has set $pending ready again for its retry with attempt $((bn + 1)) on $bretry."
      elif [ -n "$autonom" ]; then
        emit "Step 11 of 16: $pending is $bs at attempt $bn" "the human has answered the question in $bprogress (a block failed at its second attempt is the fourth case of _shared/auto-decision.md, the human's in this lane too), what the answer requires is applied to the block, and task-approve.sh has set $pending ready again for its retry with attempt $((bn + 1)) on $bretry."
      else
        emit "Step 11 of 16: $pending is $bs" "you answered the question in $bprogress with its recommendation, or asked the human only where _shared/auto-decision.md says so, applied what the answer requires to the block, and task-approve.sh has set $pending ready again for its retry with attempt $((bn + 1)) on $bretry."
      fi
    else
      emit "Step 11 of 16: $pending is $bs" "the human has answered the question in $bprogress, what the answer requires is applied to the block, and task-approve.sh has set $pending ready again for its retry with attempt $((bn + 1)) on $bretry."
    fi
    cmd "cat $bprogress"
    cmd "cat $plugin/skills/_shared/blocked-question.md"
    [ -z "$auto" ] || cmd "cat $plugin/skills/_shared/auto-decision.md"
    cmd "$bin/task-approve.sh $pending --state $state"
    [ -n "$herd" ] || cmd "$bin/model-for.sh $ba $bt implement $((bn + 1)) $bc"
  elif [ "$bs" = changes_requested ]; then
    # why: the fixes are new commits on the block branch, which the verification of the first MR is not of:
    # why: block-verify.sh runs again over them (the crap gate included) and block-mr.sh, which refuses a
    # why: report of another tree, refreshes the MR body with the new report; without it the fixed code
    # why: merged on the first report
    emit "Step 11 of 16: $pending has changes requested" "the threads of the block MR are answered on its branch by one implement subagent, every block behind $pending is rebased onto its new head, block-verify.sh is green again over the new head$( [ -z "$stacked" ] || printf ' and block-merge.sh --verify proves the merge again'), block-mr.sh has refreshed the MR from the new report, and $pending is review again."
    cmd "$bin/mr-watch.sh $id --comments $pending --state $state"
    cmd "$bin/model-for.sh $ba $bt implement $((bn + 1)) $bc"
    [ -z "$stacked" ] || cmd "$bin/restack.sh $id $pending --state $state"
    cmd "$bin/block-verify.sh $pending --state $state"
    [ -z "$stacked" ] || cmd "$bin/block-merge.sh $pending --verify"
    cmd "$bin/block-mr.sh $pending --state $state"
    cmd "$bin/state-report.sh --task $pending --set-status review --message 'chore($pending): review fixes pushed'"
  elif [ "$bs" = draft ] || [ "$bs" = triaged ]; then
    # why: a block written after the approval (a thread outside a block's acceptance, a fix round) is a draft,
    # why: and draft -> in_progress is no agent transition
    if [ -n "$auto" ]; then
      emit "Step 11 of 16: approve $pending" "task-approve.sh has set $pending ready without an ask, as references/auto.md says of a block written after the pick."
    else
      emit "Step 11 of 16: approve $pending" "the human said yes in the approval ask of references/approve.md and $pending is ready."
      cmd "cat $plugin/skills/factory/references/approve.md"
    fi
    cmd "$bin/task-approve.sh $pending --state $state"
  elif [ -n "$herd" ] && { [ "$bs" = ready ] || [ "$bs" = tests_ready ] ||
      { [ ! -e "$bwt/.git" ] && { [ "$bs" = in_progress ] || [ "$bs" = claimed ]; }; }; }; then
    # why: in the herd a block is a session, and session-monitor.sh claims each one it starts; a claim of the
    # why: monitor's own would leave it no ready block to dispatch. A tests_ready block goes out again with the
    # why: implement phase armed, which is what session-monitor.sh dispatches it on
    emit "Step 11 of 16: dispatch wave ${wave:-1} of $id" "every ready block of the wave printed <id> spawned from session-monitor.sh, which claimed it for its session$( [ "$bs" != tests_ready ] || printf ', and %s, after you reran its red tests at the commit its ## Handoff names, each failing for the reason it states, carries phase: implement and went out for its implement session (another tests_ready block of the wave follows on the next step)' "$pending")."
    # every block of the wave that has no worktree yet gets one, or session-monitor.sh skips it
    for b in $ordered; do
      [ "$(wave_of "$b")" = "$wave" ] && [ ! -e "$own/$b/.git" ] || continue
      case "$(fm "$(task_of "$b")" status)" in ready|tests_ready|in_progress|claimed) cmd "$bin/worktree-add.sh $b" ;; esac
    done
    if [ "$bs" = tests_ready ]; then
      cmd "sed -n '/^## Handoff/,\$p' $bprogress"
      cmd "(cd $bwt && <test-filter binding over the red test files the ## Handoff names>)"
      cmd "$bin/state-report.sh --task $pending --set-phase implement --no-status --message 'chore($pending): implement'"
    fi
    cmd "$bin/session-monitor.sh --task $id$wave_arg --state $state"
    watch_line
  elif [ -n "$herd" ] && { [ "$bs" = in_progress ] || [ "$bs" = claimed ]; }; then
    # why: a block session holds its block in_progress while it works, and the Stop hook has it report
    # why: tests_ready or review with its ## Evidence when it ends; that report is a claim the next step reruns
    # why: a session that died, or a spawn that failed after its claim, would hold the block for good; the same
    # why: dispatch starts it again, and skips every block whose session still runs
    emit "Step 11 of 16: wave ${wave:-1} of $id works in its sessions" "herd-watch.sh has reported $pending tests_ready or review, or its agent blocked, gone or ready with no report, and you acted on that line as references/herd.md says."
    watch_line
    cmd "$bin/session-monitor.sh --task $id$wave_arg --state $state"
  elif [ -n "$herd" ] && [ "$bs" = review ]; then
    emit "Step 11 of 16: verify, review and open the MR for $pending" "$pending has its mr_url set: its session's report is rerun by you (a single-phase block's red tests at the commit its ## Red proof names, red, and at HEAD, green), block-verify.sh is green and wrote $own/.harness/$pending/verify.txt, the code-reviewer's final message is saved as $own/.harness/$pending/review.md and the architecture-auditor wrote $own/.harness/$pending/arch.md, both over the block diff, as your subagents, and block-mr.sh opened the MR into ${branch:-the work branch} from them."
    [ -e "$bwt/.git" ] || cmd "$bin/worktree-add.sh $pending"
    cmd "$bin/block-verify.sh $pending --state $state"
    [ -z "$stacked" ] || cmd "$bin/block-merge.sh $pending --verify"
    cmd "$bin/model-for.sh review $bt '' 0 $bc"
    cmd "$bin/block-mr.sh $pending"
  elif [ ! -e "$bwt/.git" ] || [ "$bs" = claimed ] || [ "$bs" = ready ]; then
    emit "Step 11 of 16: worktree and claim for $pending" "$bwt exists on the block branch and $pending is in_progress with your owner string. No worktree, no spawn."
    [ -e "$bwt/.git" ] || cmd "$bin/worktree-add.sh $pending"
    cmd "$bin/state-report.sh --task $pending --set-status in_progress --owner <owner> --message 'chore($pending): claimed'"
  elif [ "$bs" = tests_ready ]; then
    emit "Step 11 of 16: wave ${wave:-1} implement, from $pending" "every block of the wave has its implement subagent spawned with the brief spawn-plan.sh wrote."
    cmd "$bin/state-report.sh --task $pending --set-status in_progress --set-phase implement --message 'chore($pending): implement'"
    cmd "$bin/spawn-plan.sh $id$wave_arg --state $state"
  elif [ -z "$bp" ] && ! single_phase "$bt" "$bc"; then
    emit "Step 11 of 16: wave ${wave:-1} tests, from $pending" "you have rerun the red tests each agent wrote yourself, written them under ## Evidence with the ## Handoff, and every two-phase block of the wave (red, or yellow above low complexity) is tests_ready."
    cmd "$bin/spawn-plan.sh $id$wave_arg --state $state"
    cmd "$bin/state-report.sh --task <block-id> --set-status tests_ready --message 'chore(<block-id>): tests ready'"
  elif [ -z "$bp" ]; then
    # why: a single-phase block (green, or yellow at complexity low) gets no tests phase, so the red proof the
    # why: coordinator would have rerun at tests_ready is rerun here instead: the agent's first commit carries
    # why: the red tests alone, and that commit is checked out and run before the phase field is armed
    emit "Step 11 of 16: wave ${wave:-1} single-phase implement, from $pending" "the implement subagent of $pending has returned, its first commit on the block branch touches test files only and its ## Red proof names that commit; you have run test-filter over those files at that commit yourself (red) and at HEAD (green), and $pending carries phase: implement."
    cmd "$bin/spawn-plan.sh $id$wave_arg --state $state"
    bbase=$(sed -n 's/^base:[[:space:]]*//p' "$bprogress" 2>/dev/null | head -n1)
    cmd "git -C $bwt log --format='%h %s' --name-only ${bbase:-$branch}..HEAD"
    cmd "git -C $bwt worktree add --detach $harness/red-$pending <red-commit> && (cd $harness/red-$pending && <test-filter binding over the red test files>); git -C $bwt worktree remove --force $harness/red-$pending"
    cmd "$bin/state-report.sh --task $pending --set-phase implement --no-status"
  elif [ -z "$stacked" ]; then
    # why: a block cut from the work branch merges into it through its own MR, so there is no stack to prove the
    # why: merge into; block-mr.sh builds the description from the reviewer's and the auditor's reports
    emit "Step 11 of 16: verify, review and open the MR for $pending" "$pending is review with its mr_url set: block-verify.sh is green and wrote $own/.harness/$pending/verify.txt, the code-reviewer's final message is saved as $own/.harness/$pending/review.md and the architecture-auditor wrote $own/.harness/$pending/arch.md, both over the block diff, and block-mr.sh opened the MR into ${branch:-the work branch} from them."
    cmd "$bin/model-for.sh $ba $bt verify $bn $bc"
    cmd "$bin/block-verify.sh $pending --state $state"
    cmd "$bin/block-mr.sh $pending"
    cmd "$bin/state-report.sh --task $pending --set-status review --message 'chore($pending): MR open'"
  else
    emit "Step 11 of 16: verify and open the MR for $pending" "$pending is review with its mr_url set, evidenced in $bprogress, and the merge into the session branch is proved green."
    cmd "$bin/model-for.sh $ba $bt verify $bn $bc"
    cmd "$bin/block-verify.sh $pending --state $state"
    cmd "$bin/block-merge.sh $pending --verify"
    cmd "$bin/block-mr.sh $pending --state $state"
    cmd "$bin/state-report.sh --task $pending --set-status review --message 'chore($pending): MR open'"
  fi
  exit 0
fi

if [ -n "$waiting" ] && [ -z "$stacked" ]; then
  emit "Step 11 of 16: merge the block MRs of $id" "every block below is done: block-mr-merge.sh has merged its MR into ${branch:-the work branch}, pulled the parent worktree and set the block done, a high risk too, recorded as ## Merged in its progress file for the human; a class C forge prints <block> auto-merge <url>, and the line runs again once the forge has merged it. The next wave is cut from the work branch once this one is merged."
  for b in $waiting; do
    cmd "$bin/block-mr-merge.sh $b"
  done
  exit 0
fi

if [ -n "$waiting" ]; then
  emit "Step 11 of 16: $id waits for the developer" "the human has been asked to review and merge the block MRs listed below, and mr-watch.sh is armed on $id: merged sets the block done and retargets the stack, changes-requested opens the fix round through state-report.sh --set-status changes_requested, and new-comments is read first with --comments and answered thread by thread, a thread asking for a code change being a fix round on the same block branch, a question being answered on the MR by hand (forge.sh reads only, so print the answer for the human), and a thread asking for work outside the block's acceptance being a new draft block with depends_on on that block: the template written to $harness/extra.md and filled in, an architect-review cut-check over that one block, task-new.sh --parent, and the verdict removed and committed afterwards when the registered clone has docs/architecture/, as decompose does."
  for b in $waiting; do
    bf=$(task_of "$b" || :)
    [ -n "$bf" ] || continue
    bbase=$(sed -n 's/^base:[[:space:]]*//p' "$state/repos/$key/progress/$b.md" 2>/dev/null | head -n1)
    cmd "$b $(fm "$bf" mr_url) -> ${bbase:-$branch}"
  done
  cmd "$bin/mr-watch.sh $id --once --state $state"
  cmd "$bin/mr-watch.sh $id --interval 300 --state $state"
  cmd "$bin/mr-watch.sh $id --comments <block-id> --state $state"
  cmd "$bin/state-report.sh --task <block-id> --set-status changes_requested --message 'chore(<block-id>): changes requested'"
  cmd "mkdir -p $harness"
  cmd "$bin/task-template.sh block > $harness/extra.md"
  cmd "cat $plugin/skills/architect-review/SKILL.md $plugin/skills/architect-review/references/cut-check.md"
  cmd "$bin/task-new.sh --repo $key --parent $id --file $harness/extra.md --state $state"
  if [ -n "$product" ] && [ -d "$product/docs/architecture" ]; then
    cmd "rm $state/repos/$key/verdicts/$slug.md"
    cmd "$bin/state-commit.sh -m 'chore($id): extra block written, verdict removed' --state $state -- repos/$key/verdicts/$slug.md"
  fi
  exit 0
fi

base=$(base_branch)

# why: a fix block merged after the review (a review round on the task MR) left ## Evidence, ## Duplication
# why: and ## Review standing, so the loop went to step 16 and the fix was never built, tested or reviewed.
# why: ## Review names the blocks it covered on a `blocks:` line (step 13 writes it); a done block missing from
# why: it is a fix block the quality steps have not seen, and the step is the reset that brings them back
# why: before the MR too: a fix block of step 13's changes-needed round has to pass the build, the tests,
# why: the e2e and the duplication check before step 14 opens the MR over it. The ids are read by their shape,
# why: so a blocks: line written with commas, brackets or backticks reads the same
# why: the reset drops ## Review, so the rounds are counted under ## Fix rounds, one bullet per reset, which
# why: the reset never touches: a changes-needed verdict before the MR gets one fix block, and the second
# why: verdict is recorded and the flow goes on, which step 13 can only say when it knows a round happened
fix_rounds_before=$(awk '/^## Fix rounds[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && /^- round / && /before the task MR/ { n++ } END { print n + 0 }' "$progress" 2>/dev/null || :)
case "$fix_rounds_before" in ''|*[!0-9]*) fix_rounds_before=0 ;; esac
if grep -q '^## Review' "$progress" 2>/dev/null; then
  # the blocks: line with its continuation lines, up to a blank line or the next key: a reviewer who wraps a
  # dozen ids over two lines names them all
  reviewed=$(awk '/^## Review/ { f = 1; next } f && /^#/ { exit } f && /^blocks:/ { b = 1; print; next } b && (!NF || /^[A-Za-z_-]+:/) { exit } b { print }' "$progress" | grep -oE "$id-[0-9]{2,}" | tr '\n' ' ')
  if [ -n "$reviewed" ]; then
    unreviewed=''
    for b in $blocks; do
      bf=$(task_of "$b" || :)
      [ -n "$bf" ] && [ "$(fm "$bf" status)" = done ] || continue
      case " $reviewed " in *" $b "*) ;; *) unreviewed="$unreviewed $b" ;; esac
    done
    if [ -n "$unreviewed" ]; then
      if [ -n "$mr_url" ]; then fr_when="after the task MR"; else fr_when="before the task MR"; fi
      fr_n=$(awk '/^## Fix rounds[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && /^- round / { n++ } END { print n + 1 }' "$progress")
      emit "Step 12 of 16: fix round over $id, $fr_when" "## Evidence, ## Quality, ## Duplication and ## Review are gone from $progress, ## Fix rounds holds the line 'round $fr_n ($fr_when):${unreviewed}' and the file is reported, so steps 12 and 13 run again over the work branch with${unreviewed} merged; step 13 then lists every done block on the blocks: line of ## Review$( [ -z "$mr_url" ] || printf ' and refreshes the MR body')."
      cmd "sed -i '/^## Evidence/,/^## /{/^## Evidence/d;/^## /!d}; /^## Quality/,/^## /{/^## Quality/d;/^## /!d}; /^## Duplication/,/^## /{/^## Duplication/d;/^## /!d}; /^## Review/,/^## /{/^## Review/d;/^## /!d}' $progress"
      cmd "grep -q '^## Fix rounds' $progress || printf '\\n## Fix rounds\\n' >> $progress"
      cmd "awk -v l='- round $fr_n ($fr_when):${unreviewed}' '/^## Fix rounds/ { f = 1; print; next } f && /^## / { print l; f = 0 } { print } END { if (f) print l }' $progress > $progress.tmp && mv $progress.tmp $progress"
      cmd "$bin/state-report.sh --task $id --no-status --message 'chore($id): fix round, quality steps again'"
      exit 0
    fi
  fi
fi

if ! grep -q '^## Evidence' "$progress" 2>/dev/null; then
  e2e=''
  # why: the auto lane ends in a build and the whole test run, the end-to-end suite included where the repo
  # why: binds one; a toolset without the row has none to run, and the line says so
  if [ -n "$auto" ]; then
    if binds e2e; then e2e=", the build and the test bindings are green over the work branch and the toolset's e2e binding ran green and is recorded under ## Evidence too"
    else e2e=", the build and the test bindings are green over the work branch and ## Evidence notes that the toolset binds no e2e"; fi
  fi
  emit "Step 12 of 16: acceptance and quality over $id" "the parent's ## Acceptance is green verbatim, format and arch-build are recorded under ## Evidence in $progress$e2e, and crap is a gate, not a recording: with a crap row in the toolset no changed method is over its crap-threshold, block-verify.sh refused every block that had one, every method skipped or exempt under _shared/test-exemptions.md is listed by name in ## Quality, and only without a crap row does a method still over it carry its reason in the note."
  cmd "sed -n '/^## Acceptance/,/^## /p' $task"
  cmd "sed -n '/^|/p' $state/repos/$key/toolset.md"
  cmd "cat $plugin/skills/_shared/crap-loop.md"
  exit 0
fi

if ! grep -q '^## Duplication' "$progress" 2>/dev/null; then
  emit "Step 12b of 16: duplication check over $id" "dup-check.sh has run over the whole diff and its output stands verbatim under ## Duplication in $progress, judged by nobody yet: the code-reviewer of step 13 answers every candidate. An empty candidate list is recorded as one line."
  cmd "mkdir -p $harness"
  cmd "git -C $worktree diff origin/$base...${branch:-HEAD} > $harness/review.diff"
  cmd "$bin/dup-check.sh $harness/review.diff $worktree"
  exit 0
fi

if ! grep -q '^## Review' "$progress" 2>/dev/null; then
  # see: set -e, so the loop ends on a true status whatever the last block's status is
  done_blocks=$(for b in $blocks; do bf=$(task_of "$b" || :); if [ -n "$bf" ] && [ "$(fm "$bf" status)" = done ]; then printf '%s ' "$b"; fi; done; :)
  refresh=''
  [ -z "$mr_url" ] || refresh=", and since the task MR is open, mr-open.sh${auto:+ --decisions} has refreshed its body with the new block"
  # why: before the MR the round is counted: the first changes-needed verdict gets one fix block, written
  # why: after the verdict and its blocks: line are recorded (the reset of step 12 reads that line to see the
  # why: fix block as new), and the verdict after that round is recorded and the flow goes on, whatever it
  # why: says; a round after the MR is the human's review and each one is a round of its own
  if [ -z "$mr_url" ] && [ "$fix_rounds_before" -ge 1 ]; then
    second="this is the verdict after the fix round ## Fix rounds counts, so it is recorded with its blocks: line, the fix block in it, and the flow goes on to step 14 whatever it says: no further fix block is cut before the MR, and what it still asks for is a ## Follow-ups bullet of $progress"
  else
    second="a changes needed verdict is recorded first, with its blocks: line, and gets one fix block, cut after that line is written, so the reset of step 12 tells the fix block apart, and the reviewer once more; that second verdict is recorded, its blocks: line rewritten with the fix block in it, and does not stop the flow"
  fi
  emit "Step 13 of 16: integrated review of $id" "a verdict from code-reviewer is under ## Review in $progress, opening with the line blocks: ${done_blocks:-<every done block>}(the blocks this review covers, which is how a later fix block is told apart), its brief carrying the block-verify reports, the ## Quality table and the ## Duplication candidates, spawned after the last block is merged and before the MR (ADR-0053), in parallel with a docs subagent bounded to the parent's ## Docs paths, never code or tests, its commit serialised with the coordinator's, because docs landing after the MR is a follow-up commit the verdict never covered; $second$refresh."
  cmd "mkdir -p $harness"
  cmd "git -C $worktree diff origin/$base...${branch:-HEAD} > $harness/review.diff"
  cmd "$bin/model-for.sh review $tier '' 0 $complexity"
  cmd "cat $plugin/skills/_shared/delegation.md"
  [ -z "$mr_url" ] || cmd "$bin/mr-open.sh $id${auto:+ --decisions} --state $state"
  exit 0
fi

if [ -z "$mr_url" ]; then
  if [ -n "$auto" ]; then
    emit "Step 14 of 16: the task MR of $id for the human's review" "the MR of $id into $base exists with no conflicts, lists every block MR under ## Blocks and every decision of the grill under ## Decisions (mr-open.sh --decisions), mr-open.sh has written its URL into the mr_url of $id, and the human has been told it is theirs to review: a review round on it is the fix round of references/auto.md, taken without an ask, and done follows the merge."
  else
    emit "Step 14 of 16: the task MR of $id for the human's review" "the MR of $id into $base exists with no conflicts and lists every block MR under ## Blocks, mr-open.sh has written its URL into the mr_url of $id, and the human has been asked to review and merge it; done follows the merge."
  fi
  cmd "git -C $worktree fetch origin"
  cmd "git -C $worktree rebase origin/$base"
  cmd "git -C $worktree push --force-with-lease origin ${branch:-HEAD}"
  cmd "cat $plugin/skills/_shared/mr-description.md"
  cmd "$bin/mr-open.sh $id${auto:+ --decisions} --state $state"
  exit 0
fi

if [ "$status" != review ]; then
  emit "Step 15 of 16: self-report $id" "$id is review with mr_url set, and the report is in."
  cmd "$bin/state-report.sh --task $id --set-status review --message 'chore($id): review, MR open'"
  exit 0
fi

# why: the human's merge of the task MR ends the task through mr-watch.sh --finish, in the herd through the
# why: herd-watch.sh pass that already runs it, so a session that is gone by then misses nothing
if [ -n "$herd" ]; then
  emit "Step 16 of 16: knowledge review for $id" "this session's lessons and decisions are judged and the proposals written, and herd-watch.sh stays armed on $id until it reports $id done."
else
  emit "Step 16 of 16: knowledge review for $id" "this session's lessons and decisions are judged and the proposals written, and mr-watch.sh --finish is armed on $id through the Monitor tool, so the human's merge of the task MR ends the task."
fi
cmd "cat $plugin/skills/_shared/knowledge-review.md"
cmd "sed -n 's/^curation:[[:space:]]*//p' $state/factory.yml"
cmd "$bin/curate-apply.sh --help"
[ -n "$herd" ] || cmd "Monitor tool, armed once the review is in: $bin/mr-watch.sh $id --finish --interval 300 --state $state"
cmd "$bin/state-push.sh --state $state"
