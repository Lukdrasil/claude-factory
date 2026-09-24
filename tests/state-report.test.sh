#!/bin/sh
# state-report.sh's push step over a throwaway state clone (T-264-03): a clone with no origin keeps the report
# local and exits 0, a bare origin receives the report, and an origin that refuses the push is exit 2 with the
# report commit kept in the clone.
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

# --- no origin: the report is committed and stays local, exit 0 --------------
task T-001
out=$(report T-001); rc=$?
check 'no origin exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'no origin commits the report' 'progress: T-001 in_progress' "$(git -C "$state" log -1 --format=%s)"

# --- a bare origin: the report lands on it, exit 0 ----------------------------
git init -q --bare -b main "$tmp/origin.git"
git -C "$state" remote add origin "$tmp/origin.git"
git -C "$state" push -q -u origin main >/dev/null 2>&1
task T-002
git -C "$state" push -q >/dev/null 2>&1
out=$(report T-002); rc=$?
check 'with an origin exits 0' 0 "$rc"
[ "$rc" = 0 ] || printf '  output: %s\n' "$out"
check 'the report is pushed' "$(git -C "$state" rev-parse HEAD)" \
  "$(git -C "$tmp/origin.git" rev-parse main 2>/dev/null)"
check 'the pushed tip is the report' 'progress: T-002 in_progress' \
  "$(git -C "$tmp/origin.git" log -1 --format=%s main 2>/dev/null)"

# --- an origin whose pre-receive hook refuses: exit 2, the commit stays -------
task T-003
git -C "$state" push -q >/dev/null 2>&1
printf '#!/bin/sh\nexit 1\n' > "$tmp/origin.git/hooks/pre-receive"
chmod +x "$tmp/origin.git/hooks/pre-receive"
before=$(git -C "$state" rev-parse HEAD)
out=$(report T-003); rc=$?
check 'a refused push exits 2' 2 "$rc"
check 'a refused push keeps the report commit' "$before" "$(git -C "$state" rev-parse HEAD~1)"
check 'a refused push keeps the report message' 'progress: T-003 in_progress' "$(git -C "$state" log -1 --format=%s)"
if printf '%s\n' "$out" | grep -q 'state-report: the push to the state root failed'; then
  printf 'PASS the refusal is reported on stderr\n'
else printf 'FAIL the refusal is reported on stderr: %s\n' "$out"; fail=1; fi

exit $fail
