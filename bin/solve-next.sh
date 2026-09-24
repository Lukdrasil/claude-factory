#!/bin/sh
# The next step of `factory solve` for one parent task (T-154), worked out from state instead of carried in the
# coordinator's context: the parent task file, its T-NNN-NN blocks and their statuses, the worktrees under
# <root>/<key>/, the architect verdict file and the progress file.
#
#   solve-next.sh <T-NNN> [--state <dir>] [--ui <sid>]
#                            the state clone; default $WORK_DIR/state, else resolved from the cwd
#                            --ui also records the step in that session's session.md through ui-session.sh
#
# T-164: a block ends in its own MR into the branch of the block it was cut from, so step 11 runs until every
# block is `done`, which is what mr-watch.sh writes when the developer merges that MR on the forge. A block in
# `review` with an `mr_url` is waiting for the developer, so step 11 steps over it to the next block that still
# needs work and only prints the reminder with the open MRs when every remaining block is one of those; a block
# in `changes_requested` is a fix round.
#
# It prints exactly one step of skills/factory/references/solve.md: a `## Step <n> ...` heading, one line
# beginning `Completion:`, and under `Commands:` the commands to run, two spaces in front of each. The work
# root is the parent directory of the state clone, so every path printed is absolute: `<root>/<key>/T-NNN` is
# the session worktree, `<root>/<key>/T-NNN-NN` a block worktree, `<root>/<key>/.harness/T-NNN` the scratch
# directory of the run.
#
# The state a step is read off, in the order the steps are tried: no `tier` is step 3, no plan-ready file is
# step 4, a product repo with docs/architecture/ and no verdict is step 5, no blocks is step 6, blocks with no
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

id='' state='' ui=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --ui) [ $# -ge 2 ] || die "--ui needs a value"; ui=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one parent id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: solve-next.sh <T-NNN> [--state <dir>] [--ui <sid>]"
case "$id" in
  T-[0-9][0-9][0-9]) ;;
  *) die "'$id' is not a parent task id of the shape T-NNN" ;;
esac

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

# the `default_branch:` of a repo in repos.yml, main when it names none
base_branch() {
  b=$(awk -v want="$key" '
    /^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k) }
    index($0, "default_branch:") && k == want {
      p = $0; sub(/.*default_branch:[ \t]*/, "", p); sub(/[ \t]*[,}].*$/, "", p)
      gsub(/^["'"'"']|["'"'"']$/, "", p); if (p != "") { print p; exit }
    }' "$state/repos.yml" 2>/dev/null || :)
  [ -n "$b" ] || b=main
  printf '%s' "$b"
}

emit() { # <heading> <completion line>
  printf '## %s\n' "$1"
  printf 'Completion: %s\n' "$2"
  printf 'Commands:\n'
  [ -z "$ui" ] || sh "$bin/ui-session.sh" --session "$ui" --task "$id" --flow solve --step "$1"
}
cmd() { printf '  %s\n' "$1"; }

tier=$(fm "$task" tier)
archetype=$(fm "$task" archetype)
complexity=$(fm "$task" complexity)
[ -n "$complexity" ] || complexity=medium
status=$(fm "$task" status)
branch=$(fm "$task" branch)
mr_url=$(fm "$task" mr_url)

if [ -z "$tier" ] || [ -z "$archetype" ]; then
  emit "Step 3 of 16: triage $id" "tier and archetype are set on $id."
  cmd "cat $task"
  cmd "cat $plugin/skills/_shared/investigate.md"
  cmd "$bin/state-report.sh --task $id --no-status --message 'chore($id): triaged'"
  exit 0
fi

slug=$(grep -oE 'plans/[A-Za-z0-9_.-]+-plan-ready\.md' "$task" 2>/dev/null | head -n1 | sed 's|^plans/||; s|-plan-ready\.md$||' || :)
plan="$state/repos/$key/plans/$slug-plan-ready.md"

if [ -z "$slug" ] || [ ! -f "$plan" ]; then
  emit "Step 4 of 16: grill $id" "no open gaps, the program design is approved and $state/repos/$key/plans/<slug>-plan-ready.md exists, named in the parent's ## Context."
  cmd "cat $plugin/skills/grill/SKILL.md"
  cmd "cat $task"
  exit 0
fi

product=$(clone_path "$key")
verdict="$state/repos/$key/verdicts/$slug.md"

