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

# a lead ends its turns with the parent it leads in_progress for hours while its blocks run
# (skills/factory/references/lead.md): FACTORY_ROLE=repo-lead, or ceo, is asked no worker self-report for a
# parent it owns. A block it owns still is, and so is a real worker on the same parent. The state is a git
# clone here so the report the hook sends for the parent is committed and the Stop can pass.
mkdir -p "$W/demo/T-013" "$W/demo/T-014" "$state/repos/demo/progress"
task T-013 lead
task T-014 lead2
task T-014-01 lead2
printf '# T-013\n' > "$state/repos/demo/progress/T-013.md"
git -C "$state" init -q -b main
git -C "$state" add -A
git -C "$state" -c user.name=t -c user.email=t@t commit -q -m init
role_stop() { # <role> <cwd> <session id>
  (cd "$2" && printf '{"session_id":"%s"}' "$3" \
    | FACTORY_ROLE=$1 WORK_DIR=$W sh "$bin/self-report-check.sh" >/dev/null 2>"$tmp/err")
}

role_stop repo-lead "$W/demo/T-013" lead
check 'a repo-lead stops with the parent it leads in_progress' 0 "$?"
check 'and is not asked for a self-report' no "$(has "$tmp/err" 'Write the self-report')"
rm -rf "$W/demo/.harness"
role_stop ceo "$W/demo/T-013" lead
check 'the CEO stops with a parent it owns in_progress' 0 "$?"
rm -rf "$W/demo/.harness"
role_stop '' "$W/demo/T-013" lead
check 'a worker on the same in_progress parent is still blocked' 2 "$?"
check 'and asked for the self-report' yes "$(has "$tmp/err" 'Write the self-report')"
rm -rf "$W/demo/.harness"
role_stop implementer "$W/demo/T-013" lead
check 'a worker with another role is still blocked' 2 "$?"
rm -rf "$W/demo/.harness"
role_stop repo-lead "$W/demo/T-014" lead2
check 'a repo-lead that owns an in_progress block is still blocked' 2 "$?"
check 'and asked for the self-report of the block' yes "$(has "$tmp/err" 'task T-014-01')"
check 'and not of the parent' no "$(has "$tmp/err" 'task T-014 ')"

exit "$fail"
