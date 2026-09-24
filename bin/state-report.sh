#!/bin/sh
# The one write path for task state (ADR-0050). The session's own state clone is the writer, and the
# report is validated right here (including the transition, which is measured from the *committed* status of the
# task file, not from the working copy the agent just wrote), committed into the state clone and, when the clone
# has an origin, pushed to the state root; the local commit stays when the push fails. A clone with no origin is
# the state root itself (factory-init.sh --root), so its report stays local.
#
#   state-report.sh --task <id> [--attempts "<line>"] [--tool-failures "<line>"] [--message "<commit message>"]
#                   [--owner <owner>] [--set-status <status>] [--set-phase <tests|implement>] [--no-status]
#                   [--branch <branch>] [--mr-url <url>]
#
# `--task` names the task and is required.
# `--no-status` leaves `status` out of the report — and with it the status and evidence checks: a caller that is
# recording *why* the status is wrong (self-report-check.sh on an exhausted budget) or is not reporting a status
# at all (pre-compact.sh, a reclaim) must not be refused for a status it is not claiming.
# `--owner <owner>` rewrites the task's `owner:` frontmatter field — the reclaim rule of the factory solve
# coordinator (skills/factory/references/solve.md), a session taking over a task a dead session still owns.
# It is a report about ownership, not about status, so it runs on a `claimed`/`ready`/`review` task too; combine
# it with `--no-status`.
# `--set-status <status>` rewrites the task's `status:` field and then reports it — the claim step of the solve
# coordinator (solve.md step 9 and per block), so the agent never edits frontmatter by hand: on 2026-09-07 the
# standalone guard denied the hand-written `in_progress` and the coordinator could not claim. The transition is
# checked before the write, against the committed status like every report, so a refused claim leaves the file
# as it was. Refused with `--no-status` (a status is set to be reported).
# `--set-phase <tests|implement>` rewrites the task's `phase:` field and then reports, the way `--set-status` does
# for the status: it is how the solve coordinator arms the implement test lock, which policy-guard.sh reads off
# `phase: implement` in the block's task file. The vocabulary is the one task-new.sh validates, `tests|implement`;
# any other value is refused (exit 1) before anything is written. Combine it with `--no-status` when the status is
# not changing and with `--set-status` when it is, in which case both fields are written and reported once.
# `--branch <branch>` rewrites the task's `branch:` field and then reports, the twin of `--owner` for the branch
# block-merge.sh merges by. worktree-add.sh writes it right after it created the worktree, so the branch a task
# is worked on is recorded by the script that made it instead of by hand. Combine it with `--no-status` when the
# status is not changing.
#
# Exit 0 = the report is in, 1 = it was refused (the reason is on stderr, fix it and run again),
# 2 = it never got there (no task, a push the root refuses,
# another session holding the state clone's lock for longer than STATE_LOCK_WAIT seconds — default 30).
set -eu

attempts=''
tool_failures=''
message=''
send_status=1
id=''
owner=''
set_status=''
set_phase=''
branch=''
set_mr_url=''
die2() { printf 'state-report: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --attempts|--tool-failures|--message|--task|--owner|--set-status|--set-phase|--branch|--mr-url)
      [ $# -ge 2 ] || die2 "$1 needs a value"
      case "$1" in
        --attempts) attempts=$2 ;;
        --tool-failures) tool_failures=$2 ;;
        --message) message=$2 ;;
        --task) id=$2 ;;
        --owner) owner=$2 ;;
        --set-status) set_status=$2 ;;
        --set-phase) set_phase=$2 ;;
        --branch) branch=$2 ;;
        --mr-url) set_mr_url=$2 ;;
      esac
      shift 2 ;;
    --no-status) send_status=0; shift ;;
    *) die2 "unknown argument '$1'" ;;
  esac
done
# invariant: the vocabulary check runs before every write path, so a refused phase leaves the state clone and the
# invariant: task file exactly as they were (task-new.sh: phase is tests|implement, or absent)
case "$set_phase" in
  ''|tests|implement) ;;
  *) printf 'state-report: the report was refused: --set-phase takes tests or implement, not %s\n' "$set_phase" >&2
     exit 1 ;;
esac
if [ -n "$set_status" ] && [ "$send_status" = 0 ]; then
  printf 'state-report: the report was refused: --set-status sets a status to report, --no-status reports none — drop one of them\n' >&2
  exit 1
fi

[ -n "$id" ] || die2 "no --task: name the task with --task <id>"

# the layout resolver is shared with the hooks that call this script (self-report-check.sh, session-stats.sh)
. "$(dirname -- "$0")/lib-tasks.sh"

# ../state next to the product clone, $WORK_DIR/state in the standalone layout, the cwd itself for a triage
# session — resolve_state_dir (lib-tasks.sh) is the one rule, shared with the two Stop hooks
state=$(resolve_state_dir "$PWD")

