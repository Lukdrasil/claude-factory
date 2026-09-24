#!/bin/sh
# The task drawer for solve in a browser: the fixture of tests/ui-fixture.sh, extended with one task per solve
# stage and its plan, grill file, verdicts, progress, blocks, sessions and gate asks, and a wave with one worker per
# agent state, served through ui-up.sh and driven by tests/ui-task.test.js through the fixture's `browser`. The server
# runs from an image built from this checkout's ui/ under a tag of its content, so neither a stale image nor another
# worktree's build is tested.
# The browser checks print their own PASS and FAIL lines. Without Docker it prints `SKIP ui-task: no docker`.
set -u
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-task: no docker'
  exit 0
fi

tmp=$(mktemp -d)
name="cf-ui-task-$$"
tag=$(cd "$repo" && find ui -type f ! -path 'ui/bin/*' ! -path 'ui/obj/*' -exec sha256sum {} + | LC_ALL=C sort -k2 | sha256sum | cut -c1-12)
mkdir -p "$tmp/plugin/.claude-plugin"
cp -R "$repo/bin" "$repo/ui" "$tmp/plugin/"
sed 's/"version":[[:space:]]*"\([^"]*\)"/"version": "\1-'"$tag"'"/' "$repo/.claude-plugin/plugin.json" \
  > "$tmp/plugin/.claude-plugin/plugin.json"
