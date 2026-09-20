#!/bin/sh
# The one write path for task state, in two postures (ADR-0047, ADR-0050). With DASHBOARD_URL set:
# `PATCH $DASHBOARD_URL/api/tasks/<id>` with the `status` of the local task file, its `mr_url` once the task has
# one, the whole local progress file and any line for `## Attempts` / `## Tool failures`; the session's state
# clone is read-only towards the state repo, the dashboard is the only pusher, and there is no git fallback —
# a report that does not arrive is reported as such (exit 2) and the caller decides. With DASHBOARD_URL empty or
# unset (a standalone session, no dashboard) the same report is validated here — including the transition, which
# is measured from the *committed* status of the task file, not from the working copy the agent just wrote —
# committed into the state clone and pushed to the state root; the local commit stays when the push fails.
#
#   state-report.sh [--task <id>] [--attempts "<line>"] [--tool-failures "<line>"] [--message "<commit message>"]
#                   [--owner <owner>] [--set-status <status>] [--set-phase <tests|implement>] [--no-status]
#                   [--branch <branch>] [--mr-url <url>]
#
# `--task` names the task instead of the `# Task <id>` line of CLAUDE.md (a session that owns several tasks).
# `--no-status` leaves `status` out of the report — and with it the status and evidence checks: a caller that is
# recording *why* the status is wrong (self-report-check.sh on an exhausted budget) or is not reporting a status
# at all (pre-compact.sh, a reclaim) must not be refused for a status it is not claiming.
# `--owner <owner>` rewrites the task's `owner:` frontmatter field — the reclaim rule of the factory solve
# coordinator (skills/factory/references/solve.md), a session taking over a task a dead session still owns.
# It is a report about ownership, not about status, so it runs on a `claimed`/`ready`/`review` task too; combine
# it with `--no-status`. Local posture only — the Task API has no owner field, so a `--owner` under
# DASHBOARD_URL is refused (exit 1).
# `--set-status <status>` rewrites the task's `status:` field and then reports it — the claim step of the solve
# coordinator (solve.md step 9 and per block), so the agent never edits frontmatter by hand: on 2026-09-07 the
# standalone guard denied the hand-written `in_progress` and the coordinator could not claim. The transition is
# checked before the write, against the committed status like every report, so a refused claim leaves the file
# as it was. Refused with `--no-status` (a status is set to be reported), and under DASHBOARD_URL like `--owner`.
# `--set-phase <tests|implement>` rewrites the task's `phase:` field and then reports, the way `--set-status` does
# for the status: it is how the solve coordinator arms the implement test lock, which policy-guard.sh reads off
# `phase: implement` in the block's task file. The vocabulary is the one task-new.sh validates, `tests|implement`;
# any other value is refused (exit 1) before anything is written. Combine it with `--no-status` when the status is
# not changing and with `--set-status` when it is, in which case both fields are written and reported once. Local
# posture only, like `--owner`: the Task API has no phase field, so `--set-phase` under DASHBOARD_URL is refused.
# `--branch <branch>` rewrites the task's `branch:` field and then reports, the twin of `--owner` for the branch
# block-merge.sh merges by. worktree-add.sh writes it right after it created the worktree, so the branch a task
# is worked on is recorded by the script that made it instead of by hand. Combine it with `--no-status` when the
# status is not changing. Local posture only, like `--owner`: the Task API has no branch field.
#
# Exit 0 = the report is in, 1 = it was refused (the reason is on stderr, fix it and run again),
# 2 = it never got there (unreachable, no token, no task, an answer other than 2xx/400, a push the root refuses,
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