# why: architect-gate.sh denies the block writes of step 8 without a verdict whose plan_hash still matches, so
# why: the curation is the next step and not a note beside a later one
if [ -n "$product" ] && [ -d "$product/docs/architecture" ] && [ ! -f "$verdict" ]; then
  emit "Step 5 of 16: architect plan-check of $slug" "$verdict records a verdict whose plan_hash is the current hash of $plan."
  cmd "cat $plugin/skills/architect-review/SKILL.md"
  cmd "sha256sum $plan"
  exit 0
fi

blocks=''
for f in "$state"/repos/*/tasks/*.md; do
  [ -f "$f" ] || continue
  b=$(fm "$f" id)
  case "$b" in
    "$id"-[0-9][0-9]) blocks="$blocks$b
" ;;
  esac
done
blocks=$(printf '%s' "$blocks" | sort)

if [ -z "$blocks" ]; then
  emit "Step 6 of 16: decompose $id into blocks" "every block of the cut is a draft T-NNN-NN file, at most 12 of them, each with its depends_on and parallel_group."
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
  draft|triaged|ready|claimed|blocked|stalled|failed)
    emit "Step 9 of 16: approve and claim $id" "$id is in_progress with plan_hash set."
    cmd "$bin/task-approve.sh $id --state $state"
    cmd "$bin/state-report.sh --task $id --set-status in_progress --message 'chore($id): claimed'"
    exit 0 ;;
esac

# why: nothing from step 11 on runs in the clone, so no block stage is reachable before this one
if [ ! -e "$worktree/.git" ]; then
  emit "Step 10 of 16: session worktree for $id" "git -C $worktree rev-parse --abbrev-ref HEAD prints the session branch, written into the parent's branch: field."
  cmd "$bin/worktree-add.sh $id"
  cmd "git -C $worktree rev-parse --abbrev-ref HEAD"
  exit 0
fi

# the blocks in the order the wave plan names them, the rest appended so a block missing from the plan is still
# reached; an id is listed once, at its first mention
ordered=$(
  { wave_lines | grep -oE "$id-[0-9][0-9]" || :
    printf '%s\n' "$blocks"
  } | awk 'NF && !seen[$0]++'
)

wave_of() { # <block id>: the number of the wave line naming it, or nothing
  wave_lines | awk -v b="$1" 'index($0, b) {
      match($0, /wave[[:space:]]*[0-9]+/); n = substr($0, RSTART, RLENGTH)
      sub(/wave[[:space:]]*/, "", n); print n; exit }'
}

pending='' waiting=''
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
  pending=$b
  break
done

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
    emit "Step 11 of 16: $pending is $bs" "the human has answered the question in $bprogress, or $pending is retried with attempt $((bn + 1)) on a fresh implement subagent."
    cmd "cat $bprogress"
    cmd "cat $plugin/skills/_shared/blocked-question.md"
    cmd "$bin/model-for.sh $ba $bt implement $((bn + 1)) $bc"
  elif [ "$bs" = changes_requested ]; then
    emit "Step 11 of 16: $pending has changes requested" "the threads of the block MR are answered on its branch by one implement subagent, every block behind $pending is rebased onto its new head, and $pending is review again."
    cmd "$bin/mr-watch.sh $id --comments $pending --state $state"
    cmd "$bin/model-for.sh $ba $bt implement $((bn + 1)) $bc"
    cmd "$bin/restack.sh $id $pending --state $state"
    cmd "$bin/state-report.sh --task $pending --set-status review --message 'chore($pending): review fixes pushed'"
  elif [ ! -e "$bwt/.git" ] || [ "$bs" = claimed ]; then
    emit "Step 11 of 16: worktree and claim for $pending" "$bwt exists on the block branch and $pending is in_progress. No worktree, no spawn."
    [ -e "$bwt/.git" ] || cmd "$bin/worktree-add.sh $pending"
    cmd "$bin/state-report.sh --task $pending --set-status in_progress --message 'chore($pending): claimed'"
  elif [ "$bs" = tests_ready ]; then
    emit "Step 11 of 16: wave ${wave:-1} implement, from $pending" "every block of the wave has its implement subagent spawned with the brief spawn-plan.sh wrote."
    cmd "$bin/state-report.sh --task $pending --set-phase implement --no-status"
    cmd "$bin/spawn-plan.sh $id$wave_arg --state $state"
  elif [ -z "$bp" ] && ! single_phase "$bt" "$bc"; then
    emit "Step 11 of 16: wave ${wave:-1} tests, from $pending" "you have rerun the red tests each agent wrote yourself, and every two-phase block of the wave (red, or yellow above low complexity) is tests_ready."
    cmd "$bin/spawn-plan.sh $id$wave_arg --state $state"
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