# the file is chosen by the `id:` line, not by an `<id>-*.md` glob: with hierarchical ids a child `T-005-01-…`
# sorts before its parent `T-005-…` (`0` < a letter) and the glob would hand back the wrong task.
task=$(grep -lx "id: $id" "$state"/repos/*/tasks/*.md 2>/dev/null | head -n1)
[ -n "${task:-}" ] && [ -f "$task" ] || die2 "no task file with 'id: $id' in $state/repos/*/tasks/"

status=''
if [ "$send_status" = 1 ]; then status=$(sed -n 's/^status:[[:space:]]*//p' "$task" | head -n1); fi
# --set-status: the status reported is the one asked for, checked below as if the file already carried it, and
# written only once the checks are through
[ -z "$set_status" ] || status=$set_status
# the MR link the agent wrote at the end of the task (ADR-0014); `null` is "no MR yet", not a value to send
mr_url=$(sed -n 's/^mr_url:[[:space:]]*//p' "$task" | head -n1)
[ "$mr_url" != null ] || mr_url=''
# T-186: the archetype decides which terminal status a task can reach. triage, ops and research never open an MR
# (task-new.sh: no branch, no base_branch for triage/ops; block-research is read-only towards the product repo),
# so they end in `closed`, and only a task with an MR ends in `done`.
archetype=$(sed -n 's/^archetype:[[:space:]]*//p' "$task" | head -n1 | sed 's/[[:space:]]*#.*//')
[ -z "$set_mr_url" ] || mr_url=$set_mr_url
set -- "$state"/repos/*/progress/"$id".md
progress_file=''
progress=''
if [ -f "$1" ]; then progress_file=$1; progress=$(cat "$1"); fi

# ---------------------------------------------------------------------------
# The session's own clone is the writer (ADR-0050).
die1() { printf 'state-report: the report of %s was refused: %s\n' "$id" "$1" >&2; exit 1; }
# E3: one report at a time per state clone, from the read of the committed status to the push — two sessions
# that both read `claimed` and both wrote `in_progress` is the race the lock closes (state_lock, lib-tasks.sh).
# The trap releases it on every exit, a refusal included.
state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die2 "another session holds the state lock of $state — waited ${STATE_LOCK_WAIT:-30} s; the report of $id was not written, run it again" ;;
  *) die2 "the state lock could not be taken in $state — is it a git clone?" ;;
esac
current=$(sed -n 's/^status:[[:space:]]*//p' "$task" | head -n1)
[ -z "$set_status" ] || current=$set_status
rel_task=${task#"$state/"}
# T-004 review: the working tree is the agent's own draft, so a check that reads the requested status out of it
# and compares it with itself checks nothing. The status the *state root* has is the committed one, and that is
# what a transition is measured from. A task file not committed yet (a block just written) has none, and then
# there is no transition to judge.
committed=$(git -C "$state" show "HEAD:$rel_task" 2>/dev/null | sed -n 's/^status:[[:space:]]*//p' | head -n1)
# T-007 review: both checks belong to the status, so both hang off `--no-status`. A report that claims no
# status — pre-compact's snapshot, self-report-check's "why the status is wrong" line, the coordinator's
# `--owner` reclaim of a claimed/ready/review task — is not refused for a claim it never made.
if [ "$send_status" = 1 ]; then
  case "$status" in
    review|blocked|failed|tests_ready|in_progress|changes_requested) ;;
    # why: a block MR merged on the forge is a fact the watcher records, so `done` is reachable for a block
    # why: and for a block only; the parent's done stays the human gate of task-done.sh
    done) is_block_id "$id" \
            || die1 "agent may not set done on $id — only a block reaches done by itself, once its MR is merged" ;;
    # why (T-186): a triage, ops or research task never opens an MR, so `done` is out of reach for it and
    # why: `closed` is its terminal status; the session that finished the work is the one that gets there.
    closed) case "$archetype" in
              triage|ops|research) ;;
              *) die1 "agent may not set closed - a session reports review|blocked|failed|tests_ready|in_progress|changes_requested, or done on a block whose MR is merged (closed is the terminal status of a triage, ops or research task; a task with an MR ends in done via task-done.sh)" ;;
            esac ;;
    *) die1 "agent may not set $status — a session reports review|blocked|failed|tests_ready|in_progress|changes_requested, or done on a block whose MR is merged" ;;
  esac
  # The agent transitions, with `ready → in_progress` for the claim a session makes for itself (ADR-0050), and
  # the T-186 case below: a triage, ops or research task reaches `closed` from
  # `review`, `in_progress` or `blocked` because no MR and no watcher will ever close it for the session.
  # Everything else, done and ready and back, is a human's.
  if [ -n "$committed" ] && [ "$committed" != "$status" ]; then
    case "$committed:$status" in
      claimed:in_progress|ready:in_progress|tests_ready:in_progress) ;;
      in_progress:review|in_progress:blocked|in_progress:failed|in_progress:tests_ready) ;;
      review:changes_requested|changes_requested:review|changes_requested:in_progress|review:done) ;;
      review:closed|in_progress:closed|blocked:closed) ;;
      *) die1 "agent may not set $status from $committed: $committed is what the state root has for $id, and $committed → $status is not an agent transition. Report a status you may reach from there, or leave it to the human who owns this one." ;;
    esac
  fi
  case "$current" in
    review|tests_ready)
      printf '%s\n' "$progress" | grep -q '^## Evidence' \
        || die1 "task $id reports '$current' but the progress file has no '## Evidence' section. A status is a claim; evidence makes it checkable — run the proving command fresh (for review the acceptance command after the rebase, for tests_ready the red tests failing for the right reason), write it with its exit code and key output line under '## Evidence' in the progress file, then report again." ;;
  esac
