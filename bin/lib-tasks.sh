#!/bin/sh
# Sourced by the hooks and the task scripts, never run: which tasks a session owns, one frontmatter field of a
# task file, one string field of the hook stdin, and which registered repo a cwd belongs to. task_of /
# owned_task_ids read the state clone the caller put in $state, the way self-report-check.sh and
# session-stats.sh always did.

# the permissions.allow rules factory-init.sh writes and factory-doctor.sh checks, one per line: a step session
# reads the factory root and the plugin, edits the state clone and runs the plugin scripts without a dialog,
# which a model that cannot run in auto mode (Haiku 4.5) needs
factory_allow_rules() { # <work dir> <plugin root>
  printf '%s\n' "Read(/$1/**)" "Read(/$2/**)" "Edit(/$1/state/**)" "Bash(sh $2/bin/*)" "Bash($2/bin/*)"
}

# every task file of $state, one path per line: the live ones under repos/<key>/tasks/, and with --all also the
# archived ones under repos/<key>/archive/<YYYY-MM>/tasks/ (state-archive.sh moves a finished parent there).
# Without a key every repo. Every reader that used to glob repos/*/tasks goes through this.
task_files() { # [--all] [<key>]
  tf_all=''
  if [ "${1:-}" = --all ]; then tf_all=1; shift; fi
  tf_k=${1:-*}
  for tf_f in "$state"/repos/$tf_k/tasks/*.md; do [ -f "$tf_f" ] || continue; printf '%s\n' "$tf_f"; done
  [ -n "$tf_all" ] || return 0
  for tf_f in "$state"/repos/$tf_k/archive/*/tasks/*.md; do [ -f "$tf_f" ] || continue; printf '%s\n' "$tf_f"; done
}

# the file of a task, live first, then the archive. By the file name first (`<id>.md`, `<id>-*.md`), and only when
# no name matches by grepping every `id:` line. A name is only a hint: with hierarchical ids a child
# `T-005-01-…` also matches `T-005-*` and sorts before its parent `T-005-…` (`0` < a letter), so the `id:` line of
# a candidate decides. Prints nothing, and still returns 0, when no file holds the id.
task_of() { # <id>
  task_of_in "$1" "$state"/repos/*/tasks && return 0
  task_of_in "$1" "$state"/repos/*/archive/*/tasks || :
}
task_of_in() { # <id> <tasks dir>...
  to_id=$1
  shift
  for to_d in "$@"; do
    for to_f in "$to_d/$to_id.md" "$to_d/$to_id"-*.md; do
      [ -f "$to_f" ] && grep -qx "id: $to_id" "$to_f" && { printf '%s\n' "$to_f"; return 0; }
    done
  done
  to_f=$(for to_d in "$@"; do grep -lx "id: $to_id" "$to_d"/*.md 2>/dev/null; done | head -n1)
  [ -n "$to_f" ] && printf '%s\n' "$to_f"
}

# frontmatter fields of one task file, one value per line in the order asked, an empty line for a field that is
# not there, from one awk instead of three processes per field. Only the frontmatter is read (a body line
# `status: …` is no field); a ` # comment` is dropped as setf and task-new.sh drop it, a `#` inside a value (a
# url anchor) stays.
task_fields() { # <file> <field>...
  tfs_f=$1
  shift
  [ -f "$tfs_f" ] || tfs_f=/dev/null
  awk -v want="$*" '
    BEGIN { n = split(want, k, " ") }
    NR == 1 && /^---[ \t\r]*$/ { fm = 1; next }
    fm && /^---[ \t\r]*$/ { exit }
    !fm { exit }
    {
      c = index($0, ":"); if (c < 2 || $0 ~ /^[ \t#]/) next
      name = substr($0, 1, c - 1); if (name in v) next
      val = substr($0, c + 1); sub(/[ \t]+#.*$/, "", val); sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
      v[name] = val
    }
    END { for (i = 1; i <= n; i++) print v[k[i]] }' "$tfs_f"
}

# one field of the repos.yml line of a repo in $state (ADR-0013 revision): `<key>: {url: …, default_branch: …,
# path: …}`, written by factory-add-repo.sh, in the flat or the indented spelling
yml_field() { # <key> <field>
  [ -f "$state/repos.yml" ] || return 0
  awk -v want="$1" -v field="$2" '
    /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
    key == want && match($0, field "[ \t]*:[ \t]*") {
      v = substr($0, RSTART + RLENGTH)
      sub(/[ \t]*[,}].*$/, "", v); sub(/[ \t]+#.*$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      if (v != "") { print v; exit }
    }' "$state/repos.yml"
}

# the id alias of a repo, `alias:` in its repos.yml entry: 2 to 4 uppercase letters, which make its new ids
# T-<ALIAS>-<n>. Prints nothing for a repo without one (it keeps the legacy T-<n> ids), and nothing with status 1
# when the value is no alias, so a writer can refuse instead of silently falling back to a legacy id.
repo_alias() { # <key>
  ra_v=$(yml_field "$1" alias)
  case "$ra_v" in
    '') return 0 ;;
    [A-Z][A-Z]|[A-Z][A-Z][A-Z]|[A-Z][A-Z][A-Z][A-Z]) printf '%s\n' "$ra_v" ;;
    *) return 1 ;;
  esac
}

# the plan slug of a task on stdin: decompose names `repos/<key>/plans/<slug>-plan-ready.md` in its `## Context`
plan_slug() { grep -oE 'plans/[A-Za-z0-9_.-]+-plan-ready\.md' | head -n1 | sed 's|^plans/||; s|-plan-ready\.md$||'; }

# a quick-lane task (skills/factory/references/solve-quick.md) has no grilled plan to hash, so its verdict says
# `scope: quick` and is read by the task id instead of by a plan slug
quick_verdict() { # <verdict file>
  [ -f "$1" ] || return 1
  [ "$(sed -n 's/^scope:[[:space:]]*//p' "$1" | head -n1)" = quick ] || return 1
  case "$(sed -n 's/^verdict:[[:space:]]*//p' "$1" | head -n1)" in aligned|overridden-by-human) return 0 ;; esac
  return 1
}

