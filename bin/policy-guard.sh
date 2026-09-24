#!/bin/sh
# PreToolUse policy (E4.4, ADR-0009/0012, P7 "the text describes, the hook enforces"): the deterministic
# twin of the prohibitions in the block-* skills. exit 2 = deny, and the reason on stderr reaches the agent.
# Deny by default — whatever the guard cannot evaluate, it blocks.
set -eu

WORK_DIR=${WORK_DIR:-/work}
STATUS_ALLOWED='review blocked failed'

# see: skills/factory/references/solve-pitfalls.md (T-155), the fix each deny carries; DENY_FIX adds the fixes
# that depend on the shape of the denied Bash command
DENY_FIX=''
deny() { printf 'policy-guard deny: %s%s\n' "$1" "$DENY_FIX" >&2; exit 2; }

# ponytail: node is in the worker image (base node:22) — no parser of our own, no extra dependency.
# QS-13 (T-003): exactly one node run per hook call, and it reads the hook stdin itself. Every field the guard
# can need comes back from that single pass as one escaped line — a Bash command carries the newlines of a
# heredoc, so `\` and the line breaks are escaped on the way out and `printf %b` puts them back on the way in.
fields=$(node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let o;try{o=JSON.parse(s)}catch(err){process.exit(3)}
const t=o.tool_input||{};
const nt=[t.content,t.new_string,...((t.edits)||[]).map(e=>e.new_string)].filter(x=>typeof x==="string").join("\n");
const e=v=>String(v==null?"":v).replace(/\\/g,"\\\\").replace(/\n/g,"\\n").replace(/\r/g,"\\r");
process.stdout.write([o.tool_name,o.cwd,o.session_id,
  t.file_path!=null?t.file_path:t.notebook_path,t.command,nt].map(e).join("\n"))})') \
  || deny "unreadable JSON on the hook stdin"
{ IFS= read -r f_tool || f_tool=''
  IFS= read -r f_cwd  || f_cwd=''
  IFS= read -r f_sid  || f_sid=''
  IFS= read -r f_path || f_path=''
  IFS= read -r f_cmd  || f_cmd=''
  IFS= read -r f_new  || f_new=''
} <<EOF
$fields
EOF
# QS-13: undoing the escaping costs a process, so it only runs when there is an escape to undo — a POSIX path
# and an ordinary one-line command go through untouched
un() { # <variable name> <escaped value>
  case "$2" in
    *\\*) eval "$1=\$(printf '%b' \"\$2\")" ;;
    *) eval "$1=\$2" ;;
  esac
}

un tool "$f_tool"
un cwd "$f_cwd"
un sid "$f_sid"

# T-003: one layout rule, shared with the Stop hook and session-stats (ADR-0049). The cwd gives the task on the
# worker — and the work dir of the RC clones, which are $WORK_DIR/<name> with no task file at all. In the
# standalone posture the coordinator's cwd is the user's clone and carries no task, so there the task comes from
# the write target instead (adopt_target below).
. "$(dirname -- "$0")/lib-tasks.sh"

# T-003: every path comparison below is between these two and a write target, so all three are spelled the one
# way norm_path defines (forward slashes, a lower-case drive letter, no trailing slash, `x/..` collapsed) —
# `$WORK_DIR/` with a trailing slash, or a Windows target written `D:\…`, otherwise matches nothing and the
# deny-by-default the whole guard rests on turns into an allow-by-typo.
norm_into WORK_DIR "$WORK_DIR"
norm_into cwd "$cwd"
# issue #358's mention scan reads raw command text, where a Windows work root can be spelled `D:\key` just as
# well as `d:/key`: its pattern takes either slash and either case of the drive letter. A POSIX root is its own
# pattern and pays nothing.
WORK_RE="$WORK_DIR/"
case "$WORK_DIR" in
  [a-z]:/*)
    WORK_RE=$(printf '%s' "$WORK_RE" | sed 's,/,[/\\],g')
    wd_l=${WORK_DIR%%:*}
    WORK_RE="[$(printf '%s' "$wd_l" | tr '[:lower:]' '[:upper:]')$wd_l]${WORK_RE#?}" ;;
esac

# a write target the way the comparisons want it: absolute (a Windows `D:/…` or `D:\…` is absolute too — read as
# relative it would be joined onto the cwd and land inside whatever that cwd is) and normalised.
abs_norm() { # <path>
  case "$1" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) norm_path "$1" ;;
    *) norm_path "$cwd/$1" ;;
  esac
}

if resolve_layout "$cwd" "$WORK_DIR"; then
  task=$LO_TASK; own=$LO_OWN; state=$LO_STATE; stamp=$LO_STAMP; posture=$LO_POSTURE
else
  # ADR-0049: HARNESS_WORKER=1 is the worker container, where a cwd outside the work root stays fail-closed.
  # Standalone posture — only the cwd rule is waived: every target-path rule below still runs with an empty
  # own work dir, and the task is derived from the target path instead.
  [ "${HARNESS_WORKER:-}" = 1 ] && deny "cwd '$cwd' is not inside $WORK_DIR/<task> (worker posture). Do not relocate the session with EnterWorktree or a 'cd' into a worktree: stay where the session started and reach the other tree by absolute path, 'git -C $WORK_DIR/<key>/T-NNN-NN ...'."
  task=''; own=''; state=''; stamp=''; posture=standalone
fi
# 2026-09-07 lesson D: the coordinator scope below opens only in the standalone layout on a developer machine —
# the worker container (HARNESS_WORKER=1) and the worker layout keep exactly the reach they had.
[ "${HARNESS_WORKER:-}" != 1 ] || posture=worker

docs_carveout() { # <absolute path>
  rel=${1#"$cwd"/}
  case "$rel" in /*) rel=${rel#"$own"/} ;; esac
  case "$rel" in docs/*|CONTEXT.md|README.md) return 0 ;; esac
  return 1
}

# Everything the rules below read out of the task file. It is a function because the standalone posture learns
# which task it is looking at only from the write target (adopt_target), and then has to read it again.
archetype=''; branch=''; phase=''; taskfile=''; triage_target=''; architecture_docs=''
status=''; plan_hash=''; owner=''
TEST_GLOBS=''; TEST_GLOBS_SRC=''; TEST_PATS=''; progress=''
load_task_context() {
  archetype=''; branch=''; phase=''; taskfile=''; triage_target=''; architecture_docs=''
  status=''; plan_hash=''; owner=''
  TEST_GLOBS=''; TEST_GLOBS_SRC=''; TEST_PATS=''; progress=''
  STATUS_ALLOWED='review blocked failed'
  # task_of (lib-tasks.sh) picks the file by its `id:` line, out of the state clone of this posture
  if [ -n "$task" ] && [ -n "$state" ]; then taskfile=$(task_of "$task") || taskfile=''; fi
  if [ -n "$taskfile" ]; then
    # QS-13: the whole frontmatter in one pass — a `sed … | head -n1` per field was six processes on its own
    { IFS= read -r status    || status=''
      IFS= read -r archetype || archetype=''
      IFS= read -r branch    || branch=''
      IFS= read -r phase     || phase=''
      IFS= read -r plan_hash || plan_hash=''
      IFS= read -r owner     || owner=''
    } <<EOF
$(awk '
  /^---[ \t\r]*$/ { if (++fence == 2) exit; next }
  fence == 1 && match($0, /^[A-Za-z_]+:[ \t]*/) {
    k = substr($0, 1, index($0, ":") - 1); v = substr($0, RLENGTH + 1)
    sub(/[ \t\r]+$/, "", v)
    if (!(k in f)) { f[k] = v }
  }
  END { b = f["branch"]; sub(/[ \t#].*$/, "", b)
        print f["status"]; print f["archetype"]; print b
        print f["phase"]; print f["plan_hash"]; print f["owner"] }' "$taskfile")
EOF
  fi
  # ADR-0036: triage of a roadmap draft carries its target in `## Context` as `- draft: repos/<key>/tasks/<id>.md`
  if [ "$archetype" = triage ] && [ -n "$taskfile" ]; then
    triage_target=$(sed -n 's/^- draft:[[:space:]]*`\{0,1\}\(repos\/[^`[:space:]]*\.md\)`\{0,1\}[[:space:]]*$/\1/p' "$taskfile" | head -n1)
    if [ -n "$triage_target" ]; then triage_target="$state/$triage_target"; fi
  fi
  # architect-agent plan #3: a research task whose `## Context` names the architecture-docs skill gets a
  # product-repo write carve-out (docs/**, CONTEXT.md, README.md) — every other research session stays
  # read-only. README.md is in because the bootstrap task template asks for a paragraph pointing at the model
  # (docs/design/architecture-model.md § Docs); without it the task's own ## Docs section is unsatisfiable.
  if [ "$archetype" = research ] && [ -n "$taskfile" ]; then
    if awk '/^## Context/ { s=1; next } /^## / { s=0 } s' "$taskfile" | grep -q 'architecture-docs'; then
      architecture_docs=1
    fi
  fi
  # ADR-0030: the tests phase self-reports tests_ready; review belongs to the implement phase
  if [ "$phase" = tests ]; then STATUS_ALLOWED='tests_ready blocked failed'; fi
  # ADR-0050's standalone divergence: with no dashboard there is no other writer, and state-report.sh already
  # accepts `claimed → in_progress` and `ready → in_progress`. The guard denying the same word deadlocked every
  # block at `claimed` (2026-09-07, lesson B). With a dashboard configured it writes that transition itself.
  [ -n "${DASHBOARD_URL:-}" ] || STATUS_ALLOWED="$STATUS_ALLOWED in_progress"

  # Issue #290: the test lock of the implement phase. "The red tests are the contract" was prompt-level only, and
  # prompting is not a control — ImpossibleBench measured strict prompting cutting reward hacking on SWE-bench
  # from 66 % only to 54 %, and EvilGenie found Claude models specifically favour editing the tests directly.
  # The globs come from the repo's toolset frontmatter (ADR-0039, issue #289) through the very awk snippet
  # docs/design/toolset.md publishes — one source, no YAML parser. `phase` is empty (or `null`) on a single-phase
  # run, so nothing below ever fires there.
  if [ "$phase" = implement ] && [ -n "$taskfile" ]; then
    key=${taskfile#"$state"/repos/}; key=${key%%/*}
    progress="$state/repos/$key/progress/$task.md"
    toolset="$state/repos/$key/toolset.md"
    if [ -f "$toolset" ]; then
      TEST_GLOBS=$(awk '/^test-globs:[[:space:]]*$/ { g=1; next }
           g && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); print; next }
           g { exit }' "$toolset")
    fi
    if [ -n "$TEST_GLOBS" ]; then
      TEST_GLOBS_SRC="test-globs in repos/$key/toolset.md"
    else
      # a repo with no toolset (or a toolset with no frontmatter) must keep working — the fallback is named in
      # the deny reason so a human can tell which globs were in force
      TEST_GLOBS='**/tests/**
**/*Tests.*'
      TEST_GLOBS_SRC="the built-in default (repos/$key/toolset.md declares no test-globs)"
    fi
  fi
  # The `**`→`*` rewrite is done once here rather than per call: issue #308 walks the whole `git ls-files`
  # inventory through path_is_test, and a `sed` per glob per file would be thousands of processes.
  if [ -n "$TEST_GLOBS" ]; then TEST_PATS=$(printf '%s' "$TEST_GLOBS" | sed 's|\*\*|*|g'); fi
}

# `case` is the whole glob matcher: `*` in a case pattern already spans `/`, so `**` collapses to `*`. The path
# is tried repo-relative (an anchored glob like `src/**`) and again with a leading `/` (so a leading `**/` also
# matches a file in the repo root). Nothing matches on a bare substring — `**/tests/**` becomes `*/tests/*` and
# needs a literal `/tests/`, so `src/Testing/Helper.cs` and `src/contest/Foo.cs` stay allowed.
# ponytail: a directory component that itself reads like a test file (`Foo.Tests.Core/Prod.cs` against
# `**/*Tests.*`) over-denies; the escape hatch for that is the same `blocked` as for any other test change.
path_is_test() {
  rel=${1#"$cwd"/}
  case "$rel" in /*) rel=${rel#"$own"/} ;; esac
  set -f
  for pat in $TEST_PATS; do
    case "$rel" in $pat) set +f; return 0 ;; esac
    case "/$rel" in $pat) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

# Issue #308: the Stop-hook backstop that closes the routes no PreToolUse rule can see (`sed -i`, a heredoc, a
# two-line python script) needs a boundary to diff against. The cheapest reversible one is a stamp in the fresh
# per-session work dir — the same trick #290 used for `.harness-test-edits`: it lives outside both clones, so the
# rebase in `## Output` cannot corrupt it, and it needs no bookkeeping in the progress file and no second SHA in
# the task frontmatter. Line 1 is the tests-phase HEAD (this runs on the *first* tool call of the session, before
# anything has been written, and the implement phase starts from a fresh clone of what the tests phase pushed —
# ADR-0030, block-tests `## Self-report`), the remaining lines are the test files that existed at that moment.
# self-report-check.sh diffs exactly that inventory against exactly that SHA.
# ponytail: no repo, no git, no stamp. The backstop is best-effort — the deny rules above are not.
# T-003: the stamp directory is $stamp — the work dir itself on the worker, $WORK_DIR/<key>/.harness/<task-id>
# in the standalone posture, where the work dir is a git worktree the rebase would carry the stamps through.
stamp_test_base() {
  [ -n "$stamp" ] && [ -n "$TEST_GLOBS" ] || return 0
  base_mark="$stamp/.harness-test-base"
  [ ! -f "$base_mark" ] || return 0
  case "$archetype" in
    feature|bugfix|refactor) ;;
    *) return 0 ;;
  esac
  if base_sha=$(git -C "$cwd" rev-parse HEAD 2>/dev/null); then
    mkdir -p "$stamp" 2>/dev/null || return 0
    { printf '%s\n' "$base_sha"
      git -C "$cwd" ls-files 2>/dev/null | while IFS= read -r f; do
        if path_is_test "$cwd/$f"; then printf '%s\n' "$f"; fi
      done
    } > "$base_mark.tmp" 2>/dev/null && mv "$base_mark.tmp" "$base_mark" || rm -f "$base_mark.tmp"
  fi
  return 0
}

