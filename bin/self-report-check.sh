#!/bin/sh
# Stop hook (ADR-0009): a session must not end without a self-report the controller can see —
# status review|blocked|failed in the task, delivered through state-report.sh: by default a commit and a push
# from the session's own state clone (ADR-0050, the standalone posture), or through the Task API in the
# alternative posture where DASHBOARD_URL is set (ADR-0047).
# The hook is the writer: it sends the report itself, so the agent cannot forget to.
# A task that already carries a terminal status, `done` or `closed`, is finished and is skipped by every loop
# below (T-186): it has no self-report left to make, and re-reporting it is a transition state-report.sh refuses,
# which used to block the Stop for the whole round budget.
set -eu

stdin=$(cat)

# Issue #313: this file used to open with `stop_hook_active=true → exit 0`, which made every guarantee below
# first-Stop-only — a session that simply stopped a second time passed unconditionally, status check, #290 audit,
# #308 sweep, commit and push included. That early exit was not gratuitous: a hook that always blocks loops
# forever, which is worse than the hole (it breaks every session instead of letting a rare one through). So the
# loop is bounded instead of the guard removed: every round this hook blocks is counted, and after
# ROUND_BUDGET blocked rounds it stops blocking and records the unresolved violation in the state repo (see
# record_unresolved below) rather than passing silently.
#
# Nothing here reads stop_hook_active any more. It is documented as "true when Claude Code is already continuing
# as a result of a stop hook", but whether that means *a Stop hook blocked* or merely *a Stop hook ran* cannot be
# settled from this repo. Counting our own blocks needs no signal from the harness and is correct under either
# reading.
#
# ponytail: 3 rounds, the same number as max_attempts in the task frontmatter — three real chances to fix the
# self-report, and at most three extra agent turns per session. It is a knob: change the number, nothing else.
ROUND_BUDGET=3

