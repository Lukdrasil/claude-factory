#!/bin/sh
# worktree-add.sh over a throwaway state clone and registered clone (T-228 A7): a block records the sha of its
# base beside `base:`, and a resumed block whose base moved is reset when it has no commits of its own, refused
# with the command when it has, and left alone when the base did not move. Without `base_sha:` only a branch
# that is an ancestor of the new base is reset. T-253: a progress file it creates arrives with `## Remaining`
# seeded from the task's `## Checklist`, and one that already exists keeps its sections.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=$tmp
export WORK_DIR

state="$tmp/state"
clone="$tmp/clone"
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/progress"
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
git init -q --bare "$tmp/state-origin.git"
git -C "$state" remote add origin "$tmp/state-origin.git"
printf 'demo: {url: %s, default_branch: main, path: %s}\n' "$tmp/clone-origin.git" "$clone" > "$state/repos.yml"

git init -q -b main "$clone"
git -C "$clone" config user.email harness@localhost
git -C "$clone" config user.name harness
git -C "$clone" commit -q --allow-empty -m init

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}

task() { # <id> <branch or null>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
branch: $2
status: in_progress
archetype: bugfix
tier: yellow
complexity: medium
depends_on: []
owner: factory@host:sess-1
mr_url: null
---

# Goal
fix(demo): $1
EOF
}

publish() {
  git -C "$state" add -A
  git -C "$state" commit -q -m fixture >/dev/null 2>&1 || :
  git -C "$state" push -q -u origin main >/dev/null 2>&1
}

progress_field() { # <id> <key>
  sed -n "s/^$2:[[:space:]]*//p" "$state/repos/demo/progress/$1.md" 2>/dev/null | head -n1
}

set_base_sha() { # <id> <sha, or nothing to drop the line>
  f="$state/repos/demo/progress/$1.md"
  awk -v s="$2" '/^base_sha:/ { next } { print } END { if (s != "") print "base_sha: " s }' "$f" > "$f.tmp"
  mv -f "$f.tmp" "$f"
  publish
}

tip() { git -C "$clone" rev-parse "$1" 2>/dev/null; }

add() { # <id> -> stdout and stderr in $out, exit code in $rc
  out=$(cd "$clone" && sh "$bin/worktree-add.sh" "$1" --state "$state" 2>&1); rc=$?
}

commit_on() { # <branch> <message> -> the new sha, the branch moved to it, nothing checked out
  cmt=$(git -C "$clone" commit-tree -p "$(tip "$1")" -m "$2" "$(tip "$1")^{tree}")
  git -C "$clone" update-ref "refs/heads/$1" "$cmt"
  printf '%s' "$cmt"
}

# --- the parent T-300 on feat/T-300-demo, one commit A ahead of main ---------
git -C "$clone" branch -q feat/T-300-demo main
A=$(commit_on feat/T-300-demo 'parent work A')
task T-300 feat/T-300-demo
for b in 01 02 03 04; do task "T-300-$b" null; done
publish

# --- a fresh block records base: and base_sha: ------------------------------
add T-300-01
check 'a fresh block exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the block is cut from the parent tip' "$A" "$(tip block/T-300-01)"
check 'base: holds the branch alone, the readers take the whole value' feat/T-300-demo "$(progress_field T-300-01 base)"
check 'base_sha: holds the sha the block was cut from' "$A" "$(progress_field T-300-01 base_sha)"
check 'base_sha: is committed in the state clone' "$A" \
  "$(git -C "$state" show HEAD:repos/demo/progress/T-300-01.md 2>/dev/null | sed -n 's/^base_sha:[[:space:]]*//p' | head -n1)"
if printf '%s\n' "$out" | grep -qx 'base: feat/T-300-demo'; then printf 'PASS stdout still prints base: <branch>\n'
else printf 'FAIL stdout still prints base: <branch>: %s\n' "$out"; fail=1; fi

# --- three more blocks at A: T-300-02 keeps its worktree, T-300-03 loses it, T-300-04 gains a commit C ---
add T-300-02
add T-300-03
git -C "$clone" worktree remove "$tmp/demo/T-300-03"
add T-300-04
git -C "$tmp/demo/T-300-04" commit -q --allow-empty -m 'block work C'
C=$(tip block/T-300-04)
for b in 02 03 04; do set_base_sha "T-300-$b" "$A"; done

# the parent is squashed onto main: B does not contain A
git -C "$clone" update-ref refs/heads/feat/T-300-demo main
B=$(commit_on feat/T-300-demo 'parent work A, squashed')