# ADR-0030 says a test from the tests phase "may only be changed with a justification in the progress file
# (`## Test deviations`)". Issue #290 implemented that for feature/bugfix as a hard deny, which left an approved
# deviation with no path into the files at all (T-028): the human wrote the approval into the task and the next
# session was denied exactly like the one before it. The gate is the written analysis instead — the first edit is
# denied and tells the session to work out whether the goal needs the test changed or the implementation fixed;
# an entry under `## Test deviations` naming this file then opens it. The edit is recorded either way
# (self-report-check.sh audits it on Stop, block-review diffs it against the tests-phase commit).
# ponytail: naming the file is all a shell hook can check — whether the reasoning holds is the reviewer's job.
deviation_declared() { # <absolute path>
  [ -n "$progress" ] && [ -f "$progress" ] || return 1
  awk '/^## Test deviations/ { s = 1; next } /^## / { s = 0 } s' "$progress" | grep -qF "$(basename "$1")"
}

check_test_lock() { # <tool> <absolute path>
  [ -n "$TEST_GLOBS" ] || return 0
  case "$archetype" in feature|bugfix|refactor) ;; *) return 0 ;; esac
  if [ -n "$state" ]; then case "$2" in "$state"/*) return 0 ;; esac; fi
  path_is_test "$2" || return 0
  # A *new* test file stays allowed: the lock protects the tests-phase contract, not new coverage (issue #293,
  # the CRAP loop, adds missing tests in this same phase). Only a file that already exists is a modification —
  # Edit/MultiEdit imply one, a Write does not. Adding a new *case* to an existing test file is therefore
  # blocked too; that is the deliberate price of the cheap deterministic rule, and `blocked` is the way out.
  { [ "$1" = Write ] && [ ! -e "$2" ]; } && return 0
  # Issue #290 point 4, option (a): block-refactor's implement phase legitimately follows a rename through the
  # tests, so it is not hard-denied here. It is recorded instead, and self-report-check.sh fails the session on
  # Stop if the progress file carries no matching `## Test deviations` entry. feature/bugfix reach the same
  # recording path once the analysis for this file is on record (deviation_declared above).
  if [ "$archetype" = refactor ] || deviation_declared "$2"; then
    mkdir -p "$stamp" 2>/dev/null || true
    printf '%s\n' "$2" >> "$stamp/.harness-test-edits" 2>/dev/null || true
    return 0
  fi
  deny "the implement phase must not modify a test (issue #290, ADR-0030): '$2' matches $TEST_GLOBS_SRC [$(printf '%s' "$TEST_GLOBS" | tr '\n' ' ')]. The red tests from the tests phase are the contract — do not bend them to fit. First work out which of the two is wrong for the goal in '## Acceptance': if the implementation can be made to satisfy this test as written, fix the implementation. Only if the test itself is wrong, write that analysis into '## Test deviations' in ${progress:-the progress file} — name '$(basename "$2")', the exact change, and why fixing the implementation cannot get you there — and then repeat this edit: with the entry on record it is allowed and logged for the reviewer. A brand new test file needs none of this. Do not retry this edit before the entry exists."
}

# T-003 rule (a), QS-14: the clone a repo is registered with (`path:` in <root>/state/repos.yml, ADR-0013
# revision) is the human's own checkout and is read-only towards every session, in every posture — work happens
# in the worktrees under $WORK_DIR/<key>/<task-id>/. Loaded once per call and only when the registry exists, so
# a factory that never ran `factory add-repo` pays nothing for this rule.
CLONE_PATHS=''
CLONE_PATHS_LOADED=''
check_product_clone() { # <absolute path>
  if [ -z "$CLONE_PATHS_LOADED" ]; then
    CLONE_PATHS_LOADED=1
    CLONE_PATHS=$(repo_clone_paths 2>/dev/null) || CLONE_PATHS=''
  fi
  [ -n "$CLONE_PATHS" ] || return 0
  # QS-13: both sides through lib-tasks.sh's norm_into, which spends a subshell only on a path that actually
  # needs normalising (a Windows one, or one with a trailing slash) — a POSIX comparison stays as cheap as it was.
  norm_into np "$1"
  while IFS='	' read -r ck cp; do
    [ -n "$cp" ] || continue
    norm_into cp "$cp"
    case "$np" in
      "$cp"|"$cp"/*)
        deny "the clone registered for '$ck' in repos.yml is read-only (ADR-0049, QS-14): $1. That directory is the human's own checkout — work happens in a worktree of it under $WORK_DIR/$ck/<task-id>/, created with 'git worktree add'." ;;
    esac
  done <<EOF
$CLONE_PATHS
EOF
}

# T-003 rule (b): the human gate, enforced. A worktree under $WORK_DIR/<key>/<task-id>/ opens only for a task
# that is `ready` with the body the `plan_hash` commit carries (the twin of DispatchGate.BodyUnchanged: nothing
# dispatches on any other basis, and `ready` with a plan_hash is what task-approve.sh writes in the standalone
# posture and what the dashboard writes where one is configured), or one this very session already holds: `owner:
# factory@<host>:<session_id>` with the session id off the hook stdin. A block (`T-NNN-NN`) is created `claimed`
# by the coordinator and never carries a plan_hash of its own, so `claimed` + owner is the whole gate for it.
# It reads what load_task_context already parsed out of the frontmatter — nothing here opens the file twice.
# T-187: the two denials below name the approver, and the approver is a command in the standalone posture and a
# dashboard only where DASHBOARD_URL is set. Telling a standalone session to go to a dashboard it does not have
# is what sent four sessions to tell their user to "close it in the dashboard".
approval_stale() { # <the target that asked for it> <the plan_hash it was approved as>
  if [ -z "${DASHBOARD_URL:-}" ]; then
    deny "the body of $task changed since it was approved as $2 (DispatchGate.BodyUnchanged): re-approve it with $(dirname -- "$0")/task-approve.sh $task --state $state before working in its worktree: $1"
  fi
  deny "the body of $task changed since it was approved as $2 (DispatchGate.BodyUnchanged), so re-approve it in the dashboard before working in its worktree: $1"
}
approval_gate() { # <the target that asked for it>
  if [ -z "$taskfile" ]; then
    if [ -z "${DASHBOARD_URL:-}" ]; then
      deny "no task file for '$task' in $state: a worktree is only created for a task approved with task-approve.sh (status ready with a plan_hash) or one this session already owns (ADR-0049): $1. Create the task file first, with task-new.sh from the plugin's bin/, and add the worktree after it exists."
    fi
    deny "no task file for '$task' in $state: a worktree is only created for a task the dashboard approved (status ready with a plan_hash) or one this session already owns (ADR-0049): $1. Create the task file first, with task-new.sh from the plugin's bin/, and add the worktree after it exists."
  fi
  case "$status" in
    ready)
      case "${plan_hash%%[ 	#]*}" in
        ''|null) deny "task $task is ready but carries no plan_hash — a human has not approved this body yet (ADR-0004), so its worktree stays closed: $1" ;;
        *) gph=${plan_hash%%[ 	#]*} ;;
      esac
      # DispatchGate.BodyUnchanged: the body at the approved commit against the body on disk, both without the
      # frontmatter and without the two sections the machine keeps writing back (`## Attempts`,
      # `## Tool failures` — the status notes and the session-stats lines). A missing commit and an empty
      # approved body are the same mismatch (DispatchGate.cs:83-87).
      gappr=$(git -C "$state" show "$gph:${taskfile#"$state"/}" 2>/dev/null) || gappr=''
      [ -n "$gappr" ] || deny "the approved body of $task cannot be read from plan_hash $gph in $state (a missing commit or an empty body is a mismatch, DispatchGate.BodyUnchanged): $1"
      # the approved body travels in the environment, not in `awk -v`: -v runs its value through escape
      # processing, so a body containing `printf %s\n` (or any other backslash) would arrive changed and every
      # comparison against it would report a mismatch that is not there.
      gappr="$gappr" awk '
        BEGIN { approved = ENVIRON["gappr"] }
        function norm(text,   n, i, lines, skip, t, out) {
          n = split(text, lines, "\n"); skip = 0; out = ""
          for (i = 1; i <= n; i++) {
            t = lines[i]; sub(/^[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t)
            # DispatchGate.Normalize:118-119 — only `# ` and `## ` end a machine section, so a `### ` inside one
            # does not turn it back on and one under it does not turn it off
            if (t ~ /^# / || t ~ /^## /) { skip = (t == "## Attempts" || t == "## Tool failures") }
            if (!skip) { out = out lines[i] "\n" }
          }
          sub(/^\n+/, "", out); sub(/\n+$/, "", out); return out
        }
        function body(text,   p) { if (text ~ /^---\n/) { p = index(substr(text, 5), "\n---\n")
            if (p > 0) { return substr(text, p + 9) } } return text }
        { cur = cur $0 "\n" }
        END { a = norm(body(approved)); b = norm(body(cur))
              exit (a != "" && a == b) ? 0 : 1 }' "$taskfile" \
        || approval_stale "$1" "$gph"
      ;;
    claimed|in_progress|tests_ready|review|blocked|failed)
      case "$owner" in
        factory@*:"$sid") ;;
        *) deny "task $task is '$status' but its owner is not this session (${owner:-none}), so its worktree belongs to someone else: $1" ;;
      esac
      ;;
    *)
      deny "task $task is '$status' — a worktree opens only for a task that is ready with an approved plan_hash, or one this session owns (claimed|in_progress|tests_ready|review|blocked|failed with owner: factory@<host>:$sid): $1" ;;
  esac
}

# T-003 rule (b), the other half: the standalone posture's cwd is the user's own clone and names no task, so the
# task and its work dir come from the write *target*. The worker layout keeps working through the cwd, which
# already gave `own` above, and is never re-derived here.
adopt_target() { # <absolute target path>
  [ -z "$own" ] || return 0
  resolve_layout "$1" "$WORK_DIR" || return 0
  [ "$LO_POSTURE" = standalone ] || return 0
  task=$LO_TASK; own=$LO_OWN; state=$LO_STATE; stamp=$LO_STAMP
  load_task_context
  approval_gate "$1"
  stamp_test_base
}

# 2026-09-07 lesson D (rows 11-13): the coordinator of skills/factory/references/solve.md works in
# $WORK_DIR/<key>/T-NNN and, from there, creates the block worktrees $WORK_DIR/<key>/T-NNN-NN and writes the stamp
# and diff files under $WORK_DIR/<key>/.harness/. Three helpers, all standalone-only (`posture`):
# — the `owner:` of another task's frontmatter, read fresh: load_task_context holds the session's own task and
#   must not be clobbered by a look at a child
task_field() { # <task id> <frontmatter key>
  tf_saved=$state
  state=${state:-$WORK_DIR/state}
  tf_file=$(task_of "$1") || tf_file=''
  state=$tf_saved
  [ -n "$tf_file" ] || return 0
  awk -v k="$2" '/^---[ \t\r]*$/ { if (++fence == 2) exit; next }
                 fence == 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2)
                   sub(/^[ \t]*/, "", v); sub(/[ \t\r]+$/, "", v); print v; exit }' "$tf_file"
}
owner_is_session() { # <task id>
  case "$(task_field "$1" owner)" in factory@*:"$sid") return 0 ;; esac
  return 1
}
# T-228 D1: a read, never a write. The coordinator reads into the worktree of a block whose parent it owns, and a
# block reads its own brief, which stays out of coord_scope so that it does not become writable.
read_scope() { # <absolute path>
  [ "$posture" = standalone ] || return 1
  case "$1" in *..*) return 1 ;; esac
  norm_into rs_p "$1"
  case "$task" in
    T-[0-9][0-9][0-9]-[0-9][0-9])
      [ -n "$own" ] && [ "$rs_p" = "${own%/*}/.harness/${task%-[0-9][0-9]}/brief-$task.md" ] && return 0 ;;
  esac
  resolve_layout "$rs_p" "$WORK_DIR" || return 1
  [ "$LO_POSTURE" = standalone ] || return 1
  case "$LO_TASK" in T-[0-9][0-9][0-9]-[0-9][0-9]) ;; *) return 1 ;; esac
  owner_is_session "${LO_TASK%-[0-9][0-9]}"
}
# — $WORK_DIR/<key>/.harness/<T>[/…] recognised, the task id in HT_TASK
harness_target() { # <absolute path>
  HT_TASK=''
  case "$1" in "$WORK_DIR"/*) ;; *) return 1 ;; esac
  ht_rest=${1#"$WORK_DIR"/}
  ht_key=${ht_rest%%/*}
  case "$ht_rest" in "$ht_key"/.harness/?*) ;; *) return 1 ;; esac
  ht_rest=${ht_rest#"$ht_key"/.harness/}
  HT_TASK=${ht_rest%%/*}
  is_task_id "$HT_TASK"
}
# — the scope itself. With an own work dir: the stamp directory of the own task and of its blocks, and a child
#   block worktree whose task file this session owns (the very owner check approval_gate runs for claimed|
#   in_progress|…). With none (the cwd is the registered clone): a stamp directory of a task this session owns,
#   or of a block whose parent it owns. Anything else falls through to the rules that were there before.
coord_scope() { # <absolute path>
  [ "$posture" = standalone ] || return 1
  if [ -n "$own" ]; then
    cs_hdir=${stamp%/*}
    case "$1" in
      "$cs_hdir/$task"|"$cs_hdir/$task"/*|"$cs_hdir/$task"-[0-9][0-9]|"$cs_hdir/$task"-[0-9][0-9]/*) return 0 ;;
    esac
    resolve_layout "$1" "$WORK_DIR" || return 1
    [ "$LO_POSTURE" = standalone ] || return 1
    case "$LO_TASK" in "$task"-[0-9][0-9]) ;; *) return 1 ;; esac
    [ "$LO_OWN" = "${own%/*}/$LO_TASK" ] || return 1
    owner_is_session "$LO_TASK" && return 0
    return 1
  fi
  harness_target "$1" || return 1
  owner_is_session "$HT_TASK" && return 0
  case "$HT_TASK" in
    T-[0-9][0-9][0-9]-[0-9][0-9]) owner_is_session "${HT_TASK%-[0-9][0-9]}" ;;
    *) return 1 ;;
  esac
}

check_path() {
  p=$1
  [ -n "$p" ] || deny "empty path"
  # the `..` is judged on what was written: norm_path collapses `x/..`, and a path that needs collapsing to be
  # understood is exactly the one this guard refuses to reason about
  case "$p" in *..*) deny "a path with '..' cannot be evaluated safely: $1" ;; esac
  p=$(abs_norm "$p")
  # The kernel's own pseudo-files are not filesystem writes: /dev/tcp and /dev/udp are bash's socket
  # syntax (egress, which the firewall governs, ADR-0002) and std{out,err} are this process's own streams.
  case "$p" in /dev/null|/dev/stdout|/dev/stderr|/dev/tcp/*|/dev/udp/*) return 0 ;; esac
  check_product_clone "$p"
  # issue #358: /tmp is scratch space, not a protected surface — a work dir nested under it stays guarded
  case "$p" in "$WORK_DIR"/*) ;; /tmp|/tmp/*) return 0 ;; esac
  # 2026-09-07 lesson A1: the standalone state clone is the coordinator's shared registry and its own write path
  # (state-report.sh writes there), and resolve_layout can never adopt it as a task — `state` is not a task id.
  # The worker layout's clone is $WORK_DIR/<task>/state, which this does not name, so it stays foreign there.
  case "$p" in "$WORK_DIR"/state|"$WORK_DIR"/state/*) return 0 ;; esac
  adopt_target "$p"
  if [ -z "$own" ]; then
    coord_scope "$p" && return 0
    case "$p" in "$WORK_DIR"/*) deny "write into a foreign work dir (no own work dir in this session): $p" ;; esac
    return 0
  fi
  if [ -n "$state" ]; then case "$p" in "$state"|"$state"/*) return 0 ;; esac; fi
  coord_scope "$p" && return 0
  case "$p" in "$own"|"$own"/*) ;; *) deny "write outside your own work dir $own: $p. Run one 'git worktree add' per Bash call, and spell every worktree path literally: a second add in the same command reads as a write outside the first, and a path built from a shell variable cannot be resolved here." ;; esac
  case "$p" in *"/.claude/"*|*/CLAUDE.md|*/.mcp.json)
    deny "the product repo is agentic-free (ADR-0001): $p" ;;
  esac
  # Issue #429: a dashboard RC clone is $WORK_DIR/rc-<key> and carries no task file, so `archetype` is empty and
  # nothing below constrains it. The session starts in `--permission-mode plan`, but the grill contract itself
  # tells the human to approve leaving plan mode (RcBriefBuilder) — and from then on every write inside the clone
  # would be permitted, product source included. An RC interview may end in documents, so it gets the same scope
  # as the architecture-docs carve-out and nothing more; state/ returned above. The standalone rc-worker clones to
  # $WORK_DIR/<key> without the prefix (rc-ctl.sh) and keeps its full-trust posture (ADR-0043).
  case "$task" in
    rc-*) docs_carveout "$p" && return 0
          deny "an RC session may only write docs/**, CONTEXT.md and README.md (issue #429): $p" ;;
  esac
  case "$archetype" in
    research|review)
      if [ "$archetype" = research ] && [ -n "$architecture_docs" ] && docs_carveout "$p"; then
        return 0
      fi
      deny "a $archetype task is read-only towards the product repo (block-$archetype): $p" ;;
  esac
}