elif [ -n "$committed" ] && [ "$committed" != "$current" ]; then
  # the commit below carries the whole task file, so a `--no-status` call whose task file *has* moved the status
  # would push a transition nothing checked — the one hole a "no status is claimed" exemption must not open.
  die1 "--no-status reports no status, but the task file moved $id from $committed to $current. Drop --no-status and report the transition, or put the status back to $committed — the commit carries the whole task file either way."
fi
if [ -n "$mr_url" ]; then
  case "$mr_url" in http://*|https://*) ;; *) die1 "mr_url must be an http(s) URL" ;; esac
fi

# the lines go under their sections: at the end of the section, which is
# created at the end of the file when missing; one array element per line of the argument
if [ -n "$attempts$tool_failures" ]; then
  A=$attempts T=$tool_failures node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
const e=process.env,lines=v=>v.split("\n").filter(l=>l.trim()!=="");
const app=(t,sec,line)=>{const L=t.replace(/\r\n/g,"\n").replace(/\n+$/,"").split("\n");let st=L.findIndex(l=>l.trimEnd()===sec);
  if(st<0){L.push("",sec);st=L.length-1}
  let nx=L.findIndex((l,i)=>i>st&&l.startsWith("## "));L.splice(nx<0?L.length:nx,0,line);return L.join("\n")+"\n"};
for(const l of lines(e.A||""))s=app(s,"## Attempts",l);
for(const l of lines(e.T||""))s=app(s,"## Tool failures",l);
process.stdout.write(s)})' < "$task" > "$task.tmp" && mv -f "$task.tmp" "$task" || die2 "the lines could not be appended to $task"
fi

# the reclaim rule of references/solve.md: a resumed session rewrites owner: before touching any worktree.
# setf (lib-tasks.sh), not `sed -i s/^owner:.*/`, because a task whose frontmatter has no `owner:` line would
# otherwise be reported as reclaimed with nothing written (T-007 review). The write sits with the other
# writes, after the checks it is independent of, so a refusal never leaves the state clone half-rewritten.
if [ -n "$owner" ]; then
  setf "$task" owner "$owner" || die2 "owner could not be rewritten in $task"
fi
# worktree-add.sh records the branch it just created here, for the same reason: block-merge.sh merges the
# branch named in the task, and setf is what keeps that key inside the frontmatter fence exactly once
if [ -n "$branch" ]; then
  setf "$task" branch "$branch" || die2 "branch could not be rewritten in $task"
fi
# the MR link block-mr.sh just opened, written the one way frontmatter is written (T-164)
if [ -n "$set_mr_url" ]; then
  setf "$task" mr_url "$set_mr_url" || die2 "mr_url could not be rewritten in $task"
fi
# the claim step (--set-status), written here for the same reason: every check above has passed against the
# status asked for, so the file never carries a status the state root would refuse
if [ -n "$set_status" ]; then
  setf "$task" status "$set_status" || die2 "status could not be rewritten in $task"
  # T-186: a terminal task has no owner. Leaving `owner:` set is what made the Stop hook's owner-based lookup
  # pick the finished task up again and re-report it, round after round, until the budget ran out.
  case "$set_status" in
    done|closed) setf "$task" owner null || die2 "owner could not be released in $task" ;;
  esac
fi

# the implement test lock of the solve coordinator: policy-guard.sh denies a test-file edit only when the task
# file carries `phase: implement`. setf, not a `sed -i s/^phase:.*/`, because the task usually has no `phase:`
# line yet and the key has to land inside the frontmatter fence exactly once.
if [ -n "$set_phase" ]; then
  setf "$task" phase "$set_phase" || die2 "phase could not be rewritten in $task"
fi

# the commit is scoped to the two files this report is about — whatever else the session left in the state
# clone is not part of a progress report and must not ride along (state_commit, lib-tasks.sh)
[ -n "$message" ] || message="progress: $id ${status:-$current}"
set -- "$rel_task"
if [ -n "$progress_file" ]; then set -- "$@" "${progress_file#"$state/"}"; fi
state_commit "$state" "$message" "$@" || die2 "the report of $id could not be committed in $state"

# the push recipe of ADR-0012 (state_push, lib-tasks.sh), three tries; a clone with no origin is the state root
# itself and keeps the report local, a root that still refuses leaves the commit in the clone (exit 2)
state_push "$state" || die2 "the push to the state root failed 3 times, the report of $id is committed in $state but not pushed"
exit 0