image="claude-factory-ui:$(sed -n 's/.*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp/plugin/.claude-plugin/plugin.json" | head -n1)"
bin="$tmp/plugin/bin"
cleanup() {
  FACTORY_UI_CONTAINER=$name HERDR_ENV=1 timeout 120 sh "$bin/ui-down.sh" >/dev/null 2>&1
  docker rm -f "$name" "$name-free" >/dev/null 2>&1
  docker image rm "$image" >/dev/null 2>&1
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

. "$repo/tests/ui-fixture.sh"

st="$state1/repos/claude-factory"
mkdir -p "$st/plans" "$st/verdicts" "$st/progress"
task() { # <id> <status> [frontmatter line ...], stdin: the body
  id=$1 status=$2
  shift 2
  {
    printf -- '---\nid: %s\nrepo: claude-factory\nstatus: %s\ntier: yellow\narchetype: feature\ncomplexity: high\n' "$id" "$status"
    for line in "$@"; do printf '%s\n' "$line"; done
    printf -- '---\n\n'
    cat
  } > "$st/tasks/$id-fixture.md"
}
goal() { printf '# Goal\n%s\n' "$1"; }
session() { sh "$bin/ui-session.sh" "$@" || bad "ui-session.sh $*"; }
confirm() { # <sid> <ask> <task> <flow> <step> <question>
  printf -- '---\nask: %s\ntask: %s\nflow: %s\nstep: %s\nstatus: open\n---\n\n%s\n' "$2" "$3" "$4" "$5" \
    "❓ **Q1** - **$6**: the gate of the fixture.
  **A** yes
  **B** no

➡️ **A**: the fixture passed." | sh "$bin/ui-ask.sh" --session "$1" >/dev/null || bad "ui-ask.sh --session $1 ($2)"
}

# --- T-020 at step 16: the finished plan, two blocks with MRs, verify evidence, a review verdict, the done gate ---
task T-020 review 'branch: feat/T-020-fx' 'mr_url: https://example.invalid/mr/20' <<'EOF'
# Goal
feat(fx): the finished fixture task

## Context
From the plan `repos/claude-factory/plans/cf-fx-plan-ready.md`
The triage found the fixture context sentence of T-020.

## Acceptance
`sh tests/fx-020.test.sh`
EOF
goal 'feat(fx): block one of T-020' | task T-020-01 done 'mr_url: https://example.invalid/mr/201'
goal 'feat(fx): block two of T-020' | task T-020-02 review 'mr_url: https://example.invalid/mr/202'
cat > "$st/plans/cf-fx-plan-ready.md" <<'EOF'
---
repo: claude-factory
task: T-020
created: 2026-09-24
---

# Spec
The spec of the finished fixture plan.

## Terms
- **fixture widget**: the term of the finished plan. Avoid: gadget

## Program design

### `src/fx.js` (new)
export function fxFinished()
  The member of the finished plan.

## Gap ledger
| # | type | question | deps | state | answer |
|---|---|---|---|---|---|
| 1 | decision | Which finished store? | - | closed | the finished file |
EOF
cat > "$st/progress/T-020.md" <<'EOF'
# T-020

## Wave plan
- wave 1: T-020-01
- wave 2: T-020-02

## Evidence
- `sh tests/fx-020.test.sh` -> exit 0

## Duplication
No candidates.

## Review
`code-reviewer` over the integrated diff at `abc1234`, verdict `changes needed`, 1 blocking, 2 suggestions.
EOF
printf '# T-020-01\n\n## Evidence\n- block-verify.sh T-020-01 -> green, tests: 3 run, 3 passed, 0 failed\n' > "$st/progress/T-020-01.md"
printf '# T-020-02\n\n## Evidence\n- block-verify.sh T-020-02 -> green, tests: 5 run, 5 passed, 0 failed\n' > "$st/progress/T-020-02.md"
session --session s20 --pane w2:p20 --flow solve --task T-020 --step 'Step 16 of 16: knowledge review for T-020'
confirm s20 dn1 T-020 done 'done T-020' 'Close T-020 as done?'

# --- T-021 at step 9: two draft blocks, the wave plan, the cut-check verdict and the approve gate ----------------
task T-021 draft <<'EOF'
# Goal
feat(fx): the fixture task waiting for approval

## Context
From the plan `repos/claude-factory/plans/cf-ap-plan-ready.md`
The context sentence the approver must read in full.

## Acceptance
`sh tests/fx-021.test.sh`

## Out of scope
The last sentence of the body of T-021.
EOF
goal 'feat(fx): block one of T-021' | task T-021-01 draft 'depends_on: []'
goal 'feat(fx): block two of T-021' | task T-021-02 draft 'depends_on: [T-021-01]'
printf -- '---\nrepo: claude-factory\ntask: T-021\n---\n\n# Spec\nThe spec of T-021.\n' > "$st/plans/cf-ap-plan-ready.md"
cat > "$st/verdicts/cf-ap.md" <<'EOF'
---
verdict: aligned
plan: repos/claude-factory/plans/cf-ap-plan-ready.md
---

# cf-ap - architect review

## plan-check
The plan-check sentence of cf-ap.

## cut-check
The cut-check sentence of cf-ap.
EOF
printf '# T-021\n\n## Wave plan\n- wave 1: T-021-01\n- wave 2: T-021-02\n' > "$st/progress/T-021.md"
session --session s21 --pane w2:p21 --flow solve --task T-021 --step 'Step 9 of 16: approve and claim T-021'
confirm s21 ap1 T-021 solve 'Step 9 of 16: approve and claim T-021' 'Approve T-021?'

# --- T-022 at step 4: a grill file named by its task: line and no plan yet, beside the grill file of T-099 --------
task T-022 ready <<'EOF'
# Goal
feat(fx): the fixture task in its grill

## Context
The triage context sentence of T-022.

- the first context item of T-022
- the second context item of T-022
EOF
cat > "$st/plans/cf-gr-grill.md" <<'EOF'
---
repo: claude-factory
task: T-022
created: 2026-09-24
---

# Spec
The spec of the grill in progress.

## Terms
- **fixture gauge**: the term the grill settled. Avoid: meter

## Program design

### `src/gauge.js` (new)
export function readGauge(level)
  The member the design round sketched.

## Gap ledger
| # | type | question | deps | state | answer |
|---|---|---|---|---|---|
| 1 | decision | Which gauge store? | - | closed | the flat file |
| 2 | decision | Which gauge port? | 1 | open | |
EOF
cat > "$st/plans/cf-decoy-grill.md" <<'EOF'
---
repo: claude-factory
task: T-099
created: 2026-09-24
---

## Gap ledger
| # | type | question | deps | state | answer |
|---|---|---|---|---|---|
| 1 | decision | Which decoy store? | - | open | |
EOF
session --session s22 --pane w2:p22 --flow solve --task T-022 --step 'Step 4 of 16: grill T-022'

# --- blocked: T-023 with a live session in herdr, T-024 with one outside herdr, T-025 through its block ----------
question() { # <file> <question> <option 1> <option 2> <recommendation>
  printf '# fixture\n\n## Question\n%s\n\n1. %s\n2. %s\n\nRecommendation: %s\n\nBlocked because the fixture says so.\n' \
    "$2" "$3" "$4" "$5" > "$1"
}
goal 'fix(fx): the blocked fixture task with a live session' | task T-023 blocked
question "$st/progress/T-023.md" 'Which fixture queue should T-023 drain first?' 'the old queue' 'the new queue' \
  '2, the old one is empty.'
session --session s23 --pane w2:p23 --flow solve --task T-023 --step 'Step 9 of 16: approve and claim T-023'
goal 'fix(fx): the blocked fixture task outside herdr' | task T-024 blocked
question "$st/progress/T-024.md" 'Which fixture lane should T-024 take?' 'the left lane' 'the right lane' \
  '1, it is shorter.'
session --session s24 --flow solve --task T-024 --step 'Step 9 of 16: approve and claim T-024'
goal 'feat(fx): the fixture task with a blocked block' | task T-025 in_progress
goal 'feat(fx): the blocked block of T-025' | task T-025-01 blocked
question "$st/progress/T-025-01.md" 'Which fixture cache should T-025-01 keep?' 'the warm cache' 'the cold cache' \
  '1, it is filled.'

# --- T-027 in its wave: one block per worker state the relay writes to agent -----------------------------------
goal 'feat(fx): the fixture task in its wave' | task T-027 in_progress
for w in 1:idle 2:working 3:done 4:gone 5:blocked; do
  n=${w%%:*} agent=${w#*:}
  goal "feat(fx): block $n of T-027" | task "T-027-0$n" in_progress "owner: factory@fx:s27w$n"
  session --session "s27w$n" --pane "w2:p27$n" --flow block --task "T-027-0$n" --step "block T-027-0$n"
  printf '%s\n' "$agent" > "$ui/sessions/s27w$n/agent"
done

# --- T-028 at step 3b: a parent of a request whose map is still being charted ------------------------------------
goal 'feat(fx): the fixture task of a request in its chart' | task T-028 ready 'request: R-20260925-1' 'priority: P1'
session --session s28 --pane w2:p28 --flow solve --task T-028 --step 'Step 3b of 16: chart R-20260925-1'

# --- T-026 at step 3: its session registered by solve-next.sh --ui alone, no hand-written session.md -------------
printf -- '---\nid: T-026\nrepo: claude-factory\nstatus: ready\n---\n\n# Goal\nfeat(fx): the fixture task solve-next registered\n' \
  > "$st/tasks/T-026-fixture.md"
sh "$bin/solve-next.sh" T-026 --state "$state1" --ui s26 > "$tmp/next26.out" 2>&1 || bad "solve-next.sh T-026 --ui s26: $(cat "$tmp/next26.out")"
has 'solve-next.sh puts T-026 at step 3'                      '^## Step 3 of 16' "$(cat "$tmp/next26.out")"
has 'solve-next.sh --ui records the task in session.md'       '^task: T-026$' "$(cat "$ui/sessions/s26/session.md" 2>/dev/null)"
has 'solve-next.sh --ui records the flow in session.md'       '^flow: solve$' "$(cat "$ui/sessions/s26/session.md" 2>/dev/null)"

# --- the server, then the browser --------------------------------------------------------------------------------
up --state "$state1"; rc=$?
is 'ui-up.sh exits 0'                                         "$rc" 0
[ "$rc" = 0 ] || { sed 's/^/  up: /' "$tmp/up.err" | tail -n 30; exit 1; }
is 'the server runs the image of this checkout'               "$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)" "$image"
port=$(cat "$ui/port" 2>/dev/null)
token=$(cat "$ui/token" 2>/dev/null)
ready "$port" || { bad "the server never answered / on $port: $(docker logs "$name" 2>&1 | tail -n 20)"; exit 1; }

browser "$repo/tests/ui-task.test.js"
rc=$?
cat "$tmp/browser.out"
is 'the browser checks exit 0'                                "$rc" 0
has 'the browser checks ran'                                  '^PASS |^FAIL ' "$(cat "$tmp/browser.out")"

exit $fail
