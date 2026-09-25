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
printf 'cf: {url: "https://forge.test/cf.git", default_branch: main, path: "%s"}\nuserorg: {url: "https://forge.test/u.git", default_branch: main, path: "%s"}\ndemo: {url: "https://forge.test/demo.git", default_branch: main, path: "%s"}\n' \
  "$C/cf" "$C/userorg" "$W/src/ui-demo" > "$W/state/repos.yml"
git init -q "$W/src/ui-demo"
git -C "$W/src/ui-demo" -c user.name=t -c user.email=t@t.test -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$W/src/ui-demo" worktree add -q "$W/src/ui-demo-wt" 2>/dev/null
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
home=$H
role=''
proj=''

try() { # <want exit> <label> <cwd> <session id> <command>
  node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",cwd:process.argv[1],session_id:process.argv[2],tool_input:{command:process.argv[3]}}))' \
    "$3" "$4" "$5" | env -u HOME -u FACTORY_ROLE -u CLAUDE_PROJECT_DIR ${home:+HOME=$home} ${role:+FACTORY_ROLE=$role} \
    ${proj:+CLAUDE_PROJECT_DIR=$proj} WORK_DIR="$W" sh "$root/bin/policy-guard.sh" >/dev/null 2>"$tmp/err"
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

# T-264-01: a registered clone under the work root takes the standalone posture, not the catch-all's own dir
try 0 'the coordinator runs git -C <parent> rev-parse from a registered clone under the work root' "$W/src/ui-demo" coord \
  "git -C $PAR rev-parse HEAD"
try 0 'the coordinator cats <parent>/README.md from a registered clone under the work root' "$W/src/ui-demo" coord \
  "cat $PAR/README.md"
try 2 'a worktree of a registered clone under the work root keeps the catch-all' "$W/src/ui-demo-wt" coord \
  "cat $PAR/README.md"
try 2 'a block writes into a sibling block, T-264 regression' "$BLK" blk "echo x > $W/cf/T-900-02/x"
try 2 'a write from the state clone to outside it and outside /tmp, T-264 regression' "$W/state" coord \
  'echo x > /opt/outside.txt'

# T-264-02: a redirect target is read off the segment with the quote tracking of split_segs, escapes included, and
# `~` and `~/x` expand to $HOME in both target loops. A quoted `~` stays relative to the cwd, as the shell writes it.
try 0 'printf into ~/.claude-factory/… && mv it, from the registered clone' "$C/cf" coord \
  'printf x > ~/.claude-factory/ui/sessions/x/visual.md.tmp && mv ~/.claude-factory/ui/sessions/x/visual.md.tmp ~/.claude-factory/ui/sessions/x/visual.md'
try 0 "a grep pattern quoting '>', from the registered clone" "$C/cf" coord "grep -n \"'>'\\|redirect\\|tilde\" bin/policy-guard.sh"
try 0 "a grep pattern quoting '>' and a later quote, from the registered clone" "$C/cf" coord \
  "grep -n \"'>'\\|redirect\\|tilde\\|'~'\" bin/policy-guard.sh"
try 0 'tee ~/x, from the registered clone' "$C/cf" coord 'tee ~/x < /dev/null'
try 0 'an escaped quote inside a quoted span, then a redirect to /tmp, from the registered clone' "$C/cf" coord \
  "printf '%s\\n' \"a\\\"b > c\" > /tmp/y"
try 2 'an escaped quote, then a relative redirect into the registered clone' "$C/cf" coord 'echo \" > README.md \"'
try 2 'a redirect to ~/<registered clone>/README.md' "$C/cf" coord 'echo x > ~/clones/cf/README.md'
try 2 'tee ~/<registered clone>/README.md' "$C/cf" coord 'tee ~/clones/cf/README.md < /dev/null'
try 2 'a quoted relative redirect into the registered clone' "$C/cf" coord 'echo x > "README.md"'
try 2 'a quoted ~/ target, relative to the registered clone' "$C/cf" coord 'echo x > "~/y"'
try 0 'a quoted ~/ target, relative to the own worktree' "$BLK" blk 'echo x > "~/y"'
try 2 'a 2> redirect into the registered clone' "$C/cf" coord 'echo x 2> README.md'
try 2 'a &> redirect into the registered clone' "$C/cf" coord 'echo x &> README.md'
try 2 'a >> redirect into the registered clone' "$C/cf" coord 'echo x >> README.md'
try 2 'a redirect with no space into the registered clone' "$C/cf" coord 'echo x >README.md'
try 2 'a quoted >, then a relative redirect into the registered clone' "$C/cf" coord 'echo "a > b" > README.md'
try 2 'a second redirect into the registered clone' "$C/cf" coord 'echo x > /tmp/y 2> README.md'
try 0 "a quoted >, then a redirect to /tmp, from the registered clone" "$C/cf" coord "echo ${q}a > b${q} > /tmp/y"
try 0 'a quoted $S redirect target, from the registered clone' "$C/cf" coord 'echo x > "$S/x"'
try 0 '>&2 and 2>&1 name no file, from the registered clone' "$C/cf" coord 'echo x >&2 2>&1'
try 0 'an arrow after = or - is not a redirect, from the registered clone' "$C/cf" coord 'echo x=>y a->b'
home=''
try 2 'with HOME unset, a redirect to ~/y' "$BLK" blk 'echo x > ~/y'
try 2 'with HOME unset, tee ~/y' "$BLK" blk 'tee ~/y < /dev/null'
home=$H

# T-264-07: a `'` after an unquoted `$` opens an ANSI-C span, where `\'` is an escaped quote and the span closes only
# at an unescaped `'`. A plain `'…'` and a `'` after an escaped `\$` keep no escapes. `>&word` writes the file word,
# only `>&N` and `>&-` name no file.
try 2 "echo \$'\\'' into the registered clone" "$C/cf" coord "echo \$${q}\\${q}${q} > README.md"
try 2 "printf \$'it\\'s' into the registered clone" "$C/cf" coord "printf \$${q}it\\${q}s${q} > README.md"
try 0 'a > inside an ANSI-C span with an escaped quote, then a redirect to /tmp, from the registered clone' "$C/cf" coord \
  "echo \$${q}a\\${q}> README.md${q} > /tmp/y"
try 2 "an ANSI-C span ending in an escaped backslash, then a relative redirect into the registered clone" "$C/cf" coord \
  "echo \$${q}a\\\\${q} > README.md"
try 2 "a plain single-quoted backslash, then a relative redirect into the registered clone" "$C/cf" coord \
  "echo ${q}\\${q} > README.md"
try 2 "an escaped \$ before a single-quoted backslash, then a relative redirect into the registered clone" "$C/cf" coord \
  "echo \\\$${q}\\${q} > README.md"
try 2 "a redirect to \$'README.md' in the registered clone" "$C/cf" coord "echo x > \$${q}README.md${q}"
try 2 '>&README.md into the registered clone' "$C/cf" coord 'echo x >&README.md'
try 2 '>& README.md into the registered clone' "$C/cf" coord 'echo x >& README.md'
try 0 '>&2 names no file, from the registered clone' "$C/cf" coord 'echo x >&2'
try 0 '2>&- names no file, from the registered clone' "$C/cf" coord 'echo x 2>&-'
try 0 '>& 2 names no file, from the registered clone' "$C/cf" coord 'echo x >& 2'
try 0 '>&- names no file, from the registered clone' "$C/cf" coord 'echo x >&-'
try 2 "\$\$ before a single-quoted backslash is the PID and a plain quote, then a redirect into the registered clone" "$C/cf" coord \
  "echo \$\$${q}\\${q} > README.md"
try 2 '>&/abs outside the work dir, from a block' "$BLK" blk 'echo x >&/opt/outside.txt'

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

# T-252-03: a cwd under $W that is not a task worktree is confined to its own top-level directory, and the
# coordinator reach of coord_scope and read_scope stays closed from there. The target is judged, never written,
# and sits outside /tmp, which check_path allows from any cwd (issue #358), so it cannot live under $H.
try 2 'a state-clone session writes outside $W' "$W/state" coord 'printf x > /home/t252/outside.txt'
try 2 'a key-dir session writes outside $W' "$W/cf" coord 'printf x > /home/t252/outside.txt'
try 0 'the registered clone writes the same path' "$C/cf" coord 'printf x > /home/t252/outside.txt'
try 0 'a state-clone session writes inside the state clone' "$W/state" coord "printf x > $W/state/notes.txt"
try 0 'a key-dir session writes inside its key dir' "$W/cf" coord "printf x > $W/cf/notes.txt"
try 2 'a state-clone session writes the stamp dir of a task it owns' "$W/state" coord "printf x > $W/cf/.harness/T-900/x.md"
try 2 'a state-clone session reads a block of a task it owns' "$W/state" coord "cat $BLK/tests/x.test.sh"

# R3: the human gates are the CEO's and the lead's, after the human's yes. A session a monitor dispatched carries
# FACTORY_ROLE; any role but ceo and repo-lead is denied task-approve.sh, task-done.sh, block-mr-merge.sh
# --confirmed and curate-apply.sh approve, however the script is spelled. No FACTORY_ROLE is a human's own session.
P=/plug/bin
S=$W/state
for role in triage implementer; do
  try 2 "$role: sh task-approve.sh" "$S" coord "sh $P/task-approve.sh T-900 --state $S"
  try 2 "$role: task-approve.sh by its path" "$S" coord "$P/task-approve.sh T-900 --state $S"
  try 2 "$role: bash task-approve.sh with a quoted path" "$S" coord "bash \"$P/task-approve.sh\" T-900"
  try 2 "$role: task-done.sh" "$S" coord "sh $P/task-done.sh T-900 --state $S"
  try 2 "$role: task-done.sh --close" "$S" coord "sh $P/task-done.sh T-900 --close ${q}no MR${q} --state $S"
  try 2 "$role: block-mr-merge.sh --confirmed" "$S" coord "sh $P/block-mr-merge.sh T-900-01 --confirmed"
  try 2 "$role: curate-apply.sh approve" "$S" coord "sh $P/curate-apply.sh approve repos/cf/x.md --state $S"
  try 2 "$role: cd, then task-approve.sh" "$C/cf" coord "cd $S && sh $P/task-approve.sh T-900"
  try 2 "$role: task-done.sh after a ; in a chain" "$S" coord "git pull --ff-only; $P/task-done.sh T-900"
  try 2 "$role: task-approve.sh after an env assignment" "$S" coord "X=1 sh $P/task-approve.sh T-900"
  try 2 "$role: task-approve.sh inside bash -c" "$S" coord "bash -c ${q}cd $S && sh $P/task-approve.sh T-900${q}"
  try 0 "$role: block-mr-merge.sh without --confirmed" "$S" coord "sh $P/block-mr-merge.sh T-900-01"
  try 0 "$role: curate-apply.sh list" "$S" coord "sh $P/curate-apply.sh list --state $S"
  try 0 "$role: a commit message naming task-approve.sh" "$C/cf" coord "git commit -m ${q}fix: task-approve.sh reads the lock${q}"
  try 0 "$role: a test named after a gate" "$C/cf" coord 'sh tests/task-done.test.sh'
done
role=ceo
try 0 'ceo: task-approve.sh' "$S" coord "sh $P/task-approve.sh T-900 --state $S"
try 0 'ceo: task-done.sh' "$S" coord "sh $P/task-done.sh T-900 --state $S"
try 0 'ceo: task-done.sh --close' "$S" coord "sh $P/task-done.sh T-900 --close ${q}no MR${q} --state $S"
try 0 'ceo: curate-apply.sh approve' "$S" coord "sh $P/curate-apply.sh approve repos/cf/x.md --state $S"
try 2 'ceo: block-mr-merge.sh --confirmed' "$S" coord "sh $P/block-mr-merge.sh T-900-01 --confirmed"
role=repo-lead
try 0 'repo-lead: block-mr-merge.sh --confirmed' "$PAR" coord "sh $P/block-mr-merge.sh T-900-01 --confirmed"
try 0 'repo-lead: block-mr-merge.sh without --confirmed' "$PAR" coord "sh $P/block-mr-merge.sh T-900-01"
try 0 'repo-lead: task-done.sh' "$PAR" coord "sh $P/task-done.sh T-900 --state $S"
try 2 'repo-lead: task-done.sh --close' "$PAR" coord "sh $P/task-done.sh T-900 --close ${q}no MR${q} --state $S"
try 2 'repo-lead: task-approve.sh' "$PAR" coord "sh $P/task-approve.sh T-900 --state $S"
try 2 'repo-lead: curate-apply.sh approve' "$PAR" coord "sh $P/curate-apply.sh approve repos/cf/x.md --state $S"
role=''
try 0 'no role: task-approve.sh' "$S" coord "sh $P/task-approve.sh T-900 --state $S"
try 0 'no role: task-done.sh --close' "$S" coord "sh $P/task-done.sh T-900 --close ${q}no MR${q} --state $S"
try 0 'no role: block-mr-merge.sh --confirmed' "$S" coord "sh $P/block-mr-merge.sh T-900-01 --confirmed"
try 0 'no role: curate-apply.sh approve' "$S" coord "sh $P/curate-apply.sh approve repos/cf/x.md --state $S"

# a lead whose shell cd'ed into the state clone keeps the posture of the worktree it was launched in
# (CLAUDE_PROJECT_DIR), so it can cd back and read its blocks; the state clone as launch dir changes nothing
role=repo-lead proj=$PAR
try 0 'launched in the parent worktree, cwd the state clone: cd back to the worktree' "$W/state" coord "cd $PAR && pwd"
try 0 'launched in the parent worktree, cwd the state clone: git -C <own block> log' "$W/state" coord "git -C $BLK log --oneline -3"
try 2 'launched in the parent worktree, cwd the state clone: a write into another parent stays denied' "$W/state" coord "touch $W/cf/T-901/x"
proj=$W/state
try 2 'launched in the state clone: git -C <a block> log stays denied' "$W/state" coord "git -C $BLK log --oneline -3"
role='' proj=''

# C7 (add-repo F4): an onboarding session (FACTORY_ROLE=onboard, FACTORY_UNIT=onboard-<key>) runs in the registered
# clone it reports on, launched there, and works from an allowlist: it writes only <state>/repos/<key>/onboarding.md,
# runs only factory-doctor.sh, doc-cites.sh, state-commit.sh of that file, ui-ask.sh and ui-session.sh, drives herdr
# only with `agent prompt ceo` and `tab close` of its own tab, and never pushes
ob() { # <want exit> <label> <Bash|Write|Edit> <cwd> <command or path>
  node -e 'const [t,c,x]=process.argv.slice(1);process.stdout.write(JSON.stringify({tool_name:t,cwd:c,session_id:"onb",
    tool_input:t==="Bash"?{command:x}:t==="Edit"?{file_path:x,old_string:"a",new_string:"b"}:{file_path:x,content:"# Onboarding\n"}}))' \
    "$3" "$4" "$5" | env -u CLAUDE_PROJECT_DIR HOME="$H" FACTORY_ROLE=onboard FACTORY_UNIT=onboard-cf HERDR_TAB_ID=tab-3 \
    CLAUDE_PROJECT_DIR="$C/cf" WORK_DIR="$W" sh "$root/bin/policy-guard.sh" >/dev/null 2>"$tmp/err"
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'PASS onboard: %s\n' "$2"; return; fi
  printf 'FAIL onboard: want=%s got=%s %s: %s\n' "$1" "$got" "$2" "$(head -c 200 "$tmp/err")"
  fail=1
}
O=$S/repos/cf/onboarding.md
ob 0 'Write its report'                           Write "$C/cf" "$O"
ob 0 'Edit its report from the state clone'       Edit "$S" "$O"
ob 0 'a heredoc into its report'                  Bash "$C/cf" "cat > $O <<'EOF'
# Onboarding of cf
EOF"
ob 0 'factory-doctor.sh --repo'                   Bash "$C/cf" "sh $P/factory-doctor.sh --root $W --repo $C/cf"
ob 0 'doc-cites.sh'                               Bash "$C/cf" "sh $P/doc-cites.sh $C/cf"
ob 0 'state-commit.sh of its report'              Bash "$C/cf" "sh $P/state-commit.sh -m ${q}chore(cf): onboarding started${q} -- repos/cf/onboarding.md"
ob 0 'state-commit.sh of its report, absolute, with --state' Bash "$C/cf" \
  "sh $P/state-commit.sh -m \"chore(cf): onboarding report\" --state $S -- $O"
