#!/bin/sh
# mr-open.sh and block-mr.sh --dry-run over a throwaway state clone (T-253): a finished step moves to `## Done`
# as `- [x] <step>`, and the MR description renders it without the box. A bullet with no box is unchanged.
# 3.4 of the agent-org plan: the task MR lists every block MR under `## Blocks` with its link and the risk
# the architecture-auditor wrote into `.harness/<block>/arch.md`.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=$tmp
export WORK_DIR

state="$tmp/state"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/progress"
printf 'demo: {url: https://github.com/o/demo.git, default_branch: main, path: %s}\n' "$tmp/clone" > "$state/repos.yml"

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}

task() { # <id> <branch>
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
feat(demo): ship $1
EOF
}

progress() { # <id>
  cat > "$state/repos/demo/progress/$1.md" <<'EOF'
# the progress
base: feat/T-700-demo
**acceptance green**: done.

## Done
- [x] a
- b

## Remaining
- none

## Evidence
- [x] `sh tests/x.test.sh` -> exit 0

## Follow-ups
- [ ] c
EOF
}

worktree() { # <id>
  git init -q -b main "$tmp/demo/$1"
  git -C "$tmp/demo/$1" remote add origin https://github.com/o/demo.git
}

mr_url() { # <id> <url>
  sed "s#^mr_url: null\$#mr_url: $2#" "$state/repos/demo/tasks/$1.md" > "$tmp/mr.md"
  mv -f "$tmp/mr.md" "$state/repos/demo/tasks/$1.md"
}

arch() { # <id> <risk>
  mkdir -p "$tmp/demo/.harness/$1"
  printf -- '---\nunit: %s\nbase: feat/T-700-demo\nrisk: %s\ndrift: 0\n---\n\n### Risk\n`%s`: why.\n' "$1" "$2" "$2" \
    > "$tmp/demo/.harness/$1/arch.md"
}

task T-700 feat/T-700-demo
task T-700-01 block/T-700-01
progress T-700
progress T-700-01
worktree T-700
worktree T-700-01

# the three merged block MRs mr-open.sh lists under ## Blocks, and one block that never opened one
for b in 01 02 03 04; do [ -f "$state/repos/demo/tasks/T-700-$b.md" ] || task "T-700-$b" "block/T-700-$b"; done
mr_url T-700-01 https://github.com/o/demo/pull/11
mr_url T-700-02 https://github.com/o/demo/pull/12
mr_url T-700-03 https://github.com/o/demo/pull/13
arch T-700-01 low
arch T-700-02 high

# block-mr.sh reads the forge class of the task and the block's review before it builds anything
mkdir -p "$tmp/demo/.harness/T-700"
printf '{"merge_method": "merge", "pipeline_must_succeed": false, "skipped_counts_as_success": false}\n' \
  > "$tmp/demo/.harness/T-700/forge.json"
printf '## Review\n\n### Verdict\n`ok`: clean.\n' > "$tmp/demo/.harness/T-700-01/review.md"

out=$(sh "$bin/mr-open.sh" T-700 --dry-run --state "$state" --worktree "$tmp/demo/T-700" 2>&1); rc=$?
check 'mr-open.sh --dry-run exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'mr-open.sh renders - [x] a in ## Done as a' '**What changed** - a; b' \
  "$(printf '%s\n' "$out" | grep -F '**What changed**')"
check 'mr-open.sh drops the box from an Evidence bullet' '**How to verify** - `sh tests/x.test.sh` -> exit 0' \
  "$(printf '%s\n' "$out" | grep -F '**How to verify**')"
check 'mr-open.sh drops an open box from a Follow-ups bullet' '- c' \
  "$(printf '%s\n' "$out" | sed -n '/^\*\*Follow-ups\*\*$/{n;p;}')"
check 'mr-open.sh lists every block MR with its link and risk under ## Blocks' "$(printf '%s\n' \
  '## Blocks' \
  '- [feat(demo): ship T-700-01](https://github.com/o/demo/pull/11), risk low' \
  '- [feat(demo): ship T-700-02](https://github.com/o/demo/pull/12), risk high' \
  '- [feat(demo): ship T-700-03](https://github.com/o/demo/pull/13), risk not rated')" \
  "$(printf '%s\n' "$out" | sed -n '/^## Blocks$/,/^$/p' | sed '/^$/d')"

