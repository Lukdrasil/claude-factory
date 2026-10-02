#!/bin/sh
# mr-watch.sh over a glab stub: F31, the parent's own task MR is watched beside its block MRs, so the lead learns
# the human merged it without being told; a merged parent prints `<T-id> merged` and is not set done here
# (task-done.sh does that behind the done gate). With --finish the watcher runs task-done.sh itself on the merge,
# retries a finish that failed, and its loop ends with the task.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { # <label> <0 want match | 1 want none> <pattern> <text>
  if printf '%s\n' "$4" | grep -qE "$3"; then got=0; else got=1; fi
  if [ "$got" -eq "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

state="$tmp/factory/state"
mkdir -p "$state/repos/demo/tasks" "$tmp/bin" "$tmp/mrs"
printf 'demo: {url: "https://forge.test/g/demo.git", default_branch: main, path: "%s"}\n' "$tmp/clone" > "$state/repos.yml"
printf -- '---\nid: T-501\nrepo: demo\nstatus: review\nbranch: feat/T-501-x\nmr_url: https://forge.test/g/demo/-/merge_requests/9\n---\n\n# Goal\nfeat(demo): x\n' \
  > "$state/repos/demo/tasks/T-501.md"
printf -- '---\nid: T-501-01\nrepo: demo\nstatus: done\nbranch: block/T-501-01\nmr_url: https://forge.test/g/demo/-/merge_requests/8\n---\n\n# Goal\nfeat(demo): y\n' \
  > "$state/repos/demo/tasks/T-501-01.md"
cat > "$tmp/bin/glab" <<STUB
#!/bin/sh
[ "\$1 \$2" = "mr view" ] || exit 1
printf '%s\\n' "\${3##*/}" >> "$tmp/calls"
cat "$tmp/mrs/\${3##*/}.json"
STUB
chmod +x "$tmp/bin/glab"
mr() { printf '{"iid":%s,"state":"%s","user_notes_count":0}\n' "$1" "$2" > "$tmp/mrs/$1.json"; }
watch() { PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-501 --once --state "$state" 2>&1; }
seen="$tmp/factory/demo/.harness/T-501/mr-watch.state"

mr 8 merged
mr 9 opened
printf 'T-501-01 merged 0\n' > "$tmp/seen0" && mkdir -p "${seen%/*}" && cp "$tmp/seen0" "$seen"
out=$(watch)
check 'an open task MR prints nothing'            1 'T-501 ' "$out"
check 'the task MR is in the state file'          0 '^T-501 open 0$' "$(cat "$seen")"
mr 9 merged
out=$(watch)
check 'a merged task MR prints <T-id> merged'     0 '^T-501 merged$' "$out"
check 'the state file keeps it merged'            0 '^T-501 merged 0$' "$(cat "$seen")"
check 'the parent is not set done by the watcher' 0 '^status: review$' "$(cat "$state/repos/demo/tasks/T-501.md")"
out=$(watch)
check 'the merge is reported once'                1 'T-501 merged' "$out"

# --- --finish: the merge ends the task ---------------------------------------------------------
git init -q "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
printf -- '---\nid: T-502\nrepo: demo\narchetype: feature\nstatus: review\nowner: factory@h:s1\nbranch: feat/T-502-x\nmr_url: https://forge.test/g/demo/-/merge_requests/12\n---\n\n# Goal\nfeat(demo): z\n' \
  > "$state/repos/demo/tasks/T-502.md"
git -C "$state" add -A
git -C "$state" commit -q -m init
fin() { PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-502 --finish "$@" --state "$state" 2>&1; }
file502() { ls "$state"/repos/demo/tasks/T-502.md "$state"/repos/demo/archive/*/tasks/T-502.md 2>/dev/null | head -n1; }

mr 12 opened
out=$(fin --once)
check 'an open task MR with --finish prints nothing'   1 'T-502 ' "$out"
check 'and leaves the parent in review'                0 '^status: review$' "$(cat "$(file502)")"

# a loop over a task MR still open goes on: it is stopped from outside after its first sleep
out=$( (PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-502 --finish --interval 5 --state "$state" >/dev/null 2>&1 & p=$!
  sleep 2; kill -0 $p 2>/dev/null && echo running; kill $p 2>/dev/null) )
check 'a --finish loop keeps watching an open task MR' 0 '^running$' "$out"

mr 12 merged
# another writer holds the state lock until it is killed, so task-done.sh exits 2 and nothing is written
if command -v flock >/dev/null 2>&1; then
  ( exec 9>"$state/.git/factory-state.lock"; flock 9; : > "$tmp/held"; exec sleep 600 ) & holder=$!
  until [ -f "$tmp/held" ]; do sleep 1; done
else
  mkdir "$state/.git/factory-state.lockdir" && date +%s > "$state/.git/factory-state.lockdir/since"; holder=''
fi
out=$(STATE_LOCK_WAIT=1 fin --once)
if [ -n "$holder" ]; then kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; else rm -rf "$state/.git/factory-state.lockdir"; fi
check 'a finish task-done.sh refuses is finish-failed' 0 '^T-502 finish-failed ' "$out"
check 'and the parent stays in review'                 0 '^status: review$' "$(cat "$(file502)")"

out=$(fin --once)
check 'the next pass finishes it: <T-id> done'         0 '^T-502 done$' "$out"
check 'the merge itself is not reported twice'         1 '^T-502 merged$' "$out"
check 'the parent is done'                             0 '^status: done$' "$(cat "$(file502)")"
check 'its owner is released'                          0 '^owner: null$' "$(cat "$(file502)")"
check 'the done is committed in the state clone'       0 'chore\(T-502\): review' "$(git -C "$state" log --format=%s)"

out=$(fin --once)
check 'a finished task is not finished again'          1 'T-502 (done|finish-failed)' "$out"
ended() { # <pid of a job of the calling shell>: ended within a minute, or killed and running
  e_n=0
  while kill -0 "$1" 2>/dev/null; do
    e_n=$((e_n + 1)); [ "$e_n" -lt 60 ] || { kill "$1"; echo running; return; }
    sleep 1
  done
  echo ended
}
out=$(fin --interval 600 >/dev/null & ended $!)
check 'a --finish loop over a done task ends'          0 '^ended$' "$out"

# --- several finishers at once: one done, no pass that dies ---------------------------------------
newtask() { # <id> <iid> <status>
  printf -- '---\nid: %s\nrepo: demo\narchetype: feature\nstatus: %s\nowner: factory@h:s1\nbranch: feat/%s-x\nmr_url: https://forge.test/g/demo/-/merge_requests/%s\n---\n\n# Goal\nfeat(demo): %s\n' \
    "$1" "${3:-review}" "$1" "$2" "$1" > "$state/repos/demo/tasks/$1.md"
  git -C "$state" add -A && git -C "$state" commit -q -m "$1"
}
newtask T-503 13
mr 13 merged
for n in 1 2 3 4; do
  ( PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-503 --once --finish --state "$state" > "$tmp/race.$n" 2>&1
    echo "rc=$?" >> "$tmp/race.$n" ) &
done
wait
races=$(cat "$tmp"/race.*)
check 'four finishers print one done'                  0 '^1$' "$(printf '%s\n' "$races" | grep -c '^T-503 done$')"
check 'none of them fails'                             1 'finish-failed|rc=[1-9]|cannot stat' "$races"
check 'the task is done'                               0 '^status: done$' "$(cat "$state"/repos/demo/archive/*/tasks/T-503.md 2>/dev/null)"

# --- a task MR closed without a merge: said once, and the --finish loop ends -----------------------
newtask T-504 14
mr 14 closed
out=$(PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-504 --finish --interval 600 --state "$state" > "$tmp/t504" 2>&1 & ended $!)
check 'a closed task MR ends the --finish loop'        0 '^ended$' "$out"
check 'it prints <T-id> closed-unmerged'               0 '^T-504 closed-unmerged$' "$(cat "$tmp/t504")"
check 'and the parent stays in review'                 0 '^status: review$' "$(cat "$state/repos/demo/tasks/T-504.md")"

# --- --task-mr-only reads the task MR alone ------------------------------------------------------
newtask T-505 15
mr 15 opened
printf -- '---\nid: T-505-01\nrepo: demo\nstatus: review\nbranch: block/T-505-01\nmr_url: https://forge.test/g/demo/-/merge_requests/16\n---\n\n# Goal\nfeat(demo): w\n' \
  > "$state/repos/demo/tasks/T-505-01.md"
mr 16 opened
: > "$tmp/calls"
PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-505 --once --finish --task-mr-only --state "$state" >/dev/null 2>&1
check '--task-mr-only asks the forge for the task MR'  0 '^15$' "$(cat "$tmp/calls")"
check 'and not for the block MRs'                      1 '^16$' "$(cat "$tmp/calls")"

# --- a done commit that does not reach the state root is push-failed ----------------------------
git -C "$state" remote add origin "$tmp/no-such-root"
newtask T-506 17
mr 17 merged
out=$(PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-506 --once --finish --state "$state" 2>&1)
check 'the task is still done'                         0 '^T-506 done$' "$out"
check 'and the failed push is a stdout line'           0 '^T-506 push-failed$' "$out"

exit $fail