check_status() {
  for v in $(printf '%s' "$1" | grep -oE 'status:[[:space:]\]*[A-Za-z_]+' | sed 's/.*:[[:space:]\]*//'); do
    case " $STATUS_ALLOWED " in
      *" $v "*) ;;
      *) deny "an agent may only write status $(printf '%s' "$STATUS_ALLOWED" | tr ' ' '|'), not '$v' (ADR-0009). Do not edit 'status:' in a task file by hand: run state-report.sh from the plugin's bin/ as 'state-report.sh --task <id> --set-status <status>', which writes the frontmatter and the commit as one judged write." ;;
    esac
  done
}

# `git push --force-with-lease[=<branch>[:<sha>]] [-u] origin <your own task branch>` is the only permitted rewrite
# of history (the rebase in `## Output` of the block-* skills). T-228 A4: the coordinator pushes the parent branch
# as `git -C <parent worktree> push …`, allowed only when this session owns the task of that worktree and the
# branch is its `branch:`. No other remote, no other ref (not even `HEAD`); anything extra is unknown, and denied.
fwl_allowed() {
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  [ "${1:-}" = git ] || return 1
  shift
  fwl_branch=$branch
  if [ "${1:-}" = -C ]; then
    [ -n "${2:-}" ] || return 1
    fwl_dir=$(abs_norm "$2")
    shift 2
    resolve_layout "$fwl_dir" "$WORK_DIR" && [ "$LO_POSTURE" = standalone ] && [ "$fwl_dir" = "$LO_OWN" ] \
      && owner_is_session "$LO_TASK" || return 1
    fwl_branch=$(task_field "$LO_TASK" branch)
    fwl_branch=${fwl_branch%%[ 	#]*}
  fi
  [ "${1:-}" = push ] || return 1
  shift
  [ -n "$fwl_branch" ] || deny "--force-with-lease: your own task branch cannot be determined from the task frontmatter"
  lease=0; remote=0; head=0
  for a in "$@"; do
    case "$a" in
      --force-with-lease|--force-with-lease="$fwl_branch") lease=1 ;;
      --force-with-lease="$fwl_branch":*)
        case "${a##*:}" in ''|*[!0-9a-f]*) return 1 ;; esac
        lease=1 ;;
      -u|--set-upstream) ;;
      origin) [ "$remote" = 0 ] || return 1; remote=1 ;;
      "$fwl_branch") [ "$head" = 0 ] || return 1; head=1 ;;
      *) return 1 ;;
    esac
  done
  [ "$lease" = 1 ] && [ "$remote" = 1 ] && [ "$head" = 1 ]
}

