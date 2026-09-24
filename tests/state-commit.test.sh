#!/bin/sh
# state-commit.sh and state-push.sh over throwaway state clones: an agent commits its own state files under the
# state lock and only the paths it names, and the push to the state root is a separate step with its own lock
# that never autostashes, never resets, and keeps the commits when the root refuses them.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
export WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
has() { # <file> <text>
  if grep -qF -- "$2" "$1"; then printf yes; else printf no; fi
}

new_state() { # <dir>
  mkdir -p "$1/repos/demo/research"
  git init -q -b main "$1"
  git -C "$1" config user.email harness@localhost
  git -C "$1" config user.name harness
  printf 'mine\n' > "$1/mine.md"
  printf 'shared notes\n' > "$1/notes.md"
  git -C "$1" add -A
  git -C "$1" commit -q -m init
}

with_origin() { # <state> <other clone>
  git init -q --bare -b main "$1.git"
  git -C "$1" remote add origin "$1.git"
  git -C "$1" push -q -u origin main >/dev/null 2>&1
  git clone -q -b main "$1.git" "$2" >/dev/null 2>&1
  git -C "$2" config user.email other@localhost
  git -C "$2" config user.name other
}

# a background holder of a lock: <kind> is state (state_lock) or push (flock on factory-push.lock)
hold() { # <kind> <state>
  rm -f "$tmp/held" "$tmp/release"
  if [ "$1" = state ]; then
    (. "$bin/lib-tasks.sh"; state_lock "$2" || exit 1; : > "$tmp/held"
     while [ ! -e "$tmp/release" ]; do sleep 0.2; done) &
  else
    (exec 8>"$2/.git/factory-push.lock"; flock -n 8 || exit 1; : > "$tmp/held"
     while [ ! -e "$tmp/release" ]; do sleep 0.2; done) &
  fi
  holder=$!
  n=0
  while [ ! -e "$tmp/held" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
}
release() { : > "$tmp/release"; wait "$holder"; }

# =============================== state-commit.sh ===============================
st="$tmp/c/state"
new_state "$st"

# --- only the named paths are committed, a foreign edit stays uncommitted ---------------
printf 'mine, edited\n' > "$st/mine.md"
printf 'another session, not committed\n' >> "$st/notes.md"
printf 'a report\n' > "$st/repos/demo/research/T-001-report.md"
rc=0
sh "$bin/state-commit.sh" -m 'research: T-001' --state "$st" -- mine.md repos/demo/research/T-001-report.md \
  >"$tmp/out" 2>&1 || rc=$?
check 'state-commit exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/out"
check 'the commit carries the message' 'research: T-001' "$(git -C "$st" log -1 --format=%s)"
check 'the commit holds only the named paths' 'mine.md
repos/demo/research/T-001-report.md' "$(git -C "$st" show --name-only --format= HEAD)"
check 'the foreign edit survives' 'shared notes
another session, not committed' "$(cat "$st/notes.md")"
check 'the foreign edit is still uncommitted' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"

# --- an absolute path inside the clone, and the clone found from the cwd ----------------
printf 'mine, again\n' > "$st/mine.md"
rc=0
(cd "$st" && sh "$bin/state-commit.sh" -m 'memory: a lesson' -- "$st/mine.md") >"$tmp/out" 2>&1 || rc=$?
check 'an absolute path in the clone from a cwd in it exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/out"
check 'and commits it' 'memory: a lesson' "$(git -C "$st" log -1 --format=%s)"

# --- nothing to commit is success, and no commit ------------------------------------------
before=$(git -C "$st" rev-parse HEAD)
rc=0
sh "$bin/state-commit.sh" -m 'nothing' --state "$st" -- mine.md >/dev/null 2>&1 || rc=$?
check 'nothing to commit exits 0' 0 "$rc"
check 'nothing to commit makes no commit' "$before" "$(git -C "$st" rev-parse HEAD)"

# --- usage errors are refusals (exit 1) and write nothing ---------------------------------
rc=0; sh "$bin/state-commit.sh" --state "$st" -- mine.md >/dev/null 2>&1 || rc=$?
check 'no -m exits 1' 1 "$rc"
rc=0; sh "$bin/state-commit.sh" -m x --state "$st" -- >/dev/null 2>&1 || rc=$?
check 'no path exits 1' 1 "$rc"
rc=0; sh "$bin/state-commit.sh" -m x --state "$st" -- "$tmp/elsewhere.md" >/dev/null 2>"$tmp/err" || rc=$?
check 'an absolute path outside the clone exits 1' 1 "$rc"
check 'and says it is outside' yes "$(has "$tmp/err" 'outside')"

# --- the state lock is taken: a held lock is exit 2 and no commit -------------------------
printf 'mine, under a held lock\n' > "$st/mine.md"
hold state "$st"
before=$(git -C "$st" rev-parse HEAD)
rc=0
STATE_LOCK_WAIT=1 sh "$bin/state-commit.sh" -m 'locked out' --state "$st" -- mine.md >/dev/null 2>"$tmp/err" || rc=$?
check 'a held state lock exits 2' 2 "$rc"
check 'a held state lock makes no commit' "$before" "$(git -C "$st" rev-parse HEAD)"
check 'the refusal names the lock' yes "$(has "$tmp/err" 'lock')"
release
rc=0
sh "$bin/state-commit.sh" -m 'after the lock' --state "$st" -- mine.md >/dev/null 2>&1 || rc=$?
check 'the freed lock lets the commit through' '0 after the lock' "$rc $(git -C "$st" log -1 --format=%s)"

# =============================== state-push.sh ===============================
# --- no origin: the clone is the state root, nothing to push ------------------------------
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'no origin exits 0' 0 "$rc"

# --- nothing to push ----------------------------------------------------------------------
st="$tmp/p/state"
new_state "$st"
with_origin "$st" "$tmp/p/other"
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'nothing to push exits 0' 0 "$rc"

# --- a local commit is pushed -------------------------------------------------------------
printf 'mine, pushed\n' > "$st/mine.md"
git -C "$st" commit -q -m 'a local commit' -- mine.md
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'a local commit exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/out"
check 'the root has the local commit' "$(git -C "$st" rev-parse HEAD)" "$(git -C "$st.git" rev-parse main)"

# --- a moved remote is rebased onto, no autostash needed for a clean tree ------------------
git -C "$tmp/p/other" pull -q >/dev/null 2>&1
printf 'foreign\n' > "$tmp/p/other/foreign.md"
git -C "$tmp/p/other" add foreign.md
git -C "$tmp/p/other" commit -q -m 'a foreign commit'
git -C "$tmp/p/other" push -q >/dev/null 2>&1
printf 'mine, after the move\n' > "$st/mine.md"
git -C "$st" commit -q -m 'a local commit after the move' -- mine.md
printf 'untracked scratch\n' > "$st/scratch.md"
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'a moved remote exits 0' 0 "$rc"
[ "$rc" = 0 ] || sed 's/^/  /' "$tmp/out"
check 'the root has the rebased local commit' "$(git -C "$st" rev-parse HEAD)" "$(git -C "$st.git" rev-parse main)"
check 'the local commit sits on the foreign one' 'a local commit after the move
a foreign commit' "$(git -C "$st" log -2 --format=%s)"
check 'the history stays linear, no merge commit' 0 "$(git -C "$st" log --merges --format=%h | wc -l | tr -d ' ')"
check 'the untracked file survives' yes "$([ -f "$st/scratch.md" ] && echo yes || echo no)"
rm -f "$st/scratch.md"

# --- a moved remote with a foreign uncommitted edit: no autostash, exit 1, all kept ---------
git -C "$tmp/p/other" pull -q >/dev/null 2>&1
printf 'foreign 2\n' > "$tmp/p/other/foreign.md"
git -C "$tmp/p/other" commit -q -m 'a second foreign commit' -- foreign.md
git -C "$tmp/p/other" push -q >/dev/null 2>&1
printf 'mine, dirty case\n' > "$st/mine.md"
git -C "$st" commit -q -m 'a local commit beside a dirty tree' -- mine.md
printf 'another session, not committed\n' >> "$st/notes.md"
before=$(git -C "$st" rev-parse HEAD)
root_before=$(git -C "$st.git" rev-parse main)
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'a moved remote beside a dirty tree exits 1' 1 "$rc"
check 'the local commit stays' "$before" "$(git -C "$st" rev-parse HEAD)"
check 'the root is not touched' "$root_before" "$(git -C "$st.git" rev-parse main)"
check 'the uncommitted edit survives in place' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"
check 'nothing was stashed' '' "$(git -C "$st" stash list)"
check 'no rebase is left in progress' no "$([ -d "$st/.git/rebase-merge" ] || [ -d "$st/.git/rebase-apply" ] && echo yes || echo no)"
git -C "$st" checkout -q -- notes.md
rc=0
sh "$bin/state-push.sh" --state "$st" >/dev/null 2>&1 || rc=$?
check 'the next pass over a clean tree pushes it' "0 $(git -C "$st" rev-parse HEAD)" "$rc $(git -C "$st.git" rev-parse main)"

# --- a rebase that conflicts is aborted, exit 1, the commit stays ---------------------------
git -C "$tmp/p/other" pull -q >/dev/null 2>&1
printf 'theirs\n' > "$tmp/p/other/mine.md"
git -C "$tmp/p/other" commit -q -m 'a conflicting foreign commit' -- mine.md
git -C "$tmp/p/other" push -q >/dev/null 2>&1
printf 'ours\n' > "$st/mine.md"
git -C "$st" commit -q -m 'a conflicting local commit' -- mine.md
before=$(git -C "$st" rev-parse HEAD)
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'a conflicting rebase exits 1' 1 "$rc"
check 'the conflicting commit stays' "$before" "$(git -C "$st" rev-parse HEAD)"
check 'the conflicting rebase is aborted' no "$([ -d "$st/.git/rebase-merge" ] || [ -d "$st/.git/rebase-apply" ] && echo yes || echo no)"
check 'the tree is clean after the abort' '' "$(git -C "$st" status --porcelain --untracked-files=no)"
git -C "$st" reset -q --keep HEAD~1

# --- a refused push exits 1 and keeps the commits -----------------------------------------
st="$tmp/r/state"
new_state "$st"
with_origin "$st" "$tmp/r/other"
printf '#!/bin/sh\nexit 1\n' > "$st.git/hooks/pre-receive"
chmod +x "$st.git/hooks/pre-receive"
printf 'mine, refused\n' > "$st/mine.md"
git -C "$st" commit -q -m 'a refused commit' -- mine.md
before=$(git -C "$st" rev-parse HEAD)
root_before=$(git -C "$st.git" rev-parse main)
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'a refused push exits 1' 1 "$rc"
check 'a refused push keeps the commit' "$before" "$(git -C "$st" rev-parse HEAD)"
check 'a refused push leaves the root' "$root_before" "$(git -C "$st.git" rev-parse main)"
check 'the refusal is on stderr' yes "$(has "$tmp/out" 'state-push:')"
rm -f "$st.git/hooks/pre-receive"

# --- a held push lock: another push is running, exit 0 quietly, nothing pushed -------------
hold push "$st"
rc=0
sh "$bin/state-push.sh" --state "$st" >"$tmp/out" 2>&1 || rc=$?
check 'a held push lock exits 0' 0 "$rc"
check 'a held push lock is quiet' '' "$(cat "$tmp/out")"
check 'a held push lock pushes nothing' "$root_before" "$(git -C "$st.git" rev-parse main)"
release
rc=0
sh "$bin/state-push.sh" --state "$st" >/dev/null 2>&1 || rc=$?
check 'the freed push lock pushes' "0 $before" "$rc $(git -C "$st.git" rev-parse main)"

# --- the push never takes the state lock: a held state lock does not stop it --------------
printf 'mine, beside a held state lock\n' > "$st/mine.md"
git -C "$st" commit -q -m 'a commit beside a held state lock' -- mine.md
hold state "$st"
rc=0
STATE_LOCK_WAIT=1 sh "$bin/state-push.sh" --state "$st" >/dev/null 2>&1 || rc=$?
check 'a held state lock does not stop a push that needs no rebase' "0 $(git -C "$st" rev-parse HEAD)" \
  "$rc $(git -C "$st.git" rev-parse main)"
release

exit "$fail"