# The counter lives in the per-session work dir next to <work>/.harness-test-edits and <work>/.harness-test-base
# (issues #290/#308), and is keyed by the session id so a work dir reused by a second attempt starts over.
# ponytail: no JSON parser for one flat string field, and no node dependency in this hook.
sid=$(printf '%s' "$stdin" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# task_of, the owner-based lookup and the layout resolver are shared with session-stats.sh and pre-compact.sh
. "$(dirname -- "$0")/lib-tasks.sh"

# ponytail: a triage session sits in the state clone itself (ADR-0018), the others next to it in the product one —
# resolve_state_dir (lib-tasks.sh) is that one rule, shared with session-stats.sh and state-report.sh
state=$(resolve_state_dir "$PWD")

# ponytail: the task is identified by the CLAUDE.md prepare_task generated into cwd ("# Task <id>"). Without that
# line (a standalone session that owns several tasks, ADR-0050) the tasks are the ones whose `owner:` ends in this
# session's id — `factory@<host>:<session_id>`, the whole id after the last colon.
ids=$(sed -n '1s/^# Task //p' CLAUDE.md 2>/dev/null) || :
if [ -z "${ids:-}" ]; then
  [ -n "${sid:-}" ] || exit 0
  ids=$(owned_task_ids "$sid") || :
fi
[ -n "${ids:-}" ] || exit 0

# the first task keeps the single-task shape of every message and record below: the parent (an id with no -NN
# suffix) of a session that owns a block and its children, otherwise the first owned task
id=''
for i in $ids; do
  if is_parent_id "$i"; then id=$i; break; fi
done
[ -n "$id" ] || id=$(printf '%s\n' "$ids" | head -n1)
task=$(task_of "$id")
[ -n "${task:-}" ] && [ -f "$task" ] || exit 0

# T-003: in the standalone layout ($WORK_DIR/<key>/<task-id>/, ADR-0049) the per-session stamps live in
# $WORK_DIR/<key>/.harness/<task-id>/, not next to a work dir that is a git worktree. T-162: a coordinator
# standing in the registered clone gets the same stamp directory for the task it reports for, resolved once the
# owner lookup above named it. The worker layout resolves to exactly the relative path below, so nothing moves.
stamp=..
if resolve_session_layout "$PWD" "$id" && [ "$LO_POSTURE" = standalone ]; then
  stamp=$LO_STAMP
  mkdir -p "$stamp" 2>/dev/null || :
fi
rounds="$stamp/.harness-stop-rounds"

# Issue #313 point 2: the budget must never end in a silent pass — that silence is the failure mode being fixed.
# The unresolved violation is written where the controller and a human already look: a line in the task's
# `## Attempts`, in the shape session-stats.sh and Orchestrator.SetStatusAsync already write there, sent through
# state-report.sh, which is the one write path either posture has (ADR-0050, and ADR-0047 where a dashboard is
# configured). Idempotent (a repeated Stop must not append a
# second line) and never fatal — a failure to record must not take the session down on top of everything else.
record_unresolved() { # <a short label of what stayed unresolved>
  # under a dashboard the line is written server side, so the local clone never gains it and grepping the task
  # file cannot deduplicate any more: the marker is a file in the work dir, next to the round counter. The `<!-- sid:… -->`
  # marker of session-stats.sh stays deliberately unshared — it greps for exactly that string to skip its own
  # duplicate, so sharing it would silently suppress the stats line for this session.
  marker="$stamp/.harness-stop-unresolved"
  if [ -f "$marker" ] && grep -qFx "${sid:-?}" "$marker" 2>/dev/null; then return 0; fi

  attempt=$(sed -n 's/^attempt:[[:space:]]*//p' "$task" | head -n1)
  line="attempt ${attempt:-?} — UNRESOLVED Stop contract, the session ended without satisfying it after $ROUND_BUDGET blocked rounds (issue #313): $1"

  # `--no-status`: the record is *about* a status the server may well refuse, and it must not go down with it.
  sh "$(dirname -- "$0")/state-report.sh" --task "$id" --no-status --attempts "$line" \
    --message "stop: $id unresolved Stop contract" >/dev/null 2>&1 || return 0
  printf '%s\n' "${sid:-?}" >> "$marker" 2>/dev/null || :
  return 0
}

# <$1> is the reason the agent gets (unchanged wording, every rule below keeps its own), <$2> the short label the
# exhaustion record carries. The counter file is "<session id> <blocked rounds>".
block() {
  n=0
  if [ -f "$rounds" ] && [ "$(sed -n '1s/ .*//p' "$rounds" 2>/dev/null)" = "$sid" ]; then
    n=$(sed -n '1s/^[^ ]* //p' "$rounds" 2>/dev/null)
    case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  fi
  if [ "$n" -ge "$ROUND_BUDGET" ]; then record_unresolved "$2"; exit 0; fi
  # a counter that cannot be persisted cannot bound anything, and an unbounded block is the worse failure mode of
  # the two — so treat an unwritable work dir as an exhausted budget rather than starting a loop nobody can end.
  printf '%s %s\n' "$sid" "$((n + 1))" > "$rounds" 2>/dev/null \
    || { record_unresolved "$2"; exit 0; }
  echo "$1" >&2
  exit 2
}

# the rules run over every owned task and block once, naming each failing one: <msgs> is what the agent reads,
# <labels> the short form the exhaustion record carries
msgs=''
labels=''
add() { msgs="${msgs:+$msgs
}$1"; labels="${labels:+$labels; }$2"; }

for i in $ids; do
  t=$(task_of "$i")
  [ -n "${t:-}" ] && [ -f "$t" ] || continue
  s=$(sed -n 's/^status:[[:space:]]*//p' "$t" | head -n1)
  # T-186: a task already at a terminal status is finished, and a finished task has no self-report left to make.
  case "$s" in done|closed) continue ;; esac

  # Evidence gate: a terminal "it worked" status is a claim, and the claim must be checkable — the proving
  # command, its exit code and the key output line under `## Evidence` in the progress snapshot
  # (skills/_shared/progress-and-push.md). blocked/failed report the opposite and need none.
  case "$s" in
    review|tests_ready)
      set -- "$state"/repos/*/progress/"$i".md
      grep -q '^## Evidence' "$1" 2>/dev/null \
        || add "Stop blocked: task $i reports '$s' but $1 has no '## Evidence' section. A status is a claim; evidence makes it checkable — run the proving command fresh (for review the acceptance command after the rebase, for tests_ready the red tests failing for the right reason), write it with its exit code and key output line under '## Evidence' in the progress file, then commit + push from the state clone." \
           "status '$s' with no '## Evidence' in the progress file — the claim is not checkable" ;;
  esac

  # T-164: a session may end while the block MRs wait on the forge, so a block in `review` with an `mr_url`
  # (the developer has it), one in `changes_requested` (the fix round is open) and one already `done` are all
  # reports the controller can see, and none of them blocks the Stop.
  case "$s" in
    review|tests_ready|blocked|failed|changes_requested|done) ;;
    *) add "Stop blocked: task $i has status '$s'. Write the self-report (ADR-0009): in the frontmatter of $t set status to review (acceptance green, or for a block its MR open with mr_url set; in the tests phase tests_ready instead, ADR-0030), changes_requested (the block MR came back with threads to answer), blocked (you need a human decision, write the question into the progress file) or failed (acceptance not met, add a line to ## Attempts), rewrite the progress snapshot $state/repos/*/progress/$i.md and commit + push from the state clone." \
         "no self-report — task $i still has status '$s', not review|tests_ready|blocked|failed (ADR-0009)" ;;
  esac