# T-228 Q4/Q17: a commit in the state clone names its paths. Without `--`, or with -a/--all, it also takes whatever
# another session left staged or modified there. T-228-06: the flags are read with quoted spans removed, the `-C`
# directory and the paths after `--` from the segment as written, so a quoted one still counts. T-228-07: the paths
# are the words after the first bare `--`, a quoted span one word, so a `--` inside the message is not one.
check_state_commit() { # <one command segment, quotes removed> <the segment as written>
  scseg=${2:-}
  scraw=$(printf '%s' "${2:-}" | tr -d '\042\047')
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  [ "${1:-}" = git ] || return 0
  shift
  scd=$cwd
  if [ "${1:-}" = -C ]; then
    shift
    scop=$(printf '%s' "$scraw" | awk '{ for (i = 1; i < NF; i++) if ($i == "-C") { print $(i + 1); exit } }')
    [ -n "$scop" ] || return 0
    [ "${1:-}" != "$scop" ] || shift
    case "$scop" in
      "~") scop=${HOME:-} ;;
      "~/"*) scop=${HOME:+$HOME/${scop#"~/"}} ;;
    esac
    scd=$(abs_norm "$scop")
  fi
  [ "${1:-}" = commit ] || return 0
  shift
  case "$scd" in "$WORK_DIR"/state|"$WORK_DIR"/state/*) ;; *) return 0 ;; esac
  for a in "$@"; do
    case "$a" in
      --)
        scpaths=$(printf '%s' "$scseg" | awk '{
          n = length($0); w = ""; q = ""; qd = 0; seen = 0
          for (i = 1; i <= n + 1; i++) {
            ch = i <= n ? substr($0, i, 1) : " "
            if (q != "") { if (ch == q) q = ""; else w = w ch; continue }
            if (ch == "\"" || ch == "\047") { q = ch; qd = 1; continue }
            if (ch == " " || ch == "\t") {
              if (seen && (w != "" || qd)) print w
              else if (w == "--" && !qd) seen = 1
              w = ""; qd = 0; continue
            }
            w = w ch
          }
        }')
        [ -n "$scpaths" ] || break
        set -f
        oIFS=$IFS; IFS=$NL
        for p in $scpaths; do
          case "$p" in
            :/|*/) sc_dir=1 ;;
            *) sc_dir=''; [ ! -d "$scd/$p" ] || sc_dir=1 ;;
          esac
          [ -z "$sc_dir" ] || deny "a commit in the state clone $WORK_DIR/state names files, not '$p': a directory, '.' or ':/' sweeps up another session's changes. 'git commit -m <message> -- <file>…'"
        done
        IFS=$oIFS
        set +f
        return 0 ;;
      --all|-[!-]*a*) deny "'git commit -a' in the state clone $WORK_DIR/state takes every modified file, including another session's: stage your own files and commit them by name, 'git commit -m <message> -- <path>…'" ;;
    esac
  done
  deny "a commit in the state clone $WORK_DIR/state names its paths: 'git commit -m <message> -- <path>…'. Without '--' it also commits whatever another session left staged there."
}

