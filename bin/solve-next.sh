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
# in `changes_requested` is a fix round. That holds for a task already stacked (a block whose progress file
# records `base: block/...`). Every other task cuts its blocks from the work branch, one wave at a time, and puts
# each one up through block-verify.sh, the code-reviewer and the architecture-auditor, then block-mr.sh: a block
# in `review` with an `mr_url` does not hold the blocks of its own wave, and before a block of a later wave is
# cut, step 11 is the automatic merge of the waiting block MRs through block-mr-merge.sh (a high-risk one after
# the human's yes). Step 14 is then the task MR the human reviews and merges.
#
# A parent with `request:` is charted first: while no plan-ready file exists and `map.sh clear <R-id>` does not
# exit 0 or the map is not yet `planned` or later, the step is 3b, the request map of skills/wayfinder; the grill of step 4 is then seeded by
# `map.sh export <R-id> <key>`.
#
# It prints exactly one step of skills/factory/references/solve.md: a `## Step <n> ...` heading, one line
# beginning `Completion:`, and under `Commands:` the commands to run, two spaces in front of each. The work
# root is the parent directory of the state clone, so every path printed is absolute: `<root>/<key>/T-NNN` is
# the session worktree, `<root>/<key>/T-NNN-NN` a block worktree, `<root>/<key>/.harness/T-NNN` the scratch
# directory of the run.
#
# The state a step is read off, in the order the steps are tried: no `tier` is step 3, and so is no plan-ready
# file on a feature, bugfix or refactor with no `## Related issues`; no plan-ready file is step 3b while the
# parent's request map is not clear or its `Status:` is still charting or grilling, else step 4 (the plan-ready file is the one whose
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
request=$(fm "$task" request)

triage_step() {
  emit "Step 3 of 16: triage $id" "tier and archetype are set on $id and ## Related issues is written for a feature, bugfix or refactor."
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
# why: step 4 has written ## Related issues (feature, bugfix and refactor only), and charting only once the chart
# why: session has moved the map past charting and grilling, which it does when the map is clear
triaged() {
  case "$archetype" in feature|bugfix|refactor) grep -q '^## Related issues[[:space:]]*$' "$task" ;; esac
}
charted() {
  sh "$bin/map.sh" clear "$request" --state "$state" >/dev/null 2>&1 || return 1
  case "$(awk '/^Status:/ { print $2; exit }' "$state/requests/$request/map.md")" in
    planned|queued|running|done) ;;
    *) return 1 ;;
  esac
}

if [ -z "$slug" ] || [ ! -f "$plan" ]; then
  triaged || triage_step
  # why: the request map is one per request and decides what every parent of it shares, so no grill starts on
  # why: a parent while a ticket of the map is open or fog is left on it
  if [ -n "$request" ] && ! charted; then
    emit "Step 3b of 16: chart $request" "$bin/map.sh clear $request exits 0: no ticket of $state/requests/$request/map.md is open or claimed and nothing is left under Not yet specified."
    cmd "cat $plugin/skills/wayfinder/SKILL.md"
    if [ -f "$state/requests/$request/map.md" ]; then
      cmd "cat $state/requests/$request/map.md"
      cmd "$bin/map.sh frontier $request --state $state"
    else
      cmd "$bin/map.sh new $request --destination '<the request in one or two lines>' --state $state"
    fi
    exit 0
  fi
  emit "Step 4 of 16: grill $id" "no open gaps, the program design is approved and $state/repos/$key/plans/<slug>-plan-ready.md exists with task: $id${request:+ and request: $request} in its frontmatter."
  cmd "cat $plugin/skills/grill/SKILL.md"
  [ -z "$request" ] || cmd "$bin/map.sh export $request $key --state $state"
  cmd "cat $task"
  exit 0
fi

blocks=$(task_files | while IFS= read -r f; do
  b=$(fm "$f" id)
  if is_block_of "$id" "$b"; then printf '%s\n' "$b"; fi
done | sort_ids)

product=$(clone_path "$key")
verdict="$state/repos/$key/verdicts/$slug.md"