# --- a resumed worktree whose tip is base_sha is reset to the new base --------
add T-300-02
check 'a stale worktree with no own commits resumes with exit 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the stale worktree branch is reset to the new base' "$B" "$(tip block/T-300-02)"
check 'the worktree HEAD follows the reset' "$B" "$(git -C "$tmp/demo/T-300-02" rev-parse HEAD 2>/dev/null)"
check 'base_sha: follows the reset' "$B" "$(progress_field T-300-02 base_sha)"

# --- a stale branch with no worktree is reset the same way -------------------
add T-300-03
check 'a stale branch with no worktree resumes with exit 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the stale branch is reset to the new base' "$B" "$(tip block/T-300-03)"
check 'its worktree is back' block/T-300-03 "$(git -C "$tmp/demo/T-300-03" rev-parse --abbrev-ref HEAD 2>/dev/null)"

# --- a stale branch with commits of its own is refused, with the command -----
add T-300-04
check 'a stale branch with own commits is refused' 1 "$rc"
check 'the refused branch keeps its commits' "$C" "$(tip block/T-300-04)"
if printf '%s\n' "$out" | grep -q 'git '; then printf 'PASS the refusal prints the git command\n'
else printf 'FAIL the refusal prints the git command: %s\n' "$out"; fail=1; fi
check 'the refusal leaves base_sha: as it was' "$A" "$(progress_field T-300-04 base_sha)"

# --- a block whose base did not move resumes as it stands, own commits and all ---
git -C "$clone" branch -q feat/T-400-demo main
E=$(commit_on feat/T-400-demo 'parent work E')
task T-400 feat/T-400-demo
task T-400-01 null
publish
add T-400-01
git -C "$tmp/demo/T-400-01" commit -q --allow-empty -m 'block work F'
F=$(tip block/T-400-01)
set_base_sha T-400-01 "$E"
add T-400-01
check 'an unmoved base resumes with exit 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'an unmoved base keeps the block commits' "$F" "$(tip block/T-400-01)"

# --- without base_sha: only an ancestor of the new base is reset --------------
git -C "$clone" branch -q feat/T-500-demo main
G=$(commit_on feat/T-500-demo 'parent work G')
task T-500 feat/T-500-demo
task T-500-01 null
task T-500-02 null
publish
add T-500-01
add T-500-02
git -C "$tmp/demo/T-500-02" commit -q --allow-empty -m 'block work H'
H=$(tip block/T-500-02)
set_base_sha T-500-01 ''
set_base_sha T-500-02 ''
I=$(commit_on feat/T-500-demo 'parent work I, a fast-forward')
add T-500-01
check 'no base_sha:, an ancestor resumes with exit 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'no base_sha:, an ancestor of the new base is reset to it' "$I" "$(tip block/T-500-01)"
add T-500-02
check 'no base_sha:, a branch with own commits is not reset' "$H" "$(tip block/T-500-02)"

# --- T-253: a new progress file is seeded with the checklist, an existing one keeps its sections ---
section() { # <file> <heading>: the non-blank lines under the heading, up to the next `## `
  awk -v h="$2" '$0 == h { on = 1; next } on && /^## / { exit } on && NF { print }' "$1"
}
git -C "$clone" branch -q feat/T-600-demo main
commit_on feat/T-600-demo 'parent work J' >/dev/null
task T-600 feat/T-600-demo
for b in 01 02; do
  task "T-600-$b" null
  printf '\n## Out of scope\nnothing\n\n## Checklist\n- [ ] a\n- [ ] b\n\n## Attempts\n' >> "$state/repos/demo/tasks/T-600-$b.md"
done
existing="$state/repos/demo/progress/T-600-02.md"
printf '# T-600-02: resumed\n**on track**: kept as written.\n\n## Done\n- the first half\n\n## Remaining\n- [ ] old step\n' > "$existing"
cp "$existing" "$tmp/T-600-02.before"
publish

add T-600-01
check 'a block with a checklist exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
new="$state/repos/demo/progress/T-600-01.md"
check 'a new progress file seeds ## Remaining with the checklist' "$(printf '%s\n%s' '- [ ] a' '- [ ] b')" \
  "$(section "$new" '## Remaining')"
check 'the seeded file still records base:' feat/T-600-demo "$(progress_field T-600-01 base)"
check 'the seeded ## Remaining is committed in the state clone' 2 \
  "$(git -C "$state" show HEAD:repos/demo/progress/T-600-01.md 2>/dev/null | grep -cE '^- \[ \] [ab]$')"

add T-600-02
check 'a block with an existing progress file exits 0' 0 "$rc"
check 'an existing progress file keeps its sections as they are' "$(cat "$tmp/T-600-02.before")" \
  "$(grep -vE '^base(_sha)?:' "$existing")"

check 'a block with no checklist gets no ## Remaining' 0 \
  "$(grep -cxF '## Remaining' "$state/repos/demo/progress/T-300-01.md")"

exit $fail