# the task is identified by the CLAUDE.md prepare_task generated into cwd ("# Task <id>"), same as the Stop hooks
[ -n "$id" ] || id=$(sed -n '1s/^# Task //p' CLAUDE.md 2>/dev/null) || :
[ -n "${id:-}" ] || die2 "no '# Task <id>' in a CLAUDE.md in $(pwd) and no --task — this is not a task session"

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
[ -z "$set_mr_url" ] || mr_url=$set_mr_url
set -- "$state"/repos/*/progress/"$id".md
progress_file=''
progress=''
if [ -f "$1" ]; then progress_file=$1; progress=$(cat "$1"); fi

# ---------------------------------------------------------------------------
# The local posture (ADR-0050): no DASHBOARD_URL — empty or unset, the one switch policy-guard.sh reads too —
# means no dashboard, and the session's own clone is the writer. The checks are TaskReport.Check / CheckMrUrl and
# TaskTransitions.Agent, the edits Frontmatter.SetField / AppendSection.
if [ -z "${DASHBOARD_URL:-}" ]; then
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
      done) case "$id" in
              T-[0-9][0-9][0-9]-[0-9][0-9]) ;;
              *) die1 "agent may not set done on $id — only a block reaches done by itself, once its MR is merged" ;;
            esac ;;
      *) die1 "agent may not set $status — a session reports review|blocked|failed|tests_ready|in_progress|changes_requested, or done on a block whose MR is merged" ;;
    esac
    # TaskTransitions.Agent (ClaudeOs.Dashboard/State/TaskTransitions.cs), plus the one standalone divergence of
    # ADR-0050: `ready → in_progress`, the claim a session makes for itself where there is no orchestrator to
    # claim for it. Everything else — done, review, closed and back — is a human's or the watchdog's.
    if [ -n "$committed" ] && [ "$committed" != "$status" ]; then
      case "$committed:$status" in
        claimed:in_progress|ready:in_progress|tests_ready:in_progress) ;;
        in_progress:review|in_progress:blocked|in_progress:failed|in_progress:tests_ready) ;;
        review:changes_requested|changes_requested:review|changes_requested:in_progress|review:done) ;;
        *) die1 "agent may not set $status from $committed — $committed is what the state root has for $id, and $committed → $status is not an agent transition (TaskTransitions.Agent). Report a status you may reach from there, or leave it to the human who owns this one." ;;
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

  # the lines go under their sections the way the dashboard writes them: at the end of the section, which is
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

  # the push recipe of ADR-0012, three tries; a root that still refuses leaves the commit in the clone (exit 2)
  n=0
  until git -C "$state" pull -q --rebase --autostash -X theirs >/dev/null 2>&1 && git -C "$state" push -q >/dev/null 2>&1; do
    n=$((n + 1))
    [ "$n" -lt 3 ] || die2 "the push to the state root failed 3 times — the report of $id is committed in $state but not pushed"
    sleep 1
  done
  exit 0
fi

# ---------------------------------------------------------------------------
# The dashboard posture (ADR-0047) — reached only with a non-empty DASHBOARD_URL, the switch above
[ -n "${DASHBOARD_API_TOKEN:-}" ] || die2 "DASHBOARD_API_TOKEN is not set — the session cannot authenticate to the Task API"
if [ -n "$owner" ]; then
  printf 'state-report: the report of %s was refused: --owner has no meaning under the dashboard posture — the Task API has no owner field\n' "$id" >&2
  exit 1
fi
if [ -n "$set_phase" ]; then
  printf 'state-report: the report of %s was refused: --set-phase is a local-posture flag, the Task API has no phase field\n' "$id" >&2
  exit 1
fi
if [ -n "$branch" ]; then
  printf 'state-report: the report of %s was refused: --branch is a local-posture flag, the Task API has no branch field\n' "$id" >&2
  exit 1
fi
if [ -n "$set_mr_url" ]; then
  printf 'state-report: the report of %s was refused: --mr-url is a local-posture flag, under the dashboard the mr_url of the task file is what is reported\n' "$id" >&2
  exit 1
fi
if [ -n "$set_status" ]; then
  printf 'state-report: the report of %s was refused: --set-status is the standalone claim step — under the dashboard posture the status of the task file is what is reported\n' "$id" >&2
  exit 1
fi

# ponytail: node builds and reads the JSON — policy-guard.sh already makes it a hard dependency of every session,
# so this adds none. Multi-line arguments become one array element per line.
body=$(S=$status P=$progress A=$attempts T=$tool_failures M=$message U=$mr_url node -e '
const e=process.env,o={},lines=s=>s.split("\n").filter(l=>l.trim()!=="");
if(e.S)o.status=e.S;
if(e.P)o.progress=e.P;
if(e.A)o.attempts=lines(e.A);
if(e.T)o.tool_failures=lines(e.T);
if(e.U)o.mr_url=e.U;
if(e.M)o.message=e.M;
process.stdout.write(JSON.stringify(o))') || die2 "the report could not be composed"
[ "$body" != '{}' ] || die2 "nothing to report for $id — the task file has no status and there is no progress file"

# the HTTP call is a variable so a test can put a stub in its place; everywhere else it is plain curl
out=$(printf '%s' "$body" | "${STATE_REPORT_CURL:-curl}" -sS -X PATCH \
  -H "Authorization: Bearer $DASHBOARD_API_TOKEN" -H 'Content-Type: application/json' \
  -w '\n%{http_code}' --data-binary @- "$DASHBOARD_URL/api/tasks/$id" 2>/dev/null) \
  || die2 "the dashboard at $DASHBOARD_URL is unreachable — the report of $id was not delivered"
code=$(printf '%s\n' "$out" | sed -n '$p')
resp=$(printf '%s\n' "$out" | sed '$d')

case "$code" in
  2??) exit 0 ;;
  400)
    err=$(printf '%s' "$resp" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  let v="";try{v=JSON.parse(s).error||""}catch{}process.stdout.write(String(v))})' 2>/dev/null) || err=''
    printf 'state-report: the dashboard refused the report of %s: %s\n' "$id" "${err:-$resp}" >&2
    exit 1 ;;
  *)
    printf 'state-report: the dashboard answered %s for %s — the report was not delivered: %s\n' \
      "$code" "$id" "$resp" >&2
    exit 2 ;;
esac
