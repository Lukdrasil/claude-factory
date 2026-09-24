#!/bin/sh
# session-stats.sh in the standalone layout, T-252-02: a repeated Stop of one session writes the stats line of
# its task once, the `sid:` marker in the line being the only guard it needs. T-252-03: the tasks are the ones the
# session owns, whatever a CLAUDE.md in the cwd names.
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
for t in 'T-002 other' 'T-003 sess-3'; do
  set -- $t
  printf -- '---\nid: %s\nrepo: demo\nbranch: fix/%s\nstatus: review\narchetype: bugfix\ntier: green\ncomplexity: low\nattempt: 0\nowner: factory@host:%s\n---\n\n# Goal\nfix(demo): a task\n\n## Attempts\n' \
    "$1" "$1" "$2" > "$state/repos/demo/tasks/$1.md"
  printf '# %s\n\n## Evidence\n- `true` -> exit 0\n' "$1" > "$state/repos/demo/progress/$1.md"
done
mkdir -p "$W/demo/T-003"
printf '# Task T-002\n' > "$W/demo/T-003/CLAUDE.md"
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
stop() { # [cwd] [session id]
  (cd "${1:-$work}" && printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "${2:-sess-1}" "$tmp/transcript.jsonl" "${1:-$work}" \
    | WORK_DIR=$W sh "$bin/session-stats.sh" >/dev/null 2>&1)
}

stop
check 'the first Stop writes one stats line' 1 "$(grep -c 'sid:sess-1' "$state/repos/demo/tasks/T-001.md")"
stop
check 'a repeated Stop writes no second one' 1 "$(grep -c 'sid:sess-1' "$state/repos/demo/tasks/T-001.md")"
stop "$W/demo/T-003" sess-3
check 'the owned task gets the line beside a CLAUDE.md naming another' 1 "$(grep -c 'sid:sess-3' "$state/repos/demo/tasks/T-003.md")"
check 'the task CLAUDE.md names gets none' 0 "$(grep -c 'sid:sess-3' "$state/repos/demo/tasks/T-002.md")"

exit "$fail"
