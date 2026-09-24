#!/bin/sh
# policy-guard.sh, T-228-08: outside the plain cd && chain every cd target joins the bases, whether it is reached
# through pushd, a prefix word or an assignment, and after a lost cd a push is judged as the state clone's only while
# that clone holds a commit to push.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
H=$tmp/home
W=$H/factory
C=$H/clones
BLK=$W/cf/T-900-01

mkdir -p "$W/state/repos/cf/tasks" "$BLK" "$C/cf"
printf 'cf: {url: "https://forge.test/cf.git", default_branch: main, path: "%s"}\n' "$C/cf" > "$W/state/repos.yml"
printf -- '---\nid: T-900-01\nrepo: cf\nbranch: block/T-900-01\nstatus: in_progress\narchetype: bugfix\nphase: tests\nowner: factory@host:blk\n---\n\n# Goal\nx\n' \
  > "$W/state/repos/cf/tasks/T-900-01.md"
printf 'x\n' > "$C/cf/README.md"
dash=''

try() { # <want exit> <label> <command>
  node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",cwd:process.argv[1],session_id:"blk",tool_input:{command:process.argv[2]}}))' \
    "$BLK" "$3" | env -u DASHBOARD_URL -u HARNESS_WORKER ${dash:+DASHBOARD_URL=$dash} HOME="$H" WORK_DIR="$W" sh "$root/bin/policy-guard.sh" >/dev/null 2>"$tmp/err"
  got=$?
  if [ "$got" -eq "$1" ]; then printf 'PASS %s\n' "$2"; return; fi
  printf 'FAIL want=%s got=%s %s: %s\n' "$1" "$got" "$2" "$(head -c 200 "$tmp/err")"
  fail=1
}
g() { git -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }

try 2 'pushd <clone>, then a relative redirect' "pushd $C/cf && echo x > README.md"
try 2 'an assignment before cd <clone>, then a relative redirect' "A=1 cd $C/cf && echo x > README.md"
try 2 'builtin cd <clone>, then a relative redirect' "builtin cd $C/cf && echo x > README.md"
try 2 'cd <clone>;, then a relative redirect' "cd $C/cf; echo x > README.md"
try 0 'cd /tmp/scratch && make 2>&1 | tee on an absolute file' 'cd /tmp/scratch && make 2>&1 | tee /tmp/b.log'

g init -q -b main "$W/state"
g -C "$W/state" add -A
g -C "$W/state" commit -qm init
g init -q --bare "$tmp/remote.git"
g -C "$W/state" remote add origin "$tmp/remote.git"
g -C "$W/state" push -u origin main
dash=http://dash.test
try 0 'a lost cd, then git push, the state clone with nothing to push' 'cd sub && git push'
printf 'y\n' >> "$W/state/repos/cf/tasks/T-900-01.md"
g -C "$W/state" commit -qam edit
try 2 'a lost cd, then git push, the state clone holding a task edit' 'cd sub && git push'
try 0 'cd /tmp/scratch && git push, the state clone holding a task edit' 'cd /tmp/scratch && git push'

exit $fail