# ADR-0047: the session's state clone is read-only towards the state repo — `status`, the progress snapshot and the
# lines under `## Attempts` / `## Tool failures` are written by the dashboard, which is the only pusher. Every other
# git operation in the clone (pull, log, show, and a commit) stays allowed: new files still push themselves, because
# a research report, an ADR or memory proposal and a grilled plan have unique names and cannot conflict.

# the commits this push would carry: only when every one of their files is a new-file writer's is the push allowed
state_push_new_files_only() { # <state clone>
  sfiles=$(git -C "$1" diff --name-only '@{upstream}..HEAD' 2>/dev/null) || return 1
  [ -n "$sfiles" ] || return 1
  printf '%s\n' "$sfiles" | grep -Ev '(^|/)(research|proposals|plans)/' >/dev/null && return 1
  return 0
}

check_state_push() { # <one command segment>
  printf '%s' "$1" | grep -Eq '(^|[[:space:]])git(-guard)?([[:space:]]+[^[:space:]]+)*[[:space:]]push([[:space:]]|$)' \
    || return 0
  sdir=$(printf '%s' "$1" | sed -n 's/.*[[:space:]]-C[[:space:]][[:space:]]*\([^[:space:]]*\).*/\1/p' | head -n1)
  [ -n "$sdir" ] || sdir=$cwd
  # abs_norm collapses the `x/..` of `git -C ../state push`, so the product clone's sibling is recognised
  sdir=$(abs_norm "$sdir")
  sroot=''
  if [ -n "$state" ]; then case "$sdir" in "$state"|"$state"/*) sroot=$state ;; esac; fi
  # T-003: the standalone posture's state clone is $WORK_DIR/state, a sibling of the repo keys (ADR-0049), and
  # the cwd that pushes it names no task at all
  if [ -z "$sroot" ]; then
    case "$sdir" in "$WORK_DIR"/state|"$WORK_DIR"/state/*) sroot="$WORK_DIR/state" ;; esac
  fi
  # T-228-08: after a cd the guard cannot resolve, the push may run in the state clone, so it is judged as one
  # whenever that clone holds a commit to push
  if [ -z "$sroot" ] && [ -n "$cwd_lost" ]; then
    for sr in "$state" "$WORK_DIR/state"; do
      [ -n "$sr" ] && [ -d "$sr" ] || continue
      git -C "$sr" diff --quiet '@{upstream}..HEAD' 2>/dev/null && continue
      sroot=$sr; break
    done
  fi
  [ -n "$sroot" ] || return 0
  # ADR-0050: with no dashboard configured there is no other pusher — the state clone is the write path itself,
  # and denying it here would strand the local posture. With one, ADR-0047's rule stands unchanged.
  [ -n "${DASHBOARD_URL:-}" ] || return 0
  state_push_new_files_only "$sroot" && return 0
  deny "the state clone does not push (ADR-0047): the status, the progress snapshot and the '## Attempts' / '## Tool failures' lines are written by the dashboard. Run state-report.sh from the plugin's bin/ instead — it sends them through PATCH /api/tasks/<id>, and the Stop hook sends them for you at the end anyway. Only a new file of your own (a research report, an ADR or memory proposal, a plan) may still be committed and pushed from the state clone."
}

# Issue #308, point 1: the same implement-phase test lock the Edit/Write branch applies, reached from bash.
# `Write` semantics on purpose — a redirect that CREATES a test file is new coverage (issue #293, the CRAP loop),
# only rewriting one that already exists bends the tests-phase contract, exactly as for the Write tool.
# T-003: and the same product-clone rule, because a relative target is resolved against a cwd that may itself be
# the registered clone — `echo x > README.md` there writes into the human's own checkout exactly like the
# absolute spelling check_path already denies.
# A `..` in the path cannot be resolved safely here; check_path already denies those on the routes it sees.
bash_write_target() {
  t=$1
  [ -n "$t" ] || return 0
  case "$t" in *..*) return 0 ;; esac
  t=$(abs_norm "$t")
  check_product_clone "$t"
  check_test_lock Write "$t"
}

# Only unambiguous *write* forms. `sed -n 's/x/y/p' FooTests.cs`, `grep -r Assert FooTests.cs` and `cat FooTests.cs`
# read a test file and must stay allowed — a guard that strands legitimate sessions is worse than the hole it
# closes, and point 2 (the Stop backstop) is the net for everything this cannot tell apart.
# `patch -p1 < fix.diff` and `python -c` name no target on the command line and are deliberately not guessed at.
bash_in_place_write() { # <one command segment>
  s=$1
  if printf '%s' "$s" | grep -Eq '(^|[[:space:]])(sed|perl)[[:space:]]' \
     && printf '%s' "$s" | grep -Eq '[[:space:]](-[a-z]*i[a-z]*([.=][^[:space:]]*)?|--in-place([=][^[:space:]]*)?)([[:space:]]|$)'; then
    return 0
  fi
  if printf '%s' "$s" | grep -Eq '(^|[[:space:]])(patch|tee)([[:space:]]|$)'; then return 0; fi
  if printf '%s' "$s" | grep -Eq '(^|[[:space:]])git([[:space:]]+[^[:space:]]+)*[[:space:]](checkout|restore)([[:space:]]|$)'; then return 0; fi
  return 1
}

# 2026-09-07 lessons A3/A4: a heredoc body is data — a progress note saying `dotnet test ran green`, a line with
# `<id>` and a backtick (read as a redirect into a file named backtick), a python script quoting "status: ready" —
# and the scans below misread every one of them as a command. This drops the BODY lines: from the line after one
# carrying `<<[-]['"]TAG['"]` up to and including the TAG line (tab-indented or not); the heredoc line itself, and
# with it the redirect target it feeds, stays. A `<<<` here-string is not a heredoc and is left alone. One awk, run
# once per hook call and only when the command carries a `<<` at all.
strip_heredocs() { # <command>
  printf '%s\n' "$1" | awk '
    body { t = $0; sub(/^\t+/, "", t); if (t == tag) { body = 0 }; next }
    { print }
    match($0, /(^|[^<])<<-?[ \t]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*/) {
      tag = substr($0, RSTART, RLENGTH); sub(/^[^<]*<<-?[ \t]*["'"'"']?/, "", tag); body = 1 }'
}
# …except when the body is code or a status write: fed to a shell (`sh <<EOF` / `eval`) the body IS the command,
# and a heredoc redirected into a task file (`cat > …/tasks/T.md <<EOF`) is the status write check_status must
# still judge. In both the command is scanned as written.
heredoc_stripped() { # <command> — prints the command to scan
  case "$1" in *"<<"*) ;; *) printf '%s' "$1"; return 0 ;; esac
  # 2026-09-10: the task-file route is judged on the heredoc line alone — a body line quoting `cat > …/tasks/T.md`
  # (a skill doc, a task body under edit) is prose, and scanning that body as a command read its backticks and
  # arrows as redirects into the cwd.
  if printf '%s\n' "$1" | grep -F '<<' | grep -Eq '(^|[[:space:];&|(])(sh|bash|zsh|eval)([[:space:]]|$)' \
     || printf '%s\n' "$1" | grep -F '<<' | grep -Eq '(>>?[[:space:]]*|(^|[[:space:]])tee([[:space:]]+-[a-z]+)*[[:space:]]+)[^[:space:]"'"'"']*tasks/'; then
    printf '%s' "$1"; return 0
  fi
  strip_heredocs "$1"
}

