#!/bin/sh
# state-report.sh commits the report in the state clone and pushes nothing (the push is state-push.sh's, run in the
# background by the monitor pass and the CEO loop): a clone with no origin, one with a bare origin and one whose
# origin would refuse a push all exit 0 with the report committed locally and the origin untouched. Exit 2 is a
# report that could not be written or committed, here another session holding the state lock.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/state"
work="$tmp/work"
mkdir -p "$state/repos/demo/tasks" "$work"
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected %s, got %s\n' "$1" "$2" "$3"; fail=1; fi
}

task() { # <id>
  cat > "$state/repos/demo/tasks/$1.md" <<EOF
---
id: $1
repo: demo
status: ready
archetype: bugfix
tier: yellow
complexity: low
owner: null
mr_url: null
---

# Goal
fix(demo): $1
EOF
  git -C "$state" add -A
  git -C "$state" commit -q -m "fixture $1"
}

report() { # <id>
  (cd "$work" && sh "$bin/state-report.sh" --task "$1" --set-status in_progress 2>&1)
}

# --- no origin: the report is committed, exit 0 ------------------------------
task T-001
out=$(report T-001); rc=$?
check 'no origin exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'no origin commits the report' 'progress: T-001 in_progress' "$(git -C "$state" log -1 --format=%s)"

# --- a bare origin: the report is committed and not pushed, exit 0 ------------
git init -q --bare -b main "$tmp/origin.git"
git -C "$state" remote add origin "$tmp/origin.git"
git -C "$state" push -q -u origin main >/dev/null 2>&1
task T-002
git -C "$state" push -q >/dev/null 2>&1
root_before=$(git -C "$tmp/origin.git" rev-parse main)
out=$(report T-002); rc=$?
check 'with an origin exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the report is committed' 'progress: T-002 in_progress' "$(git -C "$state" log -1 --format=%s)"
check 'the report is not pushed, the origin is untouched' "$root_before" "$(git -C "$tmp/origin.git" rev-parse main)"

# --- an origin that would refuse a push changes nothing: exit 0 ---------------
task T-003
printf '#!/bin/sh\nexit 1\n' > "$tmp/origin.git/hooks/pre-receive"
chmod +x "$tmp/origin.git/hooks/pre-receive"
out=$(report T-003); rc=$?
check 'a refusing origin still exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the report is committed beside a refusing origin' 'progress: T-003 in_progress' "$(git -C "$state" log -1 --format=%s)"

# --- another session holds the state lock: exit 2, nothing written -----------
task T-004
rm -f "$tmp/held" "$tmp/release"
(. "$bin/lib-tasks.sh"; state_lock "$state" || exit 1; : > "$tmp/held"
 while [ ! -e "$tmp/release" ]; do sleep 0.2; done) &
holder=$!
n=0; while [ ! -e "$tmp/held" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
before=$(git -C "$state" rev-parse HEAD)
out=$(cd "$work" && STATE_LOCK_WAIT=1 sh "$bin/state-report.sh" --task T-004 --set-status in_progress 2>&1); rc=$?
check 'a held lock exits 2' 2 "$rc"
check 'a held lock commits nothing' "$before" "$(git -C "$state" rev-parse HEAD)"
check 'a held lock leaves the status' ready "$(sed -n 's/^status:[[:space:]]*//p' "$state/repos/demo/tasks/T-004.md")"
if printf '%s\n' "$out" | grep -q 'state-report: another session holds the state lock'; then
  printf 'PASS the lock is reported on stderr\n'
else printf 'FAIL the lock is reported on stderr: %s\n' "$out"; fail=1; fi
: > "$tmp/release"; wait "$holder"

exit $fail