# the architect rule for a task write in $state, shared by architect-gate.sh's Write branch and every
# block write of task-new.sh. The product is the registered clone at the repos.yml `path:` of <key>; without
# docs/architecture/ there it passes (plan, decision 6). A valid verdict is `aligned` or `overridden-by-human`
# whose plan_hash is the current hash of its plan file, a mismatch counting as no verdict; only the verdict of the
# plan the task names is read. Returns 0 to pass, 1 with the reason on stdout, and 2 with a warning on stdout when
# the clone, the slug or a sha256 tool cannot be resolved: deny on positive evidence only, so a forgotten check is
# blocked and an unrelated flow never is.
architect_verdict() { # <key> <plan slug> <task id or empty>
  av_clone=$(yml_field "$1" path)
  if [ -z "$av_clone" ] || [ ! -d "$av_clone" ]; then
    printf "the registered clone of '%s' (repos.yml path:) is not on disk, so there is nothing to check\n" "$1"
    return 2
  fi
  [ -d "$av_clone/docs/architecture" ] || return 0
  if command -v sha256sum >/dev/null 2>&1; then av_sum='sha256sum'
  elif command -v shasum >/dev/null 2>&1; then av_sum='shasum -a 256'
  else printf '%s\n' 'no sha256 tool, so the plan hash of the verdict cannot be recomputed'; return 2; fi
  if [ -n "$3" ] && quick_verdict "$state/repos/$1/verdicts/$3.md"; then return 0; fi
  if [ -z "$2" ]; then
    printf "the task for '%s' names no plans/<slug>-plan-ready.md, so its verdict cannot be found\n" "$1"
    return 2
  fi
  av_f="$state/repos/$1/verdicts/$2.md"
  quick_verdict "$av_f" && return 0
  av_why="repos/$1/verdicts/$2.md, the verdict of the plan this task names, is missing"
  if [ -f "$av_f" ]; then
    av_v=$(sed -n 's/^verdict:[[:space:]]*//p' "$av_f" | head -n1)
    av_plan=$(sed -n 's/^plan:[[:space:]]*//p' "$av_f" | head -n1)
    av_want=$(sed -n 's/^plan_hash:[[:space:]]*//p' "$av_f" | head -n1)
    case "$av_plan" in /*) av_pf=$av_plan ;; *) av_pf="$state/$av_plan" ;; esac
    case "$av_v" in
      aligned|overridden-by-human)
        if [ -z "$av_plan" ] || [ -z "$av_want" ]; then
          av_why="$2.md has no plan/plan_hash"
        elif [ ! -f "$av_pf" ]; then
          av_why="the plan '$av_plan' of $2.md is missing"
        elif [ "$($av_sum "$av_pf" | cut -d' ' -f1)" != "$av_want" ]; then
          av_why="the plan_hash in $2.md does not match '$av_plan'"
        else
          return 0
        fi
        ;;
      *) av_why="the verdict in $2.md is '${av_v:-unreadable}'" ;;
    esac
  fi
  printf "the product repo '%s' has docs/architecture/, so a task for '%s' may only be written on an architect verdict: %s. Run the architect-review skill (plan-check on the plan, cut-check on the task drafts), let the human decide on the findings, and write the verdict per its verdict contract; a plan edited after the review has to be reviewed again.\n" \
    "$av_clone" "$1" "$av_why"
  return 1
}

# the tasks whose `owner:` ends in this session's id, `factory@<host>:<session_id>`, the whole id after the
# last colon (ADR-0050); one id per line, sorted
owned_task_ids() { # <session id>
  esc=$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g')
  task_files | xargs -r grep -l "^owner:[[:space:]]*[^[:space:]]*:$esc[[:space:]]*\$" 2>/dev/null \
    | xargs -r sed -n 's/^id:[[:space:]]*//p' 2>/dev/null | sed 's/[[:space:]]*#.*//' | sort -u | sort_ids
}