# T-228 Q23: a segment ends at `;`, `|`, `&` and a line break, but only outside quotes: a `&&` inside a printf
# argument or a commit message is data. A quoted span that runs over several lines stays on one. T-228-06: with
# `lead`, each segment carries the separator before it, `a` for `&&`, `p` for `|`, `r` for `||`, `o` for any other
# and `-` for none.
split_segs() { # <command> [lead]
  printf '%s\n' "$1" | awk -v lead="${2:-}" '
    function emit() { if (seg != "") print (lead != "" ? code " " : "") seg; seg = "" }
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      n = length(s); q = ""; seg = ""; sep = ""; code = "-"
      for (i = 1; i <= n; i++) {
        ch = substr(s, i, 1)
        if (q != "") {
          if (ch == "\\" && q == "\"") { seg = seg ch substr(s, ++i, 1); continue }
          if (ch == q) q = ""
          seg = seg (ch == "\n" ? " " : ch); continue
        }
        if (ch == ";" || ch == "|" || ch == "&" || ch == "\n") { sep = sep ch; continue }
        if (sep != "") { emit(); code = (sep == "&&" ? "a" : (sep == "|" ? "p" : (sep == "||" ? "r" : "o"))); sep = "" }
        if (ch == "\\") { seg = seg ch substr(s, ++i, 1); continue }
        if (ch == "\047" || ch == "\"") q = ch
        seg = seg ch
      }
      emit()
    }'
}

unquoted() { # <text>
  printf '%s' "$1" | sed -E "s/'[^']*'|\"[^\"]*\"//g"
}

# T-228 Q22: `cd <abs>`, and `cd`, `cd ~`, `cd ~/x` through $HOME, name the cwd the later segments are judged
# against. A `cd` the guard cannot resolve (relative, `-`, a variable, `..`, a quoted path, a `)`) leaves it unknown.
# T-228-08: an allowlist, not a denylist. Only in the shape chain_shape accepts does a cd replace the cwd. In every
# other shape the cwd stays the hook's, every cd target joins cwd_alt, and a relative target is judged against all
# of them. An unresolvable cd turns the shape off for the rest of the command and keeps the hook cwd among the bases.
NL='
'
cwd_lost=''
cwd_alt=''
cd_plain=''
cd_reset() { cwd=$cwd0; cwd_lost=''; cwd_alt=''; cd_plain=$cd_plain0; }
alt_add() { [ -z "$1" ] || cwd_alt=${cwd_alt:+$cwd_alt$NL}$1; }

# the allowlisted shape: one or more leading `cd <path>` segments, then simple commands, every separator `&&` and a
# `|` only inside a later segment; no unquoted `(`, `)`, backtick, `;`, `||`, background `&` or line break, no word
# that moves the shell unseen, and no assignment prefixed to a cd
chain_shape() { # <the command, heredoc bodies removed> <its segments, each led by its separator code>
  cs=$(unquoted "$1")
  case "$cs" in *[\(\)\;\`]*|*'||'*|*"$NL"*) return 1 ;; esac
  case "$(printf '%s' "$cs" | sed 's/&&//g; s/[<>]&//g; s/&>//g')" in *'&'*) return 1 ;; esac
  printf '%s\n' "$2" | {
    lead=1 after=''
    while IFS= read -r line; do
      [ -z "$after" ] || [ "${line%% *}" = a ] || exit 1
      set -f
      # shellcheck disable=SC2046
      set -- $(unquoted "${line#* }")
      set +f
      for w in "$@"; do
        case "$w" in pushd|popd|builtin|command|eval|source|exec|CDPATH=*) exit 1 ;; esac
      done
      [ "${1:-}" != . ] || exit 1
      asg=''
      while [ $# -gt 0 ]; do case "$1" in *=*) asg=1; shift ;; *) break ;; esac; done
      after=''
      if [ "${1:-}" = cd ]; then
        [ -n "$lead" ] && [ -z "$asg" ] && [ $# -le 2 ] || exit 1
        after=1
      else
        lead=''
      fi
    done
  }
}

cd_track() { # <one command segment>
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  while [ $# -gt 0 ]; do case "$1" in *=*|builtin|command|eval|exec) shift ;; *) break ;; esac; done
  case "${1:-}" in
    cd) ;;
    pushd) [ $# -gt 1 ] || { cd_lose; return 0; } ;;
    popd) cd_lose; return 0 ;;
    *) return 0 ;;
  esac
  shift
  while [ $# -gt 0 ]; do
    case "$1" in -L|-P|-e|-@) shift ;; --) shift; break ;; *) break ;; esac
  done
  cd_to=${1:-"~"}
  case "$cd_to" in
    "~") cd_to=${HOME:-} ;;
    "~/"*) cd_to=${HOME:+$HOME/${cd_to#"~/"}} ;;
  esac
  case "$cd_to" in
    *..*|*'$'*|*'`'*|*\"*|*\'*|*')'*) cd_lose ;;
    /*|[A-Za-z]:/*)
      norm_into ct_to "$cd_to"
      if [ -n "$cd_plain" ]; then
        ct_real=$(cd -P -- "$ct_to" 2>/dev/null && pwd -P) || ct_real=$ct_to
        [ "$ct_real" = "$ct_to" ] || cd_unplain
      fi
      if [ -n "$cd_plain" ]; then cwd=$ct_to; else alt_add "$ct_to"; fi ;;
    *) cd_lose ;;
  esac
}
cd_lose() {
  cwd_lost=1
  cd_unplain
}
cd_unplain() {
  [ -n "$cd_plain" ] || return 0
  cd_plain=''
  [ "$cwd" = "$cwd0" ] || alt_add "$cwd0"
}

# T-228 D1: the reads a parent's owner may run in its blocks' worktrees, and a block on its own brief. T-228-06: a
# command substitution or a process substitution runs a command of its own, so it is never a read.
bash_read_only() { # <one command segment, quotes removed>
  case "$1" in *'$('*|*'`'*|*'<('*|*'>('*) return 1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  case "${1:-}" in
    cat|ls) return 0 ;;
    git)
      [ "${2:-}" = -C ] && [ -n "${3:-}" ] || return 1
      case "${4:-}" in log|diff|status|show) ;; *) return 1 ;; esac
      shift 4
      for a in "$@"; do case "$a" in --output*) return 1 ;; esac; done
      return 0 ;;
  esac
  return 1
}

# T-228-06: a check that reads $cwd runs again against cwd_alt when a cd may not have moved the shell
with_alt() { # <command…>
  "$@"
  [ -n "$cwd_alt" ] || return 0
  wa_cwd=$cwd; wa_rest=$cwd_alt
  while [ -n "$wa_rest" ]; do
    cwd=${wa_rest%%"$NL"*}
    case "$wa_rest" in *"$NL"*) wa_rest=${wa_rest#*"$NL"} ;; *) wa_rest='' ;; esac
    "$@"
  done
  cwd=$wa_cwd
}
inplace_tok() { case "$1" in */*) ;; *) [ -e "$cwd/$1" ] || return 0 ;; esac; bash_write_target "$1"; }
inplace_last() { [ -e "$cwd/$1" ] || bash_write_target "$1"; }
lost_inplace() { deny "a relative in-place write target after a 'cd' the guard cannot resolve (a relative path, '-', a variable or '..'): '$1'. Name the file by its absolute path, or 'cd' to an absolute one first (T-228)."; }

