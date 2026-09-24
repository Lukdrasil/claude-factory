#!/bin/sh
# block-mr-merge.sh over a throwaway state clone, a registered clone with a local bare origin, and glab and gh
# stubs on PATH that merge on the "forge" by merging the block branch into the work branch on origin (3.4 step 5
# of the agent-org plan): the MR is merged with `glab mr merge` or `gh pr merge --merge --delete-branch`, the
# parent worktree follows with `pull --ff-only`, the block's worktree is removed and the block is set done. A
# high risk block is refused until --confirmed, a sibling MR of a class B task is rebased before its merge, a
# class C MR is left to auto-merge, and --dry-run changes nothing.
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

git init -q --bare -b main "$origin"
git init -q -b main "$clone"
git -C "$clone" config user.email harness@localhost
git -C "$clone" config user.name harness
git -C "$clone" commit -q --allow-empty -m init
git -C "$clone" remote add origin "$origin"
git -C "$clone" push -q origin main

# the forge's side of a merge: the block branch merged into its target on origin, from a scratch clone
git clone -q "$origin" "$tmp/scratch"
git -C "$tmp/scratch" config user.email forge@localhost
git -C "$tmp/scratch" config user.name forge
cat > "$tmp/forge-merge.sh" <<EOF
#!/bin/sh
set -e
git -C "$tmp/scratch" fetch -q origin
git -C "$tmp/scratch" checkout -q -B "\$2" "origin/\$2"
git -C "$tmp/scratch" merge -q --no-ff -m "Merge branch '\$1' into '\$2'" "origin/\$1"
git -C "$tmp/scratch" push -q origin "\$2"
EOF

STUB_LOG="$tmp/forge.log" STUB_DIR="$tmp/stub" FORGE_MERGE="$tmp/forge-merge.sh"
export STUB_LOG STUB_DIR FORGE_MERGE
: > "$STUB_LOG"
# one json file per MR (`mr-<n>.json`) and its `<source> <target>` (`mr-<n>.ref`); a merge rewrites the json to
# merged unless STUB_AUTO is set, which leaves it open as a forge does with auto-merge on a running pipeline
for tool in glab gh; do
  cat > "$tmp/stub/$tool" <<'EOF'
#!/bin/sh
tool=${0##*/}
{ printf '%s' "$tool"; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$STUB_LOG"
n=${3##*/}
case "$1 $2" in
  'mr view'|'pr view') cat "$STUB_DIR/mr-$n.json" ;;
  'mr rebase') printf '{"state": "opened", "detailed_merge_status": "mergeable", "rebase_in_progress": false}\n' > "$STUB_DIR/mr-$n.json" ;;
  'mr merge'|'pr merge')
    [ -z "${STUB_AUTO:-}" ] || exit 0
    sh "$FORGE_MERGE" $(cat "$STUB_DIR/mr-$n.ref") || exit 1
    if [ "$tool" = gh ]; then echo '{"state": "MERGED"}'; else echo '{"state": "merged"}'; fi > "$STUB_DIR/mr-$n.json" ;;
esac
exit 0
EOF
  chmod +x "$tmp/stub/$tool"
done
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

task() { # <id> <branch or null> <status> <mr_url or null>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
branch: $2
status: $3
archetype: feature
tier: yellow
complexity: medium
depends_on: []
owner: factory@host:sess-1
mr_url: $4
---

# Goal
feat(demo): ship $1
EOF
}

publish() {
  git -C "$state" add -A
  git -C "$state" commit -q -m fixture >/dev/null 2>&1 || :
}

parent() { # <id> <class: merge_method pipeline_must_succeed skipped_counts_as_success>
  git -C "$clone" branch -q "feat/$1-demo" main
  git -C "$clone" push -q origin "feat/$1-demo"
  task "$1" "feat/$1-demo" in_progress null
  publish
  (cd "$clone" && sh "$bin/worktree-add.sh" "$1" --state "$state") >/dev/null 2>&1
  mkdir -p "$harness/$1"
  printf '{"merge_method": "%s", "pipeline_must_succeed": %s, "skipped_counts_as_success": %s}\n' "$2" "$3" "$4" \
    > "$harness/$1/forge.json"
}