# a block that runs as one implement agent with red-first TDD inside, instead of a tests phase and an implement
# phase: green, or yellow at complexity low. spawn-plan.sh, solve-next.sh and block-brief.sh decide the phase
# by this one rule.
single_phase() { # <tier> <complexity>
  [ "$1" = green ] || { [ "$1" = yellow ] && [ "$2" = low ]; }
}

# one frontmatter field of a task file, rewritten in place: the line is replaced when the key is already there
# (a trailing ` # comment` kept) and inserted just above the closing `---` when it is not. T-007 review: a
# `sed -i 's/^owner:.*/…/'` is a silent no-op on a task whose frontmatter carries no `owner:` line at all, so
# both writers of a task field, task-done.sh and state-report.sh, go through this one helper.
setf() { # <file> <key> <value>
  node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const [k,v]=process.argv.slice(1);const L=s.replace(/\r\n/g,"\n").split("\n");let end=-1;
  for(let i=1;i<L.length;i++)if(L[i].trimEnd()==="---"){end=i;break}
  if(end<0){process.stdout.write(s);return}
  for(let i=1;i<end;i++){const c=L[i].indexOf(":");if(c<0||/^\s/.test(L[i]))continue;const n=L[i].slice(0,c);if(n.trim()!==k)continue;
    const cm=L[i].slice(c+1).split(" #");L[i]=cm.length>1?`${n}: ${v} #${cm.slice(1).join(" #")}`:`${n}: ${v}`;process.stdout.write(L.join("\n"));return}
  L.splice(end,0,`${k}: ${v}`);process.stdout.write(L.join("\n"))})' "$2" "$3" < "$1" > "$1.tmp" && mv -f "$1.tmp" "$1"
}

# one commit in a state clone, scoped to the paths it is given, the three local writers (task-new.sh,
# task-approve.sh, state-report.sh) commit exactly the files they wrote and never whatever else the clone had
# lying around. The identity fallback is for a worker image with no git identity configured; nothing to commit
# is success, not a failure. Returns non-zero when git refuses, and the caller maps that to its own exit code.
state_commit() { # <state> <message> [paths…]
  sc_state=$1
  sc_msg=$2
  shift 2
  git -C "$sc_state" add -- "$@" || return 1
  if git -C "$sc_state" diff --cached --quiet -- "$@"; then return 0; fi
  if [ -n "$(git -C "$sc_state" config user.email || :)" ]; then
    git -C "$sc_state" commit -q -m "$sc_msg" -- "$@"
  else
    git -C "$sc_state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$sc_msg" -- "$@"
  fi
}