# why: task-new.sh refuses the block writes of step 8 without a verdict whose plan_hash still matches, so
# why: the curation is the next step and not a note beside a later one; decompose deletes the verdict once it
# why: writes the blocks, so a parent with blocks is past this step
if [ -z "$blocks" ] && [ -n "$product" ] && [ -d "$product/docs/architecture" ] && [ ! -f "$verdict" ]; then
  emit "Step 5 of 16: architect plan-check of $slug" "$verdict records a verdict whose plan_hash is the current hash of $plan."
  cmd "cat $plugin/skills/architect-review/SKILL.md"
  cmd "sha256sum $plan"
  exit 0
fi

if [ -z "$blocks" ]; then
  emit "Step 6 of 16: decompose $id into blocks" "every block of the cut is a draft T-NNN-NN file, at most 12 of them, each with its depends_on."
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
  { wave_lines | grep -oE "$id-[0-9]{2,}" || :
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
  elif [ "${FACTORY_ROLE:-}" = repo-lead ] && { [ ! -e "$bwt/.git" ] || [ "$bs" = ready ]; }; then
    # why: a lead herds its blocks as sessions and session-monitor.sh claims each one it starts; a claim of the
    # why: lead's own leaves it no ready block to dispatch (F36)
    emit "Step 11 of 16: dispatch wave ${wave:-1} of $id" "every ready block of the wave printed <id> spawned from session-monitor.sh, which claimed it for its session."
    [ -e "$bwt/.git" ] || cmd "$bin/worktree-add.sh $pending"
    cmd "$bin/session-monitor.sh --task $id$wave_arg --spawn herdr"
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
  emit "Step 11 of 16: merge the block MRs of $id" "every block below is done: block-mr-merge.sh has merged its MR into ${branch:-the work branch}, pulled the parent worktree and set the block done; exit 3 is a block whose MR rates the risk high, merged only after the human's yes (_shared/ask.md) by the same line with --confirmed; a class C forge prints <block> auto-merge <url>, and the line runs again once the forge has merged it. The next wave is cut from the work branch once this one is merged."
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

if ! grep -q '^## Evidence' "$progress" 2>/dev/null; then
  emit "Step 12 of 16: acceptance and quality over $id" "the parent's ## Acceptance is green verbatim, format and arch-build are recorded under ## Evidence in $progress, and crap is a gate, not a recording: no changed method is over the toolset's crap-threshold, every method skipped or exempt under _shared/test-exemptions.md is listed by name in ## Quality, and a method still over it carries its reason in the note."
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
  emit "Step 13 of 16: integrated review of $id" "a verdict from code-reviewer is under ## Review in $progress, its brief carrying the block-verify reports, the ## Quality table and the ## Duplication candidates, spawned after the last block is merged and before the MR (ADR-0053), in parallel with a docs subagent bounded to the parent's ## Docs paths, never code or tests, its commit serialised with the coordinator's, because docs landing after the MR is a follow-up commit the verdict never covered; a changes needed verdict gets one fix block and the reviewer once more, and that second verdict is recorded but does not stop the flow."
  cmd "mkdir -p $harness"
  cmd "git -C $worktree diff origin/$base...${branch:-HEAD} > $harness/review.diff"
  cmd "$bin/model-for.sh review $tier '' 0 $complexity"
  cmd "cat $plugin/skills/_shared/delegation.md"
  exit 0
fi

if [ -z "$mr_url" ]; then
  emit "Step 14 of 16: the task MR of $id for the human's review" "the MR of $id into $base exists with no conflicts and lists every block MR under ## Blocks, or the branch is merge-ready without a forge, and the human has been asked to review and merge it; done follows the merge."
  cmd "git -C $worktree fetch origin"
  cmd "git -C $worktree rebase origin/$base"
  cmd "git -C $worktree push --force-with-lease origin ${branch:-HEAD}"
  cmd "cat $plugin/skills/_shared/mr-description.md"
  cmd "$bin/mr-open.sh $id --state $state"
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
