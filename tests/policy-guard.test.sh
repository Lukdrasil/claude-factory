#!/bin/sh
# policy-guard.sh over Bash commands, T-228-01: segments split only outside quotes and heredoc bodies, `cd <abs>`
# carried across segments, a parent's owner reading its blocks, the pinned lease, and the state-clone commit rule.
# Every deny the fixes keep is replayed beside them (QS-01).
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
H=$tmp/home
W=$H/factory
C=$H/clones
q="'"
sha=0123456789abcdef0123456789abcdef01234567

mkdir -p "$W/state/repos/cf/tasks" "$W/cf/T-900" "$W/cf/T-900-01" "$W/cf/T-900-02" "$W/cf/.harness/T-900" \
  "$C/cf" "$C/userorg"
printf 'cf: {url: "https://forge.test/cf.git", default_branch: main, path: "%s"}\nuserorg: {url: "https://forge.test/u.git", default_branch: main, path: "%s"}\n' \
  "$C/cf" "$C/userorg" > "$W/state/repos.yml"
task() { # <id> <branch> <owner sid> <phase>
  printf -- '---\nid: %s\nrepo: cf\nbranch: %s\nstatus: in_progress\narchetype: bugfix\nphase: %s\nowner: factory@host:%s\n---\n\n# Goal\nx\n' \
    "$1" "$2" "$4" "$3" > "$W/state/repos/cf/tasks/$1.md"
}
task T-900 feat/T-900 coord null
task T-900-01 block/T-900-01 blk tests
task T-900-02 block/T-900-02 blk2 tests
task T-901 feat/T-901 other null
task T-901-01 block/T-901-01 other tests
printf 'brief\n' > "$W/cf/.harness/T-900/brief-T-900-01.md"
printf 'x\n' > "$C/cf/README.md"

try() { # <want exit> <label> <cwd> <session id> <command>
  node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",cwd:process.argv[1],session_id:process.argv[2],tool_input:{command:process.argv[3]}}))' \
    "$3" "$4" "$5" | env -u HARNESS_WORKER HOME="$H" WORK_DIR="$W" sh "$root/bin/policy-guard.sh" >/dev/null 2>"$tmp/err"
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'PASS %s\n' "$2"; return; fi
  printf 'FAIL want=%s got=%s %s: %s\n' "$1" "$got" "$2" "$(head -c 200 "$tmp/err")"
  fail=1
}
BLK=$W/cf/T-900-01
PAR=$W/cf/T-900

# the expected-exit list of ## Context
try 0 'cd ~/factory/state, then sed -i on a verdict, from the userorg clone' "$C/userorg" coord \
  "cd ~/factory/state && sed -i ${q}s/^verdict: aligned\$/verdict: misaligned/${q} repos/userorg/verdicts/x.md"
try 0 'cd /tmp/scratch, then a heredoc into digest.py, from the claude-factory clone' "$C/cf" coord \
  "cd /tmp/scratch && cat > digest.py <<'EOF'
