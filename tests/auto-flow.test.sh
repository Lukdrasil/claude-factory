#!/bin/sh
# The auto lane (skills/factory/references/auto.md): solve-next.sh --auto is the herd with step 4a in front of
# the grill, two solution sessions and the human's pick, and refuses to pass triage while the toolset binds no
# crap; from the pick on the grill and decompose go out with --auto, the approval and a blocked block take no
# ask, step 12 names the e2e binding, and step 14 opens the MR with --decisions. session-monitor.sh dispatches
# the solution steps on their models at effort medium, herdr-tabs.sh names them, herd-watch.sh tracks them and
# the guard keeps them read-only in the task worktree. The skills carry their auto sections.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$root/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR HERDR_ENV HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_PANE_ID FACTORY_CLAUDE_ARGS FACTORY_UNIT

fail=0
check() { # <what> <pattern> <output>
  if printf '%s\n' "$3" | grep -q "$2"; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
no() { # <what> <pattern> <output>
  if printf '%s\n' "$3" | grep -q "$2"; then printf 'FAIL %s\n' "$1"; fail=1; else printf 'PASS %s\n' "$1"; fi
}

froot="$tmp/factory"
state="$froot/state"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/plans" "$state/repos/demo/progress" "$state/repos/demo/research"
printf 'demo: {url: https://github.com/o/demo.git, default_branch: main}\n' > "$state/repos.yml"

parent() { # <id> <status> <context line>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: $2
archetype: feature
tier: yellow
complexity: medium
---

# Goal
feat(demo): $1

## Context
$3

## Related issues

none
EOF
}
block() { # <id> <status>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: $2
archetype: feature
tier: green
complexity: low
mr_url: null
---

# Goal
feat(demo): $1
EOF
}

# --- step 4a: no crap row, two solutions, the pick ----------------------------------------------------------
parent T-020 triaged 'the export'
printf '| command | binding |\n|---|---|\n| `build` | `make` |\n| `test` | `make test` |\n' > "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a toolset with no crap row stops before the solutions' '^## Step 4a of 16: the toolset of demo binds no crap$' "$out"
check 'auto: the stop names the row to add' 'Completion:.*`crap <scope>` row' "$out"
no 'auto: nothing is dispatched without the crap row' 'session-monitor\.sh' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: the toolset is not checked outside the auto lane' '^## Step 4 of 16: grill T-020$' "$out"

printf '| crap <scope> | crap <scope> |\n' >> "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a crap row without backticks is a crap row, as block-verify reads it' '^## Step 4a of 16: two solutions for T-020$' "$out"
sed -i '$d' "$state/repos/demo/toolset.md"
printf '| `crap <scope>` | |\n' >> "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a crap row with an empty cell binds nothing' '^## Step 4a of 16: the toolset of demo binds no crap$' "$out"
sed -i '$d' "$state/repos/demo/toolset.md"
printf '| `crap <scope>` | `crap "<scope>"` |\n' >> "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: with a crap row step 4a dispatches the solutions' '^## Step 4a of 16: two solutions for T-020$' "$out"
check 'auto: the open solution goes out' "session-monitor\.sh --task T-020 --step solution-open --state $state\$" "$out"
check 'auto: the minimal solution goes out' "session-monitor\.sh --task T-020 --step solution-min --state $state\$" "$out"
check 'auto: the watcher follows them, once' 'herd-watch\.sh T-020 --interval 60' "$out"
[ "$(printf '%s\n' "$out" | grep -c 'herd-watch\.sh T-020')" = 1 ]; r=$?
check 'auto: one watch line for two dispatches' '^0$' "$r"
check 'auto: step 4a opens with state-push.sh' "^  .*state-push\.sh --state $state\$" "$(printf '%s\n' "$out" | sed -n '/^Commands:$/{n;p;}')"

printf '\n## Solution\nthe issue author wrote this heading\n' >> "$state/repos/demo/tasks/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a ## Solution heading without a view line is no pick' '^## Step 4a of 16: two solutions for T-020$' "$out"
printf '\n## Steps\n1. the issue author wrote this too\n\n## Solution\n- view: open\n- file: repos/demo/research/T-020-solution-open.md\n' >> "$state/repos/demo/tasks/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: the lane'"'"'s pick below the issue heading and another heading is still the pick' '^## Step 4 of 16: grill T-020$' "$out"
sed -i '/^## Solution$/,$d' "$state/repos/demo/tasks/T-020.md"
# the state clone is a git repo from here: a solution file counts once it is committed
git -C "$state" init -q 2>/dev/null; git -C "$state" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false add -A >/dev/null 2>&1
git -C "$state" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m fixture >/dev/null 2>&1
printf '# Solution (open) for T-020\n' > "$state/repos/demo/research/T-020-solution-open.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a solution file not yet committed is dispatched again' '\-\-step solution-open' "$out"
git -C "$state" add -A >/dev/null 2>&1 && git -C "$state" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'research: open' >/dev/null 2>&1
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
no 'auto: a committed solution is not dispatched again' '\-\-step solution-open' "$out"
check 'auto: the missing one still goes out' '\-\-step solution-min' "$out"
check 'auto: a session gone twice with no file is the human'"'"'s' 'Completion:.*gone twice with no file is _shared/blocked-question\.md to the human' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: a session gone twice leaves the pick to the one file, with its view and file lines' 'Completion:.*its lines - view: <open|min>, - file: <that file>, - chosen by: agent' "$out"
check 'autonom: both gone twice is the human'"'"'s' 'Completion:.*both gone twice with no file is _shared/blocked-question\.md to the human' "$out"

printf '# Solution (min) for T-020\n' > "$state/repos/demo/research/T-020-solution-min.md"
git -C "$state" add -A >/dev/null 2>&1 && git -C "$state" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'research: min' >/dev/null 2>&1
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: both files present is the pick' '^## Step 4a of 16: the human picks the solution for T-020$' "$out"
check 'auto: the pick goes through the ask rule' 'Completion:.*_shared/ask\.md' "$out"
check 'auto: the pick is the consent for the lane' 'Completion:.*consent' "$out"
check 'auto: both files are shown' "^  cat $state/repos/demo/research/T-020-solution-open\.md\$" "$out"
check 'auto: the reference is read' 'skills/factory/references/auto\.md' "$out"
check 'auto: the pick is reported without a status' "state-report\.sh --task T-020 --no-status" "$out"
no 'auto: no grill before the pick' '\-\-step grill' "$out"

out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: the monitor picks' '^## Step 4a of 16: the monitor picks the solution for T-020$' "$out"
check 'autonom: over the analysis table' 'Completion:.*one row per solution' "$out"
check 'autonom: chosen by the agent' 'Completion:.*chosen by: agent' "$out"
check 'autonom: the decision rule is read' "^  cat $root/skills/_shared/auto-decision\.md\$" "$out"
no 'autonom: nobody is asked' '_shared/ask\.md' "$out"
printf '\n## Solution\n- view: min\n- file: repos/demo/research/T-020-solution-min.md\n- the human'"'"'s words: as written\n' >> "$state/repos/demo/tasks/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: the pick written is the grill' '^## Step 4 of 16: grill T-020$' "$out"
check 'auto: the grill goes out with --auto' "session-monitor\.sh --task T-020 --step grill --auto --state $state\$" "$out"
check 'auto: the completion names plan-lint --auto' 'Completion:.*plan-lint\.sh --auto' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: the grill goes out with --autonom' "session-monitor\.sh --task T-020 --step grill --autonom --state $state\$" "$out"
check 'auto: the grill completion names the decision rule' 'Completion:.*_shared/auto-decision\.md' "$out"
check 'auto: and the tests every proposal names' 'Completion:.*tests that cover' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: the grill goes out without --auto' "session-monitor\.sh --task T-020 --step grill --state $state\$" "$out"
out=$(sh "$bin/solve-next.sh" T-020 --state "$state" 2>&1)
no 'solve: step 4a is not a step of solve' 'Step 4a' "$out"

# --- step 6: decompose with --auto; step 9 without the ask; step 11 blocked by recommendation ---------------
mkdir -p "$tmp/product"
printf 'demo: {url: https://github.com/o/demo.git, default_branch: main, path: %s}\n' "$tmp/product" > "$state/repos.yml"
plan_body() { # <task> <steps sub-bullets>
  cat <<EOF
---
repo: demo
task: $1
---

# Spec
x.

## Decisions
- one exporter per format: the API resolves it by content type

## Program design

## Proposed tasks

### 1. the exporter
- tier: green, small
- archetype: feature
- complexity: low, local
- depends_on: []
- goal: feat(demo): the exporter
- context: x
- acceptance: \`make test\`
- docs: none
- design: none
- steps:
$2
- out of scope: y

## Gap ledger
| # | type | question | deps | state | answer |
|---|---|---|---|---|---|
| 1 | decision | q | - | closed | a |
EOF
}
plan_body T-020 '  - wire it' > "$state/repos/demo/plans/export-plan-ready.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a plan without the test lines goes back to the grill' '^## Step 4 of 16: the plan of T-020 misses the auto musts$' "$out"
check 'auto: with the lint lines shown' '^  # plan-lint: proposal 1 names no test' "$out"
check 'auto: and the grill dispatched again' '\-\-step grill --auto' "$out"
no 'auto: plan-check is not dispatched over such a plan' '\-\-step plan-check' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
no 'herd: the auto musts are not asked of a herd plan' 'misses the auto musts' "$out"
plan_body T-020 '  - wire it
  - test tests/exporter.test.sh: one row
  - no e2e' > "$state/repos/demo/plans/export-plan-ready.md"
mkdir -p "$tmp/product/docs/architecture"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: plan-check goes out with --auto' "session-monitor\.sh --task T-020 --step plan-check --auto --state $state\$" "$out"
mkdir -p "$state/repos/demo/verdicts"
printf -- '---\nverdict: misaligned\nplan: repos/demo/plans/export-plan-ready.md\nplan_hash: %s\n---\n' "$(sha256sum "$state/repos/demo/plans/export-plan-ready.md" | cut -d' ' -f1)" > "$state/repos/demo/verdicts/export.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a misaligned verdict with the current hash stops the lane' '^## Step 5 of 16: plan-check found export misaligned$' "$out"
check 'auto: with the findings shown' "^  cat $state/repos/demo/verdicts/export\.md\$" "$out"
no 'auto: and nothing dispatched' 'session-monitor\.sh' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: a misaligned verdict is decompose, where a human may override it' '^## Step 6 of 16: decompose T-020' "$out"
# no sha256 tool at all is a stop naming it, not a stale verdict forever
mkdir -p "$tmp/nosha"
for d in /usr/local/bin /usr/bin /bin; do
  for f in "$d"/*; do
    case "${f##*/}" in sha256sum|shasum|openssl) continue ;; esac
    [ -e "$tmp/nosha/${f##*/}" ] || ln -s "$f" "$tmp/nosha/${f##*/}" 2>/dev/null || :
  done
done
out=$(PATH="$tmp/nosha" sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1); rc=$?
check 'auto: with no sha256 tool on PATH the loop stops and names the tool' 'no sha256 tool on PATH' "$out"
no 'auto: and prints no step' '^## Step' "$out"
[ "$rc" != 0 ]; r=$?; check 'with a non-zero exit' '^0$' "$r"
printf '\n' >> "$state/repos/demo/plans/export-plan-ready.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a verdict over an edited plan is stale, and plan-check runs again' '^## Step 5 of 16: architect plan-check of export$' "$out"
check 'auto: which says it is stale' 'Completion:.*stale' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: a stale verdict is plan-check again too' '^## Step 5 of 16: architect plan-check of export$' "$out"
rm "$state/repos/demo/verdicts/export.md"
rm -r "$tmp/product/docs"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: decompose goes out with --auto' "session-monitor\.sh --task T-020 --step decompose --auto --state $state\$" "$out"

# a task with a plan but no ## Solution has no pick to call its consent: the auto lane keeps the herd's gates
parent T-021 draft 'plans/export21-plan-ready.md'
plan_body T-021 '  - wire it
  - test tests/e.test.sh: x
  - no e2e' > "$state/repos/demo/plans/export21-plan-ready.md"
block T-021-01 draft
printf 'wave 1: T-021-01\n' > "$state/repos/demo/progress/T-021.md"
out=$(sh "$bin/solve-next.sh" T-021 --auto --state "$state" 2>&1)
check 'auto without a pick: step 9 keeps the ask' 'references/approve\.md' "$out"
no 'auto without a pick: nothing is called a consent' 'consent' "$out"
out=$(sh "$bin/solve-next.sh" T-021 --autonom --state "$state" 2>&1)
check 'autonom needs no pick: step 9 approves without an ask' 'Completion:.*without an ask' "$out"

block T-020-01 draft
printf 'wave 1: T-020-01\n' > "$state/repos/demo/progress/T-020.md"
sed -i 's/^status: triaged$/status: draft/' "$state/repos/demo/tasks/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 9 approves without an ask' '^## Step 9 of 16: approve and claim T-020$' "$out"
check 'auto: the consent is the pick' 'Completion:.*the human.s pick of step 4a being the consent' "$out"
no 'auto: approve.md is not read' 'references/approve\.md' "$out"
check 'auto: task-approve.sh still covers the parent and the block' 'task-approve\.sh T-020 T-020-01 --state' "$out"
check 'auto: the parent body is printed as the notice' "^  cat $state/repos/demo/tasks/T-020\.md\$" "$out"
check 'auto: the block body too' "^  cat $state/repos/demo/tasks/T-020-01\.md\$" "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: step 9 keeps the ask' 'references/approve\.md' "$out"

sed -i 's/^status: draft$/status: in_progress\nbranch: feat\/T-020-export/' "$state/repos/demo/tasks/T-020.md"
gitclone() { # <dir> <branch>
  git init -q -b "$2" "$1" && git -C "$1" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false \
    commit -q --allow-empty -m init
}
gitclone "$froot/demo/T-020" feat/T-020-export
block T-020-01 blocked
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a blocked block is answered by its recommendation' '^## Step 11 of 16: T-020-01 is blocked$' "$out"
check 'auto: with the decision rule read' 'skills/_shared/auto-decision\.md' "$out"
check 'auto: and the human asked only where it says so' 'Completion:.*asked the human only where' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: a blocked block with no recommendation is analysed' 'Completion:.*your analysis picked' "$out"
block T-020-01 failed
out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: a first failure is analysed' 'Completion:.*your analysis picked' "$out"
check 'autonom: and says every option failing, or a second failure, is the human'"'"'s' 'Completion:.*failed at its second attempt, is the human' "$out"
no 'autonom: no session closes a block' 'set-status closed' "$out"
sed -i 's/^complexity: low$/complexity: low\nattempt: 1/' "$state/repos/demo/tasks/T-020-01.md"
out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: a block failed at its second attempt is the human'"'"'s' '^## Step 11 of 16: T-020-01 is failed at attempt 1$' "$out"
check 'autonom: through the blocked question' 'Completion:.*the human has answered' "$out"
no 'autonom: and not analysed again' 'your analysis picked' "$out"
check 'autonom: the retry is still approved after the answer' 'task-approve\.sh T-020-01 --state' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
no 'herd: a blocked block stays the human'"'"'s' 'auto-decision\.md' "$out"
# a blocked block answered by the lane once is the human's when it comes back blocked
block T-020-01 blocked
mkdir -p "$state/repos/demo/progress"
printf '## Question\nwhich\n\n**Answer (2026-10-01): option 2** (analysed)\n' > "$state/repos/demo/progress/T-020-01.md"
out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: a block blocked again after an answer of the lane is the human'"'"'s' '^## Step 11 of 16: T-020-01 is blocked again, after 1 answer of the lane$' "$out"
check 'autonom: through the blocked question' 'Completion:.*the human has answered' "$out"
no 'autonom: and not analysed a second time' 'your analysis picked' "$out"
printf '## Question\nwhich\n\n**Answer (2026-10-01): option 2** (human)\n' > "$state/repos/demo/progress/T-020-01.md"
out=$(sh "$bin/solve-next.sh" T-020 --autonom --state "$state" 2>&1)
check 'autonom: a block blocked again after a human answer is analysed' 'Completion:.*your analysis picked' "$out"
rm "$state/repos/demo/progress/T-020-01.md"
# a block MR with changes requested is verified and its MR refreshed over the fixes before it is review again
block T-020-01 changes_requested
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: changes requested on a block MR runs block-verify again' "^  $bin/block-verify\.sh T-020-01 --state $state\$" "$out"
check 'auto: and block-mr.sh refreshes the MR from the new report' "^  $bin/block-mr\.sh T-020-01 --state $state\$" "$out"
check 'auto: before the block is review again' 'Completion:.*block-verify\.sh is green again over the new head' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: the same gates on changes requested' "^  $bin/block-verify\.sh T-020-01 --state $state\$" "$out"
block T-020-01 draft
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a draft block after the pick is approved without an ask' 'Completion:.*without an ask' "$out"
no 'auto: and approve.md is not read for it' 'references/approve\.md' "$out"

# --- step 12 names e2e, step 14 opens with --decisions --------------------------------------------------------
block T-020-01 done
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 12 without an e2e row records that there is none' 'Completion:.*binds no e2e' "$out"
printf '| `e2e` | `make e2e` |\n' >> "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 12 with an e2e row runs it' 'Completion:.*e2e binding ran green' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
no 'herd: step 12 says nothing of e2e' 'e2e' "$out"
printf 'wave 1: T-020-01\n## Evidence\nok\n## Duplication\nnone\n' > "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 13 asks for the blocks line under ## Review' 'Completion:.*blocks: T-020-01 ' "$out"
no 'auto: step 13 refreshes no MR before there is one' 'mr-open\.sh' "$out"
printf 'wave 1: T-020-01\n## Evidence\nok\n## Duplication\nnone\n## Review\nblocks: T-020-01\nok\n' > "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 14 opens the MR with the decisions' "mr-open\.sh T-020 --decisions --state $state\$" "$out"
check 'auto: the completion names the ## Decisions section' 'Completion:.*## Decisions' "$out"
check 'auto: a review round is the fix round without an ask' 'Completion:.*without an ask' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: step 14 opens the MR without the decisions' "mr-open\.sh T-020 --state $state\$" "$out"

# the fix round after the MR: a block done after the review brings steps 12 and 13 back, and 13 refreshes the MR
sed -i 's/^status: in_progress$/status: review/; s/^complexity: medium$/complexity: medium\nmr_url: https:\/\/forge.test\/mr\/20/' "$state/repos/demo/tasks/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: with the MR open and every done block reviewed, step 16' '^## Step 16 of 16' "$out"
block T-020-02 done
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a fix block done after the review is the fix round' '^## Step 12 of 16: fix round over T-020, after the task MR$' "$out"
check 'auto: which names the block' 'Completion:.* T-020-02 merged' "$out"
check 'auto: and resets the four sections' "^  sed -i .*## Evidence.*## Quality.*## Duplication.*## Review.* $state/repos/demo/progress/T-020\.md\$" "$out"
reset_cmds() { printf '%s\n' "$1" | sed -n 's/^  \(sed -i .*\|grep -q .*\|awk -v l=.*\)$/\1/p'; }
eval "$(reset_cmds "$out")"
out=$(cat "$state/repos/demo/progress/T-020.md")
check 'the reset keeps the wave plan' '^wave 1: T-020-01$' "$out"
no 'the reset drops ## Review' '^## Review' "$out"
no 'the reset drops ## Evidence' '^## Evidence' "$out"
check 'the reset records the round' '^- round 1 (after the task MR): T-020-02$' "$out"
check 'under ## Fix rounds' '^## Fix rounds$' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 12 runs again after the reset' '^## Step 12 of 16: acceptance and quality over T-020$' "$out"
printf '## Evidence\nok\n## Duplication\nnone\n' >> "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 13 lists both done blocks' 'Completion:.*blocks: T-020-01 T-020-02 ' "$out"
check 'auto: and refreshes the MR body with the decisions' "mr-open\.sh T-020 --decisions --state $state\$" "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: the fix round refreshes the body without the decisions' "mr-open\.sh T-020 --state $state\$" "$out"
printf '## Review\nblocks: [`T-020-01`, `T-020-02`]\nok\n' >> "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: once reviewed, a bracketed and backticked blocks line too, step 16 again' '^## Step 16 of 16' "$out"
sed -i '/^## Review/,$d' "$state/repos/demo/progress/T-020.md"
printf '## Review\nblocks: T-020-01,\n  T-020-02\nok\n' >> "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a blocks line wrapped over a second line names them all, step 16' '^## Step 16 of 16' "$out"
sed -i '/^## Review/,$d' "$state/repos/demo/progress/T-020.md"
printf '## Review\nblocks: T-020-01\n\nT-020-02 is not covered\nok\n' >> "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: an id after a blank line is prose, not the blocks line: the fix round' '^## Step 12 of 16: fix round over T-020, after the task MR$' "$out"
sed -i '/^## Review/,$d' "$state/repos/demo/progress/T-020.md"
printf '## Review\nblocks: T-020-01 T-020-02\nok\n' >> "$state/repos/demo/progress/T-020.md"
# the fix round before the MR: a changes-needed fix block merged at step 11 brings 12, 12b and 13 back before 14
sed -i 's/^status: review$/status: in_progress/; /^mr_url:/d' "$state/repos/demo/tasks/T-020.md"
block T-020-04 done
printf 'wave 1: T-020-01\n## Evidence\nok\n## Quality\n| m | 1 | |\n## Duplication\nnone\n## Review\nblocks: T-020-01 T-020-02\nchanges needed\n' > "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: a fix block done before the MR is the fix round too' '^## Step 12 of 16: fix round over T-020, before the task MR$' "$out"
check 'auto: which names the block' 'Completion:.* T-020-04 merged' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
# step 13 before any round: the first verdict is recorded with its blocks: line before the fix block is cut
printf 'wave 1: T-020-01\n## Evidence\nok\n## Quality\n| m | 1 | |\n## Duplication\nnone\n' > "$tmp/t020-no-review.md"
cp "$state/repos/demo/progress/T-020.md" "$tmp/t020-review.md"
cp "$tmp/t020-no-review.md" "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 13 with no round yet records the verdict before the fix block is cut' 'Completion:.*cut after that line is written' "$out"
no 'auto: and does not call it the second verdict' 'no further fix block' "$out"
cp "$tmp/t020-review.md" "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
eval "$(reset_cmds "$out")"
out=$(cat "$state/repos/demo/progress/T-020.md")
no 'the reset drops ## Quality too' '^## Quality' "$out"
check 'the reset keeps the wave plan' '^wave 1: T-020-01$' "$out"
check 'the reset records the round before the MR' '^- round 1 (before the task MR): T-020-04$' "$out"
check 'under the one ## Fix rounds section' '^1$' "$(printf '%s\n' "$out" | grep -c '^## Fix rounds$')"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 12 runs again before the MR' '^## Step 12 of 16: acceptance and quality over T-020$' "$out"
# step 13 after the round before the MR: the second verdict is recorded and the flow goes on
printf '## Evidence\nok\n## Quality\n| m | 1 | |\n## Duplication\nnone\n' >> "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 13 after the round before the MR is the second verdict' '^## Step 13 of 16: integrated review of T-020$' "$out"
check 'auto: which is recorded and the flow goes on' 'Completion:.*no further fix block is cut before the MR' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: the same rule' 'Completion:.*no further fix block is cut before the MR' "$out"
rm "$state/repos/demo/tasks/T-020-04.md"
sed -i 's/^status: in_progress$/status: review/; s/^complexity: medium$/complexity: medium\nmr_url: https:\/\/forge.test\/mr\/20/' "$state/repos/demo/tasks/T-020.md"
printf 'wave 1: T-020-01\n## Evidence\nok\n## Duplication\nnone\n## Review\nblocks: T-020-01 T-020-02\nok\n' > "$state/repos/demo/progress/T-020.md"
# a closed last block (a research block, or a block the human closed) does not end the step under set -e
block T-020-03 closed
sed -i '/^## Review/,$d' "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1); rc=$?
check 'herd: step 13 with a closed last block still prints' '^## Step 13 of 16: integrated review of T-020$' "$out"
check 'and lists only the done blocks' 'Completion:.*blocks: T-020-01 T-020-02 (' "$out"
[ "$rc" = 0 ]; r=$?; check 'with exit 0' '^0$' "$r"
rm "$state/repos/demo/tasks/T-020-03.md"
printf '## Review\nblocks: T-020-01 T-020-02\nok\n' >> "$state/repos/demo/progress/T-020.md"
sed -i 's/^status: review$/status: in_progress/; /^mr_url:/d' "$state/repos/demo/tasks/T-020.md"
rm "$state/repos/demo/tasks/T-020-02.md"

# --- session-monitor.sh: the solution steps, their models and effort, --auto on grill and decompose ----------
gitclone "$tmp/product" main
out=$(sh "$bin/session-monitor.sh" --task T-020 --step solution-open --state "$state" 2>/dev/null)
check 'the open solution runs in the task worktree' "^T-020-solution-open printed $froot/demo/T-020\$" "$out"
check 'on claude-opus-5-5 at effort medium' 'claude --model claude-opus-5-5 --effort medium --name ' "$out"
check 'with the solution skill and the open view' '"/claude-factory:solution [^"]*T-020\.md --view open"$' "$out"
check 'as FACTORY_ROLE=solution-open' 'FACTORY_ROLE=solution-open FACTORY_UNIT=T-020-solution-open ' "$out"
check 'named with the open emoji' 'name "💡 [^ ]* demo T-020-solution-open"' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step solution-min --state "$state" 2>/dev/null)
check 'the minimal solution runs in the task worktree too' "^T-020-solution-min printed $froot/demo/T-020\$" "$out"
check 'on claude-fable-5-1 at effort medium' 'claude --model claude-fable-5-1 --effort medium --name ' "$out"
check 'with the min view' '"/claude-factory:solution [^"]*T-020\.md --view min"$' "$out"
check 'named with the min emoji' 'name "🪛 [^ ]* demo T-020-solution-min"' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step grill --state "$state" 2>/dev/null)
check 'a grill step carries no effort of its own' 'claude --model opus --name ' "$out"
check 'and no --auto without the flag' '"/claude-factory:grill [^"]*T-020\.md"$' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step grill --auto --state "$state" 2>/dev/null)
check '--auto puts --auto on the grill prompt' '"/claude-factory:grill [^"]*T-020\.md --auto"$' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step decompose --auto --state "$state" --dry-run 2>/dev/null)
check '--auto puts --auto on the decompose prompt' '"/claude-factory:decompose [^"]*export-plan-ready\.md --auto"$' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step plan-check --auto --state "$state" --dry-run 2>/dev/null)
check '--auto puts --auto on the plan-check prompt' '"/claude-factory:architect-review plan-check [^"]*export-plan-ready\.md --auto"$' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step grill --autonom --state "$state" --dry-run 2>/dev/null)
check '--autonom puts --autonom on the grill prompt' '"/claude-factory:grill [^"]*T-020\.md --autonom"$' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step solution-open --auto --state "$state" --dry-run 2>/dev/null)
check '--auto leaves a solution prompt alone' '"/claude-factory:solution [^"]*T-020\.md --view open"$' "$out"
out=$(sh "$bin/session-monitor.sh" --task T-020 --step solution --state "$state" 2>&1)
check 'a step must name its view' "takes triage, solution-open, solution-min, grill" "$out"

# a herdr spawn passes the effort to agent start, and the close before start covers the solution tabs
( . "$(dirname -- "$0")/herdr-stub.sh"
  herdr_stub "$tmp/stub"
  : > "$HERDR_STUB_LOG"
  HERDR_TAB_ID=tab-mon sh "$bin/session-monitor.sh" --task T-020 --step solution-min --spawn herdr --state "$state" >/dev/null 2>&1
  log=$(cat "$HERDR_STUB_LOG")
  check 'a herdr spawn starts the agent on its model at effort medium' \
    '^agent start solution-min_t-020 .* -- --model claude-fable-5-1 --effort medium --name ' "$log"
  check 'the tab is created with the solution-min role' '^tab create .*--env FACTORY_ROLE=solution-min ' "$log"
  mkdir -p "$froot/demo/.harness/T-020"
  printf 'T-020-solution-open tab-5 pane-5\n' >> "$froot/demo/.harness/T-020/herdr-tabs"
  herdr_tab tab-5 idle false solution-open_t-020
  : > "$HERDR_STUB_LOG"
  HERDR_TAB_ID=tab-mon sh "$bin/session-monitor.sh" --task T-020 --step solution-min --spawn herdr --state "$state" >/dev/null 2>&1
  no 'dispatching one solution step keeps the sibling solution tab' '^tab close tab-5 ' "$(cat "$HERDR_STUB_LOG")"
  : > "$HERDR_STUB_LOG"
  HERDR_TAB_ID=tab-mon sh "$bin/session-monitor.sh" --task T-020 --step grill --spawn herdr --state "$state" >/dev/null 2>&1
  check 'the grill closes an idle solution tab before it starts' '^tab close tab-5 ' "$(cat "$HERDR_STUB_LOG")"
  # herd-watch tracks the solution steps as units
  rec_dir="$froot/demo/.harness/T-020"
  printf 'T-020-solution-min tab-6 pane-6 sid-6\n' >> "$rec_dir/herdr-tabs"
  herdr_agent solution-min_t-020 working pane-6 sid-6
  out=$(sh "$bin/herd-watch.sh" T-020 --once --no-mr --state "$state")
  check 'herd-watch tracks the minimal solution step' '^T-020-solution-min agent working$' "$out"
  exit "$fail"
) || fail=1

# the guard: a solution session writes the state clone and not the task worktree, like a grill session
W="$tmp/guard"
mkdir -p "$W/state/repos/cf/tasks" "$W/state/repos/cf/research" "$W/cf/T-950"
printf 'cf: {url: https://github.com/o/cf.git, default_branch: main}\n' > "$W/state/repos.yml"
# status ready: past the status rule of the guard, so the deny below is the role's
printf -- '---\nid: T-950\nrepo: cf\nstatus: ready\narchetype: feature\ntier: yellow\ncomplexity: medium\n---\n\n# Goal\nfeat(cf): x\n' > "$W/state/repos/cf/tasks/T-950.md"
guard() { # <role> <cwd> <command>
  printf '{"tool_name":"Bash","session_id":"s1","cwd":"%s","tool_input":{"command":"%s"}}' "$2" "$3" \
    | env -u HOME -u CLAUDE_PROJECT_DIR WORK_DIR="$W" FACTORY_ROLE="$1" sh "$bin/policy-guard.sh" 2>&1
  echo "rc=$?"
}
out=$(guard solution-open "$W/cf/T-950" "echo x > $W/state/repos/cf/research/T-950-solution-open.md")
check 'a solution-open session writes the state clone' '^rc=0$' "$out"
sed -i 's/^status: ready$/status: triaged/' "$W/state/repos/cf/tasks/T-950.md"
out=$(guard solution-open "$W/cf/T-950" "echo x > $W/state/repos/cf/research/T-950-solution-open.md")
check 'and at triaged too, where it really runs' '^rc=0$' "$out"
out=$(guard solution-open "$W/cf/T-950" "echo x > $W/cf/T-950/src.cs")
check 'while the triaged task worktree is denied' 'rc=2$' "$out"
sed -i 's/^status: triaged$/status: ready/' "$W/state/repos/cf/tasks/T-950.md"
out=$(guard solution-min "$W/cf/T-950" "echo x > $W/cf/T-950/src.cs")
check 'a solution-min session is denied a write into the task worktree' 'rc=2$' "$out"
check 'and the deny names the role' 'a solution-min session reads the product repo' "$out"

# --- plan-lint --auto: every proposal names its tests and says e2e or no e2e ----------------------------------
plan="$tmp/lint-plan-ready.md"
mkdir -p "$tmp/repos/demo/plans"; plan="$tmp/repos/demo/plans/lint-plan-ready.md"
cat > "$plan" <<'EOF'
---
repo: demo
task: none
---

# Spec
x.

## Program design

## Proposed tasks

### 1. the exporter
- tier: green, small
- archetype: feature
- complexity: low, local
- depends_on: []
- goal: feat(demo): the exporter
- context: x
- acceptance: `make test`
- docs: none
- design: none
- steps:
  - wire it
- out of scope: y

## Gap ledger
| # | type | question | deps | state | answer |
|---|---|---|---|---|---|
| 1 | decision | q | - | closed | a |
EOF
out=$(sh "$bin/plan-lint.sh" "$plan" 2>&1); rc=$?
check 'plan-lint without --auto accepts a proposal with no test line' '^plan ok: 1 proposals$' "$out"
out=$(sh "$bin/plan-lint.sh" "$plan" --auto 2>&1); rc=$?
[ "$rc" = 1 ]; r=$?
check 'plan-lint --auto refuses it' '^0$' "$r"
check 'and names the missing test' 'proposal 1 names no test under `steps:`' "$out"
check 'and the missing e2e line' 'proposal 1 says nothing of e2e' "$out"
sed -i 's/^  - wire it$/  - wire it\n  - test tests\/exporter.test.sh: the export of one row\n  - no e2e/' "$plan"
out=$(sh "$bin/plan-lint.sh" "$plan" --auto 2>&1)
check 'plan-lint --auto passes with a test line and no e2e' '^plan ok: 1 proposals$' "$out"
sed -i 's/^- archetype: feature$/- archetype: research/; /^- steps:$/,/^  - no e2e$/d' "$plan"
out=$(sh "$bin/plan-lint.sh" "$plan" --auto 2>&1)
check 'plan-lint --auto asks no test of a research proposal' '^plan ok: 1 proposals$' "$out"

# --- block-verify: the crap binding runs as the toolset wrote it, and an empty run is red ---------------------
bv="$tmp/bv"
mkdir -p "$bv/state/repos/demo/tasks" "$bv/state/repos/demo/progress" "$bv/demo"
printf 'demo: {url: https://github.com/o/demo.git, default_branch: main}\n' > "$bv/state/repos.yml"
cat > "$bv/state/repos/demo/toolset.md" <<'EOF'
---
stack: dotnet
crap-threshold: 8
test-globs:
  - "**/*.test.sh"
---
| command | binding |
|---|---|
| `coverage` | `echo covered > .coverage` |
| `crap <scope>` | `CRAP_ENV=1 sh crap.sh <scope>` |
EOF
printf -- '---\nid: T-030\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\nbranch: feat/T-030-x\n---\n\n# Goal\nfeat(demo): x\n' > "$bv/state/repos/demo/tasks/T-030.md"
printf -- '---\nid: T-030-01\nrepo: demo\nstatus: in_progress\narchetype: feature\ntier: green\ncomplexity: low\nbranch: block/T-030-01\n---\n\n# Goal\nfeat(demo): x\n' > "$bv/state/repos/demo/tasks/T-030-01.md"
wt="$bv/demo/T-030-01"
git init -q -b feat/T-030-x "$wt"
printf '#!/bin/sh\n# prints one method row per file given, the value from CRAP_VALUE; nothing with CRAP_ENV unset\n[ "${CRAP_ENV:-}" = 1 ] || exit 3\n[ -f .coverage ] || exit 4\nfor f; do printf "%%s.Run %%s\\n" "$f" "${CRAP_VALUE:-2}"; done\n' > "$wt/crap.sh"
printf 'exit 0\n' > "$wt/a.test.sh"
git -C "$wt" add -A && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m base
git -C "$wt" checkout -q -b block/T-030-01
printf 'x\n' > "$wt/src.cs"; printf 'exit 0\n' > "$wt/b.test.sh"
git -C "$wt" add -A && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m change
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'block-verify runs a crap binding that opens with an assignment, over the changed .cs file alone' '^crap:  src\.cs\.Run 2$' "$out"
check 'coverage ran first' '^verdict: green$' "$out"
check 'the report names the head it is of' "^head: $(git -C "$wt" rev-parse HEAD)\$" "$out"
printf 'z\n' > "$wt/Služba two.cs"
printf 'q\n' > "$wt/a\"b.cs"
git -C "$wt" add -A && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'more files'
printf '#!/bin/sh\nprintf "%%s\\n" "$#"\nfor f; do printf "arg.%%s 1\\n" "$(printf %%s "$f" | tr -c "a-zA-Z0-9.\\n" _)"; done\n' > "$wt/crap.sh"
git -C "$wt" add -A && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'counting stub'
sed -i 's/^| `crap <scope>` .*$/| `crap <scope>` | `CRAP_ENV=1 sh crap.sh "<scope>"` |/' "$bv/state/repos/demo/toolset.md"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a row that quotes <scope> (the older template) still hands three files one by one, a space, a quote and a non-ASCII name among them' '^crap:  3$' "$out"
sed -i "s/^| \`crap <scope>\` .*\$/| \`crap <scope>\` | \`CRAP_ENV=1 sh crap.sh '<scope>'\` |/" "$bv/state/repos/demo/toolset.md"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a single-quoted <scope> too' '^crap:  3$' "$out"
printf '#!/bin/sh\n[ "${CRAP_ENV:-}" = 1 ] || exit 3\n[ -f .coverage ] || exit 4\nfor f; do printf "%%s.Run %%s\\n" "$f" "${CRAP_VALUE:-2}"; done\n' > "$wt/crap.sh"
git -C "$wt" add -A && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'row stub'
git -C "$wt" rm -q 'Služba two.cs' 'a"b.cs' && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'fewer files'
sed -i 's/^| `crap <scope>` .*$/| `crap <scope>` | `CRAP_ENV=1 sh crap.sh <scope>` |/' "$bv/state/repos/demo/toolset.md"
sed -i 's/^| `coverage` .*$/| `coverage` | `echo no collector >\&2; exit 5` |/' "$bv/state/repos/demo/toolset.md"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a coverage run that fails is red with its last stderr line' '^crap:  coverage failed: no collector$' "$out"
check 'and no crap ran' '^verdict: red$' "$out"
sed -i 's/^| `coverage` .*$/| `coverage` | `echo covered > .coverage` |/' "$bv/state/repos/demo/toolset.md"
out=$(CRAP_VALUE=11 WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a method over the threshold is red' '^crap:  over 8: src\.cs\.Run 11$' "$out"
[ "$rc" = 1 ]; r=$?; check 'with exit 1' '^0$' "$r"
sed -i 's/^| `crap <scope>` .*$/| `crap <scope>` | `sh crap.sh <scope>` |/' "$bv/state/repos/demo/toolset.md"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a crap run that prints nothing is red, with its exit code' '^crap:  exit 3' "$out"
check 'and the verdict says so' '^verdict: red$' "$out"
# a run that fails but prints something is red too: the output is not a method row and the exit is not 0
printf '#!/bin/sh\necho "Error: coverage file not found"\nexit 1\n' > "$wt/crap.sh"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a crap run that fails with output on stdout is red' '^crap:  exit 1' "$out"
check 'with the verdict red' '^verdict: red$' "$out"
# a tool that exits non-zero because a method is over its threshold reports the rows, not the exit
printf '#!/bin/sh\nfor f; do printf "%%s.Run 12\\n" "$f"; done\nexit 2\n' > "$wt/crap.sh"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a non-zero exit with rows over the threshold reports the rows' '^crap:  over 8: src\.cs\.Run 12$' "$out"
# a path with a space and a dollar is one argument, and no shell
printf '#!/bin/sh\nprintf "%%s\\n" "$#"\nfor f; do printf "arg.%%s 1\\n" "$(printf %%s "$f" | tr -c "a-zA-Z0-9.\\n" _)"; done\n' > "$wt/crap.sh"
mkdir -p "$wt/my dir" && printf 'y\n' > "$wt/my dir/\$(touch PWNED).cs"
git -C "$wt" add -A && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m space
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'two changed source files are two arguments' '^crap:  2$' "$out"
[ ! -e "$wt/PWNED" ]; r=$?; check 'and a path that looks like a command substitution runs nothing' '^0$' "$r"
# a tool that exits 0 with no method row in its output held nothing to the threshold: red
printf '#!/bin/sh\necho "Summary: all files analysed"\n' > "$wt/crap.sh"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a crap run with no method row parsed is red' '^crap:  no method row parsed: Summary: all files analysed$' "$out"
check 'with the verdict red' '^verdict: red$' "$out"
[ "$rc" = 1 ]; r=$?; check 'and exit 1' '^0$' "$r"
# a run over an edit not committed says so, and block-mr.sh refuses it
printf '#!/bin/sh\nfor f; do printf "%%s.Run 1\\n" "$f"; done\n' > "$wt/crap.sh"
git -C "$wt" add -A && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'row stub again'
printf 'y2\n' > "$wt/src.cs"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a run over a change not committed is green on its files' '^verdict: green$' "$out"
check 'and says the worktree is dirty' '^dirty: yes, the worktree holds changes not committed at ' "$out"
check 'the report in .harness carries the line' '^dirty: ' "$(cat "$bv/demo/.harness/T-030-01/verify.txt")"
git -C "$wt" checkout -q -- src.cs
mkdir -p "$wt/.coverage/raw" && printf 'x\n' > "$wt/.coverage/raw/c.xml"
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
no 'an untracked file (the coverage run leaves them) is not dirt' '^dirty:' "$out"
rm -rf "$wt/.coverage"
# a git warning on stderr with exit 0 is no failure
mkdir -p "$bv/gitwrap"
printf '#!/bin/sh\nprintf "warning: exhaustive rename detection was skipped due to too many files.\\n" >&2\nexec /usr/bin/git "$@"\n' > "$bv/gitwrap/git"
chmod +x "$bv/gitwrap/git"
out=$(PATH="$bv/gitwrap:$PATH" WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a git warning on stderr with exit 0 is no failure' '^verdict: green$' "$out"
no 'and not a failed diff' 'git diff .* failed' "$out"
# block-merge.sh --verify runs block-verify.sh over the parent's session worktree: that report is not the block's
before=$(cat "$bv/demo/.harness/T-030-01/verify.txt")
git -C "$wt" worktree add -q --detach "$bv/demo/T-030" feat/T-030-x
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$bv/demo/T-030" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a run over another task'"'"'s worktree reports on stdout' '^block: T-030-01$' "$out"
check 'but leaves the block'"'"'s own verify.txt as it was' "$before" "$(cat "$bv/demo/.harness/T-030-01/verify.txt")"
[ ! -e "$bv/demo/.harness/T-030/verify.txt" ]; r=$?; check 'and writes none for the other task' '^0$' "$r"
git -C "$wt" worktree remove --force "$bv/demo/T-030"
# no source file changed: no crap run, green
git -C "$wt" rm -q 'src.cs' 'my dir/$(touch PWNED).cs' && git -C "$wt" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q -m 'tests only'
out=$(WORK_DIR=$bv sh "$bin/block-verify.sh" T-030-01 --worktree "$wt" --state "$bv/state" --base feat/T-030-x 2>&1); rc=$?
check 'a block with no source file changed runs no crap' '^crap:  no source file changed$' "$out"
check 'and is green on its tests' '^verdict: green$' "$out"

# --- the doctor names a seeded coverage row without Cobertura and a quoted <scope> ---------------------------
dr="$tmp/doctor"
mkdir -p "$dr/state/repos/demo" "$dr/clone"
git init -q "$dr/clone" && git -C "$dr/clone" remote add origin https://example.invalid/demo.git
printf 'demo: { path: %s }\n' "$dr/clone" > "$dr/state/repos.yml"
printf -- '---\nstack: dotnet\ntest-globs:\n  - "**/*Tests.cs"\n---\n\n| command | binding |\n|---|---|\n| `coverage` | `dotnet test && reportgenerator -reporttypes:TextSummary` |\n| `crap <scope>` | `dotnet-crap analyze "<scope>"` |\n' > "$dr/state/repos/demo/toolset.md"
out=$(cd "$dr/clone" && sh "$bin/factory-doctor.sh" --root "$dr" --repo "$dr/clone" 2>&1)
check 'the doctor names a coverage row without a Cobertura report' 'missing: a Cobertura report in the coverage row' "$out"
check 'the doctor names a quoted <scope>' 'missing: an unquoted <scope> in the crap row' "$out"
printf -- '---\nstack: dotnet\ntest-globs:\n  - "**/*Tests.cs"\n---\n\n| command | binding |\n|---|---|\n| `coverage` | `dotnet test && reportgenerator -reporttypes:"TextSummary;Cobertura"` |\n| `crap <scope>` | `dotnet-crap analyze <scope>` |\n' > "$dr/state/repos/demo/toolset.md"
out=$(cd "$dr/clone" && sh "$bin/factory-doctor.sh" --root "$dr" --repo "$dr/clone" 2>&1)
check 'the doctor accepts the 0.19 rows' 'ok: coverage writes the Cobertura report crap reads' "$out"
check 'and the unquoted scope' 'ok: the crap row takes <scope> unquoted' "$out"
tsrow=$(grep -E '^\|[[:space:]]*`coverage`' "$root/toolsets/dotnet.md")
check 'the plugin coverage row writes Cobertura' 'TextSummary;Cobertura' "$tsrow"
check 'and empties its raw results before every run' 'rm -rf .coverage/raw' "$tsrow"
check 'and reads only that run' '-reports:".coverage/raw/' "$tsrow"
# the auto lane gates on the coverage row of a dotnet toolset too
parent T-022 triaged 'a fresh task'
printf -- '---\nstack: dotnet\n---\n| command | binding |\n|---|---|\n| `coverage` | `reportgenerator -reporttypes:TextSummary` |\n| `crap <scope>` | `crap <scope>` |\n' > "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-022 --auto --state "$state" 2>&1)
check 'auto: a dotnet coverage row without Cobertura stops at step 4a' '^## Step 4a of 16: the coverage row of demo writes no Cobertura report$' "$out"
printf -- '---\nstack: dotnet\n---\n| command | binding |\n|---|---|\n| `coverage` | `reportgenerator -reporttypes:"TextSummary;Cobertura"` |\n| `crap <scope>` | `crap <scope>` |\n' > "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-022 --auto --state "$state" 2>&1)
check 'auto: with Cobertura the lane goes on to the solutions' '^## Step 4a of 16: two solutions for T-022$' "$out"

# --- the skills: the auto sections and the solution skill ------------------------------------------------------
grill="$root/skills/grill/SKILL.md"
section=$(awk '/^## / { on = ($0 == "## Auto mode"); next } on { print }' "$grill")
section_grill=$section
check 'the grill has an auto mode' '^`/claude-factory:grill <task file> --auto`' "$section"
check 'the auto grill takes the recommendation under the decision rule' '_shared/auto-decision\.md' "$section"
check 'the auto grill reads the chosen solution' '## Solution' "$section"
check 'the auto grill puts tests into every proposal' 'test <path>: <what it proves>' "$section"
check 'the auto grill marks the human'"'"'s decisions' '(human)' "$section"
check 'the auto grill still asks the UI round' 'references/ui-round\.md' "$section"
ui="$root/skills/grill/references/ui-round.md"
check 'the UI round offers a mockup or the agent' 'agent decides' "$(cat "$ui")"
check 'the UI round writes the mockup under research' 'research/<id>-ui-mockup\.html' "$(cat "$ui")"
check 'the UI round asks for the variant' 'The variant' "$(cat "$ui")"
check 'the grill steps hold the UI round before the design round' 'references/ui-round\.md' "$(awk '/^## / { on = ($0 == "## Steps"); next } on { print }' "$grill")"
check 'the decision rule never takes the UI round for the human' 'surface a person sees' "$(cat "$root/skills/_shared/auto-decision.md")"
check 'the UI round is skipped when the task settles the look' '^## Skipped when the task settles it$' "$(cat "$ui")"
check 'the UI round has the autonom exception' 'Under `--autonom` the `## Autonomous` section' "$(cat "$ui")"
check 'the auto grill runs plan-check with its flag' 'architect-review plan-check <plan> --auto` or `--autonom`' "$section_grill"
check 'auto.md describes the fix round reset solve-next prints' 'Step 12 of 16: fix round over <T-id>' "$(cat "$root/skills/factory/references/auto.md")"
check 'a design link in the task is the variant' 'design or mockup link' "$(cat "$ui")"
check 'the look left to the agent in the task closes the row' 'no mockup' "$(cat "$ui")"
dec="$root/skills/decompose/SKILL.md"
section=$(awk '/^## / { on = ($0 == "## Auto mode"); next } on { print }' "$dec")
check 'decompose has an auto mode' '^`/claude-factory:decompose <plan> --auto`' "$section"
check 'the auto decompose applies the spec-critic edits as written' 'applied as written' "$section"
check 'the auto decompose approves nothing' 'approves nothing' "$section"
rule="$root/skills/_shared/auto-decision.md"
check 'the decision rule takes the recommendation' 'The recommendation is the answer' "$(cat "$rule")"
check 'the decision rule asks when every option fails' 'Every option fails' "$(cat "$rule")"
check 'the decision rule names the MR body' 'mr-open\.sh --decisions' "$(cat "$rule")"
sol="$root/skills/solution/SKILL.md"
check 'the solution skill takes a view' '\-\-view open|min' "$(cat "$sol")"
check 'the solution skill writes under research' 'research/<id>-solution-<view>\.md' "$(cat "$sol")"
check 'the solution skill asks for the tests' '^   ## Tests$' "$(cat "$sol")"
check 'the solution skill asks for the crap stance' 'crap threshold' "$(cat "$sol")"
check 'the solution skill asks nobody' 'ask nobody' "$(cat "$sol")"
auto="$root/skills/factory/references/auto.md"
check 'auto.md names the opus model' '`claude-opus-5-5`' "$(cat "$auto")"
check 'auto.md names the fable model' '`claude-fable-5-1`' "$(cat "$auto")"
check 'auto.md names the e2e run' '`e2e` when the toolset binds one' "$(cat "$auto")"
check 'auto.md opens the MR with the decisions' 'mr-open\.sh <T-id> --decisions' "$(cat "$auto")"
check 'auto.md turns the MR review into fix rounds' 'changes-requested' "$(cat "$auto")"
check 'the factory skill routes auto' '^| `auto` |' "$(cat "$root/skills/factory/SKILL.md")"
check 'the factory skill routes autonom' '^| `autonom` |' "$(cat "$root/skills/factory/SKILL.md")"
check 'auto.md has the autonom section' '^## autonom$' "$(cat "$auto")"
check 'auto.md tells the fix round to drop the four sections so 12 and 13 run again' 'the four sections' "$(cat "$auto")"
check 'auto.md names ## Quality among them' '`## Quality`, `## Duplication` and `## Review` go' "$(cat "$auto")"
check 'auto.md runs the reset before the MR too' 'The same reset runs before the MR' "$(cat "$auto")"
check 'auto.md counts the rounds' '`## Fix rounds` counts the rounds' "$(cat "$auto")"
check 'README sends both solution sessions dead twice to the human' 'both solution sessions dead' "$(cat "$root/README.md")"
check 'the factory skill too' 'both solution sessions dead twice' "$(cat "$root/skills/factory/SKILL.md")"
check 'the autonom skill too' 'both solution sessions' "$(cat "$root/skills/autonom/SKILL.md")"
check 'the auto skill keeps the UI round the human'"'"'s' 'UI round of the grill aside' "$(cat "$root/skills/auto/SKILL.md")"
check 'the grill skill names the third and fourth cases under --autonom' 'asks nothing\*\* but the third and fourth cases' "$(cat "$root/skills/grill/SKILL.md")"
check 'herd.md has the comments line' '^| `<id> comments <n> -> <m>` |' "$(cat "$root/skills/factory/references/herd.md")"
check 'the decision rule sends a block blocked again after a lane answer to the human' 'blocked again after an answer the lane gave' "$(cat "$root/skills/_shared/auto-decision.md")"
check 'crap-loop.md calls the gate absolute with a crap row' 'the gate is absolute' "$(cat "$root/skills/_shared/crap-loop.md")"
no 'crap-loop.md no longer says to record a method over the threshold' 'record it rather than force it' "$(cat "$root/skills/_shared/crap-loop.md")"
check 'auto.md reads the comments line of the task MR' '<T-id> comments <n> -> <m>' "$(cat "$auto")"
check 'auto.md lists both files for a mixed pick' 'lists both files' "$(cat "$auto")"
check 'the decision rule has the autonomous section' '^## Autonomous$' "$(cat "$root/skills/_shared/auto-decision.md")"
check 'the autonomous section keeps the destructive case and the one where every option fails' 'Cases 3 and 4 are still asked' "$(cat "$root/skills/_shared/auto-decision.md")"
check 'the autonomous section marks its decisions' '(analysed)' "$(cat "$root/skills/_shared/auto-decision.md")"
check 'architect-review has an auto mode' '^## Auto mode$' "$(cat "$root/skills/architect-review/SKILL.md")"
check 'the auto plan-check never writes overridden-by-human' 'overridden-by-human` is never written' "$(cat "$root/skills/architect-review/SKILL.md")"
check 'herd.md reruns solve-next with the lane flag' '`--herd`, `--auto` or `--autonom`' "$(cat "$root/skills/factory/references/herd.md")"
check 'the grill auto mode takes --autonom' '^`/claude-factory:grill <task file> --auto`, the grill step of `factory auto`, or `--autonom`' "$section_grill"
entry="$root/skills/autonom/SKILL.md"
check 'the autonom skill is its own entry' '^name: autonom$' "$(cat "$entry")"
check 'the autonom skill runs solve-next.sh --autonom' 'solve-next\.sh <T-id> --autonom' "$(cat "$entry")"
entry="$root/skills/auto/SKILL.md"
check 'the auto skill is its own entry' '^name: auto$' "$(cat "$entry")"
check 'the auto skill runs solve-next.sh --auto' 'solve-next\.sh <T-id> --auto' "$(cat "$entry")"
check 'the auto skill reads the reference' 'references/auto\.md' "$(cat "$entry")"

exit "$fail"