ob 0 'ui-ask.sh'                                  Bash "$C/cf" "sh $P/ui-ask.sh --session onb --id onboard-cf-x --flow onboard"
ob 0 'ui-session.sh'                              Bash "$C/cf" "sh $P/ui-session.sh --session onb --step ${q}Onboarding cf${q}"
ob 0 'herdr agent prompt ceo'                     Bash "$C/cf" 'herdr agent prompt ceo "onboard cf done 7 done 3 missing 1 failing 2 proposals"'
ob 0 'herdr tab close of its own tab'             Bash "$C/cf" 'herdr tab close "$HERDR_TAB_ID"'
ob 0 'herdr tab close of its own tab by id'       Bash "$C/cf" 'herdr tab close tab-3'
# the exact shapes of skills/factory/references/onboard.md
ob 0 'onboard.md: state-commit.sh of the stub with --state "$WORK_DIR/state"' Bash "$C/cf" \
  "sh $P/state-commit.sh -m \"chore(cf): onboarding started\" --state \"\$WORK_DIR/state\" -- repos/cf/onboarding.md"
ob 0 'onboard.md: state-commit.sh of the report with --state "$WORK_DIR/state"' Bash "$C/cf" \
  "sh $P/state-commit.sh -m \"chore(cf): onboarding report\" --state \"\$WORK_DIR/state\" -- repos/cf/onboarding.md"