if [ -n "$waiting" ]; then
  emit "Step 11 of 16: $id waits for the developer" "the human has been asked to review and merge the block MRs listed below, and mr-watch.sh is armed on $id: merged sets the block done and retargets the stack, changes-requested opens the fix round through state-report.sh --set-status changes_requested, and new-comments is read first with --comments and answered thread by thread, a thread asking for a code change being a fix round on the same block branch, a question being answered on the MR by hand (forge.sh reads only, so print the answer for the human), and a thread asking for work outside the block's acceptance being a new draft block through task-new.sh with depends_on on that block."
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
  cmd "$bin/task-template.sh block > $harness/extra.md && $bin/task-new.sh --repo $key --parent $id --file $harness/extra.md --state $state"
  exit 0
fi

base=$(base_branch)

if ! grep -q '^## Evidence' "$progress" 2>/dev/null; then
  emit "Step 12 of 16: acceptance and quality over $id" "the parent's ## Acceptance is green verbatim, format and arch-build are recorded under ## Evidence in $progress, and crap is a gate, not a recording: no changed method is over the toolset's crap-threshold, every method skipped or exempt under _shared/test-exemptions.md is listed by name in ## Quality, and a method still over it carries its reason in the note."
  cmd "sed -n '/^## Acceptance/,/^## /p' $task"
  cmd "sed -n '/^|/p' $state/repos/$key/toolset.md"
  cmd "cat $plugin/skills/_shared/crap-loop.md"
  exit 0
fi

if ! grep -q '^## Duplication' "$progress" 2>/dev/null; then
  emit "Step 12b of 16: duplication check over $id" "dup-check.sh has run over the whole diff and its output stands verbatim under ## Duplication in $progress, judged by nobody yet: the factory-reviewer of step 13 answers every candidate. An empty candidate list is recorded as one line."
  cmd "mkdir -p $harness"
  cmd "git -C $worktree diff origin/$base...${branch:-HEAD} > $harness/review.diff"
  cmd "$bin/dup-check.sh $harness/review.diff $worktree"
  exit 0
fi

if ! grep -q '^## Review' "$progress" 2>/dev/null; then
  emit "Step 13 of 16: integrated review of $id" "a verdict from factory-reviewer is under ## Review in $progress, its brief carrying the block-verify reports, the ## Quality table and the ## Duplication candidates, spawned after the last block is merged and before the MR (ADR-0053), in parallel with a docs subagent bounded to the parent's ## Docs paths, never code or tests, its commit serialised with the coordinator's, because docs landing after the MR is a follow-up commit the verdict never covered; a changes needed verdict gets one fix block and the reviewer once more, and that second verdict is recorded but does not stop the flow."
  cmd "mkdir -p $harness"
  cmd "git -C $worktree diff origin/$base...${branch:-HEAD} > $harness/review.diff"
  cmd "$bin/model-for.sh review $tier '' 0 $complexity"
  cmd "cat $plugin/skills/_shared/delegation.md"
  exit 0
fi

if [ -z "$mr_url" ]; then
  emit "Step 14 of 16: open the MR for $id" "the MR exists with no conflicts against $base, or the branch is merge-ready without a forge."
  cmd "git -C $worktree fetch origin"
  cmd "git -C $worktree rebase origin/$base"
  cmd "git -C $worktree push --force-with-lease origin ${branch:-HEAD}"
  cmd "cat $plugin/skills/_shared/mr-description.md"
  exit 0
fi

if [ "$status" != review ]; then
  emit "Step 15 of 16: self-report $id" "$id is review with mr_url set, and the report is in."
  cmd "$bin/state-report.sh --task $id --set-status review --message 'chore($id): review, MR open'"
  exit 0
fi

emit "Step 16 of 16: knowledge review for $id" "this session's lessons and decisions are judged and the proposals written."
cmd "cat $plugin/skills/_shared/knowledge-review.md"
cmd "sed -n 's/^curation:[[:space:]]*//p' $state/factory.yml"
cmd "$bin/curate-apply.sh --help"