# E3 (2026-09-07): two solve sessions in one standalone state clone reported at the same time, and git's index
# lock is not a transaction, one report's `add` rode in the other's commit. The whole critical section of
# state-report.sh (read the committed status, write, commit, push) runs under one lock per state clone: flock on
# <git-dir>/factory-state.lock where flock exists, otherwise a mkdir spin on <git-dir>/factory-state.lockdir with
# the holder's pid and start time inside, taken over once it is 120 s old (a session that died mid-report).
# STATE_LOCK_WAIT (default 30) is the wait in seconds. Returns 1 on a timeout, 2 when the lock path cannot be made;
# state_unlock is safe to call when nothing is held, so a caller can hang it on `trap … EXIT`.
STATE_LOCK_HELD=''
state_lock() { # <state>
  sl_gd=$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null) || sl_gd="$1/.git"
  [ -d "$sl_gd" ] || return 2
  sl_wait=${STATE_LOCK_WAIT:-30}
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$sl_gd/factory-state.lock" || return 2
    flock -w "$sl_wait" 9 || { exec 9>&-; return 1; }
    STATE_LOCK_HELD=fd
    return 0
  fi
  sl_dir="$sl_gd/factory-state.lockdir"
  sl_n=0
  until mkdir "$sl_dir" 2>/dev/null; do
    sl_since=$(cat "$sl_dir/since" 2>/dev/null || :)
    case "$sl_since" in *[!0-9]*) sl_since='' ;; esac
    if [ -n "$sl_since" ] && [ $(( $(date +%s) - sl_since )) -ge 120 ]; then rm -rf "$sl_dir"; continue; fi
    sl_n=$((sl_n + 1))
    [ "$sl_n" -lt "$sl_wait" ] || return 1
    sleep 1
  done
  printf '%s\n' "$$" > "$sl_dir/pid"
  date +%s > "$sl_dir/since"
  STATE_LOCK_HELD=$sl_dir
}
state_unlock() {
  case "$STATE_LOCK_HELD" in
    '') ;;
    fd) exec 9>&- ;;
    *) rm -rf "$STATE_LOCK_HELD" ;;
  esac
  STATE_LOCK_HELD=''
}

# The one write path of a state clone for files already written: lock, add, commit the named paths, unlock, and
# no push (state-push.sh publishes in the background, never under this lock). Returns state_lock's 1 (timeout) or
# 2 (no lock path), and 3 when git refuses the commit. A caller that already holds the lock, because it picked an
# id inside it, gets the commit alone and keeps its lock.
state_write() { # <state> <message> <path>...
  if [ -n "$STATE_LOCK_HELD" ]; then state_commit "$@" || return 3; return 0; fi
  state_lock "$1" || return $?
  sw_rc=0
  state_commit "$@" || sw_rc=3
  state_unlock
  return "$sw_rc"
}

# one flat string field of the hook stdin (session_id, cwd, transcript_path) without a JSON parser; a Windows
# path arrives with `\\` and possibly `\/`, both unescaped here
hook_field() { # <json> <field>
  printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's/\\\\/\\/g; s/\\\//\//g'
}

# a path the way both sides of a comparison see it: forward slashes, no trailing slash, a lower-case drive letter
# and `x/..` collapsed. T-003: a Windows path is what makes it necessary, `D:\src\repo`, `D:/src/repo` and
# `d:/src/repo/` are one directory, and a comparison that spells them differently lets through the write it meant
# to deny. Every step runs only when there is something to do, so an ordinary POSIX path spawns no process.
norm_path() {
  n=$1
  case "$n" in *\\*) n=$(printf '%s' "$n" | tr '\\' '/') ;; esac
  while :; do case "$n" in ?*/) n=${n%/} ;; *) break ;; esac; done
  case "$n" in
    *..*) while :; do
            nq=$(printf '%s' "$n" | sed -E 's#/[^/]+/\.\.(/|$)#\1#')
            [ "$nq" = "$n" ] && break
            n=$nq
          done ;;
  esac
  case "$n" in [A-Z]:/*|[A-Z]:) n=$(printf '%s' "$n" | cut -c1 | tr '[:upper:]' '[:lower:]')${n#?} ;; esac
  printf '%s' "$n"
}

# norm_path into a variable, skipping the subshell for a path already in that spelling, a command substitution
# would fork exactly the process the cases inside norm_path avoid.
norm_into() { # <variable name> <path>
  case "$2" in
    *\\*|[A-Za-z]:*|*..*|?*/) eval "$1=\$(norm_path \"\$2\")" ;;
    *) eval "$1=\$2" ;;
  esac
}

