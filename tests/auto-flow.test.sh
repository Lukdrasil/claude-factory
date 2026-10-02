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

printf '| `crap <scope>` | `crap "<scope>"` |\n' >> "$state/repos/demo/toolset.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: with a crap row step 4a dispatches the solutions' '^## Step 4a of 16: two solutions for T-020$' "$out"
check 'auto: the open solution goes out' "session-monitor\.sh --task T-020 --step solution-open --state $state\$" "$out"
check 'auto: the minimal solution goes out' "session-monitor\.sh --task T-020 --step solution-min --state $state\$" "$out"
check 'auto: the watcher follows them, once' 'herd-watch\.sh T-020 --interval 60' "$out"
[ "$(printf '%s\n' "$out" | grep -c 'herd-watch\.sh T-020')" = 1 ]; r=$?
check 'auto: one watch line for two dispatches' '^0$' "$r"
check 'auto: step 4a opens with state-push.sh' "^  .*state-push\.sh --state $state\$" "$(printf '%s\n' "$out" | sed -n '/^Commands:$/{n;p;}')"

printf '# Solution (open) for T-020\n' > "$state/repos/demo/research/T-020-solution-open.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
no 'auto: a solution already written is not dispatched again' '\-\-step solution-open' "$out"
check 'auto: the missing one still goes out' '\-\-step solution-min' "$out"

printf '# Solution (min) for T-020\n' > "$state/repos/demo/research/T-020-solution-min.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: both files present is the pick' '^## Step 4a of 16: the human picks the solution for T-020$' "$out"
check 'auto: the pick goes through the ask rule' 'Completion:.*_shared/ask\.md' "$out"
check 'auto: the pick is the consent for the lane' 'Completion:.*consent' "$out"
check 'auto: both files are shown' "^  cat $state/repos/demo/research/T-020-solution-open\.md\$" "$out"
check 'auto: the reference is read' 'skills/factory/references/auto\.md' "$out"
check 'auto: the pick is reported without a status' "state-report\.sh --task T-020 --no-status" "$out"
no 'auto: no grill before the pick' '\-\-step grill' "$out"

printf '\n## Solution\n- view: min\n- file: repos/demo/research/T-020-solution-min.md\n- the human'"'"'s words: as written\n' >> "$state/repos/demo/tasks/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: the pick written is the grill' '^## Step 4 of 16: grill T-020$' "$out"
check 'auto: the grill goes out with --auto' "session-monitor\.sh --task T-020 --step grill --auto --state $state\$" "$out"
check 'auto: the grill completion names the decision rule' 'Completion:.*_shared/auto-decision\.md' "$out"
check 'auto: and the tests every proposal names' 'Completion:.*tests that cover' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: the grill goes out without --auto' "session-monitor\.sh --task T-020 --step grill --state $state\$" "$out"
out=$(sh "$bin/solve-next.sh" T-020 --state "$state" 2>&1)
no 'solve: step 4a is not a step of solve' 'Step 4a' "$out"

# --- step 6: decompose with --auto; step 9 without the ask; step 11 blocked by recommendation ---------------
mkdir -p "$tmp/product"
printf 'demo: {url: https://github.com/o/demo.git, default_branch: main, path: %s}\n' "$tmp/product" > "$state/repos.yml"
printf -- '---\nrepo: demo\ntask: T-020\n---\n' > "$state/repos/demo/plans/export-plan-ready.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: decompose goes out with --auto' "session-monitor\.sh --task T-020 --step decompose --auto --state $state\$" "$out"

block T-020-01 draft
printf 'wave 1: T-020-01\n' > "$state/repos/demo/progress/T-020.md"
sed -i 's/^status: triaged$/status: draft/' "$state/repos/demo/tasks/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 9 approves without an ask' '^## Step 9 of 16: approve and claim T-020$' "$out"
check 'auto: the consent is the pick' 'Completion:.*without an ask' "$out"
no 'auto: approve.md is not read' 'references/approve\.md' "$out"
check 'auto: task-approve.sh still covers the parent and the block' 'task-approve\.sh T-020 T-020-01 --state' "$out"
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
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
no 'herd: a blocked block stays the human'"'"'s' 'auto-decision\.md' "$out"
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
printf 'wave 1: T-020-01\n## Evidence\nok\n## Duplication\nnone\n## Review\nok\n' > "$state/repos/demo/progress/T-020.md"
out=$(sh "$bin/solve-next.sh" T-020 --auto --state "$state" 2>&1)
check 'auto: step 14 opens the MR with the decisions' "mr-open\.sh T-020 --decisions --state $state\$" "$out"
check 'auto: the completion names the ## Decisions section' 'Completion:.*## Decisions' "$out"
check 'auto: a review round is the fix round without an ask' 'Completion:.*without an ask' "$out"
out=$(sh "$bin/solve-next.sh" T-020 --herd --state "$state" 2>&1)
check 'herd: step 14 opens the MR without the decisions' "mr-open\.sh T-020 --state $state\$" "$out"

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
out=$(guard solution-min "$W/cf/T-950" "echo x > $W/cf/T-950/src.cs")
check 'a solution-min session is denied a write into the task worktree' 'rc=2$' "$out"
check 'and the deny names the role' 'a solution-min session reads the product repo' "$out"

# --- the skills: the auto sections and the solution skill ------------------------------------------------------
grill="$root/skills/grill/SKILL.md"
section=$(awk '/^## / { on = ($0 == "## Auto mode"); next } on { print }' "$grill")
check 'the grill has an auto mode' '.' "$section"
check 'the auto grill takes the recommendation under the decision rule' '_shared/auto-decision\.md' "$section"
check 'the auto grill reads the chosen solution' '## Solution' "$section"
check 'the auto grill puts tests into every proposal' 'test <path>: <what it proves>' "$section"
check 'the auto grill marks the human'"'"'s decisions' '(human)' "$section"
dec="$root/skills/decompose/SKILL.md"
section=$(awk '/^## / { on = ($0 == "## Auto mode"); next } on { print }' "$dec")
check 'decompose has an auto mode' '.' "$section"
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
check 'auto.md names the two models' 'claude-opus-5-5.*\|claude-fable-5-1' "$(cat "$auto")"
check 'auto.md names the e2e run' '`e2e` when the toolset binds one' "$(cat "$auto")"
check 'auto.md opens the MR with the decisions' 'mr-open\.sh <T-id> --decisions' "$(cat "$auto")"
check 'auto.md turns the MR review into fix rounds' 'changes-requested' "$(cat "$auto")"
check 'the factory skill routes auto' '^| `auto` |' "$(cat "$root/skills/factory/SKILL.md")"
entry="$root/skills/auto/SKILL.md"
check 'the auto skill is its own entry' '^name: auto$' "$(cat "$entry")"
check 'the auto skill runs solve-next.sh --auto' 'solve-next\.sh <T-id> --auto' "$(cat "$entry")"
check 'the auto skill reads the reference' 'references/auto\.md' "$(cat "$entry")"

exit "$fail"
