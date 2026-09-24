#!/bin/sh
# T-252-03: a task is named by `--task` or by the owner lookup, never by a first line of CLAUDE.md in the cwd.
# state-report.sh without --task exits 2 "no --task"; self-report-check.sh judges the tasks this session owns, and
# its Stop message sends the agent's own state files through state-commit.sh, the push being state-push.sh's.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

W=$tmp/factory
state=$W/state
mkdir -p "$state/repos/demo/tasks" "$W/demo/T-010" "$W/demo/T-011" "$W/demo/T-012"
task() { # <id> <owner sid>
  printf -- '---\nid: %s\nrepo: demo\nbranch: fix/%s\nstatus: in_progress\narchetype: bugfix\nowner: factory@host:%s\n---\n\n# Goal\nx\n' \
    "$1" "$1" "$2" > "$state/repos/demo/tasks/$1.md"
}
task T-010 other
task T-011 me
task T-012 me2
printf '# Task T-010\n' > "$W/demo/T-010/CLAUDE.md"
printf '# Task T-010\n' > "$tmp/CLAUDE.md"

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
has() { # <file> <text>
  if grep -qF -- "$2" "$1"; then printf yes; else printf no; fi
}

(cd "$W/demo/T-011" && WORK_DIR=$W sh "$bin/state-report.sh" --no-status >/dev/null 2>"$tmp/err")
check 'state-report.sh with no --task exits 2' 2 "$?"
check 'and says no --task' yes "$(has "$tmp/err" 'no --task')"

(cd "$tmp" && WORK_DIR=$W sh "$bin/state-report.sh" --no-status >/dev/null 2>"$tmp/err")
check 'state-report.sh with no --task beside a CLAUDE.md naming a task exits 2' 2 "$?"
check 'and says no --task' yes "$(has "$tmp/err" 'no --task')"
check 'and never looks the named task up' no "$(has "$tmp/err" T-010)"

stop() { # <cwd> <session id>
  (cd "$1" && printf '{"session_id":"%s"}' "$2" | WORK_DIR=$W sh "$bin/self-report-check.sh" >/dev/null 2>"$tmp/err")
}

stop "$W/demo/T-011" me
check 'self-report-check.sh blocks on the in_progress task the session owns' 2 "$?"
check 'and names it' yes "$(has "$tmp/err" 'task T-011')"
check 'and sends own state files through state-commit.sh' yes "$(has "$tmp/err" 'state-commit.sh')"
check 'and says the push runs in the background' yes "$(has "$tmp/err" 'state-push.sh')"
check 'and no longer asks for a commit + push' no "$(has "$tmp/err" 'commit + push')"

stop "$W/demo/T-010" me2
check 'self-report-check.sh beside a CLAUDE.md naming another task blocks on the owned one' 2 "$?"
check 'and names the owned task' yes "$(has "$tmp/err" 'task T-012')"
check 'and not the task CLAUDE.md names' no "$(has "$tmp/err" 'task T-010')"

stop "$W/demo/T-010" nobody
check 'self-report-check.sh for a session that owns no task passes beside a CLAUDE.md naming one' 0 "$?"

exit "$fail"