# T-003: the one layout rule the guard, the Stop hook and session-stats share: the standalone
# <root>/<key>/<task-id>/… (ADR-0049), where <task-id> is a parent id (a session worktree) or a block id (a block
# worktree). Given a path (the guard's write target) or a cwd (a hook) plus the work root, it sets
#   LO_POSTURE  standalone
#   LO_TASK     the task id
#   LO_OWN      the session's work dir LO_STATE  the state clone   LO_STAMP  the per-session stamp directory
# and returns 1, setting nothing, for every path that is not inside such a task worktree.
is_task_id() { is_parent_id "$1" || is_block_id "$1"; }

# two parent grammars side by side: the legacy `T-<n>` with three or more digits, and `T-<ALIAS>-<n>` with the
# repo's 2 to 4 uppercase letters from repos.yml and one or more digits. A repo key is lowercase, so neither
# grammar reads a key as an id, and a step unit `<parent>-<step>` still strips back to its parent.
is_parent_id() { # <id>
  case "$1" in
    T-[A-Z][A-Z]-*|T-[A-Z][A-Z][A-Z]-*|T-[A-Z][A-Z][A-Z][A-Z]-*) ip_n=${1#T-*-} ;;
    T-*) ip_n=${1#T-}; [ "${#ip_n}" -ge 3 ] || return 1 ;;
    *) return 1 ;;
  esac
  case "$ip_n" in ''|*[!0-9]*) return 1 ;; esac
}

is_block_id() { # <id>
  is_parent_id "${1%-*}" || return 1
  case "${1##*-}" in [0-9][0-9]*) ;; *) return 1 ;; esac
  case "${1##*-}" in *[!0-9]*) return 1 ;; esac
}

is_block_of() { # <parent> <id>
  is_block_id "$2" && [ "${2%-*}" = "$1" ]
}

# lines ordered by the task id in their first word: legacy ids first, then the alias ids by alias (bytewise), then
# the parent number, then the block number with a parent before its blocks, the whole line breaking a tie.
# Duplicates stay; a caller wanting unique lines runs sort -u.
sort_ids() {
  awk '{ p = $1; sub(/^T-/, "", p); g = 0; a = ""; b = 0
         if (match(p, /^[A-Z]+-/)) { g = 1; a = substr(p, 1, RLENGTH - 1); p = substr(p, RLENGTH + 1) }
         if (i = index(p, "-")) { b = substr(p, i + 1) + 1; p = substr(p, 1, i - 1) }
         print g "\t" a "\t" p "\t" b "\t" $0 }' \
    | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2 -k3,3n -k4,4n -k5 | cut -f5-
}

