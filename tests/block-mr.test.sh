#!/bin/sh
# block-mr.sh over a throwaway state clone, a registered clone whose origin is a local bare repository that takes
# push options and logs them, and a glab stub on PATH (3.4 of the agent-org plan): the forge settings are read
# once per task into .harness/<T-id>/forge.json, the class picks the push (A: -o ci.skip, B: an empty
# `[skip ci]` head commit, C: a plain push), the description carries the risk from arch.md, the verification
# block-verify.sh wrote and the verdict from review.md, --dry-run changes nothing, and `[skip ci]` never
# reaches the title.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=$tmp
export WORK_DIR

state="$tmp/state"
clone="$tmp/clone"
origin="$tmp/origin.git"
harness="$tmp/demo/.harness"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/progress" "$tmp/stub"
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
printf 'demo: {url: https://gitlab.example/o/demo.git, default_branch: main, path: %s}\n' "$clone" > "$state/repos.yml"

# the origin logs every pushed branch with the push options it came with, one `<branch>[ <option>...]` a line
git init -q --bare -b main "$origin"
git -C "$origin" config receive.advertisePushOptions true
cat > "$origin/hooks/pre-receive" <<EOF
#!/bin/sh
opts='' i=0
while [ "\$i" -lt "\${GIT_PUSH_OPTION_COUNT:-0}" ]; do eval "opts=\"\\\$opts \\\$GIT_PUSH_OPTION_\$i\""; i=\$((i + 1)); done
while read -r old new ref; do printf '%s%s\n' "\${ref#refs/heads/}" "\$opts" >> "$tmp/push.log"; done
EOF
chmod +x "$origin/hooks/pre-receive"

git init -q -b main "$clone"
git -C "$clone" config user.email harness@localhost
git -C "$clone" config user.name harness
git -C "$clone" commit -q --allow-empty -m init
git -C "$clone" remote add origin "$origin"
git -C "$clone" push -q origin main
: > "$tmp/push.log"

STUB_LOG="$tmp/forge.log" STUB_DIR="$tmp/stub"
export STUB_LOG STUB_DIR
: > "$STUB_LOG"
cat > "$tmp/stub/glab" <<'EOF'
#!/bin/sh
{ printf 'glab'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$STUB_LOG"
prev=''
for a in "$@"; do
  case "$prev" in --description-file) cp "$a" "$STUB_DIR/desc.md" ;; esac
  prev=$a
done
case "$1 $2" in
  api\ *) cat "$STUB_DIR/api.json" ;;
  'mr view') exit 1 ;;
  'mr create')
    n=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/n"
    echo "https://gitlab.example/o/demo/-/merge_requests/$n" ;;
esac
exit 0
EOF
chmod +x "$tmp/stub/glab"
PATH="$tmp/stub:$PATH"
export PATH

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}
has() { # <what> <fixed string> <text>
  if printf '%s\n' "$3" | grep -qF -- "$2"; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: no %s in:\n%s\n' "$1" "$2" "$3"; fail=1; fi
}
hasnt() { # <what> <fixed string> <text>
  if printf '%s\n' "$3" | grep -qF -- "$2"; then printf 'FAIL %s: %s in:\n%s\n' "$1" "$2" "$3"; fail=1
  else printf 'PASS %s\n' "$1"; fi
}

task() { # <id> <branch or null> [<goal>]
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
branch: $2
status: in_progress
archetype: feature
tier: yellow
complexity: medium
depends_on: []
owner: factory@host:sess-1
mr_url: null
---

# Goal
${3:-feat(demo): ship $1}
EOF
}

publish() {
  git -C "$state" add -A
  git -C "$state" commit -q -m fixture >/dev/null 2>&1 || :
}

parent() { # <id>: the task, its work branch one commit ahead of main, not on origin yet
  git -C "$clone" branch -q "feat/$1-demo" main
  task "$1" "feat/$1-demo"
}

block() { # <id>: the worktree cut by worktree-add.sh, one commit with a passing test, a finished progress file
  task "$1" null
  publish
  (cd "$clone" && sh "$bin/worktree-add.sh" "$1" --state "$state") >/dev/null 2>&1
  mkdir -p "$tmp/demo/$1/tests"
  printf 'exit 0\n' > "$tmp/demo/$1/tests/$1.test.sh"
  git -C "$tmp/demo/$1" add -A
  git -C "$tmp/demo/$1" commit -q -m "feat: $1"
  printf '\n## Done\n- the parser takes empty rows\n\n## Evidence\n- `sh tests/%s.test.sh` -> exit 0\n' "$1" \
    >> "$state/repos/demo/progress/$1.md"
  publish
}

review() { # <id> <verdict line>
  mkdir -p "$harness/$1"
  printf '## Review\n\n### Verdict\n%s\n\n### Findings\n- none\n\n### Verified\n- acceptance\n' "$2" > "$harness/$1/review.md"
}