# --decisions: the task MR of factory auto carries every bullet of the plan's ## Decisions, the [locked] tag
# dropped, after ## Blocks and outside the 120 words; a task with no plan, or a plan with no bullet, is exit 1
out=$(sh "$bin/mr-open.sh" T-700 --dry-run --decisions --state "$state" --worktree "$tmp/demo/T-700" 2>&1); rc=$?
check 'mr-open.sh --decisions without a plan exits 1' 1 "$rc"
mkdir -p "$state/repos/demo/plans"
printf -- '---\nrepo: demo\ntask: T-700\n---\n\n# Spec\nx.\n\n## Decisions\n\n## Program design\n' > "$state/repos/demo/plans/export-plan-ready.md"
out=$(sh "$bin/mr-open.sh" T-700 --dry-run --decisions --state "$state" --worktree "$tmp/demo/T-700" 2>&1); rc=$?
check 'mr-open.sh --decisions over a plan that decided nothing exits 0' 0 "$rc"
check 'and says so' '- none taken' "$(printf '%s\n' "$out" | sed -n '/^## Decisions$/{n;p;}')"
mkdir -p "$state/repos/demo/plans"
printf -- '---\nrepo: demo\ntask: T-700\n---\n\n# Spec\nx.\n\n## Decisions\n- [locked] one exporter per format: the API resolves it by content type;\n  rejected: a switch, it grows per format\n* the stream is not buffered: large exports (human)\n\n## Program design\n' \
  > "$state/repos/demo/plans/export-plan-ready.md"
out=$(sh "$bin/mr-open.sh" T-700 --dry-run --decisions --state "$state" --worktree "$tmp/demo/T-700" 2>&1); rc=$?
check 'mr-open.sh --decisions exits 0 with a plan' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'mr-open.sh --decisions joins a wrapped bullet, reads a * bullet and drops the locked tag' "$(printf '%s\n' \
  '## Decisions' \
  '- one exporter per format: the API resolves it by content type; rejected: a switch, it grows per format' \
  '- the stream is not buffered: large exports (human)')" \
  "$(printf '%s\n' "$out" | sed -n '/^## Decisions$/,/^$/p' | sed '/^$/d')"
check 'mr-open.sh --decisions keeps ## Blocks in front of it' '## Blocks' \
  "$(printf '%s\n' "$out" | grep -E '^## (Blocks|Decisions)$' | head -n1)"
out=$(sh "$bin/mr-open.sh" T-700 --dry-run --state "$state" --worktree "$tmp/demo/T-700" 2>&1)
check 'mr-open.sh without --decisions lists none' '' "$(printf '%s\n' "$out" | grep -c '^## Decisions$' | sed 's/^0$//')"

out=$(sh "$bin/block-mr.sh" T-700-01 --dry-run --state "$state" --worktree "$tmp/demo/T-700-01" 2>&1); rc=$?
check 'block-mr.sh --dry-run exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'block-mr.sh renders - [x] a in ## Done as a' '**What changed** - a; b' \
  "$(printf '%s\n' "$out" | grep -F '**What changed**')"
check 'block-mr.sh drops the box from an Evidence bullet' '**How to verify** - `sh tests/x.test.sh` -> exit 0' \
  "$(printf '%s\n' "$out" | grep -F '**How to verify**')"

# a self-hosted GitLab on a port (F10): the origin's host keeps its port and still routes to glab
git -C "$tmp/demo/T-700" remote set-url origin http://localhost:8929/g/r.git
git -C "$tmp/demo/T-700-01" remote set-url origin http://localhost:8929/g/r.git
out=$(sh "$bin/mr-open.sh" T-700 --dry-run --state "$state" --worktree "$tmp/demo/T-700" 2>&1)
check 'mr-open.sh routes an http://localhost:8929 origin to glab' 'glab mr create' \
  "$(printf '%s\n' "$out" | grep -o '^glab mr create')"
check "the task MR targets the repo's default_branch" 'main' \
  "$(printf '%s\n' "$out" | sed -n 's/^glab mr create .*--target-branch \([^ ]*\) .*/\1/p')"