resolve_layout() { # <path> <work root>
  LO_POSTURE=''; LO_TASK=''; LO_OWN=''; LO_STATE=''; LO_STAMP=''
  [ -n "${2:-}" ] || return 1
  # T-003: both sides in the one spelling, so that a Windows path and a work root written the other way round
  # (or with a trailing slash) still compare as the same directory
  norm_into lo_p "$1"; norm_into lo_root "$2"
  case "$lo_p" in "$lo_root"/?*) lo_rest=${lo_p#"$lo_root"/} ;; *) return 1 ;; esac
  lo_s1=${lo_rest%%/*}
  lo_s2=${lo_rest#*/}
  if [ "$lo_s2" = "$lo_rest" ]; then lo_s2=''; else lo_s2=${lo_s2%%/*}; fi
  [ -n "$lo_s2" ] && is_task_id "$lo_s2" && ! is_task_id "$lo_s1" || return 1
  LO_POSTURE=standalone; LO_TASK=$lo_s2
  LO_OWN="$lo_root/$lo_s1/$lo_s2"; LO_STATE="$lo_root/state"; LO_STAMP="$lo_root/$lo_s1/.harness/$lo_s2"
}

# the same rule for a hook, which is handed no target path: the work root is $WORK_DIR when the cwd is under it,
# and otherwise the cwd's own two trailing segments, a standalone session's environment need not carry WORK_DIR.
resolve_cwd_layout() { # <cwd>
  resolve_layout "$1" "${WORK_DIR:-}" && return 0
  lo_d=${1%/*}
  resolve_layout "$1" "${lo_d%/*}"
}

# the state clone of a session, the one rule state-report.sh, self-report-check.sh and session-stats.sh share:
# the sibling `../state` of the product clone when that is a clone itself, the standalone layout's $WORK_DIR/state
# when the cwd is a work dir of it (ADR-0049), and otherwise the cwd, which is where a triage session sits
# (ADR-0018). `../state` first: a sibling state clone (ADR-0018) wins over the standalone rule.
resolve_state_dir() { # <cwd>
  if [ -d "$1/../state/.git" ]; then printf '%s' ../state; return 0; fi
  if resolve_cwd_layout "$1" && [ "$LO_POSTURE" = standalone ]; then printf '%s' "$LO_STATE"; return 0; fi
  if in_registered_clone "$1" >/dev/null; then printf '%s' "$WORK_DIR/state"; return 0; fi
  printf '%s' .
}

# why: a factory coordinator (ADR-0049) runs in the registered clone itself, outside $WORK_DIR, where neither the
# sibling `../state` nor the standalone layout resolves and the cwd is no state clone either. Without
# this case the Stop chain and the PreCompact hook look for its tasks under the product clone and find none.
# Prints the registry key and returns 0 only when $WORK_DIR/state is a clone as well.
in_registered_clone() { # <cwd>
  [ -d "${WORK_DIR:-}/state/.git" ] || return 1
  rc_key=$(repo_key_of_cwd "$1")
  [ -n "$rc_key" ] || return 1
  printf '%s' "$rc_key"
}

# the layout of a session that is reporting for a known task: resolve_cwd_layout's standalone answer where the cwd
# is a work dir under $WORK_DIR, and otherwise the coordinator's own standalone posture, whose work dir is the
# registered clone, whose state clone is $WORK_DIR/state and whose stamps sit in $WORK_DIR/<key>/.harness/<task-id>/,
# the same stamp directory the task's own session would use. It falls back to resolve_cwd_layout, so every
# posture the resolver already reported stays what it was.
resolve_session_layout() { # <cwd> <task id>
  resolve_cwd_layout "$1" && [ "$LO_POSTURE" = standalone ] && return 0
  if is_task_id "${2:-}" && rs_key=$(in_registered_clone "$1"); then
    rs_top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || rs_top=$1
    LO_POSTURE=standalone; LO_TASK=$2
    LO_OWN=$(norm_path "$rs_top"); LO_STATE="$WORK_DIR/state"; LO_STAMP="$WORK_DIR/$rs_key/.harness/$2"
    return 0
  fi
  resolve_cwd_layout "$1"
}

# every clone registered with a `path:` in $WORK_DIR/state/repos.yml, one `<key><TAB><path>` per line (ADR-0013
# revision; T-006 writes it, the readers do nothing without it)
repo_clone_paths() {
  [ -f "${WORK_DIR:-}/state/repos.yml" ] || return 0
  awk '
    /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
    /path:/ && key != "" {
      p = $0; sub(/.*path:[ \t]*/, "", p); sub(/[ \t]*[,}].*$/, "", p); sub(/[ \t]+#.*$/, "", p)
      gsub(/^["'"'"']|["'"'"']$/, "", p); if (p != "") print key "\t" p
    }' "$WORK_DIR/state/repos.yml"
}

# the key in $WORK_DIR/state/repos.yml whose `path:` is the clone this cwd is in, its toplevel, or the main
# clone when the cwd is a worktree made from it (ADR-0049). Prints nothing when there is no registry or no match.
repo_key_of_cwd() { # <cwd>
  [ -f "${WORK_DIR:-}/state/repos.yml" ] || return 0
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=''
  clone=''
  case "$common" in */.git) clone=$(norm_path "${common%/.git}") ;; esac
  top=$(norm_path "$top")
  repo_clone_paths | while IFS="$(printf '\t')" read -r key p; do
    p=$(norm_path "$p")
    if [ "$p" = "$top" ] || { [ -n "$clone" ] && [ "$p" = "$clone" ]; }; then printf '%s\n' "$key"; break; fi
  done
}

# true when the cwd's own toplevel is a `path:` in $WORK_DIR/state/repos.yml: repo_key_of_cwd without its
# git-common-dir match, so a worktree made from a registered clone is not one.
is_registered_top() { # <cwd>
  irt_top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  irt_top=$(norm_path "$irt_top")
  repo_clone_paths | while IFS="$(printf '\t')" read -r irt_key irt_p; do
    [ "$(norm_path "$irt_p")" = "$irt_top" ] && printf '%s\n' "$irt_key"
  done | grep -q .
}