arch() { # <id> <risk>
  mkdir -p "$harness/$1"
  cat > "$harness/$1/arch.md" <<EOF
---
unit: $1
base: feat/T-700-demo
risk: $2
drift: 0
---

## Architecture audit: $1

### Risk
\`$2\`: the parser is shared.
- blast radius: $2, two consumers
- contracts: low, no public shape moved
- security: low, no edge input
- data: low, no schema
- drift: low, none

### Drift
none

### Checks
- arch-delta.sh: skipped
EOF
}

forge_json() { # <T-id> <merge_method> <pipeline_must_succeed> <skipped_counts_as_success>
  mkdir -p "$harness/$1"
  printf '{"merge_method": "%s", "pipeline_must_succeed": %s, "skipped_counts_as_success": %s}\n' "$2" "$3" "$4" \
    > "$harness/$1/forge.json"
}

api() { # <merge_method> <only_allow_merge_if_pipeline_succeeds> <allow_merge_on_skipped_pipeline>
  printf '{"id": 7, "merge_method": "%s", "squash_option": "default_off", "only_allow_merge_if_pipeline_succeeds": %s, "allow_merge_on_skipped_pipeline": %s}\n' \
    "$1" "$2" "$3" > "$tmp/stub/api.json"
}

run() { # <id> [<flag>...] -> stdout in $out, stderr in $err, exit code in $rc
  run_id=$1; shift
  out=$(sh "$bin/block-mr.sh" "$run_id" --state "$state" "$@" 2>"$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
}

count() { grep -cF -- "$1" "$2" 2>/dev/null || :; }
field() { sed -n "s/^$2:[[:space:]]*//p" "$state/repos/demo/tasks/$1.md" | head -n1; }
subject() { git -C "$clone" log -1 --format=%s "$1"; }
skip_subject='ci: skip the pipeline of a block MR [skip ci]'

# --- class A: merge method merge, pipeline not required -----------------------
api merge false false
parent T-700
block T-700-01
block T-700-02
review T-700-01 '`ok`: no blocking findings, 0 blocking and 1 suggestion.'
review T-700-02 '`ok`: clean.'
arch T-700-01 medium
arch T-700-02 low
(cd "$tmp/demo/T-700-01" && sh "$bin/block-verify.sh" T-700-01 --state "$state") >/dev/null 2>&1

run T-700-01
check 'class A: block-mr.sh exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
check 'class A: stdout is the MR URL' 'https://gitlab.example/o/demo/-/merge_requests/1' "$out"
forge=$(tr -d ' \n' < "$harness/T-700/forge.json" 2>/dev/null)
has 'forge.json records merge_method' '"merge_method":"merge"' "$forge"
has 'forge.json records pipeline_must_succeed' '"pipeline_must_succeed":false' "$forge"
has 'forge.json records skipped_counts_as_success' '"skipped_counts_as_success":false' "$forge"
check 'class A: the block branch is pushed with -o ci.skip' 1 "$(count 'block/T-700-01 ci.skip' "$tmp/push.log")"
check 'class A: the work branch goes to origin once, with -o ci.skip' 1 "$(count 'feat/T-700-demo ci.skip' "$tmp/push.log")"
hasnt 'class A: no [skip ci] commit on the block branch' 'skip ci' "$(subject block/T-700-01)"
create=$(grep -F 'glab [mr] [create]' "$STUB_LOG")
has 'class A: the MR targets the work branch' '[--target-branch] [feat/T-700-demo]' "$create"
has 'class A: the title is the goal' '[--title] [feat(demo): ship T-700-01]' "$create"
desc=$(cat "$tmp/stub/desc.md" 2>/dev/null)
has 'the description keeps What changed' '**What changed** - the parser takes empty rows' "$desc"
has 'the description carries the risk and its sentence' '**Risk** - medium: the parser is shared.' "$desc"
has 'the description carries the risk reasons' '- blast radius: medium, two consumers' "$desc"
has 'the description carries the drift reason' '- drift: low, none' "$desc"
has 'the description carries the verification that ran' '**Verified** - tests: 1 run, 1 passed, 0 failed' "$desc"
has 'the description carries the review verdict' '**Review** - ok: no blocking findings, 0 blocking and 1 suggestion.' "$desc"
check 'class A: the MR URL is recorded in the task file' 'https://gitlab.example/o/demo/-/merge_requests/1' "$(field T-700-01 mr_url)"

# --- --dry-run prints the push and changes nothing -----------------------------
state_head=$(git -C "$state" rev-parse HEAD)
cp "$STUB_LOG" "$tmp/forge.before"
cp "$tmp/push.log" "$tmp/push.before"
run T-700-02 --dry-run
check 'dry-run: exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
has 'dry-run class A: prints the push with -o ci.skip' "push -o ci.skip --force-with-lease -u origin block/T-700-02" "$out"
has 'dry-run: prints the create' 'glab mr create --source-branch block/T-700-02 --target-branch feat/T-700-demo' "$out"
has 'dry-run: prints the description' '**Risk** - low: the parser is shared.' "$out"
check 'dry-run: the state clone has no new commit' "$state_head" "$(git -C "$state" rev-parse HEAD)"
check 'dry-run: the task file keeps mr_url null' null "$(field T-700-02 mr_url)"
check 'dry-run: nothing was pushed' "$(cat "$tmp/push.before")" "$(cat "$tmp/push.log")"
check 'dry-run: the forge was not called' "$(cat "$tmp/forge.before")" "$(cat "$STUB_LOG")"

# --- forge.json is read once per task ------------------------------------------
run T-700-02
check 'a second block of the task exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
check 'the forge settings were read once for the task' 1 "$(count 'glab [api]' "$STUB_LOG")"
check 'the work branch is not pushed again' 1 "$(count 'feat/T-700-demo' "$tmp/push.log")"

# --- class B: ff and squash, pipeline required, skipped counts as success ------
parent T-800
block T-800-01
review T-800-01 '`ok`: clean.'
arch T-800-01 low
forge_json T-800 ff true true
tip=$(git -C "$clone" rev-parse block/T-800-01)
run T-800-01 --dry-run
check 'dry-run class B: exits 0' 0 "$rc"
has 'dry-run class B: prints the empty [skip ci] commit' \
  "commit --allow-empty -m '$skip_subject'" "$out"
hasnt 'dry-run class B: no -o ci.skip on the block push' 'push -o ci.skip --force-with-lease -u origin block/T-800-01' "$out"
check 'dry-run class B: the block branch did not move' "$tip" "$(git -C "$clone" rev-parse block/T-800-01)"

apis=$(count 'glab [api]' "$STUB_LOG")
run T-800-01
check 'class B: block-mr.sh exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
check 'class B: the head commit is the [skip ci] commit' "$skip_subject" "$(subject block/T-800-01)"
check 'class B: the [skip ci] commit is empty' "$(git -C "$clone" rev-parse "$tip^{tree}")" \
  "$(git -C "$clone" rev-parse 'block/T-800-01^{tree}')"
check 'class B: the block branch reached origin' "$(git -C "$clone" rev-parse block/T-800-01)" \
  "$(git -C "$origin" rev-parse block/T-800-01 2>/dev/null)"
check 'class B: an existing forge.json is not read from the forge again' "$apis" "$(count 'glab [api]' "$STUB_LOG")"
create=$(grep -F 'block/T-800-01' "$STUB_LOG" | grep -F '[mr] [create]')
has 'class B: the title is the goal' '[--title] [feat(demo): ship T-800-01]' "$create"
hasnt 'class B: no [skip ci] in the title' 'skip ci' "$create"

run T-800-01
check 'class B: a rerun exits 0' 0 "$rc"
check 'class B: a rerun adds no second [skip ci] commit' "$tip" "$(git -C "$clone" rev-parse block/T-800-01~1)"

# --- class C: pipeline required, skipped does not count -------------------------
api merge true false
parent T-900
block T-900-01
review T-900-01 '`ok`: clean.'
arch T-900-01 low
run T-900-01 --dry-run
check 'dry-run class C: exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
has 'dry-run class C: a plain push' "push --force-with-lease -u origin block/T-900-01" "$out"
hasnt 'dry-run class C: no -o ci.skip' 'ci.skip' "$out"
hasnt 'dry-run class C: no [skip ci] commit' 'skip ci' "$out"
if [ -e "$harness/T-900/forge.json" ]; then printf 'FAIL dry-run: forge.json is not written\n'; fail=1
else printf 'PASS dry-run: forge.json is not written\n'; fi

# --- refusals --------------------------------------------------------------------
task T-800-02 null 'fix(demo): drop the pipeline [skip ci]'
publish
run T-800-02 --dry-run
check 'a goal with [skip ci] is refused' 1 "$rc"
has 'the refusal names [skip ci]' 'skip ci' "$err"

block T-700-03
run T-700-03 --dry-run
check 'a block with no review.md is refused' 1 "$rc"
has 'the refusal names review.md' 'review.md' "$err"

review T-700-03 '`ok`: clean.'
run T-700-03 --dry-run
check 'no arch.md and no docs/architecture/: exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
has 'no arch.md and no docs/architecture/: the risk is not rated' '**Risk** - not rated' "$out"

mkdir -p "$tmp/demo/T-700-03/docs/architecture"
run T-700-03 --dry-run
check 'no arch.md in a repo with docs/architecture/ is refused' 1 "$rc"
has 'the refusal names arch.md' 'arch.md' "$err"

arch T-700-03 low
printf 'block: T-700-03\ntests: 1 run, 0 passed, 1 failed\ncrap:  not bound\nverdict: red\n' > "$harness/T-700-03/verify.txt"
run T-700-03 --dry-run
check 'a block block-verify.sh found red is refused' 1 "$rc"

exit $fail