mrs=0
block() { # <id> <forge: glab|gh> <risk> <review verdict> [<detailed_merge_status>]
  mrs=$((mrs + 1))
  if [ "$2" = gh ]; then url="https://github.com/o/demo/pull/$mrs"; json='{"state": "OPEN"}'
  else url="https://gitlab.example/o/demo/-/merge_requests/$mrs"
    json="{\"state\": \"opened\", \"detailed_merge_status\": \"${5:-mergeable}\", \"rebase_in_progress\": false}"
  fi
  task "$1" null in_progress null
  publish
  (cd "$clone" && sh "$bin/worktree-add.sh" "$1" --state "$state") >/dev/null 2>&1
  printf '%s\n' "$1" > "$tmp/demo/$1/$1.txt"
  git -C "$tmp/demo/$1" add -A
  git -C "$tmp/demo/$1" commit -q -m "feat: $1"
  git -C "$tmp/demo/$1" push -q origin "block/$1"
  task "$1" "block/$1" review "$url"
  publish
  printf '%s\n' "$json" > "$tmp/stub/mr-$mrs.json"
  printf 'block/%s feat/%s-demo\n' "$1" "${1%-*}" > "$tmp/stub/mr-$mrs.ref"
  mkdir -p "$harness/$1"
  printf -- '---\nunit: %s\nbase: feat/%s-demo\nrisk: %s\ndrift: 0\n---\n\n### Risk\n`%s`: why.\n' "$1" "${1%-*}" "$3" "$3" \
    > "$harness/$1/arch.md"
  printf '## Review\n\n### Verdict\n%s\n' "$4" > "$harness/$1/review.md"
}