guard_bash() {
  c=$1
  [ -n "$c" ] || deny "empty command"
  if printf '%s' "$c" | grep -Eq '&&|\|\||;'; then
    DENY_FIX="$DENY_FIX Each segment of a chained command is judged on its own and a denial does not stop the next one, so run the commit and the push as separate Bash calls, with 'git log -1' between them."
  fi
  if printf '%s' "$c" | grep -Eq '<<|(^|[^=<>-])>|(^|[[:space:]])(sed|perl)[[:space:]][^;&|]*[[:space:]]-[a-z]*i([[:space:].=]|$)'; then
    DENY_FIX="$DENY_FIX Write a file with the Edit or Write tool instead of 'sed -i', a heredoc or a redirect: every bare token and heredoc body of a segment that writes is scanned here."
  fi
  if printf '%s' "$c" | grep -Eq '(^|[[:space:]])(glab[[:space:]]+mr|gh[[:space:]]+pr)[[:space:]]+create([[:space:]]|$)'; then
    DENY_FIX="$DENY_FIX Pass the description as a file, 'glab mr create --description-file <path>' or 'gh pr create --body-file <path>': an inline description is split on ';', '&&' and '|' and its pieces are judged as commands."
  fi
  # The MR title rule of skills/_shared/mr-description.md, on the path that does not go through mr-open.sh or
  # block-mr.sh: a forge command writing a title is held to the same mr_title_check those two apply, with the
  # cap of the repo the cwd belongs to. Every way a title reaches the forge is covered - `--title`, its short
  # `-t`, and the raw `glab api`/`gh api` field - because MR !412 was retitled by hand in the UI and the next
  # hand-written title is the one this has to catch. A title that is present but cannot be read out (a
  # variable, a substitution, a heredoc) is denied rather than passed: the guard cannot judge it, and the two
  # scripts can.
  mt_flag=0 mt_api=0
  if printf '%s' "$c" | grep -Eq '(^|[[:space:]])(glab[[:space:]]+mr|gh[[:space:]]+pr)[[:space:]]+(create|edit|update)([[:space:]]|$)'; then mt_flag=1; fi
  if printf '%s' "$c" | grep -Eq '(^|[[:space:]])(glab|gh)[[:space:]]+api([[:space:]]|$)'; then mt_api=1; fi
  # the first pattern that yields something wins; each one reads the last occurrence of the option, quoted
  # either around the whole `title=…` pair or around the value alone, and bare last
  mt_take() { # <ERE with one capturing group for the value, group 2>
    printf '%s' "$c" | sed -nE "s/$1/\\2/p"
  }
  mt_seen='' mt_title=''
  if [ "$mt_flag" = 1 ] && printf '%s' "$c" | grep -Eq -- '[[:space:]](--title|-t)([ =]|$)'; then
    mt_seen='--title'
    for mt_p in \
      '.*[[:space:]](--title|-t)[ =]"([^"]*)".*' \
      ".*[[:space:]](--title|-t)[ =]'([^']*)'.*" \
      '.*[[:space:]](--title|-t)[ =]([^ "'"'"']+).*'
    do
      mt_title=$(mt_take "$mt_p")
      [ -z "$mt_title" ] || break
    done
  elif [ "$mt_api" = 1 ] && printf '%s' "$c" | grep -Eq -- '[[:space:]](-f|--field|--raw-field)[ =]("|'"'"')?title='; then
    mt_seen='title='
    for mt_p in \
      '.*[[:space:]](-f|--field|--raw-field)[ =]title="([^"]*)".*' \
      '.*[[:space:]](-f|--field|--raw-field)[ =]"title=([^"]*)".*' \
      ".*[[:space:]](-f|--field|--raw-field)[ =]title='([^']*)'.*" \
      ".*[[:space:]](-f|--field|--raw-field)[ =]'title=([^']*)'.*" \
      '.*[[:space:]](-f|--field|--raw-field)[ =]title=([^ "'"'"']+).*'
    do
      mt_title=$(mt_take "$mt_p")
      [ -z "$mt_title" ] || break
    done
  fi
  if [ -n "$mt_seen" ]; then
    case "$mt_title" in ''|*'$'*|*'`'*) mt_title='' ;; esac
    if [ -z "$mt_title" ]; then
      deny "a forge command writes $mt_seen but the title cannot be checked here: open the MR through bin/mr-open.sh or bin/block-mr.sh, which take it from the task's # Goal line"
    fi
    # the registered key of this cwd, so the repo's own mr_title_max holds here too; the registry's `path:`
    # is matched as a prefix when the cwd is not the toplevel of the clone (a worktree under $WORK_DIR/<key>/)
    mt_key=$(repo_key_of_cwd "$cwd" 2>/dev/null || :)
    if [ -z "$mt_key" ] && [ -f "$WORK_DIR/state/repos.yml" ]; then
      mt_key=$(repo_clone_paths | while IFS="$(printf '\t')" read -r mt_k mt_p; do
          mt_p=$(norm_path "$mt_p")
          case "$cwd/" in "$mt_p"/*) printf '%s\n' "$mt_k"; break ;; esac
        done | head -n1)
    fi
    if [ -z "$mt_key" ] && [ -f "$WORK_DIR/state/repos.yml" ]; then
      case "$cwd/" in
        "$WORK_DIR"/*)
          mt_key=${cwd#"$WORK_DIR"/}; mt_key=${mt_key%%/*}
          grep -q "^$mt_key:" "$WORK_DIR/state/repos.yml" || mt_key='' ;;
      esac
    fi
    if ! reason=$(mr_title_check "$mt_title" "$mt_key"); then
      deny "the MR title '$mt_title' breaks the contract: $reason. It is the task's '# Goal' line, and bin/mr-open.sh or bin/block-mr.sh opens the MR with it rather than a hand-written title"
    fi
  fi
  # every scan below reads the command with its heredoc bodies removed (strip_heredocs); check_status at the end
  # reads the command as written, because a status write through a heredoc is exactly what it is there for.
  # T-228 Q23: the push checks read it too, so a python script quoting a push is not judged as one, and every
  # split into segments is split_segs, which ends a segment only outside quotes.
  sc=$(heredoc_stripped "$c")
  segs=$(split_segs "$sc")
  if printf '%s' "$sc" | grep -Eq 'git([[:space:]]+[^|;&]*)?[[:space:]]push([[:space:]][^|;&]*)?([[:space:]](-f|--force)([[:space:]]|$)|[[:space:]]\+)'; then
    deny "force push is forbidden (block-* skills, ADR-0012)"
  fi
  if printf '%s' "$sc" | grep -q -- '--force-with-lease'; then
    lsegs=$(printf '%s\n' "$segs" | grep -- '--force-with-lease')
    [ "$(printf '%s\n' "$lsegs" | wc -l | tr -d ' ')" = 1 ] \
      || deny "--force-with-lease may appear in a command at most once"
    fwl_allowed "$lsegs" \
      || deny "--force-with-lease is only allowed as 'git push --force-with-lease[=<branch>:<sha>] [-u] origin <branch>' on your own task branch${branch:+ $branch}, or as 'git -C <worktree of a task you own> push' on that task's branch (ADR-0012)"
  fi
  # T-228 Q22: the loops below that judge a path against the cwd walk the segments in order, and a `cd <abs>` moves
  # the cwd for the segments after it (cd_track, in the shape chain_shape accepts); each loop starts again from the
  # hook's cwd
  cwd0=$cwd
  ssegs=$(split_segs "$sc" lead)
  cd_plain0=''
  if chain_shape "$sc" "$ssegs"; then cd_plain0=1; fi
  cd_plain=$cd_plain0
  set -f
  oIFS=$IFS; IFS='
'
  # shellcheck disable=SC2086
  set -- $ssegs
  IFS=$oIFS
  set +f
  prev=''
  for line in "$@"; do
    seg=${line#* }
    cd_track "$prev"; prev=$seg
    with_alt check_state_push "$seg"
    with_alt check_state_commit "$(unquoted "$seg")" "$seg"
  done
  cd_reset
  # T-036: a `dotnet test` with no wall-clock cap hung a session until the watchdog stalled it — 20 minutes of
  # dead time and no trace of which test hung. The deterministic twin of _shared/test-budget.md: every command
  # segment that runs `dotnet test` carries a `timeout` in the same segment. A quoted mention is prose, not a run.
  if printf '%s' "$sc" | grep -Eq '(^|[[:space:]])dotnet[[:space:]]+test([[:space:]]|$)'; then
    set -f
    oIFS=$IFS; IFS='
'
    # shellcheck disable=SC2086
    set -- $segs
    IFS=$oIFS
    set +f
    for seg in "$@"; do
      plain=$(printf '%s' "$seg" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
      if printf '%s' "$plain" | grep -Eq '(^|[[:space:]])dotnet[[:space:]]+test([[:space:]]|$)' \
         && ! printf '%s' "$plain" | grep -Eq '(^|[[:space:]])timeout[[:space:]]'; then
        deny "a test run must carry a wall-clock cap (T-036, _shared/test-budget.md): run it as 'timeout 15m dotnet test …'. If the cap fires, retry once with '--blame-hang-timeout 10m --blame-hang-dump-type none' (VSTest) to name the hanging test, then self-report failed with the reason — never wait a hung run out."
      fi
    done
  fi
  # ponytail: bash is not parsed — only absolute paths on destructive commands, redirections
  # and any mention of a work dir (even someone else's, read-only) are checked
  for p in $(printf '%s' "$sc" \
    | grep -oE '(^|[;&|(]|[[:space:]])(rm|mv|cp|dd|tee|truncate|chmod|chown|ln|shred|mkfs[^[:space:]]*)[[:space:]][^|;&]*' \
    | grep -oE '(^|[[:space:]])/[^[:space:]"'"'"';|&)]+' || true); do
    check_path "$p"
    # issue #308: the paths the guard already extracts go through the test lock too. ponytail: this loop cannot
    # tell a source operand from a destination, so `cp /…/FooTests.cs /tmp/b` over-denies — `blocked` is the way out.
    bash_write_target "$p"
  done
  for p in $(printf '%s' "$sc" | grep -oE '>>?[[:space:]]*/[^[:space:]"'"'"';|&)]+' | sed 's/^>*[[:space:]]*//' || true); do
    check_path "$p"
  done
  # issue #358: a $WORK_DIR path quoted as data — a grep pattern, an echo, a commit message — is prose,
  # not a write, so the mention scan drops quoted spans before it looks. A segment that can write (a
  # redirect, a destructive command, an in-place editor) gets no such shield: there every mention is
  # checked, quotes stripped rather than honoured. An unquoted mention in a read segment stays denied —
  # bash is not parsed, and a read of a foreign work dir is forbidden anyway (issue #19).
  # T-228 D1: the reads of bash_read_only reach read_scope before check_path.
  set -f
  oIFS=$IFS; IFS='