done
[ -z "$msgs" ] || block "$msgs" "$labels"

# Issue #308 point 2: the backstop that closes every route into the tests, including the ones no PreToolUse rule
# can see — `sed -i`, a heredoc, `git checkout <sha> -- <test>`, a two-line python script. It inspects the diff
# the session produced instead of the command that produced it. policy-guard.sh stamps <work>/.harness-test-base
# on the first tool call of an implement session: line 1 is the tests-phase HEAD, the rest is the inventory of
# test files that existed then. No stamp (single-phase run, the tests phase, a non-implementation archetype) =
# nothing to compare, and nothing is ever blocked here.
base="$stamp/.harness-test-base"
if [ -s "$base" ]; then
  base_sha=$(head -n1 "$base")
  # `## Output` rebases onto origin/<default> before Stop, so a test file that *upstream* changed arrives in the
  # working tree looking like this session's doing. A candidate whose current content is byte-for-byte the
  # upstream one therefore came from the rebase, not from the agent, and is dropped. A file the session edited on
  # top of the upstream change still differs from both and is kept.
  up=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$up" ]; then
    for c in origin/main origin/master; do
      if git rev-parse --verify -q "$c" >/dev/null 2>&1; then up=$c; break; fi
    done
  fi
  d=$(mktemp)
  git -c core.quotePath=false diff --name-only "$base_sha" > "$d" 2>/dev/null || : > "$d"
  # ponytail: word splitting on the candidate list — a test path with a space in it is not evaluated here
  set -f
  for f in $(tail -n +2 "$base" | grep -Fxf "$d" - 2>/dev/null || true); do
    if [ -f "$f" ]; then cur=$(git hash-object -- "$f" 2>/dev/null || true); else cur=''; fi
    ub=''
    if [ -n "$up" ]; then ub=$(git rev-parse --verify -q "$up:$f" 2>/dev/null || true); fi
    if [ -n "$ub" ] && [ "$ub" = "$cur" ]; then continue; fi
    printf '%s\n' "$f" >> "$stamp/.harness-test-edits"
  done
  set +f
  rm -f "$d"
fi

