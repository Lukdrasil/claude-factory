#!/bin/sh
# session-stats.sh in the standalone layout, T-252-02: a repeated Stop of one session writes the stats line of
# its task once, the `sid:` marker in the line being the only guard it needs.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

W=$tmp/factory
state=$W/state
work=$W/demo/T-001
mkdir -p "$state/repos/demo/tasks" "$state/repos/demo/progress" "$work" "$tmp/demo"
printf '# T-001\n\n## Evidence\n- `true` -> exit 0\n' > "$state/repos/demo/progress/T-001.md"
printf 'demo: {url: %s, default_branch: main, path: %s}\n' "$tmp/origin.git" "$tmp/demo" > "$state/repos.yml"
cat > "$state/repos/demo/tasks/T-001.md" <<'TASK'
---
id: T-001
repo: demo
branch: fix/T-001
status: review
archetype: bugfix
tier: green
complexity: low
attempt: 0
owner: factory@host:sess-1
---

# Goal
fix(demo): a task

## Attempts
TASK
git init -q -b main "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
git -C "$state" add -A
git -C "$state" commit -q -m init
git init -q --bare -b main "$tmp/state-root.git"
git -C "$state" remote add origin "$tmp/state-root.git"
git -C "$state" push -q -u origin main

printf '%s\n' \
  '{"timestamp":"2026-09-24T10:00:00Z","message":{"model":"claude-test","id":"m1","usage":{"input_tokens":10,"output_tokens":5}}}' \
  '{"timestamp":"2026-09-24T10:03:00Z","message":{"model":"claude-test","id":"m2","usage":{"input_tokens":10,"output_tokens":5}}}' \
  > "$tmp/transcript.jsonl"

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
stop() {
  (cd "$work" && printf '{"session_id":"sess-1","transcript_path":"%s","cwd":"%s"}' "$tmp/transcript.jsonl" "$work" \
    | WORK_DIR=$W sh "$bin/session-stats.sh" >/dev/null 2>&1)
}

stop
check 'the first Stop writes one stats line' 1 "$(grep -c 'sid:sess-1' "$state/repos/demo/tasks/T-001.md")"
stop
check 'a repeated Stop writes no second one' 1 "$(grep -c 'sid:sess-1' "$state/repos/demo/tasks/T-001.md")"

exit "$fail"