# the state clone whose repos.yml the title cap is read from: an explicit $STATE_DIR, the caller's own `$state`
# (every task script resolves one before it reads a task), the standalone $WORK_DIR/state, and the cwd's layout
# last - the same order and the same resolver solve-next.sh and decompose.sh use for their own --state default.
mr_title_state() { # -> the state dir on stdout, or nothing
  if [ -n "${STATE_DIR:-}" ] && [ -f "$STATE_DIR/repos.yml" ]; then printf '%s' "$STATE_DIR"; return 0; fi
  if [ -n "${state:-}" ] && [ -f "$state/repos.yml" ]; then printf '%s' "$state"; return 0; fi
  if [ -n "${WORK_DIR:-}" ] && [ -f "$WORK_DIR/state/repos.yml" ]; then printf '%s' "$WORK_DIR/state"; return 0; fi
  mts_d=$(resolve_state_dir "$(pwd)")
  case "$mts_d" in /*|[A-Za-z]:/*) ;; *) mts_d="$(pwd)/$mts_d" ;; esac
  [ -f "$mts_d/repos.yml" ] || return 0
  printf '%s' "$mts_d"
}

# E (2026-09-22, MR !412): the plugin capped the title at 130, the product repo's CI ran commitlint with
# @commitlint/config-conventional, whose `header-max-length` is 100 - a 113-character title passed here and
# failed there, and a human retitled in the forge UI. The cap is per repo now: `mr_title_max:` in the entry
# repos.yml holds for that key (factory-add-repo.sh writes it when it finds such a lint), and 100 otherwise,
# which is what config-conventional enforces out of the box. The same awk as repo_clone_paths, so a flow
# entry (`key: {…, mr_title_max: 130}`) and a block entry read alike.
mr_title_limit() { # <repo key> -> the cap on stdout, 100 when the registry says nothing
  mtl_state=$(mr_title_state)
  mtl_n=''
  if [ -n "$mtl_state" ] && [ -n "${1:-}" ]; then
    mtl_n=$(awk -v want="$1" '
      /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
      /mr_title_max:/ && key == want {
        v = $0; sub(/.*mr_title_max:[ \t]*/, "", v); sub(/[ \t]*[,}].*$/, "", v); sub(/[ \t]+#.*$/, "", v)
        gsub(/^["'"'"']|["'"'"']$/, "", v)
        if (v ~ /^[0-9]+$/ && v + 0 > 0) { print v; exit }
      }' "$mtl_state/repos.yml")
  fi
  case "${mtl_n:-}" in ''|*[!0-9]*) mtl_n=100 ;; esac
  printf '%s' "$mtl_n"
}

# the length of a title in characters, not bytes: a scope or a subject with an accent or a dash is one
# character per glyph to commitlint and to the forge, and `wc -m` only agrees in a UTF-8 locale. A machine
# without C.UTF-8 falls back to a plain `wc -m`, which is the old behaviour rather than a refusal.
mr_title_chars() { # <title> -> the character count on stdout
  if [ "$(printf '\303\251' | LC_ALL=C.UTF-8 wc -m 2>/dev/null | tr -d '[:space:]')" = 1 ]; then
    printf '%s' "$1" | LC_ALL=C.UTF-8 wc -m | tr -d '[:space:]'
  else
    printf '%s' "$1" | wc -m | tr -d '[:space:]'
  fi
}

# The MR title is the task's `# Goal` line, and the forge takes it as written: Conventional Commits
# (`type(scope): subject`) so the release tooling can read the semver bump off it, and at most the repo's
# `mr_title_max` characters (default 100) so the product repo's own title lint cannot refuse what the factory
# opened. Both MR scripts check it before they call the forge, and task-new.sh, decompose.sh and
# task-approve.sh check the `# Goal` line that becomes the title, so a goal that cannot be a title is a task
# defect caught while the task is being authored and not a bad title on the forge.
mr_title_check() { # <title> [<repo key>] -> 0, or the reason on stdout and 1
  cap=$(mr_title_limit "${2:-}")
  n=$(mr_title_chars "$1")
  if [ "$n" -gt "$cap" ]; then
    printf 'the title is %s characters and the cap is %s (repo %s: mr_title_max, default 100 from commitlint config-conventional)\n' \
      "$n" "$cap" "${2:--}"
    return 1
  fi
  if printf '%s' "$1" | grep -Eq '^(feat|fix|chore|docs|refactor|test|perf|build|ci)(\([a-z0-9._/-]+\))?!?: .+'; then
    return 0
  fi
  printf '%s\n' 'the title is not Conventional Commits; write it as `type(scope): subject` with type one of feat, fix, chore, docs, refactor, test, perf, build, ci'
  return 1
}