awk 'NR == 2 { print "base_branch: develop" } { print }' "$state/repos/demo/tasks/T-700.md" > "$tmp/bb.md"
cp "$state/repos/demo/tasks/T-700.md" "$tmp/nobb.md"
mv -f "$tmp/bb.md" "$state/repos/demo/tasks/T-700.md"
out=$(sh "$bin/mr-open.sh" T-700 --dry-run --state "$state" --worktree "$tmp/demo/T-700" 2>&1)
check "the task MR targets the task's base_branch: over the repo's" 'develop' \
  "$(printf '%s\n' "$out" | sed -n 's/^glab mr create .*--target-branch \([^ ]*\) .*/\1/p')"
mv -f "$tmp/nobb.md" "$state/repos/demo/tasks/T-700.md"
out=$(sh "$bin/block-mr.sh" T-700-01 --dry-run --state "$state" --worktree "$tmp/demo/T-700-01" 2>&1)
check 'block-mr.sh routes an http://localhost:8929 origin to glab' 'glab mr create' \
  "$(printf '%s\n' "$out" | grep -o '^glab mr create' | head -n1)"

# F17: **Why** is the reason, not the title again: the task's ## Context first sentence, else the # Spec
# sentence of the plan the task names, else the goal
why() { sh "$bin/mr-open.sh" T-700 --dry-run --state "$state" --worktree "$tmp/demo/T-700" 2>&1 | grep -F '**Why**'; }
check 'Why: with no context and no plan the task MR falls back to the goal' '**Why** - feat(demo): ship T-700' "$(why)"

mkdir -p "$state/repos/demo/plans"
printf -- '---\nrepo: demo\n---\n\n# Spec\nSearch finds a note\nby term so nobody scrolls. The rest.\n' \
  > "$state/repos/demo/plans/notes-plan-ready.md"
printf '\n## Context\nFrom the plan `repos/demo/plans/notes-plan-ready.md`\n' >> "$state/repos/demo/tasks/T-700.md"
check 'Why: with no context sentence the task MR takes the plan'"'"'s # Spec sentence' \
  '**Why** - Search finds a note by term so nobody scrolls.' "$(why)"

task T-700 feat/T-700-demo
printf '\n## Context\nUsers lose track of notes once there are many! They asked for search.\n\n## Acceptance\n- x\n' \
  >> "$state/repos/demo/tasks/T-700.md"
check 'Why: the task MR takes the first sentence of the task'"'"'s ## Context' \
  '**Why** - Users lose track of notes once there are many!' "$(why)"

# the task MR's URL lands in the parent's mr_url, the field solve-next.sh, mr-watch.sh and task-done.sh read
mkdir -p "$tmp/stub"
cat > "$tmp/stub/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "pr view") exit 1 ;;
  "pr create") echo https://github.com/o/demo/pull/70 ;;
  *) exit 1 ;;
esac
EOF
# glab too: a git insteadOf rule of the machine can rewrite the github.com origin to another host
cat > "$tmp/stub/glab" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "mr view") exit 1 ;;
  "mr create") echo https://github.com/o/demo/pull/70 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/stub/gh" "$tmp/stub/glab"
git -C "$state" init -q -b main
git -C "$state" add -A
git -C "$state" -c user.name=t -c user.email=t@t commit -q -m fixture
out=$(cd "$tmp/demo/T-700" && PATH="$tmp/stub:$PATH" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t \
  GIT_COMMITTER_EMAIL=t@t sh "$bin/mr-open.sh" T-700 --state "$state" --worktree "$tmp/demo/T-700" 2>&1); rc=$?
check 'mr-open.sh prints the URL of the task MR' '0 https://github.com/o/demo/pull/70' "$rc $(printf '%s\n' "$out" | tail -n1)"
check 'and writes it into the mr_url of the parent' 'mr_url: https://github.com/o/demo/pull/70' \
  "$(grep '^mr_url:' "$state/repos/demo/tasks/T-700.md")"
check 'in a commit of the state clone' 'chore(T-700): task MR open into main' "$(git -C "$state" log -1 --format=%s)"

exit $fail