import json
print(json.dumps({\"ok\": 1}))
EOF"
try 0 'a redirect into $S/t196-dup.txt' "$C/cf" coord '> $S/t196-dup.txt'
try 0 'tee into $S/t196-dup.txt from the registered clone' "$C/cf" coord 'sort a.txt | tee $S/t196-dup.txt'
try 0 'sed -i on $S/x.txt from the registered clone' "$C/cf" coord "sed -i ${q}s/a/b/${q} \$S/x.txt"
try 0 'the pieces of a quoted sed script are not write targets' "$C/userorg" coord \
  "sed -i ${q}s/^verdict: aligned\$/verdict: misaligned/${q} /tmp/x.md"
try 0 'a block cats its own brief' "$BLK" blk "cat $W/cf/.harness/T-900/brief-T-900-01.md"
try 0 'the coordinator runs git -C <block> log' "$C/cf" coord "git -C $BLK log --oneline -5"
try 0 'the coordinator runs git -C <block> diff' "$C/cf" coord "git -C $BLK diff main...HEAD"
try 0 'the coordinator runs git -C <block> status' "$C/cf" coord "git -C $BLK status --short"
try 0 'the coordinator runs git -C <block> show' "$C/cf" coord "git -C $BLK show HEAD --stat"
try 0 'the coordinator cats a file of its block' "$C/cf" coord "cat $BLK/tests/x.test.sh"
try 0 'the coordinator lists its block' "$C/cf" coord "ls $BLK/tests"
try 0 'a block pushes its own branch with a pinned lease' "$BLK" blk \
  "git push --force-with-lease=block/T-900-01:$sha origin block/T-900-01"
try 0 'the coordinator pushes the parent branch through -C with a pinned lease' "$C/cf" coord \
  "git -C $PAR push --force-with-lease=feat/T-900:$sha origin feat/T-900"
try 0 'a quoted && inside a printf argument' "$BLK" blk "printf '%s\n' \"see $W/cf/T-900-02/notes.md && more\""
try 0 'a heredoc into python3 whose body names --force-with-lease' "$C/cf" coord "python3 - <<'EOF'
print('git push --force-with-lease origin main')
EOF"
try 2 'git commit -m x with the state clone as cwd' "$W/state" coord 'git commit -m x'
try 2 'git -C <state clone> commit -m x' "$C/cf" coord "git -C $W/state commit -m x"
try 2 'cd <state clone>, then git commit -m x' "$C/cf" coord "cd $W/state && git commit -m x"
try 2 'git commit -a -m x in the state clone' "$W/state" coord 'git commit -a -m x'
try 2 'git commit -am x in the state clone' "$W/state" coord 'git commit -am x'
try 2 'git commit --all with a pathspec in the state clone' "$W/state" coord 'git commit --all -m x -- repos/cf/tasks/T-900.md'
try 2 'cd rel, then a relative write' "$BLK" blk 'cd rel && echo x > y'
try 2 'cd -, then a relative write' "$BLK" blk 'cd - && echo x > y'
try 2 'cd $D, then a relative write' "$BLK" blk 'cd $D && echo x > y'
try 0 'cd ~, then a relative write' "$C/cf" coord 'cd ~ && echo x > notes.txt'
try 2 'cd rel, then cd /tmp, then a relative write' "$C/cf" coord 'cd rel && cd /tmp && echo x > y'

# the denies the fixes keep
try 2 'a force push' "$BLK" blk 'git push --force origin block/T-900-01'
try 2 'a force push with -f' "$BLK" blk 'git push -f origin block/T-900-01'
try 2 'a pinned lease on the default branch' "$BLK" blk "git push --force-with-lease=main:$sha origin main"
try 2 'a bare lease on the default branch' "$BLK" blk 'git push --force-with-lease origin main'
try 2 'a pinned lease on another branch than the one pushed' "$BLK" blk \
  "git push --force-with-lease=main:$sha origin block/T-900-01"
try 2 'a block pins a lease on its parent branch' "$BLK" blk "git push --force-with-lease=feat/T-900:$sha origin feat/T-900"
try 2 'two leases in one command' "$BLK" blk \
  'git push --force-with-lease origin block/T-900-01 && git push --force-with-lease origin block/T-900-01'
try 2 'the coordinator pushes a block branch through -C <parent>' "$C/cf" coord \
  "git -C $PAR push --force-with-lease=block/T-900-01:$sha origin block/T-900-01"
try 2 'the coordinator leases through -C on a dir that is not the parent worktree' "$C/cf" coord \
  "git -C /tmp/x push --force-with-lease=feat/T-900:$sha origin feat/T-900"
try 2 'a session that does not own the parent leases through -C <parent>' "$C/cf" other \
  "git -C $PAR push --force-with-lease=feat/T-900:$sha origin feat/T-900"
try 2 'the coordinator leases from the registered clone without -C' "$C/cf" coord \
  "git push --force-with-lease=feat/T-900:$sha origin feat/T-900"
try 2 'a heredoc into sh whose body is a lease push' "$C/cf" coord "sh <<'EOF'
git push --force-with-lease origin main
EOF"
try 2 'a relative redirect into the registered clone' "$C/cf" coord 'echo x > README.md'
try 2 'sed -i with a spaced script on a file of the registered clone' "$C/cf" coord "sed -i ${q}s/a b/c d/${q} README.md"
try 2 'an unquoted && still splits before a write into the clone' "$C/cf" coord 'echo ok && echo x > README.md'
try 2 'cd <registered clone>, then a relative write' "$BLK" blk "cd $C/cf && echo x > y"
try 2 'cd ~/<registered clone>, then a relative write' "$BLK" blk 'cd ~/clones/cf && echo x > y'
try 2 'a block writes into a sibling block' "$BLK" blk "echo x > $W/cf/T-900-02/f"
try 2 'the coordinator removes files in its block' "$C/cf" coord "rm -rf $BLK/src"
try 2 'the coordinator runs git checkout in its block' "$C/cf" coord "git -C $BLK checkout -- ."
try 2 'the coordinator redirects a cat into its block' "$C/cf" coord "cat /tmp/x > $BLK/f"
try 2 'a session that does not own the parent runs git -C <block> log' "$C/cf" other "git -C $BLK log"
try 2 'the coordinator cats a block of a parent it does not own' "$C/cf" coord "cat $W/cf/T-901-01/f"
try 2 'a block cats the brief of a sibling block' "$BLK" blk "cat $W/cf/.harness/T-900/brief-T-900-02.md"
try 2 'a block cats a file of its parent worktree' "$BLK" blk "cat $PAR/f"
try 2 'a mention with ..' "$BLK" blk "cat $W/cf/../x"

# what stays allowed today
try 0 'git commit with a pathspec in the state clone' "$W/state" coord 'git commit -m x -- repos/cf/tasks/T-900.md'
try 0 'git add in the state clone' "$W/state" coord 'git add repos/cf/tasks/T-900.md'
try 0 'git commit -m x in a block worktree' "$BLK" blk 'git commit -m x'
try 0 'a bare lease on the own branch' "$BLK" blk 'git push --force-with-lease origin block/T-900-01'
try 0 'a bare lease with -u on the own branch' "$BLK" blk 'git push -u --force-with-lease origin block/T-900-01'
try 0 'a quoted mention of a sibling block without &&' "$BLK" blk "printf '%s\n' \"see $W/cf/T-900-02/notes.md\""
try 0 'cd rel, then an absolute write into /tmp' "$BLK" blk 'cd rel && echo x > /tmp/y'
try 0 'cd rel, then a read' "$BLK" blk 'cd rel && cat y'
try 0 'a relative write in the own worktree' "$BLK" blk 'echo x > notes.md'

# T-228-06: a cd carries the cwd across && only, and a command substitution is never a read
try 2 'cd /tmp/typo; then sed -i on a relative file of the registered clone' "$C/cf" coord 'cd /tmp/typo; sed -i s/a/b/ README.md'
try 2 'cd /tmp || then a relative redirect into the registered clone' "$C/cf" coord 'cd /tmp || echo x > README.md'
try 2 'cd /tmp | then a relative redirect into the registered clone' "$C/cf" coord 'cd /tmp | echo x > README.md'
try 2 'a cd inside a subshell, then a relative redirect into the registered clone' "$C/cf" coord '(true; cd /tmp); echo x > README.md'
try 2 'a cd inside a subshell joined by &&, then a relative redirect into the registered clone' "$C/cf" coord '(true && cd /tmp) && echo x > README.md'
try 0 'cd /tmp/scratch && sed -i on a relative file, from the registered clone' "$C/cf" coord "cd /tmp/scratch && sed -i ${q}s/a/b/${q} x.md"
try 2 'the coordinator cats a $(git -C <block> reset)' "$C/cf" coord "cat \$(git -C $BLK reset --hard HEAD~3)"
try 2 'the coordinator cats a $(touch <block>/x)' "$C/cf" coord "cat \$(touch $BLK/x)"
try 2 'the coordinator cats a backtick git -C <block> reset' "$C/cf" coord "cat \`git -C $BLK reset --hard HEAD~3\`"
try 2 'the coordinator cats a backtick touch <block>/x' "$C/cf" coord "cat \`touch $BLK/x\`"
try 2 'the coordinator cats a <(git -C <block> reset)' "$C/cf" coord "cat <(git -C $BLK reset --hard HEAD~3)"
try 2 'the coordinator cats a <(touch <block>/x)' "$C/cf" coord "cat <(touch $BLK/x)"
try 2 'the coordinator cats a >(git -C <block> reset)' "$C/cf" coord "cat >(git -C $BLK reset --hard HEAD~3)"
try 2 'the coordinator cats a >(touch <block>/x)' "$C/cf" coord "cat >(touch $BLK/x)"
try 0 'the coordinator runs git -C <block> log --oneline -3' "$C/cf" coord "git -C $BLK log --oneline -3"
try 0 'the coordinator cats <block>/README.md' "$C/cf" coord "cat $BLK/README.md"
try 2 'git -C "<state clone>" commit -m x' "$C/cf" coord "git -C \"$W/state\" commit -m x"
try 2 'git commit -m x -- with no path, in the state clone' "$W/state" coord 'git commit -m x --'
try 0 'cd rel, then sed -i with a quoted script on an absolute file' "$BLK" blk "cd rel && sed -i ${q}s/a/b/${q} /tmp/x.md"
try 0 'cd rel, then sed -i with an unquoted script on an absolute file' "$BLK" blk 'cd rel && sed -i s/a/b/ /tmp/x.md'
try 2 'cd rel, then sed -i on a relative file' "$BLK" blk "cd rel && sed -i ${q}s/a/b/${q} x.md"
try 0 'cd rel, then sed -i on $S/x.txt' "$BLK" blk "cd rel && sed -i ${q}s/a/b/${q} \$S/x.txt"
try 2 'a cd entered through |, then && a relative redirect into the registered clone' "$C/cf" coord 'echo | cd /tmp && echo x > README.md'
try 2 'a cd entered through |, then ; a relative redirect into the registered clone' "$C/cf" coord 'true | cd /tmp; echo x > README.md'

# T-228-07: a cd carries the cwd only while its && chain holds, a lost cd judges paths and not command words, and a
# state-clone commit counts only the words after its bare --
try 2 'cd /nonexistent && make ||, then a relative redirect into the registered clone' "$C/cf" coord 'cd /nonexistent && make || echo x > README.md'
try 2 'cd /tmp && true;, then a relative redirect into the registered clone' "$C/cf" coord 'cd /tmp && true; echo x > README.md'
try 2 'a subshell cd whose ) closes a later segment, then a relative redirect into the registered clone' "$C/cf" coord '(true; cd /tmp && true); echo x > README.md'
try 2 'a cd inside $( ), then a relative redirect into the registered clone' "$C/cf" coord 'echo $(true; cd /tmp && pwd) > README.md'
try 0 'cd /tmp/scratch && true &&, then a relative write, from the registered clone' "$C/cf" coord 'cd /tmp/scratch && true && echo x > y'
try 2 'a closed (, then cd /tmp/scratch && a relative write, from the registered clone' "$C/cf" coord '(true); cd /tmp/scratch && echo x > y'
try 2 'a closed $(, then cd /tmp/scratch && a relative write, from the registered clone' "$C/cf" coord 'echo $(pwd); cd /tmp/scratch && echo x > y'
try 2 'a quoted (, then cd /tmp/scratch && a relative write, from the registered clone' "$C/cf" coord 'echo "("; cd /tmp/scratch && echo x > y'
try 0 'cd "$d", then make | tee on an absolute file' "$BLK" blk 'cd "$d" && make | tee /tmp/b.log'
try 0 'cd sub, then git checkout x' "$BLK" blk 'cd sub && git checkout x'
try 2 'cd "$d", then sed -i on a relative file' "$BLK" blk 'cd "$d" && sed -i s/a/b/ x.md'
try 2 'git commit -m "a -- b" -- with no path, in the state clone' "$W/state" coord 'git commit -m "a -- b" --'
try 0 'git commit -m "a -- b" -- with a path, in the state clone' "$W/state" coord 'git commit -m "a -- b" -- repos/x/tasks/T-1.md'
try 0 'git commit -m x -- with a quoted path, in the state clone' "$W/state" coord 'git commit -m x -- "repos/cf/tasks/T-900.md"'

# T-228-08: a cd replaces the base only in a plain chain of `cd <abs>` && simple commands. In every other shape, and
# after a cd the guard cannot resolve, a relative target is judged against the hook cwd and every cd target seen.
try 2 'cd <clones dir> && cd cf, then git checkout -- README.md' "$C/cf" coord "cd $C && cd cf && git checkout -- README.md"
try 2 'cd <clones dir> && cd cf, then tee README.md' "$C/cf" coord "cd $C && cd cf && tee README.md"
try 2 'cd /tmp && pushd <clone>, then a relative redirect' "$C/cf" coord "cd /tmp && pushd $C/cf && echo x > README.md"
try 2 'pushd . && cd /tmp && popd, then a relative redirect' "$C/cf" coord 'pushd . && cd /tmp && popd && echo x > README.md'
try 2 'cd /tmp && builtin cd -, then a relative redirect' "$C/cf" coord 'cd /tmp && builtin cd - && echo x > README.md'
try 2 'cd /tmp && eval cd -, then a relative redirect' "$C/cf" coord 'cd /tmp && eval cd - && echo x > README.md'
try 2 'a case ) inside a subshell with a cd, then a relative redirect' "$C/cf" coord '(case a in a) ;; esac; cd /tmp && true) && echo x > README.md'
try 2 'cd /tmp && CDPATH=<clones dir> cd cf, then a relative redirect' "$C/cf" coord "cd /tmp && CDPATH=$C cd cf && echo x > README.md"
try 2 'an escaped ) inside a subshell with a cd, then a relative redirect' "$C/cf" coord '(echo \); cd /tmp && true) && echo x > README.md'
try 2 'cd /tmp && command cd <clone>, then a relative redirect' "$C/cf" coord "cd /tmp && command cd $C/cf && echo x > README.md"
try 2 'cd /tmp && . ./env.sh, then a relative redirect' "$C/cf" coord 'cd /tmp && . ./env.sh && echo x > README.md'
try 2 'cd /a; cd /b; then a relative redirect' "$C/cf" coord 'cd /a; cd /b; echo x > README.md'
try 0 'git push from the state clone' "$W/state" coord 'git push'
try 0 'cd /nonexistent && true; git push from the state clone' "$W/state" coord 'cd /nonexistent && true; git push'
try 0 'cd <state clone>; git push from the registered clone' "$C/cf" coord "cd $W/state; git push"
try 2 'git -C ~/<state clone> commit -m x' "$C/cf" coord 'git -C ~/factory/state commit -m x'
try 0 'git -C ~/<state clone> commit -m x -- <file>' "$C/cf" coord 'git -C ~/factory/state commit -m x -- repos/cf/tasks/T-900.md'
try 2 'git commit -m x -- . in the state clone' "$W/state" coord 'git commit -m x -- .'
try 2 'git commit -m x -- :/ in the state clone' "$W/state" coord 'git commit -m x -- :/'
try 2 'git commit -m x -- repos/ in the state clone' "$W/state" coord 'git commit -m x -- repos/'
try 2 'git commit -m x -- <a directory without a slash> in the state clone' "$W/state" coord 'git commit -m x -- repos/cf/tasks'
try 0 'cd /tmp && cd /tmp/scratch, then a relative write, from the registered clone' "$C/cf" coord 'cd /tmp && cd /tmp/scratch && echo x > y'
try 0 'cd /tmp/scratch && a pipe into a relative redirect, from the registered clone' "$C/cf" coord 'cd /tmp/scratch && make | sort > out.txt'
try 0 'cd /tmp/scratch && a quoted ; and ( in a relative write, from the registered clone' "$C/cf" coord 'cd /tmp/scratch && echo "a; b (c)" > y'

# T-254-02: a created issue carries the ai-drafted label, as one comma-separated value of --label or -l, and the
# deny names bin/issue-create.sh, which adds it
try 2 'gh issue create without a label' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md'
if grep -q 'issue-create\.sh' "$tmp/err"; then printf 'PASS the label deny names bin/issue-create.sh\n'
else printf 'FAIL the label deny names bin/issue-create.sh: %s\n' "$(head -c 200 "$tmp/err")"; fail=1; fi
try 2 'glab issue create without a label' "$C/cf" coord 'glab issue create --title "fix: x" --description-file /tmp/b.md'
try 2 'gh issue create with another label' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md --label bug'
try 2 'gh issue create with a label that only contains ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md --label not-ai-drafted'
try 2 'gh issue create with a label that only starts with ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md -l ai-drafted-later'
try 2 'glab issue create -l bug' "$C/cf" coord 'glab issue create --title "fix: x" --description-file /tmp/b.md -l bug'
try 2 'an unlabelled create, then a labelled one in the next segment' "$C/cf" coord \
  'gh issue create --title "fix: y" --body-file /tmp/b.md && gh issue create --title "fix: x" --body-file /tmp/b.md --label ai-drafted'
try 0 'gh issue create --label ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md --label ai-drafted'
try 0 'gh issue create --label=ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md --label=ai-drafted'
try 0 'gh issue create -l ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md -l ai-drafted'
try 0 'gh issue create -l=ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md -l=ai-drafted'
try 0 'gh issue create -l bug,ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md -l bug,ai-drafted'
try 0 'gh issue create --label ai-drafted,bug' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md --label ai-drafted,bug'
try 0 'gh issue create --label "ai-drafted"' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md --label "ai-drafted"'
try 0 "gh issue create --label 'bug,ai-drafted'" "$C/cf" coord "gh issue create --title \"fix: x\" --body-file /tmp/b.md --label ${q}bug,ai-drafted${q}"
try 0 'gh issue create --label bug --label ai-drafted' "$C/cf" coord 'gh issue create --title "fix: x" --body-file /tmp/b.md --label bug --label ai-drafted'
try 0 'gh issue create -R with the label before the title' "$C/cf" coord 'gh issue create -R github.com/acme/w --label ai-drafted --title "fix: x" --body-file /tmp/b.md'
try 0 'glab issue create -l ai-drafted' "$C/cf" coord 'glab issue create --title "fix: x" --description-file /tmp/b.md -l ai-drafted'
try 0 'glab issue create --label ai-drafted' "$C/cf" coord 'glab issue create -R gitlab.example.com/g/w --title "fix: x" --description-file /tmp/b.md --label ai-drafted'
# a mention inside quotes is no create: the create pattern reads the segment with its quoted spans removed
try 0 'a commit message naming gh issue create mid-quote' "$C/cf" coord 'git commit -m "docs: gh issue create is denied without the label"'
try 0 'an echo naming glab issue create mid-quote' "$C/cf" coord 'echo "run glab issue create with the label"'
try 0 'bin/issue-create.sh is not a direct create' "$C/cf" coord 'sh bin/issue-create.sh cf --title "fix: x" --body-file /tmp/b.md'
try 0 'gh issue list stays allowed' "$C/cf" coord 'gh issue list --state open --limit 100'
try 0 'glab issue list stays allowed' "$C/cf" coord 'glab issue list --per-page 100'

exit $fail