# Issue #290 point 4, option (a): block-refactor's implement phase may mechanically follow a rename through the
# tests, so policy-guard.sh records every such edit into <work>/.harness-test-edits instead of denying it. A
# feature/bugfix edit lands in the same file once its `## Test deviations` entry opened the lock (T-028). Issue #308 adds the sweep above to the same file, so
# feature/bugfix land here too when they got at a test file through bash. If this session touched a test file,
# the progress file has to declare it under `## Test deviations`, which is what the reviewer diffs against.
# No edits, no marker file, no block — a session that left the tests alone is never stopped here.
edits="$stamp/.harness-test-edits"
if [ -s "$edits" ]; then
  set -- "$state"/repos/*/progress/"$id".md
  progress=$1
  grep -q '^## Test deviations' "$progress" 2>/dev/null \
    || block "Stop blocked: this session changed test files ($(sort -u "$edits" | tr '\n' ' ')) but $progress has no '## Test deviations' section. The red tests from the tests phase are the contract (issue #290/#308) — turn them green, do not bend them; a refactor may only follow a rename mechanically through (block-refactor step 4). Revert the change, or add a '## Test deviations' section to $progress listing each test file you touched and why and self-report 'blocked' so a human decides; then commit + push from the state clone." \
    "test files changed with no '## Test deviations' in the progress file (issues #290/#308): $(sort -u "$edits" | tr '\n' ' ')"
fi

# "is it committed and pushed" is not a question the agent answers: the hook delivers the report itself through
# state-report.sh, which in the standalone posture (ADR-0050) commits in the state clone and pushes it, and under
# a configured DASHBOARD_URL sends it to the Task API instead (ADR-0047), where there is deliberately no git
# fallback because a second write path is exactly what that ADR removes. The exit codes carry the same meaning in
# both. An undeliverable report therefore blocks, and once the round budget is spent block() records the
# violation and lets the session go.
for i in $ids; do
  t=$(task_of "$i")
  [ -n "${t:-}" ] && [ -f "$t" ] || continue
  s=$(sed -n 's/^status:[[:space:]]*//p' "$t" | head -n1)
  # T-186 again: nothing to deliver for a finished task, and the report would be refused as a transition
  case "$s" in done|closed) continue ;; esac
  set +e
  report=$(sh "$(dirname -- "$0")/state-report.sh" --task "$i" --message "progress: $i $s" 2>&1 >/dev/null)
  report_rc=$?
  set -e
  case "$report_rc" in
    0) ;;
    1) add "Stop blocked: state-report.sh refused the self-report of task $i. $report Fix what it names in $t or in $state/repos/*/progress/$i.md and stop again: the report is sent for you, you do not commit or push it." \
         "state-report.sh refused the self-report of $i: $report" ;;
    *) if [ -n "${DASHBOARD_URL:-}" ]; then
         add "Stop blocked: the self-report of task $i never reached the controller. $report The state clone cannot push it instead (ADR-0047) — check DASHBOARD_URL and DASHBOARD_API_TOKEN in the session environment, note what happened in the progress file and stop again." \
           "the self-report of $i never reached the dashboard: $report"
       else
         add "Stop blocked: the self-report of task $i could not be pushed to the state root. $report There is no dashboard to send it to instead (ADR-0050) — check \`<root>/state\` is reachable and carries receive.denyCurrentBranch=updateInstead (ADR-0040), note what happened in the progress file and stop again." \
           "the self-report of $i could not be pushed to the state root: $report"
       fi ;;
  esac
done
[ -z "$msgs" ] || block "$msgs" "$labels"

# the self-report is in the state repo, so the session's statistics can go on top of it. Both scripts report for
# the same task, hence the chain instead of a second Stop hook running beside this one. Telemetry never decides a
# Stop: whatever it returns, this hook passes.
printf '%s' "$stdin" | sh "$(dirname -- "$0")/session-stats.sh" >/dev/null 2>&1 || :

exit 0