'
  # shellcheck disable=SC2086
  set -- $segs
  IFS=$oIFS
  set +f
  for seg in "$@"; do
    ro=''
    if printf '%s' "$seg" | grep -Eq '>|(^|[[:space:](])(rm|mv|cp|dd|rsync|install|truncate|chmod|chown|ln|shred|mkfs[^[:space:]]*)([[:space:]]|$)' \
       || bash_in_place_write "$seg"; then
      scan=$(printf '%s' "$seg" | tr -d '\042\047')
    else
      scan=$(printf '%s' "$seg" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
      if bash_read_only "$(unquoted "$seg")"; then ro=1; fi
    fi
    for p in $(printf '%s' "$scan" | grep -oE "$WORK_RE[^[:space:]\"';|&)]+" || true); do
      if [ -n "$ro" ] && read_scope "$p"; then continue; fi
      check_path "$p"
    done
  done
  # issue #308: a redirection target is a write whether it is absolute or relative — `cat > src/FooTests.cs <<EOF`
  # and `echo x >> src/FooTests.cs` are the same bypass as `sed -i`. T-003: this ran only in the implement phase,
  # for the test lock alone, which left the relative form of a write into the registered clone (`echo x > README.md`
  # with the clone as cwd) seen by nothing at all — so it runs for every bash call now, and the clone rule runs
  # with it. check_path's reach over bash stays exactly as #19 drew it.
  # 2026-09-07 lesson A4: check_status used to fire on any `tasks/` anywhere in the command, which denied a
  # `grep -rl "status: ready" …/tasks/` — a read. It fires only when a write route (a redirect target, a `tee`
  # operand, an in-place editor's token) names a task file; the two loops below raise the flag as they go.
  # 2026-09-10: a `>` inside quotes (`x=>y` in a node -e script, `"a -> b"`, `--format="%h>%s"`, a grep pattern,
  # a PR body) is data, and one right after `=`, `-` or `<` is an arrow or `<>`, never a redirect — every one of
  # them was denied as a write into the cwd, the registered clone, on a read-only command. Quoted spans go first
  # (leftmost quote wins, so an apostrophe inside "…" stays inside it; a span may run over several lines), then
  # the unquoted targets are read off what is left, and a target quoted as a whole (`> "README.md"`) off the
  # command as written. A `$VAR/…` target is unknown here and resolving it against the cwd is a guess, not a rule.
  # T-228 Q22: read per segment, split_segs keeps a quoted span on one line, and after a `cd` the guard cannot
  # resolve a relative target is denied rather than joined onto a cwd that is no longer the shell's.
  status_write=''
  set -f
  oIFS=$IFS; IFS='
'
  # shellcheck disable=SC2086
  set -- $ssegs
  IFS=$oIFS
  set +f
  prev=''
  for line in "$@"; do
    seg=${line#* }
    cd_track "$prev"; prev=$seg
    case "$seg" in
      *'>'*)
        rtargets=$(unquoted "$seg" | grep -oE '(^|[^=<>-])>>?[[:space:]]*[^[:space:]"'"'"';|&<>()]+' | sed 's/^[^>]*>*[[:space:]]*//'
          printf '%s' "$seg" | grep -oE '(^|[^=<>-])>>?[[:space:]]*("[^"]+"|'"'"'[^'"'"']+'"'"')' | sed 's/^[^>]*>*[[:space:]]*//' | tr -d '\042\047')
        set -f
        for p in $rtargets; do
          case "$p" in \$*) continue ;; esac
          case "$p" in *tasks/*) status_write=1 ;; esac
          if [ -n "$cwd_lost" ]; then
            case "$p" in
              /*|[A-Za-z]:/*|"~"*) ;;
              *) deny "a relative write target after a 'cd' the guard cannot resolve (a relative path, '-', a variable or '..'): '$p'. Write to an absolute path, or 'cd' to an absolute one first (T-228)." ;;
            esac
          fi
          with_alt bash_write_target "$p"
        done
        set +f ;;
    esac
  done
  cd_reset
  # …and the in-place editors, per command segment so that a read in one segment is not blamed on a write in
  # another. Inside a write segment every path-like token is offered to the checks; an option (`-i`), a quoted
  # script (`'s|/tests/a|/tests/b|'`) or a backtick is skipped, and both checks ignore a path they have no rule for.
  # T-228 Q3: the tokens come from the segment with its quoted spans removed, so the pieces of a quoted script are
  # never offered, and a `$` target is skipped as the redirect loop skips one. T-228-06: the script operand of a
  # `sed -i`/`perl -i` without `-e` is skipped, quoted or not, and after a `cd` the guard cannot resolve, a relative
  # token is denied while an absolute one is judged as usual. T-228-07: there only a token with a `/` and the last
  # operand of `sed`/`perl` count as relative targets, never a command word.
  set -f
  oIFS=$IFS; IFS='
'
  # shellcheck disable=SC2086
  set -- $ssegs
  IFS=$oIFS
  set +f
  prev=''
  for line in "$@"; do
    seg=${line#* }
    cd_track "$prev"; prev=$seg
    bash_in_place_write "$seg" || continue
    useg=$(unquoted "$seg")
    pseg=$(printf '%s' "$seg" | sed -E "s/'[^']*'|\"[^\"]*\"/ @Q /g")
    script=1
    case " $pseg " in *" -e "*|*" --expression"*|*" -f "*) script='' ;; esac
    cmdseen=''
    set -f
    # shellcheck disable=SC2086
    for t in $pseg; do
      case "$t" in sed|perl) cmdseen=1; continue ;; -*) continue ;; esac
      if [ -n "$cmdseen" ] && [ -n "$script" ]; then script=''; continue; fi
      case "$t" in @Q|\$*|\`*|'') continue ;; esac
      if [ -n "$cwd_lost" ]; then
        case "$t" in
          /*|[A-Za-z]:/*|"~"*) ;;
          */*) lost_inplace "$t" ;;
        esac
      fi
      [ "$t" != . ] || continue
      case "$t" in *tasks/*) status_write=1 ;; esac
      # 2026-09-07 lesson A2: a bare word is a file only when it names one — `git restore --staged .` from the
      # registered clone was denied as a write into `<clone>/git`. A token with a `/` is a path; one without is
      # offered only when it exists in the cwd. `.` is the directory itself, and a `cd` earlier in the command may
      # have moved it — it is not judged here (the clone rule already denies every explicit spelling of the clone).
      with_alt inplace_tok "$t"
    done
    set +f
    # the last operand of `sed -i` or `perl -i` is its file, whether it exists yet or not
    lw=$(printf '%s' "$useg" | awk '/(^|[ \t])(sed|perl)[ \t]/ && NF > 1 { print $NF }')
    case "$lw" in
      -*|\$*|\`*|''|.|*/*) ;;
      *) [ -z "$cwd_lost" ] || lost_inplace "$lw"; with_alt inplace_last "$lw" ;;
    esac
  done
  cd_reset
  [ -z "$status_write" ] || check_status "$c"
}

load_task_context
stamp_test_base

case "$tool" in
  Bash)
    un cmd "$f_cmd"
    guard_bash "$cmd"
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    un p "$f_path"; check_path "$p"
    abs=$(abs_norm "$p")
    check_test_lock "$tool" "$abs"
    case "$abs" in */tasks/*)
      # ADR-0018/0035/0036: a triage session may create a file that does not exist yet and, on top of that, edit
      # exactly the one draft it has in its `## Context` — nothing else, and only to `status: triaged`
      if [ "$archetype" = triage ] && { { [ "$tool" = Write ] && [ ! -e "$abs" ]; } || { [ -n "$triage_target" ] && [ "$abs" = "$triage_target" ]; }; }; then
        STATUS_ALLOWED=triaged
      fi
      un newtext "$f_new"; check_status "$newtext"
      ;;
    esac
    ;;
  *)
    deny "unknown tool '$tool' — the policy guard does not know its write paths"
    ;;
esac
exit 0