ob 2 'onboard.md: state-commit.sh with --state "$WORK_DIR/state" of a task file' Bash "$C/cf" \
  "sh $P/state-commit.sh -m \"chore(cf): onboarding report\" --state \"\$WORK_DIR/state\" -- repos/cf/tasks/T-900.md"
ob 0 'onboard.md: factory-doctor.sh --root "$WORK_DIR" --repo <clone>' Bash "$C/cf" \
  "sh $P/factory-doctor.sh --root \"\$WORK_DIR\" --repo $C/cf"
ob 0 'onboard.md: doc-cites.sh <clone>'           Bash "$C/cf" "sh $P/doc-cites.sh $C/cf"
ob 0 'onboard.md: herdr agent prompt ceo "onboard <key> done ..."' Bash "$C/cf" \
  'herdr agent prompt ceo "onboard cf done 7 done 3 missing 1 failing 2 proposals"'
ob 0 'onboard.md: herdr tab close "$HERDR_TAB_ID"' Bash "$C/cf" 'herdr tab close "$HERDR_TAB_ID"'
ob 0 'reads in the clone'                         Bash "$C/cf" 'ls -la && cat README.md 2>/dev/null | head -n 20'
ob 0 'git reads in the clone'                     Bash "$C/cf" "git -C $C/cf symbolic-ref refs/remotes/origin/HEAD && git log --oneline -5"
ob 0 'a read of the state clone'                  Bash "$C/cf" "cat $S/repos/cf/toolset.md"
ob 2 'Write a task file in the state clone'       Write "$C/cf" "$S/repos/cf/tasks/T-900.md"
if grep -qF "a write to $S/repos/cf/tasks/T-900.md is not for an onboarding session: it only reports, writing repos/cf/onboarding.md through state-commit.sh (references/onboard.md), and this session runs as FACTORY_ROLE=onboard." "$tmp/err"
then printf 'PASS onboard: the deny carries the C7 text\n'
else printf 'FAIL onboard: the deny carries the C7 text: %s\n' "$(head -c 300 "$tmp/err")"; fail=1; fi
ob 2 'Write the report of another repo'           Write "$C/cf" "$S/repos/userorg/onboarding.md"
ob 2 'Edit a file of the clone'                   Edit "$C/cf" "$C/cf/README.md"
ob 2 'Write under /tmp'                           Write "$C/cf" /tmp/onb.md
ob 2 'a redirect into a task file'                Bash "$C/cf" "echo status: review > $S/repos/cf/tasks/T-900.md"
ob 2 'a redirect under /tmp'                      Bash "$C/cf" 'echo x > /tmp/onb.txt'
ob 2 'a redirect to a variable'                   Bash "$C/cf" 'echo x > "$S/x"'
ob 2 'rm of its report'                           Bash "$C/cf" "rm -f $O"
ob 2 'sed -i on its report'                       Bash "$C/cf" "sed -i s/a/b/ $O"
ob 2 'state-report.sh'                            Bash "$C/cf" "sh $P/state-report.sh --task T-900 --set-status review"
ob 2 'task-new.sh'                                Bash "$C/cf" "sh $P/task-new.sh --repo cf --goal x"
ob 2 'session-monitor.sh'                         Bash "$C/cf" "sh $P/session-monitor.sh --step onboard --scope cf"
ob 2 'factory-add-repo.sh'                        Bash "$C/cf" "sh $P/factory-add-repo.sh --root $W --clone https://x.test/y.git"
ob 2 'a script of the repo'                       Bash "$C/cf" 'sh ./build.sh'
ob 2 'a denied script inside bash -c'             Bash "$C/cf" "bash -c ${q}sh $P/state-push.sh${q}"
ob 2 'state-commit.sh of a task file'             Bash "$C/cf" "sh $P/state-commit.sh -m x -- repos/cf/tasks/T-900.md"
ob 2 'state-commit.sh of its report and a task file' Bash "$C/cf" "sh $P/state-commit.sh -m x -- repos/cf/onboarding.md repos/cf/tasks/T-900.md"
ob 2 'state-commit.sh with no path'               Bash "$C/cf" "sh $P/state-commit.sh -m x"
ob 2 'state-commit.sh of another state clone'     Bash "$C/cf" "sh $P/state-commit.sh -m x --state /tmp/st -- repos/cf/onboarding.md"
ob 2 'git push from the clone'                    Bash "$C/cf" 'git push'
ob 2 'git push from the state clone'              Bash "$S" 'git push'
ob 2 'git -C <state clone> push'                  Bash "$C/cf" "git -C $S push origin main"
ob 2 'herdr agent prompt lead_x'                  Bash "$C/cf" 'herdr agent prompt lead_x "merge it"'
ob 2 'herdr agent prompt to a lead inside $( )'   Bash "$C/cf" 'echo $(herdr agent prompt lead_x hi)'
ob 2 'herdr tab create'                           Bash "$C/cf" 'herdr tab create --label x'
ob 2 'herdr tab close of another tab'             Bash "$C/cf" 'herdr tab close tab-9'
ob 2 'herdr agent start'                          Bash "$C/cf" 'herdr agent start x --kind claude'
role=triage
try 0 'another role keeps herdr agent prompt to a lead' "$C/cf" coord 'herdr agent prompt lead_x "hi"'
try 0 'another role keeps state-report.sh' "$S" coord "sh $P/state-report.sh --task T-900 --no-status"
role=''

exit $fail