# Every `goal:` of a plan's `## Proposed tasks` that cannot be the MR title it becomes, one reason per line;
# triage and research goals never become titles. decompose.sh refuses on it and plan-lint.sh checks it earlier,
# before plan-check signs the plan hash.
plan_goal_violations() { # <plan-ready.md> [<repo key>]
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^##[ \t]+Proposed tasks[ \t]*$/ { ps = 1; next }
    /^##[ \t]/ { if (ps && have) { print arch "\t" goal; have = 0 } ; ps = 0; next }
    !ps { next }
    /^###[ \t]/ { if (have) print arch "\t" goal; arch = ""; goal = ""; have = 1; next }
    /^-[ \t]*goal:/ { g = $0; sub(/^-[ \t]*goal:[ \t]*/, "", g); goal = trim(g); next }
    /^-[ \t]*archetype:/ { a = $0; sub(/^-[ \t]*archetype:[ \t]*/, "", a); sub(/[ \t,].*$/, "", a); arch = trim(a); next }
    END { if (ps && have) print arch "\t" goal }
  ' "$1" | while IFS="$(printf '\t')" read -r pg_arch pg_goal; do
    [ -n "$pg_goal" ] || continue
    case "$pg_arch" in triage|research) continue ;; esac
    pg_reason=$(mr_title_check "$pg_goal" "${2:-}") \
      || printf 'the `goal:` of a proposal cannot be the MR title it becomes: %s (`%s`)\n' "$pg_reason" "$pg_goal"
  done
}

# Does this clone lint its own MR titles, and at what length? A commitlint config, or a CI file that names
# commitlint or CI_MERGE_REQUEST_TITLE, means the forge judges the title a second time, and the factory's cap
# has to be no larger than that one (MR !412). An explicit `header-max-length` in the commitlint config wins;
# otherwise it is the 100 of @commitlint/config-conventional. Prints `<cap><TAB><the file it found>` and
# returns 0 when the clone lints its titles, nothing and 1 when it does not.
commitlint_cap() { # <clone dir>
  cc_top=$1
  [ -d "$cc_top" ] || return 1
  cc_files=$(git -C "$cc_top" ls-files 2>/dev/null) || return 1
  cc_cfg=$(printf '%s\n' "$cc_files" \
    | grep -E '(^|/)(commitlint\.config\.(js|cjs|mjs|ts|json)|\.commitlintrc(\.(js|cjs|mjs|ts|json|yml|yaml))?)$' | head -n1)
  cc_ci=''
  for cc_f in $(printf '%s\n' "$cc_files" | grep -E '^(\.gitlab-ci\.ya?ml|\.gitlab/.*\.ya?ml|\.github/workflows/.*\.ya?ml)$'); do
    if grep -qE 'CI_MERGE_REQUEST_TITLE|commitlint' "$cc_top/$cc_f" 2>/dev/null; then cc_ci=$cc_f; break; fi
  done
  [ -n "$cc_cfg" ] || [ -n "$cc_ci" ] || return 1
  cc_n=''
  if [ -n "$cc_cfg" ] && [ -f "$cc_top/$cc_cfg" ]; then
    # the rule reads `header-max-length: [2, 'always', 120]`: the number that matters is the last one before
    # the closing bracket, the first is the severity, so "the first number after the key" would read 2 as a cap
    cc_seg=$(tr '\n' ' ' < "$cc_top/$cc_cfg" | sed -n 's/.*header-max-length\([^]]*\).*/\1/p')
    cc_n=$(printf '%s' "$cc_seg" | awk '{ v = ""; for (i = 1; i <= NF; i++) { gsub(/[^0-9]/, "", $i); if ($i != "") v = $i } print v }')
  fi
  case "${cc_n:-}" in ''|*[!0-9]*|0) cc_n=100 ;; esac
  printf '%s\t%s\n' "$cc_n" "${cc_cfg:-$cc_ci}"
}

# A line with the userinfo of every scheme URL cut out (https://user:token@host becomes https://host), the redact of
# factory-doctor.sh: git echoes the URL it was given in its errors, so a token typed into a URL would otherwise reach
# the terminal, a json file or the state repo. An scp-style git@host:path carries no secret and is kept.
redact_urls() { # <text>
  printf '%s\n' "$1" | sed -E 's#([A-Za-z][A-Za-z0-9+.-]*://)[^/@[:space:]]*@#\1#g'
}