run() { # <id> [<flag>...] -> stdout in $out, stderr in $err, exit code in $rc
  run_id=$1; shift
  out=$(sh "$bin/block-mr-merge.sh" "$run_id" --state "$state" "$@" 2>"$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
}

status() { git -C "$state" show "HEAD:repos/demo/tasks/$1.md" 2>/dev/null | sed -n 's/^status:[[:space:]]*//p' | head -n1; }
gone() { # <what> <path>
  if [ -e "$2" ]; then printf 'FAIL %s: %s is still there\n' "$1" "$2"; fail=1; else printf 'PASS %s\n' "$1"; fi
}
there() { # <what> <path>
  if [ -e "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s: %s is gone\n' "$1" "$2"; fail=1; fi
}

# --- class A on glab ----------------------------------------------------------------
parent T-700 merge false false
block T-700-01 glab low '`ok`: clean.'
url1=https://gitlab.example/o/demo/-/merge_requests/1
run T-700-01
check 'glab: block-mr-merge.sh exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
check 'glab: stdout names the merged MR' "T-700-01 merged $url1" "$out"
has 'glab: glab mr merge merges at once and removes the source branch' \
  "glab [mr] [merge] [$url1] [--auto-merge=false] [--remove-source-branch] [--yes]" "$(cat "$STUB_LOG")"
hasnt 'class A: no rebase' '[mr] [rebase]' "$(cat "$STUB_LOG")"
check 'the parent worktree is pulled --ff-only to the merged work branch' \
  "$(git -C "$origin" rev-parse feat/T-700-demo)" "$(git -C "$tmp/demo/T-700" rev-parse HEAD)"
there 'the merged block file is in the parent worktree' "$tmp/demo/T-700/T-700-01.txt"
gone "the block's worktree is removed" "$tmp/demo/T-700-01"
check "the block's local branch is deleted" '' "$(git -C "$clone" branch --list block/T-700-01)"
check 'the block is set done in the state clone' done "$(status T-700-01)"

# --- high risk waits for the human ------------------------------------------------------
block T-700-02 glab high '`ok`: clean.'
url2=https://gitlab.example/o/demo/-/merge_requests/2
run T-700-02
check 'high risk without --confirmed exits 3' 3 "$rc"
has 'the refusal says to ask the human' 'human' "$err"
has 'the refusal names --confirmed' '--confirmed' "$err"
hasnt 'high risk: nothing is merged' "[merge] [$url2]" "$(cat "$STUB_LOG")"
there 'high risk: the worktree stays' "$tmp/demo/T-700-02"
check 'high risk: the block stays review' review "$(status T-700-02)"
run T-700-02 --confirmed
check 'high risk with --confirmed exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
check 'high risk with --confirmed is done' done "$(status T-700-02)"

# --- gh -------------------------------------------------------------------------------------
block T-700-03 gh medium '`ok`: clean.'
url3=https://github.com/o/demo/pull/3
run T-700-03
check 'gh: block-mr-merge.sh exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
has 'gh: gh pr merge --merge --delete-branch' "gh [pr] [merge] [$url3] [--merge] [--delete-branch]" "$(cat "$STUB_LOG")"
there 'gh: the merged block file is in the parent worktree' "$tmp/demo/T-700/T-700-03.txt"
gone "gh: the block's worktree is removed" "$tmp/demo/T-700-03"
check 'gh: the block is set done' done "$(status T-700-03)"

# --- --dry-run changes nothing ------------------------------------------------------------
block T-700-04 glab low '`ok`: clean.'
url4=https://gitlab.example/o/demo/-/merge_requests/4
cp "$STUB_LOG" "$tmp/forge.before"
state_head=$(git -C "$state" rev-parse HEAD)
run T-700-04 --dry-run
check 'dry-run exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
has 'dry-run prints the merge' "glab mr merge $url4 --auto-merge=false --remove-source-branch --yes" "$out"
has 'dry-run prints the pull' "git -C $tmp/demo/T-700 pull --ff-only origin feat/T-700-demo" "$out"
has 'dry-run prints the worktree removal' "worktree remove --force $tmp/demo/T-700-04" "$out"
has 'dry-run prints the done report' 'state-report.sh --task T-700-04 --set-status done' "$out"
check 'dry-run: the forge was not called' "$(cat "$tmp/forge.before")" "$(cat "$STUB_LOG")"
check 'dry-run: the state clone has no new commit' "$state_head" "$(git -C "$state" rev-parse HEAD)"
there 'dry-run: the worktree stays' "$tmp/demo/T-700-04"

# --- a review that asks for changes is not merged --------------------------------------------
block T-700-05 glab low '`changes needed`: one blocking finding.'
run T-700-05
check 'changes needed is refused' 1 "$rc"
has 'the refusal names the review' 'changes needed' "$err"
check 'changes needed: the block stays review' review "$(status T-700-05)"

# --- class B: a sibling MR is rebased before its merge -------------------------------------
parent T-800 ff true true
block T-800-01 glab low '`ok`: clean.'
block T-800-02 glab low '`ok`: clean.' need_rebase
url6=https://gitlab.example/o/demo/-/merge_requests/6
url7=https://gitlab.example/o/demo/-/merge_requests/7
run T-800-01
check 'class B: the first block exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
hasnt 'class B: an MR that needs no rebase is not rebased' "[rebase] [$url6]" "$(cat "$STUB_LOG")"
run T-800-02
check 'class B: the sibling exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
has 'class B: the sibling is rebased with the pipeline skipped' "glab [mr] [rebase] [$url7] [--skip-ci]" "$(cat "$STUB_LOG")"
check 'class B: the rebase runs before the merge' "rebase merge" \
  "$(grep -F "$url7" "$STUB_LOG" | awk '$3 == "[rebase]" || $3 == "[merge]" { gsub(/[][]/, "", $3); print $3 }' | tr '\n' ' ' | sed 's/ $//')"
check 'class B: the sibling is done' done "$(status T-800-02)"

# --- class C: auto-merge, nothing else yet ---------------------------------------------------
parent T-900 merge true false
block T-900-01 glab low '`ok`: clean.'
url8=https://gitlab.example/o/demo/-/merge_requests/8
STUB_AUTO=1
export STUB_AUTO
run T-900-01
unset STUB_AUTO
check 'class C: exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  stderr: %s\n' "$err"
check 'class C: stdout says auto-merge' "T-900-01 auto-merge $url8" "$out"
has 'class C: glab mr merge with --auto-merge' "glab [mr] [merge] [$url8] [--auto-merge] [--remove-source-branch] [--yes]" "$(cat "$STUB_LOG")"
there 'class C: the worktree stays until the MR is merged' "$tmp/demo/T-900-01"
check 'class C: the block stays review' review "$(status T-900-01)"

exit $fail
